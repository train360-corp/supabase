#!/bin/bash
set -euo pipefail

# System
source /etc/os-release
ARCH="$(uname -m)"
SUPPORTED_ARCHS=("x86_64" "aarch64")
SUPPORTED_DISTROS=("debian" "ubuntu")

# Colors
RED="\033[1;31m"
BLUE="\033[1;34m"
RESET="\033[0m"
GREEN="\033[1;32m"

ok() {
  echo -e "${GREEN}[OK   ] $*${RESET}"
}

error() {
  echo -e "${RED}[ERROR] $*${RESET}" >&2
  exit 1
}

info() {
  echo -e "${BLUE}[INFO ] $*${RESET}"
}

# Must run as root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run with sudo or as root."
fi

# Check supported distro
IS_DISTRO_SUPPORTED=0
for d in "${SUPPORTED_DISTROS[@]}"; do
  if [[ "$ID" == "$d" ]]; then
    IS_DISTRO_SUPPORTED=1
    info "Linux Distro: $ID"
    break
  fi
done
[[ $IS_DISTRO_SUPPORTED -eq 1 ]] || error "Linux Distro Unsupported: $ID"

# Check supported arch
IS_ARCH_SUPPORTED=0
for a in "${SUPPORTED_ARCHS[@]}"; do
  if [[ "$ARCH" == "$a" ]]; then
    IS_ARCH_SUPPORTED=1
    info "Architecture: $ARCH"
    break
  fi
done
[[ $IS_ARCH_SUPPORTED -eq 1 ]] || error "Architecture Unsupported: $ARCH"

# Install config
function install_config() {
  info "writing config file"

  mkdir -p /etc/supabase || error "failed to create /etc/supabase"

  DASHBOARD_USERNAME="admin"
  DASHBOARD_PASSWORD=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 64)

  cat > /etc/supabase/conf.env <<EOF
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
EOF

  chmod 600 /etc/supabase/conf.env
  ok "wrote config file to /etc/supabase/conf.env"

  info "writing env-injecting wrapper script..."

  cat > /usr/local/bin/with-supabase-config <<'WRAPPER'
#!/bin/bash
set -a  # Export all variables
source /etc/supabase/conf.env
set +a

exec "$@"
WRAPPER

  chmod +x /usr/local/bin/with-supabase-config
  ok "Created wrapper: /usr/local/bin/with-supabase-config"
}

# Install Kong
install_kong() {

  KONG_CONFIG_URL="https://raw.githubusercontent.com/supabase/supabase/03aa5c34740e63a7af09c46a749a4506985363dc/docker/volumes/api/kong.yml"

  info "installing Kong"
  if [[ "$ID" == "debian" || "$ID" == "ubuntu" ]]; then
    codename=$(lsb_release -sc 2>/dev/null || grep -oP 'VERSION_CODENAME=\K\w+' /etc/os-release)
    curl -1sLf "https://packages.konghq.com/public/gateway-311/gpg.CF9CDA9D288571F9.key" |
      gpg --dearmor | tee /usr/share/keyrings/kong-gateway-311-archive-keyring.gpg > /dev/null
    curl -1sLf "https://packages.konghq.com/public/gateway-311/config.deb.txt?distro=$ID&codename=$codename" |
      tee /etc/apt/sources.list.d/kong-gateway-311.list > /dev/null
    apt-get update
    apt-get install -y kong-enterprise-edition=3.11.0.2
  elif [[ "$ID" == "rhel" ]]; then
    rhelver=$(rpm --eval '%{rhel}')
    curl -1sLf "https://packages.konghq.com/public/gateway-311/config.rpm.txt?distro=el&codename=$rhelver" |
      tee /etc/yum.repos.d/kong-gateway-311.repo
    yum -q makecache -y --disablerepo='*' --enablerepo='kong-gateway-311'
    yum install -y kong-enterprise-edition-3.11.0.2
  else
    error "Linux distro unsupported by Kong: $ID"
  fi

  mkdir -p /etc/kong || error "failed to create /etc/kong"
  curl -sLo /etc/kong/base.kong.yml "$KONG_CONFIG_URL"
  chown kong:0 /etc/kong/base.kong.yml \
     && chown kong:0 /usr/local/bin/kong \
     && chown -R kong:0 /usr/local/kong \
     && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit \
     && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/lua \
     && ln -s /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx \
     && kong version

  ok "Kong installed"
}

install_config

install_kong