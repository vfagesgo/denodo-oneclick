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
  [string]$DENODO_VDP_USER,
  [string]$DENODO_VDP_PWD,
  [string]$CLOUDFLARE_TUNNEL_KEY,
  [string]$Mode = "docker",
  [switch]$Reset,
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
  -DENODO_VDP_USER <value>
  -DENODO_VDP_PWD <value>

Optional:
  -CLOUDFLARE_TUNNEL_KEY <value>
  -Mode <docker|local>           Default: docker (local not implemented yet)
  -Reset                         Wipe any existing container + its volume first,
                                  so the install starts truly from scratch
  -Help                          Show this message
"@ | Write-Host
}

if ($Help) {
  Show-Usage
  exit 0
}

# Raw-file base used to fetch install artifacts when this script is run
# standalone (no local checkout to read docker/, denodo_config.env from).
# Override with an env var for testing against a fork/branch.
$RepoRawBase = if ($env:REPO_RAW_BASE) { $env:REPO_RAW_BASE } else { "https://raw.githubusercontent.com/vfagesgo/denodo-oneclick/main" }

$ImageName = "denodo-oneclick"
$ImageTag = "hello-world"
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
$DENODO_VDP_USER = Get-WithDefault $DENODO_VDP_USER "DENODO_VDP_USER"
$DENODO_VDP_PWD = Get-WithDefault $DENODO_VDP_PWD "DENODO_VDP_PWD"

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
    -v "${VolumeName}:/data" `
    -e "DENODO_SUPPORT_CI=$DENODO_SUPPORT_CI" `
    -e "DENODO_SUPPORT_SECRET=$DENODO_SUPPORT_SECRET" `
    -e "DENODO_UPDATE=$DENODO_UPDATE" `
    -e "DENODO_PG_USER=$DENODO_PG_USER" `
    -e "DENODO_PG_PWD=$DENODO_PG_PWD" `
    -e "DENODO_VDP_USER=$DENODO_VDP_USER" `
    -e "DENODO_VDP_PWD=$DENODO_VDP_PWD" `
    -e "CLOUDFLARE_TUNNEL_KEY=$CLOUDFLARE_TUNNEL_KEY" `
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
docker logs -f $ImageName

Write-Host ""
Write-Host "From-scratch reinstall: re-run this script with -Reset"
