## denodo-oneclick install script (Windows / PowerShell)
##
## Windows-native port of install.sh, same behavior and same Docker
## artifacts (docker/Dockerfile, docker/entrypoint.sh) - only the
## orchestration shell differs. Docker Desktop's Linux container backend
## builds/runs the exact same image either way.
##
## Usage (from a checked-out repo):
##   .\install.ps1 -DENODO_SUPPORT_CI <id> -DENODO_SUPPORT_SECRET <secret> -DENODO_LIC <path-to-license>
##
## Usage (no local checkout - download then run, PowerShell's equivalent of
## `curl | bash`; run as two steps rather than piped into iex so you can see
## what you're about to execute):
##   iwr -useb https://raw.githubusercontent.com/vfagesgo/denodo-oneclick/main/install.ps1 -OutFile install.ps1
##   .\install.ps1 -DENODO_SUPPORT_CI <id> -DENODO_SUPPORT_SECRET <secret> -DENODO_LIC <path-to-license>

[CmdletBinding()]
param(
  [string]$DENODO_SUPPORT_CI,
  [string]$DENODO_SUPPORT_SECRET,
  [string]$DENODO_LIC,
  [string]$DENODO_UPDATE,
  [string]$DENODO_PG_USER,
  [string]$DENODO_PG_PWD,
  [string]$DENODO_VDP_PWD,
  [string]$CLOUDFLARE_TUNNEL_KEY,
  [string]$OPENAI_API_KEY,
  [string]$Mode = "docker",
  [switch]$Reset,
  [switch]$Refresh,
  [switch]$Upgrade,
  [switch]$Help
)

$ErrorActionPreference = "Stop"
# PowerShell 7.3+ otherwise treats stderr output from native commands (docker
# included) as a terminating error under $ErrorActionPreference = "Stop" -
# even when redirected with `*> $null` - which is what turned the expected
# "no such object" from the exit-code probes below into a hard failure
# instead of just setting $LASTEXITCODE. Restore the classic behavior so
# those probes work the same way the bash version's `|| true` does.
$PSNativeCommandUseErrorActionPreference = $false

function Show-Usage {
  @"
Usage: install.ps1 -DENODO_SUPPORT_CI <id> -DENODO_SUPPORT_SECRET <secret> -DENODO_LIC <path-to-license> [options]

Mandatory:
  -DENODO_SUPPORT_CI <value>
  -DENODO_SUPPORT_SECRET <value>
  -DENODO_LIC <path>            Path to the Denodo license file

Overrides (default comes from denodo_config.env):
  -DENODO_UPDATE <value>
  -DENODO_PG_USER <value>
  -DENODO_PG_PWD <value>
  -DENODO_VDP_PWD <value>

Optional:
  -CLOUDFLARE_TUNNEL_KEY <value>
  -OPENAI_API_KEY <value>        Used to pre-fill the AI SDK/chatbot config
                                  (sdk_config.env, chatbot_config.env); can
                                  also be added/changed later via -Upgrade
  -Mode <docker|local>           Default: docker (local not implemented yet)
  -Reset                         Wipe any existing container + its volume first,
                                  so the install starts truly from scratch
  -Help                          Show this message

Actions on an existing container (instead of building/running one):
  -Refresh                       Pull the latest denodo-oneclick repo into the
                                  running container and reapply its nginx/
                                  service config, then restart services. Does
                                  not touch the installed Denodo software.
  -Upgrade                       Like -Refresh, but also re-runs the Denodo
                                  platform installer if -DENODO_UPDATE changed,
                                  and always re-fetches the AI SDK and MCP
                                  server. Needs -DENODO_SUPPORT_CI/-DENODO_SUPPORT_SECRET.
"@ | Write-Host
}

if ($Help) {
  Show-Usage
  exit 0
}

