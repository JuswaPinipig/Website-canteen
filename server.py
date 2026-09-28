#!/usr/bin/env python3
"""
NovaLunch Unified Local Web & Kiosk Bridge Server
=================================================
Serves the web portal on http://localhost:8080 and handles 1-click
native GUI launching directly from the browser without terminal commands.
Saint Joseph College of Novaliches (SJC)
"""

import sys
import os
import time
import json
import socket
import urllib.parse
import subprocess
import threading
from pathlib import Path
from http.server import HTTPServer, ThreadingHTTPServer, SimpleHTTPRequestHandler

# Import Instant QR Pairing Service
try:
    from src.services.qr_pairing_service import handle_create_pairing_token, handle_link_by_qr
except ImportError:
    services_dir = Path(__file__).resolve().parent / "src" / "services"
    if str(services_dir) not in sys.path:
        sys.path.insert(0, str(services_dir))
    from qr_pairing_service import handle_create_pairing_token, handle_link_by_qr

PORT = int(os.environ.get("PORT", 8080))
ROOT_DIR = Path(__file__).resolve().parent
KIOSK_SCRIPT_NAME = "src/hardware/student_kiosk_gui.py"

kiosk_process = None

def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('127.0.0.1', port)) == 0

def launch_target_script(script_name: str):
    """
    Spawns a target Python script cross-platform using the exact same Python interpreter
    (sys.executable), dynamically resolving paths and setting cwd to the script's directory.
    """
    try:
        base_dir = Path(__file__).resolve().parent
        candidate_paths = [
            base_dir / "src" / "hardware" / "student_kiosk_gui.py",
            base_dir / "student_kiosk_gui.py",
            Path.cwd() / "src" / "hardware" / "student_kiosk_gui.py",
            (base_dir / script_name).resolve()
        ]
        target_script = None
        for candidate in candidate_paths:
            candidate_resolved = candidate.resolve()
            if candidate_resolved.exists() and candidate_resolved.is_file():
                target_script = candidate_resolved
                break

        if not target_script:
            raise FileNotFoundError(f"Kiosk script not found at {[str(p) for p in candidate_paths]}")

        popen_kwargs = {
            "cwd": str(target_script.parent)
        }

        # Cross-platform window and process detachment: On Windows, allocate a new console window
        # so any camera or dependency errors display directly instead of terminating silently.
        if sys.platform == "win32":
            popen_kwargs["creationflags"] = subprocess.CREATE_NEW_CONSOLE
        else:
            popen_kwargs["start_new_session"] = True
            log_path = base_dir / "novalunch_kiosk.log"
            try:
                log_file = open(str(log_path), "a", encoding="utf-8")
                log_file.write(f"\n--- Launching {target_script.name} at {time.ctime()} ---\n")
                log_file.flush()
                popen_kwargs["stdout"] = log_file
                popen_kwargs["stderr"] = log_file
            except Exception as log_err:
                print(f"[WARN] Failed to open kiosk log file: {log_err}", file=sys.stderr)

        proc = subprocess.Popen(
            [sys.executable, str(target_script)],
            **popen_kwargs
        )
        return True, f"{target_script.name} launched successfully.", proc
    except Exception as exc:
        print(f"[ERROR] Failed to launch {script_name}: {exc}", file=sys.stderr)
        return False, f"Failed to launch {script_name}: {exc}", None

def launch_kiosk_gui():
    global kiosk_process
    if is_port_in_use(8085):
        return True, "Kiosk GUI is already running on port 8085."

    success, msg, proc = launch_target_script(KIOSK_SCRIPT_NAME)
    if success:
        kiosk_process = proc
    return success, msg

class NovaLunchPortalHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT_DIR), **kwargs)

    def _send_cors(self, code=200, ctype="application/json"):
        self.send_response(code)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PATCH")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Content-Type", ctype)

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Max-Age", "86400")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def translate_path(self, path):
        original = super().translate_path(path)
        if os.path.exists(original):
            return original

        # If not found directly under ROOT_DIR, check under ROOT_DIR/src/
        rel = os.path.relpath(original, str(ROOT_DIR))
        src_path = os.path.join(str(ROOT_DIR), "src", rel)
        if os.path.exists(src_path):
            return src_path

        # If requested /services/ or /assets/ specifically
        parts = rel.split(os.sep)
        if parts and parts[0] in ["services", "assets", "portals", "hardware", "ai_engine", "database"]:
            alt = os.path.join(str(ROOT_DIR), "src", *parts)
            if os.path.exists(alt):
                return alt

        return original

    def do_HEAD(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path in ["/", "/index.html", "/pos", "/cashier"]:
            portal_path = os.path.join(str(ROOT_DIR), "src", "portals", "unified_web_portal.html")
            if os.path.exists(portal_path):
                self._send_cors(200, "text/html; charset=utf-8")
                self.send_header("Content-Length", str(os.path.getsize(portal_path)))
                self.end_headers()
                return
        return super().do_HEAD()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path in ["/", "/index.html", "/pos", "/cashier"]:
            # Route directly to unified web portal
            portal_path = os.path.join(str(ROOT_DIR), "src", "portals", "unified_web_portal.html")
            if os.path.exists(portal_path):
                self._send_cors(200, "text/html; charset=utf-8")
                self.end_headers()
                with open(portal_path, "rb") as f:
                    self.wfile.write(f.read())
                return

        elif path == "/api/kiosk/status":
            online = is_port_in_use(8085)
            self._send_cors(200)
            self.end_headers()
            self.wfile.write(json.dumps({
                "online": online,
                "port": 8085,
                "kiosk_running": online,
                "timestamp": time.time()
            }).encode('utf-8'))
            return

        elif path == "/api/launch_kiosk":
            success, msg = launch_kiosk_gui()
            self._send_cors(200 if success else 500)
            self.end_headers()
            self.wfile.write(json.dumps({"success": success, "message": msg}).encode('utf-8'))
            return

        return super().do_GET()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip('/')

        # Parse request body (if any)
        content_length = int(self.headers.get('Content-Length', 0))
        body_data = {}
        if content_length > 0:
            try:
                raw_body = self.rfile.read(content_length).decode('utf-8')
                if raw_body.strip():
                    body_data = json.loads(raw_body)
            except Exception as e:
                self._send_cors(400)
                self.end_headers()
                self.wfile.write(json.dumps({"success": False, "error": f"Invalid JSON body: {str(e)}"}).encode('utf-8'))
                return

        headers_dict = {k.lower(): v for k, v in self.headers.items()}

        if path in ["/api/kiosk/launch", "/api/launch_kiosk"]:
            try:
                base_dir = Path(__file__).resolve().parent
                candidate_paths = [
                    base_dir / "src" / "hardware" / "student_kiosk_gui.py",
                    base_dir / "student_kiosk_gui.py",
                    Path.cwd() / "src" / "hardware" / "student_kiosk_gui.py"
                ]
                target_script = None
                for candidate in candidate_paths:
                    candidate_resolved = candidate.resolve()
                    if candidate_resolved.exists() and candidate_resolved.is_file():
                        target_script = candidate_resolved
                        break

                if not target_script:
                    searched_paths = [str(p) for p in candidate_paths]
                    self._send_cors(404)
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": f"Kiosk script not found at {searched_paths}"}).encode('utf-8'))
                    return

                # If already running on port 8085, return status launched
                if is_port_in_use(8085):
                    self._send_cors(200)
                    self.end_headers()
                    self.wfile.write(json.dumps({"status": "launched", "message": "Kiosk is already running on port 8085."}).encode('utf-8'))
                    return

                popen_kwargs = {"cwd": str(target_script.parent)}
                # On Windows, allocate a new console window to show camera/dependency errors in real-time
                if sys.platform == "win32":
                    popen_kwargs["creationflags"] = subprocess.CREATE_NEW_CONSOLE
                else:
                    popen_kwargs["start_new_session"] = True
                    log_path = base_dir / "novalunch_kiosk.log"
                    try:
                        log_file = open(str(log_path), "a", encoding="utf-8")
                        log_file.write(f"\n--- Launching {target_script.name} via /api/kiosk/launch at {time.ctime()} ---\n")
                        log_file.flush()
                        popen_kwargs["stdout"] = log_file
                        popen_kwargs["stderr"] = log_file
                    except Exception:
                        pass

                global kiosk_process
                kiosk_process = subprocess.Popen([sys.executable, str(target_script)], **popen_kwargs)
                self._send_cors(200)
                self.end_headers()
                self.wfile.write(json.dumps({"status": "launched"}).encode('utf-8'))
                return
            except Exception as err:
                self._send_cors(500)
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(err)}).encode('utf-8'))
                return

        elif path == "/api/students/pairing-token":
            status_code, response_data = handle_create_pairing_token(headers_dict, body_data)
            self._send_cors(status_code)
            self.end_headers()
            self.wfile.write(json.dumps(response_data).encode('utf-8'))
            return

        elif path == "/api/parents/link-by-qr":
            status_code, response_data = handle_link_by_qr(headers_dict, body_data)
            self._send_cors(status_code)
            self.end_headers()
            self.wfile.write(json.dumps(response_data).encode('utf-8'))
            return

        self._send_cors(404)
        self.end_headers()
        self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))

def run_server():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), NovaLunchPortalHandler)
    print("=" * 65)
    print("  🍱 NOVALUNCH UNIFIED WEB & KIOSK BRIDGE SERVER ACTIVE")
    print(f"  🌐 Web Portal:    http://localhost:{PORT}")
    print(f"  ⚡ 1-Click Launch: http://localhost:{PORT}/api/launch_kiosk")
    print("=" * 65)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down NovaLunch server...")
        server.server_close()

if __name__ == "__main__":
    run_server()
