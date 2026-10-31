# Pterodactyl Deadlock Egg

https://gitlab.steamos.cloud/steamrt/sniper/platform

Valve only ships Deadlock (app `1422450`) as a Windows build, so this image runs
`game/bin/win64/deadlock.exe -dedicated` through
[GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom) on the Steam
Linux Runtime Sniper, with Xvfb and Mesa llvmpipe for the headless display.
GE-Proton is pinned by version and SHA-512 in `platform/Dockerfile`.

## Requirements

- A Steam account that owns Deadlock. Anonymous SteamCMD logins cannot download it.
- About 40 GB of disk and at least 8 GB of memory per server.
- `vm.max_map_count` raised on the node, for example `sysctl -w vm.max_map_count=2147483642`.

## Steam login

Set `STEAM_USER`, `STEAM_PASS`, and a current Steam Guard code in `STEAM_AUTH`
before installing. SteamCMD caches the login under `steamcmd/` in the server
files, so clear `STEAM_PASS` and `STEAM_AUTH` after the install; later updates
log in with the cached session. If the cached session expires, set them again
with a fresh Steam Guard code and restart.

## Steam client libraries

The install script and every update download the Windows Steamworks SDK
Redistributable (app `1007`) to `steamworks-redist/`. On startup the launcher
copies its 64-bit Steam client DLLs into the Proton prefix at
`.proton/pfx/drive_c/Program Files (x86)/Steam/`.

## Startup arguments

The launcher splits `STARTUP` using shell-style quotes before replacing
`{{VARIABLE}}`, `${VARIABLE}`, or `$VARIABLE` references with environment values.
Each replacement stays inside its original argument, including empty strings,
spaces, quote characters, and wildcards. Undefined variables and malformed quotes
fail startup. Environment values are never evaluated as shell commands.

For example, `+sv_password {{PASSWORD}}` supplies exactly one password argument,
even when `PASSWORD` is empty. Shell operators and command substitution are not
evaluated by the launcher; commands needing shell logic must explicitly invoke a
shell script.

## Console

Proton launches the game through its `steam.exe` helper, which does not pass the
game's stdout through. The startup line uses `-condebug`, and the launcher
truncates and follows `game/citadel/console.log` so the panel console shows the
server output.

Proton does not pass stdin through either, so the launcher forwards each line
typed in the panel console to the game over RCON on `127.0.0.1`. On every start
it writes a random RCON password to `game/citadel/cfg/pterodactyl_rcon.cfg` and
appends `+exec pterodactyl_rcon.cfg` to the startup arguments, which keeps the
password out of the logged command line. Command output appears through
`console.log`; RCON failures, such as a command sent before the server is ready,
are printed by the launcher.

The server listens on the allocation port for game traffic (UDP) and RCON (TCP).
The panel stops it with `quit`. `SIGINT` and `SIGTERM` are forwarded to Proton
as `SIGTERM`.
