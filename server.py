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
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = int(os.environ.get("PORT", 8080))
ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
KIOSK_SCRIPT = os.path.join(ROOT_DIR, "src", "hardware", "student_kiosk_gui.py")

kiosk_process = None

def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('127.0.0.1', port)) == 0

def launch_kiosk_gui():
    global kiosk_process
    if is_port_in_use(8085):
        return True, "Kiosk GUI is already running on port 8085."

    python_exec = sys.executable or "python"
    try:
        log_path = os.path.join(ROOT_DIR, "novalunch_kiosk.log")
        log_file = open(log_path, "a", encoding="utf-8")
        log_file.write(f"\n--- Launching Kiosk GUI at {time.ctime()} ---\n")
        log_file.flush()

        popen_kwargs = {
            "cwd": ROOT_DIR,
            "stdout": log_file,
            "stderr": log_file,
        }
        if sys.platform == "win32":
            popen_kwargs["creationflags"] = subprocess.CREATE_NEW_CONSOLE
        else:
            popen_kwargs["start_new_session"] = True

        kiosk_process = subprocess.Popen(
            [python_exec, KIOSK_SCRIPT],
            **popen_kwargs
        )
        return True, "Python Kiosk GUI launched successfully."
    except Exception as e:
        return False, f"Failed to launch Kiosk GUI: {str(e)}"

class NovaLunchPortalHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT_DIR, **kwargs)

    def _send_cors(self, code=200, ctype="application/json"):
        self.send_response(code)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Content-Type", ctype)

    def do_OPTIONS(self):
        self._send_cors(200)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path in ["/", "/index.html", "/pos", "/cashier"]:
            # Route directly to unified web portal
            portal_path = os.path.join(ROOT_DIR, "src", "portals", "unified_web_portal.html")
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
        path = parsed.path

        if path in ["/api/launch_kiosk", "/api/kiosk/launch"]:
            success, msg = launch_kiosk_gui()
            self._send_cors(200 if success else 500)
            self.end_headers()
            self.wfile.write(json.dumps({"success": success, "message": msg}).encode('utf-8'))
            return

        self._send_cors(404)
        self.end_headers()
        self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))

def run_server():
    server = HTTPServer(("0.0.0.0", PORT), NovaLunchPortalHandler)
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
