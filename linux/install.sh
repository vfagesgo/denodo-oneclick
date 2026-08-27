#!/usr/bin/env bash
set -euo pipefail

# Resolve paths relative to this script instead of hardcoding an install
# location. Previously Section 15/16 hardcoded /opt/denodo-pi or referenced
# $INSTALL_DIR without ever setting it, which failed regardless of where
# the repo was actually cloned.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

LOG=/var/log/1-denodo_install.log
sudo touch $LOG
sudo chown -R denodo:denodo "$LOG"
# This installer makes privileged changes across the OS, so fail early on
# missing variables, command failures inside pipelines, and unexpected errors.
set -euo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

log_section() {
  echo "[SECTION $1] $2" | tee -a "$LOG"
}

log_step() {
  echo "[STEP] $1" | tee -a "$LOG"
}



# Section 03:
# Running directly as root would hide which user should own the installed
# files. This check enforces the expected pattern: regular user + sudo.
log_section "03" "Validate the install user"
user="${USER:-$(id -un 2>/dev/null || echo "#$(id -u)")}"
if [ "$user" = "root" ] || [ "$user" = "#0" ]; then
  log_step "This script must be run as a regular user with sudo privileges"
  exit 1
fi

# Section 04:
# Start from an up-to-date operating system before adding product-specific
# dependencies. This block refreshes package indexes and installs the base
# toolchain used by the later bootstrap steps.
log_section "04" "Refresh apt metadata and install base dependencies"
sudo apt update -y 
sudo apt upgrade -y 

sudo apt install -y libglib2.0-dev build-essential 
sudo apt install -y python3 python3-venv python3-dev

sudo apt install -y jq

# These packages are only here to support repository registration and secure
# package downloads from external vendors.
sudo apt install -y wget gnupg ca-certificates lsb-release curl


# Section 05:
# PostgreSQL is installed from the upstream PGDG repository so the target
# version stays available regardless of the base Raspberry Pi OS defaults.
log_section "05" "Configure the PostgreSQL apt repository"
# Import the PostgreSQL signing key.
wget -qO- https://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/postgresql.gpg > /dev/null

# Register the PostgreSQL repository for the current Debian release.
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  | sudo tee /etc/apt/sources.list.d/pgdg.list

# Section 06:
# Install the database, web server, networking tools, and Python/system
# libraries that the final Denodo environment depends on.
log_section "06" "Install PostgreSQL and runtime packages"
# Refresh package indexes after adding PostgreSQL and install runtime packages.
sudo apt update
sudo apt install -y postgresql-15 postgresql-client-15 libpq-dev
sudo apt install nginx -y
sudo apt install gettext -y
sudo apt install git -y
sudo apt install python3-gi gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly -y
sudo apt install python3-pil -y
sudo apt install python3-pip -y
sudo apt install dnsmasq network-manager -y

# Section 09:
# PostgreSQL needs two kinds of access for this deployment:
# 1. Local trusted access for the bootstrap steps.
# 2. Remote access for the Denodo application user on the project subnet.
# This section updates both the authentication rules and the listener
# settings, then restarts PostgreSQL so the changes take effect.
log_section "09" "Configure PostgreSQL access for Denodo"

