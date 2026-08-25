#!/usr/bin/env python3
"""
NovaLunch Automated Canteen Kiosk — Student-Facing Display (CFD) Monitor GUI
=============================================================================
Enterprise-grade, simplified & robust Pygame & OpenCV interface with Real-Time
Cashier POS synchronization via embedded HTTP REST + SSE Server (Port 8085).
Saint Joseph College of Novaliches (SJC)
"""

import sys
import os
import time
import math
import json
import sqlite3
import shutil
import subprocess
import threading
import urllib.request
import urllib.parse
from socketserver import ThreadingMixIn
from http.server import HTTPServer, BaseHTTPRequestHandler
import numpy as np
import cv2
import pygame

# Ensure Windows console handles UTF-8 prints without UnicodeEncodeError
try:
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

# ==============================================================================
# CONFIGURATION & CONSTANTS
# ==============================================================================
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://wtvkmywmlifcsddlgvnn.supabase.co")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "sb_publishable_yywY2quhz5k1x6Pu_w6pgQ_e-mBU0q2")
HTTP_PORT = int(os.environ.get("KIOSK_HTTP_PORT", 8085))

SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
TARGET_FPS = 60

# 2026 Light Minimalist Maroon Palette
COLOR_BG_CANVAS = (248, 250, 252)        # Slate White (#F8FAFC)
COLOR_CARD_BG = (255, 255, 255)          # Pure White (#FFFFFF)
COLOR_CARD_ALT = (241, 245, 249)         # Light Slate Row (#F1F5F9)
COLOR_CARD_BORDER = (226, 232, 240)      # Border Outline (#E2E8F0)

COLOR_MAROON_HEADER = (74, 14, 23)       # Deep Burgundy (#4A0E17)
COLOR_MAROON_DARK = (45, 8, 14)          # Deep Crimson (#2D080E)
COLOR_ROSE_VIBRANT = (201, 24, 74)       # Radiant Crimson (#C9184A)
COLOR_GOLD_ACCENT = (217, 119, 6)        # Amber Gold (#D97706)
COLOR_GOLD_LIGHT = (254, 243, 199)       # Warm Cream (#FEF3C7)

COLOR_TEXT_MAIN = (15, 23, 42)           # Slate Onyx (#0F172A)
COLOR_TEXT_MUTED = (100, 116, 139)       # Slate Gray (#64748B)
COLOR_WHITE = (255, 255, 255)            # Pure White (#FFFFFF)

COLOR_EMERALD = (16, 185, 129)           # Emerald Green (#10B981)
COLOR_EMERALD_BG = (236, 253, 245)       # Light Emerald Pill (#ECFDF5)
COLOR_AMBER = (245, 158, 11)             # Warning Amber (#F59E0B)
COLOR_AMBER_BG = (254, 243, 199)         # Warning Amber Pill (#FEF3C7)
COLOR_ROSE_ALERT = (225, 29, 72)         # Alert Red (#E11D48)
COLOR_ROSE_ALERT_BG = (255, 228, 230)    # Alert Light Red (#FFE4E6)
COLOR_CYAN_HUD = (6, 182, 212)           # HUD Cyan (#06B6D4)

# State Constants
STATE_IDLE = 1
STATE_GREET = 2
STATE_SCANNING = 3
STATE_STABILITY_COUNTDOWN = 4
STATE_SETTLEMENT = 5
STATE_ERROR = 6
STATE_PREORDER_ANNOUNCEMENT = 7

STATE_NAMES = {
    STATE_IDLE: "IDLE",
    STATE_GREET: "GREET",
    STATE_SCANNING: "SCANNING",
    STATE_STABILITY_COUNTDOWN: "COUNTDOWN",
    STATE_SETTLEMENT: "SETTLEMENT",
    STATE_ERROR: "ERROR",
    STATE_PREORDER_ANNOUNCEMENT: "PREORDER"
}

# Catalog Database
POS_CATALOG_DATABASE = {
    "Buttercream_Biscuits": {"name": "Buttercream Biscuits", "category": "SNACKS & BAKERY", "price": 35.00, "stock": 50},
    "buttercream_biscuits": {"name": "Buttercream Biscuits", "category": "SNACKS & BAKERY", "price": 35.00, "stock": 50},
    "Buttercream Biscuits": {"name": "Buttercream Biscuits", "category": "SNACKS & BAKERY", "price": 35.00, "stock": 50},
    "buttercream_crackers": {"name": "Buttercream Biscuits", "category": "SNACKS & BAKERY", "price": 35.00, "stock": 50},
    "Buttercream Crackers": {"name": "Buttercream Biscuits", "category": "SNACKS & BAKERY", "price": 35.00, "stock": 50},
    "Jack_And_Jill_Magic_Chips": {"name": "Jack & Jill Magic Chips", "category": "SNACKS & BAKERY", "price": 25.00, "stock": 50},
    "jack_and_jill_magic_chips": {"name": "Jack & Jill Magic Chips", "category": "SNACKS & BAKERY", "price": 25.00, "stock": 50},
    "Jack & Jill Magic Chips": {"name": "Jack & Jill Magic Chips", "category": "SNACKS & BAKERY", "price": 25.00, "stock": 50},
    "Magic_Chips": {"name": "Jack & Jill Magic Chips", "category": "SNACKS & BAKERY", "price": 25.00, "stock": 50},
    "magic_chips": {"name": "Jack & Jill Magic Chips", "category": "SNACKS & BAKERY", "price": 25.00, "stock": 50},
    "adobo": {"name": "Pork Adobo Meal", "category": "MEAL", "price": 100.00, "stock": 45},
    "pork_adobo": {"name": "Pork Adobo Meal", "category": "MEAL", "price": 100.00, "stock": 45},
    "steamed_rice": {"name": "Steamed Rice", "category": "RICE", "price": 15.00, "stock": 120},
    "burger": {"name": "Classic Cheeseburger", "category": "MEAL", "price": 75.00, "stock": 50},
    "fried_chicken": {"name": "Crispy Chicken Bowl", "category": "MEAL", "price": 85.00, "stock": 60},
    "water_bottle": {"name": "Mineral Water 500ml", "category": "BEVERAGE", "price": 20.00, "stock": 150},
    "juice_box": {"name": "Iced Fruit Juice 350ml", "category": "BEVERAGE", "price": 30.00, "stock": 80},
    "sandwich": {"name": "Ham & Cheese Sandwich", "category": "SNACK", "price": 45.00, "stock": 40},
    "apple": {"name": "Fresh Red Apple", "category": "HEALTHY", "price": 25.00, "stock": 40}
}

def lookup_pos_item(raw_label):
    if not raw_label:
        return {"name": "Tray Item", "category": "ITEM", "price": 35.00, "stock": 50, "available": True, "status": "active"}
    s = str(raw_label).strip()
    match = None
    if s in POS_CATALOG_DATABASE:
        match = dict(POS_CATALOG_DATABASE[s])
    elif s.lower() in POS_CATALOG_DATABASE:
        match = dict(POS_CATALOG_DATABASE[s.lower()])
    elif s.replace("_", " ").strip() in POS_CATALOG_DATABASE:
        match = dict(POS_CATALOG_DATABASE[s.replace("_", " ").strip()])
    else:
        s_snake = s.lower().replace(" ", "_").replace("-", "_")
        if s_snake in POS_CATALOG_DATABASE:
            match = dict(POS_CATALOG_DATABASE[s_snake])
        else:
            for k, v in POS_CATALOG_DATABASE.items():
                if k.lower() in s.lower() or s.lower() in k.lower():
                    match = dict(v)
                    break
    if not match:
        clean = s.replace("_", " ").title()
        match = {"name": clean, "category": "ITEM", "price": 35.00, "stock": 50, "available": True, "status": "active"}
    
    if match.get("available") is None:
        match["available"] = True
    if match.get("status") is None:
        match["status"] = "active"
    return match

def aggregate_detections(detections_list):
    if not detections_list:
        return []
    aggregated = {}
    for it in detections_list:
        # Exclude archived and expired items
        if it.get("available") is False or it.get("status") in ["archived", "EXPIRED", "expired"]:
            continue
        name = it.get("name", "Item")
        if name in aggregated:
            aggregated[name]["qty"] += it.get("qty", 1)
        else:
            aggregated[name] = dict(it)
    return list(aggregated.values())

