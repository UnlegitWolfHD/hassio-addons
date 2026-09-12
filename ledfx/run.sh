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
emit("OFFLINE", "offline_mode", False)
PY
)"

mkdir -p "$CONFIG_DIR"

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

# Sendspin braucht zwingend ein Ausgabeziel. Hat PulseAudio ueberhaupt keins
# (headless Pi ohne Soundkarte), ist das Null-Sink die einzige Moeglichkeit
# abzuspielen - dann ohne Nachfrage anlegen. Gibt es schon Sinks, wird nichts
# angefasst, damit echte Hardware Standard-Ausgang bleibt.
case "$SENDSPIN" in
    True|true|1)
        if [ "$(pactl list short sinks 2>/dev/null | wc -l)" -eq 0 ]; then
            echo "[ledfx] PulseAudio hat kein Ausgabeziel - lege fuer Sendspin"
            echo "[ledfx] automatisch eins an."
            ensure_null_sink
        fi
        ;;
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
# Meldet das Add-on bei Music Assistant als Player an (mDNS, kein Server-URL
# noetig). Der Ton laeuft in den Standard-Sink, dessen Monitor LedFx aufnimmt -
# Kette: Music Assistant -> Sendspin -> Sink -> LedFx -> WLED.
case "$SENDSPIN" in
    True|true|1)
        if [ ! -x /opt/sendspin/bin/sendspin ]; then
            echo "[ledfx] FEHLER: Sendspin-Client fehlt im Image. Add-on neu bauen."
        else
            SS_CFG="$CONFIG_DIR/.config/sendspin"
            mkdir -p "$SS_CFG"
            # MPRIS braucht einen D-Bus-Session-Bus, den es im Container nicht
            # gibt. Nur als Startwert schreiben - der Daemon pflegt die Datei
            # danach selbst (Lautstaerke, client_id, Pairing).
            if [ ! -f "$SS_CFG/settings-daemon.json" ]; then
                echo '{"use_mpris": false}' > "$SS_CFG/settings-daemon.json"
            fi
            echo "[ledfx] Starte Sendspin-Daemon als '$SENDSPIN_NAME' (Port 8927)."
            # Exit-Code mitloggen: stirbt der Daemon still, sieht man sonst
            # ueberhaupt nichts im Protokoll.
            # sed -u ist Pflicht: ohne das puffert sed blockweise, solange
            # stdout kein Terminal ist - im Docker-Log erscheint dann selbst
            # von einem laufenden Daemon minutenlang gar nichts.
            (
                HOME="$CONFIG_DIR" /opt/sendspin/bin/sendspin daemon --name "$SENDSPIN_NAME" --audio-device pulse 2>&1
                echo "Daemon beendet (Exit $?)."
            ) | sed -u 's/^/[sendspin] /' &
            SS_PID=$!
            sleep 2
            if kill -0 "$SS_PID" 2>/dev/null; then
                echo "[ledfx] Sendspin laeuft (PID $SS_PID)."
            else
                echo "[ledfx] Sendspin wurde sofort beendet - siehe [sendspin]-Zeilen."
            fi
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