pg_hba_files=(/etc/postgresql/*/main/pg_hba.conf)

# Count trust entries without failing when no file matches.
trust=$(sudo grep -cE '^local[[:space:]]+all[[:space:]]+all[[:space:]]+trust' "${pg_hba_files[@]}" || true)

if [ "$trust" -lt 1 ]; then
  log_step "Configuring PostgreSQL for trusted local access"

  sudo sed -i.orig -E \
    's/^(local[[:space:]]+all[[:space:]]+all[[:space:]]+)(peer|md5|scram-sha-256)$/\1trust/' \
    "${pg_hba_files[@]}"


  trust=$(sudo grep -cE '^local[[:space:]]+all[[:space:]]+all[[:space:]]+trust' "${pg_hba_files[@]}" || true)

  if [ "$trust" -lt 1 ]; then
    log_step "Failed to configure PostgreSQL local trust access"
    exit 1
  fi
fi

# Add a network rule for the application user if it is not already present.

DENODO_SUBNET="192.168.0.0/16"
DENODO_USER=${DENODO_PG_USER:-"denodo"}

remote_denodopi=$(sudo grep -cE \
"^host[[:space:]]+all[[:space:]]+$DENODO_USER[[:space:]]+$DENODO_SUBNET[[:space:]]+scram-sha-256" \
"${pg_hba_files[@]}" || true)

if [ "$remote_denodopi" -lt 1 ]; then
  log_step "Configuring PostgreSQL network access for user '$DENODO_USER'"

  sudo sed -i.orig -E \
    "/^#.*IPv4 local connections:/a host all $DENODO_USER $DENODO_SUBNET scram-sha-256" \
    "${pg_hba_files[@]}"
fi

log_step "Configuring PostgreSQL listen_addresses"

pg_conf_files=(/etc/postgresql/*/main/postgresql.conf)

for PG_CONF in "${pg_conf_files[@]}"; do
  log_step "Updating $PG_CONF"

  # Fail fast if the expected PostgreSQL config file is missing.
  if [ ! -f "$PG_CONF" ]; then
    log_step "Config not found: $PG_CONF"
    exit 1
  fi

  # Keep a one-time backup of the original PostgreSQL config.
  if [ ! -f "$PG_CONF.orig" ]; then
    log_step "Backing up $PG_CONF to $PG_CONF.orig"
    sudo cp "$PG_CONF" "$PG_CONF.orig"
  fi

  # Listen on all interfaces required by the target network layout.
  sudo sed -i -E \
    "s|^[[:space:]]*#?[[:space:]]*listen_addresses[[:space:]]*=.*|listen_addresses = '*'|" \
    "$PG_CONF"
  
  # Verify the listen_addresses update before continuing.
  if ! grep -q "^listen_addresses = '\\*'" "$PG_CONF"; then
    log_step "Failed to update listen_addresses in $PG_CONF"
    exit 1
  fi
done


for conf in "${pg_hba_files[@]}"; do
  version=$(echo "$conf" | cut -d/ -f4)
  name=$(echo "$conf" | cut -d/ -f5)

  log_step "Restarting PostgreSQL cluster $version/$name"
  # pg_ctlcluster works with or without systemd. The `systemctl restart
  # postgresql` that used to run right after this loop was both redundant
  # with it and fatal outside a real systemd environment (e.g. inside a
  # plain Docker container: "System has not been booted with systemd as
  # init system (PID 1)").
  sudo pg_ctlcluster "$version" "$name" restart
done

# Section 10:
# Create the PostgreSQL role and database expected by Denodo. Re-running the
# script should converge on the same state, so existing roles are updated
# instead of treated as a failure.
log_section "10" "Create or update the Denodo database"
DENODO_PG_USER=${DENODO_PG_USER:-"denodo"}
DENODO_PG_PWD=${DENODO_PG_PWD:-"password"}

role_exists=$(sudo -u postgres psql -tAc \
  "SELECT 1 FROM pg_roles WHERE rolname='$DENODO_PG_USER'")

if [ -z "$role_exists" ]; then
  log_step "Creating PostgreSQL user $DENODO_PG_USER"
  sudo -u postgres psql -c "CREATE USER $DENODO_PG_USER PASSWORD '$DENODO_PG_PWD'"
else
  log_step "Updating PostgreSQL user $DENODO_PG_USER"
  sudo -u postgres psql -c "ALTER USER $DENODO_PG_USER WITH PASSWORD '$DENODO_PG_PWD';"
fi

db_exists=$(sudo -u postgres psql -tAc \
  "SELECT 1 FROM pg_database WHERE datname='denodo'")

