#!/usr/bin/env bash
# MHF local — one-click del servidor (Docker). Solo server, sin cliente.
# Uso: ./start-frontier.sh [up|logs|status|down|--wipe] [--build]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE=(docker compose)
ENV_FILE="$SCRIPT_DIR/.env"
CONFIG_FILE="$SCRIPT_DIR/config.json"
TEMPLATE_FILE="$SCRIPT_DIR/config.template.json"
QUESTS_URL="https://files.catbox.moe/xf0l7w.7z"

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "$*"; }

check_docker() {
  command -v docker >/dev/null 2>&1 || die "Docker no encontrado. Instala Docker y vuelve a intentar."
  docker compose version >/dev/null 2>&1 || die "'docker compose' no disponible. Actualiza Docker a una versión con Compose v2."
}

gen_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    tr -dc 'a-f0-9' < /dev/urandom | head -c 32
  fi
}

ensure_env() {
  if [ -f "$ENV_FILE" ]; then
    return 0
  fi
  info "Generando .env con password aleatorio..."
  printf 'POSTGRES_PASSWORD=%s\n' "$(gen_password)" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

load_password() {
  # shellcheck disable=SC1091
  set -a; . "$ENV_FILE"; set +a
  [ -n "${POSTGRES_PASSWORD:-}" ] || die ".env sin POSTGRES_PASSWORD. Bórralo y re-ejecuta para regenerar."
}

ensure_config() {
  if [ -f "$CONFIG_FILE" ]; then
    return 0
  fi
  [ -f "$TEMPLATE_FILE" ] || die "Falta config.template.json junto al script."
  info "Generando config.json desde la plantilla..."
  load_password
  sed "s/__POSTGRES_PASSWORD__/${POSTGRES_PASSWORD}/" "$TEMPLATE_FILE" > "$CONFIG_FILE"
}

ensure_dirs() {
  mkdir -p "$SCRIPT_DIR/bin" "$SCRIPT_DIR/savedata"
}

extract_archive() {
  local archive="$1" dest="$2"
  if command -v 7z >/dev/null 2>&1; then
    7z x "$archive" -o"$dest" >/dev/null
  elif command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$archive" -C "$dest"
  else
    return 1
  fi
}

install_example_quests() {
  local exdir="$SCRIPT_DIR/examples/quests"
  [ -d "$exdir" ] || return 0
  local missing=0 f
  for f in "$exdir"/*.json; do
    [ -e "$f" ] || continue
    [ -f "$SCRIPT_DIR/bin/quests/$(basename "$f")" ] || missing=1
  done
  [ "$missing" -eq 1 ] || return 0
  [ -t 0 ] || return 0
  local ans=""
  printf '¿Instalo las quests de ejemplo en español en bin/quests? (s/N): '
  read -r ans || return 0
  case "$ans" in
    [sSyY]*) ;;
    *) return 0 ;;
  esac
  mkdir -p "$SCRIPT_DIR/bin/quests"
  cp -n "$exdir"/*.json "$SCRIPT_DIR/bin/quests"/
  info "Quests de ejemplo instaladas. Si el server ya estaba corriendo: docker compose restart server."
}

normalize_bin() {
  # Si el .7z traía una carpeta contenedora (bin/<algo>/quests), sube su contenido a bin/.
  if [ ! -d "$SCRIPT_DIR/bin/quests" ]; then
    local sub
    for sub in "$SCRIPT_DIR"/bin/*/; do
      if [ -d "${sub}quests" ]; then
        cp -rn "${sub}". "$SCRIPT_DIR/bin/"
        rm -rf "$sub"
        break
      fi
    done
  fi
}

check_quests() {
  if [ -d "$SCRIPT_DIR/bin/quests" ] && [ -n "$(ls -A "$SCRIPT_DIR/bin/quests" 2>/dev/null)" ]; then
    return 0
  fi
  echo "AVISO: bin/quests está vacío o no existe."
  echo "  Sin estos archivos el server arranca pero las quests no cargan y el cliente puede fallar."
  echo "  Si ya descargaste el archivo de quests (xf0l7w.7z), indícame la ruta y lo descomprimo en bin/."
  echo "  Descarga: $QUESTS_URL"
  local archive=""
  if [ -t 0 ]; then
    printf 'Ruta al .7z (Enter para omitir): '
    read -r archive || archive=""
  fi
  if [ -z "$archive" ]; then
    echo "  Destino manual: descomprime el .7z dentro de bin/ (debe quedar bin/quests, bin/scenarios, bin/rengoku_data.bin)."
    return 0
  fi
  # Limpia comillas y expande ~ (el read no lo hace solo)
  archive="${archive%\"}"; archive="${archive#\"}"
  archive="${archive%\'}"; archive="${archive#\'}"
  archive="${archive/#\~/$HOME}"
  [ -f "$archive" ] || { echo "  No existe ese archivo: $archive. Continúo sin quests."; return 0; }
  if ! command -v 7z >/dev/null 2>&1 && ! command -v bsdtar >/dev/null 2>&1; then
    echo "  Necesito '7z' o 'bsdtar' para descomprimir (p. ej. instala p7zip). Continúo sin quests."
    return 0
  fi
  info "Descomprimiendo quests en bin/..."
  if extract_archive "$archive" "$SCRIPT_DIR/bin" && normalize_bin && \
     [ -d "$SCRIPT_DIR/bin/quests" ] && [ -n "$(ls -A "$SCRIPT_DIR/bin/quests" 2>/dev/null)" ]; then
    info "Quests instaladas en bin/."
  else
    echo "  La extracción no dejó bin/quests con contenido. Revisa el .7z o hazlo manual."
  fi
}

wait_healthy() {
  local i
  for i in $(seq 1 60); do
    if curl -fsS -m 3 http://localhost:8080/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

print_ready() {
  echo ""
  echo "FRONTIER READY"
  echo "  Entrance: 127.0.0.1:53310 | Sign: 127.0.0.1:53312 | Channels: 54001-54008 | API: http://localhost:8080/health"
  echo "  Cliente: edita tu host.txt hacia 127.0.0.1 y abre mhf.exe por tu cuenta (no incluido)."
}

setup_launcher() {
  # Preconfigura MHFZ-Launcher (ButterClient/config.json) con este servidor. Opcional.
  [ -t 0 ] || return 0
  echo ""
  echo "Puedo dejar tu MHFZ-Launcher apuntando a este servidor (endpoints en ButterClient/config.json)."
  local clientdir=""
  printf 'Ruta a tu carpeta del juego (Enter para omitir): '
  read -r clientdir || return 0
  [ -z "$clientdir" ] && return 0
  clientdir="${clientdir%\"}"; clientdir="${clientdir#\"}"
  clientdir="${clientdir%\'}"; clientdir="${clientdir#\'}"
  clientdir="${clientdir/#\~/$HOME}"
  [ -d "$clientdir" ] || { echo "  No existe: $clientdir. Launcher no configurado."; return 0; }
  write_launcher_endpoint "$clientdir"
  ensure_launcher_app "$clientdir"
}

write_launcher_endpoint() {
  local clientdir="$1"
  command -v python3 >/dev/null 2>&1 || { echo "  Necesito python3 para escribir la config del launcher."; return 0; }
  if python3 - "$CONFIG_FILE" "$clientdir" <<'PYEOF'
import json, os, shutil, sys
server_cfg_path, client_dir = sys.argv[1], sys.argv[2]
with open(server_cfg_path, encoding="utf-8") as f:
    cfg = json.load(f)
host = cfg.get("Host") or "127.0.0.1"
version = cfg.get("ClientMode", "ZZ")
launcher_port = (cfg.get("API") or {}).get("Port", 8080)
game_port = (cfg.get("Entrance") or {}).get("Port", 53310)
endpoint = {
    "name": "MHF Local",
    "url": f"http://{host}",
    "launcher_port": launcher_port,
    "game_port": game_port,
    "version": version,
    "is_remote": False,
}
launcher_dir = os.path.join(client_dir, "ButterClient")
os.makedirs(launcher_dir, exist_ok=True)
launcher_cfg = os.path.join(launcher_dir, "config.json")
data = {}
if os.path.isfile(launcher_cfg):
    with open(launcher_cfg, encoding="utf-8") as f:
        try:
            data = json.load(f) or {}
        except json.JSONDecodeError:
            print("  El config.json del launcher no es JSON válido; no lo toco.")
            sys.exit(2)
    bak = launcher_cfg + ".bak"
    if not os.path.isfile(bak):
        shutil.copy2(launcher_cfg, bak)
endpoints = [e for e in data.get("endpoints", []) if e.get("name") != "MHF Local"]
endpoints.append(endpoint)
data["endpoints"] = endpoints
with open(launcher_cfg, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("  Launcher configurado: endpoint 'MHF Local' en ButterClient/config.json.")
PYEOF
  then
    return 0
  else
    [ $? -eq 2 ] || echo "  No se pudo escribir la config del launcher."
    return 0
  fi
}

ensure_launcher_app() {
  # Descarga opcional del MHFZ-Launcher (AppImage) a la carpeta del juego.
  local clientdir="$1"
  if ls "$clientdir"/*.AppImage >/dev/null 2>&1; then
    info "Launcher AppImage ya presente en la carpeta del juego."
    return 0
  fi
  command -v curl >/dev/null 2>&1 || { echo "  Necesito curl para descargar el launcher."; return 0; }
  command -v python3 >/dev/null 2>&1 || { echo "  Necesito python3 para descargar el launcher."; return 0; }
  local ans=""
  printf '¿Descargo mhfz.AppImage del último release a la carpeta del juego? (s/N): '
  read -r ans || return 0
  case "$ans" in
    [sSyY]*) ;;
    *) return 0 ;;
  esac
  local api="https://api.github.com/repos/mrsasy89/MHFZ-Launcher/releases/latest"
  local url=""
  url="$(curl -fsSL -m 20 "$api" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(next((a['browser_download_url'] for a in d.get('assets',[]) if 'linux' in a.get('name','').lower()), ''))")"
  if [ -z "$url" ]; then
    echo "  No encontré el asset Linux en el último release. Descárgalo manual: https://github.com/mrsasy89/MHFZ-Launcher/releases"
    return 0
  fi
  local tmpzip
  tmpzip="$(mktemp /tmp/mhfz-launcher-XXXXXX.zip)"
  info "Descargando launcher..."
  if ! curl -fsSL -m 180 -o "$tmpzip" "$url"; then
    echo "  Falló la descarga del launcher."
    rm -f "$tmpzip"
    return 0
  fi
  if python3 - "$tmpzip" "$clientdir" <<'PYEOF'
import sys, zipfile
zpath, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zpath) as zf:
    names = [n for n in zf.namelist() if n.lower().endswith(".appimage")]
    if not names:
        sys.exit(3)
    for n in names:
        target = dest.rstrip("/") + "/" + n.rsplit("/", 1)[-1]
        with zf.open(n) as src, open(target, "wb") as out:
            out.write(src.read())
PYEOF
  then
    chmod +x "$clientdir"/*.AppImage
    rm -f "$tmpzip"
    info "Launcher descargado en la carpeta del juego (mhfz.AppImage)."
  else
    echo "  No se pudo extraer el AppImage del zip."
    rm -f "$tmpzip"
  fi
  return 0
}

ERUPE_REPO="${ERUPE_REPO:-https://github.com/Mezeporta/Erupe.git}"

ensure_erupe_source() {
  local src="$SCRIPT_DIR/../Erupe"
  if [ -f "$src/Dockerfile" ] && [ -f "$src/go.mod" ]; then
    return 0
  fi
  [ -t 0 ] && command -v git >/dev/null 2>&1 || die "Falta el código de Erupe en ../Erupe. Clónalo manual: git clone $ERUPE_REPO $src (o instala git para que lo haga solo)."
  local ans=""
  printf 'No encontré Erupe junto al instalador. ¿Lo clono de GitHub? (s/N): '
  read -r ans || die "Cancelado. Clónalo manual: git clone $ERUPE_REPO $src"
  case "$ans" in
    [sSyY]*) ;;
    *) die "Cancelado. Clónalo manual: git clone $ERUPE_REPO $src" ;;
  esac
  command -v git >/dev/null 2>&1 || die "Necesito git para clonar Erupe."
  info "Clonando Erupe en $src ..."
  git clone --depth 1 "$ERUPE_REPO" "$src" || die "Falló el clon. Revisa tu conexión o clónalo manual."
}

cmd_up() {
  local build_flag=()
  check_docker
  ensure_erupe_source
  if [ "${1:-}" = "--build" ]; then
    info "Reconstruyendo imagen local..."
    build_flag=(--build)
  elif ! docker image inspect mhf-erupe:local >/dev/null 2>&1; then
    info "Imagen local no encontrada; construyendo en primera ejecución..."
    build_flag=(--build)
  fi
  ensure_env
  load_password
  ensure_config
  ensure_dirs
  check_quests
  install_example_quests
  info "Levantando servidor MHF..."
  "${COMPOSE[@]}" up -d "${build_flag[@]}"
  if command -v curl >/dev/null 2>&1; then
    info "Esperando /health..."
    if wait_healthy; then
      print_ready
    else
      echo "AVISO: el server arrancó pero /health no respondió a tiempo. Revisa: docker compose logs server" >&2
    fi
  else
    print_ready
  fi
  setup_launcher
}

cmd_logs() {
  check_docker
  "${COMPOSE[@]}" logs --tail=200 "$@"
}

cmd_status() {
  check_docker
  "${COMPOSE[@]}" ps
  if curl -fsS -m 3 http://localhost:8080/health >/dev/null 2>&1; then
    echo "health: OK (http://localhost:8080/health)"
  else
    echo "health: no responde (¿server aún arrancando?)"
  fi
}

cmd_down() {
  check_docker
  "${COMPOSE[@]}" down
  info "Detenido. Datos preservados en db-data/ y savedata/."
}

wipe_dir() {
  local d="$SCRIPT_DIR/$1"
  [ -e "$d" ] || return 0
  if rm -rf "$d" 2>/dev/null; then
    return 0
  fi
  # Los bind mounts de postgres quedan con otro dueño; se borran como root vía container.
  info "$1 tiene archivos de otro usuario; reintentando vía Docker..."
  docker run --rm -v "$d:/wipe" alpine sh -c 'find /wipe -mindepth 1 -delete' >/dev/null 2>&1 \
    && rmdir "$d" 2>/dev/null \
    || die "No se pudo borrar $1. Prueba manual: sudo rm -rf $1"
}

cmd_wipe() {
  check_docker
  echo "Esto borra db-data/ y savedata/ (personajes, mundo). .env, config.json y bin/ se conservan."
  printf 'Escribe SI para confirmar: '
  read -r ans
  [ "$ans" = "SI" ] || die "Cancelado."
  "${COMPOSE[@]}" down
  wipe_dir db-data
  wipe_dir savedata
  info "Wipe completo."
}

if [ "${1:-up}" = "-h" ] || [ "${1:-up}" = "--help" ]; then
  echo "Uso: ./start-frontier.sh [up|logs|status|down|--wipe] [--build]"
  echo "  up (default)  levanta el servidor (construye la imagen si falta; --build fuerza reconstrucción)"
  echo "  logs [args]   muestra logs (pasa args a 'docker compose logs')"
  echo "  status        compose ps + chequeo /health"
  echo "  down          detiene preservando datos"
  echo "  --wipe        borra db-data/ y savedata/ con confirmación"
  exit 0
fi

CMD="${1:-up}"
case "$CMD" in
  up) cmd_up "${2:-}" ;;
  logs) shift; cmd_logs "$@" ;;
  status) cmd_status ;;
  down) cmd_down ;;
  --wipe) cmd_wipe ;;
  *) die "Comando desconocido: $CMD (usa -h)" ;;
esac
