#!/bin/bash

set -euo pipefail

cd "$(dirname "${0}")"

REAL_PATH="$(realpath ../buildenlights.sh)"
DIR_NAME="$(dirname "${REAL_PATH}")"
SERVICE="buildenlights"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user/"
mkdir -p "${USER_SYSTEMD_DIR}" # create systemd user dir
sed < ./buildenlights.service "s~%h~${DIR_NAME}~g" > "${USER_SYSTEMD_DIR}/${SERVICE}.service" # fix the script path
systemctl --user daemon-reload
systemctl --user enable "${SERVICE}"
echo "Successfully installed systemd unit ${SERVICE}.service in ~/.config/systemd/user ; not started yet."
echo ""
echo "To (re)start:"
echo "systemctl --user restart ${SERVICE}"
echo "To edit the unit parameters:"
echo "systemctl --user edit --full ${SERVICE}"
echo "To change the script parameters, edit ${DIR_NAME}/buildenlights.rc"
echo "editor ${DIR_NAME}/buildenlights.rc"