# ==============================================================================
# DATABASE & CLOUD DUAL-SYNC MANAGER
# ==============================================================================
class DatabaseManager:
    def __init__(self, accounts_path="src/database/accounts.json", sqlite_path="src/database/novalunch_edge.db"):
        if not os.path.exists(accounts_path) and os.path.exists("database/accounts.json"):
            accounts_path = "database/accounts.json"
        if not os.path.exists(sqlite_path) and os.path.exists("novalunch_edge.db"):
            sqlite_path = "novalunch_edge.db"
        self.accounts_path = os.path.abspath(accounts_path)
        self.sqlite_path = os.path.abspath(sqlite_path)
        self._lock = threading.Lock()
        self._init_sqlite()
        self.sync_remote_accounts()
        self.sync_worker = OfflineSyncWorker(self)
        self.sync_worker.start()

    def _init_sqlite(self):
        try:
            os.makedirs(os.path.dirname(self.sqlite_path), exist_ok=True)
            conn = sqlite3.connect(self.sqlite_path, timeout=10.0)
            c = conn.cursor()
            c.execute("PRAGMA journal_mode=WAL;")
            c.execute("PRAGMA busy_timeout=5000;")
            c.execute("""
                CREATE TABLE IF NOT EXISTS pending_transactions (
                    transaction_id TEXT PRIMARY KEY,
                    student_id TEXT NOT NULL,
                    items_purchased TEXT NOT NULL,
                    total_amount REAL NOT NULL,
                    payment_method TEXT NOT NULL,
                    tray_image_url TEXT,
                    sync_status TEXT DEFAULT 'EDGE_CACHED',
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """)
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"[DB WARN] SQLite init: {e}")

    def load_accounts(self):
        with self._lock:
            if os.path.exists(self.accounts_path):
                try:
                    with open(self.accounts_path, "r", encoding="utf-8") as f:
                        return json.load(f).get("students", [])
                except Exception as e:
                    print(f"[DB WARN] load_accounts: {e}")
            return []

    def save_accounts(self, students):
        with self._lock:
            if os.path.exists(self.accounts_path):
                try:
                    with open(self.accounts_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    data["students"] = students
                    with open(self.accounts_path, "w", encoding="utf-8") as f:
                        json.dump(data, f, indent=2)
                except Exception as e:
                    print(f"[DB ERROR] save_accounts: {e}")

    def sync_remote_accounts(self):
        def _fetch():
            try:
                url = f"{SUPABASE_URL}/rest/v1/profiles?role=eq.student&select=id,full_name,email,student_id_number,rfid_uid,wallets(balance,daily_limit)"
                req = urllib.request.Request(url, headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"})
                with urllib.request.urlopen(req, timeout=4) as resp:
                    if resp.status == 200:
                        profiles = json.loads(resp.read().decode('utf-8'))
                        if profiles and isinstance(profiles, list):
                            local = self.load_accounts()
                            by_id = {st.get("student_id_number"): st for st in local}
                            for p in profiles:
                                st_id = p.get("student_id_number")
                                if not st_id:
                                    continue
                                w = (p.get("wallets") or [{}])[0] if isinstance(p.get("wallets"), list) and p.get("wallets") else {}
                                bal = float(w.get("balance", p.get("balance", 200.0)))
                                dlim = float(w.get("daily_limit", p.get("daily_limit", 200.0)))
                                if st_id in by_id:
                                    by_id[st_id]["balance"] = bal
                                    by_id[st_id]["daily_limit"] = dlim
                                    if p.get("rfid_uid"):
                                        by_id[st_id]["rfid_uid"] = p.get("rfid_uid")
                                else:
                                    by_id[st_id] = {
                                        "full_name": p.get("full_name", "Student"),
                                        "email": p.get("email", ""),
                                        "role": "student",
                                        "student_id_number": st_id,
                                        "rfid_uid": p.get("rfid_uid", ""),
                                        "balance": bal,
                                        "daily_limit": dlim
                                    }
                            self.save_accounts(list(by_id.values()))
                            print(f"[DB MANAGER] ☁️ Synced {len(profiles)} accounts from Supabase cloud.")
            except Exception as e:
                print(f"[DB NOTICE] Supabase sync deferred (offline/cached): {e}")
        threading.Thread(target=_fetch, daemon=True).start()

    def find_student_by_rfid(self, raw_uid):
        if not raw_uid:
            return None
        q = str(raw_uid).strip()
        q_clean = q.upper().replace("-", "")
        q_nozero = q_clean.lstrip("0")

        students = self.load_accounts()
        for s in students:
            db_rfid = str(s.get("rfid_uid", "")).strip()
            db_id = str(s.get("student_id_number", "")).strip()
            db_email = str(s.get("email", "")).strip()
            db_clean = db_rfid.upper().replace("-", "")
            db_id_clean = db_id.upper().replace("-", "")

            if q in (db_rfid, db_id, db_email) or (q_clean and q_clean in (db_clean, db_id_clean)) or (q_nozero and q_nozero in (db_clean.lstrip("0"), db_id_clean.lstrip("0"))):
                return {
                    "id": s.get("student_id_number"),
                    "name": s.get("full_name"),
                    "email": s.get("email"),
                    "rfidUid": s.get("rfid_uid"),
                    "balance": float(s.get("balance", 0.0)),
                    "daily_limit": float(s.get("daily_limit", 200.0)),
                    "pay_later_count": int(s.get("pay_later_count", 0)),
                    "pay_later_balance": float(s.get("pay_later_balance", 0.0))
                }
        return None

    def get_active_preorders(self, student_id, student_name=None):
        try:
            quoted_id = urllib.parse.quote(str(student_id))
            or_parts = [f"student_id.eq.{quoted_id}", f"student_name.eq.{quoted_id}"]
            if student_name:
                quoted_name = urllib.parse.quote(str(student_name))
                or_parts.append(f"student_name.eq.{quoted_name}")
                or_parts.append(f"student_name.ilike.*{quoted_name}*")
            or_filter = ",".join(or_parts)
            url = f"{SUPABASE_URL}/rest/v1/preorders?or=({or_filter})&status=neq.Claimed&select=*"
            req = urllib.request.Request(url, headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode('utf-8'))
                    if data and isinstance(data, list):
                        return data
        except Exception:
            pass

        # Local preorders fallback
        po_path = "src/database/preorders.json"
        if not os.path.exists(po_path) and os.path.exists("database/preorders.json"):
            po_path = "database/preorders.json"
        if os.path.exists(po_path):
            try:
                with open(po_path, "r", encoding="utf-8") as f:
                    pos = json.load(f).get("preorders", [])
                    matched = [
                        p for p in pos 
                        if (
                            p.get("student_id") == student_id or 
                            p.get("studentId") == student_id or 
                            p.get("student_id_number") == student_id or 
                            p.get("studentIdNumber") == student_id or 
                            (student_name and (p.get("student_name") == student_name or p.get("studentName") == student_name))
                        ) and p.get("status") != "Claimed"
                    ]
                    if matched:
                        return matched
            except Exception:
                pass

        return []

    def deduct_student_balance(self, student_id, amount):
        students = self.load_accounts()
        rem_bal = 0.0
        for s in students:
            if s.get("student_id_number") == student_id or s.get("id") == student_id:
                curr = float(s.get("balance", 0.0))
                rem_bal = max(0.0, curr - amount)
                s["balance"] = rem_bal
                break
        self.save_accounts(students)
        return rem_bal

    def record_transaction(self, tx_id, student_id, cart_items, total_amt, tray_img="", payment_method="rfid"):
        items_json = json.dumps([{
            "name": i.get("name", "Item"),
            "qty": i.get("qty", 1),
            "price": i.get("price", 0.0),
            "category": i.get("category", "ITEM")
        } for i in cart_items])

        max_retries = 3
        for attempt in range(max_retries):
            try:
                conn = sqlite3.connect(self.sqlite_path, timeout=10.0)
                c = conn.cursor()
                c.execute("PRAGMA busy_timeout=5000;")
                c.execute("""
                    INSERT INTO pending_transactions 
                    (transaction_id, student_id, items_purchased, total_amount, payment_method, tray_image_url, sync_status)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (tx_id, student_id, items_json, total_amt, payment_method, tray_img, "EDGE_CACHED"))
                conn.commit()
                conn.close()
                return True
            except Exception as e:
                print(f"[DB ERROR] record_transaction (attempt {attempt + 1}/{max_retries}): {e}")
                if attempt < max_retries - 1:
                    time.sleep(0.1 * (2 ** attempt))
        return False

    def get_student_daily_spent(self, student_id):
        try:
            conn = sqlite3.connect(self.sqlite_path)
            c = conn.cursor()
            c.execute("SELECT SUM(total_amount) FROM pending_transactions WHERE student_id = ? AND date(timestamp) = date('now')", (student_id,))
            row = c.fetchone()
            conn.close()
            return float(row[0]) if row and row[0] is not None else 0.0
        except Exception:
            return 0.0

class OfflineSyncWorker(threading.Thread):
    """
    Background worker thread that monitors offline transactions cached in SQLite
    (novalunch_edge.db) and safely replays them to Supabase cloud with reconciliation.
    """
    def __init__(self, db_manager):
        super().__init__()
        self.daemon = True
        self.db = db_manager
        self.running = True

    def run(self):
        while self.running:
            time.sleep(12)  # Sweep every 12 seconds
            self.sync_pending_transactions()

    def sync_pending_transactions(self):
        try:
            conn = sqlite3.connect(self.db.sqlite_path)
            c = conn.cursor()
            c.execute("""
                SELECT transaction_id, student_id, items_purchased, total_amount, payment_method, tray_image_url
                FROM pending_transactions 
                WHERE sync_status = 'EDGE_CACHED'
                ORDER BY timestamp ASC
            """)
            rows = c.fetchall()
            if not rows:
                conn.close()
                return

            for row in rows:
                tx_id, student_id, items_json, total_amt, pay_method, tray_img = row
                try:
                    items = json.loads(items_json) if items_json else []
                except Exception:
                    items = []

                # Resolve student user UUID from local accounts cache
                local_students = self.db.load_accounts()
                matched_st = next((s for s in local_students if s.get("student_id_number") == student_id or s.get("rfid_uid") == student_id or s.get("id") == student_id), None)
                user_uuid = matched_st.get("id") if (matched_st and str(matched_st.get("id", "")).count("-") == 4) else None
                student_name = matched_st.get("full_name", "Student") if matched_st else "Offline Student"

                order_payload = {
                    "order_number": tx_id,
                    "student_name": student_name,
                    "total_amount": float(total_amt),
                    "final_amount": float(total_amt),
                    "discount_amount": 0,
                    "payment_method": (pay_method or 'RFID').upper(),
                    "order_source": "offline_edge_kiosk",
                    "order_status": "COMPLETED"
                }
                if user_uuid:
                    order_payload["user_id"] = user_uuid

                try:
                    url = f"{SUPABASE_URL}/rest/v1/orders"
                    req = urllib.request.Request(
                        url,
                        data=json.dumps(order_payload).encode('utf-8'),
                        headers={
                            "apikey": SUPABASE_ANON_KEY,
                            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                            "Content-Type": "application/json",
                            "Prefer": "return=representation"
                        },
                        method="POST"
                    )
                    with urllib.request.urlopen(req, timeout=5) as resp:
                        if resp.status in (200, 201):
                            c.execute("UPDATE pending_transactions SET sync_status = 'SYNCED' WHERE transaction_id = ?", (tx_id,))
                            conn.commit()
                            print(f"[EDGE SYNC] ☁️ Replayed offline transaction to cloud: {tx_id}")
                except Exception as sync_err:
                    print(f"[EDGE SYNC NOTICE] Offline sync pending connection for {tx_id}: {sync_err}")
                    break  # Pause sweep if network is unreachable

            conn.close()
        except Exception as e:
            print(f"[EDGE SYNC ERROR] {e}")

# ==============================================================================
# THREADED CAMERA CAPTURE & VISION PIPELINE
# ==============================================================================
YOLO_MODEL = None
YOLO_ATTEMPTED = False

def get_yolo_model(pt_path="src/assets/models/novalunch_yolo.pt"):
    global YOLO_MODEL, YOLO_ATTEMPTED
    if YOLO_MODEL is not None:
        return YOLO_MODEL
    if YOLO_ATTEMPTED:
        return None
    YOLO_ATTEMPTED = True
    if not os.path.exists(pt_path) and os.path.exists("novalunch_yolo.pt"):
        pt_path = "novalunch_yolo.pt"
    if os.path.exists(pt_path):
        try:
            from ultralytics import YOLO
            YOLO_MODEL = YOLO(pt_path)
            print(f"[AI VISION] 🟢 Ultralytics YOLO model loaded: {pt_path}")
        except Exception as e:
            print(f"[AI VISION WARN] YOLO load error: {e}")
    return YOLO_MODEL

class CameraThread(threading.Thread):
    def __init__(self):
        super().__init__()
        self.daemon = True
        self.cap = None
        self.current_frame = None
        self.frame_size = (640, 480)
        self.latest_detections = []
        self.ai_engine_name = "YOLOv8 Engine"
        self.fps_display = 60
        self.lock = threading.Lock()
        self.running = True
        self.manual_enabled = True
        self._init_camera()

    def _init_camera(self):
        for idx in [0, 1, 2]:
            try:
                c = cv2.VideoCapture(idx)
                if c and c.isOpened():
                    c.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                    c.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                    ret, f = c.read()
                    if ret and f is not None:
                        self.cap = c
                        print(f"[CAMERA] 🟢 Hardware stream initialized on index {idx}.")
                        return
                    c.release()
            except Exception:
                pass
        self.cap = None
        print("[CAMERA] Running in High-Fidelity Synthetic Vision mode.")

    def toggle_manual(self):
        with self.lock:
            self.manual_enabled = not self.manual_enabled
            return self.manual_enabled

    def _generate_synthetic_frame(self, angle_deg):
        h, w = 480, 640
        canvas = np.full((h, w, 3), (30, 35, 45), dtype=np.uint8)

        # Platform grid
        for x in range(0, w, 40):
            cv2.line(canvas, (x, 0), (x, h), (45, 50, 65), 1)
        for y in range(0, h, 40):
            cv2.line(canvas, (0, y), (w, y), (45, 50, 65), 1)

        # Tray boundary
        cv2.rectangle(canvas, (100, 70), (540, 410), (60, 65, 80), 2)
        cv2.putText(canvas, "NOVALUNCH SCANNING ZONE (SYNTHETIC FEED)", (130, 95), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (160, 175, 200), 1)

        # Sweeping cyan laser line
        sweep_y = int(80 + (320 * (math.sin(math.radians(angle_deg)) + 1.0) / 2.0))
        cv2.line(canvas, (105, sweep_y), (535, sweep_y), (212, 182, 6), 2)

        # Simulated item 1: Buttercream Biscuits (novalunch_yolo.pt class 0)
        cv2.rectangle(canvas, (150, 130), (320, 270), (14, 14, 74), -1)
        cv2.rectangle(canvas, (150, 130), (320, 270), (74, 24, 201), 2)
        cv2.putText(canvas, "Buttercream Biscuits", (160, 160), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
        cv2.putText(canvas, "P35.00", (160, 180), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (199, 243, 254), 1)

        # Simulated item 2: Jack & Jill Magic Chips (novalunch_yolo.pt class 1)
        cv2.rectangle(canvas, (360, 150), (480, 360), (74, 14, 23), -1)
        cv2.rectangle(canvas, (360, 150), (480, 360), (217, 119, 6), 2)
        cv2.putText(canvas, "Magic Chips", (370, 180), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
        cv2.putText(canvas, "P25.00", (370, 200), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (254, 243, 199), 1)

        detections = [
            {
                "id": "item-01",
                "ai_label": "Buttercream_Biscuits",
                "name": "Buttercream Biscuits",
                "category": "SNACKS & BAKERY",
                "qty": 1,
                "price": 35.00,
                "stock": 50,
                "bbox": [150, 130, 170, 140],
                "conf": 0.98
            },
            {
                "id": "item-02",
                "ai_label": "Jack_And_Jill_Magic_Chips",
                "name": "Jack & Jill Magic Chips",
                "category": "SNACKS & BAKERY",
                "qty": 1,
                "price": 25.00,
                "stock": 50,
                "bbox": [360, 150, 120, 210],
                "conf": 0.96
            }
        ]
        return canvas, detections

    def run(self):
        synth_angle = 0
        while self.running:
            try:
                if self.cap is not None and self.cap.isOpened() and self.manual_enabled:
                    ret, frame = self.cap.read()
                    if ret and frame is not None:
                        h_f, w_f, _ = frame.shape
                        self.frame_size = (w_f, h_f)
                        detections = []
                        model = get_yolo_model()
                        if model is not None:
                            self.ai_engine_name = "YOLO11-OBB Vision"
                            try:
                                results = model(frame, conf=0.30, verbose=False)
                                for r in results:
                                    # 1. Check for OBB (Oriented Bounding Box) predictions (novalunch_yolo.pt is yolo11n-obb)
                                    obb_data = getattr(r, 'obb', None)
                                    if obb_data is not None and len(obb_data) > 0:
                                        for idx in range(len(obb_data)):
                                            cls_id = int(obb_data.cls[idx])
                                            cls_name = model.names.get(cls_id, f"Class {cls_id}")
                                            conf = float(obb_data.conf[idx])
                                            coords = obb_data.xyxy[idx].tolist() if hasattr(obb_data.xyxy[idx], 'tolist') else list(obb_data.xyxy[idx])
                                            x1, y1, x2, y2 = map(int, coords)
                                            bw = max(20, x2 - x1)
                                            bh = max(20, y2 - y1)
                                            pos_info = lookup_pos_item(cls_name)
                                            if pos_info.get("available") is False or pos_info.get("status") in ["archived", "EXPIRED", "expired"]:
                                                continue
                                            is_near_exp = pos_info.get("status") in ["NEAR_EXPIRY", "near_expiry"] or pos_info.get("expiry_status") == "near_expiry"
                                            detections.append({
                                                "id": f"yolo-obb-{cls_id}-{idx}",
                                                "ai_label": cls_name,
                                                "name": pos_info.get("name", cls_name),
                                                "category": pos_info.get("category", "SNACKS & BAKERY"),
                                                "qty": 1,
                                                "price": float(pos_info.get("price", 35.00)),
                                                "stock": int(pos_info.get("stock", 50)),
                                                "is_near_expiry": is_near_exp,
                                                "bbox": [x1, y1, bw, bh],
                                                "conf": conf
                                            })

                                    # 2. Check for standard 2D axis-aligned bounding boxes
                                    elif getattr(r, 'boxes', None) is not None and len(r.boxes) > 0:
                                        for idx, box in enumerate(r.boxes):
                                            cls_id = int(box.cls[0])
                                            cls_name = model.names.get(cls_id, f"Class {cls_id}")
                                            conf = float(box.conf[0])
                                            coords = box.xyxy[0].tolist() if hasattr(box.xyxy[0], 'tolist') else list(box.xyxy[0])
                                            x1, y1, x2, y2 = map(int, coords)
                                            bw = max(20, x2 - x1)
                                            bh = max(20, y2 - y1)
                                            pos_info = lookup_pos_item(cls_name)
                                            if pos_info.get("available") is False or pos_info.get("status") in ["archived", "EXPIRED", "expired"]:
                                                continue
                                            is_near_exp = pos_info.get("status") in ["NEAR_EXPIRY", "near_expiry"] or pos_info.get("expiry_status") == "near_expiry"
                                            detections.append({
                                                "id": f"yolo-box-{cls_id}-{idx}",
                                                "ai_label": cls_name,
                                                "name": pos_info.get("name", cls_name),
                                                "category": pos_info.get("category", "ITEM"),
                                                "qty": 1,
                                                "price": float(pos_info.get("price", 35.00)),
                                                "stock": int(pos_info.get("stock", 50)),
                                                "is_near_expiry": is_near_exp,
                                                "bbox": [x1, y1, bw, bh],
                                                "conf": conf
                                            })
                            except Exception as e:
                                pass

                        # Optional fallback when no YOLO model is loaded at all
                        if model is None and not detections:
                            self.ai_engine_name = "Native Vision"
                            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                            _, thresh = cv2.threshold(gray, 180, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
                            contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                            valid = [c for c in contours if cv2.contourArea(c) > 6000]
                            for i, c in enumerate(valid[:2]):
                                x, y, bw, bh = cv2.boundingRect(c)
                                detections.append({
                                    "id": f"contour-{i}",
                                    "ai_label": "tray_item",
                                    "name": f"Scanned Item #{i+1}",
                                    "category": "ITEM",
                                    "qty": 1,
                                    "price": 35.00,
                                    "stock": 50,
                                    "bbox": [x, y, bw, bh],
                                    "conf": 0.80
                                })

                        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                        self.null_frame_count = 0
                        with self.lock:
                            self.current_frame = rgb
                            self.latest_detections = detections
                    else:
                        self.null_frame_count = getattr(self, 'null_frame_count', 0) + 1
                        if self.null_frame_count >= 15:
                            print("[CAMERA] ⚠️ Hardware stream dropped. Attempting auto-reconnect cycle...")
                            try:
                                if self.cap:
                                    self.cap.release()
                            except Exception:
                                pass
                            self._init_camera()
                            self.null_frame_count = 0
                        time.sleep(0.05)
                else:
                    synth_angle = (synth_angle + 4) % 360
                    frame_rgb, detections = self._generate_synthetic_frame(synth_angle)
                    self.ai_engine_name = "Synthetic AI Engine"
                    with self.lock:
                        self.current_frame = frame_rgb
                        self.latest_detections = detections

            except Exception as e:
                time.sleep(0.05)
            time.sleep(0.016)

    def get_frame(self):
        with self.lock:
            return self.current_frame.copy() if self.current_frame is not None else None

    def get_jpeg_frame(self, draw_boxes=False):
        with self.lock:
            if self.current_frame is None:
                return None
            frame = self.current_frame.copy()
            detections = list(self.latest_detections)

        # Convert RGB to BGR for OpenCV JPEG encoding
        bgr = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)

        if draw_boxes:
            for item in detections:
                bx, by, bw, bh = item.get("bbox", [100, 100, 150, 150])
                cv2.rectangle(bgr, (bx, by), (bx + bw, by + bh), (0, 215, 255), 2)
                lbl = f"{item['name']} (₱{item['price']:.2f})"
                cv2.putText(bgr, lbl, (bx, max(20, by - 8)), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 215, 255), 2)

        ret, jpeg = cv2.imencode('.jpg', bgr, [cv2.IMWRITE_JPEG_QUALITY, 80])
        if ret:
            return jpeg.tobytes()
        return None

    def get_annotated_jpeg_frame(self):
        return self.get_jpeg_frame(draw_boxes=True)

    def get_latest_detections(self):
        with self.lock:
            return list(self.latest_detections)

    def get_ai_status(self):
        with self.lock:
            return self.ai_engine_name, self.fps_display, self.frame_size

    def stop(self):
        self.running = False
        if self.cap and self.cap.isOpened():
            self.cap.release()

# ==============================================================================
# AUDIO & SPEECH ANNOUNCEMENT ENGINE (MUTED)
# ==============================================================================
def speak_text(text):
    # Sounds and voice announcements muted per user kiosk setup
    pass

def create_synthesized_sounds():
    # Sound effects disabled per user kiosk setup
    return {"success": None, "tick": None}

# ==============================================================================
# REAL-TIME KIOSK HTTP REST & SERVER-SENT EVENTS (SSE) SERVER (PORT 8085)
# ==============================================================================
_GLOBAL_KIOSK_REF = None
_SSE_CLIENTS = []
_SSE_LOCK = threading.Lock()

def broadcast_kiosk_event(event_type, payload):
    data = f"event: {event_type}\ndata: {json.dumps(payload)}\n\n".encode('utf-8')
    with _SSE_LOCK:
        dead = []
        for wfile in _SSE_CLIENTS:
            try:
                wfile.write(data)
                wfile.flush()
            except Exception:
                dead.append(wfile)
        for d in dead:
            if d in _SSE_CLIENTS:
                _SSE_CLIENTS.remove(d)

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

class KioskHTTPRequestHandler(BaseHTTPRequestHandler):
    def _send_cors_headers(self, status=200, content_type="application/json"):
        self.send_response(status)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, HEAD")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
        self.send_header("Content-Type", content_type)

    def do_OPTIONS(self):
        self._send_cors_headers(200)
        self.end_headers()

    def do_HEAD(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path in ["/api/kiosk/status", "/api/scan_tray"]:
            self._send_cors_headers(200, "application/json")
            self.end_headers()
        elif path in ["/api/camera/frame.jpg", "/api/camera/frame_clean.jpg", "/api/camera/frame_annotated.jpg"]:
            self._send_cors_headers(200, "image/jpeg")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")
            self.end_headers()
        elif path == "/api/camera/stream":
            self.send_response(200)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
            self.end_headers()
        else:
            self._send_cors_headers(200, "application/json")
            self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path in ["/api/kiosk/status", "/api/scan_tray"]:
            self._send_cors_headers(200, "application/json")
            self.end_headers()
            if _GLOBAL_KIOSK_REF is not None:
                state_data = _GLOBAL_KIOSK_REF.get_live_kiosk_data()
            else:
                state_data = {
                    "status": "SUCCESS",
                    "kiosk_state": "IDLE",
                    "student": None,
                    "cart": [],
                    "total_amount": 0.0,
                    "timestamp": time.time()
                }
            self.wfile.write(json.dumps(state_data).encode('utf-8'))

        elif path in ["/api/camera/frame.jpg", "/api/camera/frame_clean.jpg"]:
            if _GLOBAL_KIOSK_REF is not None and hasattr(_GLOBAL_KIOSK_REF, 'camera_thread') and _GLOBAL_KIOSK_REF.camera_thread:
                jpeg_bytes = _GLOBAL_KIOSK_REF.camera_thread.get_jpeg_frame(draw_boxes=False)
                if jpeg_bytes:
                    self._send_cors_headers(200, "image/jpeg")
                    self.send_header("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
                    self.send_header("Pragma", "no-cache")
                    self.send_header("Expires", "0")
                    self.send_header("Content-Length", str(len(jpeg_bytes)))
                    self.end_headers()
                    self.wfile.write(jpeg_bytes)
                    return
            self._send_cors_headers(404, "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Camera frame unavailable"}).encode('utf-8'))

        elif path == "/api/camera/frame_annotated.jpg":
            if _GLOBAL_KIOSK_REF is not None and hasattr(_GLOBAL_KIOSK_REF, 'camera_thread') and _GLOBAL_KIOSK_REF.camera_thread:
                jpeg_bytes = _GLOBAL_KIOSK_REF.camera_thread.get_annotated_jpeg_frame()
                if jpeg_bytes:
                    self._send_cors_headers(200, "image/jpeg")
                    self.send_header("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
                    self.send_header("Pragma", "no-cache")
                    self.send_header("Expires", "0")
                    self.send_header("Content-Length", str(len(jpeg_bytes)))
                    self.end_headers()
                    self.wfile.write(jpeg_bytes)
                    return
            self._send_cors_headers(404, "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Camera frame unavailable"}).encode('utf-8'))

        elif path == "/api/camera/stream":
            query = urllib.parse.parse_qs(parsed.query)
            draw_annotated = query.get("annotated", ["0"])[0].lower() in ["1", "true", "yes"]
            self.send_response(200)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()
            try:
                while True:
                    if _GLOBAL_KIOSK_REF is not None and hasattr(_GLOBAL_KIOSK_REF, 'camera_thread') and _GLOBAL_KIOSK_REF.camera_thread:
                        jpeg_bytes = _GLOBAL_KIOSK_REF.camera_thread.get_jpeg_frame(draw_boxes=draw_annotated)
                        if jpeg_bytes:
                            self.wfile.write(b"--frame\r\n")
                            self.wfile.write(b"Content-Type: image/jpeg\r\n")
                            self.wfile.write(f"Content-Length: {len(jpeg_bytes)}\r\n\r\n".encode('utf-8'))
                            self.wfile.write(jpeg_bytes)
                            self.wfile.write(b"\r\n")
                            self.wfile.flush()
                    time.sleep(0.033)
            except Exception:
                pass

        elif path == "/api/kiosk/events":
            # Server-Sent Events (SSE) Real-Time stream
            self._send_cors_headers(200, "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()

            with _SSE_LOCK:
                _SSE_CLIENTS.append(self.wfile)

            # Send initial state snapshot immediately
            if _GLOBAL_KIOSK_REF is not None:
                init_payload = _GLOBAL_KIOSK_REF.get_live_kiosk_data()
                self.wfile.write(f"event: kiosk_update\ndata: {json.dumps(init_payload)}\n\n".encode('utf-8'))
                self.wfile.flush()

            try:
                while True:
                    time.sleep(15)
                    self.wfile.write(b": heartbeat\n\n")
                    self.wfile.flush()
            except Exception:
                with _SSE_LOCK:
                    if self.wfile in _SSE_CLIENTS:
                        _SSE_CLIENTS.remove(self.wfile)

        else:
            self._send_cors_headers(404, "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        content_len = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_len).decode('utf-8') if content_len > 0 else "{}"
        try:
            req_data = json.loads(body)
        except Exception:
            req_data = {}

        if path == "/api/kiosk/sync":
            action = req_data.get("action", "")
            if _GLOBAL_KIOSK_REF is not None:
                if action == "reset":
                    _GLOBAL_KIOSK_REF.transition_to_state(STATE_IDLE)
                elif action == "scan":
                    _GLOBAL_KIOSK_REF.execute_simulation_step(2)
                elif action == "pay":
                    _GLOBAL_KIOSK_REF.execute_simulation_step(4)
                elif action == "pay_later":
                    _GLOBAL_KIOSK_REF.execute_pay_later_checkout()
                elif action in ["confirm_payment", "complete_checkout"]:
                    st = req_data.get("student")
                    amt = float(req_data.get("amount", _GLOBAL_KIOSK_REF.total_amount))
                    if st and isinstance(st, dict):
                        student_id = st.get("studentId") or st.get("student_id_number") or st.get("id", "STU-2026")
                        student_name = st.get("name") or st.get("full_name", "Student")
                        curr_bal = float(st.get("balance", 200.0))
                        rem_bal = max(0.0, curr_bal - amt)
                        _GLOBAL_KIOSK_REF.active_student = {
                            "id": student_id,
                            "name": student_name,
                            "email": st.get("email", ""),
                            "rfidUid": st.get("rfidUid") or st.get("rfid_uid", ""),
                            "balance": rem_bal,
                            "daily_limit": float(st.get("daily_limit", 200.0))
                        }
                        # Deduct balance in local database cache
                        _GLOBAL_KIOSK_REF.db_manager.deduct_student_balance(student_id, amt)
                        tx_id = f"TXN_{int(time.time())}_{student_id.replace('-', '')}"
                        _GLOBAL_KIOSK_REF.db_manager.record_transaction(
                            tx_id, student_id, _GLOBAL_KIOSK_REF.cart_items, amt,
                            _GLOBAL_KIOSK_REF.latest_tray_image, payment_method="rfid"
                        )

                    _GLOBAL_KIOSK_REF.total_amount = amt
                    _GLOBAL_KIOSK_REF.status_message = "Payment have been confirmed please claim your order."
                    _GLOBAL_KIOSK_REF.current_state = STATE_SETTLEMENT
                    _GLOBAL_KIOSK_REF.state_timer = time.time()
                    _GLOBAL_KIOSK_REF.notify_pos_update()

            self._send_cors_headers(200, "application/json")
            self.end_headers()
            resp = {"status": "SUCCESS", "action": action, "data": _GLOBAL_KIOSK_REF.get_live_kiosk_data() if _GLOBAL_KIOSK_REF else None}
            self.wfile.write(json.dumps(resp).encode('utf-8'))

        elif path in ["/api/cache_offline", "/api/offline_sync"]:
            self._send_cors_headers(200, "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "SUCCESS", "message": "Offline cache synced"}).encode('utf-8'))
        else:
            self._send_cors_headers(404, "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))

    def log_message(self, format, *args):
        return

def start_kiosk_api_server(port=HTTP_PORT):
    for attempt in range(5):
        try:
            server = ThreadedHTTPServer(("0.0.0.0", port), KioskHTTPRequestHandler)
            print(f"[KIOSK API SERVER] 🟢 Live Real-Time Multi-Threaded Bridge listening on http://127.0.0.1:{port}")
            server.serve_forever()
            break
        except OSError as e:
            if attempt < 4:
                time.sleep(0.5)
            else:
                print(f"[KIOSK API SERVER] ⚠️ Notice: Port {port} in use ({e}). Bridge will retry in background.")

# ==============================================================================
# NOVALUNCH STUDENT-FACING DISPLAY (CFD) MONITOR APPLICATION
# ==============================================================================
class NovaLunchKioskGUI:
    def __init__(self):
        global _GLOBAL_KIOSK_REF
        _GLOBAL_KIOSK_REF = self

        pygame.init()
        pygame.font.init()
        pygame.display.set_caption("Saint Joseph College NovaLunch — Student-Facing Display (CFD) Monitor")

        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        self.clock = pygame.time.Clock()

        # Database Manager
        self.db_manager = DatabaseManager()

        # Branding Logo
        self.logo_surface = None
        logo_path = os.path.abspath("src/assets/images/branding/school no bg.png")
        if not os.path.exists(logo_path):
            logo_path = os.path.abspath("assets/images/branding/school no bg.png")
        if os.path.exists(logo_path):
            try:
                raw = pygame.image.load(logo_path).convert_alpha()
                h = 48
                w = int(raw.get_width() * (h / float(raw.get_height())))
                self.logo_surface = pygame.transform.smoothscale(raw, (w, h))
            except Exception:
                pass

        # Typography System
        self.font_brand_sub = pygame.font.SysFont("Helvetica Neue", 11, bold=True)
        self.font_title = pygame.font.SysFont("Helvetica Neue", 20, bold=True)
        self.font_subtitle = pygame.font.SysFont("Helvetica Neue", 13)
        self.font_subtitle_bold = pygame.font.SysFont("Helvetica Neue", 13, bold=True)
        self.font_header = pygame.font.SysFont("Helvetica Neue", 16, bold=True)
        self.font_body = pygame.font.SysFont("Helvetica Neue", 14)
        self.font_body_bold = pygame.font.SysFont("Helvetica Neue", 14, bold=True)
        self.font_large = pygame.font.SysFont("Helvetica Neue", 28, bold=True)
        self.font_footer = pygame.font.SysFont("Helvetica Neue", 12)
        self.font_timer_large = pygame.font.SysFont("Helvetica Neue", 34, bold=True)
        self.font_timer_badge = pygame.font.SysFont("Helvetica Neue", 13, bold=True)
        self.font_badge = pygame.font.SysFont("Helvetica Neue", 12, bold=True)

        # State Variables
        self.current_state = STATE_IDLE
        self.active_student = None
        self.active_preorders = []
        self.cart_items = []
        self.total_amount = 0.0
        self.state_timer = 0.0
        self.status_message = "Welcome to NovaLunch! Tap Student RFID Card to begin."
        self.latest_tray_image = ""

        # Stability & Motion
        self.countdown_remaining = 5.0
        self.last_tick_sec = 5
        self.motion_detected = False
        self.motion_voice_alerted = False
        self.greet_audio_spoken = False
        self.stable_start_time = 0.0
        self.last_detection_hash = ""

        # Hardware Buffer
        self.rfid_scan_buffer = ""
        self.last_key_time = 0
        self.rfid_anti_passback_cache = {}
        self.last_rfid_tap_timestamp = 0

        # Subsystems
        self.camera_thread = CameraThread()
        self.camera_thread.start()
        self.sounds = create_synthesized_sounds()

        # Start Embedded HTTP + SSE Server
        api_thread = threading.Thread(target=start_kiosk_api_server, args=(HTTP_PORT,), daemon=True)
        api_thread.start()

        # 3-Step Guided Progress Bar Rects
        self.btn_step1 = pygame.Rect(45, 578, 205, 46)
        self.btn_step2 = pygame.Rect(260, 578, 205, 46)
        self.btn_step3 = pygame.Rect(475, 578, 205, 46)
        self.btn_step4 = pygame.Rect(475, 578, 205, 46)

    def get_live_kiosk_data(self):
        """Returns JSON-serializable snapshot of live kiosk state for Cashier POS."""
        detections = []
        ai_engine = "YOLOv8 Engine"
        fps = 60
        if hasattr(self, 'camera_thread') and self.camera_thread:
            detections = self.camera_thread.get_latest_detections()
            ai_engine, fps, _ = self.camera_thread.get_ai_status()

        is_active_session = self.current_state != STATE_IDLE and self.active_student is not None
        return {
            "status": "SUCCESS",
            "kiosk_state": STATE_NAMES.get(self.current_state, "UNKNOWN"),
            "current_state_id": self.current_state,
            "student": self.active_student if is_active_session else None,
            "cart": list(self.cart_items) if is_active_session else [],
            "detections": detections if is_active_session else [],
            "ai_engine": ai_engine,
            "camera_online": True,
            "fps": fps,
            "total_amount": round(self.total_amount, 2) if is_active_session else 0.0,
            "items_count": sum(i.get("qty", 1) for i in self.cart_items) if is_active_session else 0,
            "countdown_remaining": round(self.countdown_remaining, 1) if is_active_session else 0.0,
            "status_message": self.status_message,
            "preorders_count": len(self.active_preorders) if is_active_session else 0,
            "timestamp": time.time()
        }

    def notify_pos_update(self):
        """Broadcasts live cart/state update to all connected Cashier POS terminals."""
        broadcast_kiosk_event("kiosk_update", self.get_live_kiosk_data())

    def recalculate_total(self):
        self.total_amount = sum(item["price"] * item.get("qty", 1) for item in self.cart_items)
        self.notify_pos_update()

    def execute_simulation_step(self, step):
        if step == 1:
            # Step 1: RFID Tap
            if not self.active_student:
                accounts = self.db_manager.load_accounts()
                if accounts:
                    st = accounts[0]
                    self.active_student = {
                        "id": st.get("student_id_number"),
                        "name": st.get("full_name"),
                        "email": st.get("email"),
                        "rfidUid": st.get("rfid_uid"),
                        "balance": float(st.get("balance", 200.0)),
                        "daily_limit": float(st.get("daily_limit", 200.0))
                    }
            if self.active_student:
                self.active_preorders = self.db_manager.get_active_preorders(self.active_student["id"], self.active_student.get("name"))
                if self.active_preorders:
                    self.transition_to_state(STATE_PREORDER_ANNOUNCEMENT)
                else:
                    self.transition_to_state(STATE_GREET)
            else:
                self.transition_to_state(STATE_GREET)

        elif step == 2:
            # Step 2: AI Scan
            self.transition_to_state(STATE_SCANNING)

        elif step == 3:
            # Step 3: Calibrate Timer
            self.transition_to_state(STATE_STABILITY_COUNTDOWN)

        elif step == 4:
            # Step 4: Settlement
            self.transition_to_state(STATE_SETTLEMENT)

    def transition_to_state(self, new_state):
        self.current_state = new_state
        self.state_timer = time.time()

        if new_state == STATE_IDLE:
            self.active_student = None
            self.active_preorders = []
            self.cart_items = []
            self.total_amount = 0.0
            self.countdown_remaining = 4.0
            self.motion_detected = False
            self.motion_voice_alerted = False
            self.greet_audio_spoken = False
            self.stable_start_time = 0.0
            self.last_detection_hash = ""
            self.status_message = "Welcome to NovaLunch! Tap Student RFID Card to begin."

        elif new_state == STATE_PREORDER_ANNOUNCEMENT:
            st_name = self.active_student["name"] if self.active_student else "Student"
            first_po = self.active_preorders[0] if self.active_preorders else {}
            item_name = first_po.get("name") or first_po.get("item") or "Reserved Meal"
            shelf_loc = first_po.get("shelf") or first_po.get("shelf_location") or "Shelf B2"
            self.status_message = f"🍱 ACTIVE PRE-ORDER FOUND: Collect from {shelf_loc}!"
            if not self.greet_audio_spoken:
                speak_text(f"Hello {st_name.split()[0]}! Your pre-order for {item_name} is ready at {shelf_loc}.")
                self.greet_audio_spoken = True

        elif new_state == STATE_GREET:
            if not self.active_student:
                accounts = self.db_manager.load_accounts()
                if accounts:
                    st = accounts[0]
                    self.active_student = {
                        "id": st.get("student_id_number"),
                        "name": st.get("full_name"),
                        "email": st.get("email"),
                        "rfidUid": st.get("rfid_uid"),
                        "balance": float(st.get("balance", 200.0)),
                        "daily_limit": float(st.get("daily_limit", 200.0))
                    }
            st_name = self.active_student["name"] if self.active_student else "Student"
            self.status_message = f"Hello {st_name}! Place food items on scanning platform."
            self.stable_start_time = 0.0
            self.last_detection_hash = ""
            if not self.greet_audio_spoken:
                speak_text(f"Welcome {st_name.split()[0]}! Place your tray on the platform.")
                self.greet_audio_spoken = True

        elif new_state == STATE_SCANNING:
            live_items = self.camera_thread.get_latest_detections()
            if live_items:
                self.cart_items = aggregate_detections(live_items)
                self.recalculate_total()
                self.status_message = f"AI Detected {len(self.cart_items)} item(s). Calibrating stability..."
            else:
                self.cart_items = []
                self.total_amount = 0.0
                self.status_message = "Waiting for tray... Place food on scanning platform."

            # Save snapshot
            try:
                trays_dir = "src/ai_engine/trays_queue"
                os.makedirs(trays_dir, exist_ok=True)
                student_id = self.active_student["id"] if self.active_student else "GUEST"
                filename = f"{trays_dir}/tray_{int(time.time())}_{student_id}.jpg"
                self.latest_tray_image = filename

                frame = self.camera_thread.get_frame()
                if frame is not None:
                    h, w, _ = frame.shape
                    cropped = frame[int(h * 0.15):int(h * 0.85), int(w * 0.15):int(w * 0.85)]
                    cv2.imwrite(filename, cv2.cvtColor(cropped, cv2.COLOR_RGB2BGR))
            except Exception as e:
                print(f"[TRAY SNAPSHOT WARN]: {e}")

        elif new_state == STATE_STABILITY_COUNTDOWN:
            self.countdown_remaining = 5.0
            self.last_tick_sec = 5
            self.motion_voice_alerted = False
            self.status_message = f"🟢 AI Scanning items (5.0s)... Hold tray steady"

        elif new_state == STATE_SETTLEMENT:
            self.status_message = "Payment have been confirmed please claim your order."

        elif new_state == STATE_ERROR:
            self.status_message = "⚠️ UNREGISTERED RFID CARD — PLEASE VISIT ADMIN"

        self.notify_pos_update()

    def execute_pay_later_checkout(self):
        if not self.active_student or self.total_amount <= 0:
            return

        # Check 5x Pay Later limit per student
        current_pay_later_count = self.active_student.get("pay_later_count", 0)
        if current_pay_later_count >= 5:
            self.status_message = "🚫 PAY LATER LIMIT REACHED (5/5 USED) — DEBT CLEARANCE REQUIRED"
            speak_text("Pay later limit reached. Please settle existing balance at cashier.")
            return

        student_id = str(self.active_student.get("id", "") or self.active_student.get("student_id_number", "STU"))
        st_name = self.active_student.get("name", "Student")
        tx_id = f"TXN_PAYLATER_{int(time.time())}_{student_id.replace('-', '')}"

        self.active_student["pay_later_count"] = current_pay_later_count + 1
        self.active_student["pay_later_balance"] = self.active_student.get("pay_later_balance", 0.0) + self.total_amount

        # Persist updated pay-later count & liability to accounts cache
        students = self.db_manager.load_accounts()
        for s in students:
            if s.get("student_id_number") == student_id or s.get("id") == student_id:
                s["pay_later_count"] = self.active_student["pay_later_count"]
                s["pay_later_balance"] = self.active_student["pay_later_balance"]
                break
        self.db_manager.save_accounts(students)

        self.db_manager.record_transaction(tx_id, student_id, self.cart_items, self.total_amount, self.latest_tray_image, payment_method="pay_later")
        self.status_message = f"🟢 SAFETY NET APPROVED: ₱{self.total_amount:.2f} Charged to Pay Later ({st_name}) [{self.active_student['pay_later_count']}/5]"
        if self.sounds.get("success"):
            try:
                self.sounds["success"].play()
            except Exception:
                pass
        speak_text(f"Safety net approved. Charged to pay later. Thank you {st_name.split()[0]}!")
        self.notify_pos_update()

    def handle_rfid_tap(self, scanned_uid=None):
        now = time.time()
        if scanned_uid:
            clean = str(scanned_uid).strip().replace("NL-QR-", "").replace("QR-", "")
            last_tap = self.rfid_anti_passback_cache.get(clean, 0)
            if now - last_tap < 3.0:
                return  # Hardware debounce
            self.rfid_anti_passback_cache[clean] = now

            student = self.db_manager.find_student_by_rfid(clean)
            if student:
                self.active_student = student
                bal = float(student.get("balance", 0.0))
                if bal <= 0:
                    self.status_message = f"⚠️ Low/Zero Balance (₱{bal:.2f}). You may use Pay Later at Cashier."
                else:
                    self.status_message = f"Welcome {student.get('name', 'Student')}! Balance: ₱{bal:.2f}"

                self.active_preorders = self.db_manager.get_active_preorders(student["id"], student.get("name"))
                if self.active_preorders:
                    self.transition_to_state(STATE_PREORDER_ANNOUNCEMENT)
                else:
                    self.transition_to_state(STATE_GREET)
            else:
                self.status_message = f"⚠️ UNRECOGNIZED CARD ({clean}) — VISIT ADMIN"
                self.transition_to_state(STATE_ERROR)
            return

        # Keyboard/simulation advance
        if self.current_state in [STATE_IDLE, STATE_ERROR]:
            self.execute_simulation_step(1)
        elif self.current_state == STATE_PREORDER_ANNOUNCEMENT:
            self.transition_to_state(STATE_GREET)
        elif self.current_state == STATE_GREET:
            self.execute_simulation_step(2)
        elif self.current_state == STATE_SCANNING:
            self.execute_simulation_step(3)
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            self.transition_to_state(STATE_SCANNING)
        elif self.current_state == STATE_SETTLEMENT:
            self.transition_to_state(STATE_IDLE)

    # ==========================================================================
    # UI RENDERING SYSTEM
    # ==========================================================================
    def render_header(self):
        pygame.draw.rect(self.screen, COLOR_MAROON_HEADER, (0, 0, SCREEN_WIDTH, 84))
        pygame.draw.line(self.screen, COLOR_GOLD_ACCENT, (0, 83), (SCREEN_WIDTH, 83), 2)

        left_offset = 24
        if self.logo_surface is not None:
            self.screen.blit(self.logo_surface, (left_offset, 18))
            left_offset += self.logo_surface.get_width() + 16
        else:
            pygame.draw.circle(self.screen, COLOR_GOLD_ACCENT, (46, 42), 20)
            txt = self.font_subtitle_bold.render("SJC", True, COLOR_MAROON_DARK)
            self.screen.blit(txt, (46 - txt.get_width() // 2, 42 - txt.get_height() // 2))
            left_offset += 56

        school_tag = self.font_brand_sub.render("SAINT JOSEPH COLLEGE OF NOVALICHES", True, COLOR_GOLD_LIGHT)
        kiosk_title = self.font_title.render("NovaLunch AI Self-Scan Counter Display", True, COLOR_WHITE)
        self.screen.blit(school_tag, (left_offset, 20))
        self.screen.blit(kiosk_title, (left_offset, 38))

        # Real-time POS bridge badge (Top Center-Right)
        pos_badge = self.font_brand_sub.render(f"● POS BRIDGE LIVE (: {HTTP_PORT})", True, COLOR_EMERALD)
        pos_rect = pygame.Rect(SCREEN_WIDTH - 590, 26, pos_badge.get_width() + 16, 28)
        pygame.draw.rect(self.screen, COLOR_MAROON_DARK, pos_rect, border_radius=14)
        pygame.draw.rect(self.screen, COLOR_EMERALD, pos_rect, width=1, border_radius=14)
        self.screen.blit(pos_badge, (pos_rect.x + 8, pos_rect.y + 6))

        # Active Student Badge
        if self.active_student and self.current_state != STATE_IDLE:
            st_name = self.active_student["name"]
            st_id = self.active_student["id"]
            bal = self.active_student["balance"]

            card_rect = pygame.Rect(SCREEN_WIDTH - 380, 14, 356, 56)
            pygame.draw.rect(self.screen, COLOR_MAROON_DARK, card_rect, border_radius=14)
            pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, card_rect, width=1, border_radius=14)

            pygame.draw.circle(self.screen, COLOR_GOLD_ACCENT, (card_rect.left + 28, card_rect.top + 28), 17)
            inits = "".join([n[0] for n in st_name.split()[:2]]).upper()
            av_txt = self.font_subtitle_bold.render(inits, True, COLOR_MAROON_DARK)
            self.screen.blit(av_txt, (card_rect.left + 28 - av_txt.get_width() // 2, card_rect.top + 28 - av_txt.get_height() // 2))

            name_surf = self.font_body_bold.render(st_name, True, COLOR_WHITE)
            id_surf = self.font_brand_sub.render(f"RFID: {st_id}", True, COLOR_GOLD_LIGHT)
            self.screen.blit(name_surf, (card_rect.left + 54, card_rect.top + 10))
            self.screen.blit(id_surf, (card_rect.left + 54, card_rect.top + 32))

            bal_str = f"₱{bal:.2f}"
            bal_surf = self.font_body_bold.render(bal_str, True, COLOR_EMERALD if bal >= self.total_amount else COLOR_ROSE_ALERT)
            bal_rect = pygame.Rect(card_rect.right - bal_surf.get_width() - 20, card_rect.top + 13, bal_surf.get_width() + 14, 30)
            pygame.draw.rect(self.screen, COLOR_EMERALD_BG if bal >= self.total_amount else COLOR_ROSE_ALERT_BG, bal_rect, border_radius=15)
            self.screen.blit(bal_surf, (bal_rect.x + 7, bal_rect.y + 5))
        else:
            idle_rect = pygame.Rect(SCREEN_WIDTH - 320, 20, 296, 44)
            pygame.draw.rect(self.screen, COLOR_MAROON_DARK, idle_rect, border_radius=22)
            pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, idle_rect, width=1, border_radius=22)
            lbl = self.font_subtitle_bold.render("Tap Student RFID Card on Reader", True, COLOR_GOLD_LIGHT)
            self.screen.blit(lbl, (idle_rect.centerx - lbl.get_width() // 2, idle_rect.centery - lbl.get_height() // 2))

    def render_left_panel(self):
        panel_rect = pygame.Rect(20, 100, 710, 545)
        pygame.draw.rect(self.screen, COLOR_CARD_BG, panel_rect, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, panel_rect, width=1, border_radius=16)

        header_surf = self.font_header.render("OVERHEAD COUNTER SCANNING PLATFORM", True, COLOR_MAROON_HEADER)
        self.screen.blit(header_surf, (36, 116))

        cam_frame = self.camera_thread.get_frame()
        ai_engine, fps_val, _ = self.camera_thread.get_ai_status()
        badge_lbl = self.font_brand_sub.render(f"LIVE STREAM • {ai_engine}", True, COLOR_EMERALD)
        badge_w = badge_lbl.get_width() + 20
        badge_rect = pygame.Rect(panel_rect.right - badge_w - 20, 114, badge_w, 24)
        pygame.draw.rect(self.screen, COLOR_EMERALD_BG, badge_rect, border_radius=12)
        self.screen.blit(badge_lbl, (badge_rect.x + 10, badge_rect.y + 4))

        video_area = pygame.Rect(34, 150, 682, 410)
        if cam_frame is not None:
            try:
                resized = cv2.resize(cam_frame, (682, 410))
                surface = pygame.surfarray.make_surface(resized.swapaxes(0, 1))
                self.screen.blit(surface, (34, 150))

                # Draw Reticles only when active (NOT in STATE_IDLE standby)
                if self.current_state != STATE_IDLE and self.active_student:
                    detections = self.camera_thread.get_latest_detections() or self.cart_items
                    for item in detections:
                        bx, by, bw, bh = item.get("bbox", [100, 100, 150, 150])
                        scale_x, scale_y = 682.0 / 640.0, 410.0 / 480.0
                        rx, ry = 34 + int(bx * scale_x), 150 + int(by * scale_y)
                        rw, rh = max(40, int(bw * scale_x)), max(30, int(bh * scale_y))

                        pygame.draw.rect(self.screen, COLOR_ROSE_VIBRANT, (rx, ry, rw, rh), width=2, border_radius=6)
                        conf_pct = int(item.get('conf', 0.95) * 100)
                        tag_str = f" {item['name']} ({conf_pct}%) • ₱{item['price']:.2f} "
                        tag_surf = self.font_subtitle_bold.render(tag_str, True, COLOR_WHITE)
                        tag_bg = pygame.Rect(rx, ry - 22, tag_surf.get_width() + 4, 22)
                        pygame.draw.rect(self.screen, COLOR_MAROON_DARK, tag_bg, border_radius=4)
                        self.screen.blit(tag_surf, (rx + 2, ry - 20))
                else:
                    # In Standby mode, show clean camera feed with a sleek standby badge overlay
                    standby_badge = self.font_subtitle_bold.render("STANDBY MODE • TAP STUDENT RFID CARD TO BEGIN SCANNING", True, COLOR_GOLD_LIGHT)
                    sbg_w = standby_badge.get_width() + 28
                    sbg_rect = pygame.Rect(video_area.centerx - sbg_w // 2, video_area.bottom - 44, sbg_w, 32)
                    pygame.draw.rect(self.screen, COLOR_MAROON_DARK, sbg_rect, border_radius=16)
                    pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, sbg_rect, width=1, border_radius=16)
                    self.screen.blit(standby_badge, (sbg_rect.x + 14, sbg_rect.y + 7))
            except Exception:
                pygame.draw.rect(self.screen, COLOR_CARD_ALT, video_area, border_radius=12)
        else:
            pygame.draw.rect(self.screen, COLOR_CARD_ALT, video_area, border_radius=12)

        if self.current_state == STATE_STABILITY_COUNTDOWN:
            self.render_countdown_gauge(video_area)
        elif self.current_state == STATE_SETTLEMENT:
            self.render_settlement_banner(video_area)

        # Simulation Step Toolbar
        self.render_toolbar()

    def render_countdown_gauge(self, video_area):
        banner_bg = COLOR_AMBER_BG if self.motion_detected else COLOR_EMERALD_BG
        banner_fg = COLOR_AMBER if self.motion_detected else COLOR_EMERALD
        banner_txt = "⚠️ MOTION DETECTED — KEEP CLEAR" if self.motion_detected else f"🟢 AI SCANNING PLATFORM ({self.countdown_remaining:.1f}s)"

        txt_surf = self.font_timer_badge.render(banner_txt, True, banner_fg)
        b_rect = pygame.Rect(video_area.centerx - txt_surf.get_width() // 2 - 16, video_area.top + 14, txt_surf.get_width() + 32, 34)
        pygame.draw.rect(self.screen, banner_bg, b_rect, border_radius=17)
        self.screen.blit(txt_surf, (b_rect.x + 16, b_rect.y + 7))

        # Radial Gauge
        cx, cy, radius = video_area.right - 50, video_area.top + 50, 36
        pygame.draw.circle(self.screen, COLOR_CARD_BG, (cx, cy), radius)
        progress = max(0.0, min(1.0, 1.0 - (self.countdown_remaining / 5.0)))
        arc_color = COLOR_AMBER if self.motion_detected else COLOR_EMERALD
        for i in range(20):
            ang = -math.pi / 2 + (2 * math.pi * (i / 20.0))
            if (i / 20.0) <= progress:
                px = int(cx + (radius - 5) * math.cos(ang))
                py = int(cy + (radius - 5) * math.sin(ang))
                pygame.draw.circle(self.screen, arc_color, (px, py), 3)

        num_surf = self.font_timer_large.render(str(max(1, int(math.ceil(self.countdown_remaining)))), True, arc_color)
        self.screen.blit(num_surf, (cx - num_surf.get_width() // 2, cy - num_surf.get_height() // 2))

    def render_settlement_banner(self, video_area):
        banner = pygame.Rect(video_area.centerx - 220, video_area.centery - 40, 440, 80)
        pygame.draw.rect(self.screen, COLOR_EMERALD_BG, banner, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_EMERALD, banner, width=2, border_radius=16)
        t1 = self.font_large.render("✓ PAYMENT APPROVED", True, COLOR_EMERALD)
        t2 = self.font_subtitle_bold.render("Payment have been confirmed please claim your order.", True, COLOR_TEXT_MAIN)
        self.screen.blit(t1, (banner.centerx - t1.get_width() // 2, banner.y + 12))
        self.screen.blit(t2, (banner.centerx - t2.get_width() // 2, banner.y + 48))

    def render_toolbar(self):
        """Renders an interactive, guided 3-step progress bar for students."""
        # Step 1: Tap ID
        if self.active_student is not None or self.current_state in [
            STATE_GREET, STATE_PREORDER_ANNOUNCEMENT, STATE_SCANNING,
            STATE_STABILITY_COUNTDOWN, STATE_SETTLEMENT
        ]:
            s1_state = "DONE"
            bal = self.active_student.get("balance", 0.0) if self.active_student else 0.0
            s1_sub = f"Bal: ₱{bal:.0f}"
        elif self.current_state == STATE_IDLE:
            s1_state = "ACTIVE"
            s1_sub = "Tap RFID Card"
        else:
            s1_state = "PENDING"
            s1_sub = "Tap Card"

        # Step 2: AI Scan (5s)
        if self.current_state == STATE_SETTLEMENT or (
            len(self.cart_items) > 0 and self.current_state == STATE_SCANNING
        ):
            s2_state = "DONE"
            cnt = sum(i.get("qty", 1) for i in self.cart_items)
            s2_sub = f"{cnt} Items Scanned"
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            s2_state = "ACTIVE"
            s2_sub = f"{self.countdown_remaining:.1f}s Scanning..."
        elif self.current_state in [STATE_GREET, STATE_SCANNING] and len(self.cart_items) > 0:
            s2_state = "ACTIVE"
            cnt = sum(i.get("qty", 1) for i in self.cart_items)
            s2_sub = f"{cnt} Items Detected"
        elif self.current_state in [STATE_GREET, STATE_SCANNING]:
            s2_state = "ACTIVE"
            s2_sub = "Scanning Tray..."
        else:
            s2_state = "PENDING"
            s2_sub = "Waiting"

        # Step 3: Cashier Pay
        if self.current_state == STATE_SETTLEMENT:
            s3_state = "DONE"
            s3_sub = f"Paid ₱{self.total_amount:.2f}"
        elif len(self.cart_items) > 0 and self.current_state != STATE_IDLE:
            s3_state = "ACTIVE"
            s3_sub = f"Total: ₱{self.total_amount:.2f}"
        else:
            s3_state = "PENDING"
            s3_sub = "Cashier Checkout"

        steps_info = [
            (self.btn_step1, "Step 1: Tap ID", s1_state, s1_sub, 1),
            (self.btn_step2, "Step 2: AI Scan (5s)", s2_state, s2_sub, 2),
            (self.btn_step3, "Step 3: Cashier Pay", s3_state, s3_sub, 3),
        ]

        # Draw connecting background progress track
        track_y = 578 + 23
        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (70, track_y), (650, track_y), 4)

        # Highlight completed segments on connecting line
        for i in range(len(steps_info) - 1):
            curr_rect, _, curr_state, _, _ = steps_info[i]
            next_rect, _, _, _, _ = steps_info[i + 1]
            if curr_state == "DONE":
                pygame.draw.line(self.screen, COLOR_EMERALD, (curr_rect.centerx, track_y), (next_rect.centerx, track_y), 4)

        mouse_pos = pygame.mouse.get_pos()

        # Render each step card
        for rect, label, state, subtext, num in steps_info:
            is_hover = rect.collidepoint(mouse_pos)

            if state == "DONE":
                bg_color = COLOR_EMERALD
                border_color = (5, 150, 105)
                title_color = COLOR_WHITE
                sub_color = (209, 250, 229)
                badge_bg = COLOR_WHITE
                badge_fg = COLOR_EMERALD
            elif state == "ACTIVE":
                bg_color = COLOR_ROSE_VIBRANT
                border_color = COLOR_GOLD_ACCENT if is_hover else COLOR_MAROON_DARK
                title_color = COLOR_WHITE
                sub_color = COLOR_GOLD_LIGHT
                badge_bg = COLOR_WHITE
                badge_fg = COLOR_ROSE_VIBRANT
            else:
                bg_color = (241, 245, 249)
                border_color = COLOR_CARD_BORDER if not is_hover else COLOR_TEXT_MUTED
                title_color = COLOR_TEXT_MUTED
                sub_color = (148, 163, 184)
                badge_bg = (226, 232, 240)
                badge_fg = (100, 116, 139)

            pygame.draw.rect(self.screen, bg_color, rect, border_radius=12)
            pygame.draw.rect(self.screen, border_color, rect, width=2 if (is_hover or state == "ACTIVE") else 1, border_radius=12)

            cx = rect.x + 22
            cy = rect.centery
            pygame.draw.circle(self.screen, badge_bg, (cx, cy), 13)
            if state == "DONE":
                self.screen.blit(self.font_badge.render("✓", True, badge_fg), (cx - 5, cy - 8))
            else:
                num_txt = self.font_badge.render(str(num), True, badge_fg)
                self.screen.blit(num_txt, (cx - num_txt.get_width() // 2, cy - num_txt.get_height() // 2))

            text_x = rect.x + 42
            lbl_surf = self.font_subtitle_bold.render(label, True, title_color)
            sub_surf = self.font_brand_sub.render(subtext, True, sub_color)
            self.screen.blit(lbl_surf, (text_x, rect.y + 7))
            self.screen.blit(sub_surf, (text_x, rect.y + 24))

    def render_right_panel(self):
        panel_rect = pygame.Rect(750, 100, 510, 545)
        pygame.draw.rect(self.screen, COLOR_CARD_BG, panel_rect, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, panel_rect, width=1, border_radius=16)

        title_surf = self.font_header.render("CUSTOMER ORDER SUMMARY", True, COLOR_MAROON_HEADER)
        subtitle_surf = self.font_subtitle.render("Scanned Food Items & Automated Price Tally", True, COLOR_TEXT_MUTED)
        self.screen.blit(title_surf, (775, 116))
        self.screen.blit(subtitle_surf, (775, 138))
        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 162), (1235, 162), 1)

        # Table Header
        self.screen.blit(self.font_brand_sub.render("ITEM DESCRIPTION", True, COLOR_TEXT_MUTED), (775, 168))
        self.screen.blit(self.font_brand_sub.render("QTY", True, COLOR_TEXT_MUTED), (1060, 168))
        self.screen.blit(self.font_brand_sub.render("PRICE", True, COLOR_TEXT_MUTED), (1165, 168))
        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 188), (1235, 188), 1)

        if self.current_state == STATE_IDLE or not self.cart_items:
            empty = self.font_body.render("Standby Mode: Tap Student RFID Card", True, COLOR_TEXT_MUTED)
            self.screen.blit(empty, (750 + (510 - empty.get_width()) // 2, 280))
            hint = self.font_subtitle.render("Place food items on counter after card is tapped.", True, COLOR_TEXT_MUTED)
            self.screen.blit(hint, (750 + (510 - hint.get_width()) // 2, 308))
        else:
            for idx, item in enumerate(self.cart_items[:6]):
                row_y = 200 + (idx * 44)
                if idx % 2 == 0:
                    pygame.draw.rect(self.screen, COLOR_CARD_ALT, (775, row_y - 2, 460, 38), border_radius=6)
                cat_tag = self.font_brand_sub.render(f"[{item.get('category', 'ITEM')}]", True, COLOR_GOLD_ACCENT)
                self.screen.blit(cat_tag, (785, row_y + 9))

                name = self.font_body_bold.render(item["name"], True, COLOR_TEXT_MAIN)
                qty = self.font_body.render(f"x{item.get('qty', 1)}", True, COLOR_TEXT_MAIN)
                price = self.font_body_bold.render(f"₱{item['price'] * item.get('qty', 1):.2f}", True, COLOR_ROSE_VIBRANT)

                self.screen.blit(name, (840, row_y + 8))
                self.screen.blit(qty, (1065, row_y + 8))
                self.screen.blit(price, (1165, row_y + 8))

        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 470), (1235, 470), 1)

        # Total Calculation Display
        total_lbl = self.font_header.render("TOTAL AMOUNT:", True, COLOR_TEXT_MAIN)
        total_val = self.font_large.render(f"₱{self.total_amount:.2f}", True, COLOR_ROSE_VIBRANT)
        self.screen.blit(total_lbl, (775, 492))
        self.screen.blit(total_val, (1235 - total_val.get_width(), 484))

        # Status Action Banner
        self.render_action_banner()

    def render_action_banner(self):
        banner_rect = pygame.Rect(775, 565, 460, 56)
        if self.current_state == STATE_IDLE:
            bg, txt, fg = COLOR_CARD_ALT, "Tap Student RFID Card to begin...", COLOR_TEXT_MUTED
        elif self.current_state in [STATE_GREET, STATE_SCANNING] and len(self.cart_items) == 0:
            bg, txt, fg = COLOR_MAROON_HEADER, "AI Overhead Vision Scanning Active...", COLOR_WHITE
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            bg = COLOR_AMBER_BG if self.motion_detected else COLOR_ROSE_VIBRANT
            txt = "⚠️ Motion Detected — Keep Hands Off" if self.motion_detected else f"⏳ AI Scanning ({self.countdown_remaining:.1f}s remaining)"
            fg = COLOR_MAROON_HEADER if self.motion_detected else COLOR_WHITE
        elif len(self.cart_items) > 0 and self.current_state != STATE_SETTLEMENT:
            bg, txt, fg = COLOR_EMERALD, "✓ Scanned Items Ready — Confirm at Cashier POS", COLOR_WHITE
        elif self.current_state == STATE_SETTLEMENT:
            bg, txt, fg = COLOR_EMERALD, "✓ Payment Confirmed — Please Claim Your Order!", COLOR_WHITE
        else:
            bg, txt, fg = COLOR_ROSE_ALERT, "⚡ Insufficient Balance — Press [P] for Pay Later", COLOR_WHITE

        self.pay_later_btn_rect = banner_rect
        pygame.draw.rect(self.screen, bg, banner_rect, border_radius=12)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, banner_rect, width=1, border_radius=12)
        surf = self.font_body_bold.render(txt, True, fg)
        self.screen.blit(surf, (banner_rect.centerx - surf.get_width() // 2, banner_rect.centery - surf.get_height() // 2))

    def render_preorder_announcement(self):
        panel_rect = pygame.Rect(20, 100, SCREEN_WIDTH - 40, 565)
        pygame.draw.rect(self.screen, COLOR_CARD_BG, panel_rect, border_radius=20)
        pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, panel_rect, width=2, border_radius=20)

        # Header ribbon
        ribbon_rect = pygame.Rect(20, 100, SCREEN_WIDTH - 40, 64)
        pygame.draw.rect(self.screen, COLOR_MAROON_HEADER, ribbon_rect, border_top_left_radius=20, border_top_right_radius=20)
        banner_txt = self.font_header.render("🍱 ACTIVE PRE-ORDER READY FOR COUNTER PICKUP", True, COLOR_GOLD_LIGHT)
        self.screen.blit(banner_txt, (panel_rect.centerx - banner_txt.get_width() // 2, 118))

        # Left Info Box
        st_name = self.active_student["name"] if self.active_student else "Student"
        first_po = self.active_preorders[0] if self.active_preorders else {}
        shelf_loc = first_po.get("shelf") or first_po.get("shelf_location") or "Shelf B2"

        left_col = pygame.Rect(45, 180, 570, 465)
        pygame.draw.rect(self.screen, COLOR_CARD_ALT, left_col, border_radius=16)

        greet_lbl = self.font_large.render(f"Welcome, {st_name}!", True, COLOR_MAROON_HEADER)
        self.screen.blit(greet_lbl, (65, 200))

        shelf_box = pygame.Rect(65, 260, 530, 120)
        pygame.draw.rect(self.screen, COLOR_EMERALD_BG, shelf_box, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_EMERALD, shelf_box, width=2, border_radius=16)

        self.screen.blit(self.font_subtitle_bold.render("PICKUP STATION / WARMING SHELF:", True, COLOR_EMERALD), (85, 275))
        self.screen.blit(self.font_title.render(f"📍 {shelf_loc.upper()}", True, COLOR_MAROON_HEADER), (85, 305))

        # Right Items List
        right_col = pygame.Rect(635, 180, 600, 465)
        pygame.draw.rect(self.screen, COLOR_CARD_ALT, right_col, border_radius=16)
        self.screen.blit(self.font_header.render("PRE-ORDERED MEAL ITEMS", True, COLOR_TEXT_MAIN), (655, 200))

        y_pos = 245
        for idx, po in enumerate(self.active_preorders[:3]):
            name = po.get("name") or po.get("item") or "Pork Adobo w/ Rice"
            price = float(po.get("price", 85.0))
            card = pygame.Rect(655, y_pos, 560, 65)
            pygame.draw.rect(self.screen, COLOR_WHITE, card, border_radius=12)
            self.screen.blit(self.font_body_bold.render(name, True, COLOR_TEXT_MAIN), (670, y_pos + 12))
            p_surf = self.font_large.render(f"₱{price:.2f}", True, COLOR_ROSE_VIBRANT)
            self.screen.blit(p_surf, (card.right - p_surf.get_width() - 15, y_pos + 14))
            y_pos += 75

    def render_rfid_confirm_overlay(self):
        """Full-screen overlay prompting student to tap RFID to confirm payment."""
        # Semi-transparent dark backdrop over left/right panels
        overlay = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT - 84 - 42), pygame.SRCALPHA)
        overlay.fill((10, 10, 20, 195))
        self.screen.blit(overlay, (0, 84))

        st = self.active_student or {}
        st_name = st.get("name", "Student")
        st_id = st.get("id", "—")
        rfid_uid = st.get("rfidUid", "—")
        balance = float(st.get("balance", 0.0))
        total = self.total_amount
        has_balance = balance >= total

        # Center card
        card_w, card_h = 680, 370
        card_x = (SCREEN_WIDTH - card_w) // 2
        card_y = 84 + ((SCREEN_HEIGHT - 84 - 42 - card_h) // 2)
        card_rect = pygame.Rect(card_x, card_y, card_w, card_h)

        # Card shadow (simple drop)
        shadow_rect = pygame.Rect(card_x + 5, card_y + 6, card_w, card_h)
        pygame.draw.rect(self.screen, (0, 0, 0, 100), shadow_rect, border_radius=24)

        # Card background
        card_bg = (16, 24, 40)
        pygame.draw.rect(self.screen, card_bg, card_rect, border_radius=24)
        border_color = COLOR_EMERALD if has_balance else COLOR_GOLD_ACCENT
        pygame.draw.rect(self.screen, border_color, card_rect, width=2, border_radius=24)

        # Header ribbon
        ribbon = pygame.Rect(card_x, card_y, card_w, 60)
        pygame.draw.rect(self.screen, COLOR_MAROON_HEADER, ribbon, border_top_left_radius=24, border_top_right_radius=24)
        title_surf = self.font_header.render("SCAN RFID TO CONFIRM PURCHASE", True, COLOR_GOLD_LIGHT)
        self.screen.blit(title_surf, (card_rect.centerx - title_surf.get_width() // 2, card_y + 16))

        # Animated pulse ring around card (pulse every 0.8s using time)
        pulse_t = time.time() % 1.0
        pulse_alpha = int(80 + 100 * abs(math.sin(pulse_t * math.pi)))
        ring_surf = pygame.Surface((card_w + 24, card_h + 24), pygame.SRCALPHA)
        pygame.draw.rect(ring_surf, (*border_color, pulse_alpha), (0, 0, card_w + 24, card_h + 24), width=3, border_radius=28)
        self.screen.blit(ring_surf, (card_x - 12, card_y - 12))

        # --- Student info block ---
        info_y = card_y + 76

        # Avatar circle
        av_cx, av_cy = card_x + 52, info_y + 44
        pygame.draw.circle(self.screen, COLOR_GOLD_ACCENT, (av_cx, av_cy), 34)
        initials = "".join([n[0] for n in st_name.split()[:2]]).upper()
        av_txt = self.font_title.render(initials, True, COLOR_MAROON_DARK)
        self.screen.blit(av_txt, (av_cx - av_txt.get_width() // 2, av_cy - av_txt.get_height() // 2))

        # Name + IDs
        name_surf = self.font_large.render(st_name, True, COLOR_WHITE)
        self.screen.blit(name_surf, (card_x + 102, info_y + 16))
        id_surf = self.font_subtitle_bold.render(f"Student No: {st_id}", True, COLOR_TEXT_MUTED)
        self.screen.blit(id_surf, (card_x + 102, info_y + 50))
        rfid_surf = self.font_brand_sub.render(f"RFID UID: {rfid_uid}", True, COLOR_TEXT_MUTED)
        self.screen.blit(rfid_surf, (card_x + 102, info_y + 70))

        # Divider
        div_y = info_y + 100
        pygame.draw.line(self.screen, (40, 50, 70), (card_x + 24, div_y), (card_x + card_w - 24, div_y), 1)

        # Balance + Total
        bal_y = div_y + 18
        bal_lbl = self.font_subtitle_bold.render("Current Balance:", True, COLOR_TEXT_MUTED)
        bal_val = self.font_large.render(f"₱{balance:.2f}", True, COLOR_EMERALD if has_balance else COLOR_ROSE_ALERT)
        self.screen.blit(bal_lbl, (card_x + 28, bal_y))
        self.screen.blit(bal_val, (card_x + card_w - bal_val.get_width() - 28, bal_y))

        tot_y = bal_y + 44
        tot_lbl = self.font_subtitle_bold.render("Order Total:", True, COLOR_TEXT_MUTED)
        tot_val = self.font_large.render(f"₱{total:.2f}", True, COLOR_ROSE_VIBRANT)
        self.screen.blit(tot_lbl, (card_x + 28, tot_y))
        self.screen.blit(tot_val, (card_x + card_w - tot_val.get_width() - 28, tot_y))

        pygame.draw.line(self.screen, (40, 50, 70), (card_x + 24, tot_y + 42), (card_x + card_w - 24, tot_y + 42), 1)

        # Instruction prompt
        prompt_y = tot_y + 56
        if has_balance:
            prompt_bg = COLOR_EMERALD
            prompt_txt = "👆  TAP YOUR RFID CARD NOW TO CONFIRM"
            prompt_fg = COLOR_WHITE
        else:
            prompt_bg = COLOR_GOLD_ACCENT
            prompt_txt = "⚠️  BALANCE LOW — PRESS [P] FOR PAY LATER"
            prompt_fg = COLOR_MAROON_DARK

        btn_rect = pygame.Rect(card_x + 28, prompt_y, card_w - 56, 46)
        pygame.draw.rect(self.screen, prompt_bg, btn_rect, border_radius=14)
        p_surf = self.font_body_bold.render(prompt_txt, True, prompt_fg)
        self.screen.blit(p_surf, (btn_rect.centerx - p_surf.get_width() // 2, btn_rect.centery - p_surf.get_height() // 2))

    def render_footer(self):
        footer_rect = pygame.Rect(0, 678, SCREEN_WIDTH, 42)
        pygame.draw.rect(self.screen, COLOR_MAROON_HEADER, footer_rect)
        pygame.draw.line(self.screen, COLOR_GOLD_ACCENT, (0, 678), (SCREEN_WIDTH, 678), 1)

        msg = self.font_footer.render(f"STATUS: {self.status_message} | REAL-TIME POS SERVER: ACTIVE (PORT {HTTP_PORT})", True, COLOR_WHITE)
        self.screen.blit(msg, (24, 690))
        shortcuts = self.font_subtitle_bold.render("[SHORTCUTS: 1-4 | P: PAY LATER | W: SWAP AI | SPACE | R: RESET]", True, COLOR_GOLD_LIGHT)
        self.screen.blit(shortcuts, (SCREEN_WIDTH - shortcuts.get_width() - 24, 690))

    # ==========================================================================
    # MAIN APPLICATION LOOP
    # ==========================================================================
    def run(self):
        running = True
        print(f"=============================================================")
        print(f"  NOVALUNCH STUDENT-FACING DISPLAY (CFD) MONITOR INITIALIZED ")
        print(f"  Live Real-Time Cashier POS Bridge Active on Port {HTTP_PORT}")
        print(f"=============================================================")

        while running:
            dt = self.clock.tick(TARGET_FPS) / 1000.0

            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        running = False
                    elif event.key in [pygame.K_RETURN, pygame.K_KP_ENTER]:
                        if len(self.rfid_scan_buffer) >= 4:
                            self.handle_rfid_tap(self.rfid_scan_buffer.strip())
                        else:
                            self.handle_rfid_tap()
                        self.rfid_scan_buffer = ""
                    elif event.key == pygame.K_SPACE:
                        self.handle_rfid_tap()
                    elif event.key == pygame.K_p:
                        self.execute_pay_later_checkout()
                    elif event.key == pygame.K_w:
                        # Quick swap Fried Chicken <-> Pork Adobo
                        for it in self.cart_items:
                            if "Chicken" in it["name"]:
                                it["name"] = "Pork Adobo with Rice"
                                it["ai_label"] = "pork_adobo"
                                break
                            elif "Pork" in it["name"]:
                                it["name"] = "Crispy Chicken Bowl"
                                it["ai_label"] = "fried_chicken"
                                break
                        self.recalculate_total()
                    elif event.key == pygame.K_m:
                        self.motion_detected = not self.motion_detected
                    elif event.key == pygame.K_r:
                        self.transition_to_state(STATE_IDLE)
                    elif event.key in [pygame.K_1, pygame.K_KP1]:
                        self.execute_simulation_step(1)
                    elif event.key in [pygame.K_2, pygame.K_KP2]:
                        self.execute_simulation_step(2)
                    elif event.key in [pygame.K_3, pygame.K_KP3]:
                        self.execute_simulation_step(3)
                    elif event.key in [pygame.K_4, pygame.K_KP4]:
                        self.execute_simulation_step(4)
                    elif event.key == pygame.K_c:
                        self.camera_thread.toggle_manual()

                    if event.unicode and (event.unicode.isalnum() or event.unicode in ['-', '_']):
                        now = time.time()
                        if now - self.last_key_time > 0.4:
                            self.rfid_scan_buffer = ""
                        self.rfid_scan_buffer += event.unicode
                        self.last_key_time = now

                elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                    pos = event.pos
                    if hasattr(self, 'pay_later_btn_rect') and self.pay_later_btn_rect.collidepoint(pos) and self.current_state == STATE_SETTLEMENT:
                        self.execute_pay_later_checkout()
                    elif self.btn_step1.collidepoint(pos):
                        self.execute_simulation_step(1)
                    elif self.btn_step2.collidepoint(pos):
                        self.execute_simulation_step(2)
                    elif self.btn_step3.collidepoint(pos):
                        self.execute_simulation_step(3)
                    elif self.btn_step4.collidepoint(pos):
                        self.execute_simulation_step(4)

            # Auto-transitions & Live Scanned Food Summary Sync
            now = time.time()
            if self.current_state == STATE_IDLE:
                # Standby Mode: Do NOT scan food items or update cart until student taps card
                if self.cart_items:
                    self.cart_items = []
                    self.total_amount = 0.0

            elif self.current_state == STATE_PREORDER_ANNOUNCEMENT and (now - self.state_timer >= 8.0):
                self.transition_to_state(STATE_IDLE)

            elif self.current_state in [STATE_GREET, STATE_SCANNING]:
                if now - self.state_timer >= 20.0:
                    self.transition_to_state(STATE_IDLE)
                else:
                    live_items = self.camera_thread.get_latest_detections()
                    if live_items:
                        agg_items = aggregate_detections(live_items)
                        curr_hash = "-".join(sorted([f"{item['name']}:{item.get('qty', 1)}" for item in agg_items]))
                        if curr_hash == self.last_detection_hash:
                            if self.stable_start_time == 0.0:
                                self.stable_start_time = now
                            elif now - self.stable_start_time >= 1.2:
                                self.cart_items = agg_items
                                self.recalculate_total()
                                self.transition_to_state(STATE_STABILITY_COUNTDOWN)
                        else:
                            self.last_detection_hash = curr_hash
                            self.stable_start_time = now
                            self.cart_items = agg_items
                            self.recalculate_total()

            elif self.current_state == STATE_STABILITY_COUNTDOWN:
                if self.motion_detected:
                    self.countdown_remaining = 5.0
                else:
                    self.motion_voice_alerted = False
                    self.countdown_remaining -= dt
                    curr_sec = int(math.ceil(self.countdown_remaining))
                    if curr_sec < self.last_tick_sec and curr_sec >= 1:
                        self.last_tick_sec = curr_sec
                    if self.countdown_remaining <= 0.0:
                        # 5-second scan finished — hold cart items ready for Cashier confirmation (do NOT auto-deduct)
                        cnt = len(self.cart_items)
                        self.status_message = f"🟢 Scanned {cnt} item(s) (₱{self.total_amount:.2f}) — Sent to Cashier POS"
                        self.current_state = STATE_SCANNING
                        self.notify_pos_update()

            elif self.current_state == STATE_SETTLEMENT and (now - self.state_timer >= 3.0):
                # 3-second thank-you screen then return to idle (clears cart for next customer)
                self.transition_to_state(STATE_IDLE)
            elif self.current_state == STATE_ERROR and (now - self.state_timer >= 4.0):
                self.transition_to_state(STATE_IDLE)

            self.screen.fill(COLOR_BG_CANVAS)
            self.render_header()
            if self.current_state == STATE_PREORDER_ANNOUNCEMENT:
                self.render_preorder_announcement()
            else:
                self.render_left_panel()
                self.render_right_panel()
            self.render_footer()

            pygame.display.flip()

        self.camera_thread.stop()
        pygame.quit()
        sys.exit(0)

if __name__ == "__main__":
    app = NovaLunchKioskGUI()
    app.run()
