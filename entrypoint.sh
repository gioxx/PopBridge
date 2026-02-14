#!/bin/sh
set -eu

. /scripts/lib.sh

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
SMTP_SENDER="/scripts/smtp_send.py"

# Build getmailrc for the current runtime configuration.
/scripts/render_getmailrc.sh

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
