#!/bin/bash
set -euo pipefail

# Optional logging helpers
log() {
  echo -e "[KONG ENTRYPOINT] $*" >&2
}

# Load environment overrides
if [[ -f /etc/supabase/conf.env ]]; then
  log "Loading config from /etc/supabase/conf.env"
  set -a
  source /etc/supabase/conf.env
  set +a
else
  log "No /etc/supabase/conf.env found. Proceeding without it."
fi

# Ensure Kong config directory exists
mkdir -p /etc/kong

# Substitute environment variables into base.kong.yml
if [[ -f /etc/kong/base.kong.yml ]]; then
  log "Rendering /etc/kong/gen.kong.yml from base template"
  envsubst < /etc/kong/base.kong.yml > /etc/kong/gen.kong.yml
else
  log "Missing /etc/kong/base.kong.yml" && exit 1
fi

# Start Kong
log "Starting Kong Gateway..."
exec kong start