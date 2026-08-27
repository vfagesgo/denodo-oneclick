#!/usr/bin/env bash
set -euo pipefail

LOG=/var/log/1-denodo_install.log
sudo touch $LOG
sudo chown -R denodo:denodo "$LOG"
# This installer makes privileged changes across the OS, so fail early on
# missing variables, command failures inside pipelines, and unexpected errors.
set -uo pipefail
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND"; exit $s' ERR

log_section() {
  echo "[SECTION $1] $2" | tee -a "$LOG"
}

log_step() {
  echo "[STEP] $1" | tee -a "$LOG"
}


# Section 01:
# The installer can be driven by values stored denodo_config.env or already passed as environment variables
# If those environemnt variable are missing, the script falls back to its built-in defaults from denodo_config.env.
log_section "01" "Check inputs and load environment variables"

# Load environment variables from the boot partition when available.
if [ -f /boot/firmware/denodo/denodo_config.env ]; then
    log_step "Loading config from /boot/firmware/denodo/denodo_config.env"
    set -o allexport
    source /boot/firmware/denodo/denodo_config.env
    set +o allexport
else
    log_step "No config file found; continuing with defaults"
fi


INSTALL_DIR="/opt/denodo-pi"
AISDK_INSTALL_DIR="/opt/denodo-aisdk"

# Install Cloudflare tunnel if env variable is set
# Add cloudflare gpg key


log_step "Add cloudflare gpg key"
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

log_step "Add this repo to your apt repositories"
# Add this repo to your apt repositories
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list

log_step "install cloudflared"
# install cloudflared
sudo apt-get update && sudo apt-get install cloudflared

if [ -n "$CLOUDFLARE_TUNNEL_KEY" ]; then
  if [ -f /etc/systemd/system/cloudflared.service ]; then
    log_step "Removing existing cloudflared service"

    sudo systemctl stop cloudflared || true
    sudo cloudflared service uninstall || true
  fi

  sudo cloudflared service install $CLOUDFLARE_TUNNEL_KEY
  sudo systemctl enable cloudflared
  sudo systemctl restart cloudflared
fi

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

# Section 07:
# The hotspot/captive-portal path needs persisted firewall rules. Preseeding
# the debconf answers prevents the package install from stopping for input.
log_section "07" "Prepare NAT routing for the captive portal"
# Preseed iptables-persistent so the package install stays non-interactive.
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

# Section 08:
# Install the firewall packages after preseeding so the setup remains fully
# unattended during automatic provisioning.
log_section "08" "Install firewall persistence packages"
sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables iptables-persistent

sudo rm -f /var/lib/systemd/rfkill/*
sudo systemctl restart systemd-rfkill.service

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

  sudo pg_ctlcluster "$version" "$name" restart 
done

log_step "Restarting PostgreSQL"
sudo systemctl restart postgresql

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
ZIP_URL="https://github.com/denodo/$GITHUB_DENODO_UTILS"
TARGET_DIR="/home/denodo/"
DENODO_INSTALL="/home/denodo/denodo-install-9"

curl -L "$ZIP_URL" -o $TARGET_DIR/Denodo.Support.Utilities.zip
unzip -o $TARGET_DIR/Denodo.Support.Utilities.zip -d "$TARGET_DIR"
rm -f $TARGET_DIR/Denodo.Support.Utilities.zip

cd $TARGET_DIR/denodo-support-utils/bin/
chmod +x denodo-support

log_step "Download Installer"
./denodo-support -t installer -n denodo-install-9-ga -d /home/denodo -u $DENODO_SUPPORT_CI -s $DENODO_SUPPORT_SECRET
log_step "Download Update$DENODO_UPDATE"
./denodo-support -t update -n $DENODO_UPDATE -d /home/denodo -u $DENODO_SUPPORT_CI -s $DENODO_SUPPORT_SECRET

log_step "Prepare install folder"
cd /home/denodo
unzip -o denodo-install-9-ga.zip 

DENODO_INSTALL="/home/denodo/denodo-install-9"
mkdir "$DENODO_INSTALL/denodo-update"
unzip -q -o "$DENODO_UPDATE.zip" -d "$DENODO_INSTALL/denodo-update"
mv "$DENODO_INSTALL/denodo-update/$DENODO_UPDATE.jar" "$DENODO_INSTALL/denodo-update/denodo-update.jar"

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

log_step "Copy Denodo Lincense: $DENODO_LIC"
DENODO_LIC=${DENODO_LIC:-"denodo-developer-lic-9.lic"}

sudo cp "/boot/firmware/denodo/$DENODO_LIC" "$DENODO_INSTALL/denodo-developer-lic-9.lic"
sudo chown denodo:denodo "$DENODO_INSTALL/denodo-developer-lic-9.lic"
#./installer_cli.sh install
sudo mkdir /opt/denodo-9
sudo chown -R denodo:denodo /opt/denodo-9

log_step "Faking JAVA JRE in Denodo Home"
ln -s "$JAVA_HOME" jre
cd denodo-update
rm -rf jre
mkdir jre
cd jre
ln -s "$JAVA_HOME" jre-linux
cd "$DENODO_INSTALL"

log_step "Start Denodo Install"
./installer_cli.sh install --autoinstaller /boot/firmware/denodo/response_file_9_0.xml | tee -a $LOG

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
change_config "-Xmx" "/opt/denodo-9/conf/vdp/VDBConfiguration.properties" "2048m"
log_step "JAVA Config: Change -XX:ReservedCodeCacheSize= in VDBConfiguration.properties"
change_config "-XX:ReservedCodeCacheSize=" "/opt/denodo-9/conf/vdp/VDBConfiguration.properties" "256m"
log_step "JAVA Config: Change -Xmx in resources/apache-tomcat/conf/tomcat.properties"
change_config "-Xmx" "/opt/denodo-9/resources/apache-tomcat/conf/tomcat.properties" "1024m"

/opt/denodo-9/bin/regenerateFiles.sh

# Section 13:
# The AI SDK lives in its own Git repository. On first install it is cloned;
# on later runs it is refreshed so the workspace matches the remote branch.
log_section "13" "Install Denodo AI SDK"
GITHUB_REPO_URL="https://github.com/denodo/denodo-ai-sdk.git"

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

# Install pyenv to manage the project Python version.
log_step "Installing pyenv"
sudo rm -rf ~/.pyenv
curl -fsSL https://pyenv.run | bash

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

sudo cp -f /opt/denodo-pi/nginx-site.conf /etc/nginx/sites-enabled/default

sudo chmod o+rx /opt
sudo chmod o+rx /opt/denodo-pi
sudo chmod -R o+rx /opt/denodo-pi/www

sudo chgrp -R www-data /opt/denodo-pi/www
sudo chmod -R 750 /opt/denodo-pi/www

sudo usermod -aG www-data www-data
 
log_step "Restarting Nginx" 
sudo systemctl restart nginx
  

# copy service files
log_section "16" "Configuring the different services"
log_step "Installing service files"
for service_file in $INSTALL_DIR/services/*.service ; do
  name=`basename ${service_file}`
  echo "Installing service ${name}"
  sudo cp $INSTALL_DIR/services/${name} /lib/systemd/system/${name}
  sudo chown root /lib/systemd/system/${name}

  sudo systemctl daemon-reload

  # 🔑 critical fix
  sudo systemctl unmask ${name}

  sudo systemctl enable ${name}
done

sudo reboot