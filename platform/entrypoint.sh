#!/bin/bash
set -Eeuo pipefail

#
# Copyright (c) 2021 Matthew Penner
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# Give everything time to initialize for preventing SteamCMD deadlock
sleep 1

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the container's working directory
cd /home/container || exit 1

STEAMWORKS_REDIST_APPID=1007
STEAMWORKS_REDIST_DIR="/home/container/steamworks-redist"
PREFIX_STEAM_DIR="${STEAM_COMPAT_DATA_PATH}/pfx/drive_c/Program Files (x86)/Steam"
GAME_EXECUTABLE="/home/container/game/bin/win64/deadlock.exe"
CONSOLE_LOG="/home/container/game/citadel/console.log"

if [ -z "${STEAM_USER:-}" ] || [ "${STEAM_USER}" == "anonymous" ]; then
  echo "A Steam account that owns Deadlock is required. Set STEAM_USER." >&2
  exit 1
fi

echo -e "user set to ${STEAM_USER}"

## if auto_update is not set or to 1 update
if [ -z "${AUTO_UPDATE:-}" ] || [ "${AUTO_UPDATE}" == "1" ]; then
  if [ -n "${APPID:-}" ]; then
    steam_login=(+login "${STEAM_USER}" "${STEAM_PASS:-}" "${STEAM_AUTH:-}")
    steam_update=(+app_update "${APPID}")

    if [ "${VALIDATE:-0}" != "0" ]; then
      steam_update+=(validate)
    fi

    ./steamcmd/steamcmd.sh \
      +@sSteamCmdForcePlatformType windows \
      +force_install_dir /home/container \
      "${steam_login[@]}" \
      "${steam_update[@]}" \
      +quit

    ./steamcmd/steamcmd.sh \
      +@sSteamCmdForcePlatformType windows \
      +force_install_dir "${STEAMWORKS_REDIST_DIR}" \
      +login anonymous \
      +app_update "${STEAMWORKS_REDIST_APPID}" \
      +quit
  else
    echo -e "No appid set. Starting Server"
  fi

else
  echo -e "Not updating game server as auto update was set to 0. Starting Server"
fi

if [ ! -f "${GAME_EXECUTABLE}" ]; then
  echo "Deadlock is not installed at ${GAME_EXECUTABLE}. Reinstall the server." >&2
  exit 1
fi

install_steam_client_dlls() {
  local dll

  mkdir -p "${PREFIX_STEAM_DIR}"

  for dll in steamclient64.dll steamwebrtc64.dll tier0_s64.dll vstdlib_s64.dll; do
    if [ ! -f "${STEAMWORKS_REDIST_DIR}/${dll}" ]; then
      echo "${dll} is missing from ${STEAMWORKS_REDIST_DIR}. Reinstall the server." >&2
      exit 1
    fi

    cp -f -- "${STEAMWORKS_REDIST_DIR}/${dll}" "${PREFIX_STEAM_DIR}/${dll}"
  done
}

install_steam_client_libraries() {
  local arch

  for arch in 32 64; do
    mkdir -p "/home/container/.steam/sdk${arch}"
    cp -f -- "/home/container/steamcmd/linux${arch}/steamclient.so" "/home/container/.steam/sdk${arch}/steamclient.so"
  done
}

start_virtual_display() {
  local display_number="${DISPLAY#:}"

  rm -f -- "/tmp/.X${display_number}-lock" "/tmp/.X11-unix/X${display_number}"
  Xvfb "${DISPLAY}" -screen 0 640x480x24 -nolisten tcp &

  sleep 1
}

follow_console_log() {
  : >"${CONSOLE_LOG}"
  tail -F -n +1 "${CONSOLE_LOG}" &
}

mkdir -p "${STEAM_COMPAT_CLIENT_INSTALL_PATH}"
install_steam_client_libraries
install_steam_client_dlls
start_virtual_display
follow_console_log

exec python3 /startup.py
