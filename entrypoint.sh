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
BACKLOG_LOG_EVERY="${BACKLOG_LOG_EVERY:-10}"

case "$BACKLOG_LOG_EVERY" in
  ''|*[!0-9]*)
    echo "Invalid BACKLOG_LOG_EVERY: ${BACKLOG_LOG_EVERY}. Use a non-negative integer." >&2
    exit 1
    ;;
esac

DELETE_AFTER_DELIVERY="${DELETE_AFTER_DELIVERY:-true}"
SRC_SSL="${SRC_SSL:-true}"
SRC_STARTTLS="${SRC_STARTTLS:-false}"

DST_SMTP_STARTTLS="${DST_SMTP_STARTTLS:-true}"

mkdir -p "$STATE_DIR" "$LOG_DIR" /etc/forwarder

# -----------------------------
# Build getmail config
# -----------------------------
RETRIEVER_EXTRA=""
RETRIEVER_TYPE="SimplePOP3Retriever"
if bool_is_true "$SRC_SSL"; then
  RETRIEVER_TYPE="SimplePOP3SSLRetriever"
fi

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
export RC_FILE SMTP_SENDER RETRIEVER_TYPE RETRIEVER_EXTRA DELETE_OPT
export SRC_HOST SRC_PORT SRC_USER SRC_PASS STATE_DIR LOG_DIR
/scripts/render_getmailrc.sh

echo "Forwarder starting: source=${SRC_USER}, destination=${DST_SMTP_USER}"
echo "Transport: src_ssl=${SRC_SSL}, src_starttls=${SRC_STARTTLS}, dst_starttls=${DST_SMTP_STARTTLS}"
echo "Polling every ${POLL_SECONDS}s; delete_after_delivery=${DELETE_AFTER_DELIVERY}; state_dir=${STATE_DIR}"

RUNNER_LOG="${LOG_DIR}/runner.log"
GETMAIL_RUN_LOG="${LOG_DIR}/getmail-run.log"
STATE_FILE="${STATE_DIR}/getmail.state"
SOURCE_COUNT_SCRIPT="/scripts/source_mailbox_count.py"
CYCLE_COUNT=0

echo "$(date -Iseconds) startup: state_file=${STATE_FILE}" >> "$RUNNER_LOG"
if [ -f "$STATE_FILE" ]; then
  echo "$(date -Iseconds) startup: existing state detected, bridge mode resumes from known UIDLs" >> "$RUNNER_LOG"
else
  echo "$(date -Iseconds) startup: no state file detected, initial run may migrate existing messages from source" >> "$RUNNER_LOG"
fi

if SOURCE_COUNT="$("$SOURCE_COUNT_SCRIPT" 2>>"$RUNNER_LOG")"; then
  echo "$(date -Iseconds) startup: source mailbox currently reports ${SOURCE_COUNT} message(s)" >> "$RUNNER_LOG"
  if [ ! -f "$STATE_FILE" ] && bool_is_true "$DELETE_AFTER_DELIVERY"; then
    echo "$(date -Iseconds) startup: initial migration mode active (delete_after_delivery=true)" >> "$RUNNER_LOG"
  fi
else
  echo "$(date -Iseconds) startup: unable to estimate source message count (continuing)" >> "$RUNNER_LOG"
fi

# -----------------------------
# Poll loop
# -----------------------------
while true; do
  CYCLE_COUNT=$((CYCLE_COUNT + 1))

  # Run one fetch cycle.
  # If it fails, we log and retry next cycle.
  # Messages remain on source if delivery failed; with delete=true, successful delivery removes from source.
  if ! getmail --rcfile "$RC_FILE" >>"$GETMAIL_RUN_LOG" 2>&1; then
    echo "$(date -Iseconds) getmail run failed (will retry)" >> "$RUNNER_LOG"
  else
    echo "$(date -Iseconds) getmail run OK" >> "$RUNNER_LOG"
  fi

  if [ "$BACKLOG_LOG_EVERY" -gt 0 ] && [ $((CYCLE_COUNT % BACKLOG_LOG_EVERY)) -eq 0 ]; then
    if SOURCE_COUNT="$("$SOURCE_COUNT_SCRIPT" 2>>"$RUNNER_LOG")"; then
      echo "$(date -Iseconds) progress: cycle=${CYCLE_COUNT}, source mailbox reports ${SOURCE_COUNT} message(s)" >> "$RUNNER_LOG"
    else
      echo "$(date -Iseconds) progress: cycle=${CYCLE_COUNT}, unable to estimate source message count" >> "$RUNNER_LOG"
    fi
  fi

  sleep "$POLL_SECONDS"
done
