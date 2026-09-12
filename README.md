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
| Music Assistant | erscheint als **Sendspin**-Player (Port 8927, optional) |

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

> **Kurzfassung für den Normalfall:** `sendspin: true` setzen, neu starten — fertig. Das Add-on erscheint dann in Music Assistant
> als Player namens *LedFx*. Die Details dazu stehen in Variante A.

Der Teil, an dem die meisten Setups scheitern — hier Schritt für Schritt.

### Wie es funktioniert

Home Assistant OS betreibt einen eigenen **PulseAudio-Server** (das
Audio-Plugin des Supervisors). Alle Add-ons mit `audio: true` hängen am selben
Server:

```
Music Assistant ──► Sendspin ──► Sendspin-Daemon im LedFx-Add-on
                                          │  (spielt ab)
                                          ▼
                               PulseAudio-Sink  "ledfx"
                                          │
                                 Monitor-Quelle "ledfx.monitor"
                                          │  (nimmt auf)
                                          ▼
                                    LedFx ──► WLED (DDP/E1.31)
```

Der Sendspin-Daemon steckt mit im Add-on. Music Assistant sieht das Add-on
damit als ganz normalen Player und schickt Musik direkt dorthin — es braucht
kein zweites Add-on und keinen Snapcast-Server dazwischen.

Jedes Sink besitzt automatisch eine **Monitor-Quelle**. LedFx nimmt diese auf
und analysiert damit exakt das, was gerade abgespielt wird — ohne Mikrofon,
ohne Kabel, latenzarm.

### Schritt 1 – Virtuelles Audio-Ziel anlegen

Nur nötig, wenn der Host keine nutzbare Soundkarte hat (typisch für einen
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

**Variante A (empfohlen): Sendspin — das Add-on selbst als Player**

Sendspin ist das eigene Player-Protokoll von Music Assistant. Es ist dort
eingebaut, immer aktiv und findet Geräte per mDNS von allein. Dieses Add-on
bringt einen Sendspin-Daemon mit, das heißt: **kein zweites Add-on, kein
Snapcast-Server, keine IP-Eintragerei.**

1. *LedFx → Konfiguration →* `sendspin: true` setzen, bei Bedarf
   `sendspin_name` anpassen. Speichern, Add-on neu starten.
   `null_sink` muss **nicht** gesetzt werden: hat PulseAudio überhaupt kein
   Ausgabeziel, legt das Add-on selbst eines an. Existierende Sinks (echte
   Soundkarte, HDMI) bleiben unangetastet.
2. Im Add-on-Log erscheint:

   ```
   [ledfx] Starte Sendspin-Daemon als 'LedFx' (Port 8927).
   [ledfx] Sendspin laeuft (PID 42).
   ```

   Steht dort stattdessen `Sendspin wurde sofort beendet`, verrät die
   darauffolgende `[sendspin]`-Zeile den Grund.

3. In Music Assistant unter *Einstellungen → Player* auftauchen lassen — der
   Player erscheint nach wenigen Sekunden von selbst. Nichts hinzufügen, nichts
   konfigurieren.
4. Musik auf diesen Player abspielen. Der Ton landet im Sink `ledfx`, LedFx
   nimmt dessen Monitor auf.

> **Pairing:** Music Assistant zeigt bei jedem Sendspin-Player oben seinen
> Sicherheitsstatus. Beim ersten Verbinden gegebenenfalls über **Setup** am
> Player die Verbindung bestätigen.

> **Port 8927** muss auf dem Host frei sein — das Add-on läuft im Host-Netzwerk.

> **Technical Preview:** Sendspin ist laut Music Assistant noch im technischen
> Vorschau-Stadium. Funktioniert, kann sich aber ändern. Wenn etwas klemmt, sind
> die Varianten B–D der stabile Rückfallweg.

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

**Feste Version statt `latest`:** `ghcr.io/ledfx/ledfx` ist mit reinen
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

## 9. Fehlersuche

| Symptom | Ursache / Lösung |
|---|---|
| Add-on startet nicht, Log endet sofort | `log_level: debug` setzen und Log prüfen. Häufigste Ursache: Port 8888 auf dem Host belegt. |
| Web-UI nicht erreichbar | Läuft das Add-on wirklich? `host: 0.0.0.0` gesetzt? Firewall/VLAN zwischen Browser und HA-Host prüfen. |
| `WARNUNG: kein PulseAudio-Socket` im Log | `audio: true` fehlt in der `config.yaml`, oder das Add-on wurde nach der Änderung nur neu gestartet statt neu gebaut. |
| Keine Audioquelle in LedFx sichtbar | Abschnitt 5, Schritt 3: ist `pulse`/`default` ausgewählt? Listet das Log überhaupt Quellen? |
| Pegelanzeige bleibt bei 0 | Es läuft nichts in das Sink. Zuerst im Log des Snapcast-/Squeezelite-Add-ons prüfen, ob es wirklich abspielt, dann die richtige `.monitor`-Quelle wählen. |
| WLED wird nicht gefunden | Host-Netzwerk aktiv? Gleiches Subnetz? IP manuell eintragen. |
| Player taucht in Music Assistant nicht auf | Log auf `Starte Sendspin-Daemon` prüfen. Ist Port 8927 auf dem Host frei? MA und HA im selben Layer-2-Netz (mDNS)? |
| `FEHLER: Sendspin-Client fehlt im Image` | Das Add-on wurde vor dem Einbau von Sendspin gebaut — Version hochzählen und neu bauen (Abschnitt 7). |
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
├── .github/
│   └── workflows/
│       └── builder.yaml          # Multi-Arch-Build nach ghcr.io (optional)
└── ledfx/
    ├── config.yaml               # Add-on-Definition (Schema, Ports, Rechte)
    ├── build.yaml                # Basis-Images pro Architektur
    ├── Dockerfile                # Ableitung von ghcr.io/ledfx/ledfx:latest
    └── run.sh                    # Startskript: Optionen, Audio, Sendspin, LedFx
```

Vor dem Push in allen Dateien `DEIN-GITHUB-USER` durch den eigenen Account
ersetzen.

---

## Lizenz

Die Add-on-Verpackung steht unter der MIT-Lizenz. LedFx selbst folgt seiner
eigenen Lizenz, siehe [LedFx/LedFx](https://github.com/LedFx/LedFx).
