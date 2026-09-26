# MHF local — one-click del servidor (Docker). Solo server, sin cliente.
# Uso: .\Start-Frontier.ps1 [up|logs|status|down|--wipe] [--build]
# Si PowerShell bloquea la ejecución por ExecutionPolicy:
#   powershell -ExecutionPolicy Bypass -File .\Start-Frontier.ps1 up
# Rutas con espacios soportadas (todo se resuelve vía $ScriptDir con Join-Path).
param(
  [string]$Command = "up",
  [string]$Extra = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$EnvFile = Join-Path $ScriptDir ".env"
$ConfigFile = Join-Path $ScriptDir "config.json"
$TemplateFile = Join-Path $ScriptDir "config.template.json"
$QuestsUrl = "https://files.catbox.moe/xf0l7w.7z"

function Fail($msg) { Write-Error "ERROR: $msg"; exit 1 }

function Check-Docker {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail "Docker no encontrado. Instala Docker Desktop, actívalo y vuelve a intentar."
  }
  docker compose version > $null 2>&1
  if ($LASTEXITCODE -ne 0) { Fail "'docker compose' no disponible. Actualiza Docker Desktop." }
  $running = docker info 2>&1
  if ($LASTEXITCODE -ne 0) { Fail "Docker Desktop no está corriendo. Ábrelo y espera a que inicie." }
}

function New-Password {
  $bytes = New-Object byte[] 16
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Ensure-Env {
  if (Test-Path $EnvFile) { return }
  Write-Host "Generando .env con password aleatorio..."
  "POSTGRES_PASSWORD=$(New-Password)" | Out-File -FilePath $EnvFile -Encoding ascii -NoNewline
}

function Get-Password {
  $line = Get-Content $EnvFile | Where-Object { $_ -match "^POSTGRES_PASSWORD=" } | Select-Object -First 1
  if (-not $line) { Fail ".env sin POSTGRES_PASSWORD. Bórralo y re-ejecuta para regenerar." }
  return $line.Split("=", 2)[1]
}

function Ensure-Config {
  if (Test-Path $ConfigFile) { return }
  if (-not (Test-Path $TemplateFile)) { Fail "Falta config.template.json junto al script." }
  Write-Host "Generando config.json desde la plantilla..."
  $pw = Get-Password
  $content = (Get-Content $TemplateFile -Raw).Replace("__POSTGRES_PASSWORD__", $pw)
  # WriteAllText en vez de Out-File -Encoding utf8NoBOM (no existe en Windows PowerShell 5.1).
  [System.IO.File]::WriteAllText($ConfigFile, $content, [System.Text.UTF8Encoding]::new($false))
}

function Ensure-Dirs {
  New-Item -ItemType Directory -Force -Path (Join-Path $ScriptDir "bin"), (Join-Path $ScriptDir "savedata") > $null
}

function Check-Quests {
  $quests = Join-Path $ScriptDir "bin\quests"
  if ((Test-Path $quests) -and (Get-ChildItem $quests -Force | Select-Object -First 1)) { return }
  Write-Host "AVISO: bin/quests está vacío o no existe."
  Write-Host "  Sin estos archivos el server arranca pero las quests no cargan y el cliente puede fallar."
  Write-Host "  Si ya descargaste el archivo de quests (xf0l7w.7z), indícame la ruta y lo descomprimo en bin/."
  Write-Host "  Descarga: $QuestsUrl"
  $archive = ""
  if ([Environment]::UserInteractive) {
    $archive = Read-Host "Ruta al .7z (Enter para omitir)"
  }
  if ([string]::IsNullOrWhiteSpace($archive)) {
    Write-Host "  Destino manual: descomprime el .7z dentro de bin/ (debe quedar bin/quests, bin/scenarios, bin/rengoku_data.bin)."
    return
  }
  $archive = $archive.Trim().Trim('"').Trim("'")
  if (-not (Test-Path $archive)) { Write-Host "  No existe ese archivo: $archive. Continúo sin quests."; return }
  if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
    Write-Host "  Necesito 7-Zip en el PATH para descomprimir (https://www.7-zip.org/). Continúo sin quests."
    return
  }
  Write-Host "Descomprimiendo quests en bin/..."
  $binDir = Join-Path $ScriptDir "bin"
  & 7z x "$archive" -o"$binDir" > $null 2>&1
  $sub = Get-ChildItem $binDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName "quests") } | Select-Object -First 1
  if ($sub) {
    Copy-Item (Join-Path $sub.FullName "*") $binDir -Recurse -Force
    Remove-Item -Recurse -Force $sub.FullName
  }
  if ((Test-Path $quests) -and (Get-ChildItem $quests -Force | Select-Object -First 1)) {
    Write-Host "Quests instaladas en bin/."
  } else {
    Write-Host "  La extracción no dejó bin/quests con contenido. Revisa el .7z o hazlo manual."
  }
}

