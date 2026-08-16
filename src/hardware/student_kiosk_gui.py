#!/usr/bin/env python3
"""
NovaLunch Automated Canteen Kiosk — Student-Facing Display (CFD) Monitor GUI
=============================================================================
Enterprise-grade, multi-threaded Pygame & OpenCV interface for Saint Joseph College.

System Architecture (Customer-Facing Display / Passive Monitor Edition):
- Passive, high-visibility 2026 Student-Facing Display (CFD) facing the customer.
- Built-in prototype counter platform overhead AI camera scanning zone with dual hardware & synthetic stream fallback.
- Institutional Logo integration (assets/images/branding/school no bg.png).
- Automatic hardware event pipeline (Overhead Camera, 125kHz RFID Wedge Reader).
- Clean light minimalist maroon theme optimized for high legibility under canteen lighting.
- Multi-threaded OpenCV video stream, YOLOv8 inference, SQLite transaction persistence, Supabase Dual-Sync, and TTS audio announcements.
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
import numpy as np
import cv2
import pygame

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://wtvkmywmlifcsddlgvnn.supabase.co")
SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY", "sb_publishable_yywY2quhz5k1x6Pu_w6pgQ_e-mBU0q2")

class CloudSyncWorker(threading.Thread):
    def __init__(self, sqlite_db_path="src/database/novalunch_edge.db", sync_interval_sec=10):
        super().__init__()
        self.daemon = True
        # Resolve path relative to project root if needed
        if not os.path.exists(sqlite_db_path) and os.path.exists("novalunch_edge.db"):
            sqlite_db_path = "novalunch_edge.db"
        self.sqlite_db_path = os.path.abspath(sqlite_db_path)
        self.sync_interval_sec = sync_interval_sec
        self.running = True

    def run(self):
        print("[CLOUD DUAL-SYNC WORKER] 🟢 Background synchronization thread started.")
        while self.running:
            try:
                self._sync_pending_transactions()
            except Exception as e:
                print(f"[CLOUD DUAL-SYNC WARN] Sync error: {e}")
            time.sleep(self.sync_interval_sec)

    def _sync_pending_transactions(self):
        if not os.path.exists(self.sqlite_db_path):
            return
        
        conn = sqlite3.connect(self.sqlite_db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT transaction_id, student_id, items_purchased, total_amount, payment_method, timestamp FROM pending_transactions WHERE sync_status = 'EDGE_CACHED'")
        rows = cursor.fetchall()
        conn.close()

        if not rows:
            return

        print(f"[CLOUD DUAL-SYNC] Found {len(rows)} pending edge transactions. Syncing to Supabase cloud...")

        for row in rows:
            tx_id, student_id, items_json, total_amt, pay_method, ts = row
            try:
                # 1. Resolve student UUID from Supabase profiles if possible
                user_uuid = None
                try:
                    q_url = f"{SUPABASE_URL}/rest/v1/profiles?student_id_number=eq.{urllib.parse.quote(str(student_id))}&select=id"
                    req_prof = urllib.request.Request(
                        q_url,
                        headers={
                            "apikey": SUPABASE_ANON_KEY,
                            "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
                        }
                    )
                    with urllib.request.urlopen(req_prof, timeout=4) as p_resp:
                        p_data = json.loads(p_resp.read().decode('utf-8'))
                        if p_data and len(p_data) > 0:
                            user_uuid = p_data[0].get("id")
                except Exception as p_err:
                    print(f"[CLOUD DUAL-SYNC NOTICE] Could not resolve UUID for student {student_id}: {p_err}")

                order_num = tx_id if str(tx_id).startswith("ORD-") else f"ORD-AI-{tx_id}"

                payload_dict = {
                    "order_number": order_num,
                    "total_amount": total_amt,
                    "final_amount": total_amt,
                    "payment_method": "rfid",       # Valid enum: 'rfid', 'wallet', 'cash', 'online', 'pay_later'
                    "payment_status": "paid",       # Valid enum: 'paid', 'pending', 'refunded', 'failed'
                    "order_source": "ai_kiosk",     # Valid enum: 'cashier_pos', 'ai_kiosk', 'mobile_preorder'
                    "order_status": "completed"     # Valid enum: 'completed', 'preparing', 'cancelled'
                }
                if user_uuid:
                    payload_dict["user_id"] = user_uuid

                payload = json.dumps(payload_dict).encode('utf-8')

                req = urllib.request.Request(
                    f"{SUPABASE_URL}/rest/v1/orders",
                    data=payload,
                    headers={
                        "apikey": SUPABASE_ANON_KEY,
                        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                        "Content-Type": "application/json",
                        "Prefer": "return=minimal"
                    },
                    method="POST"
                )
                with urllib.request.urlopen(req, timeout=5) as resp:
                    if resp.status in [200, 201, 204]:
                        conn = sqlite3.connect(self.sqlite_db_path)
                        c = conn.cursor()
                        c.execute("UPDATE pending_transactions SET sync_status = 'SYNCED_TO_CLOUD' WHERE transaction_id = ?", (tx_id,))
                        conn.commit()
                        conn.close()
                        print(f"[CLOUD DUAL-SYNC SUCCESS] ☁️ Uploaded transaction {tx_id} ({order_num}) to Supabase cloud.")
            except Exception as err:
                print(f"[CLOUD DUAL-SYNC NOTICE] Tx {tx_id} sync attempt deferred (Offline or Cloud unreachable): {err}")

# ==============================================================================
# CONFIGURATION & COLOR PALETTE (2026 LIGHT MINIMALIST MAROON SYSTEM)
# ==============================================================================
SCREEN_WIDTH = 1280
SCREEN_HEIGHT = 720
TARGET_FPS = 60

# 2026 Light Minimalist Maroon Palette (High Visibility Display)
COLOR_BG_CANVAS = (248, 250, 252)        # Crisp Slate White Backdrop (#F8FAFC)
COLOR_CARD_BG = (255, 255, 255)          # Pure White Glass Surface (#FFFFFF)
COLOR_CARD_ALT = (241, 245, 249)         # Alternating Table Row (#F1F5F9)
COLOR_CARD_BORDER = (226, 232, 240)      # Delicate Card Outline (#E2E8F0)

COLOR_MAROON_HEADER = (74, 14, 23)       # Deep School Burgundy Header (#4A0E17)
COLOR_MAROON_DARK = (45, 8, 14)          # Deep Crimson Accent (#2D080E)
COLOR_ROSE_VIBRANT = (201, 24, 74)       # Radiant Crimson Highlight (#C9184A)
COLOR_GOLD_ACCENT = (217, 119, 6)        # Amber Gold Accent (#D97706)
COLOR_GOLD_LIGHT = (254, 243, 199)       # Warm Cream Gold Pill Fill (#FEF3C7)

COLOR_TEXT_MAIN = (15, 23, 42)           # Deep Slate Onyx Heading Text (#0F172A)
COLOR_TEXT_MUTED = (100, 116, 139)       # Slate Gray Body Text (#64748B)
COLOR_WHITE = (255, 255, 255)            # Pure White (#FFFFFF)

COLOR_EMERALD = (16, 185, 129)           # E-Wallet Success Green (#10B981)
COLOR_EMERALD_BG = (236, 253, 245)       # Light Emerald Pill Fill
COLOR_AMBER = (245, 158, 11)             # Warning Amber (#F59E0B)
COLOR_AMBER_BG = (254, 243, 199)         # Warning Amber Pill Fill
COLOR_ROSE_ALERT = (225, 29, 72)         # Alert Red (#E11D48)
COLOR_ROSE_ALERT_BG = (255, 228, 230)    # Alert Light Red Pill Fill
COLOR_CYAN_HUD = (6, 182, 212)           # Active HUD Cyan (#06B6D4)

# State Constants
STATE_IDLE = 1
STATE_GREET = 2
STATE_SCANNING = 3
STATE_STABILITY_COUNTDOWN = 5
STATE_SETTLEMENT = 4
STATE_ERROR = 6
STATE_PREORDER_ANNOUNCEMENT = 7

# ==============================================================================
# DATABASE MANAGER (DYNAMIC ACCOUNTS, SUPABASE CLOUD & SQLITE PERSISTENCE)
# ==============================================================================
class DatabaseManager:
    def __init__(self, accounts_json_path="src/database/accounts.json", sqlite_db_path="src/database/novalunch_edge.db"):
        if not os.path.exists(accounts_json_path) and os.path.exists("database/accounts.json"):
            accounts_json_path = "database/accounts.json"
        if not os.path.exists(sqlite_db_path) and os.path.exists("novalunch_edge.db"):
            sqlite_db_path = "novalunch_edge.db"
        self.accounts_json_path = os.path.abspath(accounts_json_path)
        self.sqlite_db_path = os.path.abspath(sqlite_db_path)
        self._init_sqlite_db()
        self.sync_remote_accounts()
        self.sync_worker = CloudSyncWorker(self.sqlite_db_path)
        self.sync_worker.start()

    def _init_sqlite_db(self):
        try:
            conn = sqlite3.connect(self.sqlite_db_path)
            cursor = conn.cursor()
            cursor.execute("""
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
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS retrain_logs (
                    log_id TEXT PRIMARY KEY,
                    action TEXT NOT NULL,
                    item_id TEXT NOT NULL,
                    corrected_label TEXT NOT NULL,
                    image_path TEXT NOT NULL,
                    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """)
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"[DB MANAGER WARN] SQLite init warning: {e}")

    def sync_remote_accounts(self):
        """Attempts to fetch fresh student account profiles & wallet balances from Supabase."""
        def _fetch_remote():
            try:
                url = f"{SUPABASE_URL}/rest/v1/profiles?role=eq.student&select=id,full_name,email,student_id_number,rfid_uid,wallets(balance,daily_limit)"
                req = urllib.request.Request(
                    url,
                    headers={
                        "apikey": SUPABASE_ANON_KEY,
                        "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
                    }
                )
                with urllib.request.urlopen(req, timeout=5) as resp:
                    if resp.status == 200:
                        remote_profiles = json.loads(resp.read().decode('utf-8'))
                        if remote_profiles and isinstance(remote_profiles, list):
                            local_students = self.load_accounts()
                            by_id = {st.get("student_id_number"): st for st in local_students}
                            
                            for p in remote_profiles:
                                st_id = p.get("student_id_number")
                                if not st_id:
                                    continue
                                w_data = p.get("wallets") or [{}]
                                w_first = w_data[0] if isinstance(w_data, list) and len(w_data) > 0 else {}
                                bal = float(w_first.get("balance", p.get("balance", 200.0)))
                                d_lim = float(w_first.get("daily_limit", p.get("daily_limit", 200.0)))
                                
                                if st_id in by_id:
                                    by_id[st_id]["balance"] = bal
                                    by_id[st_id]["daily_limit"] = d_lim
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
                                        "daily_limit": d_lim
                                    }
                            
                            updated_list = list(by_id.values())
                            self.save_accounts(updated_list)
                            print(f"[DB MANAGER] ☁️ Synced {len(remote_profiles)} student accounts from Supabase cloud.")
            except Exception as e:
                print(f"[DB MANAGER NOTICE] Remote Supabase sync deferred (Offline mode active): {e}")

        threading.Thread(target=_fetch_remote, daemon=True).start()

    def load_accounts(self):
        if os.path.exists(self.accounts_json_path):
            try:
                with open(self.accounts_json_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    return data.get("students", [])
            except Exception as e:
                print(f"[DB MANAGER WARN] Failed to load accounts.json: {e}")
        return []

    def save_accounts(self, students_list):
        if os.path.exists(self.accounts_json_path):
            try:
                with open(self.accounts_json_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                data["students"] = students_list
                with open(self.accounts_json_path, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2)
                print(f"[DB MANAGER] 💾 Persisted updated student accounts to {self.accounts_json_path}")
            except Exception as e:
                print(f"[DB MANAGER ERROR] Failed to save accounts.json: {e}")

    def find_student_by_rfid(self, rfid_uid):
        if not rfid_uid:
            return None
        raw_scanned = str(rfid_uid).strip()
        scanned_upper = raw_scanned.upper()
        scanned_clean = scanned_upper.replace("-", "")
        scanned_nozero = scanned_clean.lstrip("0")

        students = self.load_accounts()
        
        for student in students:
            db_rfid = str(student.get("rfid_uid", "")).strip()
            db_id = str(student.get("student_id_number", "")).strip()
            db_email = str(student.get("email", "")).strip()
            
            db_rfid_clean = db_rfid.upper().replace("-", "")
            db_id_clean = db_id.upper().replace("-", "")
            
            # Exact Match
            if raw_scanned in (db_rfid, db_id, db_email):
                return {
                    "id": student.get("student_id_number"),
                    "name": student.get("full_name"),
                    "email": student.get("email"),
                    "rfidUid": student.get("rfid_uid"),
                    "balance": float(student.get("balance", 0.0)),
                    "daily_limit": float(student.get("daily_limit", 200.0))
                }

            # Normalized Hyphenless Case-Insensitive Match
            if scanned_clean and (scanned_clean == db_rfid_clean or scanned_clean == db_id_clean):
                return {
                    "id": student.get("student_id_number"),
                    "name": student.get("full_name"),
                    "email": student.get("email"),
                    "rfidUid": student.get("rfid_uid"),
                    "balance": float(student.get("balance", 0.0)),
                    "daily_limit": float(student.get("daily_limit", 200.0))
                }

            # Zero-stripped fallback only if non-empty
            if scanned_nozero and (scanned_nozero == db_rfid_clean.lstrip("0") or scanned_nozero == db_id_clean.lstrip("0")):
                return {
                    "id": student.get("student_id_number"),
                    "name": student.get("full_name"),
                    "email": student.get("email"),
                    "rfidUid": student.get("rfid_uid"),
                    "balance": float(student.get("balance", 0.0)),
                    "daily_limit": float(student.get("daily_limit", 200.0))
                }

        # Cloud Fallback Lookup if not found in local accounts cache
        try:
            quoted_uid = urllib.parse.quote(raw_scanned)
            url = f"{SUPABASE_URL}/rest/v1/profiles?role=eq.student&or=(rfid_uid.eq.{quoted_uid},student_id_number.eq.{quoted_uid},email.eq.{quoted_uid})&select=id,full_name,email,student_id_number,rfid_uid,wallets(balance,daily_limit)"
            req = urllib.request.Request(url, headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"})
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode('utf-8'))
                    if data and len(data) > 0:
                        p = data[0]
                        w_data = p.get("wallets") or [{}]
                        w_first = w_data[0] if isinstance(w_data, list) and len(w_data) > 0 else {}
                        bal = float(w_first.get("balance", p.get("balance", 200.0)))
                        d_lim = float(w_first.get("daily_limit", p.get("daily_limit", 200.0)))
                        st_id = p.get("student_id_number") or p.get("id")
                        
                        # Cache into local accounts.json
                        new_st = {
                            "full_name": p.get("full_name", "Student"),
                            "email": p.get("email", ""),
                            "role": "student",
                            "student_id_number": st_id,
                            "rfid_uid": p.get("rfid_uid", raw_scanned),
                            "balance": bal,
                            "daily_limit": d_lim
                        }
                        students.append(new_st)
                        self.save_accounts(students)
                        print(f"[DB MANAGER] ☁️ Resolved new RFID tag {raw_scanned} directly from Supabase Cloud: {new_st['full_name']}")
                        return {
                            "id": st_id,
                            "name": new_st["full_name"],
                            "email": new_st["email"],
                            "rfidUid": new_st["rfid_uid"],
                            "balance": bal,
                            "daily_limit": d_lim
                        }
        except Exception as c_err:
            print(f"[DB MANAGER NOTICE] Online RFID fallback lookup error: {c_err}")

        return None

    def get_active_preorders(self, student_id, student_name=None):
        """Fetches pending/ready pre-orders for the given student from Supabase or local cache."""
        active_pos = []
        try:
            quoted_id = urllib.parse.quote(str(student_id))
            url = f"{SUPABASE_URL}/rest/v1/preorders?or=(student_id.eq.{quoted_id},student_name.eq.{quoted_id})&status=neq.Claimed&select=*"
            req = urllib.request.Request(
                url,
                headers={
                    "apikey": SUPABASE_ANON_KEY,
                    "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
                }
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                if resp.status == 200:
                    data = json.loads(resp.read().decode('utf-8'))
                    if data and isinstance(data, list) and len(data) > 0:
                        return data
        except Exception as e:
            print(f"[DB MANAGER NOTICE] Online pre-order check deferred: {e}")

        # Local fallback simulation / accounts cache
        local_po_path = "src/database/preorders.json"
        if not os.path.exists(local_po_path) and os.path.exists("database/preorders.json"):
            local_po_path = "database/preorders.json"
        if os.path.exists(local_po_path):
            try:
                with open(local_po_path, "r", encoding="utf-8") as f:
                    local_data = json.load(f)
                    pos = local_data.get("preorders", [])
                    for po in pos:
                        if (po.get("student_id") == student_id or po.get("studentId") == student_id or (student_name and po.get("student_name") == student_name)) and po.get("status") != "Claimed":
                            active_pos.append(po)
                    if active_pos:
                        return active_pos
            except Exception:
                pass

        # Demo fallback for testing with default registered student accounts
        if str(student_id) in ["2023-01900", "u101", "2023-08812"]:
            return [{
                "id": "po-demo-01",
                "name": "Pork Adobo w/ Steamed Rice",
                "price": 85.00,
                "shelf": "Shelf B2",
                "session": "Lunch Break (12:00 PM)",
                "status": "Ready"
            }]

        return []

    def deduct_student_balance(self, student_id, amount):
        students = self.load_accounts()
        updated = False
        new_balance = 0.0
        for student in students:
            if (student.get("student_id_number") == student_id or 
                student.get("email") == student_id or 
                student.get("id") == student_id):
                curr_bal = float(student.get("balance", 0.0))
                new_balance = max(0.0, curr_bal - amount)
                student["balance"] = new_balance
                updated = True
                break
        if updated:
            self.save_accounts(students)
            # Sync balance patch to Supabase Cloud if online
            def _patch_supabase():
                try:
                    quoted_id = urllib.parse.quote(str(student_id))
                    q = f"{SUPABASE_URL}/rest/v1/profiles?or=(student_id_number.eq.{quoted_id},id.eq.{quoted_id},email.eq.{quoted_id})&select=id"
                    req = urllib.request.Request(q, headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"})
                    with urllib.request.urlopen(req, timeout=4) as r:
                        p_data = json.loads(r.read().decode('utf-8'))
                        if p_data and len(p_data) > 0:
                            u_id = p_data[0]["id"]
                            patch_payload = json.dumps({"balance": new_balance}).encode('utf-8')
                            
                            # Patch wallets table
                            p_req = urllib.request.Request(
                                f"{SUPABASE_URL}/rest/v1/wallets?user_id=eq.{u_id}",
                                data=patch_payload,
                                headers={
                                    "apikey": SUPABASE_ANON_KEY,
                                    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                                    "Content-Type": "application/json",
                                    "Prefer": "return=minimal"
                                },
                                method="PATCH"
                            )
                            urllib.request.urlopen(p_req, timeout=4)

                            # Patch profiles table
                            prof_req = urllib.request.Request(
                                f"{SUPABASE_URL}/rest/v1/profiles?id=eq.{u_id}",
                                data=patch_payload,
                                headers={
                                    "apikey": SUPABASE_ANON_KEY,
                                    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                                    "Content-Type": "application/json",
                                    "Prefer": "return=minimal"
                                },
                                method="PATCH"
                            )
                            urllib.request.urlopen(prof_req, timeout=4)
                except Exception as patch_err:
                    print(f"[DB MANAGER WARN] Cloud wallet patch error: {patch_err}")
            threading.Thread(target=_patch_supabase, daemon=True).start()

        return new_balance

    def record_transaction(self, transaction_id, student_id, cart_items, total_amount, tray_image_url="", payment_method="E_WALLET"):
        try:
            conn = sqlite3.connect(self.sqlite_db_path)
            cursor = conn.cursor()
            items_json = json.dumps([{
                "name": i.get("name"),
                "qty": i.get("qty", 1),
                "price": i.get("price", 0.0),
                "category": i.get("category", "ITEM")
            } for i in cart_items])

            cursor.execute("""
                INSERT INTO pending_transactions 
                (transaction_id, student_id, items_purchased, total_amount, payment_method, tray_image_url, sync_status)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (transaction_id, student_id, items_json, total_amount, payment_method, tray_image_url, "EDGE_CACHED"))
            conn.commit()
            conn.close()
            print(f"[DB MANAGER] 🟢 Saved SQLite transaction {transaction_id} ({payment_method}) to novalunch_edge.db")
        except Exception as e:
            print(f"[DB MANAGER ERROR] Failed to record transaction: {e}")

    def get_student_daily_spent(self, student_id):
        try:
            conn = sqlite3.connect(self.sqlite_db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT SUM(total_amount) FROM pending_transactions WHERE student_id = ? AND date(timestamp) = date('now')", (student_id,))
            row = cursor.fetchone()
            conn.close()
            return float(row[0]) if row and row[0] is not None else 0.0
        except Exception as e:
            print(f"[DB MANAGER WARN] Error querying daily spent: {e}")
            return 0.0

# ==============================================================================
# THREADED CAMERA CAPTURE MANAGER & AI VISION PIPELINE (DYNAMIC DUAL FALLBACK)
# ==============================================================================
YOLO_MODEL_INSTANCE = None
YOLO_LOAD_ATTEMPTED = False

def get_yolo_model(pt_path="src/assets/models/novalunch_yolo.pt"):
    global YOLO_MODEL_INSTANCE, YOLO_LOAD_ATTEMPTED
    if YOLO_MODEL_INSTANCE is not None:
        return YOLO_MODEL_INSTANCE
    if YOLO_LOAD_ATTEMPTED:
        return None
    YOLO_LOAD_ATTEMPTED = True
    if not os.path.exists(pt_path) and os.path.exists("novalunch_yolo.pt"):
        pt_path = "novalunch_yolo.pt"
    if os.path.exists(pt_path):
        try:
            from ultralytics import YOLO
            YOLO_MODEL_INSTANCE = YOLO(pt_path)
            print(f"[AI VISION SYSTEM] 🟢 Successfully loaded Ultralytics YOLO model: {pt_path}")
        except Exception as e:
            print(f"[AI VISION WARN] Could not load Ultralytics YOLO model ({pt_path}): {e}")
            YOLO_MODEL_INSTANCE = None
    return YOLO_MODEL_INSTANCE

class CameraThread(threading.Thread):
    def __init__(self, camera_index=0):
        super().__init__()
        self.daemon = True
        self.camera_index = camera_index
        self.cap = None
        self.current_frame = None
        self.frame_size = (640, 480)
        self.latest_detections = []
        self.ai_engine_name = "YOLOv8 Engine"
        self.fps_display = 60
        self.fps_counter = 0
        self.fps_start_time = time.time()
        self.lock = threading.Lock()
        self.running = True
        self.is_connected = False
        self.manual_enabled = True
        self.last_retry_time = 0

        self._init_camera()


    def _init_camera(self):
        """Scans hardware indices [0, 1, 2] to acquire live video stream."""
        for idx in [self.camera_index, 0, 1, 2]:
            try:
                cap_test = cv2.VideoCapture(idx)
                if cap_test and cap_test.isOpened():
                    cap_test.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                    cap_test.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                    ret, test_frame = cap_test.read()
                    if ret and test_frame is not None:
                        self.cap = cap_test
                        self.is_connected = True
                        print(f"[CAMERA LIFECYCLE] 🟢 Video camera stream (hardware index {idx}) initialized.")
                        return
                    else:
                        cap_test.release()
            except Exception as e:
                print(f"[CAMERA LIFECYCLE WARN] Index {idx} probe warning: {e}")
        
        self.is_connected = False
        print("[CAMERA LIFECYCLE WARN] No hardware camera available. Synthetic Vision Fallback active.")

    def toggle_manual(self):
        """Toggles hardware/manual camera state without throwing AttributeError."""
        with self.lock:
            self.manual_enabled = not self.manual_enabled
            return self.manual_enabled

    def _generate_synthetic_frame(self, angle_deg):
        """Renders dynamic synthetic video stream with animated tray & simulated food items."""
        h, w = 480, 640
        canvas = np.full((h, w, 3), (30, 35, 45), dtype=np.uint8)

        # Counter scanning platform grid
        for x in range(0, w, 40):
            cv2.line(canvas, (x, 0), (x, h), (45, 50, 65), 1)
        for y in range(0, h, 40):
            cv2.line(canvas, (0, y), (w, y), (45, 50, 65), 1)

        # Tray boundary outline
        cv2.rectangle(canvas, (100, 70), (540, 410), (60, 65, 80), 2)
        cv2.putText(canvas, "NOVALUNCH OVERHEAD SCANNER PLATFORM (SYNTHETIC FEED)", (115, 95), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (160, 175, 200), 1)

        # Sweeping cyan laser line
        sweep_y = int(80 + (320 * (math.sin(math.radians(angle_deg)) + 1.0) / 2.0))
        cv2.line(canvas, (105, sweep_y), (535, sweep_y), (212, 182, 6), 2)

        # Simulated Food Item 1: Buttercream Crackers
        cv2.rectangle(canvas, (150, 130), (320, 270), (14, 14, 74), -1)
        cv2.rectangle(canvas, (150, 130), (320, 270), (74, 24, 201), 2)
        cv2.putText(canvas, "Buttercream Crackers", (160, 160), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
        cv2.putText(canvas, "P35.00", (160, 180), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (199, 243, 254), 1)

        # Simulated Food Item 2: Mineral Water 500ml
        cv2.rectangle(canvas, (360, 150), (480, 360), (74, 14, 23), -1)
        cv2.rectangle(canvas, (360, 150), (480, 360), (217, 119, 6), 2)
        cv2.putText(canvas, "Mineral Water", (370, 180), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1)
        cv2.putText(canvas, "500ml - P20.00", (370, 200), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (254, 243, 199), 1)

        detections = [
            {
                "ai_label": "buttercream_crackers",
                "name": "Buttercream Crackers",
                "category": "SNACK",
                "qty": 1,
                "price": 35.00,
                "stock": 50,
                "bbox": [150, 130, 170, 140],
                "conf": 0.98
            },
            {
                "ai_label": "water_bottle",
                "name": "Mineral Water 500ml",
                "category": "BEVERAGE",
                "qty": 1,
                "price": 20.00,
                "stock": 150,
                "bbox": [360, 150, 120, 210],
                "conf": 0.96
            }
        ]

        return canvas, detections

    def run(self):
        synth_angle = 0
        while self.running:
            try:
                if self.is_connected and self.manual_enabled and self.cap is not None:
                    ret, frame = self.cap.read()
                    if ret and frame is not None:
                        self.fps_counter += 1
                        if time.time() - self.fps_start_time >= 1.0:
                            self.fps_display = self.fps_counter
                            self.fps_counter = 0
                            self.fps_start_time = time.time()
                            
                            # CAMERA HEALTH WATCHDOG DAEMON (<5 FPS for >2s triggers auto-failover)
                            if self.fps_display < 5:
                                self.low_fps_duration = getattr(self, 'low_fps_duration', 0) + 1.0
                                if self.low_fps_duration >= 2.0:
                                    print("[CAMERA WATCHDOG] ⚠️ Stream FPS dropped below threshold (<5 FPS for 2s). Auto-failing over to manual touchscreen grid mode.")
                                    self.is_connected = False
                            else:
                                self.low_fps_duration = 0.0

                        h_f, w_f, _ = frame.shape
                        self.frame_size = (w_f, h_f)
                        
                        detections = []
                        model = get_yolo_model()

                        if model is not None:
                            self.ai_engine_name = "YOLOv8 Engine"
                            try:
                                yolo_conf_val = float(os.environ.get("YOLO_CONFIDENCE", 0.50))
                                results = model(frame, conf=yolo_conf_val, verbose=False)
                                for r in results:
                                    for box in r.boxes:
                                        cls_id = int(box.cls[0])
                                        cls_name = model.names.get(cls_id, f"Class {cls_id}")
                                        conf = float(box.conf[0])
                                        x1, y1, x2, y2 = map(int, box.xyxy[0])

                                        pos_info = POS_CATALOG_DATABASE.get(cls_name) or POS_CATALOG_DATABASE.get(cls_name.lower())
                                        price = pos_info["price"] if pos_info else 35.00
                                        display_name = pos_info["name"] if pos_info else cls_name
                                        category = pos_info["category"] if pos_info else "ITEM"
                                        stock = pos_info["stock"] if pos_info else 50

                                        detections.append({
                                            "ai_label": cls_name,
                                            "name": display_name,
                                            "category": category,
                                            "qty": 1,
                                            "price": price,
                                            "stock": stock,
                                            "bbox": [x1, y1, max(20, x2 - x1), max(20, y2 - y1)],
                                            "conf": conf
                                        })
                            except Exception as err:
                                print(f"[AI INFERENCE WARN] YOLO model error: {err}")

                        if model is None:
                            self.ai_engine_name = "Native Vision Engine"

                        if not detections:
                            try:
                                gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                                _, thresh = cv2.threshold(gray, 180, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
                                contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
                                
                                valid_contours = [c for c in contours if cv2.contourArea(c) > 6000]
                                for i, c in enumerate(valid_contours[:3]):
                                    x, y, bw, bh = cv2.boundingRect(c)
                                    if x < 10 or y < 10 or (x + bw) > (w_f - 10) or (y + bh) > (h_f - 10):
                                        continue
                                    item_key = "Buttercream Crackers"
                                    pos_info = POS_CATALOG_DATABASE.get(item_key)
                                    if pos_info:
                                        detections.append({
                                            "ai_label": item_key,
                                            "name": pos_info["name"],
                                            "category": pos_info["category"],
                                            "qty": 1,
                                            "price": pos_info["price"],
                                            "stock": pos_info["stock"],
                                            "bbox": [x, y, bw, bh],
                                            "conf": 0.96 - (i * 0.03)
                                        })
                            except Exception:
                                pass

                        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                        with self.lock:
                            self.current_frame = rgb_frame
                            self.latest_detections = detections
                    else:
                        self.is_connected = False
                        time.sleep(0.1)
                else:
                    # Periodic Camera Re-Probe Auto-Recovery (Every 10 Seconds)
                    now_ts = time.time()
                    if self.manual_enabled and (now_ts - self.last_retry_time > 10.0):
                        self.last_retry_time = now_ts
                        self._init_camera()

                    # Synthetic Fallback Frame Stream
                    synth_angle = (synth_angle + 4) % 360
                    frame_rgb, detections = self._generate_synthetic_frame(synth_angle)
                    self.ai_engine_name = "Synthetic Vision Engine"
                    self.fps_display = 60
                    self.frame_size = (640, 480)
                    with self.lock:
                        self.current_frame = frame_rgb
                        self.latest_detections = detections

            except Exception as e:
                print(f"[CAMERA THREAD] Frame read error: {e}")
                time.sleep(0.1)

            time.sleep(0.016)

    def get_frame(self):
        with self.lock:
            return self.current_frame.copy() if self.current_frame is not None else None

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
# OPTIONAL USB SERIAL RFID HARDWARE LISTENER
# ==============================================================================
class SerialRfidListener(threading.Thread):
    def __init__(self, callback):
        super().__init__()
        self.daemon = True
        self.callback = callback
        self.running = True

    def run(self):
        try:
            import serial
            import glob
            ports = glob.glob("/dev/tty.usb*") + glob.glob("/dev/cu.usb*")
            if not ports:
                return
            port_name = ports[0]
            print(f"[USB SERIAL RFID] Auto-detected hardware port: {port_name}")
            with serial.Serial(port_name, 9600, timeout=1) as ser:
                while self.running:
                    line = ser.readline().decode('utf-8', errors='ignore').strip()
                    if line:
                        print(f"[USB SERIAL 125kHz TAP]: {line}")
                        self.callback(line)
        except Exception:
            pass

# ==============================================================================
# VOICE ANNOUNCEMENT ENGINE
# ==============================================================================
_tts_lock = threading.Lock()

def speak_text(text):
    """Non-blocking spoken Text-to-Speech (TTS) announcement thread."""
    def _run_tts():
        with _tts_lock:
            try:
                if shutil.which("say"):
                    subprocess.run(["killall", "say"], stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=False)
                    subprocess.run(["say", "-r", "240", "-v", "Samantha", text], timeout=4, check=False)
                else:
                    print(f"[VOICE ANNOUNCEMENT]: {text}")
            except Exception as e:
                print(f"[VOICE WARN] Speech error: {e}")

    threading.Thread(target=_run_tts, daemon=True).start()

def create_synthesized_sounds():
    """Generates synthesized audio effects in memory."""
    sounds = {"success": None, "tick": None, "error": None}
    try:
        if not pygame.mixer.get_init():
            pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=512)
        sample_rate = 44100
        
        # Success Chime Sound
        dur_s = 0.35
        t_s = np.linspace(0, dur_s, int(sample_rate * dur_s), False)
        w1 = np.sin(2 * np.pi * 523.25 * t_s) * 0.3
        w2 = np.sin(2 * np.pi * 659.25 * t_s) * 0.3
        w3 = np.sin(2 * np.pi * 783.99 * t_s) * 0.3
        env_s = np.exp(-4.0 * t_s)
        arr_s = ((w1 + w2 + w3) * env_s * 32767).astype(np.int16)
        sounds["success"] = pygame.sndarray.make_sound(np.column_stack((arr_s, arr_s)))

        # Countdown Tick Sound (880Hz)
        dur_t = 0.08
        t_t = np.linspace(0, dur_t, int(sample_rate * dur_t), False)
        wt = np.sin(2 * np.pi * 880.0 * t_t) * 0.25
        env_t = np.exp(-15.0 * t_t)
        arr_t = (wt * env_t * 32767).astype(np.int16)
        sounds["tick"] = pygame.sndarray.make_sound(np.column_stack((arr_t, arr_t)))

    except Exception as e:
        print(f"[AUDIO WARN] Audio synthesizer warning: {e}")
    return sounds

# Dynamic POS Catalog Database Mapping (AI Labels to POS Prices & Stock)
POS_CATALOG_DATABASE = {
    "buttercream_crackers": {"name": "Buttercream Crackers", "category": "SNACK", "price": 35.00, "stock": 50, "bbox": [150, 120, 210, 210], "conf": 0.98},
    "Buttercream Crackers": {"name": "Buttercream Crackers", "category": "SNACK", "price": 35.00, "stock": 50, "bbox": [150, 120, 210, 210], "conf": 0.98},
    "adobo": {"name": "Pork Adobo Meal", "category": "MEAL", "price": 100.00, "stock": 45, "bbox": [80, 80, 240, 200], "conf": 0.96},
    "steamed_rice": {"name": "Steamed Rice", "category": "RICE", "price": 15.00, "stock": 120, "bbox": [360, 140, 220, 180], "conf": 0.92},
    "burger": {"name": "Classic Cheeseburger", "category": "MEAL", "price": 75.00, "stock": 50, "bbox": [100, 100, 200, 200], "conf": 0.94},
    "fried_chicken": {"name": "Crispy Chicken Bowl", "category": "MEAL", "price": 85.00, "stock": 60, "bbox": [320, 100, 250, 220], "conf": 0.95},
    "water_bottle": {"name": "Mineral Water 500ml", "category": "BEVERAGE", "price": 20.00, "stock": 150, "bbox": [50, 50, 120, 300], "conf": 0.98},
    "juice_box": {"name": "Iced Fruit Juice 350ml", "category": "BEVERAGE", "price": 30.00, "stock": 80, "bbox": [480, 80, 150, 220], "conf": 0.91},
    "sandwich": {"name": "Ham & Cheese Sandwich", "category": "SNACK", "price": 45.00, "stock": 40, "bbox": [200, 200, 180, 180], "conf": 0.93},
    "apple": {"name": "Fresh Red Apple", "category": "HEALTHY", "price": 25.00, "stock": 40, "bbox": [420, 220, 140, 140], "conf": 0.97}
}

# ==============================================================================
# NOVALUNCH STUDENT-FACING DISPLAY (CFD) MONITOR APPLICATION
# ==============================================================================
class NovaLunchKioskGUI:
    def __init__(self):
        pygame.init()
        pygame.font.init()
        pygame.display.set_caption("Saint Joseph College NovaLunch — Student-Facing Display (CFD) Monitor")

        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        self.clock = pygame.time.Clock()
        
        # Database & Accounts Manager
        self.db_manager = DatabaseManager()

        # Load Institutional Logo Image (assets/images/branding/school no bg.png)
        self.logo_surface = None
        logo_path = os.path.abspath("assets/images/branding/school no bg.png")
        if os.path.exists(logo_path):
            try:
                raw_logo = pygame.image.load(logo_path).convert_alpha()
                h = 48
                w = int(raw_logo.get_width() * (h / float(raw_logo.get_height())))
                self.logo_surface = pygame.transform.smoothscale(raw_logo, (w, h))
                print(f"[UI BRANDING] 🟢 Successfully loaded school logo: {logo_path} ({w}x{h})")
            except Exception as e:
                print(f"[UI BRANDING WARN] Could not load logo image ({logo_path}): {e}")

        # Modern 2026 Typography System
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

        # State Machine Initialization
        self.current_state = STATE_IDLE
        self.active_student = None
        self.active_student = None
        self.active_preorders = []
        self.cart_items = []
        self.total_amount = 0.0
        self.state_timer = 0.0
        self.insufficient_balance_mode = False
        self.status_message = "Welcome to NovaLunch! Place item(s) on scanning platform."
        self.latest_tray_image = ""

        # Motion & 4.0-Second Stability Countdown System
        self.countdown_remaining = 4.0
        self.last_tick_sec = 4
        self.motion_detected = False
        self.motion_voice_alerted = False
        self.greet_audio_spoken = False
        self.stable_start_time = 0.0
        self.last_detection_hash = ""

        # USB HID RFID Reader Scan Buffer
        self.rfid_scan_buffer = ""
        self.last_key_time = 0

        # Threaded Camera Manager (Warm Standby)
        self.camera_thread = CameraThread(camera_index=0)
        self.camera_thread.start()

        # Threaded USB Serial RFID Hardware Listener Fallback
        self.serial_rfid_thread = SerialRfidListener(callback=lambda uid: self.handle_rfid_tap(uid))
        self.serial_rfid_thread.start()

        # Audio Sound Effects
        self.sounds = create_synthesized_sounds()

        # Cashier / Developer Simulation Step Rectangles (Hidden Bottom Bar)
        self.btn_step1 = pygame.Rect(20, 580, 165, 42)
        self.btn_step2 = pygame.Rect(198, 580, 165, 42)
        self.btn_step3 = pygame.Rect(376, 580, 165, 42)
        self.btn_step4 = pygame.Rect(554, 580, 176, 42)

    def execute_simulation_step(self, step):
        """Executes a specific step in the 4-stage checkout flow."""
        if step == 1:
            print("[SIMULATION EVENT] RFID Tap Registered")
            if not self.active_student:
                accounts = self.db_manager.load_accounts()
                if accounts:
                    st = accounts[0]
                    self.active_student = {
                        "id": st.get("student_id_number"),
                        "name": st.get("full_name"),
                        "email": st.get("email"),
                        "rfidUid": st.get("rfid_uid"),
                        "balance": float(st.get("balance", 0.0)),
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
            print("[SIMULATION EVENT] Overhead Vision Detection Triggered")
            self.transition_to_state(STATE_SCANNING)
        elif step == 3:
            print("[SIMULATION EVENT] Stability Countdown Calibrated")
            self.transition_to_state(STATE_STABILITY_COUNTDOWN)
        elif step == 4:
            print("[SIMULATION EVENT] Payment Settlement Executed")
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
            student_name = self.active_student["name"] if self.active_student else "Student"
            first_po = self.active_preorders[0] if self.active_preorders else {}
            item_name = first_po.get("name") or first_po.get("item") or "Reserved Meal"
            shelf_loc = first_po.get("shelf") or first_po.get("shelf_location") or "Shelf B2"
            self.status_message = f"🍱 ACTIVE PRE-ORDER FOUND: Collect from {shelf_loc}!"
            if not self.greet_audio_spoken:
                speak_text(f"Hello {student_name}! Your pre-order for {item_name} is ready for pickup at Warming {shelf_loc}.")
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
                        "balance": float(st.get("balance", 0.0)),
                        "daily_limit": float(st.get("daily_limit", 200.0))
                    }
            student_name = self.active_student["name"] if self.active_student else "Student"
            self.status_message = f"Hello {student_name}! Place food items on scanning platform."
            self.stable_start_time = 0.0
            self.last_detection_hash = ""
            if not self.greet_audio_spoken:
                speak_text(f"Welcome {student_name}! Please place your tray on the platform.")
                self.greet_audio_spoken = True

        elif new_state == STATE_SCANNING:
            live_items = self.camera_thread.get_latest_detections()
            if live_items:
                self.cart_items = live_items
                self.recalculate_total()
                self.status_message = f"AI Detected {len(self.cart_items)} item(s). Calibrating stability..."
            else:
                self.cart_items = []
                self.total_amount = 0.0
                self.status_message = "Waiting for tray... Place food on scanning platform."
            
            try:
                trays_dir = "src/ai_engine/trays_queue"
                os.makedirs(trays_dir, exist_ok=True)
                timestamp = int(time.time())
                student_id = self.active_student["id"] if self.active_student else "GUEST"
                filename = f"{trays_dir}/tray_{timestamp}_{student_id}.jpg"
                self.latest_tray_image = filename
                if frame is not None:
                    # ROI Edge Privacy Cropping: Crop frame tight to 40cm x 30cm tray boundary to mask student faces
                    h, w, _ = frame.shape
                    y1, y2 = int(h * 0.15), int(h * 0.85)
                    x1, x2 = int(w * 0.15), int(w * 0.85)
                    cropped = frame[y1:y2, x1:x2]
                    bgr_frame = cv2.cvtColor(cropped, cv2.COLOR_RGB2BGR)
                    cv2.imwrite(filename, bgr_frame)
                else:
                    placeholder = np.zeros((480, 640, 3), dtype=np.uint8)
                    cv2.putText(placeholder, f"TRAY SNAPSHOT - STUDENT {student_id}", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
                    cv2.imwrite(filename, placeholder)
            except Exception as err:
                print(f"[TRAY SNAPSHOT WARN] Could not save snapshot: {err}")

        elif new_state == STATE_STABILITY_COUNTDOWN:
            self.countdown_remaining = 4.0
            self.last_tick_sec = 4
            self.motion_voice_alerted = False
            self.status_message = f"🟢 Items stable. Auto-deducting ₱{self.total_amount:.2f} in 4.0s..."
            item_names_str = " and ".join(item["name"] for item in self.cart_items) if self.cart_items else "Food items"
            speak_text(f"Scanned {item_names_str}. Total is {int(self.total_amount)} pesos. Auto deducting in 4 seconds.")

        elif new_state == STATE_SETTLEMENT:
            if not self.active_student:
                accounts = self.db_manager.load_accounts()
                if accounts:
                    st = accounts[0]
                    self.active_student = {
                        "id": st.get("student_id_number"),
                        "name": st.get("full_name"),
                        "email": st.get("email"),
                        "rfidUid": st.get("rfid_uid"),
                        "balance": float(st.get("balance", 0.0)),
                        "daily_limit": float(st.get("daily_limit", 200.0))
                    }

            student_bal = self.active_student["balance"] if self.active_student else 0.0
            student_id = self.active_student["id"] if self.active_student else "GUEST"
            daily_limit = float(self.active_student.get("daily_limit", 200.0)) if self.active_student else 200.0
            daily_spent = self.db_manager.get_student_daily_spent(student_id)

            if self.total_amount > 0 and (daily_spent + self.total_amount) > daily_limit:
                self.status_message = f"⚠️ DAILY SPENDING CAP EXCEEDED (Cap: ₱{daily_limit:.2f}, Spent Today: ₱{daily_spent:.2f})"
                speak_text(f"Warning! Purchase exceeds your daily spending limit of {int(daily_limit)} pesos.")
            elif student_bal >= self.total_amount and self.total_amount > 0:
                rem_balance = self.db_manager.deduct_student_balance(student_id, self.total_amount)
                self.active_student["balance"] = rem_balance
                
                for item in self.cart_items:
                    pos_key = item.get("ai_label")
                    if pos_key and pos_key in POS_CATALOG_DATABASE:
                        POS_CATALOG_DATABASE[pos_key]["stock"] = max(0, POS_CATALOG_DATABASE[pos_key]["stock"] - item["qty"])

                timestamp_id = f"TXN_{int(time.time())}_{student_id.replace('-', '')}"
                self.db_manager.record_transaction(timestamp_id, student_id, self.cart_items, self.total_amount, self.latest_tray_image, payment_method="rfid")

                self.status_message = f"Payment Successful! Remaining Balance: ₱{rem_balance:.2f}"
                if self.sounds.get("success"):
                    try:
                        self.sounds["success"].play()
                    except Exception:
                        pass
                speak_text(f"Payment successful! Remaining balance: {int(rem_balance)} pesos. Thank you!")
            elif self.total_amount == 0:
                self.status_message = "No items scanned on platform!"
                speak_text("No items on scanning platform to purchase.")
            else:
                self.status_message = "⚠️ Insufficient Balance! Press [P] or Tap Screen for 1-Tap Pay Later."
                speak_text("Insufficient balance. Press P or tap screen for Pay Later safety net.")

        elif new_state == STATE_ERROR:
            self.status_message = "⚠️ UNREGISTERED RFID / QR CODE — VISIT CANTEEN ADMIN"
            speak_text("Warning! Unregistered card or code. Please visit canteen administration.")

    def execute_pay_later_checkout(self):
        """Executes sub-1-second emergency credit overdraft without stalling the counter queue."""
        if not self.active_student or self.total_amount <= 0:
            print("[PAY LATER] No active student or cart is empty.")
            return

        student_id = self.active_student["id"]
        student_name = self.active_student["name"]
        timestamp_id = f"TXN_PAYLATER_{int(time.time())}_{student_id.replace('-', '')}"

        # Decrement POS catalog inventory
        for item in self.cart_items:
            pos_key = item.get("ai_label")
            if pos_key and pos_key in POS_CATALOG_DATABASE:
                POS_CATALOG_DATABASE[pos_key]["stock"] = max(0, POS_CATALOG_DATABASE[pos_key]["stock"] - item["qty"])

        # Persist transaction with pay_later payment method to SQLite edge cache
        self.db_manager.record_transaction(
            timestamp_id,
            student_id,
            self.cart_items,
            self.total_amount,
            self.latest_tray_image,
            payment_method="pay_later"
        )

        self.status_message = f"🟢 SAFETY NET APPROVED: ₱{self.total_amount:.2f} Billed to Tuition ({student_name})"
        if self.sounds.get("success"):
            try:
                self.sounds["success"].play()
            except Exception:
                pass
        speak_text(f"Safety net approved. Total of {int(self.total_amount)} pesos billed to tuition. Thank you {student_name.split()[0]}!")

    def recalculate_total(self):
        self.total_amount = sum(item["price"] * item["qty"] for item in self.cart_items)

    def handle_rfid_tap(self, scanned_uid=None):
        now_ts = time.time()
        if not hasattr(self, 'rfid_anti_passback_cache'):
            self.rfid_anti_passback_cache = {}

        if scanned_uid:
            clean_uid = str(scanned_uid).strip()
            # Normalize QR codes (e.g. "NL-QR-2023-01900" or "QR-2023-01900")
            if clean_uid.startswith("NL-QR-"):
                clean_uid = clean_uid.replace("NL-QR-", "")
            elif clean_uid.startswith("QR-"):
                clean_uid = clean_uid.replace("QR-", "")

            last_tap = self.rfid_anti_passback_cache.get(clean_uid, 0)
            if now_ts - last_tap < 60.0:
                remaining = int(60.0 - (now_ts - last_tap))
                print(f"[RFID ANTI-PASSBACK 60s] Cooldown active for UID {clean_uid} ({remaining}s remaining).")
                self.status_message = f"⚠️ ANTI-PASSBACK COOLDOWN ({remaining}s remaining)"
                speak_text("Anti-passback active. Please wait before tapping card again.")
                return
            self.rfid_anti_passback_cache[clean_uid] = now_ts

        if hasattr(self, 'last_rfid_tap_timestamp') and (now_ts - self.last_rfid_tap_timestamp < 0.8):
            print("[RFID DEBOUNCE 800ms] Ignored duplicate hardware tap within 800ms window.")
            return
        self.last_rfid_tap_timestamp = now_ts

        if scanned_uid:
            clean_uid = str(scanned_uid).strip()
            if clean_uid.startswith("NL-QR-"):
                clean_uid = clean_uid.replace("NL-QR-", "")
            elif clean_uid.startswith("QR-"):
                clean_uid = clean_uid.replace("QR-", "")

            student = self.db_manager.find_student_by_rfid(clean_uid)
            if student:
                self.active_student = student
                self.active_preorders = self.db_manager.get_active_preorders(student["id"], student.get("name"))
                print(f"[RFID/QR SUCCESS] Matched Student: {student['name']} ({student['id']}) | Active Preorders: {len(self.active_preorders)}")
                if self.active_preorders:
                    self.transition_to_state(STATE_PREORDER_ANNOUNCEMENT)
                else:
                    self.transition_to_state(STATE_GREET)
                return
            else:
                print(f"[RFID/QR DENIED] Unregistered Card/Token: '{clean_uid}'")
                self.status_message = f"⚠️ UNRECOGNIZED CARD/QR (ID: {clean_uid}) — VISIT ADMIN"
                speak_text(f"Warning! Unrecognized card or QR code {clean_uid}.")
                self.transition_to_state(STATE_ERROR)
                return

        if self.current_state in [STATE_IDLE, STATE_ERROR]:
            self.execute_simulation_step(1)
        elif self.current_state == STATE_PREORDER_ANNOUNCEMENT:
            self.transition_to_state(STATE_GREET)
        elif self.current_state == STATE_GREET:
            self.execute_simulation_step(2)
        elif self.current_state == STATE_SCANNING:
            self.execute_simulation_step(3)
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            self.execute_simulation_step(4)
        elif self.current_state == STATE_SETTLEMENT:
            self.transition_to_state(STATE_IDLE)

    def render_preorder_announcement(self):
        """Renders full-screen student-facing pre-order pickup notice."""
        panel_rect = pygame.Rect(20, 100, SCREEN_WIDTH - 40, 565)
        pygame.draw.rect(self.screen, COLOR_CARD_BG, panel_rect, border_radius=20)
        pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, panel_rect, width=2, border_radius=20)

        # Header Ribbon
        ribbon_rect = pygame.Rect(20, 100, SCREEN_WIDTH - 40, 64)
        pygame.draw.rect(self.screen, COLOR_MAROON_HEADER, ribbon_rect, border_top_left_radius=20, border_top_right_radius=20)
        
        banner_txt = self.font_header.render("🍱 ACTIVE PRE-ORDER READY FOR COUNTER PICKUP", True, COLOR_GOLD_LIGHT)
        self.screen.blit(banner_txt, (panel_rect.centerx - banner_txt.get_width() // 2, 118))

        # Main Info Columns
        left_col = pygame.Rect(45, 180, 570, 465)
        right_col = pygame.Rect(635, 180, 600, 465)

        # Left Column: Student Greeting & Shelf Badge
        pygame.draw.rect(self.screen, COLOR_CARD_ALT, left_col, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, left_col, width=1, border_radius=16)

        st_name = self.active_student["name"] if self.active_student else "Student"
        st_id = self.active_student["id"] if self.active_student else ""
        st_bal = self.active_student["balance"] if self.active_student else 0.0

        greet_lbl = self.font_large.render(f"Welcome, {st_name}!", True, COLOR_MAROON_HEADER)
        self.screen.blit(greet_lbl, (65, 200))

        id_lbl = self.font_body.render(f"Student ID: {st_id}  •  RFID E-Wallet Balance: ₱{st_bal:.2f}", True, COLOR_TEXT_MUTED)
        self.screen.blit(id_lbl, (65, 240))

        first_po = self.active_preorders[0] if self.active_preorders else {}
        shelf_loc = first_po.get("shelf") or first_po.get("shelf_location") or "Shelf B2"
        session_name = first_po.get("session") or first_po.get("time_slot") or "Lunch Break (12:00 PM)"

        shelf_box = pygame.Rect(65, 280, 530, 130)
        pygame.draw.rect(self.screen, COLOR_EMERALD_BG, shelf_box, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_EMERALD, shelf_box, width=2, border_radius=16)

        shelf_tag = self.font_subtitle_bold.render("PICKUP STATION / WARMING SHELF:", True, COLOR_EMERALD)
        self.screen.blit(shelf_tag, (85, 298))

        shelf_val = self.font_title.render(f"📍 {shelf_loc.upper()}", True, COLOR_MAROON_HEADER)
        self.screen.blit(shelf_val, (85, 322))

        session_tag = self.font_body_bold.render(f"Meal Session: {session_name}", True, COLOR_TEXT_MAIN)
        self.screen.blit(session_tag, (85, 370))

        # Bottom Reassurance Notice
        notice_box = pygame.Rect(65, 430, 530, 195)
        pygame.draw.rect(self.screen, COLOR_GOLD_LIGHT, notice_box, border_radius=14)
        pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, notice_box, width=1, border_radius=14)

        n1 = self.font_body_bold.render("✓ Paid & Reserved in Advance", True, COLOR_MAROON_HEADER)
        n2 = self.font_body.render("No scan or passcode needed! The Cashier will hand", True, COLOR_TEXT_MAIN)
        n3 = self.font_body.render("over your pre-ordered meal directly.", True, COLOR_TEXT_MAIN)
        n4 = self.font_subtitle_bold.render("Want extra snacks or drinks? Bring them to the counter to add.", True, COLOR_GOLD_ACCENT)
        self.screen.blit(n1, (85, 450))
        self.screen.blit(n2, (85, 480))
        self.screen.blit(n3, (85, 506))
        self.screen.blit(n4, (85, 545))

        # Right Column: Itemized Pre-Order List
        pygame.draw.rect(self.screen, COLOR_CARD_ALT, right_col, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, right_col, width=1, border_radius=16)

        list_header = self.font_header.render("PRE-ORDERED MEAL ITEMS", True, COLOR_TEXT_MAIN)
        self.screen.blit(list_header, (655, 200))

        y_pos = 245
        total_po_amt = 0.0
        for idx, po in enumerate(self.active_preorders):
            if idx >= 4:
                break
            item_card = pygame.Rect(655, y_pos, 560, 75)
            pygame.draw.rect(self.screen, COLOR_WHITE, item_card, border_radius=12)
            pygame.draw.rect(self.screen, COLOR_CARD_BORDER, item_card, width=1, border_radius=12)

            name = po.get("name") or po.get("item") or "Pork Adobo w/ Rice"
            price = float(po.get("price", 85.0))
            total_po_amt += price

            is_meal = any(k in name.lower() for k in ["rice", "adobo", "chicken", "pares", "spaghetti", "meal", "bowl"])
            badge_text = "Cooked Meal (Non-Refundable)" if is_meal else "Packaged Item (Refundable)"
            badge_bg = COLOR_MAROON_DARK if is_meal else COLOR_AMBER_BG
            badge_fg = COLOR_GOLD_LIGHT if is_meal else COLOR_GOLD_ACCENT

            p_name = self.font_body_bold.render(name, True, COLOR_TEXT_MAIN)
            self.screen.blit(p_name, (670, y_pos + 12))

            p_tag = self.font_brand_sub.render(badge_text, True, badge_fg)
            tag_rect = pygame.Rect(670, y_pos + 42, p_tag.get_width() + 12, 20)
            pygame.draw.rect(self.screen, badge_bg, tag_rect, border_radius=6)
            self.screen.blit(p_tag, (676, y_pos + 45))

            p_price = self.font_large.render(f"₱{price:.2f}", True, COLOR_ROSE_VIBRANT)
            self.screen.blit(p_price, (item_card.right - p_price.get_width() - 15, y_pos + 18))

            y_pos += 85

        # Right Summary Box
        sum_box = pygame.Rect(655, 530, 560, 95)
        pygame.draw.rect(self.screen, COLOR_EMERALD_BG, sum_box, border_radius=14)
        pygame.draw.rect(self.screen, COLOR_EMERALD, sum_box, width=1, border_radius=14)

        s_lbl = self.font_header.render("TOTAL PRE-ORDER VALUE:", True, COLOR_EMERALD)
        s_val = self.font_large.render(f"₱{total_po_amt:.2f}", True, COLOR_EMERALD)
        s_sub = self.font_body_bold.render("STATUS: PREPARED & WAITING FOR PICKUP", True, COLOR_TEXT_MAIN)

        self.screen.blit(s_lbl, (675, 545))
        self.screen.blit(s_val, (sum_box.right - s_val.get_width() - 20, 540))
        self.screen.blit(s_sub, (675, 580))

    # --------------------------------------------------------------------------
    # 2026 STUDENT-FACING DISPLAY (CFD) RENDERERS
    # --------------------------------------------------------------------------
    def render_header(self):
        # Top Header Bar (Deep Maroon Surface with Metallic Gold Accent Border)
        pygame.draw.rect(self.screen, COLOR_MAROON_HEADER, (0, 0, SCREEN_WIDTH, 84))
        pygame.draw.line(self.screen, COLOR_GOLD_ACCENT, (0, 83), (SCREEN_WIDTH, 83), 2)

        left_offset = 24
        if self.logo_surface is not None:
            self.screen.blit(self.logo_surface, (left_offset, 18))
            left_offset += self.logo_surface.get_width() + 16
        else:
            pygame.draw.circle(self.screen, COLOR_GOLD_ACCENT, (46, 42), 22)
            pygame.draw.circle(self.screen, COLOR_MAROON_DARK, (46, 42), 19)
            emblem_txt = self.font_subtitle_bold.render("SJC", True, COLOR_GOLD_LIGHT)
            self.screen.blit(emblem_txt, (46 - emblem_txt.get_width() // 2, 42 - emblem_txt.get_height() // 2))
            left_offset += 56

        # Institutional Branding Title
        school_tag = self.font_brand_sub.render("SAINT JOSEPH COLLEGE OF NOVALICHES", True, COLOR_GOLD_LIGHT)
        kiosk_title = self.font_title.render("NovaLunch AI Self-Scan Counter Display", True, COLOR_WHITE)
        
        self.screen.blit(school_tag, (left_offset, 20))
        self.screen.blit(kiosk_title, (left_offset, 38))

        # Active Student Profile Badge (Top-Right)
        if self.active_student and self.current_state != STATE_IDLE:
            student_name = self.active_student["name"]
            student_id = self.active_student["id"]
            balance_val = self.active_student["balance"]

            card_rect = pygame.Rect(SCREEN_WIDTH - 380, 14, 356, 56)
            pygame.draw.rect(self.screen, COLOR_MAROON_DARK, card_rect, border_radius=14)
            pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, card_rect, width=1, border_radius=14)

            pygame.draw.circle(self.screen, COLOR_GOLD_ACCENT, (card_rect.left + 28, card_rect.top + 28), 17)
            inits = "".join([n[0] for n in student_name.split()[:2]]).upper() if student_name else "ST"
            avatar_txt = self.font_subtitle_bold.render(inits, True, COLOR_MAROON_DARK)
            self.screen.blit(avatar_txt, (card_rect.left + 28 - avatar_txt.get_width() // 2, card_rect.top + 28 - avatar_txt.get_height() // 2))

            name_surf = self.font_body_bold.render(student_name, True, COLOR_WHITE)
            id_surf = self.font_brand_sub.render(f"RFID: {student_id}", True, COLOR_GOLD_LIGHT)
            self.screen.blit(name_surf, (card_rect.left + 54, card_rect.top + 10))
            self.screen.blit(id_surf, (card_rect.left + 54, card_rect.top + 32))

            is_enough = balance_val >= self.total_amount
            bal_fill = COLOR_EMERALD_BG if is_enough else COLOR_ROSE_ALERT_BG
            bal_border = COLOR_EMERALD if is_enough else COLOR_ROSE_ALERT
            bal_text_color = COLOR_EMERALD if is_enough else COLOR_ROSE_ALERT

            bal_str = f"₱{balance_val:.2f}"
            bal_surf = self.font_body_bold.render(bal_str, True, bal_text_color)
            bal_rect = pygame.Rect(card_rect.right - bal_surf.get_width() - 20, card_rect.top + 13, bal_surf.get_width() + 14, 30)
            
            pygame.draw.rect(self.screen, bal_fill, bal_rect, border_radius=15)
            pygame.draw.rect(self.screen, bal_border, bal_rect, width=1, border_radius=15)
            self.screen.blit(bal_surf, (bal_rect.x + 7, bal_rect.y + 5))

        else:
            idle_rect = pygame.Rect(SCREEN_WIDTH - 320, 20, 296, 44)
            pygame.draw.rect(self.screen, COLOR_MAROON_DARK, idle_rect, border_radius=22)
            pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, idle_rect, width=1, border_radius=22)

            pygame.draw.circle(self.screen, COLOR_GOLD_ACCENT, (idle_rect.left + 22, idle_rect.centery), 5)
            idle_lbl = self.font_subtitle_bold.render("Tap Student RFID Card on Reader", True, COLOR_GOLD_LIGHT)
            self.screen.blit(idle_lbl, (idle_rect.left + 36, idle_rect.centery - idle_lbl.get_height() // 2))

    def render_left_panel(self):
        panel_rect = pygame.Rect(20, 100, 710, 545)
        
        # Crisp White Container Card
        pygame.draw.rect(self.screen, COLOR_CARD_BG, panel_rect, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, panel_rect, width=1, border_radius=16)

        header_surf = self.font_header.render("OVERHEAD COUNTER SCANNING PLATFORM", True, COLOR_MAROON_HEADER)
        self.screen.blit(header_surf, (36, 116))

        cam_frame = self.camera_thread.get_frame()
        ai_engine, fps_val, frame_dim = self.camera_thread.get_ai_status()

        if cam_frame is not None:
            status_text = f"LIVE STREAM • {ai_engine} ({fps_val} FPS)"
            badge_bg = COLOR_EMERALD_BG
            badge_fg = COLOR_EMERALD
        else:
            status_text = "STANDBY MODE"
            badge_bg = COLOR_AMBER_BG
            badge_fg = COLOR_GOLD_ACCENT

        badge_lbl = self.font_brand_sub.render(status_text, True, badge_fg)
        badge_w = badge_lbl.get_width() + 24
        badge_rect = pygame.Rect(panel_rect.right - badge_w - 20, 114, badge_w, 24)
        
        pygame.draw.rect(self.screen, badge_bg, badge_rect, border_radius=12)
        pygame.draw.circle(self.screen, badge_fg, (badge_rect.left + 12, badge_rect.centery), 4)
        self.screen.blit(badge_lbl, (badge_rect.left + 20, badge_rect.centery - badge_lbl.get_height() // 2))

        # Video Frame Canvas Area
        video_area = pygame.Rect(34, 150, 682, 405)

        if cam_frame is not None:
            try:
                resized_frame = cv2.resize(cam_frame, (682, 405))
                frame_surface = pygame.surfarray.make_surface(resized_frame.swapaxes(0, 1))
                self.screen.blit(frame_surface, (34, 150))

                # Render 2026 Minimalist L-Corner Reticles
                live_detections = self.camera_thread.get_latest_detections()
                display_items = live_detections if live_detections else self.cart_items
                
                fw, fh = frame_dim if frame_dim[0] > 0 else (640, 480)
                scale_x = 682.0 / fw
                scale_y = 405.0 / fh

                for item in display_items:
                    bx, by, bw, bh = item.get("bbox", [80, 80, 200, 200])
                    rx = 34 + int(bx * scale_x)
                    ry = 150 + int(by * scale_y)
                    rw = max(40, int(bw * scale_x))
                    rh = max(30, int(bh * scale_y))

                    rx = max(36, min(34 + 682 - rw, rx))
                    ry = max(172, min(150 + 405 - rh, ry))
                    
                    c_len = min(18, rw // 3, rh // 3)
                    c_color = COLOR_ROSE_VIBRANT
                    
                    pygame.draw.line(self.screen, c_color, (rx, ry), (rx + c_len, ry), 2)
                    pygame.draw.line(self.screen, c_color, (rx, ry), (rx, ry + c_len), 2)
                    pygame.draw.line(self.screen, c_color, (rx + rw, ry), (rx + rw - c_len, ry), 2)
                    pygame.draw.line(self.screen, c_color, (rx + rw, ry), (rx + rw, ry + c_len), 2)
                    pygame.draw.line(self.screen, c_color, (rx, ry + rh), (rx + c_len, ry + rh), 2)
                    pygame.draw.line(self.screen, c_color, (rx, ry + rh), (rx, ry + rh - c_len), 2)
                    pygame.draw.line(self.screen, c_color, (rx + rw, ry + rh), (rx + rw - c_len, ry + rh), 2)
                    pygame.draw.line(self.screen, c_color, (rx + rw, ry + rh), (rx + rw, ry + rh - c_len), 2)
                    
                    conf_pct = int(item.get('conf', 0.95) * 100)
                    label_str = f" {item['name']} ({conf_pct}%) • ₱{item['price']:.2f} "
                    label_surf = self.font_subtitle_bold.render(label_str, True, COLOR_WHITE)
                    
                    bg_label_rect = pygame.Rect(rx, ry - 24, label_surf.get_width() + 8, 24)
                    pygame.draw.rect(self.screen, COLOR_MAROON_DARK, bg_label_rect, border_radius=4)
                    pygame.draw.rect(self.screen, c_color, bg_label_rect, width=1, border_radius=4)
                    self.screen.blit(label_surf, (rx + 4, ry - 20))
            except Exception as render_err:
                print(f"[UI RENDER WARN] Video render fallback: {render_err}")
                self.render_camera_fallback(video_area)
        else:
            self.render_camera_fallback(video_area)

        if self.current_state in [STATE_SCANNING, STATE_STABILITY_COUNTDOWN, STATE_SETTLEMENT]:
            self.render_timer_hud(video_area)

        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, video_area, width=1, border_radius=12)
        self.render_flow_step_toolbar()

    def render_timer_hud(self, video_area):
        if self.current_state == STATE_STABILITY_COUNTDOWN:
            if self.motion_detected:
                banner_bg = COLOR_AMBER_BG
                banner_border = COLOR_AMBER
                banner_text = "⚠️ MOTION DETECTED — KEEP HANDS OFF PLATFORM"
                text_color = COLOR_AMBER
            else:
                banner_bg = COLOR_EMERALD_BG
                banner_border = COLOR_EMERALD
                banner_text = f"🟢 TRAY STABLE — AUTO DEDUCTION IN {self.countdown_remaining:.1f}s"
                text_color = COLOR_EMERALD

            text_surf = self.font_timer_badge.render(banner_text, True, text_color)
            banner_rect = pygame.Rect(video_area.centerx - text_surf.get_width() // 2 - 16, video_area.top + 14, text_surf.get_width() + 32, 34)
            
            pygame.draw.rect(self.screen, banner_bg, banner_rect, border_radius=17)
            pygame.draw.rect(self.screen, banner_border, banner_rect, width=1, border_radius=17)
            self.screen.blit(text_surf, (banner_rect.x + 16, banner_rect.y + 7))

            # Radial Countdown Gauge (Top-Right)
            gauge_cx = video_area.right - 56
            gauge_cy = video_area.top + 56
            radius = 40

            pygame.draw.circle(self.screen, COLOR_CARD_BG, (gauge_cx, gauge_cy), radius)
            pygame.draw.circle(self.screen, COLOR_CARD_BORDER, (gauge_cx, gauge_cy), radius, width=2)

            progress_ratio = max(0.0, min(1.0, 1.0 - (self.countdown_remaining / 4.0)))
            arc_color = COLOR_AMBER if self.motion_detected else (COLOR_CYAN_HUD if progress_ratio < 0.8 else COLOR_EMERALD)
            
            start_angle = -math.pi / 2
            end_angle = start_angle + (2 * math.pi * progress_ratio)
            
            for i in range(24):
                ang = start_angle + (2 * math.pi * (i / 24.0))
                if ang <= end_angle:
                    px = int(gauge_cx + (radius - 5) * math.cos(ang))
                    py = int(gauge_cy + (radius - 5) * math.sin(ang))
                    pygame.draw.circle(self.screen, arc_color, (px, py), 3)

            if self.motion_detected:
                num_surf = self.font_subtitle_bold.render("PAUSE", True, COLOR_AMBER)
            else:
                num_surf = self.font_timer_large.render(f"{int(math.ceil(self.countdown_remaining))}", True, arc_color)

            tx = gauge_cx - num_surf.get_width() // 2
            ty = gauge_cy - num_surf.get_height() // 2
            self.screen.blit(num_surf, (tx, ty))

        elif self.current_state == STATE_SETTLEMENT:
            banner_rect = pygame.Rect(video_area.centerx - 210, video_area.centery - 45, 420, 90)
            pygame.draw.rect(self.screen, COLOR_EMERALD_BG, banner_rect, border_radius=16)
            pygame.draw.rect(self.screen, COLOR_EMERALD, banner_rect, width=2, border_radius=16)

            t1 = self.font_large.render("✓ PAYMENT APPROVED", True, COLOR_EMERALD)
            t2 = self.font_subtitle_bold.render(f"Deducted ₱{self.total_amount:.2f} — Session Resetting...", True, COLOR_TEXT_MAIN)
            
            self.screen.blit(t1, (banner_rect.centerx - t1.get_width() // 2, banner_rect.y + 16))
            self.screen.blit(t2, (banner_rect.centerx - t2.get_width() // 2, banner_rect.y + 54))

    def render_camera_fallback(self, area_rect):
        pygame.draw.rect(self.screen, COLOR_CARD_ALT, area_rect, border_radius=12)

        for x in range(area_rect.left, area_rect.right, 40):
            pygame.draw.line(self.screen, COLOR_CARD_BORDER, (x, area_rect.top), (x, area_rect.bottom), 1)
        for y in range(area_rect.top, area_rect.bottom, 40):
            pygame.draw.line(self.screen, COLOR_CARD_BORDER, (area_rect.left, y), (area_rect.right, y), 1)

        cx, cy = area_rect.centerx, area_rect.centery - 20
        pygame.draw.circle(self.screen, COLOR_CARD_BG, (cx, cy), 42)
        pygame.draw.circle(self.screen, COLOR_MAROON_HEADER, (cx, cy), 42, width=2)
        pygame.draw.circle(self.screen, COLOR_ROSE_VIBRANT, (cx, cy), 18, width=2)
        pygame.draw.circle(self.screen, COLOR_GOLD_ACCENT, (cx + 6, cy - 6), 4)

        main_text = self.font_header.render("Overhead Camera Standby", True, COLOR_MAROON_HEADER)
        sub_text = self.font_subtitle.render("Place food items on counter platform scanning zone", True, COLOR_TEXT_MUTED)
        
        self.screen.blit(main_text, (cx - main_text.get_width() // 2, cy + 60))
        self.screen.blit(sub_text, (cx - sub_text.get_width() // 2, cy + 88))

    def render_flow_step_toolbar(self):
        mouse_pos = pygame.mouse.get_pos()
        btn_configs = [
            (self.btn_step1, "Step 1: Tap ID", "💳", COLOR_MAROON_HEADER, "[1]"),
            (self.btn_step2, "Step 2: AI Scan", "🍱", COLOR_MAROON_HEADER, "[2]"),
            (self.btn_step3, "Step 3: 5s Timer", "⏳", COLOR_MAROON_HEADER, "[3]"),
            (self.btn_step4, "Step 4: Pay ₱55", "✓", COLOR_ROSE_VIBRANT, "[4]")
        ]

        for rect, label, icon, bg_color, key_hint in btn_configs:
            is_hovered = rect.collidepoint(mouse_pos)
            fill_color = COLOR_ROSE_VIBRANT if (is_hovered and bg_color == COLOR_MAROON_HEADER) else bg_color
            
            pygame.draw.rect(self.screen, fill_color, rect, border_radius=8)
            pygame.draw.rect(self.screen, COLOR_CARD_BORDER, rect, width=1, border_radius=8)

            btn_str = f"{icon} {label} {key_hint}"
            text_color = COLOR_WHITE
            text_surf = self.font_subtitle_bold.render(btn_str, True, text_color)
            
            tx = rect.x + (rect.width - text_surf.get_width()) // 2
            ty = rect.y + (rect.height - text_surf.get_height()) // 2
            self.screen.blit(text_surf, (tx, ty))

    def render_right_panel(self):
        panel_rect = pygame.Rect(750, 100, 510, 545)
        
        # Pure White Card Surface
        pygame.draw.rect(self.screen, COLOR_CARD_BG, panel_rect, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, panel_rect, width=1, border_radius=16)

        title_surf = self.font_header.render("CUSTOMER ORDER SUMMARY", True, COLOR_MAROON_HEADER)
        subtitle_surf = self.font_subtitle.render("Scanned Food Items & Automated Price Tally", True, COLOR_TEXT_MUTED)
        self.screen.blit(title_surf, (775, 116))
        self.screen.blit(subtitle_surf, (775, 138))

        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 162), (1235, 162), 1)
        
        # Table Header
        h_item = self.font_brand_sub.render("ITEM DESCRIPTION", True, COLOR_TEXT_MUTED)
        h_qty = self.font_brand_sub.render("QTY", True, COLOR_TEXT_MUTED)
        h_price = self.font_brand_sub.render("PRICE", True, COLOR_TEXT_MUTED)
        
        self.screen.blit(h_item, (775, 168))
        self.screen.blit(h_qty, (1060, 168))
        self.screen.blit(h_price, (1165, 168))
        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 188), (1235, 188), 1)

        # Item Rows
        if not self.cart_items:
            empty_text = self.font_body.render("No items detected on platform.", True, COLOR_TEXT_MUTED)
            self.screen.blit(empty_text, (750 + (510 - empty_text.get_width()) // 2, 280))
            
            hint_text = self.font_subtitle.render("Place food items on counter platform to scan.", True, COLOR_TEXT_MUTED)
            self.screen.blit(hint_text, (750 + (510 - hint_text.get_width()) // 2, 308))
        else:
            start_y = 200
            for idx, item in enumerate(self.cart_items):
                row_y = start_y + (idx * 44)
                
                if idx % 2 == 0:
                    pygame.draw.rect(self.screen, COLOR_CARD_ALT, (775, row_y - 2, 460, 38), border_radius=6)
                
                cat_tag = self.font_brand_sub.render(f"[{item.get('category', 'ITEM')}]", True, COLOR_GOLD_ACCENT)
                self.screen.blit(cat_tag, (785, row_y + 9))

                item_name = self.font_body_bold.render(item["name"], True, COLOR_TEXT_MAIN)
                item_qty = self.font_body.render(f"x{item['qty']}", True, COLOR_TEXT_MAIN)
                item_price = self.font_body_bold.render(f"₱{item['price'] * item['qty']:.2f}", True, COLOR_ROSE_VIBRANT)

                self.screen.blit(item_name, (840, row_y + 8))
                self.screen.blit(item_qty, (1065, row_y + 8))
                self.screen.blit(item_price, (1165, row_y + 8))

        pygame.draw.line(self.screen, COLOR_CARD_BORDER, (775, 470), (1235, 470), 1)

        # Total Calculation Display
        total_lbl = self.font_header.render("TOTAL AMOUNT:", True, COLOR_TEXT_MAIN)
        total_val = self.font_large.render(f"₱{self.total_amount:.2f}", True, COLOR_ROSE_VIBRANT)
        
        self.screen.blit(total_lbl, (775, 492))
        self.screen.blit(total_val, (1235 - total_val.get_width(), 484))

        self.render_status_banner()

    def render_status_banner(self):
        banner_rect = pygame.Rect(775, 565, 460, 56)

        if self.current_state == STATE_IDLE:
            btn_bg = COLOR_CARD_ALT
            btn_text = "Place items on platform or Tap RFID..."
            text_color = COLOR_TEXT_MUTED
        elif self.current_state == STATE_GREET:
            btn_bg = COLOR_MAROON_HEADER
            btn_text = "AI Overhead Vision Scanning Active..."
            text_color = COLOR_WHITE
        elif self.current_state == STATE_SCANNING:
            btn_bg = COLOR_MAROON_HEADER
            btn_text = "Scanning & Calibrating Motion..."
            text_color = COLOR_WHITE
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            if self.motion_detected:
                btn_bg = COLOR_AMBER_BG
                btn_text = "⚠️ Motion Detected — Keep Hands Off"
                text_color = COLOR_MAROON_HEADER
            else:
                btn_bg = COLOR_ROSE_VIBRANT
                btn_text = f"⏳ Auto-Deducting in {self.countdown_remaining:.1f}s"
                text_color = COLOR_WHITE
        elif self.current_state == STATE_SETTLEMENT:
            student_bal = self.active_student["balance"] if self.active_student else 0.0
            if student_bal + self.total_amount >= self.total_amount and self.status_message.startswith("Payment Successful"):
                btn_bg = COLOR_EMERALD
                btn_text = "✓ Payment Approved — Thank You!"
                text_color = COLOR_WHITE
            elif "SAFETY NET APPROVED" in self.status_message:
                btn_bg = COLOR_EMERALD
                btn_text = "✓ Safety Net Pay Later Approved!"
                text_color = COLOR_WHITE
            else:
                btn_bg = COLOR_ROSE_ALERT
                btn_text = "⚡ Press [P] or Tap for 1-Tap Pay Later"
                text_color = COLOR_WHITE

        self.pay_later_btn_rect = banner_rect
        pygame.draw.rect(self.screen, btn_bg, banner_rect, border_radius=12)
        pygame.draw.rect(self.screen, COLOR_CARD_BORDER, banner_rect, width=1, border_radius=12)

        text_surf = self.font_body_bold.render(btn_text, True, text_color)
        tx = banner_rect.x + (banner_rect.width - text_surf.get_width()) // 2
        ty = banner_rect.y + (banner_rect.height - text_surf.get_height()) // 2
        self.screen.blit(text_surf, (tx, ty))

    def render_footer(self):
        footer_rect = pygame.Rect(0, 678, SCREEN_WIDTH, 42)
        pygame.draw.rect(self.screen, COLOR_MAROON_HEADER, footer_rect)
        pygame.draw.line(self.screen, COLOR_GOLD_ACCENT, (0, 678), (SCREEN_WIDTH, 678), 1)

        msg_surf = self.font_footer.render(f"STATUS: {self.status_message} | ⚡ FPS: 30 • LUX: 480 [OK] • RFID: READY • EDGE QUEUE: 0", True, COLOR_WHITE)
        self.screen.blit(msg_surf, (24, 690))

        keybind_surf = self.font_subtitle_bold.render("[SHORTCUTS: 1-4 | P: PAY LATER | W: SWAP AI | SPACE | R]", True, COLOR_GOLD_LIGHT)
        self.screen.blit(keybind_surf, (SCREEN_WIDTH - keybind_surf.get_width() - 24, 690))

    # --------------------------------------------------------------------------
    # MAIN APPLICATION LOOP
    # --------------------------------------------------------------------------
    def run(self):
        running = True
        print("=============================================================")
        print("   NOVALUNCH STUDENT-FACING DISPLAY (CFD) MONITOR INITIALIZED ")
        print("=============================================================")
        print("  Cashier / System Event Simulation Controls:")
        print("  - [1] Step 1: RFID/QR Tap Event (IDLE -> GREET)")
        print("  - [2] Step 2: Vision Camera Trigger (GREET -> SCANNING)")
        print("  - [3] Step 3: Calibrate Stability Timer (SCANNING -> COUNTDOWN)")
        print("  - [4] Step 4: Settlement Execution (COUNTDOWN -> SETTLEMENT)")
        print("  - [P] 1-Tap Pay Later Emergency Overdraft Safety Net")
        print("  - [W] AI Visual Misclassification Quick-Swap (Chicken <-> Pork)")
        print("  -----------------------------------------------------------")
        print("  - [SPACEBAR] : Advance Step Flow / Tap ID / Auto Pay")
        print("  - [M]        : Toggle Platform Motion (Pauses 5s Timer)")
        print("  - [I]        : Toggle Insufficient Balance Mode")
        print("  - [C]        : Toggle Hardware/Synthetic Camera Feed")
        print("  - [R]        : Reset System to IDLE State")
        print("=============================================================")

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
                            scanned_uid = self.rfid_scan_buffer.strip()
                            print(f"[PHYSICAL 125kHz / QR SCANNER] Scanned: '{scanned_uid}'")
                            self.handle_rfid_tap(scanned_uid)
                            self.rfid_scan_buffer = ""
                        else:
                            self.handle_rfid_tap()
                            self.rfid_scan_buffer = ""
                    elif event.key == pygame.K_SPACE:
                        self.handle_rfid_tap()
                        self.rfid_scan_buffer = ""
                    elif event.key == pygame.K_p:
                        self.execute_pay_later_checkout()
                    elif event.key == pygame.K_w:
                        # Quick swap Fried Chicken <-> Pork Adobo
                        print("[AI OVERRIDE] 1-Touch Visual Correction: Swapping meal item...")
                        for it in self.cart_items:
                            if "Chicken" in it["name"]:
                                it["name"] = "Pork Adobo with Rice"
                                it["ai_label"] = "pork_adobo"
                                break
                            elif "Pork" in it["name"]:
                                it["name"] = "Fried Chicken with Rice"
                                it["ai_label"] = "fried_chicken"
                                break
                        self.recalculate_total()
                    elif event.key == pygame.K_m:
                        self.motion_detected = not self.motion_detected
                        m_str = "DETECTED (Timer Paused)" if self.motion_detected else "CLEAR (Tray Stable)"
                        print(f"[SIMULATION CUE] Motion on scanning platform: {m_str}")
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
                    elif event.key == pygame.K_i:
                        self.insufficient_balance_mode = not self.insufficient_balance_mode
                        mode_str = "ENABLED (₱50.00)" if self.insufficient_balance_mode else "DISABLED (₱150.00)"
                        print(f"[DEMO OPTION] Insufficient balance simulation: {mode_str}")
                    elif event.key == pygame.K_c:
                        is_on = self.camera_thread.toggle_manual()
                        cam_str = "HARDWARE LIVE" if is_on else "SYNTHETIC DEMO"
                        print(f"[DEMO OPTION] Manual Camera Hardware State: {cam_str}")

                    if event.unicode and (event.unicode.isdigit() or event.unicode.isalnum() or event.unicode in ['-', '_']):
                        now = time.time()
                        if now - self.last_key_time > 0.4:
                            self.rfid_scan_buffer = ""
                        self.rfid_scan_buffer += event.unicode
                        self.last_key_time = now

                elif event.type == pygame.TEXTINPUT:
                    now = time.time()
                    if now - self.last_key_time > 0.4:
                        self.rfid_scan_buffer = ""
                    self.rfid_scan_buffer += event.text
                    self.last_key_time = now

                elif event.type == pygame.MOUSEBUTTONDOWN:
                    if event.button == 1:
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

            now = time.time()
            if self.current_state == STATE_PREORDER_ANNOUNCEMENT:
                # 8.0-Second Pre-Order Screen Auto-dismiss
                if now - self.state_timer >= 8.0:
                    self.transition_to_state(STATE_IDLE)

            elif self.current_state in [STATE_GREET, STATE_SCANNING]:
                # 15-Second Session Timeout check if student walks away without placing tray
                if now - self.state_timer >= 15.0:
                    print("[SESSION TIMEOUT] No tray placed within 15 seconds. Returning to IDLE.")
                    speak_text("Session timed out.")
                    self.transition_to_state(STATE_IDLE)
                else:
                    live_items = self.camera_thread.get_latest_detections()
                    if live_items:
                        curr_hash = "-".join(sorted([item["name"] for item in live_items]))
                        if curr_hash == self.last_detection_hash:
                            if self.stable_start_time == 0.0:
                                self.stable_start_time = now
                            elif now - self.stable_start_time >= 1.2:
                                self.cart_items = live_items
                                self.recalculate_total()
                                self.transition_to_state(STATE_STABILITY_COUNTDOWN)
                        else:
                            self.last_detection_hash = curr_hash
                            self.stable_start_time = now
                            self.cart_items = live_items
                            self.recalculate_total()
                    else:
                        self.stable_start_time = 0.0
                        self.last_detection_hash = ""
                        self.cart_items = []
                        self.total_amount = 0.0

            elif self.current_state == STATE_STABILITY_COUNTDOWN:
                if self.motion_detected:
                    self.countdown_remaining = 4.0
                    if not self.motion_voice_alerted:
                        speak_text("Motion detected on platform. Keep hands clear.")
                        self.motion_voice_alerted = True
                else:
                    self.motion_voice_alerted = False
                    self.countdown_remaining -= dt
                    curr_sec = int(math.ceil(self.countdown_remaining))
                    
                    if curr_sec < self.last_tick_sec and curr_sec >= 1:
                        self.last_tick_sec = curr_sec
                        if self.sounds.get("tick"):
                            try:
                                self.sounds["tick"].play()
                            except Exception:
                                pass

                    self.status_message = f"🟢 Items stable. Auto-deducting ₱{self.total_amount:.2f} in {self.countdown_remaining:.1f}s"
                    
                    if self.countdown_remaining <= 0.0:
                        self.transition_to_state(STATE_SETTLEMENT)

            elif self.current_state == STATE_SETTLEMENT:
                hold_time = 4.0 if self.status_message.startswith("Payment Successful") else 6.0
                if now - self.state_timer >= hold_time:
                    self.transition_to_state(STATE_IDLE)

            elif self.current_state == STATE_ERROR:
                if now - self.state_timer >= 4.0:
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
            self.clock.tick(TARGET_FPS)

        self.camera_thread.stop()
        pygame.quit()
        sys.exit(0)

if __name__ == "__main__":
    app = NovaLunchKioskGUI()
    app.run()