if [ -z "$db_exists" ]; then
  log_step "Creating PostgreSQL database denodo"
  sudo -u postgres psql -c \
    "CREATE DATABASE denodo OWNER=$DENODO_PG_USER LC_COLLATE='C' LC_CTYPE='C' ENCODING='UTF8' TEMPLATE template0"
fi

sudo -u postgres psql -c "ALTER ROLE $DENODO_PG_USER CREATEDB"

# Section 11:
# Denodo 9 requires Java 17. This block registers the Azul repository and
# installs Zulu JDK 17 so the installer has a supported JVM.
log_section "11" "Configure Zulu Java 17"
curl -s https://repos.azul.com/azul-repo.key \
| sudo gpg --yes --dearmor -o /usr/share/keyrings/azul.gpg

echo "deb [signed-by=/usr/share/keyrings/azul.gpg] https://repos.azul.com/zulu/deb stable main" \
| sudo tee /etc/apt/sources.list.d/zulu.list

sudo chmod 644 /usr/share/keyrings/azul.gpg  
sudo apt update -y

sudo apt install -y zulu17-jdk

# Section 11.5:
# Get Denodo support CLI tool and pull Denodo binaries. On first install it is cloned;
# on later runs it is refreshed so the workspace matches the remote branch.

log_section "11.5" "Install Denodo Support Tools"
# denodo_config.env defines this as DENODO_UTILS_URL. The script previously
# referenced $GITHUB_DENODO_UTILS, which was never set anywhere and crashed
# here under `set -u`.
DENODO_UTILS_URL=${DENODO_UTILS_URL:-"denodocommunity-resources/releases/download/v1.3.2/Denodo.Support.Utilities.v1.3.2.zip"}
ZIP_URL="https://github.com/denodo/$DENODO_UTILS_URL"
TARGET_DIR="/home/denodo/"
DENODO_INSTALL="/home/denodo/denodo-install-9"

# Section 11.5+12 involve multi-GB downloads (installer + update archives).
# Everything below is guarded to skip work that a previous, failed run
# already completed, so re-running install.sh after a crash doesn't
# re-download or re-extract from scratch.

if [ -x "$TARGET_DIR/denodo-support-utils/bin/denodo-support" ]; then
  log_step "denodo-support already installed, skipping"
else
  curl -L "$ZIP_URL" -o "${TARGET_DIR}Denodo.Support.Utilities.zip"
  unzip -o "${TARGET_DIR}Denodo.Support.Utilities.zip" -d "$TARGET_DIR"
  rm -f "${TARGET_DIR}Denodo.Support.Utilities.zip"
fi

cd $TARGET_DIR/denodo-support-utils/bin/
chmod +x denodo-support

if [ -f "/home/denodo/denodo-install-9-ga.zip" ]; then
  log_step "Installer archive already downloaded, skipping (remove /home/denodo/denodo-install-9-ga.zip to force a re-download)"
else
  log_step "Download Installer"
  ./denodo-support -t installer -n denodo-install-9-ga -d /home/denodo -u $DENODO_SUPPORT_CI -s $DENODO_SUPPORT_SECRET
fi

if [ -f "/home/denodo/$DENODO_UPDATE.zip" ]; then
  log_step "Update archive already downloaded, skipping (remove /home/denodo/$DENODO_UPDATE.zip to force a re-download)"
else
  log_step "Download Update$DENODO_UPDATE"
  ./denodo-support -t update -n $DENODO_UPDATE -d /home/denodo -u $DENODO_SUPPORT_CI -s $DENODO_SUPPORT_SECRET
fi

log_step "Prepare install folder"
cd /home/denodo

if [ -d "$DENODO_INSTALL" ]; then
  log_step "$DENODO_INSTALL already extracted, skipping unzip"
else
  unzip -o denodo-install-9-ga.zip
fi

