ARG BUILD_FROM=ghcr.io/ledfx/ledfx:2.1.9
FROM ${BUILD_FROM}

# Vom HA-Builder gesetzt, hier nur deklariert damit es keine Warnung gibt.
ARG BUILD_ARCH
ARG BUILD_VERSION

# Das Upstream-Image endet mit "USER ledfx" (uid 1000). apt braucht root, und
# HA-Add-ons laufen als root, sonst ist /share nicht beschreibbar.
USER root

# Debian trixie (python:3.12). libportaudio2 und pulseaudio sind schon drin,
# aber mit --no-install-recommends gebaut - die ALSA->PulseAudio-Bruecke fehlt
# also. Ohne libasound2-plugins sieht PortAudio (und damit LedFx) den
# PulseAudio-Server des Supervisors nicht.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libasound2-plugins pulseaudio-utils \
    && rm -rf /var/lib/apt/lists/*

# Kein eigenes /etc/asound.conf noetig: der Supervisor mountet bei
# 'audio: true' seine eigene Vorlage schreibgeschuetzt nach /etc/asound.conf
# (pcm.!default -> type pulse) und ueberschreibt damit jede eigene Datei.
# Das Plugin dahinter liefert er aber NICHT mit - darum oben libasound2-plugins.

COPY run.sh /run.sh
COPY healthcheck.sh /healthcheck.sh
COPY sendspin_register.py /sendspin_register.py
RUN chmod a+x /run.sh /healthcheck.sh

# Der Upstream-Healthcheck prueft "pactl info" - das sagt nichts darueber aus,
# ob LedFx laeuft, und macht das Add-on ohne Audio-Hardware dauerhaft unhealthy.
# Ersetzt durch einen Check gegen die Web-UI. NICHT auf "HEALTHCHECK NONE"
# aendern: Home Assistant haelt das fuer einen vorhandenen Healthcheck, der nie
# ein Ergebnis liefert, und zeigt das Add-on fuer immer als "wird gestartet".
# start-period grosszuegig, LedFx braucht auf einem Pi den Moment zum Hochfahren.
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3     CMD /healthcheck.sh

# /share wird vom Supervisor zur Laufzeit ueber den Container gemountet,
# das Unterverzeichnis legt run.sh beim Start an.

LABEL \
    io.hass.name="LedFx" \
    io.hass.description="Audio-reactive LED-Steuerung fuer WLED & Co." \
    io.hass.type="addon" \
    io.hass.arch="aarch64|amd64" \
    io.hass.version="${BUILD_VERSION}"

# Ersetzt /home/ledfx/start.sh (startet einen containereigenen PulseAudio-Daemon,
# den wir nicht wollen - wir nutzen den des Supervisors).
ENTRYPOINT []
CMD ["/run.sh"]
