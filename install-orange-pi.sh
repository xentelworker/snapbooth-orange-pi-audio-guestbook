#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/opt/rotary-phone-audio-guestbook"
SERVICE_DIR="/etc/systemd/system"
AUDIO_CARD="Device"

log(){ printf '\n[SnapBooth] %s\n' "$*"; }
die(){ printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this installer as root."
[[ -f /etc/os-release ]] || die "Cannot identify the operating system."
source /etc/os-release
case "${ID:-}" in debian|ubuntu|armbian) ;; *) log "Warning: designed for Armbian/Debian; detected ${PRETTY_NAME:-unknown}." ;; esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/src/audioGuestBook.py" ]] || die "Run this script from the repository checkout."

if [[ "${1:-}" == "--check" ]]; then
  log "Orange Pi Audio Guestbook diagnostic"
  printf 'Repository: %s\n' "$SCRIPT_DIR"
  printf 'Model: '; cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || true; echo
  printf 'Python: '; python3 --version || true
  printf 'gpiod: '; gpiodetect --version 2>/dev/null | head -1 || true
  printf 'USB audio: '; aplay -l 2>/dev/null | grep -m1 "card .*Device" || echo "NOT FOUND"
  systemctl --no-pager --quiet is-active audioGuestBook.service && echo "Main service: active" || echo "Main service: inactive"
  systemctl --no-pager --quiet is-active audioGuestBookWebServer.service && echo "Web service: active" || echo "Web service: inactive"
  printf 'Recordings: '; find "$APP_DIR/recordings" -maxdepth 1 -type f 2>/dev/null | wc -l
  df -h "$APP_DIR" 2>/dev/null | tail -1 || true
  exit 0
fi

log "Installing required packages (no full system upgrade)"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git python3 python3-pip python3-gpiod gpiod alsa-utils ffmpeg \
  python3-flask python3-gevent python3-yaml python3-psutil gunicorn

if [[ "$SCRIPT_DIR" != "$APP_DIR" ]]; then
  [[ ! -e "$APP_DIR" ]] || die "$APP_DIR already exists. Run the installer from that checkout or move it first."
  log "Installing repository into $APP_DIR"
  cp -a "$SCRIPT_DIR" "$APP_DIR"
fi

cd "$APP_DIR"
mkdir -p recordings

if [[ ! -f config.yaml ]]; then
  log "Creating config.yaml from Orange Pi example"
  cp config.example.yaml config.yaml
else
  log "Keeping existing config.yaml"
fi

[[ -f systemd/audioGuestBook.service ]] || die "Missing main systemd service file."
[[ -f systemd/audioGuestBookWebServer.service ]] || die "Missing web systemd service file."

log "Installing systemd services"
install -m 0644 systemd/audioGuestBook.service "$SERVICE_DIR/audioGuestBook.service"
install -m 0644 systemd/audioGuestBookWebServer.service "$SERVICE_DIR/audioGuestBookWebServer.service"
systemctl daemon-reload
systemctl enable audioGuestBook.service audioGuestBookWebServer.service

if aplay -l 2>/dev/null | grep -q "card .*Device"; then
  log "USB audio adapter detected"
  amixer -D "hw:CARD=$AUDIO_CARD" sset Speaker 70% >/dev/null 2>&1 || true
  amixer -D "hw:CARD=$AUDIO_CARD" sset Mic 75% cap >/dev/null 2>&1 || true
  amixer -D "hw:CARD=$AUDIO_CARD" sset 'Auto Gain Control' off >/dev/null 2>&1 || true
  alsactl store >/dev/null 2>&1 || true
else
  log "WARNING: USB audio adapter 'Device' was not detected. Services will be installed but audio must be checked."
fi

log "Starting services"
systemctl restart audioGuestBook.service
systemctl restart audioGuestBookWebServer.service

sleep 2
systemctl --no-pager --full status audioGuestBook.service | head -12 || true
systemctl --no-pager --full status audioGuestBookWebServer.service | head -12 || true

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
log "Installation complete"
echo "Web UI: http://${IP:-<orange-pi-ip>}:8080"
echo "Run '$APP_DIR/install-orange-pi.sh --check' for diagnostics."