mkdir -p "$DENODO_INSTALL/denodo-update"
# The jar gets renamed to a fixed "denodo-update.jar" below, so its mere
# presence can't tell two different $DENODO_UPDATE versions apart - a stale
# jar from a previous version would wrongly look "already staged" on a
# rerun with a newer DENODO_UPDATE. Track which version was actually staged
# alongside it instead.
DENODO_UPDATE_MARKER="$DENODO_INSTALL/denodo-update/.staged_version"
if [ -f "$DENODO_INSTALL/denodo-update/denodo-update.jar" ] \
  && [ "$(cat "$DENODO_UPDATE_MARKER" 2>/dev/null)" = "$DENODO_UPDATE" ]; then
  log_step "Update $DENODO_UPDATE already staged, skipping unzip"
else
  unzip -q -o "$DENODO_UPDATE.zip" -d "$DENODO_INSTALL/denodo-update"
  mv "$DENODO_INSTALL/denodo-update/$DENODO_UPDATE.jar" "$DENODO_INSTALL/denodo-update/denodo-update.jar"
  echo "$DENODO_UPDATE" > "$DENODO_UPDATE_MARKER"
fi

# Section 12:
# Prepare the Denodo installer directory, link the detected JVM, place the
# license file, and run the unattended platform installation.
log_section "12" "Install Denodo 9"

unset DISPLAY
cd "$DENODO_INSTALL"

log_step "Get JAVA_HOME"
JAVA_BIN=$(readlink -f $(which java) || true)
JAVA_HOME=$(dirname $(dirname "$JAVA_BIN"))

# Configure for current session
export JAVA_HOME="$JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

chmod +x installer_cli.sh

# Default must be set before it's ever referenced - the log line below used
# to read $DENODO_LIC first, which crashed with "unbound variable" whenever
# the caller didn't set it (e.g. the Docker flow, which only mounts the
# license file and never sets this env var).
DENODO_LIC=${DENODO_LIC:-"denodo-developer-lic-9.lic"}
log_step "Copy Denodo License: $DENODO_LIC"

# Check the unambiguous absolute-path locations (Docker mount, Pi boot
# partition) before the bare $DENODO_LIC filename: cwd is $DENODO_INSTALL
# here, and on a resumed run $DENODO_INSTALL/denodo-developer-lic-9.lic
# (the copy *destination*) already exists - checking the relative filename
# first previously matched that destination file itself as the "source"
# and made `cp` fail with "are the same file".
if [ -f "/denodo/license.lic" ]; then
  DENODO_LIC_SRC="/denodo/license.lic"
elif [ -f "/boot/firmware/denodo/$DENODO_LIC" ]; then
  DENODO_LIC_SRC="/boot/firmware/denodo/$DENODO_LIC"
elif [ -f "$DENODO_LIC" ]; then
  DENODO_LIC_SRC="$DENODO_LIC"
else
  log_step "ERROR: no Denodo license file found (checked /denodo/license.lic, /boot/firmware/denodo/$DENODO_LIC, '$DENODO_LIC')"
  exit 1
fi

# Always overwrite an existing destination copy with whatever license was
# just resolved above (e.g. a newer one mounted at /denodo/license.lic) -
# `cp` does this by default. The one case that must be skipped is the
# source and destination already being the exact same file (only possible
# via the bare-filename fallback above): there's nothing to "overwrite"
# there, and `cp` would just error out on a self-copy.
if [ "$(readlink -f "$DENODO_LIC_SRC" 2>/dev/null)" = "$(readlink -f "$DENODO_INSTALL/denodo-developer-lic-9.lic" 2>/dev/null)" ]; then
  log_step "License source and destination are the same file, nothing to copy"
else
  log_step "Copying license from $DENODO_LIC_SRC (overwriting any existing destination copy)"
  sudo cp -f "$DENODO_LIC_SRC" "$DENODO_INSTALL/denodo-developer-lic-9.lic"
fi
sudo chown denodo:denodo "$DENODO_INSTALL/denodo-developer-lic-9.lic"
#./installer_cli.sh install
sudo mkdir -p /opt/denodo
sudo chown -R denodo:denodo /opt/denodo

