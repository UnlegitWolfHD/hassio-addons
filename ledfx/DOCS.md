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

LedFx 2.1.9 bringt Sendspin selbst mit. In der Konfiguration setzen:

```yaml
sendspin: true
sendspin_server: "ws://<MA-IP>:8927/sendspin"
```

Nach dem Neustart steht im Audio-Dropdown von LedFx ein Eintrag
`SENDSPIN: music-assistant`. Auswählen — fertig. Es fließt dabei kein Ton durch
PulseAudio, LedFx bekommt den Stream direkt über das Netzwerk.

Adresse unbekannt? `curl http://<HA-IP>:8888/api/sendspin/discover` sucht.

## Wichtige Hinweise

- Das Add-on läuft im **Host-Netzwerk**. Port 8888 muss auf dem Host frei sein.
- Die Konfiguration liegt dauerhaft unter `/share/ledfx` und übersteht
  Neustarts, Updates und Rebuilds.
- Nach dem Start dauert es bis zu 90 Sekunden, bis Home Assistant das Add-on
  als *Gestartet* meldet — so lange läuft die Aufwärmphase des Healthchecks.
