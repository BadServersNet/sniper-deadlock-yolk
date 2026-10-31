import os
import re
import secrets
import shlex
import signal
import socket
import struct
import subprocess
import sys
import threading
from pathlib import Path
from typing import List, Optional, Tuple


VARIABLE = re.compile(
    r"\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}"
    r"|\$\{([A-Za-z_][A-Za-z0-9_]*)\}"
    r"|\$([A-Za-z_][A-Za-z0-9_]*)"
)

RCON_HOST = "127.0.0.1"
RCON_CONFIG_NAME = "pterodactyl_rcon.cfg"
RCON_CONFIG_PATH = Path("/home/container/game/citadel/cfg") / RCON_CONFIG_NAME
RCON_TIMEOUT_SECONDS = 5
SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0
AUTH_FAILED_ID = -1


def expand_variable(match: re.Match[str]) -> str:
    name = next(group for group in match.groups() if group is not None)
    value = os.environ.get(name)
    if value is None:
        raise ValueError(f"Startup variable is not set: {name}")
    return value


def parse_startup() -> List[str]:
    startup = os.environ["STARTUP"]
    tokens = shlex.split(startup)
    arguments = [VARIABLE.sub(expand_variable, token) for token in tokens]
    if not arguments:
        raise ValueError("Startup command is empty")
    return arguments


def read_rcon_port() -> int:
    port = os.environ.get("SERVER_PORT")
    if port is None:
        raise ValueError("Startup variable is not set: SERVER_PORT")
    return int(port)


def write_rcon_config(password: str) -> None:
    contents = f'rcon_password "{password}"\n'
    RCON_CONFIG_PATH.write_text(contents)
    RCON_CONFIG_PATH.chmod(0o600)


class RconClient:
    def __init__(self, port: int, password: str) -> None:
        self.port = port
        self.password = password
        self.connection: Optional[socket.socket] = None
        self.next_id = 1

    def allocate_id(self) -> int:
        request_id = self.next_id
        self.next_id += 1
        return request_id

    def send(self, request_id: int, kind: int, body: str) -> None:
        encoded_body = body.encode()
        payload = struct.pack("<ii", request_id, kind) + encoded_body + b"\x00\x00"
        size = struct.pack("<i", len(payload))
        self.connection.sendall(size + payload)

    def receive_exactly(self, size: int) -> bytes:
        data = b""
        while len(data) < size:
            remaining = size - len(data)
            chunk = self.connection.recv(remaining)
            if not chunk:
                raise ConnectionError("RCON connection closed")
            data += chunk
        return data

    def receive(self) -> Tuple[int, int, str]:
        header = self.receive_exactly(4)
        size = struct.unpack("<i", header)[0]
        data = self.receive_exactly(size)
        request_id, kind = struct.unpack("<ii", data[:8])
        body = data[8:-2].decode(errors="replace")
        return request_id, kind, body

    def connect(self) -> None:
        address = (RCON_HOST, self.port)
        self.connection = socket.create_connection(address, RCON_TIMEOUT_SECONDS)
        auth_id = self.allocate_id()
        self.send(auth_id, SERVERDATA_AUTH, self.password)
        self.wait_for_auth()

    def wait_for_auth(self) -> None:
        while True:
            request_id, kind, _ = self.receive()
            if kind != SERVERDATA_AUTH_RESPONSE:
                continue
            if request_id == AUTH_FAILED_ID:
                raise ConnectionError("RCON authentication failed")
            return

    def close(self) -> None:
        if self.connection is None:
            return
        self.connection.close()
        self.connection = None

    def execute(self, command: str) -> str:
        if self.connection is None:
            self.connect()
        command_id = self.allocate_id()
        marker_id = self.allocate_id()
        self.send(command_id, SERVERDATA_EXECCOMMAND, command)
        self.send(marker_id, SERVERDATA_RESPONSE_VALUE, "")
        return self.read_response(command_id, marker_id)

    def read_response(self, command_id: int, marker_id: int) -> str:
        parts = []
        while True:
            request_id, _, body = self.receive()
            if request_id == marker_id:
                return "".join(parts)
            if request_id == command_id:
                parts.append(body)


def run_console_command(client: RconClient, command: str) -> None:
    try:
        client.execute(command)
    except OSError as error:
        client.close()
        print(f"RCON command failed: {error}", flush=True)


def forward_console(client: RconClient) -> None:
    for line in sys.stdin:
        command = line.strip()
        if not command:
            continue
        run_console_command(client, command)


def forward_signals(process: subprocess.Popen) -> None:
    def forward(_signum: int, _frame: object) -> None:
        process.terminate()

    signal.signal(signal.SIGINT, forward)
    signal.signal(signal.SIGTERM, forward)


def to_exit_code(return_code: int) -> int:
    if return_code < 0:
        return 128 - return_code
    return return_code


def main() -> None:
    try:
        arguments = parse_startup()
        port = read_rcon_port()
    except (KeyError, ValueError) as error:
        print(f"Invalid startup command: {error}", file=sys.stderr)
        sys.exit(1)

    password = secrets.token_hex(16)
    write_rcon_config(password)
    command = ["env", *arguments, "+exec", RCON_CONFIG_NAME]

    print("container@pterodactyl~ Starting server.", flush=True)
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL)
    forward_signals(process)

    client = RconClient(port, password)
    console_thread = threading.Thread(
        target=forward_console, args=(client,), daemon=True
    )
    console_thread.start()

    return_code = process.wait()
    exit_code = to_exit_code(return_code)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