log_step "Faking JAVA JRE in Denodo Home"
# -f/-n so re-running after a failed install doesn't crash on "File exists".
ln -sfn "$JAVA_HOME" jre
cd denodo-update
rm -rf jre
mkdir -p jre
cd jre
ln -sfn "$JAVA_HOME" jre-linux
cd "$DENODO_INSTALL"

log_step "Start Denodo Install"
./installer_cli.sh install --autoinstaller "$SCRIPT_DIR/response_file_9_0.xml" | tee -a $LOG

## Change Java memory parameters to be able to run on a Raspeberry PI
log_step "Change Java Config"
change_config() {
  local PARAM="$1"
  local CONF_FILE="$2"
  local NEW_XMX="$3"

  cp -p "$CONF_FILE" "$CONF_FILE.bak.$(date +%F_%H%M%S)" &&
  sed -i -E \
      '/^java\.env\.DENODO_OPTS_START[[:space:]]*=/ s/-Xmx[0-9]+[mMgG]/-Xmx'"$NEW_XMX"'/g' \
      "$CONF_FILE"
}
log_step "JAVA Config: Change -Xmx in VDBConfiguration.properties"
change_config "-Xmx" "/opt/denodo/denodo-platform/conf/vdp/VDBConfiguration.properties" "2048m"
log_step "JAVA Config: Change -XX:ReservedCodeCacheSize= in VDBConfiguration.properties"
change_config "-XX:ReservedCodeCacheSize=" "/opt/denodo/denodo-platform/conf/vdp/VDBConfiguration.properties" "256m"
log_step "JAVA Config: Change -Xmx in resources/apache-tomcat/conf/tomcat.properties"
change_config "-Xmx" "/opt/denodo/denodo-platform/resources/apache-tomcat/conf/tomcat.properties" "1024m"

/opt/denodo/denodo-platform/bin/regenerateFiles.sh

# Section 13:
# The AI SDK lives in its own Git repository. On first install it is cloned;
# on later runs it is refreshed so the workspace matches the remote branch.
log_section "13" "Install Denodo AI SDK"
GITHUB_REPO_URL="https://github.com/denodo/denodo-ai-sdk.git"
# Was referenced below without ever being set, which crashed under `set -u`.
AISDK_INSTALL_DIR=${AISDK_INSTALL_DIR:-"/home/denodo/denodo-ai-sdk"}

log_step "Repository: denodo-ai-sdk"
log_step "Install directory: $AISDK_INSTALL_DIR"
log_step "Branch: main"
sudo mkdir -p "$AISDK_INSTALL_DIR"
sudo chown -R denodo:denodo "$AISDK_INSTALL_DIR"

# Clone the repo on first install, otherwise refresh the existing checkout.
if [ ! -d "$AISDK_INSTALL_DIR/.git" ]; then
  log_step "Cloning denodo-ai-sdk repository"
  git clone "$GITHUB_REPO_URL" "$AISDK_INSTALL_DIR"
  chown -R denodo:denodo "$AISDK_INSTALL_DIR"
  
else
  log_step "Updating denodo-ai-sdk repository"
  cd "$AISDK_INSTALL_DIR" || exit 1

  git fetch origin
  git reset --hard "origin"
  git clean -fd
fi

# Section 14:
# The AI SDK depends on a fairly large native/Python build toolchain on
# Raspberry Pi. This section installs apt dependencies, bootstraps pyenv,
# and builds the Python runtime used by the project.
log_section "14" "Configure the Python environment"
cd ~

log_step "Installing Debian packages that reduce Python build time on Raspberry Pi"

base_packages=(
  build-essential
  pkg-config
  cmake
  gfortran
  gcc
  g++
  make
  rustc
  cargo
  python3-dev
  python3-venv
  python3-pip
  libffi-dev
  libssl-dev
  libsqlite3-dev
  sqlite3
  zlib1g-dev
  libbz2-dev
  liblzma-dev
  libreadline-dev
  libxml2-dev
  libxslt1-dev
  libpq-dev
  libgeos-dev
  libgomp1
  libopenblas-dev
  liblapack-dev
  libjpeg-dev
  libpng-dev
  libharfbuzz-dev
  libfribidi-dev
  liblcms2-dev
  libopenjp2-7-dev
  libtiff5-dev
  tk-dev
)

