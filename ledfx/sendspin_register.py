#!/usr/bin/env python3
"""Traegt einen Sendspin-Server in die LedFx-Konfiguration ein.

LedFx 2.1.9 bringt einen eigenen Sendspin-Client mit (ledfx/sendspin/,
Abhaengigkeit aiosendspin). Die Geraeteliste wird aber aus SENDSPIN_SERVERS
gebaut, und die ist leer, bis ein Server registriert wurde - ueber
POST /api/sendspin/servers oder eben den Konfigurationsschluessel
"sendspin_servers", den LedFx beim Start einliest.

Dieses Skript schreibt genau diesen Schluessel, damit niemand eine Shell
braucht, um das Add-on mit Music Assistant zu verbinden.

Aufruf: sendspin_register.py <config.json> <server_id> <server_url> <client_name>
"""

import json
import os
import pathlib
import sys
import tempfile


def log(message: str) -> None:
    print(f"[sendspin] {message}", flush=True)


def register(config_path: pathlib.Path, server_id: str, url: str, client: str) -> int:
    if not config_path.is_file():
        # Beim allerersten Start existiert die Datei noch nicht. Wir legen sie
        # bewusst NICHT an - eine unvollstaendige config.json koennte LedFx
        # durcheinanderbringen. run.sh laeuft bei jedem Start, der naechste
        # Start traegt den Server also nach.
        log(f"{config_path} existiert noch nicht - Eintrag folgt beim naechsten Start.")
        return 0

    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        log(f"FEHLER: {config_path} nicht lesbar ({exc}) - nichts geaendert.")
        return 1

    if not isinstance(config, dict):
        log("FEHLER: config.json enthaelt kein Objekt - nichts geaendert.")
        return 1

    servers = config.setdefault("sendspin_servers", {})
    if not isinstance(servers, dict):
        log("FEHLER: 'sendspin_servers' ist kein Objekt - nichts geaendert.")
        return 1

    if server_id in servers:
        current = servers[server_id].get("server_url") if isinstance(servers[server_id], dict) else None
        if current == url:
            log(f"Server '{server_id}' ist bereits eingetragen ({url}).")
            return 0
        log(f"Server '{server_id}' zeigt auf {current}, aktualisiere auf {url}.")

    servers[server_id] = {"server_url": url, "client_name": client}

    # Atomar schreiben: ein abgebrochener Schreibvorgang darf die Konfiguration
    # des Nutzers nicht zerstoeren.
    tmp_fd, tmp_name = tempfile.mkstemp(dir=str(config_path.parent), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as handle:
            json.dump(config, handle, indent=4)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, config_path)
    except OSError as exc:
        log(f"FEHLER beim Schreiben: {exc}")
        pathlib.Path(tmp_name).unlink(missing_ok=True)
        return 1

    log(f"Server '{server_id}' eingetragen: {url} (Client '{client}').")
    log("In LedFx unter Settings -> Audio erscheint jetzt 'SENDSPIN: " f"{server_id}'.")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        log(f"Aufruf: {argv[0]} <config.json> <server_id> <server_url> <client_name>")
        return 2
    return register(pathlib.Path(argv[1]), argv[2], argv[3], argv[4])


if __name__ == "__main__":
    sys.exit(main(sys.argv))
