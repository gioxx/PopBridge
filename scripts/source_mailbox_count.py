#!/usr/bin/env python3
import os
import poplib
import socket
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
    host = env("SRC_HOST")
    port = int(env("SRC_PORT"))
    user = env("SRC_USER")
    password = env("SRC_PASS")
    use_ssl = as_bool("SRC_SSL", "true")
    use_starttls = as_bool("SRC_STARTTLS", "false")

    if use_ssl and use_starttls:
        raise RuntimeError("SRC_SSL and SRC_STARTTLS cannot both be true")

    timeout = 60
    if use_ssl:
        client = poplib.POP3_SSL(host, port, timeout=timeout, context=ssl.create_default_context())
    else:
        client = poplib.POP3(host, port, timeout=timeout)
        if use_starttls:
            client.stls(context=ssl.create_default_context())

    try:
        client.user(user)
        client.pass_(password)
        count, _ = client.stat()
        sys.stdout.write(f"{int(count)}\n")
    finally:
        try:
            client.quit()
        except (OSError, socket.error):
            pass

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write(f"{exc}\n")
        raise SystemExit(2)