optional_native_packages=(
  libwebp-dev
  libblas-dev
)

python_packages=(
  python3-numpy
  python3-scipy
  python3-pandas
  python3-matplotlib
  python3-lxml
  python3-pil
  python3-psutil
  python3-yaml
  python3-requests
  python3-lz4
  python3-bs4
  python3-dateutil
  python3-kiwisolver
  python3-fonttools
  python3-packaging
  python3-click
  python3-cryptography
  python3-bcrypt
  python3-httptools
  python3-websockets
  python3-greenlet
  python3-sqlalchemy
  python3-psycopg2
  python3-pyarrow
  python3-shapely
  python3-orjson
)

available_packages=()
missing_packages=()

add_if_available() {
  local pkg="$1"
  # Keep the install resilient across Debian/Raspberry Pi OS variants by
  # selecting only packages that exist in the current apt metadata.
  if apt-cache show "$pkg" >/dev/null 2>&1; then
    available_packages+=("$pkg")
  else
    missing_packages+=("$pkg")
  fi
}

log_step "Refreshing apt metadata"
sudo apt-get update

log_step "Collecting available apt packages"
for pkg in "${base_packages[@]}"; do
  add_if_available "$pkg"
done

for pkg in "${optional_native_packages[@]}"; do
  add_if_available "$pkg"
done


for pkg in "${python_packages[@]}"; do
  add_if_available "$pkg"
done


if [[ "${#available_packages[@]}" -eq 0 ]]; then
  log_step "No installable apt packages were found"
fi

log_step "Installing ${#available_packages[@]} apt package(s)"
sudo apt-get install -y "${available_packages[@]}"

# Install pyenv to manage the project Python version. This used to
# unconditionally `rm -rf ~/.pyenv` and rebuild Python 3.11 from source on
# every run - one of the "rebuilds/redownloads everything on retry"
# problems, since $HOME (/home/denodo) can now persist across container
# restarts. Skip entirely if it's already there.
log_step "Installing pyenv"
if [ -x "$HOME/.pyenv/bin/pyenv" ]; then
  log_step "pyenv already installed, skipping"
else
  curl -fsSL https://pyenv.run | bash
fi

# Add pyenv init hooks to .bashrc only once.
if ! grep -q 'pyenv init' "$HOME/.bashrc"; then
  {
    echo '' 
    echo '# Pyenv configuration'
    echo 'export PATH="$HOME/.pyenv/bin:$PATH"'
    echo 'eval "$(pyenv init -)"'
    echo 'eval "$(pyenv virtualenv-init -)"'
  } >> "$HOME/.bashrc"
fi

# Load pyenv into the current shell so the script can use it immediately.
export PATH="$HOME/.pyenv/bin:$PATH"
eval "$(~/.pyenv/bin/pyenv init -)"
eval "$(~/.pyenv/bin/pyenv virtualenv-init -)"

# Build and select Python 3.11 for the install user.
log_step "Installing Python 3.11 with pyenv"
MAKE_OPTS="-j$(nproc)" pyenv install -s 3.11
pyenv global 3.11

# When the bootstrap block above is disabled, reuse the system Python and
# create a project virtual environment locally instead of rebuilding Python.
python --version

# Try to find any python3 version
py_cmd=$(command -v python3 || true)
if [ -z "$py_cmd" ]; then
    echo "💩 - Python 3 is not installed" | tee -a $LOG
    exit 1
