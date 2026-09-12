# LedFx – Home Assistant Add-on

Audio-reaktive LED-Steuerung für WLED, DDP/E1.31-Controller & Co. – als Add-on
für Home Assistant OS / Supervised, basierend auf dem offiziellen Container-Image
[`ghcr.io/ledfx/ledfx`](https://github.com/LedFx/LedFx).

| Eigenschaft | Wert |
|---|---|
| Architekturen | `aarch64` (Raspberry Pi 5, 64-bit), `amd64` |
| Web-UI | Port **8888** (Host-Netzwerk) |
| Konfiguration | persistent unter `/share/ledfx` |
| Audio | über den PulseAudio-Server des Supervisors (`audio: true`) |
| Music Assistant | über **Sendspin**, direkt von LedFx (kein Umweg über PulseAudio) |

---

## Inhalt

1. [Voraussetzungen](#1-voraussetzungen)
2. [Installation als Custom Repository](#2-installation-als-custom-repository)
3. [Konfigurationsoptionen](#3-konfigurationsoptionen)
4. [Web-UI und Seitenleiste](#4-web-ui-und-seitenleiste)
5. [Audio-Routing aus Music Assistant (Sendspin) / Snapcast](#5-audio-routing-aus-music-assistant--snapcast)
6. [WLED-Geräte einbinden](#6-wled-geräte-einbinden)
7. [Updates und Rebuild](#7-updates-und-rebuild)
8. [Vorgebaute Images per GitHub Actions](#8-vorgebaute-images-per-github-actions)
8a. [Add-on-Zustand und Healthcheck](#8a-add-on-zustand-und-healthcheck)
8b. [Steuerung aus Home Assistant](#8b-steuerung-aus-home-assistant)
9. [Fehlersuche](#9-fehlersuche)
10. [Repository-Struktur](#10-repository-struktur)

---

## 1. Voraussetzungen

* Home Assistant **OS** oder **Supervised** (bei Home Assistant Container/Core
  gibt es keinen Add-on-Store).
* 64-bit-System: Raspberry Pi 5 mit HAOS aarch64 oder ein x86-64-Host.
  32-bit (armv7) wird nicht unterstützt, weil LedFx dafür kein Image baut.
* Mindestens rund 1 GB freier RAM; LedFx rechnet FFTs in Echtzeit.
* Ein WLED-Gerät (oder anderer DDP/E1.31-Controller) im selben Netzwerksegment.

---

## 2. Installation als Custom Repository

1. **Repository hinzufügen**
   *Einstellungen → Add-ons → Add-on-Store* öffnen, oben rechts auf die drei
   Punkte → **Repositories**.
2. Die URL dieses Repos eintragen, z. B.
   `https://github.com/DEIN-GITHUB-USER/ha-ledfx-addon`, und auf **Hinzufügen**
   klicken.
3. Dialog schließen, Seite neu laden (`Strg`+`F5`). Unten im Store erscheint der
   Abschnitt **LedFx Add-on Repository** mit dem Add-on **LedFx**.
4. Add-on anklicken → **Installieren**.
   Beim ersten Mal baut der Supervisor das Image lokal aus dem `Dockerfile`.
   Auf einem Pi 5 dauert das je nach Netzwerk 5–15 Minuten; die Add-on-Logs
   zeigen den Fortschritt.
5. Nach dem Build: Reiter **Konfiguration** prüfen (siehe unten), dann
   **Starten**.
6. Empfohlen: *Watchdog* und *Beim Start ausführen* aktivieren.

> **Hinweis:** Das Add-on läuft im **Host-Netzwerk**. Port 8888 muss auf dem Host
> frei sein. Home Assistant zeigt deshalb kein Port-Mapping im Reiter
> „Konfiguration" an — das ist so gewollt und für mDNS-Discovery sowie
> UDP-Streaming zu WLED notwendig.

---

## 3. Konfigurationsoptionen

```yaml
host: 0.0.0.0
port: 8888
log_level: info
audio_source: ""
null_sink: false
sendspin: false
sendspin_name: LedFx
offline_mode: false
```

| Option | Typ | Default | Bedeutung |
|---|---|---|---|
| `host` | String | `0.0.0.0` | Interface, auf dem die Web-UI lauscht. `0.0.0.0` = alle. |
| `port` | Port | `8888` | Port der Web-UI. Nur ändern, wenn 8888 auf dem Host belegt ist — dann zeigt der Button „Web-UI öffnen" auf den falschen Port und die URL muss manuell eingegeben werden. |
| `log_level` | `info` / `debug` / `trace` | `info` | `debug` entspricht `ledfx -v`, `trace` entspricht `-vv`. |
| `audio_source` | String | `""` | Name der PulseAudio-Quelle, die LedFx aufnimmt (meist eine `*.monitor`-Quelle). Leer = Systemstandard. Siehe Abschnitt 5. |
| `null_sink` | Bool | `false` | Erzwingt ein virtuelles Audio-Ziel `ledfx` als Standard-Ausgang. Bei `sendspin: true` meist unnötig — dann wird eines automatisch angelegt, *falls* gar kein Sink existiert. **Achtung:** erzwungen ändert es den Standard-Ausgang für *alle* Add-ons, TTS-Ansagen landen dann im Nichts. |
| `sendspin` | Bool | `false` | Startet den Sendspin-Daemon, damit das Add-on in Music Assistant als Player erscheint. Legt bei Bedarf selbst ein Audio-Ziel an. |
| `sendspin_name` | String | `LedFx` | Anzeigename des Players in Music Assistant. |
| `offline_mode` | Bool | `false` | Startet LedFx mit `--offline`: keine Update-Checks, kein Crash-Reporting. |

Nach jeder Änderung: **Speichern** und das Add-on **neu starten**.

---

## 4. Web-UI und Seitenleiste

Direkter Zugriff: `http://<IP-DEINES-HA-HOSTS>:8888`
oder über den Button **Web-UI öffnen** auf der Add-on-Seite.

### Warum kein Ingress?

LedFx lädt seine Frontend-Assets über **absolute Pfade** (`/static/...`). Der
Home-Assistant-Ingress stellt jeder Anfrage ein Präfix
(`/api/hassio_ingress/<token>/`) voran — die UI bliebe weiß. Deshalb ist in der
`config.yaml` bewusst kein `ingress: true` gesetzt.

### Trotzdem in der Seitenleiste

Über ein Webseiten-Dashboard:

1. *Einstellungen → Dashboards → Dashboard hinzufügen → **Webseite***
2. Titel `LedFx`, Icon z. B. `mdi:led-strip-variant`, URL
   `http://<IP-DEINES-HA-HOSTS>:8888`
3. **In Seitenleiste anzeigen** aktivieren.

> **Mixed-Content-Warnung:** Läuft Home Assistant selbst über **HTTPS**,
> blockieren Browser einen eingebetteten `http://`-iFrame. Dann LedFx in einem
> eigenen Tab öffnen oder einen Reverse-Proxy mit TLS vorschalten.

---

## 5. Audio-Routing aus Music Assistant / Snapcast

> **Kurzfassung für den Normalfall:** `sendspin: true` und
> `sendspin_server: "ws://<MA-IP>:8927/sendspin"` setzen, neu starten — fertig. Das Add-on erscheint dann in Music Assistant
> sieht LedFx dann als Audioquelle. Die Details stehen in Variante A.

Der Teil, an dem die meisten Setups scheitern — hier Schritt für Schritt.

### Wie es funktioniert

Home Assistant OS betreibt einen eigenen **PulseAudio-Server** (das
Audio-Plugin des Supervisors). Alle Add-ons mit `audio: true` hängen am selben
Server:

```
Variante A (empfohlen) — LedFx spricht Sendspin selbst:

    Music Assistant ──► Sendspin (Netzwerk) ──► LedFx ──► WLED (DDP/E1.31)

Varianten B–D — über den PulseAudio-Server von Home Assistant:

    Snapcast/Squeezelite-Add-on ──► Sink "ledfx" ──► ledfx.monitor ──► LedFx
```

Variante A braucht den PulseAudio-Umweg gar nicht. Die Varianten B–D nutzen ihn:
alle Add-ons mit `audio: true` hängen am selben PulseAudio-Server, und jedes Sink
besitzt automatisch eine Monitor-Quelle, die LedFx aufnehmen kann.

Jedes Sink besitzt automatisch eine **Monitor-Quelle**. LedFx nimmt diese auf
und analysiert damit exakt das, was gerade abgespielt wird — ohne Mikrofon,
ohne Kabel, latenzarm.

### Schritt 1 – Virtuelles Audio-Ziel anlegen

**Nur für die Varianten B–D.** Wer Variante A benutzt, überspringt diesen
Schritt komplett — dort fließt kein Ton durch PulseAudio.

Nötig, wenn der Host keine nutzbare Soundkarte hat (typisch für einen
headless Raspberry Pi 5 ohne HDMI-Ton oder USB-DAC).

*LedFx → Konfiguration →* `null_sink: true` *→ Speichern → Neu starten.*

Im Add-on-Log erscheint dann:

```
[ledfx] Lege Null-Sink 'ledfx' an.
[ledfx] Verfuegbare PulseAudio-Quellen:
[ledfx]   1  ledfx.monitor  module-null-sink.c  s16le 2ch 44100Hz  IDLE
```

Wer eine echte Soundkarte oder einen HDMI-Ausgang nutzt, lässt
`null_sink: false` und wählt später einfach die Monitor-Quelle dieses Ausgangs.

### Schritt 2 – Audioquelle ins Sink schicken

**Variante A (empfohlen): LedFx' eigener Sendspin-Client**

LedFx 2.1.9 bringt Sendspin selbst mit — im Paket steckt `ledfx/sendspin/`,
`aiosendspin` ist eine feste Abhängigkeit. LedFx hängt sich damit direkt an
Music Assistant: **kein PulseAudio, kein Null-Sink, kein zusätzlicher Daemon.**
Die Audiodaten kommen über das Netzwerk, LedFx analysiert sie unmittelbar.

Die Geräteliste in LedFx startet leer (`SENDSPIN_SERVERS = {}`) — der Server
muss einmalig registriert werden. Das erledigt das Add-on für dich:

1. *LedFx → Konfiguration:*

   ```yaml
   sendspin: true
   sendspin_server: "ws://192.168.1.50:8927/sendspin"
   sendspin_name: LedFx
   ```

   Die IP ist die deines **Music-Assistant**-Hosts. Läuft MA als Add-on auf
   demselben Home Assistant, ist es dessen IP.

2. Speichern, Add-on neu starten. Im Protokoll steht dann:

   ```
   [sendspin] Server 'music-assistant' eingetragen: ws://192.168.1.50:8927/sendspin (Client 'LedFx').
   ```

3. In LedFx unter *Settings → Audio* das Gerät **`SENDSPIN: music-assistant`**
   auswählen.

Der Eintrag landet in `/share/ledfx/config.json` und übersteht Neustarts,
Updates und Rebuilds. Ein zweiter Start ändert nichts — das Add-on schreibt nur,
wenn der Eintrag fehlt oder auf eine andere Adresse zeigt. Eine unlesbare
`config.json` wird nie überschrieben, sondern gemeldet.

> **Beim allerersten Start** existiert `/share/ledfx/config.json` noch nicht.
> Das Add-on meldet dann `Eintrag folgt beim naechsten Start` — einmal neu
> starten, dann sitzt er.

> **Falls du die Adresse nicht kennst:** LedFx kann suchen.
> `curl http://<HA-IP>:8888/api/sendspin/discover` listet gefundene Server samt
> URL auf.

> **Technical Preview:** Music Assistant stuft Sendspin selbst noch als
> Vorschau ein. Wenn es klemmt, sind die Varianten B–D der stabile Rückfallweg —
> die laufen über PulseAudio und brauchen dann `null_sink: true`.

**Variante B: Music Assistant + Snapcast**

1. In Music Assistant den **Snapcast**-Player-Provider aktivieren
   (*Einstellungen → Player-Provider → Snapcast hinzufügen*). Music Assistant
   bringt einen eigenen Snapcast-Server mit.
2. Das Add-on **Snapcast Client** installieren (z. B. aus dem Repository
   `https://github.com/mdegat01/hassio-addons`).
3. Im Snapcast-Client-Add-on als Server die IP des Music-Assistant-Hosts und als
   Player-Backend **`pulse`** eintragen. Falls das Add-on eine Option für das
   Ausgabegerät hat: `ledfx` (bzw. den Sink-Namen aus Schritt 1) setzen. Ohne
   diese Option genügt `null_sink: true`, weil `ledfx` dann bereits der
   Standard-Ausgang ist.
4. Snapcast-Client starten und in Music Assistant Musik auf diesen Client
   abspielen.

**Variante C: Squeezelite / LMS**

Das Add-on **Squeezelite** installieren, als Ausgabegerät `pulse` bzw. `ledfx`
setzen und aus Logitech Media Server / Music Assistant darauf streamen.

**Variante D: Line-In / USB-Soundkarte**

USB-Audio-Interface an den Pi stecken. Die zugehörige Quelle taucht ohne
Zusatzkonfiguration in der Liste aus Schritt 3 auf (`alsa_input.usb-...`).
`null_sink` bleibt dabei `false`.

### Schritt 3 – Quelle in LedFx auswählen

**Der normale Weg: das Audio-Dropdown von Home Assistant.** Weil das Add-on
`audio: true` setzt, blendet Home Assistant auf der Add-on-Seite unter
*Konfiguration* die Auswahlfelder **Audio-Eingang** und **Audio-Ausgang** ein.
Der Supervisor schreibt die Auswahl als `default-source` in die
PulseAudio-Client-Konfiguration des Add-ons. Dort also die gewünschte
Monitor-Quelle wählen und das Add-on neu starten — die Option `audio_source`
bleibt dann leer.

**Falls die gewünschte Quelle im Dropdown fehlt** (z. B. weil Monitor-Quellen
nicht angeboten werden), greift die Option `audio_source` als Override. Sie
setzt `PULSE_SOURCE`, was Vorrang vor der Dropdown-Auswahl hat:

1. Add-on-Log von LedFx öffnen. Direkt nach dem Start steht dort die Liste aller
   Aufnahmequellen:

   ```
   [ledfx] Verfuegbare PulseAudio-Quellen:
   [ledfx]   1  ledfx.monitor                          ...  IDLE
   [ledfx]   2  alsa_output.platform-hdmi.stereo.monitor  ...  SUSPENDED
   ```

2. Den gewünschten Namen (in der Regel der mit `.monitor`) in die Option
   **`audio_source`** eintragen, speichern, Add-on neu starten.
3. In der LedFx-Web-UI: *Settings → Audio Input* → Gerät **`pulse`** oder
   **`default`** auswählen. Beides landet über die ALSA-PulseAudio-Brücke bei
   der in `audio_source` gesetzten Quelle.
4. Musik abspielen — der Pegelanzeiger in LedFx muss ausschlagen. Erst wenn er
   sich bewegt, lohnt sich das Einrichten von Effekten.

> Taucht in LedFx überhaupt kein Gerät `pulse` auf, fehlt die ALSA-Brücke im
> Image — dann das Add-on einmal neu bauen (Abschnitt 7).

---

## 6. WLED-Geräte einbinden

1. WLED-Controller ins gleiche Netzwerk bringen und dort unter
   *Config → Sync Interfaces* den Empfang aktivieren (DDP ist der empfohlene
   Standard, E1.31/DMX funktioniert ebenfalls).
2. In LedFx auf **Devices → Add Device → WLED** klicken. Dank Host-Netzwerk
   findet die mDNS-Suche die Controller meist automatisch; andernfalls IP und
   LED-Anzahl manuell eintragen.
3. Effekt auswählen, Audio abspielen, fertig.

> WLED und Home Assistant müssen im **selben Layer-2-Netz** liegen. Über
> VLAN-Grenzen hinweg funktioniert mDNS-Discovery nicht — dann die IP manuell
> eintragen und im Router UDP zulassen.

---

## 7. Updates und Rebuild

Das Add-on referenziert `ghcr.io/ledfx/ledfx:latest`. Home Assistant baut das
Image aber **nur neu, wenn sich die Add-on-Version ändert**. Um eine neuere
LedFx-Version zu ziehen:

1. In `ledfx/config.yaml` die Zeile `version: "1.0.0"` hochzählen (z. B. auf
   `"1.0.1"`) und committen.
2. In Home Assistant: *Add-on-Store → drei Punkte → **Neu laden***.
3. Beim Add-on erscheint **Aktualisieren** — anklicken.

Die Konfiguration unter `/share/ledfx` bleibt erhalten; ein Rebuild löscht
ausschließlich den Container.

**Das Basis-Image ist gepinnt.** `ledfx/build.yaml` zeigt auf
`ghcr.io/ledfx/ledfx:2.1.9` statt auf `:latest`. Ein Rebuild liefert damit
immer dieselbe LedFx-Version — mit `:latest` bekäme man bei jedem Rebuild eine
unbekannte Version samt möglicher Regressionen. Zum Aktualisieren den Tag dort
**und** die `version` in `config.yaml` hochzählen.

**Ältere Hinweise dazu:** `ghcr.io/ledfx/ledfx` ist mit reinen
Versionsnummern getaggt (`2.1.9`, **ohne** `v`-Präfix). Wer reproduzierbare
Builds will, trägt das in `ledfx/build.yaml` unter `build_from` ein. Als
Spiegel existiert `ledfxorg/ledfx` auf Docker Hub — dort gelten allerdings
Pull-Limits für nicht angemeldete Clients, deshalb ist GHCR der Default.

**Backup:** `/share/ledfx` ist Teil der normalen Home-Assistant-Backups. Dort
liegt `config.json` mit allen Geräten, Szenen und Effekten.

---

## 8. Vorgebaute Images per GitHub Actions

Optional, aber deutlich schneller als der lokale Build auf dem Pi.

1. Repo auf GitHub pushen. Der Workflow
   [`.github/workflows/builder.yaml`](.github/workflows/builder.yaml) läuft bei
   jedem Push auf `main`, der `ledfx/**` berührt, und legt Images unter
   `ghcr.io/<dein-user>/aarch64-addon-ledfx` und `.../amd64-addon-ledfx` ab.
2. Unter *GitHub → Packages* beide Pakete auf **public** stellen, sonst kann der
   Supervisor sie nicht ziehen.
3. In `ledfx/config.yaml` die Zeile einkommentieren:

   ```yaml
   image: ghcr.io/DEIN-GITHUB-USER/{arch}-addon-ledfx
   ```

   Ab jetzt **lädt** Home Assistant das passende Image, statt es zu bauen. Der
   Tag entspricht der `version` aus der `config.yaml` — beides muss also
   zusammen hochgezählt werden.

---

## 8a. Add-on-Zustand und Healthcheck

Home Assistant leitet den angezeigten Zustand direkt aus dem Docker-Healthcheck
des Containers ab. Im Supervisor steht das so:

```python
case ContainerState.RUNNING:
    return AppState.STARTUP if self.instance.healthcheck else AppState.STARTED
```

Ein laufender Container **mit** Healthcheck bleibt also so lange auf
*„wird gestartet“*, bis Docker `healthy` oder `unhealthy` meldet. Dieses Add-on
prüft deshalb alle 30 Sekunden, ob die LedFx-Web-UI antwortet, mit 90 Sekunden
Aufwärmzeit. **So lange kann der Zustand nach dem Start auf „wird gestartet“
stehen - das ist normal.** Danach springt er auf *Gestartet*.

> **Nicht auf `HEALTHCHECK NONE` ändern.** Docker hinterlegt dann
> `{"Test": ["NONE"]}`, was der Supervisor für einen vorhandenen Healthcheck
> hält - der aber nie ein Ergebnis liefert. Das Add-on bleibt dann **für immer**
> auf „wird gestartet“. Genau diesen Fehler hatte das Add-on bis Version 1.1.0.

Der Healthcheck respektiert die Option `host`: steht dort eine bestimmte
Adresse statt `0.0.0.0`, wird diese geprüft. Sonst liefe der Check ins Leere und
der Watchdog würde das Add-on in einer Schleife neu starten.

---

## 8b. Steuerung aus Home Assistant

Im Ordner [`homeassistant/`](homeassistant/) liegt ein fertiges Paket, das LedFx
über die Home-Assistant-Oberfläche bedienbar macht — Szenen, Effekte, Presets,
Helligkeit, An/Aus.

Es benutzt ausschließlich die REST-API von LedFx. Keine Integration, kein HACS,
kein Custom Component: nichts, das mit der nächsten LedFx-Version brechen kann.
(Die umfassendste Integration, `dmamontov/hass-ledfx`, wurde zuletzt im Juli
2023 angefasst. Gepflegt wird nur `guix77/homeassistant-ledfx`, die kann aber
ausschließlich Szenen schalten.)

### Einbau

1. `homeassistant/ledfx_package.yaml` nach `config/packages/ledfx.yaml` kopieren.
2. Die IP ganz oben in der Datei auf deinen Host anpassen (sie kommt mehrfach
   vor — Suchen und Ersetzen).
3. Falls noch nicht vorhanden, in `configuration.yaml` ergänzen:

   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```

4. Home Assistant neu starten.

### Was du danach hast

| Entität | Zweck |
|---|---|
| `input_select.ledfx_scene` | Szenenwahl. Die Liste füllt sich selbst aus LedFx, Auswahl aktiviert die Szene sofort. |
| `input_number.ledfx_brightness` | Helligkeitsregler für alle aktiven Virtuals. |
| `script.ledfx_alles_aus` | Schaltet alle Virtuals ab. |
| `script.ledfx_ueberraschung` | Würfelt die Einstellungen aller laufenden Effekte neu aus. |
| `sensor.ledfx_szenen` | Anzahl der Szenen; das Attribut `scenes` enthält alle Szenen. |
| `sensor.ledfx_aktive_virtuals` | Wie viele Virtuals laufen; Attribut `virtuals` mit allen Details. |
| `sensor.ledfx_version` | LedFx-Version — zugleich Verfügbarkeitsanzeige. |

### Dienste für eigene Automatisierungen

```yaml
# Szene aktivieren
- action: rest_command.ledfx_scene
  data:
    scene: meine-szene

# Effekt setzen, mit Einstellungen
- action: rest_command.ledfx_effect
  data:
    virtual: wled-gledopto
    effect: melt
    config:
      blur: 3
      background_brightness: 0.1

# Nur die Einstellungen des laufenden Effekts ändern
- action: rest_command.ledfx_effect_config
  data:
    virtual: wled-gledopto
    config:
      blur: 4

# Gespeichertes Preset anwenden
- action: rest_command.ledfx_preset
  data:
    virtual: wled-gledopto
    effect: melt
    preset: reset
    category: ledfx_presets     # oder user_presets

# Virtual an/aus
- action: rest_command.ledfx_virtual_power
  data:
    virtual: wled-gledopto
    active: true
```

Die Virtual-IDs stehen im Attribut `virtuals` von `sensor.ledfx_aktive_virtuals`
(*Entwicklerwerkzeuge → Zustände*), die Szenen-IDs im Attribut `scenes` von
`sensor.ledfx_szenen`.

### Ein typisches Beispiel

Licht folgt der Musik, sobald Music Assistant spielt, und geht danach aus:

```yaml
- alias: "LedFx folgt Music Assistant"
  triggers:
    - trigger: state
      entity_id: media_player.music_assistant
      to: playing
    - trigger: state
      entity_id: media_player.music_assistant
      to: paused
      for: "00:02:00"
  actions:
    - choose:
        - conditions: "{{ trigger.to_state.state == 'playing' }}"
          sequence:
            - action: rest_command.ledfx_scene
              data:
                scene: party
      default:
        - action: script.ledfx_alles_aus
```

> **Zum Recorder:** Die beiden Sensoren tragen die vollständigen Szenen- und
> Virtual-Objekte als Attribut. Bei vielen Szenen wird die Datenbank davon
> unnötig groß. In `configuration.yaml`:
>
> ```yaml
> recorder:
>   exclude:
>     entities:
>       - sensor.ledfx_szenen
>       - sensor.ledfx_aktive_virtuals
> ```

---

## 9. Fehlersuche

| Symptom | Ursache / Lösung |
|---|---|
| Add-on startet nicht, Log endet sofort | `log_level: debug` setzen und Log prüfen. Häufigste Ursache: Port 8888 auf dem Host belegt. |
| Web-UI nicht erreichbar | Läuft das Add-on wirklich? `host: 0.0.0.0` gesetzt? Firewall/VLAN zwischen Browser und HA-Host prüfen. |
| `WARNUNG: kein PulseAudio-Socket` im Log | `audio: true` fehlt in der `config.yaml`, oder das Add-on wurde nach der Änderung nur neu gestartet statt neu gebaut. |
| Keine Audioquelle in LedFx sichtbar | Abschnitt 5, Schritt 3: ist `pulse`/`default` ausgewählt? Listet das Log überhaupt Quellen? |
| Pegelanzeige bleibt bei 0 | Es läuft nichts in das Sink. Zuerst im Log des Snapcast-/Squeezelite-Add-ons prüfen, ob es wirklich abspielt, dann die richtige `.monitor`-Quelle wählen. |
| WLED wird nicht gefunden | Host-Netzwerk aktiv? Gleiches Subnetz? IP manuell eintragen. |
| Add-on bleibt dauerhaft auf „wird gestartet“ | Antwortet die Web-UI auf dem konfigurierten Port? Siehe Abschnitt 8a. Bis Version 1.1.0 war das ein Fehler im Add-on selbst. |
| `SENDSPIN: …` fehlt im Audio-Dropdown | Steht im Protokoll `Server 'music-assistant' eingetragen`? Beim allerersten Start existiert `config.json` noch nicht — einmal neu starten. |
| `sendspin_server ist leer` | Die WebSocket-Adresse von Music Assistant fehlt. `curl http://<HA-IP>:8888/api/sendspin/discover` findet sie. |
| `config.json nicht lesbar` | Die LedFx-Konfiguration ist beschädigt. Das Add-on rührt sie dann nicht an — Datei prüfen oder aus dem Backup holen. |
| Effekte ruckeln auf dem Pi 5 | Framerate in LedFx reduzieren (*Settings → Core → FPS*), weniger Geräte parallel bedienen. |
| Nach Update immer noch alte LedFx-Version | Add-on-`version` hochzählen und neu bauen (Abschnitt 7). |

Logs: *Add-on-Seite → Reiter **Protokoll***. Für Fehlerberichte `log_level: trace`
setzen.

---

## 10. Repository-Struktur

```
.
├── README.md
├── repository.yaml               # macht das Repo zum HA-Add-on-Store-Repository
├── test_run.sh                   # Selbsttest fuer run.sh (sh test_run.sh)
├── homeassistant/
│   └── ledfx_package.yaml        # Steuerung aus HA (Szenen, Effekte, Helligkeit)
├── .github/
│   └── workflows/
│       ├── builder.yaml          # Multi-Arch-Build nach ghcr.io (optional)
│       └── test.yaml             # YAML, Shellcheck, Selbsttests, Docker-Build
└── ledfx/
    ├── config.yaml               # Add-on-Definition (Schema, Ports, Rechte)
    ├── build.yaml                # Basis-Images pro Architektur
    ├── Dockerfile                # Ableitung von ghcr.io/ledfx/ledfx:latest
    ├── run.sh                    # Startskript: Optionen, Audio, Sendspin, LedFx
    ├── healthcheck.sh            # bestimmt den Add-on-Zustand in HA
    ├── sendspin_register.py      # traegt Music Assistant in LedFx ein
    ├── DOCS.md                   # Dokumentations-Tab auf der Add-on-Seite
    └── translations/             # Beschriftung der Optionen (de, en)
```

Vor dem Push in allen Dateien `DEIN-GITHUB-USER` durch den eigenen Account
ersetzen.

---

## Lizenz

Die Add-on-Verpackung steht unter der MIT-Lizenz. LedFx selbst folgt seiner
eigenen Lizenz, siehe [LedFx/LedFx](https://github.com/LedFx/LedFx).