function Install-ExampleQuests {
  $exDir = Join-Path $ScriptDir "examples\quests"
  if (-not (Test-Path $exDir -PathType Container)) { return }
  $missing = @(Get-ChildItem (Join-Path $exDir "*.json") -ErrorAction SilentlyContinue | Where-Object {
    -not (Test-Path (Join-Path $ScriptDir ("bin\quests\" + $_.Name)))
  })
  if ($missing.Count -eq 0) { return }
  if (-not [Environment]::UserInteractive) { return }
  $ans = Read-Host "¿Instalo las quests de ejemplo en español en bin/quests? (s/N)"
  if ($ans -notmatch '^[sSyY]$') { return }
  $dest = Join-Path $ScriptDir "bin\quests"
  New-Item -ItemType Directory -Force -Path $dest > $null
  foreach ($f in $missing) {
    Copy-Item $f.FullName $dest -Force -ErrorAction SilentlyContinue
  }
  Write-Host "Quests de ejemplo instaladas. Si el server ya estaba corriendo: docker compose restart server."
}

function Wait-Healthy {  for ($i = 0; $i -lt 60; $i++) {
    try {
      Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:8080/health > $null 2>&1
      if ($?) { return $true }
    } catch {}
    Start-Sleep -Seconds 2
  }
  return $false
}

function Print-Ready {
  Write-Host ""
  Write-Host "FRONTIER READY"
  Write-Host "  Entrance: 127.0.0.1:53310 | Sign: 127.0.0.1:53312 | Channels: 54001-54008 | API: http://localhost:8080/health"
  Write-Host "  Cliente: edita tu host.txt hacia 127.0.0.1 y abre mhf.exe por tu cuenta (no incluido)."
}

function Cmd-Up($buildArg) {
  Check-Docker
  Ensure-ErupeSource
  $withBuild = $false
  if ($buildArg -eq "--build") {
    Write-Host "Reconstruyendo imagen local..."
    $withBuild = $true
  } else {
    docker image inspect mhf-erupe:local > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Imagen local no encontrada; construyendo en primera ejecución..."
      $withBuild = $true
    }
  }
  Ensure-Env
  Ensure-Config
  Ensure-Dirs
  Check-Quests
  Install-ExampleQuests
  Write-Host "Levantando servidor MHF..."
  if ($withBuild) { docker compose up -d --build }
  else { docker compose up -d }
  if ($LASTEXITCODE -ne 0) { Fail "'docker compose up' falló. Revisa el mensaje de Docker." }
  Write-Host "Esperando /health..."
  if (Wait-Healthy) { Print-Ready }
  else { Write-Host "AVISO: el server arrancó pero /health no respondió a tiempo. Revisa: docker compose logs server" }
  Setup-Launcher
}

function Setup-Launcher {
  # Preconfigura MHFZ-Launcher (ButterClient/config.json) con este servidor. Opcional.
  if (-not [Environment]::UserInteractive) { return }
  Write-Host ""
  Write-Host "Puedo dejar tu MHFZ-Launcher apuntando a este servidor (endpoints en ButterClient/config.json)."
  $clientDir = Read-Host "Ruta a tu carpeta del juego (Enter para omitir)"
  if ([string]::IsNullOrWhiteSpace($clientDir)) { return }
  $clientDir = $clientDir.Trim().Trim('"').Trim("'")
  if (-not (Test-Path $clientDir -PathType Container)) { Write-Host "  No existe: $clientDir. Launcher no configurado."; return }
  try {
    $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $host_ = if ($cfg.Host) { $cfg.Host } else { "127.0.0.1" }
    $version = if ($cfg.ClientMode) { $cfg.ClientMode } else { "ZZ" }
    $launcherPort = if ($cfg.API -and $cfg.API.Port) { $cfg.API.Port } else { 8080 }
    $gamePort = if ($cfg.Entrance -and $cfg.Entrance.Port) { $cfg.Entrance.Port } else { 53310 }
    $launcherDir = Join-Path $clientDir "ButterClient"
    New-Item -ItemType Directory -Force -Path $launcherDir > $null
    $launcherCfg = Join-Path $launcherDir "config.json"
    $data = @{}
    if (Test-Path $launcherCfg) {
      try { $data = Get-Content $launcherCfg -Raw | ConvertFrom-Json -AsHashtable } catch {
        Write-Host "  El config.json del launcher no es JSON válido; no lo toco."
        return
      }
      $bak = "$launcherCfg.bak"
      if (-not (Test-Path $bak)) { Copy-Item $launcherCfg $bak }
    }
    $endpoints = @()
    if ($data["endpoints"]) { $endpoints = @($data["endpoints"] | Where-Object { $_["name"] -ne "MHF Local" }) }
    $endpoints += @{
      name = "MHF Local"; url = "http://$host_"; launcher_port = $launcherPort
      game_port = $gamePort; version = $version; is_remote = $false
    }
    $data["endpoints"] = $endpoints
    $data | ConvertTo-Json -Depth 10 | Out-File -FilePath $launcherCfg -Encoding utf8
    Write-Host "  Launcher configurado: endpoint 'MHF Local' en ButterClient/config.json."
  } catch {
    Write-Host "  No se pudo escribir la config del launcher."
  }
  Ensure-LauncherApp $clientDir
}

function Ensure-LauncherApp($clientDir) {
  # Descarga opcional del MHFZ-Launcher (mhfz.exe) a la carpeta del juego.
  if (Get-ChildItem (Join-Path $clientDir "mhfz*.exe") -ErrorAction SilentlyContinue | Select-Object -First 1) {
    Write-Host "  Launcher mhfz.exe ya presente en la carpeta del juego."
    return
  }
  $ans = Read-Host "¿Descargo mhfz.exe del último release a la carpeta del juego? (s/N)"
  if ($ans -notmatch '^[sSyY]$') { return }
  try {
    $rel = Invoke-RestMethod -UseBasicParsing -TimeoutSec 20 "https://api.github.com/repos/mrsasy89/MHFZ-Launcher/releases/latest"
    $asset = @($rel.assets | Where-Object { $_.name -match "(?i)windows" } | Select-Object -First 1)
    if (-not $asset) { Write-Host "  No encontré el asset Windows en el último release."; return }
    $tmpzip = Join-Path ([System.IO.Path]::GetTempPath()) "mhfz-launcher.zip"
    Write-Host "  Descargando launcher..."
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -Uri $asset.browser_download_url -OutFile $tmpzip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($tmpzip)
    try {
      $entry = @($zip.Entries | Where-Object { $_.Name -match "(?i)^mhfz.*\.exe$" } | Select-Object -First 1)
      if (-not $entry) { Write-Host "  No se pudo extraer mhfz.exe del zip."; return }
      $target = Join-Path $clientDir ([System.IO.Path]::GetFileName($entry.FullName))
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
      Write-Host "  Launcher descargado en la carpeta del juego (mhfz.exe)."
    } finally {
      $zip.Dispose()
      Remove-Item -Force $tmpzip -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Host "  Falló la descarga del launcher."
  }
}

function Ensure-ErupeSource {
  $src = Join-Path $ScriptDir "..\Erupe"
  $repo = if ($env:ERUPE_REPO) { $env:ERUPE_REPO } else { "https://github.com/Mezeporta/Erupe.git" }
  if ((Test-Path (Join-Path $src "Dockerfile")) -and (Test-Path (Join-Path $src "go.mod"))) { return }
  if (-not [Environment]::UserInteractive) { Fail "Falta el código de Erupe en ..\Erupe. Clónalo manual: git clone $repo" }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "Falta el código de Erupe en ..\Erupe y git no está instalado." }
  $ans = Read-Host "No encontré Erupe junto al instalador. ¿Lo clono de GitHub? (s/N)"
  if ($ans -notmatch '^[sSyY]$') { Fail "Cancelado. Clónalo manual: git clone $repo" }
  Write-Host "Clonando Erupe en $src ..."
  git clone --depth 1 $repo "$src"
  if ($LASTEXITCODE -ne 0) { Fail "Falló el clon. Revisa tu conexión o clónalo manual." }
}

function Cmd-Logs($LogArgs) {
  Check-Docker
  docker compose logs --tail=200 @LogArgs
}

function Cmd-Status {
  Check-Docker
  docker compose ps
  try {
    Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:8080/health > $null 2>&1
    Write-Host "health: OK (http://localhost:8080/health)"
  } catch {
    Write-Host "health: no responde (¿server aún arrancando?)"
  }
}

function Cmd-Down {
  Check-Docker
  docker compose down
  Write-Host "Detenido. Datos preservados en db-data/ y savedata/."
}

function Remove-DataDir($name) {
  $d = Join-Path $ScriptDir $name
  if (-not (Test-Path $d)) { return }
  try {
    Remove-Item -Recurse -Force $d -ErrorAction Stop
    return
  } catch {}
  # Fallback: los bind mounts de postgres pueden quedar con otro dueño.
  Write-Host "$name tiene archivos de otro usuario; reintentando vía Docker..."
  docker run --rm -v "${d}:/wipe" alpine sh -c 'find /wipe -mindepth 1 -delete' > $null 2>&1
  Remove-Item -Force $d -ErrorAction SilentlyContinue
  if (Test-Path $d) { Fail "No se pudo borrar $name." }
}

function Cmd-Wipe {
  Check-Docker
  Write-Host "Esto borra db-data/ y savedata/ (personajes, mundo). .env, config.json y bin/ se conservan."
  if (-not [Environment]::UserInteractive) { Fail "Cancelado (se requiere terminal interactiva para confirmar)." }
  $ans = Read-Host "Escribe SI para confirmar"
  if ($ans -ne "SI") { Fail "Cancelado." }
  docker compose down
  Remove-DataDir "db-data"
  Remove-DataDir "savedata"
  Write-Host "Wipe completo."
}

switch ($Command) {
  "-h" { Write-Host "Uso: .\Start-Frontier.ps1 [up|logs|status|down|--wipe] [--build]"; break }
  "--help" { Write-Host "Uso: .\Start-Frontier.ps1 [up|logs|status|down|--wipe] [--build]"; break }
  "up" { Cmd-Up $Extra; break }
  "logs" { Cmd-Logs @(); break }
  "status" { Cmd-Status; break }
  "down" { Cmd-Down; break }
  "--wipe" { Cmd-Wipe; break }
  default { Fail "Comando desconocido: $Command (usa -h)" }
}
