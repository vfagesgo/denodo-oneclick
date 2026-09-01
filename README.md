# denodo-oneclick
Denodo developer one click install for Docker

## Usage

To install Denodo Developper you just need to follow those steaps
* Regirster with Denodo Support
* Obtain your Denodo Support Client ID
* Obtain your Denodo Support Secret
* Download your Denodo License

You can then run the following command to install your own local container image of Denodo Developper by running the following command (change the parameters first)

> **_NOTE:_**  You must have Docker priorly installed on your machine

### Linux / MacOS

```zsh
curl -fsSL https://raw.githubusercontent.com/vfagesgo/denodo-oneclick/main/install.sh | bash  -s -- \
--DENODO_SUPPORT_CI <Support_CI> \
--DENODO_SUPPORT_SECRET <Support_CI> \
--DENODO_LIC <Path to your Denodo license file>
```

If you already have this repository checked out locally, you can run the script directly instead of piping it from GitHub:

```zsh
./install.sh \
  --DENODO_SUPPORT_CI <Support_CI> \
  --DENODO_SUPPORT_SECRET <Support_Secret> \
  --DENODO_LIC <Path to your Denodo license file>
```

### Windows

On Windows, use `install.ps1` from a PowerShell prompt. Docker Desktop's Linux container backend builds/runs the exact same image as the bash version.

> **_NOTE:_** Start Docker Desktop before running the script — it calls `docker` directly and fails immediately if the Docker engine isn't running.

PowerShell doesn't support piping a script straight into execution the way `curl | bash` does, so download it first, then run it. PowerShell also blocks running downloaded `.ps1` scripts by default, so bypass that for the current session with `Set-ExecutionPolicy`:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

iwr -useb https://raw.githubusercontent.com/vfagesgo/denodo-oneclick/main/install.ps1 -OutFile install.ps1

.\install.ps1 -DENODO_SUPPORT_CI <Support_CI> -DENODO_SUPPORT_SECRET <Support_Secret> -DENODO_LIC <Path to your Denodo license file>
```

`-Scope Process` only relaxes the policy for the current PowerShell session, not your machine's overall setting.

If you already have this repository checked out locally, run `.\install.ps1 ...` directly instead (still preceded by the `Set-ExecutionPolicy` line above if needed).

### Next Steps 

The install runs in the background; the script automatically follows its logs in your terminal until you Ctrl-C (the container keeps running either way). Once it completes, Denodo is available at http://localhost. To reattach to the logs later:

## Options

### Mandatory parameters
- `--DENODO_SUPPORT_CI <value>`
- `--DENODO_SUPPORT_SECRET <value>`
- `--DENODO_LIC <path>` — path to the Denodo license file

### Optional overrides
Defaults come from `denodo_config.env`; pass any of these to override them:
- `--DENODO_UPDATE <value>` (default: `denodo-update-9.5.0`)
- `--DENODO_PG_USER <value>` (default: `denodo`)
- `--DENODO_PG_PWD <value>` (default: `password`)
- `--DENODO_VDP_USER <value>` (default: `admin`)
- `--DENODO_VDP_PWD <value>` (default: `admin`)

### Optional (CLI only)
- `--CLOUDFLARE_TUNNEL_KEY <value>` — optional Cloudflare Tunnel token, if you want to expose the instance publicly
- `--mode <docker|local>` — default `docker`; `local` is not implemented yet
- `--reset` — remove any existing container and its volumes first, so the install starts truly from scratch instead of resuming. Use this when you need to change a value like `--DENODO_UPDATE`, since those can't be changed on a container that already exists.

## Retrying a failed or interrupted install

Just re-run the same command. It resumes the existing container rather than starting over — downloaded archives, installed packages, and completed install steps are kept, so a retry picks up close to where it left off instead of redoing everything from scratch.

If you do want a totally clean install, add `--reset` to remove the existing container and its data first.

## Persistence

Install progress and data live in a set of named Docker volumes, so they survive the container being removed and recreated (for example after rebuilding the image):
- `denodo-oneclick-data` — this conatians the repository's, Denodo install, PostgreSQL database

`--reset` removes all of these along with the container.

## Current status

The Docker install mode is fully working: it builds a Debian-based image, installs PostgreSQL, Java, the Denodo platform, the Denodo AI SDK, and nginx, then starts the Denodo services and serves the application on port 80. Local (non-Docker) install mode is not implemented yet.