# WORKAROUND: some services (design_studio, data-marketplace) can lose a
# startup race against denodo-vdp-server on their very first boot right
# after a fresh install/upgrade, when the host is busiest - resulting in a
# 502 from nginx for those. A plain `docker restart` reliably fixes it (the
# later "services-only" boot has none of that contention), so do it
# automatically once install/upgrade genuinely finishes, until the
# underlying race in linux/install.sh's service startup is fully solved.
function Invoke-StartupRaceWorkaroundRestart {
  Write-Host ""
  Write-Host "Restarting the container once as a workaround for a known service-startup"
  Write-Host "race (some services can fail their very first start right after a fresh"
  Write-Host "install/upgrade; a restart reliably fixes it)."
  docker restart $ImageName | Out-Null
}

# Only meaningful for a fresh install/-Reset, where "finished" can be
# minutes away and restarting mid-install would corrupt it. Polls the
# container's logs for the line install.sh prints on completion.
function Wait-ForInstallThenRestartWorkaround {
  $timeoutSec = 2400
  $intervalSec = 15
  $elapsed = 0
  Write-Host "Waiting for the install to finish, to then apply the startup-race workaround above..."
  while ($elapsed -lt $timeoutSec) {
    $logs = docker logs $ImageName 2>&1 | Out-String
    if ($logs -match '\[SECTION 18\] Installation complete' -or $logs -match 'Services-only start \(install already completed previously\)') {
      Invoke-StartupRaceWorkaroundRestart
      return $true
    }
    $running = docker inspect -f '{{.State.Running}}' $ImageName 2>$null
    if ($running -ne "true") {
      Write-Host "Container isn't running - install may have failed; skipping the workaround restart. Check the logs." -ForegroundColor Yellow
      return $false
    }
    Start-Sleep -Seconds $intervalSec
    $elapsed += $intervalSec
  }
  Write-Host "WARNING: timed out waiting for the install to finish - skipping the automatic workaround restart. Check the logs and restart manually if needed." -ForegroundColor Yellow
  return $false
}

# Raw-file base used to fetch install artifacts when this script is run
# standalone (no local checkout to read docker/, denodo_config.env from).
# Override with an env var for testing against a fork/branch.
$RepoRawBase = if ($env:REPO_RAW_BASE) { $env:REPO_RAW_BASE } else { "https://raw.githubusercontent.com/vfagesgo/denodo-oneclick/main" }

$ImageName = "denodo-oneclick"
$ImageTag = "beta"
# Single volume: entrypoint.sh mounts everything that needs to persist
# (repo checkout, downloads, Denodo install, AI SDK, Postgres data) as
# symlinks into subdirectories of /data instead of one volume per path.
$VolumeName = "denodo-oneclick-data"

# --- 0. Resolve a working directory that has docker/ + denodo_config.env ---
# Local checkout (repo cloned, install.ps1 run in place): use it as-is.
# Standalone download: there is no surrounding checkout, so fetch the
# required artifacts from GitHub into a throwaway temp dir instead of
# assuming anything exists on disk.
$ScriptDir = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "docker\Dockerfile"))) {
  $ScriptDir = $PSScriptRoot
} else {
  $ScriptDir = Join-Path $env:TEMP ("denodo-oneclick." + [System.IO.Path]::GetRandomFileName().Replace(".", ""))
  New-Item -ItemType Directory -Path (Join-Path $ScriptDir "docker") -Force | Out-Null
  Write-Host "No local checkout found - fetching install artifacts from $RepoRawBase"
  Invoke-WebRequest -UseBasicParsing -Uri "$RepoRawBase/docker/Dockerfile" -OutFile (Join-Path $ScriptDir "docker\Dockerfile")
  Invoke-WebRequest -UseBasicParsing -Uri "$RepoRawBase/docker/entrypoint.sh" -OutFile (Join-Path $ScriptDir "docker\entrypoint.sh")
  try {
    Invoke-WebRequest -UseBasicParsing -Uri "$RepoRawBase/denodo_config.env" -OutFile (Join-Path $ScriptDir "denodo_config.env")
  } catch {
    # Optional - install.sh treats a missing config the same way (warns, continues).
  }
}

