#!/bin/sh
set -eu

# -----------------------------
# Helpers
# -----------------------------
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

lower() {
  echo "${1:-}" | tr '[:upper:]' '[:lower:]'
}

# -----------------------------
# Required inputs
# -----------------------------
read_secret_or_env SRC_HOST
read_secret_or_env SRC_PORT
read_secret_or_env SRC_USER
read_secret_or_env SRC_PASS

read_secret_or_env DST_SMTP_HOST
read_secret_or_env DST_SMTP_PORT
read_secret_or_env DST_SMTP_USER
read_secret_or_env DST_SMTP_PASS

# -----------------------------
# Optional inputs
# -----------------------------
STATE_DIR="${STATE_DIR:-/var/lib/forwarder}"
LOG_DIR="${LOG_DIR:-/var/log/forwarder}"
POLL_SECONDS="${POLL_SECONDS:-120}"

DELETE_AFTER_DELIVERY="${DELETE_AFTER_DELIVERY:-true}"

SRC_PROTOCOL="$(lower "${SRC_PROTOCOL:-pop3}")"
SRC_SSL="${SRC_SSL:-true}"
SRC_STARTTLS="${SRC_STARTTLS:-false}"

DST_SMTP_STARTTLS="${DST_SMTP_STARTTLS:-true}"

mkdir -p "$STATE_DIR" "$LOG_DIR" /etc/forwarder

# -----------------------------
# Build getmail config
# -----------------------------
RETRIEVER_TYPE=""
RETRIEVER_EXTRA=""

case "$SRC_PROTOCOL" in
  pop3)
    RETRIEVER_TYPE="SimplePOP3Retriever"
    if bool_is_true "$SRC_SSL"; then
      RETRIEVER_TYPE="SimplePOP3SSLRetriever"
    fi
    ;;
  imap)
    RETRIEVER_TYPE="SimpleIMAPRetriever"
    if bool_is_true "$SRC_SSL"; then
      RETRIEVER_TYPE="SimpleIMAPSSLRetriever"
    fi
    ;;
  *)
    echo "Invalid SRC_PROTOCOL: ${SRC_PROTOCOL}. Supported: pop3, imap" >&2
    exit 1
    ;;
esac

if bool_is_true "$SRC_SSL" && bool_is_true "$SRC_STARTTLS"; then
  echo "SRC_SSL and SRC_STARTTLS cannot both be true" >&2
  exit 1
fi

# STARTTLS requires non-SSL retrievers.
if ! bool_is_true "$SRC_SSL" && bool_is_true "$SRC_STARTTLS"; then
  RETRIEVER_EXTRA="use_tls = true"
fi

DELETE_OPT="delete = true"
if ! bool_is_true "$DELETE_AFTER_DELIVERY"; then
  DELETE_OPT="delete = false"
fi

# getmail stores UIDL/state in this location.
RC_FILE="/etc/forwarder/getmailrc"
SMTP_SENDER="/etc/forwarder/smtp_send.py"

cat > "$SMTP_SENDER" <<'PYEOF'
#!/usr/bin/env python3
import os
import sys
import smtplib
import ssl

def env(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        raise RuntimeError(f"Missing env: {name}")
    return v

def main() -> int:
    raw = sys.stdin.buffer.read()

    host = env("DST_SMTP_HOST")
    port = int(env("DST_SMTP_PORT"))
    user = env("DST_SMTP_USER")
    password = env("DST_SMTP_PASS")

    starttls = os.environ.get("DST_SMTP_STARTTLS", "true").lower() in ("true", "1", "yes")

    # Envelope sender/recipient:
    # Keep a stable envelope sender (the Gmail account) to avoid rejections.
    mail_from = user
    rcpt_to = [user]  # deliver into the target Gmail mailbox

    if starttls:
        with smtplib.SMTP(host, port, timeout=60) as s:
            s.ehlo()
            s.starttls(context=ssl.create_default_context())
            s.ehlo()
            s.login(user, password)
            s.sendmail(mail_from, rcpt_to, raw)
    else:
        # For completeness; Gmail normally uses STARTTLS on 587
        with smtplib.SMTP_SSL(host, port, timeout=60, context=ssl.create_default_context()) as s:
            s.login(user, password)
            s.sendmail(mail_from, rcpt_to, raw)

    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        sys.stderr.write(str(e) + "\n")
        raise SystemExit(2)
PYEOF

chmod +x "$SMTP_SENDER"

# getmail delivery command: run smtp_send.py with message on stdin.
# Use getmail MDA_external to pipe messages to the SMTP sender script.
cat > "$RC_FILE" <<EOF
[retriever]
type = ${RETRIEVER_TYPE}
server = ${SRC_HOST}
port = ${SRC_PORT}
username = ${SRC_USER}
password = ${SRC_PASS}
${RETRIEVER_EXTRA}
${DELETE_OPT}
timeout = 60

[destination]
type = MDA_external
path = ${SMTP_SENDER}

[options]
read_all = false
# Persist state/UIDL to avoid duplicates across restarts
statefile = ${STATE_DIR}/getmail.state
# Keep logs useful for troubleshooting while avoiding secret-heavy verbosity.
logfile = ${LOG_DIR}/getmail.log
EOF

echo "Forwarder starting: protocol=${SRC_PROTOCOL}, source=${SRC_USER}, destination=${DST_SMTP_USER}"
echo "Transport: src_ssl=${SRC_SSL}, src_starttls=${SRC_STARTTLS}, dst_starttls=${DST_SMTP_STARTTLS}"
echo "Polling every ${POLL_SECONDS}s; delete_after_delivery=${DELETE_AFTER_DELIVERY}; state_dir=${STATE_DIR}"

RUNNER_LOG="${LOG_DIR}/runner.log"
GETMAIL_RUN_LOG="${LOG_DIR}/getmail-run.log"

# -----------------------------
# Poll loop
# -----------------------------
while true; do
  # Run one fetch cycle.
  # If it fails, we log and retry next cycle.
  # Messages remain on source if delivery failed; with delete=true, successful delivery removes from source.
  if ! getmail --rcfile "$RC_FILE" >>"$GETMAIL_RUN_LOG" 2>&1; then
    echo "$(date -Iseconds) getmail run failed (will retry)" >> "$RUNNER_LOG"
  else
    echo "$(date -Iseconds) getmail run OK" >> "$RUNNER_LOG"
  fi

  sleep "$POLL_SECONDS"
done
