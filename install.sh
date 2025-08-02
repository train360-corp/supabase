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

function install_package() {
  info "installing package"
  TMP_DEB="/tmp/supabase.deb"
  wget -O "$TMP_DEB" "https://github.com/train360-corp/supabase/releases/download/v__VERSION__/supabase___VERSION___$(dpkg --print-architecture).deb"
  apt install -y -f "$TMP_DEB"
  ok "package installed"
}

function install_postgres() {
  postgresql_major=15
  postgresql_release=${postgresql_major}.1
  sfcgal_release=1.3.10
  postgis_release=3.3.2
  pgrouting_release=3.4.1
  pgtap_release=1.2.0
  pg_cron_release=1.6.2
  pgaudit_release=1.7.0
  pgsql_http_release=1.5.0
  plpgsql_check_release=2.2.5
  pg_safeupdate_release=1.4
  timescaledb_release=2.9.1
  wal2json_release=2_5
  pljava_release=1.6.4
  plv8_release=3.1.5
  pg_plan_filter_release=5081a7b5cb890876e67d8e7486b6a64c38c9a492
  pg_net_release=0.7.1
  rum_release=1.3.13
  pg_hashids_release=cd0e1b31d52b394a0df64079406a14a4f7387cd6
  libsodium_release=1.0.18
  pgsodium_release=3.1.6
  pg_graphql_release=1.5.11
  pg_stat_monitor_release=1.1.1
  pg_jsonschema_release=0.1.4
  pg_repack_release=1.4.8
  vault_release=0.2.8
  groonga_release=12.0.8
  pgroonga_release=2.4.0
  wrappers_release=0.5.0
  hypopg_release=1.3.1
  pgvector_release=0.4.0
  pg_tle_release=1.3.2
  index_advisor_release=0.2.0
  supautils_release=2.2.0
  wal_g_release=2.0.1

  apt update -y && apt install -y \
    git \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
    sudo \
    && apt clean

  adduser --system  --home /var/lib/postgresql --no-create-home --shell /bin/bash --group --gecos "PostgreSQL administrator" postgres
  adduser --system  --no-create-home --shell /bin/bash --group  wal-g
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux \
  --init none \
  --no-confirm \
  --extra-conf "substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com" \
  --extra-conf "trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="

  PATH="${PATH}:/nix/var/nix/profiles/default/bin"

  git clone https://github.com/supabase/postgres.git /tmp/supabase-postgres
  cd /tmp/supabase-postgres

  nix profile install .#psql_15/bin
  nix store gc

  cd /

  mkdir -p /usr/lib/postgresql/bin \
      /usr/lib/postgresql/share/postgresql \
      /usr/share/postgresql \
      /var/lib/postgresql \
      && chown -R postgres:postgres /usr/lib/postgresql \
      && chown -R postgres:postgres /var/lib/postgresql \
      && chown -R postgres:postgres /usr/share/postgresql

  # Create symbolic links
  ln -s /nix/var/nix/profiles/default/bin/* /usr/lib/postgresql/bin/ \
      && ln -s /nix/var/nix/profiles/default/bin/* /usr/bin/ \
      && chown -R postgres:postgres /usr/bin

  # Create symbolic links for PostgreSQL shares
  ln -s /nix/var/nix/profiles/default/share/postgresql/* /usr/lib/postgresql/share/postgresql/
  ln -s /nix/var/nix/profiles/default/share/postgresql/* /usr/share/postgresql/
  chown -R postgres:postgres /usr/lib/postgresql/share/postgresql/
  chown -R postgres:postgres /usr/share/postgresql/

  # Create symbolic links for contrib directory
  mkdir -p /usr/lib/postgresql/share/postgresql/contrib \
      && find /nix/var/nix/profiles/default/share/postgresql/contrib/ -mindepth 1 -type d -exec sh -c 'for dir do ln -s "$dir" "/usr/lib/postgresql/share/postgresql/contrib/$(basename "$dir")"; done' sh {} + \
      && chown -R postgres:postgres /usr/lib/postgresql/share/postgresql/contrib/

  chown -R postgres:postgres /usr/lib/postgresql

  ln -sf /usr/lib/postgresql/share/postgresql/timezonesets /usr/share/postgresql/timezonesets

  apt-get update && apt-get install -y --no-install-recommends tzdata

  ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime
  dpkg-reconfigure --frontend noninteractive tzdata

  apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      checkinstall \
      cmake

  PGDATA=/var/lib/postgresql/data

  ####################
  # setup-wal-g.yml
  ####################
  cd /tmp/supabase-postgres

  nix profile install .#wal-g-3 && ln -s /nix/var/nix/profiles/default/bin/wal-g-3 /tmp/wal-g

  nix store gc

  cd /

  # ####################
  # # Download gosu for easy step-down from root
  # ####################

  # Install dependencies
  apt-get update && apt-get install -y --no-install-recommends \
     gnupg \
     ca-certificates \
     && rm -rf /var/lib/apt/lists/*

  GOSU_VERSION=1.16
  GOSU_GPG_KEY=B42F6819007F00F88E364FD4036A9C25BF357DD4
  curl -fsSL "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$TARGETARCH" -o /usr/local/bin/gosu
  curl -fsSL "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$TARGETARCH.asc" -o /usr/local/bin/gosu.asc

  # Verify checksum
  gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys $GOSU_GPG_KEY && \
      gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu && \
      gpgconf --kill all && \
      chmod +x /usr/local/bin/gosu

  # ####################
  # # Build final image
  # ####################
  id postgres || (echo "postgres user does not exist" && exit 1)
  # # Setup extensions
  cp /tmp/wal-g /usr/local/bin/wal-g
  chmod +x /usr/local/bin/wal-g

  # # Initialise configs
  mkdir -p \
    /etc/postgresql \
    /etc/postgresql-custom \
    /usr/lib/postgresql/bin \
    /home/postgres

  cp /tmp/supabase-postgres/ansible/files/postgresql_config/postgresql.conf.j2 /etc/postgresql/postgresql.conf
  cp /tmp/supabase-postgres/ansible/files/postgresql_config/pg_hba.conf.j2 /etc/postgresql/pg_hba.conf
  cp /tmp/supabase-postgres/ansible/files/postgresql_config/pg_ident.conf.j2 /etc/postgresql/pg_ident.conf
  cp /tmp/supabase-postgres/ansible/files/postgresql_config/postgresql-stdout-log.conf /etc/postgresql/logging.conf
  cp /tmp/supabase-postgres/ansible/files/postgresql_config/supautils.conf.j2 /etc/postgresql-custom/supautils.conf
  cp -r /tmp/supabase-postgres/ansible/files/postgresql_extension_custom_scripts /etc/postgresql-custom/extension-custom-scripts
  cp /tmp/supabase-postgres/ansible/files/pgsodium_getkey_urandom.sh.j2 /usr/lib/postgresql/bin/pgsodium_getkey.sh
  cp /tmp/supabase-postgres/ansible/files/postgresql_config/custom_read_replica.conf.j2 /etc/postgresql-custom/read-replica.conf
  cp /tmp/supabase-postgres/ansible/files/postgresql_config/custom_walg.conf.j2 /etc/postgresql-custom/wal-g.conf
  cp /tmp/supabase-postgres/ansible/files/walg_helper_scripts/wal_fetch.sh /home/postgres/wal_fetch.sh
  cp /tmp/supabase-postgres/ansible/files/walg_helper_scripts/wal_change_ownership.sh /root/wal_change_ownership.sh

  chown -R postgres:postgres \
    /etc/postgresql \
    /etc/postgresql-custom \
    /usr/lib/postgresql/bin \
    /home/postgres

  chown root:root /root/wal_change_ownership.sh

  sed -i \
    -e "s|#unix_socket_directories = '/tmp'|unix_socket_directories = '/var/run/postgresql'|g" \
    -e "s|#session_preload_libraries = ''|session_preload_libraries = 'supautils'|g" \
    -e "s|#include = '/etc/postgresql-custom/supautils.conf'|include = '/etc/postgresql-custom/supautils.conf'|g" \
    -e "s|#include = '/etc/postgresql-custom/wal-g.conf'|include = '/etc/postgresql-custom/wal-g.conf'|g" /etc/postgresql/postgresql.conf && \
    echo "cron.database_name = 'postgres'" >> /etc/postgresql/postgresql.conf && \
    echo "pgsodium.getkey_script= '/usr/lib/postgresql/bin/pgsodium_getkey.sh'" >> /etc/postgresql/postgresql.conf && \
    echo "vault.getkey_script= '/usr/lib/postgresql/bin/pgsodium_getkey.sh'" >> /etc/postgresql/postgresql.conf && \
    echo 'auto_explain.log_min_duration = 10s' >> /etc/postgresql/postgresql.conf && \
    usermod -aG postgres wal-g && \
    mkdir -p /etc/postgresql-custom && \
    chown postgres:postgres /etc/postgresql-custom

  # # Include schema migrations
  cp /tmp/supabase-postgres/migrations/db /docker-entrypoint-initdb.d/
  cp /tmp/supabase-postgres/ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql /docker-entrypoint-initdb.d/init-scripts/00-schema.sql
  cp /tmp/supabase-postgres/ansible/files/stat_extension.sql /docker-entrypoint-initdb.d/migrations/00-extension.sql

  # # Add upstream entrypoint script
#  ADD --chmod=0755 \
#      https://github.com/docker-library/postgres/raw/master/15/bullseye/docker-entrypoint.sh \
#      /usr/local/bin/docker-entrypoint.sh

  mkdir -p /var/run/postgresql && chown postgres:postgres /var/run/postgresql

#  ENTRYPOINT ["docker-entrypoint.sh"]

#  HEALTHCHECK --interval=2s --timeout=2s --retries=10 CMD pg_isready -U postgres -h localhost
#  STOPSIGNAL SIGINT
#  EXPOSE 5432

  POSTGRES_HOST=/var/run/postgresql
  POSTGRES_USER=supabase_admin
  POSTGRES_DB=postgres
  apt-get update && apt-get install -y --no-install-recommends \
      locales \
      && rm -rf /var/lib/apt/lists/* && \
      localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
      && localedef -i C -c -f UTF-8 -A /usr/share/locale/locale.alias C.UTF-8
  echo "C.UTF-8 UTF-8" > /etc/locale.gen && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen
  LANG=en_US.UTF-8
  LANGUAGE=en_US:en
  LC_ALL=en_US.UTF-8
  LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
  mkdir -p /usr/share/postgresql/extension/ && \
      ln -s /usr/lib/postgresql/bin/pgsodium_getkey.sh /usr/share/postgresql/extension/pgsodium_getkey && \
      chmod +x /usr/lib/postgresql/bin/pgsodium_getkey.sh
#  CMD ["postgres", "-D", "/etc/postgresql"]
}

function install() {
  install_kong
  install_postgres
  install_package
}

install