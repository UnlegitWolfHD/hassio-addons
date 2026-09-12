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
if command -v cygpath >/dev/null 2>&1; then TMPW=$(cygpath -m "$TMP"); fi
BIN="$TMP/bin"
mkdir -p "$BIN"
touch "$TMP/pulse.sock"

# run.sh mit Testpfaden statt Containerpfaden
sed -e "s|/data/options.json|$TMPW/options.json|g" \
    -e "s|CONFIG_DIR=/share/ledfx|CONFIG_DIR=$TMP/share/ledfx|" \
    -e "s|\[ -S /run/audio/pulse.sock \]|[ -e $TMP/pulse.sock ]|" \
    -e "s|/opt/sendspin/bin/sendspin|$BIN/sendspin|g" \
    ledfx/run.sh > "$TMP/run.sh"

cat > "$BIN/pactl" <<'EOS'
#!/bin/sh
echo "PACTL $*" >> "$LOG"
[ "$1" = "list" ] && [ "$3" = "sources" ] && echo "0 ledfx.monitor module-null-sink.c IDLE"
exit 0
EOS
cat > "$BIN/sendspin" <<'EOS'
#!/bin/sh
echo "SENDSPIN $* HOME=$HOME" >> "$LOG"
EOS
cat > "$BIN/ledfx" <<'EOS'
#!/bin/sh
echo "LEDFX $*" >> "$LOG"
echo "ENV PULSE_SERVER=$PULSE_SERVER PULSE_SOURCE=${PULSE_SOURCE-<unset>} PULSE_COOKIE=${PULSE_COOKIE-<unset>}" >> "$LOG"
EOS
chmod +x "$BIN"/pactl "$BIN"/sendspin "$BIN"/ledfx

run_case() {   # run_case <name> <options-json>
    NAME="$1"
    echo "$2" > "$TMPW/options.json"
    LOG="$TMP/log"; : > "$LOG"
    # Umgebung wie im Upstream-Image vorbelegen
    PULSE_SERVER=unix:/home/ledfx/.config/pulse/pulseaudio.socket \
    PULSE_COOKIE=/home/ledfx/.config/pulse/cookie \
    LOG="$LOG" PATH="$BIN:$PATH" sh "$TMP/run.sh" >> "$LOG" 2>&1 || echo "RUN_SH_EXIT=$?" >> "$LOG"
    sleep 1   # Sendspin laeuft im Hintergrund
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

run_case "Sendspin + Null-Sink" '{"sendspin":true,"sendspin_name":"Wohnzimmer","null_sink":true}'
expect "SENDSPIN daemon --name Wohnzimmer --audio-device pulse" "Daemon mit Namen gestartet"
expect "HOME=$TMP/share/ledfx" "Sendspin-Config liegt persistent"
expect "PULSE_SOURCE=ledfx.monitor" "Kette Sendspin -> Sink -> LedFx"

run_case "Sendspin ohne Sink" '{"sendspin":true}'
expect "HINWEIS: sendspin=true, aber null_sink=false" "Warnung ohne Audio-Ziel"

echo
[ -f "$TMP/share/ledfx/.config/sendspin/settings-daemon.json" ] \
  && echo "  OK   settings-daemon.json angelegt: $(cat "$TMP/share/ledfx/.config/sendspin/settings-daemon.json")" \
  || { echo "  FAIL settings-daemon.json fehlt"; FAILED=1; }

echo
if [ "$FAILED" = "1" ]; then echo "TESTS FEHLGESCHLAGEN"; exit 1; else echo "ALLE TESTS OK"; fi
