#!/bin/sh
set -eu

if [ -z "${RC_FILE:-}" ]; then
  echo "Missing required env: RC_FILE" >&2
  exit 1
fi

if [ -z "${SMTP_SENDER:-}" ]; then
  echo "Missing required env: SMTP_SENDER" >&2
  exit 1
fi

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
# Persist state/UIDL to avoid duplicates across restarts.
statefile = ${STATE_DIR}/getmail.state
# Keep logs useful for troubleshooting while avoiding secret-heavy verbosity.
logfile = ${LOG_DIR}/getmail.log
EOF
