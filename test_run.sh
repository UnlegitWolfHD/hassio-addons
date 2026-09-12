#!/bin/sh
# Selbsttest fuer ledfx/run.sh: stubbt pactl/sendspin/ledfx und prueft, welche
# Kommandozeile und welche Audio-Umgebung am Ende bei LedFx ankommt.
# Aufruf:  sh test_run.sh
set -e

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Zwei Pfadwelten: PATH und Shell-Befehle brauchen unter Git Bash die
# MSYS-Form (/tmp/...), das in run.sh eingebettete Python als natives
# Windows-Programm aber C:/... - sonst sucht es die Optionsdatei in C:/tmp.
TMPW="$TMP"
REPOW="$PWD"
if command -v cygpath >/dev/null 2>&1; then
    TMPW=$(cygpath -m "$TMP")
    REPOW=$(cygpath -m "$PWD")
fi
BIN="$TMP/bin"
mkdir -p "$BIN"
touch "$TMP/pulse.sock"

# run.sh mit Testpfaden statt Containerpfaden
sed -e "s|/data/options.json|$TMPW/options.json|g" \
    -e "s|CONFIG_DIR=/share/ledfx|CONFIG_DIR=$TMP/share/ledfx|" \
    -e "s|\[ -S /run/audio/pulse.sock \]|[ -e $TMP/pulse.sock ]|" \
    -e "s|python3 /sendspin_register.py|python3 '$REPOW/ledfx/sendspin_register.py'|g" \
    ledfx/run.sh > "$TMP/run.sh"

cat > "$BIN/pactl" <<'EOS'
#!/bin/sh
# Stub mit Zustand: FAKE_SINKS simuliert vorhandene Hardware, $STATE/nullsink
# merkt sich ein zuvor angelegtes Null-Sink.
echo "PACTL $*" >> "$LOG"
if [ "$1" = "list" ]; then
    case "$3" in
        sinks)
            [ -n "$FAKE_SINKS" ] && echo "0 alsa_output.hw0 module-alsa-card.c RUNNING"
            [ -f "$STATE/nullsink" ] && echo "1 ledfx module-null-sink.c IDLE"
            ;;
        sources)
            [ -n "$FAKE_SINKS" ] && echo "0 alsa_output.hw0.monitor module-alsa-card.c IDLE"
            [ -f "$STATE/nullsink" ] && echo "1 ledfx.monitor module-null-sink.c IDLE"
            ;;
        modules)
            [ -f "$STATE/nullsink" ] && echo "0 module-null-sink sink_name=ledfx"
            ;;
    esac
fi
[ "$1" = "load-module" ] && touch "$STATE/nullsink"
exit 0
EOS

cat > "$BIN/ledfx" <<'EOS'
#!/bin/sh
echo "LEDFX $*" >> "$LOG"
echo "ENV PULSE_SERVER=$PULSE_SERVER PULSE_SOURCE=${PULSE_SOURCE-<unset>} PULSE_COOKIE=${PULSE_COOKIE-<unset>}" >> "$LOG"
EOS
chmod +x "$BIN"/pactl "$BIN"/ledfx

run_case() {   # run_case <name> <options-json>
    NAME="$1"
    echo "$2" > "$TMPW/options.json"
    LOG="$TMP/log"; : > "$LOG"
    STATE="$TMP/state"; rm -rf "$STATE"; mkdir -p "$STATE"
    # Umgebung wie im Upstream-Image vorbelegen
    PULSE_SERVER=unix:/home/ledfx/.config/pulse/pulseaudio.socket \
    PULSE_COOKIE=/home/ledfx/.config/pulse/cookie \
    LOG="$LOG" STATE="$STATE" FAKE_SINKS="$FAKE_SINKS" PATH="$BIN:$PATH" sh "$TMP/run.sh" >> "$LOG" 2>&1 || echo "RUN_SH_EXIT=$?" >> "$LOG"
    sleep 3   # run.sh prueft selbst 2s lang, ob der Daemon lebt
    echo "--- $NAME"
    cat "$LOG"
}

expect() {  # expect <muster> <beschreibung>
    if grep -q -- "$1" "$TMP/log"; then
        echo "  OK   $2"
    else
        echo "  FAIL $2  (erwartet: $1)"; FAILED=1
    fi
}

FAILED=0

run_case "Standard" '{}'
expect "LEDFX --host 0.0.0.0 --port 8888 --config $TMP/share/ledfx" "Basis-Argumente"
expect "PULSE_SERVER=unix:/run/audio/pulse.sock" "PULSE_SERVER umgebogen"
expect "PULSE_COOKIE=<unset>" "PULSE_COOKIE entfernt"
expect "PULSE_SOURCE=<unset>" "keine erzwungene Quelle"

