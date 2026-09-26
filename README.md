# Servidor local MH Frontier — un solo click (Docker)

Levanta un servidor de Monster Hunter Frontier (Erupe) en tu máquina con un solo
comando. Solo necesitas **Docker instalado**; el script construye la imagen,
genera la configuración y arranca todo. El **cliente del juego no está incluido**:
usa tus propios archivos y ábrelo por tu cuenta.

## Requisitos

- Docker + Compose v2 (`docker compose version` debe responder).
- Git (solo si el checkout de `Erupe` no está junto a esta carpeta: el script
  lo clona solo con tu confirmación; `ERUPE_REPO` cambia el origen).
- Puertos libres: `53310`, `53312`, `54001–54008`, `8080`, `5432`.
- Archivos de quests (ver abajo). Sin ellos el server arranca igual, pero el
  cliente falla al pedir quests.

## Uso rápido (Linux)

```bash
cd mhf-docker-oneclick
./start-frontier.sh up
```

La primera vez construye la imagen local desde el checkout de `Erupe` (tarda
unos minutos); las siguientes arranca en segundos. Al terminar verás:

```
FRONTIER READY
  Entrance: 127.0.0.1:53310 | Sign: 127.0.0.1:53312 | ...
```

En Windows el equivalente es `.\Start-Frontier.ps1 up` (requiere Docker Desktop
corriendo; si PowerShell bloquea el script:
`powershell -ExecutionPolicy Bypass -File .\Start-Frontier.ps1 up`).

## Puertos (qué es cada uno)

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

## Comandos

| Comando | Qué hace |
|---|---|
| `up [--build]` | Arranca el servidor (`--build` fuerza reconstrucción) |
| `status` | Muestra contenedores + chequeo de `/health` |
| `logs [args]` | Muestra logs (pasa args a `docker compose logs`) |
| `down` | Detiene el servidor **conservando** personajes y mundo |
| `--wipe` | Borra `db-data/` y `savedata/` (pide escribir `SI`); conserva `.env`, `config.json` y `bin/` |

## Archivos de quests (obligatorio para jugar)

Si `bin/quests` está vacío, el script te pide la ruta del `.7z` y lo
descomprime solo en `bin/` (necesita `7z`/`bsdtar` en Linux o 7-Zip en
Windows; con Enter lo omites y te dice cómo hacerlo manual).

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

### MHFZ-Launcher (opcional)

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

## Qué genera el script (no lo edites a mano la primera vez)

- `.env` — password de postgres, generado una vez y reutilizado.
- `config.json` — derivado de `config.template.json` (`Database.Host=db`,
  `ClientMode=ZZ`).
- `bin/`, `savedata/`, `db-data/` — datos y volúmenes persistentes.

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

⚠️ No toques `Database.*` (lo gestiona el script) salvo que sepas lo que haces;
si rompes el `config.json`, bórralo y el próximo `up` lo regenera (se pierde
tu tuning, guarda backup).

## Solución de problemas

- **`/health` no responde**: `docker compose logs server` (las migraciones de
  la DB corren solas al arrancar).
- **`db unhealthy` en el primer `up` (disco lento)**: en discos mecánicos el
  `initdb` de postgres puede tardar minutos y el compose se rinde antes.
  Espera y re-ejecuta `./start-frontier.sh up` (es idempotente, no reconstruye
  nada) hasta ver `FRONTIER READY`.
- **No conecta el cliente**: revisa `host.txt`, firewall en los puertos de
  arriba y que el `ClientMode` coincida con tu cliente.
- **`--wipe` pedía permisos**: el script lo reintenta vía Docker; si aún falla,
  `sudo rm -rf db-data savedata`.
- **Imagen prebuilt de GHCR**: queda como alternativa en `docker-compose.yml`;
  su pull anónimo hoy es rechazado (401), por eso el default es build local.
- **pgAdmin** (opcional): `docker compose --profile tools up` → `http://localhost:5050`.

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