# --- 1. Load defaults from denodo_config.env --------------------------------
$ConfigFile = Join-Path $ScriptDir "denodo_config.env"
$Config = @{}
if (Test-Path $ConfigFile) {
  Get-Content $ConfigFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
      $Config[$matches[1]] = $matches[2]
    }
  }
} else {
  Write-Warning "$ConfigFile not found, continuing with CLI values only."
}

# --- 2. Apply denodo_config.env defaults for anything not passed on the CLI -
# (PowerShell already parsed the CLI args into the param() variables above;
# this just fills in anything the caller left blank.)
function Get-WithDefault([string]$CliValue, [string]$Key) {
  if ($CliValue) { return $CliValue }
  if ($Config.ContainsKey($Key)) { return $Config[$Key] }
  return ""
}

$DENODO_UPDATE = Get-WithDefault $DENODO_UPDATE "DENODO_UPDATE"
$DENODO_PG_USER = Get-WithDefault $DENODO_PG_USER "DENODO_PG_USER"
$DENODO_PG_PWD = Get-WithDefault $DENODO_PG_PWD "DENODO_PG_PWD"
$DENODO_VDP_PWD = Get-WithDefault $DENODO_VDP_PWD "DENODO_VDP_PWD"

# --- 2.5. -Refresh / -Upgrade: act on an existing container, then exit ------
# These don't build or run anything - they reach into an already-running
# install via `docker exec` and ask linux/install.sh to do less than a full
# install (see that script's DENODO_ACTION for what each one actually does).
$Action = ""
if ($Refresh) { $Action = "refresh" }
if ($Upgrade) { $Action = "upgrade" }

