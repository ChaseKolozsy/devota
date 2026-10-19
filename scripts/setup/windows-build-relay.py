"""Cradlespeak WSL relay (Windows side, no admin needed).

Listens on every Windows interface (incl. the ZeroTier address the
phone targets) and forwards each connection into WSL:

    :8002 -> WSL gateway   (desktop/bin/cradle)
    :8003 -> desktop QA server
    :8082 -> DevOTA build server (dev-ota/server/devota_server.py)

Also supervises the Windows-native DevOTA phone-agent relay (:8083), with
its live MCP control endpoint on loopback :18783. It restarts after a crash
and waits for WSL/ZeroTier when they are not ready at sign-in.

The WSL NAT IP is resolved via `wsl.exe hostname -I`, cached, and
re-resolved automatically when a connection fails — so this survives
WSL restarts and IP changes without any netsh portproxy or elevation.

Run by the Startup-folder entry cradlespeak_build_relay.bat, or by hand:
    python C:\\Users\\chase\\cradlespeak_build_relay.py
"""
import socket
import os
import json
import urllib.request
from pathlib import Path
import subprocess
import threading
import time

PORTS = [8002, 8003, 8004, 8082]

_wsl_ip = None
_wsl_ip_ts = 0.0
_ip_lock = threading.Lock()


def wsl_ip(force=False):
    global _wsl_ip, _wsl_ip_ts
    with _ip_lock:
        if not force and _wsl_ip and time.time() - _wsl_ip_ts < 300:
            return _wsl_ip
        try:
            out = subprocess.run(
                ["wsl.exe", "-e", "hostname", "-I"],
                capture_output=True, text=True, timeout=15,
            ).stdout.strip()
            ip = out.split()[0] if out else None
        except Exception:
            ip = None
        if ip:
            _wsl_ip, _wsl_ip_ts = ip, time.time()
        return _wsl_ip


def connect_upstream(port):
    ip = wsl_ip()
    candidates = [ip] if ip else []
    # Never fall back to Windows localhost: a legacy build server may own
    # that port, or the connection could loop back into this relay itself.
    for host in candidates:
        try:
            connection = socket.create_connection((host, port), timeout=8)
            connection.settimeout(None)
            return connection
        except OSError:
            continue
    # one retry with a forced IP refresh (WSL may have rebooted)
    ip = wsl_ip(force=True)
    if ip:
        try:
            connection = socket.create_connection((ip, port), timeout=8)
            connection.settimeout(None)
            return connection
        except OSError:
            pass
    return None


def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        # Preserve the response after the request side closes its write half.
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def relay_client(client, port):
    upstream = connect_upstream(port)
    if upstream is None:
        client.close()
        return
    with client, upstream:
        incoming = threading.Thread(target=pump, args=(client, upstream), daemon=True)
        incoming.start()
        pump(upstream, client)
        # The response ended; release a client that left its request half open.
        try:
            client.shutdown(socket.SHUT_RD)
        except OSError:
            pass
        incoming.join()


# ZeroTier only (security audit 2026-09-28): never bind 0.0.0.0, which exposed
# these ports on home Wi-Fi. Loopback keeps Windows-local tools working.
BIND_HOSTS = ["10.243.53.96", "127.0.0.1"]


def serve(port, host):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind((host, port))
    except OSError as e:
        print(f"skip {host}:{port}: {e}")
        return
    srv.listen(32)
    print(f"relaying {host}:{port} -> WSL:{port}")
    while True:
        client, _ = srv.accept()
        threading.Thread(target=relay_client, args=(client, port), daemon=True).start()


def supervise_agent():
    config_dir = Path(os.environ["LOCALAPPDATA"]) / "DevOTA"
    config_path = config_dir / "agent-relay.json"
    agent_script = r"\\wsl.localhost\Ubuntu-24.04\home\chase\dev-ota\mcp\src\windows_agent_host.js"
    node = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "nodejs" / "node.exe"
    env = dict(os.environ, DEVOTA_AGENT_CONFIG=str(config_path))
    while True:
        try:
            # Another startup invocation must not replace a live controller.
            try:
                with urllib.request.urlopen("http://127.0.0.1:18783/health", timeout=3) as response:
                    ready = json.load(response).get("service") == "devota-windows-agent-host"
                if ready:
                    time.sleep(5)
                    continue
            except Exception:
                pass
            # UNC access starts WSL if necessary; retry if it is still booting.
            if not config_path.is_file() or not Path(agent_script).is_file():
                time.sleep(5)
                continue
            with (config_dir / "agent-relay.log").open("a", encoding="utf-8") as log:
                log.write("Starting DevOTA Windows agent host\n")
                log.flush()
                child = subprocess.Popen([str(node), agent_script], env=env,
                                         stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                         creationflags=subprocess.CREATE_NO_WINDOW)
                child.wait()
                log.write(f"Agent host exited ({child.returncode}); retrying\n")
        except Exception as exc:
            print(f"agent supervisor: {type(exc).__name__}; retrying", flush=True)
        time.sleep(5)


def main():
    threading.Thread(target=supervise_agent, daemon=True).start()
    threads = [threading.Thread(target=serve, args=(p, h), daemon=True) for p in PORTS for h in BIND_HOSTS]
    for t in threads:
        t.start()
    for t in threads:
        t.join()


if __name__ == "__main__":
    main()