run_case "Verbose + offline + Port" '{"port":9000,"log_level":"trace","offline_mode":true}'
expect "LEDFX --host 0.0.0.0 --port 9000 --config $TMP/share/ledfx -vv --offline" "Flags gemappt"

run_case "Null-Sink" '{"null_sink":true}'
expect "PACTL load-module module-null-sink sink_name=ledfx" "Null-Sink angelegt"
expect "PACTL set-default-sink ledfx" "Standard-Ausgang gesetzt"
expect "PULSE_SOURCE=ledfx.monitor" "LedFx nimmt den Monitor auf"

run_case "Sendspin ohne Server-URL" '{"sendspin":true}'
expect "sendspin_server ist leer" "fehlende URL wird gemeldet"

# LedFx-Konfiguration vorbereiten, damit das Registrierungsskript sie findet
mkdir -p "$TMP/share/ledfx"
echo '{"configuration_version":"2.3.6","devices":[]}' > "$TMP/share/ledfx/config.json"
run_case "Sendspin mit Server-URL" '{"sendspin":true,"sendspin_server":"ws://10.0.0.5:8927/sendspin","sendspin_name":"Wohnzimmer"}'
expect "eingetragen: ws://10.0.0.5:8927/sendspin" "Server in config.json eingetragen"

echo "--- Registrierung in der LedFx-Konfiguration"
python - "$TMPW/share/ledfx/config.json" <<'PYEOF'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
entry = cfg["sendspin_servers"]["music-assistant"]
assert entry["server_url"] == "ws://10.0.0.5:8927/sendspin", entry
assert entry["client_name"] == "Wohnzimmer", entry
assert cfg["configuration_version"] == "2.3.6", "bestehende Konfiguration ueberlebt nicht"
assert cfg["devices"] == [], "bestehende Konfiguration ueberlebt nicht"
print("  OK   Eintrag korrekt, restliche Konfiguration unangetastet")
PYEOF

# Zweiter Lauf darf nichts doppeln
run_case "Sendspin erneut (idempotent)" '{"sendspin":true,"sendspin_server":"ws://10.0.0.5:8927/sendspin","sendspin_name":"Wohnzimmer"}'
expect "ist bereits eingetragen" "zweiter Start aendert nichts"

# Kaputte Konfiguration darf nicht ueberschrieben werden
echo 'kein json' > "$TMP/share/ledfx/config.json"
run_case "Sendspin mit defekter config.json" '{"sendspin":true,"sendspin_server":"ws://10.0.0.5:8927/sendspin"}'
expect "nicht lesbar" "defekte Konfiguration wird gemeldet"
if [ "$(cat "$TMP/share/ledfx/config.json")" = "kein json" ]; then
    echo "  OK   defekte Konfiguration blieb unveraendert"
else
    echo "  FAIL defekte Konfiguration wurde ueberschrieben"; FAILED=1
fi
rm -f "$TMP/share/ledfx/config.json"

# --- healthcheck.sh ------------------------------------------------------
# Der Add-on-Zustand in Home Assistant haengt daran: meldet der Healthcheck nie
# ein Ergebnis, bleibt das Add-on fuer immer auf "wird gestartet".
echo
echo "--- healthcheck.sh"
HC="$TMP/healthcheck.sh"
sed "s|/data/options.json|$TMPW/options.json|g" ledfx/healthcheck.sh > "$HC"
chmod +x "$HC"

HC_PORT=18888
python -m http.server "$HC_PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
HTTP_PID=$!
trap 'kill "$HTTP_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
sleep 2

hc_case() {  # hc_case <beschreibung> <options-json> <erwarteter exit>
    echo "$2" > "$TMPW/options.json"
    # if-Form statt blankem Aufruf: unter "set -e" wuerde ein erwarteter
    # Fehlschlag sonst den ganzen Test abbrechen.
    if sh "$HC" >/dev/null 2>&1; then RC=0; else RC=$?; fi
    if [ "$RC" = "$3" ]; then
        echo "  OK   $1 (Exit $RC)"
    else
        echo "  FAIL $1 -> Exit $RC, erwartet $3"; FAILED=1
    fi
}

hc_case "laufende UI auf 0.0.0.0 -> gesund"      "{\"host\":\"0.0.0.0\",\"port\":$HC_PORT}" 0
hc_case "leere Optionen -> Standardport, nichts da" "{}" 1
hc_case "falscher Port -> ungesund"              "{\"port\":18999}" 1
hc_case "abweichender Host wird respektiert"     "{\"host\":\"127.0.0.1\",\"port\":$HC_PORT}" 0

kill "$HTTP_PID" 2>/dev/null

echo
if [ "$FAILED" = "1" ]; then echo "TESTS FEHLGESCHLAGEN"; exit 1; else echo "ALLE TESTS OK"; fi
