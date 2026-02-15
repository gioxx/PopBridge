#!/usr/bin/env python3
import os
import smtplib
import ssl
import sys


def env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing env: {name}")
    return value


def as_bool(name: str, default: str) -> bool:
    value = os.environ.get(name, default).strip().lower()
    return value in ("true", "1", "yes")


def main() -> int:
    raw = sys.stdin.buffer.read()

    host = env("DST_SMTP_HOST")
    port = int(env("DST_SMTP_PORT"))
    user = env("DST_SMTP_USER")
    password = env("DST_SMTP_PASS")
    rcpt_to_raw = os.environ.get("DST_RCPT_TO") or user

    starttls = as_bool("DST_SMTP_STARTTLS", "true")
    tls_verify = as_bool("DST_SMTP_TLS_VERIFY", "true")

    tls_context = ssl.create_default_context()
    if not tls_verify:
        tls_context.check_hostname = False
        tls_context.verify_mode = ssl.CERT_NONE

    # Envelope sender/recipient:
    # Keep a stable envelope sender (SMTP auth identity) to avoid rejections.
    mail_from = user
    rcpt_to = [addr.strip() for addr in rcpt_to_raw.split(",") if addr.strip()]
    if not rcpt_to:
        raise RuntimeError("DST_RCPT_TO resolved to an empty recipient list")

    if starttls:
        with smtplib.SMTP(host, port, timeout=60) as client:
            client.ehlo()
            client.starttls(context=tls_context)
            client.ehlo()
            client.login(user, password)
            client.sendmail(mail_from, rcpt_to, raw)
    else:
        # For completeness; Gmail normally uses STARTTLS on port 587.
        with smtplib.SMTP_SSL(host, port, timeout=60, context=tls_context) as client:
            client.login(user, password)
            client.sendmail(mail_from, rcpt_to, raw)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write(f"{exc}\n")
        raise SystemExit(2)
