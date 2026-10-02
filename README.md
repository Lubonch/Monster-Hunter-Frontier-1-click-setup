# Monster Hunter Frontier — Servidor local en un click

Levanta un servidor privado de **Monster Hunter Frontier** ([Erupe](https://github.com/Mezeporta/Erupe))
en tu máquina con un solo comando. El script construye la imagen, genera la
configuración y arranca todo (Postgres + Erupe). El **cliente del juego no está
incluido**: usa tus propios archivos.

- [Requisitos](#requisitos) · [Uso rápido](#uso-rápido) · [Comandos](#comandos)
- [Puertos](#puertos) · [Jugar en LAN](#jugar-en-lan)
- [Quests](#archivos-de-quests) · [Quests custom](#crear-quests-custom)
- [MHFZ-Launcher](#mhfz-launcher) · [Configuración](#configuración-del-server)
- [Solución de problemas](#solución-de-problemas)

## Requisitos

- **Docker + Compose v2** (`docker compose version` debe responder). Opciones:
  | Opción | Notas |
  |---|---|
  | **Docker Desktop** (recomendado) | Cero fricción en Windows/Mac; en Windows requiere WSL2 |
  | **Docker Engine en WSL2** (liviano) | `docker-ce` instalado en tu distro Linux/WSL, sin GUI ni telemetría; 100% compatible |
  | **Rancher Desktop** | Reemplazo gratis y open-source de Desktop, con `compose` compatible |
  | ⚠️ Podman | No recomendado: su compatibilidad con `compose` es parcial |
- **Git** (solo si el código de `Erupe` no está junto a esta carpeta: el script
  lo clona solo con tu confirmación; `ERUPE_REPO` cambia el origen).
- Puertos libres: `53310`, `53312`, `54001–54008`, `8080`, `5432`.
- Archivos de quests ([ver abajo](#archivos-de-quests)). Sin ellos el server
  arranca igual, pero el cliente falla al pedir quests.

## Preparar Docker (una sola vez)

### Linux

```bash
# Docker Engine oficial (Debian/Ubuntu; ajusta a tu distro)
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
# Cierra sesión y vuelve a entrar para que el grupo aplique
```

Alternativa sin sudo por comando: la de arriba (grupo `docker`) ya lo evita.

### Windows — opción A: Docker Desktop (recomendado)

1. Instala [Docker Desktop](https://www.docker.com/products/docker-desktop/).
2. Activa el backend WSL2 (viene por defecto) e instala una distro Ubuntu
   desde Microsoft Store si no tienes.
3. Abre Docker Desktop y espera a que diga *running*.

### Windows — opción B: solo WSL2, sin Desktop (liviano)

```bash
# Dentro de tu distro WSL2 (Ubuntu)
sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo service docker start
```

Sin GUI ni telemetría; el script funciona igual.

### Windows — opción C: Rancher Desktop

Instala [Rancher Desktop](https://rancherdesktop.io/) (gratis y open-source),
elige el runtime `dockerd (moby)` y listo.

### Verificar (cualquier OS)

```bash
docker --version
docker compose version
docker info  # debe responder sin errores (en Windows: Desktop corriendo)
```

## Uso rápido

```bash
./start-frontier.sh up     # Linux
.\Start-Frontier.ps1 up    # Windows (Docker Desktop corriendo)
```

La primera vez construye la imagen local desde el código de `Erupe` (tarda
unos minutos); las siguientes arranca en segundos. Al terminar verás:

```
FRONTIER READY
  Entrance: 127.0.0.1:53310 | Sign: 127.0.0.1:53312 | ...
```

> Windows: si PowerShell bloquea el script:
> `powershell -ExecutionPolicy Bypass -File .\Start-Frontier.ps1 up`.

## Comandos

| Comando | Qué hace |
|---|---|
| `up [--build]` | Arranca el servidor (`--build` fuerza reconstrucción) |
| `status` | Muestra contenedores + chequeo de `/health` |
| `logs [args]` | Muestra logs (pasa args a `docker compose logs`) |
| `down` | Detiene el servidor **conservando** personajes y mundo |
| `--wipe` | Borra `db-data/` y `savedata/` (pide escribir `SI`); conserva `.env`, `config.json` y `bin/` |

## Puertos

| Puerto | Servicio | Quién lo usa |
|---|---|---|
| `8080` | API HTTP (`/health`, `/launcher`, `/login`, `/register`) | MHFZ-Launcher como **launcher port** |
| `53310` | Entrance (lista de mundos) | MHFZ-Launcher como **game port** |
| `53312` | Sign (autenticación del juego) | `mhf.exe` directo |
| `54001–54008` | Channels (partidas) | Negociados solos, no se configuran |
| `5432` | Postgres | Solo interno del compose |

## Jugar en LAN (otra PC / consola en tu red)

1. En `config.json` cambia `"Host"` de `127.0.0.1` a la IP LAN de tu PC
   (ej. `192.168.1.50`).
2. Abre el firewall en `53310`, `53312`, `54001+` y `8080`.
3. Reinicia: `docker compose restart server` (o `down` + `up`).
4. En el cliente/launcher usa esa IP en vez de `127.0.0.1`.

## Archivos de quests

Sin estos archivos el server arranca pero las quests no cargan. Si `bin/quests`
está vacío, el script te pide la ruta del `.7z` y lo descomprime solo en `bin/`
(necesita `7z`/`bsdtar` en Linux o 7-Zip en Windows; con Enter lo omites).

Manual:

1. Descarga: `https://files.catbox.moe/xf0l7w.7z`
2. Descomprime el `.7z` dentro de `bin/` (debe quedar `bin/quests`,
   `bin/scenarios` y `bin/rengoku_data.bin`).

## Conectar el cliente

1. Edita el `host.txt` de tu cliente MHF para que apunte a la IP del servidor
   (`127.0.0.1` si juegas en la misma máquina).
2. Abre `mhf.exe`, elige el servidor y entra. La cuenta se crea sola
   (`AutoCreateAccount: true`).
3. El `ClientMode` por defecto es `ZZ` (cámbialo en `config.json` si tu cliente
   es otra versión, p. ej. `G10`).

### MHFZ-Launcher

Al final del `up`, el script puede dejar tu
[MHFZ-Launcher](https://github.com/mrsasy89/MHFZ-Launcher) apuntando al
servidor: te pide la carpeta del juego y escribe el endpoint `MHF Local`
(`url` + `launcher_port` + `game_port` + `version` tomados de tu `config.json`)
en `ButterClient/config.json`, con backup en `config.json.bak` y sin borrar
tus otros endpoints. Si no tienes el launcher, el script ofrece descargarlo
(`mhfz.AppImage` en Linux / `mhfz.exe` en Windows) del último release a tu
carpeta del juego. Para tu primer registro usa la opción de registro del
launcher o:

```bash
curl -X POST http://localhost:8080/register \
  -H 'Content-Type: application/json' \
  -d '{"username":"tu_usuario","password":"tu_clave"}'
```

(el `/login` HTTP no auto-crea cuentas; el registro sí).

## Qué genera el script

- `.env` — password de postgres, generado una vez y reutilizado.
- `config.json` — derivado de `config.template.json` (`Database.Host=db`,
  `ClientMode=ZZ`).
- `bin/`, `savedata/`, `db-data/` — datos y volúmenes persistentes (no se
  versionan, ver `.gitignore`).

## Configuración del server

Nuestro `config.json` es mínimo (todo lo demás usa defaults del server).
Para tunearlo, agrega claves de `Erupe/config.reference.json` y reinicia:

```bash
docker compose restart server
```

Lo más útil:

| Área | Claves | Ejemplo |
|---|---|---|
| Rates (caza, puntos, zenny, materiales) | `GameplayOptions.HRPMultiplier`, `SRPMultiplier`, `GRPMultiplier`, `GSRPMultiplier`, `ZennyMultiplier`, `MaterialMultiplier`, `ExtraCarves`, `GCPMultiplier` (+ variantes `...NC` para sin curso) | `"HRPMultiplier": 2.0` = doble HRP |
| Zenny/materiales G-rank | `GZennyMultiplier`, `GMaterialMultiplier`, `GExtraCarves` | — |
| Eventos | `GameplayOptions.EnableKaijiEvent`, `EnableHiganjimaEvent`, `EnableNierEvent`, `MezFesSoloTickets`, `MezFesGroupTickets` | `"EnableNierEvent": true` |
| Forzar eventos (debug) | `DebugOptions.DivaOverride`, `FestaOverride` (`-1` auto, `1` activo), `SeasonOverride` | `"DivaOverride": 1` |
| Aviso al entrar | `HideLoginNotice`, `LoginNotices` (HTML con `<BR>`, `<PAGE>` separa páginas) | `"HideLoginNotice": false` |
| Comandos in-game | `CommandPrefix` (default `!`), lista `Commands` (`Enabled`/`Prefix`: `tele`, `kqf`, `ban`, `timer`, `course`, `lang`, ...) | `"Prefix": "tele"` + `"Enabled": true` |
| Cursos | `Courses` (`HunterLife`, `Premium`, `NetCafe`, ...), `DefaultCourses` | — |
| Idioma default | `Language` (`en`, `jp`, `fr`, `zh`; cada jugador cambia el suyo con `!lang <code>`) | — |
| Caché de quests | `QuestCacheExpiry` (segundos, default 300) | `"QuestCacheExpiry": 60` |
| Discord | `Discord.Enabled`, `BotToken`, `RelayChannel` | relay chat juego↔Discord |
| Canales | `Entrance.Entries[].Channels[]` (`Port`, `MaxPlayers`, `Enabled`) | bajar `MaxPlayers` o apagar un mundo |

Ejemplo (doble rates + aviso custom):

```json
{
  "Host": "127.0.0.1",
  "Database": { "Host": "db", "Port": 5432, "User": "postgres", "Password": "<la de tu .env>", "Database": "erupe" },
  "ClientMode": "ZZ",
  "AutoCreateAccount": true,
  "API": { "Banners": [], "Messages": [], "Links": [] },
  "GameplayOptions": { "HRPMultiplier": 2.0, "ZennyMultiplier": 2.0 },
  "LoginNotices": ["<BODY><CENTER>Bienvenido a mi server!<BR><BODY>Rates x2 este finde."]
}
```

⚠️ No toques `Database.*` (lo gestiona el script). Si rompes el `config.json`,
bórralo y el próximo `up` lo regenera (se pierde tu tuning, guarda backup).

## Crear quests custom

No necesitas herramientas binarias: Erupe compila quests desde JSON legible.
Guarda tu quest como `bin/quests/<nombre>.json` (el server prueba `.bin`
primero y cae a `.json` si no existe).

**Para probar ya mismo:** el `up` ofrece instalar 2 quests en español
(`ejemplo-caza.json`, `ejemplo-entrega.json`, IDs 9001/9002, en
`examples/quests/`) directo en `bin/quests/`. Manualmente también vale:

```bash
cp examples/quests/*.json bin/quests/
docker compose restart server
```

(Ojo: si algún `quest_id` choca con una quest oficial, cambia el número.)

Ejemplo mínimo funcional:

```json
{
  "quest_id": 1,
  "title": "Caza el Rathalos",
  "description": "Una cacería de prueba.",
  "text_main": "Hunt the Rathalos.",
  "text_sub_a": "",
  "text_sub_b": "",
  "success_cond": "Slay the Rathalos.",
  "fail_cond": "Time runs out or all hunters faint.",
  "contractor": "Guild Master",
  "monster_size_multi": 100,
  "stat_table_1": 0,
  "main_rank_points": 120,
  "sub_a_rank_points": 60,
  "sub_b_rank_points": 0,
  "fee": 500,
  "reward_main": 5000,
  "reward_sub_a": 1000,
  "reward_sub_b": 0,
  "time_limit_minutes": 50,
  "map": 2,
  "rank_band": 0,
  "objective_main": {"type": "hunt", "target": 11, "count": 1},
  "objective_sub_a": {"type": "deliver", "target": 149, "count": 3},
  "objective_sub_b": {"type": "none"},
  "large_monsters": [
    {"id": 11, "spawn_amount": 1, "spawn_stage": 5, "orientation": 180, "x": 1500.0, "y": 0.0, "z": -2000.0}
  ],
  "rewards": [
    {"table_id": 1, "items": [
      {"rate": 50, "item": 149, "quantity": 1},
      {"rate": 30, "item": 153, "quantity": 1}
    ]}
  ],
  "supply_main": [
    {"item": 1, "quantity": 5}
  ],
  "stages": [
    {"stage_id": 2}
  ]
}
```

Notas:

- **Objetivos válidos** (`type`): `none`, `hunt`, `capture`, `slay`, `deliver`,
  `deliver_flag`, `break_part`, `damage`, `slay_or_damage`, `slay_total`,
  `slay_all`, `esoteric`.
- **`target`/`item`/`id`** son IDs del juego (monstruo, objeto). Usa la DB de
  objetos [Ferias](https://xl3lackout.github.io/MHFZ-Ferias-English-Project/)
  para buscarlos.
- **Textos multi-idioma**: cualquier campo de texto acepta string simple o mapa
  `{"en": "...", "jp": "...", "fr": "...", "zh": "..."}`.
- **Caché**: `QuestCacheExpiry` son 300s — tras editar, espera 5 min o reinicia
  el server (`docker compose restart server`).
- **Scenarios**: mismo mecanismo en `bin/scenarios/<nombre>.json`, formato en
  `Erupe/docs/scenario-format.md`. El formato completo de quests está en la
  [wiki de Erupe](https://github.com/Mezeporta/Erupe/wiki).

## Solución de problemas

- **`/health` no responde**: `docker compose logs server` (las migraciones de
  la DB corren solas al arrancar).
- **`db unhealthy` en el primer `up` (disco lento)**: en discos mecánicos el
  `initdb` de postgres puede tardar minutos y el compose se rinde antes.
  Espera y re-ejecuta el `up` (es idempotente, no reconstruye nada) hasta ver
  `FRONTIER READY`.
- **No conecta el cliente**: revisa `host.txt`, firewall en los puertos de
  arriba y que el `ClientMode` coincida con tu cliente.
- **`--wipe` pedía permisos**: el script lo reintenta vía Docker; si aún falla,
  `sudo rm -rf db-data savedata`.
- **Imagen prebuilt de GHCR**: queda como alternativa en `docker-compose.yml`;
  su pull anónimo hoy es rechazado (401), por eso el default es build local.
- **pgAdmin** (opcional): `docker compose --profile tools up` → `http://localhost:5050`.
- **Personaje corrupto tras error `2597` (nombre basura + todas las quests fallan igual)**:
  el `2597` es un error del cliente ante un savedata inválido, no del server.
  Suele venir de un blob corrupto que el server persistió con hash nuevo,
  contaminando también los backups rotativos. No uses `--wipe` (borra todo).
  Diagnóstico (solo lectura):
  ```bash
  docker compose logs server | grep "Correcting name mismatch in savedata"
  docker compose exec db psql -U postgres -d erupe -c "SELECT id, name, length(savedata), last_login FROM characters WHERE id = <char_id>;"
  docker compose exec db psql -U postgres -d erupe -c "SELECT slot, length(savedata), saved_at FROM savedata_backups WHERE char_id = <char_id> ORDER BY saved_at;"
  ```
  Si algún slot viejo tiene nombre sano, restaura **clon-primero**: backup con
  `pg_dump`, `UPDATE` del slot sano + hash en el clon, verifica login y quests,
  y recién entonces repite en prod. Desde el fix de quarantine el server
  rechaza estos blobs (`Quarantined incoming savedata blob` en logs) sin pisar
  el primary; el slot 0 de backups está reservado y nunca se auto-sobrescribe.

## Stack y créditos

- Servidor: [Erupe](https://github.com/Mezeporta/Erupe) (emulador open-source de
  MHF, Go + Postgres).
- Launcher opcional: [MHFZ-Launcher](https://github.com/mrsasy89/MHFZ-Launcher).
- Este repo no incluye el cliente del juego ni assets de CAPCOM.
