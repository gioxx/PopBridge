#!/bin/sh

read_secret_or_env() {
  # Usage: read_secret_or_env VAR_NAME
  # If /run/secrets/VAR_NAME exists, read it; otherwise read env var.
  name="$1"
  secret_file="/run/secrets/${name}"

  if [ -f "$secret_file" ]; then
    val="$(cat "$secret_file")"
  else
    val="$(printenv "$name" 2>/dev/null || true)"
  fi

  if [ -z "$val" ]; then
    echo "Missing required variable/secret: ${name}" >&2
    exit 1
  fi

  export "${name}=${val}"
}

bool_is_true() {
  # Treat "true", "1", "yes" as true
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [ "$v" = "true" ] || [ "$v" = "1" ] || [ "$v" = "yes" ]
}
