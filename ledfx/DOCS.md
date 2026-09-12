# LedFx

Audio-reaktive LED-Steuerung für WLED und andere DDP/E1.31-Controller.

Die vollständige Anleitung — Installation, Audio-Routing aus Music Assistant,
WLED-Einrichtung und Fehlersuche — steht in der
[README des Repositories](https://github.com/UnlegitWolfHD/hassio-addons#readme).

## Schnellstart

1. Add-on starten und **Web-UI öffnen** (Port 8888).
2. In LedFx unter *Settings → Audio* die Aufnahmequelle wählen.
3. Unter *Devices* das WLED-Gerät hinzufügen (wird per mDNS meist selbst
   gefunden) und einen Effekt aktivieren.

## Music Assistant

LedFx 2.1.9 bringt Sendspin selbst mit. Den Music-Assistant-Server einmalig
registrieren:

```bash
curl -X POST http://<HA-IP>:8888/api/sendspin/servers -H "Content-Type: application/json" -d '{"id":"music-assistant","server_url":"ws://<MA-IP>:8927/sendspin","client_name":"LedFx"}'
```

Danach erscheint im Audio-Dropdown ein Eintrag `SENDSPIN: music-assistant`.

Alternativ startet die Option `sendspin` einen eigenständigen Sendspin-Daemon
im Add-on. Beides gleichzeitig zu benutzen ist nicht sinnvoll — beide Wege
belegen Port 8927.

## Wichtige Hinweise

- Das Add-on läuft im **Host-Netzwerk**. Port 8888 (und bei aktivem Sendspin
  8927) müssen auf dem Host frei sein.
- Die Konfiguration liegt dauerhaft unter `/share/ledfx` und übersteht
  Neustarts, Updates und Rebuilds.
- Nach dem Start dauert es bis zu 90 Sekunden, bis Home Assistant das Add-on
  als *Gestartet* meldet — so lange läuft die Aufwärmphase des Healthchecks.