fi
# Get the version number
py_ver_str=$($py_cmd -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')

# Extract major and minor
py_major=$(echo "$py_ver_str" | cut -d. -f1)
py_minor=$(echo "$py_ver_str" | cut -d. -f2)
py_ver=$py_major.$py_minor

# Require Python 3.10+ for the virtual environment and dependencies.
if [ "$py_major" -lt 3 ] || { [ "$py_major" -eq 3 ] && [ "$py_minor" -lt 10 ]; }; then
    log_step "Python 3.10 or higher is required; found $py_ver_str"
    exit 1
fi

log_step "Python version $py_ver is available"
python="$py_cmd"
# Recreate the environment if it targets a different Python minor version.
VENV_DIR="venv_denodo"
venv_cfg="$VENV_DIR/pyvenv.cfg"

if [[ -f "${venv_cfg}" && "$(grep -c version\ =\ ${py_ver} ${venv_cfg})" -eq 0 ]]; then
  log_step "Removing virtual environment because it targets a different Python version"
  sudo rm -rf "$VENV_DIR"
fi
if [ ! -d "$VENV_DIR" ]; then
  log_step "Creating Python ${py_ver} virtual environment"
  $python -m venv "$VENV_DIR"
fi

log_step "Updating pip in the virtual environment"
log_step "Activating $VENV_DIR"
source "$VENV_DIR/bin/activate"
$VENV_DIR/bin/python -m pip install --upgrade pip

# Install wheel first because some downstream packages still rely on it
# during native builds on ARM platforms.
$VENV_DIR/bin/python -m pip install --no-cache-dir wheel
log_step "Current directory: $(pwd)"

  
cd "$AISDK_INSTALL_DIR" || exit 1
log_step "Current directory: $(pwd)"

pip install --upgrade pip setuptools wheel
log_step "Installing AI SDK requirements"

sudo apt update

# Force the requirements to use the system sqlite build. This avoids pulling
# an extra binary package that is not needed on the Raspberry Pi image.
sed -i 's/^pysqlite3-binary==/pysqlite3==/' requirements.txt

/home/denodo/$VENV_DIR/bin/python -m pip install --no-cache-dir --prefer-binary -r requirements.txt



if [ -f "/boot/firmware/denodo/chatbot_config.env" ]; then
  log_step "Copy chatbot config file chatbot_config.env "
    
  sudo cp /boot/firmware/denodo/chatbot_config.env $AISDK_INSTALL_DIR/sample_chatbot/chatbot_config.env
  sudo chown denodo:denodo $AISDK_INSTALL_DIR/sample_chatbot/chatbot_config.env
fi

if [ -f "/boot/firmware/denodo/sdk_config.env" ]; then
  log_step "Copy AISDK config file sdk_config.env "
    
  sudo cp /boot/firmware/denodo/sdk_config.env $AISDK_INSTALL_DIR/api/utils/sdk_config.env
  sudo chown denodo:denodo $AISDK_INSTALL_DIR/api/utils/sdk_config.env
fi



# Section 15:
# nginx wiring is still commented out, but the placeholder remains so the
# script structure matches the intended install phases.
log_section "15" "Configure nginx"

log_step "Installing Nginx configuration file"

sudo cp -f "$SCRIPT_DIR/nginx-site.conf" /etc/nginx/sites-enabled/default

sudo chmod o+rx /opt
sudo chmod o+rx "$REPO_ROOT"
sudo chmod -R o+rx "$REPO_ROOT/www"

sudo chgrp -R www-data "$REPO_ROOT/www"
sudo chmod -R 750 "$REPO_ROOT/www"

sudo usermod -aG www-data www-data

log_step "Restarting Nginx"
# `service` works whether or not systemd is PID 1 (it falls back to the
# init.d script), unlike `systemctl`, which fails outside a real systemd
# environment such as a plain Docker container.
sudo service nginx restart
  

# Start the Denodo services, either via systemd (regular Linux install) or
# as supervised background processes (no systemd available, e.g. inside a
# Docker container). Both paths read the same *.service files under
# $SCRIPT_DIR/services so there is one source of truth for what each
# service runs.
log_section "16" "Configuring the different services"

SERVICE_DIR="$SCRIPT_DIR/services"
RUN_DIR="/var/run/denodo-oneclick"
sudo mkdir -p "$RUN_DIR"
sudo chown denodo:denodo "$RUN_DIR"

# Fixed start order: vdp-server first, then the two that depend on it, then
# aisdk which depends on data-marketplace. House-keeping has no dependents.
SERVICE_ORDER=(
  denodo_house_keeping
  denodo-vdp-server
  denodo-design_studio
  denodo-data-marketplace
  denodo-aisdk
)

if [ -d /run/systemd/system ]; then
  log_step "systemd detected - installing and starting services via systemctl"

  for name in "${SERVICE_ORDER[@]}"; do
    service_file="$SERVICE_DIR/${name}.service"
    [ -f "$service_file" ] || continue
    echo "Installing service ${name}.service"
    # denodo_house_keeping.service still hardcodes /opt/denodo-pi (stale,
    # same issue as the nginx paths fixed above); normalize it to wherever
    # this script actually lives instead of editing the checked-in unit file.
    sed "s#/opt/denodo-pi#${SCRIPT_DIR}#g" "$service_file" | sudo tee "/lib/systemd/system/${name}.service" >/dev/null
    sudo chown root "/lib/systemd/system/${name}.service"
  done

  sudo systemctl daemon-reload

  for name in "${SERVICE_ORDER[@]}"; do
    [ -f "$SERVICE_DIR/${name}.service" ] || continue
    sudo systemctl unmask "${name}.service"
    sudo systemctl enable "${name}.service"
    sudo systemctl start "${name}.service"
  done
else
  log_step "No systemd detected - starting services directly as background processes"

  # Read a single-valued field (e.g. ExecStart, User) out of a .service
  # file. Fine here because none of these fields repeat across sections in
  # our own unit files.
  service_field() {
    # grep exits 1 when the field is simply absent (many are optional -
    # e.g. denodo_house_keeping.service has no User/WorkingDirectory/
    # ExecStop). Under `set -euo pipefail`, `var=$(service_field ...)`
    # failing like that killed the whole script on the very first
    # service, before it even printed which one or why.
    grep -E "^${2}=" "$1" | head -n1 | cut -d= -f2- || true
  }

  start_service() {
    local service_file="$1"
    local name exec_start run_user working_dir pre_start restart

    name=$(basename "$service_file" .service)
    exec_start=$(service_field "$service_file" "ExecStart")
    run_user=$(service_field "$service_file" "User")
    working_dir=$(service_field "$service_file" "WorkingDirectory")
    pre_start=$(service_field "$service_file" "ExecStartPre")
    restart=$(service_field "$service_file" "Restart")
    run_user=${run_user:-denodo}

    if [ -z "$exec_start" ]; then
      log_step "Skipping $name: no ExecStart in $service_file"
      return
    fi

    service_field "$service_file" "ExecStop" | sudo tee "$RUN_DIR/${name}.stop" >/dev/null

    (
      [ -n "$pre_start" ] && eval "$pre_start"
      cd "${working_dir:-/}" || exit 1
      if [ "$restart" = "always" ]; then
        while true; do
          sudo -u "$run_user" bash -c "$exec_start"
          sleep 5
        done
      else
        sudo -u "$run_user" bash -c "$exec_start"
      fi
    ) >>"$LOG" 2>&1 &

    echo $! | sudo tee "$RUN_DIR/${name}.pid" >/dev/null
    log_step "Started $name (pid $!, log: $LOG)"
  }

  for name in "${SERVICE_ORDER[@]}"; do
    service_file="$SERVICE_DIR/${name}.service"
    [ -f "$service_file" ] && start_service "$service_file"
  done

  log_step "Services started in the background. PIDs/stop commands are under $RUN_DIR"
  log_step "Note: keeping the container itself alive (e.g. a foreground wait loop) is the entrypoint's responsibility, not this script's"
fi