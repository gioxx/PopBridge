# PopBridge

Minimal container to move emails from a source mailbox (POP3 or IMAP) into Gmail via SMTP.

Goal: when a message arrives in the old mailbox, the container forwards it to Gmail and, on successful delivery, deletes it from the source mailbox.

## How it works

1. `getmail6` fetches new messages from the source mailbox.
2. Each message is sent via SMTP to the target Gmail account.
3. With `DELETE_AFTER_DELIVERY=true`, successfully delivered messages are deleted from the source mailbox.
4. If delivery fails, the message stays in the source mailbox and is retried in the next polling cycle.

## Required variables

- `SRC_HOST`: source host.
- `SRC_PORT`: source port.
- `SRC_USER`: source username.
- `SRC_PASS`: source password.
- `DST_SMTP_HOST`: destination SMTP host (for example Gmail SMTP).
- `DST_SMTP_PORT`: destination SMTP port.
- `DST_SMTP_USER`: destination SMTP username (typically the Gmail account).
- `DST_SMTP_PASS`: destination SMTP password (typically an app password).

Required variables can be passed as environment variables or as files in `/run/secrets/<VARIABLE_NAME>`.

## Optional variables

- `SRC_PROTOCOL`: `pop3` (default) or `imap`.
- `SRC_SSL`: `true` (default) or `false`.
- `SRC_STARTTLS`: `false` (default) or `true` (not compatible with `SRC_SSL=true`).
- `DST_SMTP_STARTTLS`: `true` (default) or `false`.
- `DELETE_AFTER_DELIVERY`: `true` (default) or `false`.
- `POLL_SECONDS`: polling interval in seconds (default `120`).
- `STATE_DIR`: getmail state directory (default `/var/lib/forwarder`).
- `LOG_DIR`: runtime log directory (default `/var/log/forwarder`).

## Build

```bash
docker build -t popbridge:latest .
```

## Docker Compose (profiles)

The repository includes:
- `docker-compose.yml` with two ready-to-use profiles: `pop3` and `imap`
- `sample.env` with all required variables and placeholders

Compose maps profile-specific source variables to runtime canonical variables:
- POP3 profile reads `SRC_POP3_*`
- IMAP profile reads `SRC_IMAP_*`
- destination remains `DST_SMTP_*`

Run POP3 profile:

```bash
docker compose --profile pop3 up -d --build
```

Run IMAP profile:

```bash
docker compose --profile imap up -d --build
```

Stop and remove:

```bash
docker compose --profile pop3 down
docker compose --profile imap down
```

## POP3 run example (POP3S source)

```bash
docker run -d --name popbridge-pop3 \
  -e SRC_PROTOCOL=pop3 \
  -e SRC_HOST=pop.provider.tld \
  -e SRC_PORT=995 \
  -e SRC_USER=old-mailbox@provider.tld \
  -e SRC_PASS='source-password' \
  -e SRC_SSL=true \
  -e SRC_STARTTLS=false \
  -e DST_SMTP_HOST=smtp.gmail.com \
  -e DST_SMTP_PORT=587 \
  -e DST_SMTP_USER=your.account@gmail.com \
  -e DST_SMTP_PASS='gmail-app-password' \
  -e DST_SMTP_STARTTLS=true \
  -e DELETE_AFTER_DELIVERY=true \
  -e POLL_SECONDS=120 \
  -v popbridge-state:/var/lib/forwarder \
  -v popbridge-logs:/var/log/forwarder \
  popbridge:latest
```

## IMAP run example (IMAPS source)

```bash
docker run -d --name popbridge-imap \
  -e SRC_PROTOCOL=imap \
  -e SRC_HOST=imap.provider.tld \
  -e SRC_PORT=993 \
  -e SRC_USER=old-mailbox@provider.tld \
  -e SRC_PASS='source-password' \
  -e SRC_SSL=true \
  -e SRC_STARTTLS=false \
  -e DST_SMTP_HOST=smtp.gmail.com \
  -e DST_SMTP_PORT=587 \
  -e DST_SMTP_USER=your.account@gmail.com \
  -e DST_SMTP_PASS='gmail-app-password' \
  -e DST_SMTP_STARTTLS=true \
  -e DELETE_AFTER_DELIVERY=true \
  -e POLL_SECONDS=120 \
  -v popbridge-state:/var/lib/forwarder \
  -v popbridge-logs:/var/log/forwarder \
  popbridge:latest
```

## Useful logs

- `${LOG_DIR}/runner.log`: polling cycle result.
- `${LOG_DIR}/getmail-run.log`: full `getmail` output.
- `${LOG_DIR}/getmail.log`: internal `getmailrc` logfile.

Example:

```bash
docker logs -f popbridge-pop3
```

## Operational notes

- For Gmail, you will usually need an app password on the destination account.
- Keep state/log volumes persistent to avoid duplicates after restart.
- For a dry-run phase without deletion from source, set `DELETE_AFTER_DELIVERY=false`.
