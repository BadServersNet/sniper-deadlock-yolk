#!/bin/bash
set -Eeuo pipefail

# steamcmd Base Installation Script
#
# Server Files: /mnt/server

STEAMWORKS_REDIST_APPID=1007
STEAMWORKS_REDIST_DIR=/mnt/server/steamworks-redist

if [ -z "${STEAM_USER:-}" ] || [ "${STEAM_USER}" == "anonymous" ]; then
  echo "A Steam account that owns Deadlock is required. Set STEAM_USER." >&2
  exit 1
fi

## download and install steamcmd
mkdir -p /mnt/server/steamcmd
curl --fail --show-error --silent --location \
  --output /tmp/steamcmd.tar.gz \
  https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz

tar -xzf /tmp/steamcmd.tar.gz -C /mnt/server/steamcmd

mkdir -p /mnt/server/steamapps

cd /mnt/server/steamcmd

# SteamCMD fails otherwise for some reason, even running as root.
# This is changed at the end of the install process anyways.
chown -R root:root /mnt
export HOME=/mnt/server

## install game using steamcmd
steam_login=(+login "${STEAM_USER}" "${STEAM_PASS:-}" "${STEAM_AUTH:-}")
steam_update=(+app_update "${APPID}")

if [ "${VALIDATE:-0}" != "0" ]; then
  steam_update+=(validate)
fi

./steamcmd.sh \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir /mnt/server \
  "${steam_login[@]}" \
  "${steam_update[@]}" \
  +quit | tee /tmp/steamcmd-install.log

if ! grep -Fq "Success! App '${APPID}' fully installed." \
  /tmp/steamcmd-install.log; then
  echo "SteamCMD did not report a completed app installation." >&2
  exit 1
fi

if [ ! -f /mnt/server/game/bin/win64/deadlock.exe ]; then
  echo "SteamCMD finished without installing deadlock.exe." >&2
  exit 1
fi

## install the Windows Steam client libraries used inside the Proton prefix
./steamcmd.sh \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir "${STEAMWORKS_REDIST_DIR}" \
  +login anonymous \
  +app_update "${STEAMWORKS_REDIST_APPID}" \
  +quit | tee /tmp/steamcmd-redist.log

if ! grep -Fq "Success! App '${STEAMWORKS_REDIST_APPID}' fully installed." \
  /tmp/steamcmd-redist.log; then
  echo "SteamCMD did not report a completed Steamworks redistributable installation." >&2
  exit 1
fi

if [ ! -f "${STEAMWORKS_REDIST_DIR}/steamclient64.dll" ]; then
  echo "SteamCMD finished without installing steamclient64.dll." >&2
  exit 1
fi

## set up 32 bit libraries
mkdir -p /mnt/server/.steam/sdk32
cp -v linux32/steamclient.so /mnt/server/.steam/sdk32/steamclient.so

## set up 64 bit libraries
mkdir -p /mnt/server/.steam/sdk64
cp -v linux64/steamclient.so /mnt/server/.steam/sdk64/steamclient.so
