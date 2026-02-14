# syntax=docker/dockerfile:1
FROM python:3.12-alpine

# Install CA certs and timezone data (optional but useful)
RUN apk add --no-cache ca-certificates tzdata

# Install getmail6
RUN pip install --no-cache-dir getmail6

# Runtime dirs
RUN adduser -D -H -u 10001 app \
    && mkdir -p /etc/forwarder /var/lib/forwarder /var/log/forwarder \
    && chown -R app:app /etc/forwarder /var/lib/forwarder /var/log/forwarder

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER app

ENV STATE_DIR=/var/lib/forwarder \
    LOG_DIR=/var/log/forwarder \
    POLL_SECONDS=120 \
    DELETE_AFTER_DELIVERY=true \
    SRC_PROTOCOL=pop3 \
    SRC_SSL=true \
    SRC_STARTTLS=false \
    DST_SMTP_STARTTLS=true

ENTRYPOINT ["/entrypoint.sh"]
