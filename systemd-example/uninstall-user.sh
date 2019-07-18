#!/bin/bash

set -euo pipefail

SERVICE="buildenlights"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user/"
systemctl --user disable --now "${SERVICE}"
rm "${USER_SYSTEMD_DIR}/${SERVICE}.service"
systemctl --user daemon-reload
echo "Successfully uninstalled systemd unit ${SERVICE}.service in ~/.config/systemd/user."

