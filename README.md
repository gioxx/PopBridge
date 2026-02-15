# PopBridge

> [!WARNING]  
> Experimental project (testing phase): this bridge is still under active testing and does not yet behave reliably in every scenario. PRs, issue reports, and suggestions are very welcome.

Minimal POP3-to-Gmail bridge container.

Goal: when a message arrives in the old POP3 mailbox, the container forwards it to Gmail and, on successful delivery, deletes it from the source mailbox.

## Why this project exists (and why POP3-only)

Google announced that, starting January 2026, Gmail no longer supports continuous POP fetching from third-party accounts in the web UI ("Check mail from other accounts") and Gmailify.

Official Google documentation:
- https://support.google.com/mail/answer/16604719?hl=en
- https://support.google.com/mail/answer/21289?hl=en

PopBridge focuses only on POP3 because the goal is to replicate the historical Gmail POP import/collection workflow for external mailboxes.

## How it works

1. `getmail6` fetches messages from the POP3 source mailbox.
2. Each message is sent via SMTP to the target Gmail account.
3. With `DELETE_AFTER_DELIVERY=true`, successfully delivered messages are deleted from source.
4. If delivery fails, the message remains on source and is retried on the next cycle.

## Project layout

- `entrypoint.sh`: runtime orchestration, env validation, and polling loop.
- `scripts/lib.sh`: shared shell helpers.
- `scripts/render_getmailrc.sh`: renders runtime `getmailrc`.
- `scripts/smtp_send.py`: SMTP delivery command used by `getmail`.
- `scripts/source_mailbox_count.py`: startup/progress POP3 mailbox size estimator.

## Required variables

- `SRC_HOST`: POP3 source host.
- `SRC_PORT`: POP3 source port.
- `SRC_USER`: POP3 source username.
- `SRC_PASS`: POP3 source password.
- `DST_SMTP_HOST`: destination SMTP host (for example `smtp.gmail.com`).
- `DST_SMTP_PORT`: destination SMTP port.
- `DST_SMTP_USER`: destination SMTP username (SMTP auth identity).
- `DST_SMTP_PASS`: destination SMTP password (typically an app password).

Required variables can be passed as environment variables or as files in `/run/secrets/<VARIABLE_NAME>`.

## Optional variables

- `SRC_SSL`: `true` (default) or `false`.
- `SRC_STARTTLS`: `false` (default) or `true` (not compatible with `SRC_SSL=true`).
- `DST_SMTP_STARTTLS`: `true` (default) or `false`.
- `DST_SMTP_TLS_VERIFY`: `true` (default) or `false`. Set to `false` only for temporary troubleshooting when the SMTP certificate/hostname chain is broken.
- `DST_RCPT_TO`: recipient address(es) for forwarded messages. Default is `DST_SMTP_USER`. Multiple recipients are supported as comma-separated values.
- `DST_FORCE_FROM`: optional sender address override for message headers. Useful for providers (for example Brevo) that require a verified sender. When set, the original `From` is preserved in `X-Original-From` and used as `Reply-To` if missing.
- `DST_FORCE_TO`: optional `To` header override. Useful to make Gmail indexing/search match the final destination mailbox. When set, the original `To` is preserved in `X-Original-To`.
- `DELETE_AFTER_DELIVERY`: `true` (default) or `false`.
- `POLL_SECONDS`: polling interval in seconds (default `120`).
- `BACKLOG_LOG_EVERY`: emit source backlog progress every N cycles (default `10`, set `0` to disable).
- `STATE_DIR`: getmail state directory (default `/var/lib/forwarder`).
- `LOG_DIR`: runtime log directory (default `/var/log/forwarder`).

## Build

```bash
docker build -t popbridge:latest .
```

## Docker Compose

```bash
docker compose up -d --build
```

Stop:

```bash
docker compose down
```

## Docker run example

```bash
docker run -d --name popbridge-pop3 \
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
  -e DST_RCPT_TO=your.account@gmail.com \
  -e DST_FORCE_FROM=hello@cerbero.cc \
  -e DST_FORCE_TO=your.account@gmail.com \
  -e DST_SMTP_STARTTLS=true \
  -e DST_SMTP_TLS_VERIFY=true \
  -e DELETE_AFTER_DELIVERY=true \
  -e POLL_SECONDS=120 \
  -v popbridge-state:/var/lib/forwarder \
  -v popbridge-logs:/var/log/forwarder \
  popbridge:latest
```

## Useful logs

- `${LOG_DIR}/runner.log`: polling results and startup/progress migration hints.
- `${LOG_DIR}/getmail-run.log`: full `getmail` command output.
- `${LOG_DIR}/getmail.log`: internal `getmailrc` logfile.

Example:

```bash
docker logs -f popbridge-pop3
```

## Operational notes

- For Gmail, you will usually need an app password on the destination account.
- If your SMTP provider enforces validated senders/domains (for example Brevo), set `DST_FORCE_FROM` to an approved sender identity.
- If delivered messages are hard to find in Gmail threads/search, set `DST_FORCE_TO` to the Gmail destination address.
- Keep `DST_SMTP_TLS_VERIFY=true` in production; disabling TLS verification is insecure and should only be used for short-lived diagnostics.
- Keep state/log volumes persistent to avoid duplicates after restart.
- For a dry-run phase without deletion from source, set `DELETE_AFTER_DELIVERY=false`.
