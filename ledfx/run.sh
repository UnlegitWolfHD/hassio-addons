#!/bin/sh
# Startskript des LedFx-Add-ons. Kein bashio verfuegbar (Fremd-Basisimage),
# deshalb werden die Optionen mit dem ohnehin vorhandenen Python gelesen.
set -e

CONFIG_DIR=/share/ledfx

# /data/options.json -> Shell-Variablen (einmal Python, sauber gequotet)
eval "$(python3 - <<'PY'
import json, pathlib, shlex

opts = {}
p = pathlib.Path("/data/options.json")
if p.is_file():
    opts = json.loads(p.read_text() or "{}")

def emit(name, key, default):
    value = opts.get(key)
    if value is None or value == "":
        value = default
    print(f"{name}={shlex.quote(str(value))}")

emit("HOST", "host", "0.0.0.0")
emit("PORT", "port", 8888)
emit("LOG_LEVEL", "log_level", "info")
emit("AUDIO_SOURCE", "audio_source", "")
emit("NULL_SINK", "null_sink", False)
emit("SENDSPIN", "sendspin", False)
emit("SENDSPIN_NAME", "sendspin_name", "LedFx")
emit("SENDSPIN_SERVER", "sendspin_server", "")
emit("OFFLINE", "offline_mode", False)
PY
)"

mkdir -p "$CONFIG_DIR"

# --- Bildcache ---------------------------------------------------------
# LedFx legt seinen Bildcache unter <config>/cache/images an: bis zu 500 MB,
# ohne automatisches Verfallsdatum ("cache and keep", nur LRU am Limit).
# In /share landet das in jedem Home-Assistant-Backup. Deshalb auf das
# Add-on-eigene /data umlenken, das per backup_exclude aus Backups faellt.
# Ein bereits bestehendes echtes Verzeichnis wird NICHT angefasst.
if [ -L "$CONFIG_DIR/cache" ]; then
    :
elif [ -d "$CONFIG_DIR/cache" ]; then
    echo "[ledfx] HINWEIS: $CONFIG_DIR/cache ist ein echtes Verzeichnis und"
    echo "[ledfx]          landet damit in jedem Backup. Zum Umlenken einmal"
    echo "[ledfx]          loeschen und das Add-on neu starten."
elif mkdir -p /data/cache 2>/dev/null      && ln -s /data/cache "$CONFIG_DIR/cache" 2>/dev/null; then
    echo "[ledfx] Bildcache liegt unter /data/cache, ausserhalb der Backups."
else
    # Als Bedingung geschrieben, damit "set -e" hier nicht zuschlaegt: ein
    # nicht umlenkbarer Cache ist ein Schoenheitsfehler, kein Startabbruch.
    echo "[ledfx] HINWEIS: Bildcache konnte nicht nach /data umgelenkt werden."
    echo "[ledfx]          LedFx legt ihn dann unter $CONFIG_DIR/cache an."
fi

# --- Audio -------------------------------------------------------------
# Das Upstream-Image setzt PULSE_SERVER bereits auf seinen containereigenen
# PulseAudio-Daemon (/home/ledfx/.config/pulse/pulseaudio.socket) - ein
# ":-"-Default wuerde also nie greifen. Hart auf den Supervisor umbiegen.
export PULSE_SERVER="unix:/run/audio/pulse.sock"
# Cookie-Pfad des Upstream-Images existiert hier nicht; der Supervisor-Socket
# braucht keinen.
unset PULSE_COOKIE

# Virtuelles Ausgabeziel. Sein Monitor ist die Aufnahmequelle fuer LedFx.
ensure_null_sink() {
    if pactl list short modules 2>/dev/null | grep -q "sink_name=ledfx"; then
        echo "[ledfx] Null-Sink 'ledfx' existiert bereits."
    else
        echo "[ledfx] Lege Null-Sink 'ledfx' an."
        pactl load-module module-null-sink sink_name=ledfx sink_properties=device.description=LedFx >/dev/null
    fi
    pactl set-default-sink ledfx || true
    pactl set-default-source ledfx.monitor || true
    [ -z "$AUDIO_SOURCE" ] && AUDIO_SOURCE="ledfx.monitor"
}

case "$NULL_SINK" in
    True|true|1) ensure_null_sink ;;
esac

if [ -n "$AUDIO_SOURCE" ]; then
    # Von libpulse/ALSA-Plugin ausgewertet: legt die Aufnahmequelle fest.
    export PULSE_SOURCE="$AUDIO_SOURCE"
fi

if [ -S /run/audio/pulse.sock ]; then
    echo "[ledfx] Verfuegbare PulseAudio-Ziele (Sinks):"
    pactl list short sinks 2>&1 | sed 's/^/[ledfx]   /' || true
    echo "[ledfx] Verfuegbare PulseAudio-Quellen:"
    pactl list short sources 2>&1 | sed 's/^/[ledfx]   /' || true
    [ -n "$AUDIO_SOURCE" ] && echo "[ledfx] Aufnahmequelle (PULSE_SOURCE): $AUDIO_SOURCE"
else
    echo "[ledfx] WARNUNG: kein PulseAudio-Socket unter /run/audio/pulse.sock."
    echo "[ledfx]           'audio: true' in config.yaml gesetzt? Add-on neu gestartet?"
fi

# --- Sendspin ----------------------------------------------------------
# LedFx 2.1.9 bringt einen eigenen Sendspin-Client mit. Wir tragen nur den
# Server ein - LedFx verbindet sich dann selbst mit Music Assistant, ohne
# PulseAudio, ohne Null-Sink und ohne zusaetzlichen Daemon im Container.
case "$SENDSPIN" in
    True|true|1)
        if [ -z "$SENDSPIN_SERVER" ]; then
            echo "[ledfx] HINWEIS: sendspin=true, aber sendspin_server ist leer."
            echo "[ledfx]          Trage dort die WebSocket-Adresse von Music"
            echo "[ledfx]          Assistant ein, z. B.:"
            echo "[ledfx]            ws://192.168.1.50:8927/sendspin"
        else
            python3 /sendspin_register.py                 "$CONFIG_DIR/config.json"                 "music-assistant"                 "$SENDSPIN_SERVER"                 "$SENDSPIN_NAME"
        fi
        ;;
esac

# --- LedFx -------------------------------------------------------------
set -- --host "$HOST" --port "$PORT" --config "$CONFIG_DIR"

case "$LOG_LEVEL" in
    debug) set -- "$@" -v ;;
    trace) set -- "$@" -vv ;;
esac

case "$OFFLINE" in
    True|true|1) set -- "$@" --offline ;;
esac

echo "[ledfx] Start: ledfx $*"
if command -v ledfx >/dev/null 2>&1; then
    exec ledfx "$@"
else
    exec python3 -m ledfx "$@"
fi
