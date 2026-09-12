#!/bin/sh
# Docker-HEALTHCHECK. Home Assistant leitet den Add-on-Zustand direkt daraus ab:
#
#   case ContainerState.RUNNING:
#       return AppState.STARTUP if self.instance.healthcheck else AppState.STARTED
#
# Ein laufender Container mit Healthcheck bleibt also so lange auf
# "wird gestartet", bis Docker healthy oder unhealthy meldet. "HEALTHCHECK NONE"
# hilft dabei NICHT: Docker hinterlegt dann {"Test": ["NONE"]}, was fuer den
# Supervisor ein vorhandener Healthcheck ist, der nie ein Ergebnis liefert.
# Deshalb hier ein echter Check gegen die Web-UI.
exec python3 - <<'PY'
import json
import pathlib
import sys
import urllib.request

try:
    options = json.loads(pathlib.Path("/data/options.json").read_text())
except Exception:
    options = {}

host = options.get("host") or "0.0.0.0"
port = options.get("port") or 8888

# Auf 0.0.0.0 laesst sich nicht verbinden; eine abweichende Bindung muss aber
# respektiert werden, sonst faellt der Check ewig durch und der Watchdog
# startet das Add-on in einer Schleife neu.
target = "127.0.0.1" if host in ("0.0.0.0", "::", "") else host

try:
    with urllib.request.urlopen(f"http://{target}:{port}/", timeout=5) as response:
        if response.status >= 500:
            print(f"LedFx antwortet mit HTTP {response.status}")
            sys.exit(1)
except Exception as exc:
    print(f"LedFx auf {target}:{port} nicht erreichbar: {exc}")
    sys.exit(1)
PY
