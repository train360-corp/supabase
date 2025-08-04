#!/bin/bash
set -euo pipefail

# check that PGDATA is set
if [[ -z "${PGDATA:-}" ]]; then
  echo "ERROR: PGDATA environment variable must be set."
  exit 1
fi

# ensure PGDATA directory exists and is owned by postgres
mkdir -p "$PGDATA"
chown -R postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"

if [ -s "$PGDATA/PG_VERSION" ]; then
  DATABASE_ALREADY_EXISTS=true
else
  DATABASE_ALREADY_EXISTS=""
fi

# start socket-only postgresql server for setting up or running scripts
# all arguments will be passed along as arguments to `postgres` (via pg_ctl)
function temp_server_start() {
	if [ "$1" = 'postgres' ]; then
		shift
	fi

	# internal start of server in order to allow setup using psql client
	# does not listen on external TCP/IP and waits until start finishes
	set -- "$@" -c listen_addresses='' -p "${PGPORT:-5432}"

	PGUSER="${PGUSER:-$POSTGRES_USER}" \
	pg_ctl -D "$PGDATA" \
		-o "$(printf '%q ' "$@")" \
		-w start
}

function temp_server_stop() {
  PGUSER="${PGUSER:-postgres}" \
  pg_ctl -D "$PGDATA" -m fast -w stop
}

# Execute sql script, passed via stdin (or -f flag of pqsl)
# usage: process_sql [psql-cli-args]
#    ie: process_sql --dbname=mydb <<<'INSERT ...'
#    ie: process_sql -f my-file.sql
#    ie: process_sql <my-file.sql
process_sql() {
	local query_runner=( psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --no-password --no-psqlrc )
	if [ -n "$POSTGRES_DB" ]; then
		query_runner+=( --dbname "$POSTGRES_DB" )
	fi

	PGHOST= PGHOSTADDR= "${query_runner[@]}" "$@"
}

function setup_db() {
	local dbAlreadyExists
	dbAlreadyExists="$(
		POSTGRES_DB= process_sql --dbname postgres --set db="$POSTGRES_DB" --tuples-only <<-'EOSQL'
			SELECT 1 FROM pg_database WHERE datname = :'db' ;
		EOSQL
	)"
	if [ -z "$dbAlreadyExists" ]; then
		POSTGRES_DB= process_sql --dbname postgres --set db="$POSTGRES_DB" <<-'EOSQL'
			CREATE DATABASE :"db" ;
		EOSQL
		printf '\n'
	fi
}

# usage: process_init_files [file [file [...]]]
#    ie: process_init_files /always-initdb.d/*
# process initializer files, based on file extensions and permissions
function process_init_files() {

	# psql here for backwards compatibility "${psql[@]}"
	psql=( process_sql )

	printf '\n'
	local f
	for f; do
		case "$f" in
			*.sh)
				if [ -x "$f" ]; then
					printf '%s: running %s\n' "$0" "$f"
					"$f"
				else
					printf '%s: sourcing %s\n' "$0" "$f"
					. "$f"
				fi
				;;
			*.sql)     printf '%s: running %s\n' "$0" "$f"; process_sql -f "$f"; printf '\n' ;;
			*.sql.gz)  printf '%s: running %s\n' "$0" "$f"; gunzip -c "$f" | process_sql; printf '\n' ;;
			*.sql.xz)  printf '%s: running %s\n' "$0" "$f"; xzcat "$f" | process_sql; printf '\n' ;;
			*.sql.zst) printf '%s: running %s\n' "$0" "$f"; zstd -dc "$f" | process_sql; printf '\n' ;;
			*)         printf '%s: ignoring %s\n' "$0" "$f" ;;
		esac
		printf '\n'
	done
}

if [ -z "${DATABASE_ALREADY_EXISTS:-}" ]; then

  POSTGRES_USER="postgres"

  echo "[entrypoint.sh] INITIALIZING DB..."

  # initialize the database directory
  LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive /usr/local/bin/with-supabase-config initdb -D /var/lib/postgresql/data

  # PGPASSWORD is required for psql when authentication is required for 'local' connections via pg_hba.conf and is otherwise harmless
  # e.g. when '--auth=md5' or '--auth-local=md5' is used in POSTGRES_INITDB_ARGS
  export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
  temp_server_start "$@"

  echo "[entrypoint.sh] SETTING UP DB..."
  setup_db

  echo "[entrypoint.sh] PROCESSING INIT FILES..."
  process_init_files /etc/postgres/initdb.d/*

  temp_server_stop
  unset PGPASSWORD

  echo "[entrypoint.sh] PostgreSQL init process complete; ready for start up."
fi

# Exec the passed command (usually `postgres`)
exec "$@"