if ($Action) {
  if ($Reset) {
    Write-Host "ERROR: -Reset can't be combined with -Refresh/-Upgrade - reset starts a fresh install instead." -ForegroundColor Red
    exit 1
  }

  docker inspect $ImageName *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: no existing '$ImageName' container found - run a normal install first." -ForegroundColor Red
    exit 1
  }

  if ($Action -eq "upgrade") {
    $missingUpgrade = @()
    if (-not $DENODO_SUPPORT_CI) { $missingUpgrade += "-DENODO_SUPPORT_CI" }
    if (-not $DENODO_SUPPORT_SECRET) { $missingUpgrade += "-DENODO_SUPPORT_SECRET" }
    if ($missingUpgrade.Count -gt 0) {
      Write-Host "ERROR: -Upgrade needs $($missingUpgrade -join ', ') (used to fetch the update/AI SDK/MCP archives)." -ForegroundColor Red
      exit 1
    }
  }

  $running = docker inspect -f '{{.State.Running}}' $ImageName
  if ($running -ne "true") {
    Write-Host "Container '$ImageName' is stopped - starting it first."
    docker start $ImageName | Out-Null
    # entrypoint.sh runs its own git fetch/reset + chown on every boot,
    # racing the exec-based refresh below if it starts immediately -
    # `docker start` returns as soon as the container's process launches,
    # not once entrypoint.sh's own repo sync/services-only pass has
    # finished. Give it a head start so the two don't touch the repo
    # directory at the same time (which can leave ownership in a state
    # that trips git's "dubious ownership" check right back up).
    Write-Host "Waiting for the container's own startup sequence to settle..."
    Start-Sleep -Seconds 20
  }

  Write-Host "== denodo-oneclick: $Action =="

  # Repo ownership inside the container can drift back to root between
  # restarts (a bug in an older entrypoint.sh - now fixed there too, but
  # already-running containers won't pick that fix up until their next full
  # restart). git then refuses to touch the directory as "denodo" with a
  # "dubious ownership" error. Reassert ownership + mark it safe for git
  # unconditionally here so -Refresh/-Upgrade work regardless of whether the
  # container has been restarted since that fix landed.
  docker exec -u root $ImageName bash -c '
    chown -R -H denodo:denodo /opt/denodo-oneclick
    if [ -d /opt/denodo-oneclick/www ]; then
      chgrp -R www-data /opt/denodo-oneclick/www
      chmod -R 750 /opt/denodo-oneclick/www
    fi
    sudo -H -u denodo git config --global --get-all safe.directory 2>/dev/null | grep -qx "*" \
      || sudo -H -u denodo git config --global --add safe.directory "*"
  '

  Write-Host "Pulling the latest denodo-oneclick repo into the container and running linux/install.sh --$Action..."
  docker exec `
    -e "DENODO_ACTION=$Action" `
    -e "DENODO_SUPPORT_CI=$DENODO_SUPPORT_CI" `
    -e "DENODO_SUPPORT_SECRET=$DENODO_SUPPORT_SECRET" `
    -e "DENODO_LIC=$DENODO_LIC" `
    -e "DENODO_UPDATE=$DENODO_UPDATE" `
    -e "DENODO_PG_USER=$DENODO_PG_USER" `
    -e "DENODO_PG_PWD=$DENODO_PG_PWD" `
    -e "DENODO_VDP_PWD=$DENODO_VDP_PWD" `
    -e "CLOUDFLARE_TUNNEL_KEY=$CLOUDFLARE_TUNNEL_KEY" `
    -e "OPENAI_API_KEY=$OPENAI_API_KEY" `
    -u denodo `
    $ImageName bash -c '
      set -e
      cd /opt/denodo-oneclick
      git fetch origin
      git reset --hard origin/main
      git clean -fd
      bash linux/install.sh
    '
  $rc = $LASTEXITCODE

  if ($rc -ne 0) {
    Write-Host "ERROR: -$Action failed (exit $rc). Check the logs: docker logs -f $ImageName" -ForegroundColor Red
    exit $rc
  }

  Invoke-StartupRaceWorkaroundRestart

  # The restart above goes through entrypoint.sh's normal boot path
  # (DENODO_ACTION=services-only), which reads CLOUDFLARE_TUNNEL_KEY from
  # the value baked into the container at its *original* `docker run` - not
  # the one just passed to this -$Action call - so it silently re-starts the
  # tunnel with the old key right after the exec above correctly applied the
  # new one. Give the restart a moment to settle, then re-apply the tunnel
  # one more time, explicitly, so the key you just passed is the one left
  # running.
  if ($CLOUDFLARE_TUNNEL_KEY) {
    Write-Host "Waiting for the restart above to settle, then re-applying the Cloudflare tunnel with the key just passed in..."
    Start-Sleep -Seconds 10
    docker exec `
      -e "CLOUDFLARE_TUNNEL_KEY=$CLOUDFLARE_TUNNEL_KEY" `
      -u denodo `
      $ImageName bash -c '
        cd /opt/denodo-oneclick
        DENODO_ACTION=cloudflare-refresh bash linux/install.sh
      '
  }

  Write-Host ""
  Write-Host "-$Action completed."
  exit 0
}

# --- 3. Validate mandatory parameters ---------------------------------------
$missing = @()
if (-not $DENODO_SUPPORT_CI) { $missing += "-DENODO_SUPPORT_CI" }
if (-not $DENODO_SUPPORT_SECRET) { $missing += "-DENODO_SUPPORT_SECRET" }
if (-not $DENODO_LIC) { $missing += "-DENODO_LIC" }

if ($missing.Count -gt 0) {
  Write-Host "ERROR: missing mandatory parameter(s): $($missing -join ', ')" -ForegroundColor Red
  Show-Usage
  exit 1
}

if (-not (Test-Path $DENODO_LIC -PathType Leaf)) {
  Write-Host "ERROR: DENODO_LIC file not found at: $DENODO_LIC" -ForegroundColor Red
  exit 1
}
$DENODO_LIC = (Resolve-Path $DENODO_LIC).Path

# --- 4. Dispatch to install mode ---------------------------------------------
if ($Mode -ne "docker") {
  if ($Mode -eq "local") {
    Write-Host "ERROR: local install mode is not implemented yet." -ForegroundColor Red
  } else {
    Write-Host "ERROR: unknown mode '$Mode' (expected 'docker' or 'local')." -ForegroundColor Red
  }
  exit 1
}

Write-Host "== denodo-oneclick: Docker install mode (Windows) =="

if ($Reset) {
  # Manually running `docker rm -f` + `docker volume rm ...` (the command
  # printed at the end of a normal run) is easy to get wrong. This does the
  # full, reliable teardown in one step.
  Write-Host "-Reset: removing any existing '$ImageName' container and its volume"
  docker rm -f $ImageName *> $null
  docker volume rm $VolumeName *> $null
}

# If a container from a previous attempt already exists, resume *that*
# container instead of rebuilding: `docker start` keeps everything it had
# (downloaded files, installed packages, partial progress), and
# entrypoint.sh + linux/install.sh's own idempotency checks pick up
# wherever they left off.
docker inspect $ImageName *> $null
$containerExists = ($LASTEXITCODE -eq 0)

if ($containerExists) {
  Write-Host "Found an existing '$ImageName' container - resuming it instead of rebuilding, so any"
  Write-Host "partially completed install work isn't thrown away."
  Write-Host "(Env vars like -DENODO_UPDATE can't be changed on a resumed container - remove it first"
  Write-Host "if you need to change them; see the from-scratch command below.)"
  docker start $ImageName | Out-Null
} else {
  Write-Host "No existing container found - building the image and creating a new one."

  # Rollback safety: keep the previous image under a ':previous' tag instead
  # of letting a new build silently replace it.
  docker image inspect "${ImageName}:${ImageTag}" *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Tagging existing ${ImageName}:${ImageTag} as ${ImageName}:previous for rollback."
    docker tag "${ImageName}:${ImageTag}" "${ImageName}:previous"
  }

  docker build -t "${ImageName}:${ImageTag}" (Join-Path $ScriptDir "docker")
  if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: docker build failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
  }

  # A named volume is a second safety net (on top of container reuse above):
  # it keeps the Denodo install/database intact even if this container is
  # later removed and recreated (e.g. after an image rebuild). Docker
  # creates it automatically on first use; entrypoint.sh symlinks the
  # various real paths (repo, /home/denodo, Denodo install, AI SDK,
  # Postgres) into subdirectories of it.
  docker run --name $ImageName -d `
    -p 80:80 `
    -p 2345:5432 `
    -v "${VolumeName}:/data" `
    -e "DENODO_SUPPORT_CI=$DENODO_SUPPORT_CI" `
    -e "DENODO_SUPPORT_SECRET=$DENODO_SUPPORT_SECRET" `
    -e "DENODO_UPDATE=$DENODO_UPDATE" `
    -e "DENODO_PG_USER=$DENODO_PG_USER" `
    -e "DENODO_PG_PWD=$DENODO_PG_PWD" `
    -e "DENODO_VDP_PWD=$DENODO_VDP_PWD" `
    -e "CLOUDFLARE_TUNNEL_KEY=$CLOUDFLARE_TUNNEL_KEY" `
    -e "OPENAI_API_KEY=$OPENAI_API_KEY" `
    -v "${DENODO_LIC}:/denodo/license.lic:ro" `
    "${ImageName}:${ImageTag}"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: docker run failed (exit $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
  }
}

Write-Host ""
Write-Host "Container is running in the background. Once install completes, the app is at http://localhost"
Write-Host "Following its logs now (Ctrl-C stops watching - the container keeps running):"
Write-Host ""
# Start-Process (not a background job) so the child's console output streams
# straight through to this console in real time, the same way the bash
# version's backgrounded `docker logs -f &` does.
$logsProc = Start-Process -FilePath "docker" -ArgumentList @("logs", "-f", $ImageName) -NoNewWindow -PassThru
try {
  Wait-ForInstallThenRestartWorkaround | Out-Null
} finally {
  if (-not $logsProc.HasExited) {
    Stop-Process -Id $logsProc.Id -Force -ErrorAction SilentlyContinue
  }
}
Write-Host ""
Write-Host "Reattaching to logs after the workaround restart above (Ctrl-C stops watching - the container keeps running):"
Write-Host ""
docker logs -f $ImageName

Write-Host ""
Write-Host "From-scratch reinstall: re-run this script with -Reset"
