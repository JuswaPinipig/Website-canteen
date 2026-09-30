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
import re
import sqlite3
import shutil
import subprocess
import threading
import urllib.request
import urllib.parse
import urllib.error
import logging
from collections import deque
from pathlib import Path
from socketserver import ThreadingMixIn
from http.server import HTTPServer, BaseHTTPRequestHandler
import numpy as np
import cv2
import pygame
import argparse

# Dynamic filesystem anchor resolution for cross-platform robustness
SCRIPT_DIR = Path(__file__).resolve().parent
SRC_DIR = SCRIPT_DIR.parent
PROJECT_ROOT = SRC_DIR.parent

# Configure logger for Kiosk subsystem
logger = logging.getLogger("NovaLunchKiosk")
if not logger.handlers:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

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
STATE_PAYMENT_CONFIRMATION = 8

STATE_NAMES = {
    STATE_IDLE: "IDLE",
    STATE_GREET: "GREET",
    STATE_SCANNING: "SCANNING",
    STATE_STABILITY_COUNTDOWN: "COUNTDOWN",
    STATE_SETTLEMENT: "SETTLEMENT",
    STATE_ERROR: "ERROR",
    STATE_PREORDER_ANNOUNCEMENT: "PREORDER",
    STATE_PAYMENT_CONFIRMATION: "CONFIRMATION"
}

_GLOBAL_DB_MANAGER = None

def get_edge_db_path():
    candidates = [
        SRC_DIR / "database" / "novalunch_edge.db",
        PROJECT_ROOT / "src" / "database" / "novalunch_edge.db",
        PROJECT_ROOT / "database" / "novalunch_edge.db",
        SCRIPT_DIR / "novalunch_edge.db",
        Path("src/database/novalunch_edge.db"),
        Path("database/novalunch_edge.db"),
        Path("novalunch_edge.db")
    ]
    for c in candidates:
        if c and Path(c).exists():
            return str(Path(c).resolve())
    return str((SRC_DIR / "database" / "novalunch_edge.db").resolve())

# In-Memory Catalog Cache (STRICTLY RUNTIME-POPULATED — NO MOCK/PLACEHOLDER ITEMS)
# This dict starts EMPTY and is populated only by DatabaseManager.upsert_product()
# from the SQLite edge DB (sync_remote_catalog) and the Supabase cloud catalog.
# There are deliberately NO hardcoded demo/mock products here: any detection that
# cannot be resolved to a real, price>0, non-archived catalog record is DISCARDED
# (lookup_pos_item returns None) and never enters the cart. This is what prevents
# phantom/ghost cart items from ever appearing on the CFD or the Cashier POS.
POS_CATALOG_DATABASE = {}

def lookup_pos_item(raw_label):
    """
    Dynamically resolves a detection class name to a POS catalog item.
    1. Normalizes search: lowercases and checks against ai_label, name.lower(), or partial matches
       (e.g., 'hansel' matches 'Hansel Crackers', 'loaded' matches 'Loaded Chocolate').
    2. Queries local edge database (novalunch_edge.db) with exact and token/partial matching.
    3. Checks in-memory POS_CATALOG_DATABASE with resilient partial matching.
    4. If still unfound or resolved price is 0/null: returns None (discards from cart).
    """
    if not raw_label:
        return None

    s = str(raw_label).strip()
    s_lower = s.lower()
    s_clean = s_lower.replace("_", " ").replace("-", " ").strip()

    # 1. Query local edge SQLite database (novalunch_edge.db)
    db_path = None
    if _GLOBAL_DB_MANAGER is not None and getattr(_GLOBAL_DB_MANAGER, "sqlite_path", None):
        db_path = _GLOBAL_DB_MANAGER.sqlite_path
    if not db_path or not os.path.exists(db_path):
        db_path = get_edge_db_path()

    if db_path and os.path.exists(db_path):
        try:
            conn = sqlite3.connect(db_path, timeout=3.0)
            c = conn.cursor()

            # Priority 1: Exact or case-insensitive ai_label, name, or barcode
            c.execute("""
                SELECT id, name, price, category, barcode, is_available, stock, ai_label, is_archived 
                FROM products 
                WHERE (ai_label = ? OR LOWER(ai_label) = ? OR name = ? OR LOWER(name) = ? OR barcode = ?) 
                  AND (is_archived = 0 OR is_archived IS NULL)
                ORDER BY updated_at DESC
                LIMIT 1;
            """, (s, s_lower, s, s_lower, s))
            row = c.fetchone()
            if row:
                price = float(row[2]) if row[2] is not None else 0.0
                if price > 0.0:
                    conn.close()
                    return {
                        "id": str(row[0]),
                        "name": str(row[1]),
                        "price": price,
                        "category": str(row[3] or "SNACKS & BAKERY"),
                        "barcode": str(row[4]) if row[4] else None,
                        "available": bool(row[5]),
                        "is_available": bool(row[5]),
                        "stock": int(row[6]) if row[6] is not None else 50,
                        "ai_label": str(row[7]) if row[7] else s,
                        "is_archived": bool(row[8]) if len(row) > 8 and row[8] is not None else False,
                        "requires_cashier_review": False,
                        "status": "active"
                    }

            # Priority 2: Resilient partial search (e.g. 'hansel' in 'Hansel Crackers', 'loaded' in 'Loaded Chocolate')
            pattern = f"%{s_clean}%"
            c.execute("""
                SELECT id, name, price, category, barcode, is_available, stock, ai_label, is_archived 
                FROM products 
                WHERE (LOWER(name) LIKE ? OR LOWER(ai_label) LIKE ?)
                  AND (is_archived = 0 OR is_archived IS NULL)
                ORDER BY updated_at DESC
                LIMIT 1;
            """, (pattern, pattern))
            row = c.fetchone()
            if row:
                price = float(row[2]) if row[2] is not None else 0.0
                if price > 0.0:
                    conn.close()
                    return {
                        "id": str(row[0]),
                        "name": str(row[1]),
                        "price": price,
                        "category": str(row[3] or "SNACKS & BAKERY"),
                        "barcode": str(row[4]) if row[4] else None,
                        "available": bool(row[5]),
                        "is_available": bool(row[5]),
                        "stock": int(row[6]) if row[6] is not None else 50,
                        "ai_label": str(row[7]) if row[7] else s,
                        "is_archived": bool(row[8]) if len(row) > 8 and row[8] is not None else False,
                        "requires_cashier_review": False,
                        "status": "active"
                    }

            # Priority 3: Scan all active unarchived products for reverse substring matches
            c.execute("""
                SELECT id, name, price, category, barcode, is_available, stock, ai_label, is_archived 
                FROM products 
                WHERE (is_archived = 0 OR is_archived IS NULL);
            """)
            all_rows = c.fetchall()
            conn.close()
            for r in all_rows:
                p_name = (r[1] or "").lower().replace("_", " ").replace("-", " ")
                p_ai = (r[7] or "").lower().replace("_", " ").replace("-", " ")
                if s_clean and (s_clean in p_name or p_name in s_clean or (p_ai and (s_clean in p_ai or p_ai in s_clean))):
                    price = float(r[2]) if r[2] is not None else 0.0
                    if price > 0.0:
                        return {
                            "id": str(r[0]),
                            "name": str(r[1]),
                            "price": price,
                            "category": str(r[3] or "SNACKS & BAKERY"),
                            "barcode": str(r[4]) if r[4] else None,
                            "available": bool(r[5]),
                            "is_available": bool(r[5]),
                            "stock": int(r[6]) if r[6] is not None else 50,
                            "ai_label": str(r[7]) if r[7] else s,
                            "is_archived": bool(r[8]) if len(r) > 8 and r[8] is not None else False,
                            "requires_cashier_review": False,
                            "status": "active"
                        }
        except Exception:
            pass

    # 2. Secondary check against in-memory catalog cache with partial matching
    match = None
    if s in POS_CATALOG_DATABASE:
        match = dict(POS_CATALOG_DATABASE[s])
    elif s_lower in POS_CATALOG_DATABASE:
        match = dict(POS_CATALOG_DATABASE[s_lower])
    elif s_clean in POS_CATALOG_DATABASE:
        match = dict(POS_CATALOG_DATABASE[s_clean])
    else:
        for k, v in POS_CATALOG_DATABASE.items():
            if not isinstance(v, dict):
                continue
            k_lower = str(k).lower().replace("_", " ").replace("-", " ").strip()
            v_name = str(v.get("name") or "").lower().replace("_", " ").replace("-", " ").strip()
            v_ai = str(v.get("ai_label") or "").lower().replace("_", " ").replace("-", " ").strip()
            if (s_clean == k_lower or s_clean == v_name or s_clean == v_ai or
                s_clean in v_name or v_name in s_clean or
                (v_ai and (s_clean in v_ai or v_ai in s_clean))):
                match = dict(v)
                break

    if match and match.get("is_archived") is not True and match.get("status") != "archived":
        price = float(match.get("price", 0.0) or 0.0)
        if price > 0.0:
            return {
                "id": match.get("id", f"cached-{s}"),
                "name": match.get("name", s),
                "category": match.get("category", "ITEM"),
                "price": price,
                "stock": int(match.get("stock", 50)),
                "barcode": match.get("barcode"),
                "available": True,
                "is_available": True,
                "is_archived": False,
                "ai_label": match.get("ai_label", s),
                "requires_cashier_review": False,
                "status": "active"
            }

    # 3. Non-menu / unmapped item or zero price: ignore completely
    return None

_UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

def _is_uuid_like(value):
    """True when an edge-local product id is actually addressable in the Supabase
    `products` table (whose `id` is a UUID). Guards cloud writes from malformed-id 400s."""
    return bool(value) and bool(_UUID_RE.match(str(value).strip()))

def aggregate_detections(detections_list):
    if not detections_list:
        return []
    aggregated = {}
    for it in detections_list:
        if not it:
            continue
        # Exclude archived and expired items
        if it.get("is_archived") is True or it.get("status") in ["archived", "EXPIRED", "expired"]:
            continue
        price = float(it.get("price", 0.0) or 0.0)
        if price <= 0.0:
            continue
        if it.get("requires_cashier_review") or it.get("category") == "UNKNOWN" or "unmapped" in str(it.get("id", "")).lower() or "unmapped" in str(it.get("name", "")).lower():
            continue
        name = it.get("name", "Item")
        item_id = str(it.get("product_id") or it.get("id") or name)
        if name in aggregated:
            aggregated[name]["qty"] += it.get("qty", 1)
        else:
            item_dict = dict(it)
            item_dict["product_id"] = item_id
            aggregated[name] = item_dict
    return list(aggregated.values())

# ==============================================================================
# DATABASE & CLOUD DUAL-SYNC MANAGER
# ==============================================================================
class DatabaseManager:
    def __init__(self, accounts_path=None, sqlite_path=None):
        global _GLOBAL_DB_MANAGER
        _GLOBAL_DB_MANAGER = self

        if not accounts_path or not os.path.exists(accounts_path):
            candidates_accounts = [
                accounts_path,
                SRC_DIR / "database" / "accounts.json",
                PROJECT_ROOT / "src" / "database" / "accounts.json",
                PROJECT_ROOT / "database" / "accounts.json",
                SCRIPT_DIR / "accounts.json",
                Path("src/database/accounts.json"),
                Path("database/accounts.json")
            ]
            for ca in candidates_accounts:
                if ca and Path(ca).exists():
                    accounts_path = str(Path(ca).resolve())
                    break
            if not accounts_path:
                accounts_path = str((SRC_DIR / "database" / "accounts.json").resolve())

        if not sqlite_path or not os.path.exists(sqlite_path):
            candidates_sqlite = [
                sqlite_path,
                SRC_DIR / "database" / "novalunch_edge.db",
                PROJECT_ROOT / "src" / "database" / "novalunch_edge.db",
                PROJECT_ROOT / "database" / "novalunch_edge.db",
                SCRIPT_DIR / "novalunch_edge.db",
                Path("src/database/novalunch_edge.db"),
                Path("database/novalunch_edge.db"),
                Path("novalunch_edge.db")
            ]
            for cs in candidates_sqlite:
                if cs and Path(cs).exists():
                    sqlite_path = str(Path(cs).resolve())
                    break
            if not sqlite_path:
                sqlite_path = str((SRC_DIR / "database" / "novalunch_edge.db").resolve())

        self.accounts_path = os.path.abspath(accounts_path)
        self.sqlite_path = os.path.abspath(sqlite_path)
        self._lock = threading.Lock()
        self._init_sqlite()
        self.sync_remote_accounts()
        self.sync_remote_catalog()
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

            # Dynamic Edge Products Table with ai_label
            c.execute("""
                CREATE TABLE IF NOT EXISTS products (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    price REAL NOT NULL,
                    category TEXT,
                    barcode TEXT,
                    is_available INTEGER DEFAULT 1,
                    is_archived INTEGER DEFAULT 0,
                    stock INTEGER DEFAULT 50,
                    ai_label TEXT,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """)
            c.execute("CREATE INDEX IF NOT EXISTS idx_products_ai_label ON products (ai_label);")
            c.execute("CREATE INDEX IF NOT EXISTS idx_products_barcode ON products (barcode);")
            c.execute("CREATE INDEX IF NOT EXISTS idx_products_name ON products (name);")
            c.execute("CREATE INDEX IF NOT EXISTS idx_products_archived ON products (is_archived);")

            # Check if columns exist (migration support)
            c.execute("PRAGMA table_info(products);")
            cols = [col[1] for col in c.fetchall()]
            if "ai_label" not in cols:
                c.execute("ALTER TABLE products ADD COLUMN ai_label TEXT;")
            if "is_archived" not in cols:
                c.execute("ALTER TABLE products ADD COLUMN is_archived INTEGER DEFAULT 0;")

            # Students table: local edge cache for RFID → profile resolution
            c.execute("""
                CREATE TABLE IF NOT EXISTS students (
                    rfid_uid TEXT PRIMARY KEY,
                    student_id_number TEXT,
                    full_name TEXT,
                    email TEXT,
                    role TEXT DEFAULT 'student',
                    uuid TEXT,
                    balance REAL DEFAULT 0.0,
                    daily_limit REAL DEFAULT 200.0,
                    pay_later_count INTEGER DEFAULT 0,
                    pay_later_balance REAL DEFAULT 0.0,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """)
            c.execute("CREATE INDEX IF NOT EXISTS idx_students_rfid ON students (rfid_uid);")
            c.execute("CREATE INDEX IF NOT EXISTS idx_students_student_id ON students (student_id_number);")

            # Seed default products if products table is currently empty.
            # NOTE: These are real, sellable menu products only — NO demo/mock rows.
            # Products are synced live from Supabase via sync_remote_catalog().
            c.execute("SELECT COUNT(*) FROM products;")
            count = c.fetchone()[0]
            if count == 0:
                default_products = [
                    ("1c4cdeb9-a79c-41da-8c51-20de57e83263", "Hansel", 19.99, "SNACKS & BAKERY", "480000000021", 1, 0, 50, "hansel"),
                    ("bc0a3967-29a9-4f59-abd7-ec4ec27bf7be", "Loaded", 19.99, "SNACKS & BAKERY", "480000000022", 1, 0, 45, "loaded"),
                    ("350f2891-c29c-4523-ba49-bf7a52c39159", "Fita", 15.99, "SNACKS & BAKERY", "480000000023", 1, 0, 60, "fita"),
                    ("7b423713-16c8-4da4-a8a6-071f1a9a9fdc", "Piattos Cheese", 15.99, "SNACKS & BAKERY", "480000000024", 1, 0, 35, "piattos cheese"),
                    ("054f5317-0cce-45c3-a30e-abaa468ffeae", "Sky flakes", 9.99, "SNACKS & BAKERY", "480000000025", 1, 0, 50, "sky flakes"),
                    ("1ac49a1c-77a0-4fd9-a768-6096ce04d625", "Lemon Square", 12.99, "SNACKS & BAKERY", "480000000026", 1, 0, 30, "lemon square"),
                    ("14b584de-e1a0-4100-bc99-4eff958ff337", "Choco Mucho", 12.99, "SNACKS & BAKERY", "480000000027", 1, 0, 45, "choco mucho"),
                    ("957c9d2c-e215-4331-b4bd-17060992eee2", "Moby Caramel", 15.99, "SNACKS & BAKERY", "480000000028", 1, 0, 40, "moby caramel"),
                    ("3ce0251b-e7e7-47f2-bc3a-35a6a4b1456e", "Moby Chocolate", 9.99, "SNACKS & BAKERY", "480000000029", 1, 0, 40, "moby chocolate"),
                    ("b85e16ac-27b8-484c-8262-4630e24baf76", "Mr Chips", 15.99, "SNACKS & BAKERY", "480000000030", 1, 0, 40, "mr chips"),
                    ("3e34ca0f-c1f7-40af-88a1-986f338f7bf9", "Cheezy", 12.99, "SNACKS & BAKERY", "480000000031", 1, 0, 40, "cheezy"),
                    ("a1111111-1111-1111-1111-111111111111", "Classic Cheeseburger", 75.00, "MEALS & MAINS", "480000000001", 1, 0, 50, None),
                    ("a2222222-2222-2222-2222-222222222222", "Crispy Chicken Bowl", 85.00, "MEALS & MAINS", "480000000002", 1, 0, 60, None),
                    ("a3333333-3333-3333-3333-333333333333", "Ham & Cheese Sandwich", 45.00, "SNACKS & BAKERY", "480000000003", 1, 0, 40, None),
                    ("a4444444-4444-4444-4444-444444444444", "Mineral Water (500ml)", 20.00, "BEVERAGES", "480000000004", 1, 0, 150, None),
                    ("a5555555-5555-5555-5555-555555555555", "Iced Fruit Juice (350ml)", 30.00, "BEVERAGES", "480000000005", 1, 0, 80, None),
                    ("a6666666-6666-6666-6666-666666666666", "Fresh Red Apple", 25.00, "SNACKS & BAKERY", "480000000006", 1, 0, 40, None),
                    ("a8888888-8888-8888-8888-888888888888", "Choco Chip Cookie", 18.00, "SNACKS & BAKERY", "480000000008", 1, 0, 90, None)
                ]
                c.executemany("""
                    INSERT INTO products (id, name, price, category, barcode, is_available, is_archived, stock, ai_label, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                """, default_products)
                print(f"[DB MANAGER] Seeded {len(default_products)} default catalog items into SQLite.")

            conn.commit()
            conn.close()
        except Exception as e:
            print(f"[DB WARN] SQLite init: {e}")

    def upsert_product(self, prod):
        if not prod or not isinstance(prod, dict):
            return
        prod_id = str(prod.get("id") or f"prod_{int(time.time()*1000)}")
        name = str(prod.get("name") or "Menu Item").strip()
        price = float(prod.get("price") or 0.0)
        cat = str(prod.get("category") or "ITEM").strip()
        barcode = str(prod.get("barcode") or "") if prod.get("barcode") else None
        is_archived = 1 if (prod.get("is_archived") is True or str(prod.get("is_archived")).lower() == "true" or prod.get("status") == "archived") else 0
        avail = 1 if (prod.get("is_available") is not False and prod.get("available") is not False and is_archived == 0) else 0
        stock = int(prod.get("stock") if prod.get("stock") is not None else (prod.get("stock_quantity") if prod.get("stock_quantity") is not None else 50))
        ai_label = str(prod.get("ai_label") or prod.get("aiLabel") or "").strip()
        if not ai_label or ai_label.upper() == "NONE":
            ai_label = None

        with self._lock:
            try:
                conn = sqlite3.connect(self.sqlite_path, timeout=10.0)
                c = conn.cursor()
                if ai_label and is_archived == 0:
                    # Prevent duplicate active assignments across products
                    c.execute("""
                        UPDATE products 
                        SET ai_label = NULL, updated_at = CURRENT_TIMESTAMP 
                        WHERE id != ? AND (ai_label = ? OR LOWER(ai_label) = LOWER(?)) AND (is_archived = 0 OR is_archived IS NULL)
                    """, (prod_id, ai_label, ai_label))
                c.execute("""
                    INSERT INTO products (id, name, price, category, barcode, is_available, is_archived, stock, ai_label, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        price = excluded.price,
                        category = excluded.category,
                        barcode = excluded.barcode,
                        is_available = excluded.is_available,
                        is_archived = excluded.is_archived,
                        stock = excluded.stock,
                        ai_label = excluded.ai_label,
                        updated_at = CURRENT_TIMESTAMP
                """, (prod_id, name, price, cat, barcode, avail, is_archived, stock, ai_label))
                conn.commit()
                conn.close()
            except Exception as e:
                print(f"[DB WARN] upsert_product error: {e}")

        # Sync to in-memory POS_CATALOG_DATABASE
        global POS_CATALOG_DATABASE
        entry = {
            "id": prod_id,
            "name": name,
            "category": cat,
            "price": price,
            "stock": stock,
            "available": bool(avail),
            "is_available": bool(avail),
            "is_archived": bool(is_archived),
            "barcode": barcode,
            "ai_label": ai_label,
            "status": "archived" if is_archived else "active"
        }
        POS_CATALOG_DATABASE[name] = entry
        POS_CATALOG_DATABASE[name.lower()] = entry
        if ai_label:
            POS_CATALOG_DATABASE[ai_label] = entry
            POS_CATALOG_DATABASE[ai_label.lower()] = entry

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
                                    by_id[st_id]["id"] = p.get("id")
                                    by_id[st_id]["balance"] = bal
                                    by_id[st_id]["daily_limit"] = dlim
                                    # Always sync rfid_uid from cloud. If Supabase returns null/empty,
                                    # clear the local cache so unlinked/reassigned badges are
                                    # immediately treated as unrecognized by the kiosk lookup.
                                    by_id[st_id]["rfid_uid"] = p.get("rfid_uid") or ""
                                if st_id not in by_id:
                                    by_id[st_id] = {
                                        "id": p.get("id"),
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

    def sync_remote_catalog(self):
        def _fetch():
            try:
                # NOTE: the cloud `products` table has no `is_archived` column
                # (archival lives in `status`). Selecting it makes PostgREST reject
                # the whole query, which silently starved the kiosk of its real
                # AI-mapped catalog and pushed detections onto mock fallbacks.
                url = (
                    f"{SUPABASE_URL}/rest/v1/products"
                    f"?select=id,name,category,price,stock,stock_quantity,is_available,available,status,barcode,ai_label"
                    f"&status=neq.archived"
                )
                req = urllib.request.Request(url, headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"})
                with urllib.request.urlopen(req, timeout=6) as resp:
                    if resp.status == 200:
                        products = json.loads(resp.read().decode('utf-8'))
                        if products and isinstance(products, list):
                            for p in products:
                                self.upsert_product(p)
                            print(f"[DB MANAGER] ☁️ Synced & cached {len(products)} products from Supabase cloud catalog.")
            except urllib.error.HTTPError as e:
                print(f"[DB NOTICE] Remote catalog sync rejected (HTTP {e.code}): {e.reason}")
            except Exception as e:
                print(f"[DB NOTICE] Remote catalog sync deferred: {e}")
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

    def upsert_student(self, profile):
        """Cache a Supabase-resolved student profile into the local SQLite students table."""
        if not profile or not isinstance(profile, dict):
            return
        rfid = str(profile.get("rfid_uid") or profile.get("rfidUid") or "").strip()
        if not rfid:
            return
        sid = str(profile.get("student_id_number") or profile.get("studentId") or "").strip()
        name = str(profile.get("full_name") or profile.get("name") or "Student").strip()
        email = str(profile.get("email") or "").strip()
        uuid = str(profile.get("id") or profile.get("uuid") or "").strip()
        # Resolve wallet balance from nested wallets array (Supabase join) or flat field
        wallets = profile.get("wallets")
        if isinstance(wallets, list) and wallets:
            w = wallets[0]
            balance = float(w.get("balance") or profile.get("balance") or 0.0)
            daily_limit = float(w.get("daily_limit") or profile.get("daily_limit") or 200.0)
        else:
            balance = float(profile.get("balance") or profile.get("wallet_balance") or 0.0)
            daily_limit = float(profile.get("daily_limit") or profile.get("dailyCap") or 200.0)
        pay_later_count = int(profile.get("pay_later_count") or 0)
        pay_later_balance = float(profile.get("pay_later_balance") or profile.get("credit_liability") or 0.0)
        with self._lock:
            try:
                conn = sqlite3.connect(self.sqlite_path, timeout=10.0)
                c = conn.cursor()
                c.execute("""
                    INSERT INTO students (rfid_uid, student_id_number, full_name, email, uuid, balance, daily_limit, pay_later_count, pay_later_balance, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(rfid_uid) DO UPDATE SET
                        student_id_number = excluded.student_id_number,
                        full_name = excluded.full_name,
                        email = excluded.email,
                        uuid = excluded.uuid,
                        balance = excluded.balance,
                        daily_limit = excluded.daily_limit,
                        pay_later_count = excluded.pay_later_count,
                        pay_later_balance = excluded.pay_later_balance,
                        updated_at = CURRENT_TIMESTAMP
                """, (rfid, sid, name, email, uuid, balance, daily_limit, pay_later_count, pay_later_balance))
                conn.commit()
                conn.close()
                print(f"[DB MANAGER] Student RFID cached to SQLite: {rfid} -> {name} ({sid})")
            except Exception as e:
                print(f"[DB WARN] upsert_student error: {e}")

    def update_student_balance_sqlite(self, rfid_uid, student_id, new_balance):
        """Updates wallet balance in both the SQLite students table and the accounts JSON cache."""
        rfid = str(rfid_uid or "").strip()
        sid = str(student_id or "").strip()
        new_balance = max(0.0, float(new_balance))
        with self._lock:
            try:
                conn = sqlite3.connect(self.sqlite_path, timeout=10.0)
                c = conn.cursor()
                if rfid:
                    c.execute("UPDATE students SET balance = ?, updated_at = CURRENT_TIMESTAMP WHERE rfid_uid = ?", (new_balance, rfid))
                if sid:
                    c.execute("UPDATE students SET balance = ?, updated_at = CURRENT_TIMESTAMP WHERE student_id_number = ?", (new_balance, sid))
                conn.commit()
                conn.close()
            except Exception as e:
                print(f"[DB WARN] update_student_balance_sqlite error: {e}")
        # Also update the accounts JSON cache
        students = self.load_accounts()
        for s in students:
            if (rfid and s.get("rfid_uid") == rfid) or (sid and s.get("student_id_number") == sid):
                s["balance"] = new_balance
                break
        self.save_accounts(students)

    def fetch_student_by_rfid(self, raw_uid):
        """
        Hardened RFID resolution with live cloud balance sync:
        1. Attempt quick fetch from Supabase cloud profiles by rfid_uid.
           - On cloud hit: UPSERT into SQLite to refresh balance & limits, return profile.
        2. Fallback to local SQLite students table if cloud is unreachable or offline.
        3. Fallback to accounts JSON cache.
        4. Fail closed if card is unknown (return None).
        """
        if not raw_uid:
            return None
        q = str(raw_uid).strip()
        q_clean = q.upper().replace("-", "")
        q_nozero = q_clean.lstrip("0")

        # ── Step 1: Live Supabase cloud lookup (Primary for fresh balances) ────
        for uid_variant in list(dict.fromkeys([q, q_clean, q_nozero])):
            if not uid_variant:
                continue
            url = (
                f"{SUPABASE_URL}/rest/v1/profiles"
                f"?rfid_uid=eq.{urllib.parse.quote(uid_variant)}"
                f"&select=id,full_name,email,student_id_number,rfid_uid,role,status,"
                f"balance,daily_limit,pay_later_count,pay_later_pre_authorized,credit_liability,credit_limit,"
                f"wallets(balance,daily_limit)"
            )
            try:
                req = urllib.request.Request(
                    url,
                    headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"}
                )
                with urllib.request.urlopen(req, timeout=4) as resp:
                    if resp.status == 200:
                        profiles = json.loads(resp.read().decode('utf-8'))
                        if profiles and isinstance(profiles, list) and profiles:
                            p = profiles[0]
                            w = p.get("wallets")
                            w = w[0] if isinstance(w, list) and w else (w if isinstance(w, dict) else {})
                            bal = w.get("balance")
                            if bal is None:
                                bal = p.get("balance")
                            bal = float(bal or 0.0)
                            dlim = w.get("daily_limit")
                            if dlim is None:
                                dlim = p.get("daily_limit")
                            dlim = float(dlim if dlim is not None else 200.0)

                            student_profile = {
                                "id": p.get("student_id_number") or p.get("id"),
                                "name": p.get("full_name", "Student"),
                                "email": p.get("email", ""),
                                "rfidUid": p.get("rfid_uid", q),
                                "uuid": p.get("id"),
                                "balance": bal,
                                "wallet_balance": bal,
                                "daily_limit": dlim,
                                "status": p.get("status", "active"),
                                "pay_later_count": int(p.get("pay_later_count") or 0),
                                "pay_later_pre_authorized": p.get("pay_later_pre_authorized") is True,
                                "pay_later_allowance": p.get("pay_later_pre_authorized") is not False,
                                "pay_later_balance": float(p.get("credit_liability") or 0.0),
                                "credit_liability": float(p.get("credit_liability") or 0.0),
                                "credit_limit": float(p.get("credit_limit") or 300.0)
                            }

                            # Sync fresh balance & limits into local SQLite for offline resilience
                            try:
                                self.upsert_student({
                                    "rfid_uid": p.get("rfid_uid", q),
                                    "student_id_number": p.get("student_id_number"),
                                    "full_name": p.get("full_name"),
                                    "email": p.get("email"),
                                    "id": p.get("id"),
                                    "balance": bal,
                                    "daily_limit": dlim,
                                    "pay_later_count": int(p.get("pay_later_count") or 0),
                                    "pay_later_balance": float(p.get("credit_liability") or 0.0)
                                })
                            except Exception as cache_err:
                                logger.warning(f"[DB WARN] Failed to cache cloud profile: {cache_err}")

                            logger.info(f"[RFID LOOKUP] Cloud resolved: {q} -> {p.get('full_name')} (Balance: P{bal:.2f})")
                            return student_profile
            except Exception as e:
                logger.warning(f"[RFID LOOKUP] Supabase cloud query failed for '{uid_variant}': {e}")

        # ── Step 2: Query local SQLite students table (Offline Fallback) ──────
        try:
            conn = sqlite3.connect(self.sqlite_path, timeout=5.0)
            c = conn.cursor()
            c.execute("""
                SELECT rfid_uid, student_id_number, full_name, email, uuid, balance, daily_limit, pay_later_count, pay_later_balance
                FROM students
                WHERE rfid_uid = ? OR rfid_uid = ? OR rfid_uid = ?
                LIMIT 1
            """, (q, q_clean, q_nozero if q_nozero else q))
            row = c.fetchone()
            conn.close()
            if row:
                logger.info(f"[RFID LOOKUP] SQLite fallback resolved: {q} -> {row[2]} (Balance: P{float(row[5] or 0.0):.2f})")
                return {
                    "id": row[1] or row[0],
                    "name": row[2],
                    "email": row[3],
                    "rfidUid": row[0],
                    "uuid": row[4],
                    "balance": float(row[5] or 0.0),
                    "wallet_balance": float(row[5] or 0.0),
                    "daily_limit": float(row[6] or 200.0),
                    "pay_later_count": int(row[7] or 0),
                    "pay_later_balance": float(row[8] or 0.0),
                    "credit_liability": float(row[8] or 0.0),
                    "credit_limit": 300.0
                }
        except Exception as e:
            logger.warning(f"[DB WARN] fetch_student_by_rfid SQLite query error: {e}")

        # ── Step 3: Fallback to accounts JSON cache ────────────────────────────
        local_match = self.find_student_by_rfid(raw_uid)
        if local_match:
            try:
                self.upsert_student({
                    "rfid_uid": local_match.get("rfidUid") or q,
                    "student_id_number": local_match.get("id"),
                    "full_name": local_match.get("name"),
                    "email": local_match.get("email"),
                    "balance": local_match.get("balance", 0.0),
                    "daily_limit": local_match.get("daily_limit", 200.0),
                    "pay_later_count": local_match.get("pay_later_count", 0),
                    "pay_later_balance": local_match.get("pay_later_balance", 0.0)
                })
            except Exception as cache_err:
                logger.warning(f"[DB WARN] Failed to mirror accounts-cache hit into SQLite: {cache_err}")
            return local_match

        # ── Step 4: FAIL CLOSED — unregistered card, no mock user ─────────────
        logger.warning(f"[RFID LOOKUP] FAIL CLOSED: RFID '{q}' not found in Supabase or SQLite.")
        return None

    def decrement_product_stock(self, product_id, qty=1):
        """Dual-layer inventory deduction: local SQLite edge catalog + Supabase cloud catalog.

        Decrements local SQLite stock immediately, and dispatches a direct cloud update to
        Supabase products table so the web portal's realtime listener catches it instantly.
        """
        if not product_id:
            return False
        try:
            amount = max(1, int(qty or 1))
        except (TypeError, ValueError):
            amount = 1
        pid = str(product_id).strip()
        rowcount = 0
        with self._lock:
            try:
                conn = sqlite3.connect(self.sqlite_path, timeout=5.0)
                conn.execute("PRAGMA busy_timeout=5000;")
                cursor = conn.cursor()
                cursor.execute(
                    """
                    UPDATE products
                    SET stock = MAX(0, stock - ?),
                        is_available = CASE WHEN MAX(0, stock - ?) <= 0 THEN 0 ELSE is_available END,
                        updated_at = CURRENT_TIMESTAMP
                    WHERE id = ? OR ai_label = ? OR name = ?
                    """,
                    (amount, amount, pid, pid, pid)
                )
                conn.commit()
                conn.close()
                rowcount = cursor.rowcount
            except Exception as e:
                logger.error(f"[SQLITE STOCK ERROR] Failed to decrement {product_id}: {e}")

        # Cloud update: dispatch a direct cloud update to Supabase products table
        def _dispatch_cloud_decrement():
            try:
                filter_str = f"id.eq.{urllib.parse.quote(pid)},name.eq.{urllib.parse.quote(pid)},ai_label.eq.{urllib.parse.quote(pid)}"
                url = f"{SUPABASE_URL}/rest/v1/products?or=({filter_str})&select=id,stock"
                req = urllib.request.Request(url, headers={
                    "apikey": SUPABASE_ANON_KEY,
                    "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
                })
                with urllib.request.urlopen(req, timeout=5) as resp:
                    if resp.status == 200:
                        p_data = json.loads(resp.read().decode('utf-8'))
                        if p_data and len(p_data) > 0:
                            target = p_data[0]
                            target_id = target.get("id")
                            cur_stk = int(target.get("stock") or 0)
                            n_stk = max(0, cur_stk - amount)
                            patch_url = f"{SUPABASE_URL}/rest/v1/products?id=eq.{urllib.parse.quote(str(target_id))}"
                            patch_req = urllib.request.Request(
                                patch_url,
                                data=json.dumps({"stock": n_stk}).encode('utf-8'),
                                headers={
                                    "apikey": SUPABASE_ANON_KEY,
                                    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                                    "Content-Type": "application/json",
                                    "Prefer": "return=minimal"
                                },
                                method="PATCH"
                            )
                            urllib.request.urlopen(patch_req, timeout=5)
                            logger.info(f"[STOCK DEDUCT] Supabase cloud updated product {target_id} stock: {cur_stk} -> {n_stk}")
            except Exception as cloud_err:
                logger.warning(f"[STOCK DEDUCT WARN] Supabase cloud stock decrement failed for {product_id}: {cloud_err}")

        threading.Thread(target=_dispatch_cloud_decrement, daemon=True).start()
        return rowcount > 0

    def deduct_product_stock(self, product_id, qty=1):
        """Backward-compatible alias for :meth:`decrement_product_stock`."""
        return self.decrement_product_stock(product_id, qty)

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
        po_candidates = [
            SRC_DIR / "database" / "preorders.json",
            PROJECT_ROOT / "src" / "database" / "preorders.json",
            PROJECT_ROOT / "database" / "preorders.json",
            SCRIPT_DIR / "preorders.json",
            Path("src/database/preorders.json"),
            Path("database/preorders.json")
        ]
        po_path = None
        for cp in po_candidates:
            if Path(cp).exists():
                po_path = str(Path(cp).resolve())
                break
        if po_path and os.path.exists(po_path):
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

                # Normalize payment_method to match Postgres check constraint exactly.
                # Accepted values: 'rfid', 'cash', 'pay_later', 'payroll'
                # 'rfid' and 'card'/'wallet'/'online' are mapped to their canonical form.
                _raw_pm = str(pay_method or 'rfid').strip().lower()
                if _raw_pm in ('rfid', 'card', 'wallet', 'online'):
                    pm = 'rfid'
                elif _raw_pm == 'cash':
                    pm = 'cash'
                elif _raw_pm in ('pay_later', 'paylater', 'credit', 'emergency'):
                    pm = 'pay_later'
                elif _raw_pm in ('payroll', 'salary', 'salary_deduction'):
                    pm = 'payroll'
                else:
                    print(f"[EDGE SYNC] Unknown payment_method '{_raw_pm}' for tx {tx_id} — defaulting to 'rfid'")
                    pm = 'rfid'

                order_payload = {
                    "order_number": tx_id,
                    "total_amount": float(total_amt),
                    "final_amount": float(total_amt),
                    "discount_amount": 0.0,
                    "payment_method": pm,
                    "payment_status": "paid",
                    "order_source": "ai_kiosk",
                    "order_status": "completed"
                }
                if user_uuid:
                    order_payload["user_id"] = user_uuid
                if matched_st:
                    order_payload["student_name"] = matched_st.get("full_name") or matched_st.get("name") or "Student Member"

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
                            resp_body = resp.read().decode('utf-8')
                            items_saved = True
                            try:
                                created_data = json.loads(resp_body) if resp_body else []
                                created_order = created_data[0] if isinstance(created_data, list) and created_data else (created_data if isinstance(created_data, dict) else {})
                                created_id = created_order.get("id")
                                if created_id and items:
                                    items_payload = [{
                                        "order_id": created_id,
                                        "product_name": itm.get("name", "Item"),
                                        "unit_price": float(itm.get("price", 0.0)),
                                        "quantity": int(itm.get("qty", 1)),
                                        "total_price": round(float(itm.get("price", 0.0)) * int(itm.get("qty", 1)), 2),
                                        "subtotal": round(float(itm.get("price", 0.0)) * int(itm.get("qty", 1)), 2)
                                    } for itm in items]
                                    items_req = urllib.request.Request(
                                        f"{SUPABASE_URL}/rest/v1/order_items",
                                        data=json.dumps(items_payload).encode('utf-8'),
                                        headers={
                                            "apikey": SUPABASE_ANON_KEY,
                                            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                                            "Content-Type": "application/json"
                                        },
                                        method="POST"
                                    )
                                    with urllib.request.urlopen(items_req, timeout=5) as items_resp:
                                        if items_resp.status not in (200, 201):
                                            items_saved = False
                            except Exception as items_ex:
                                items_saved = False
                                print(f"[EDGE SYNC] ⚠️ Order items push failed: {items_ex}")

                            # Cloud Wallet Deduction for offline RFID orders
                            wallet_deducted = False
                            if user_uuid and pm == 'rfid':
                                try:
                                    rpc_url = f"{SUPABASE_URL}/rest/v1/rpc/fn_deduct_wallet_balance"
                                    rpc_req = urllib.request.Request(
                                        rpc_url,
                                        data=json.dumps({"p_user_id": user_uuid, "p_amount": float(total_amt)}).encode('utf-8'),
                                        headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}", "Content-Type": "application/json"},
                                        method="POST"
                                    )
                                    with urllib.request.urlopen(rpc_req, timeout=4) as rpc_resp:
                                        if rpc_resp.status in (200, 201, 204):
                                            wallet_deducted = True
                                except Exception as rpc_err:
                                    print(f"[EDGE SYNC] Wallet deduction notice: {rpc_err}")

                            wallet_sync_ok = (pm != 'rfid' or wallet_deducted or not user_uuid)
                            if items_saved and wallet_sync_ok:
                                c.execute("UPDATE pending_transactions SET sync_status = 'SYNCED' WHERE transaction_id = ?", (tx_id,))
                                conn.commit()
                                print(f"[EDGE SYNC] ☁️ Replayed offline transaction to cloud: {tx_id}")
                except urllib.error.HTTPError as http_err:
                    err_body = ""
                    try:
                        err_body = http_err.read().decode('utf-8')
                    except Exception:
                        pass
                    if http_err.code == 409 or "duplicate key" in err_body or "unique constraint" in err_body:
                        # Already exists in cloud — mark as synced
                        c.execute("UPDATE pending_transactions SET sync_status = 'SYNCED' WHERE transaction_id = ?", (tx_id,))
                        conn.commit()
                        print(f"[EDGE SYNC] ☁️ Transaction already exists in cloud (409): {tx_id}")
                    elif http_err.code == 400 and ("23514" in err_body or "check_violation" in err_body or "violates check constraint" in err_body):
                        # Postgres check constraint violation (e.g. invalid payment_method value).
                        # Mark as PERMANENTLY_FAILED so it is never retried in an infinite loop.
                        print(f"[EDGE SYNC ERROR] Check-constraint violation (23514) on {tx_id}. Marking PERMANENTLY_FAILED. Body: {err_body}")
                        c.execute("UPDATE pending_transactions SET sync_status = 'PERMANENTLY_FAILED' WHERE transaction_id = ?", (tx_id,))
                        conn.commit()
                    elif http_err.code == 400:
                        # Other 400 errors (e.g. bad payload, schema mismatch) — log explicitly
                        print(f"[EDGE SYNC ERROR] HTTP 400 for tx {tx_id}. Will not retry until fixed. Body: {err_body}")
                        c.execute("UPDATE pending_transactions SET sync_status = 'PERMANENTLY_FAILED' WHERE transaction_id = ?", (tx_id,))
                        conn.commit()
                    else:
                        print(f"[EDGE SYNC NOTICE] Offline sync pending connection for {tx_id} (HTTP {http_err.code}): {err_body}")
                        break  # Transient network / 5xx — pause sweep
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
RESOLVED_YOLO_PATH = None

def get_yolo_model(pt_path=None):
    global YOLO_MODEL, YOLO_ATTEMPTED, RESOLVED_YOLO_PATH
    if YOLO_MODEL is not None:
        return YOLO_MODEL
    if YOLO_ATTEMPTED:
        return None
    YOLO_ATTEMPTED = True

    # Establish assets and models directories
    models_dir = (SRC_DIR / "assets" / "models").resolve()
    if not models_dir.exists():
        models_dir = (PROJECT_ROOT / "src" / "assets" / "models").resolve()

    primary_model_path = models_dir / "novalunch_yolo-2.pt"

    candidates = [
        models_dir / "novalunch_yolo-2.pt",   # Priority 1: Updated v2 model
        models_dir / "novalunch_yolo.pt",     # Fallback
        models_dir / "best.pt",
    ]

    # Additional fallback search paths if deployed in alternate directory layouts
    candidates.extend([
        (PROJECT_ROOT / "src" / "assets" / "models" / "novalunch_yolo-2.pt").resolve(),
        (PROJECT_ROOT / "assets" / "models" / "novalunch_yolo-2.pt").resolve(),
        (SCRIPT_DIR / "novalunch_yolo-2.pt").resolve(),
        Path("novalunch_yolo-2.pt").resolve(),
    ])

    env_path = os.environ.get("YOLO_MODEL_PATH")
    if env_path:
        candidates.insert(0, Path(env_path).resolve())
    if pt_path:
        pt_cand = Path(pt_path).resolve()
        if pt_cand not in candidates:
            candidates.insert(0 if not env_path else 1, pt_cand)

    resolved_path = None
    for p in candidates:
        if not p:
            continue
        cand = Path(p)
        # Pre-flight validation
        if not cand.is_file():
            continue
        if cand.stat().st_size <= 1024 * 1024:
            logger.warning(f"[AI VISION WARN] Skipping invalid/truncated checkpoint {cand.name} (size: {cand.stat().st_size} bytes)")
            continue
        try:
            with open(cand, "rb") as f:
                header = f.read(64)
                if header.startswith(b"version https://git-lfs"):
                    logger.warning(f"[AI VISION WARN] Skipping Git LFS pointer file: {cand.name}")
                    continue
        except Exception as e:
            logger.warning(f"[AI VISION WARN] Error reading header of {cand.name}: {e}")
            continue

        resolved_path = cand
        break

    if resolved_path:
        RESOLVED_YOLO_PATH = str(resolved_path)
        try:
            from ultralytics import YOLO
            file_size_mb = resolved_path.stat().st_size / (1024 * 1024)
            YOLO_MODEL = YOLO(str(resolved_path))
            logger.info(f"[AI VISION] 🟢 Successfully loaded updated model checkpoint: {resolved_path.name} ({file_size_mb:.1f} MB)")
            print(f"[AI VISION] 🟢 Successfully loaded updated model checkpoint: {resolved_path.name} ({file_size_mb:.1f} MB)")
        except Exception as e:
            logger.error(f"[AI VISION WARN] YOLO load error: {e}")
            print(f"[AI VISION WARN] YOLO load error: {e}")
    else:
        logger.warning("[AI VISION WARN] YOLO model weights not found in standard asset paths.")
        print("[AI VISION WARN] YOLO model weights not found in standard asset paths.")
    return YOLO_MODEL

class CameraThread(threading.Thread):
    def __init__(self, cam_index=None):
        super().__init__()
        self.daemon = True
        self.cap = None
        self.current_frame = None
        self.frame_size = (640, 480)
        self.latest_detections = []
        self.ai_engine_name = "YOLO11 Vision"
        self.fps_display = 60
        self.lock = threading.Lock()
        self.running = True
        self.manual_enabled = True
        self.class_names = {}
        model = get_yolo_model()
        if model is not None:
            self.class_names = getattr(model, 'names', {})
        self.menu_catalog_by_ai_label = {}

        # External camera selection via explicit argument or KIOSK_CAM_INDEX env var (default 0)
        if cam_index is not None:
            self.cam_index = int(cam_index)
        else:
            self.cam_index = int(os.environ.get("KIOSK_CAM_INDEX", 0))

        self.refresh_menu_catalog_cache()
        self._init_camera(self.cam_index)

    def refresh_menu_catalog_cache(self):
        """
        Builds the active menu catalog whitelist mapped by ai_label and normalized names.
        """
        catalog = {}
        # 1. From POS_CATALOG_DATABASE
        for k, item in POS_CATALOG_DATABASE.items():
            if not item or item.get("is_archived") is True or item.get("status") in ["archived", "EXPIRED", "expired"]:
                continue
            price = float(item.get("price") or 0.0)
            if price <= 0.0:
                continue
            lbl = item.get("ai_label") or item.get("name") or k
            for key_variant in [lbl, str(lbl).lower(), str(lbl).replace("_", " "), str(lbl).replace(" ", "_")]:
                catalog[key_variant] = item

        # 2. From SQLite products
        db_path = get_edge_db_path()
        if db_path and os.path.exists(db_path):
            try:
                conn = sqlite3.connect(db_path, timeout=3.0)
                c = conn.cursor()
                c.execute("""
                    SELECT id, name, price, category, barcode, is_available, stock, ai_label, is_archived 
                    FROM products 
                    WHERE (is_archived = 0 OR is_archived IS NULL)
                      AND (is_available = 1 OR is_available IS NULL);
                """)
                for row in c.fetchall():
                    price = float(row[2]) if row[2] is not None else 0.0
                    if price <= 0.0:
                        continue
                    pname = str(row[1])
                    ai_lbl = str(row[7]) if row[7] else pname
                    prod = {
                        "id": str(row[0]),
                        "name": pname,
                        "price": price,
                        "category": str(row[3] or "SNACKS & BAKERY"),
                        "barcode": str(row[4]) if row[4] else None,
                        "available": bool(row[5]),
                        "is_available": bool(row[5]),
                        "stock": int(row[6]) if row[6] is not None else 50,
                        "ai_label": ai_lbl,
                        "is_archived": False,
                        "requires_cashier_review": False,
                        "status": "active"
                    }
                    for v in [ai_lbl, ai_lbl.lower(), ai_lbl.replace("_", " "), ai_lbl.replace(" ", "_"),
                              pname, pname.lower(), pname.replace("_", " "), pname.replace(" ", "_")]:
                        catalog[v] = prod
                conn.close()
            except Exception:
                pass

        # 3. For any class name in self.class_names, if lookup_pos_item finds a valid product, map it
        if hasattr(self, 'class_names') and self.class_names:
            for cls_id, cname in self.class_names.items():
                if cname not in catalog:
                    found = lookup_pos_item(cname)
                    if found and float(found.get("price") or 0.0) > 0.0:
                        catalog[cname] = found
                        catalog[cname.lower()] = found

        with self.lock:
            self.menu_catalog_by_ai_label = catalog

    def _open_capture(self, index):
        is_windows = sys.platform.startswith('win')
        try:
            # On Windows, keep DirectShow backend support to prevent timeouts and crashes
            if is_windows and hasattr(cv2, 'CAP_DSHOW'):
                c = cv2.VideoCapture(index, cv2.CAP_DSHOW)
            else:
                c = cv2.VideoCapture(index)

            if c and c.isOpened():
                c.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                c.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                ret, f = c.read()
                if ret and f is not None:
                    return c
                c.release()
        except Exception as cam_err:
            print(f"[CAMERA] ⚠️ Probe failed on index {index}: {cam_err}")
        return None

    def _init_camera(self, target_index=None):
        if target_index is not None:
            self.cam_index = int(target_index)
        else:
            self.cam_index = int(os.environ.get("KIOSK_CAM_INDEX", getattr(self, 'cam_index', 0)))

        is_windows = sys.platform.startswith('win')
        backend_str = " (DirectShow / CAP_DSHOW)" if is_windows else ""

        # Probe specified target index first
        c = self._open_capture(self.cam_index)
        if c:
            self.cap = c
            self.simulation_enabled = False
            print(f"[CAMERA] 🟢 Hardware stream initialized on index {self.cam_index}{backend_str}.")
            return

        # Fallback probe if target index fails
        for alt_idx in [0, 1, 2]:
            if alt_idx == self.cam_index:
                continue
            c = self._open_capture(alt_idx)
            if c:
                self.cap = c
                self.cam_index = alt_idx
                self.simulation_enabled = False
                print(f"[CAMERA] 🟢 Hardware stream initialized on fallback index {alt_idx}{backend_str}.")
                return

        self.cap = None
        self.simulation_enabled = True
        print("[CAMERA] 🟢 Hardware camera not detected. Running with Synthetic AI Simulation.")

    def switch_camera(self, new_index=None):
        """
        Switches camera capture device between indices (e.g., 0 and 1).
        Supports runtime switching via the 'C' hotkey.
        """
        with self.lock:
            current_idx = getattr(self, 'cam_index', 0)
            if new_index is None:
                # Toggle between 0 and 1
                target_idx = 1 if current_idx == 0 else 0
            else:
                target_idx = int(new_index)

            print(f"[CAMERA] 🔄 Requesting camera switch from index {current_idx} to {target_idx}...")
            if self.cap:
                try:
                    self.cap.release()
                except Exception:
                    pass
                self.cap = None

            c = self._open_capture(target_idx)
            if c:
                self.cap = c
                self.cam_index = target_idx
                self.simulation_enabled = False
                print(f"[CAMERA] 🟢 Successfully switched to camera index {target_idx}.")
                return True, target_idx
            else:
                print(f"[CAMERA] ⚠️ Camera index {target_idx} could not be opened. Reverting to index {current_idx}...")
                fallback_c = self._open_capture(current_idx)
                if fallback_c:
                    self.cap = fallback_c
                    self.cam_index = current_idx
                    self.simulation_enabled = False
                    return False, current_idx
                else:
                    self.cam_index = target_idx
                    self.simulation_enabled = True
                    return False, target_idx

    def toggle_manual(self):
        with self.lock:
            self.manual_enabled = not self.manual_enabled
            return self.manual_enabled

    def toggle_simulation(self):
        with self.lock:
            self.simulation_enabled = not getattr(self, 'simulation_enabled', False)
            return self.simulation_enabled

    def _generate_synthetic_frame(self, angle_deg):
        h, w = 480, 640
        canvas = np.full((h, w, 3), (25, 30, 40), dtype=np.uint8)

        # Platform grid
        for x in range(0, w, 40):
            cv2.line(canvas, (x, 0), (x, h), (38, 44, 58), 1)
        for y in range(0, h, 40):
            cv2.line(canvas, (0, y), (w, y), (38, 44, 58), 1)

        # Tray boundary
        cv2.rectangle(canvas, (100, 70), (540, 410), (55, 65, 85), 2)

        # Standby mode — safe, zero phantom food detections
        cv2.putText(canvas, "NOVALUNCH AI TRAY SCANNER - STANDBY", (140, 100), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (140, 165, 200), 1)
        cv2.putText(canvas, "Place meal tray under camera sensor", (155, 235), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 220, 240), 1)
        cv2.putText(canvas, "(Live Optical Sensor Ready)", (210, 265), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (100, 130, 160), 1)
        return canvas, []

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
                            self.ai_engine_name = "YOLO11 Vision"
                            if not self.class_names:
                                self.class_names = getattr(model, 'names', {})
                                self.refresh_menu_catalog_cache()
                            try:
                                # High confidence threshold (0.75) and NMS IoU (0.45) to eliminate background false positives
                                results = model(frame, imgsz=640, conf=0.75, iou=0.45, verbose=False)
                                for r in results:
                                    # 1. Check for OBB (Oriented Bounding Box) predictions
                                    obb_data = getattr(r, 'obb', None)
                                    if obb_data is not None and len(obb_data) > 0:
                                        for idx in range(len(obb_data)):
                                            cls_id = int(obb_data.cls[idx])
                                            class_name = self.class_names.get(cls_id)
                                            mapped_product = self.menu_catalog_by_ai_label.get(class_name)

                                            # STRICT FILTER: Discard any object not explicitly mapped to an active canteen menu item
                                            if not mapped_product:
                                                continue

                                            item_price = float(mapped_product.get("price") or 0.0)
                                            if item_price <= 0.0:
                                                continue
                                            if mapped_product.get("is_archived") is True or mapped_product.get("status") in ["archived", "EXPIRED", "expired"]:
                                                continue
                                            if mapped_product.get("requires_cashier_review") or mapped_product.get("category") == "UNKNOWN" or "unmapped" in str(mapped_product.get("id", "")).lower() or "unmapped" in str(mapped_product.get("name", "")).lower():
                                                continue

                                            conf = float(obb_data.conf[idx])
                                            coords = obb_data.xyxy[idx].tolist() if hasattr(obb_data.xyxy[idx], 'tolist') else list(obb_data.xyxy[idx])
                                            x1, y1, x2, y2 = map(int, coords)
                                            bw = max(20, x2 - x1)
                                            bh = max(20, y2 - y1)
                                            is_near_exp = mapped_product.get("status") in ["NEAR_EXPIRY", "near_expiry"] or mapped_product.get("expiry_status") == "near_expiry"
                                            prod_id = str(mapped_product.get("id") or f"yolo-obb-{cls_id}")
                                            detections.append({
                                                "id": prod_id,
                                                "product_id": prod_id,
                                                "ai_label": class_name,
                                                "name": mapped_product.get("name", class_name),
                                                "category": mapped_product.get("category", "SNACKS & BAKERY"),
                                                "qty": 1,
                                                "price": item_price,
                                                "stock": int(mapped_product.get("stock", 50)),
                                                "is_near_expiry": is_near_exp,
                                                "requires_cashier_review": False,
                                                "bbox": [x1, y1, bw, bh],
                                                "conf": conf
                                            })

                                    # 2. Check for standard 2D axis-aligned bounding boxes
                                    elif getattr(r, 'boxes', None) is not None and len(r.boxes) > 0:
                                        for idx, box in enumerate(r.boxes):
                                            cls_id = int(box.cls[0])
                                            class_name = self.class_names.get(cls_id)
                                            mapped_product = self.menu_catalog_by_ai_label.get(class_name)

                                            # STRICT FILTER: Discard any object not explicitly mapped to an active canteen menu item
                                            if not mapped_product:
                                                continue

                                            item_price = float(mapped_product.get("price") or 0.0)
                                            if item_price <= 0.0:
                                                continue
                                            if mapped_product.get("is_archived") is True or mapped_product.get("status") in ["archived", "EXPIRED", "expired"]:
                                                continue
                                            if mapped_product.get("requires_cashier_review") or mapped_product.get("category") == "UNKNOWN" or "unmapped" in str(mapped_product.get("id", "")).lower() or "unmapped" in str(mapped_product.get("name", "")).lower():
                                                continue

                                            conf = float(box.conf[0])
                                            coords = box.xyxy[0].tolist() if hasattr(box.xyxy[0], 'tolist') else list(box.xyxy[0])
                                            x1, y1, x2, y2 = map(int, coords)
                                            bw = max(20, x2 - x1)
                                            bh = max(20, y2 - y1)
                                            is_near_exp = mapped_product.get("status") in ["NEAR_EXPIRY", "near_expiry"] or mapped_product.get("expiry_status") == "near_expiry"
                                            prod_id = str(mapped_product.get("id") or f"yolo-box-{cls_id}")
                                            detections.append({
                                                "id": prod_id,
                                                "product_id": prod_id,
                                                "ai_label": class_name,
                                                "name": mapped_product.get("name", class_name),
                                                "category": mapped_product.get("category", "ITEM"),
                                                "qty": 1,
                                                "price": item_price,
                                                "stock": int(mapped_product.get("stock", 50)),
                                                "is_near_expiry": is_near_exp,
                                                "requires_cashier_review": False,
                                                "bbox": [x1, y1, bw, bh],
                                                "conf": conf
                                            })
                            except Exception as e:
                                print(f"[AI VISION WARN] Detection inference error: {e}")

                        # NO fallback to optical contours or dummy placeholder items.
                        # If no valid canteen items are detected, detections stays strictly empty [].

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
                if not item or not item.get("name"):
                    continue
                # Whitelist guard: ensure item has valid price > 0 and is not unknown/unmapped
                if float(item.get("price", 0.0) or 0.0) <= 0.0:
                    continue
                if item.get("requires_cashier_review") or item.get("category") == "UNKNOWN":
                    continue
                if "unmapped" in str(item.get("id", "")).lower() or "unmapped" in str(item.get("name", "")).lower():
                    continue

                bx, by, bw, bh = item.get("bbox", [100, 100, 150, 150])
                cv2.rectangle(bgr, (bx, by), (bx + bw, by + bh), (0, 215, 255), 2)
                lbl = f"{item.get('name', 'Item')} (₱{float(item.get('price', 0.0) or 0.0):.2f})"
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
# AUDIO & SPEECH ANNOUNCEMENT ENGINE (SYNTHESIZED & PLATFORM TTS)
# ==============================================================================
_tts_lock = threading.Lock()
_current_tts_process = None
_tts_generation = 0
_last_spoken_text = ""
_last_spoken_time = 0.0

def stop_active_speech():
    """Immediately stops and cancels any currently active speech announcement to prevent overlap."""
    global _current_tts_process, _tts_generation
    proc = None
    with _tts_lock:
        _tts_generation += 1
        if _current_tts_process is not None:
            proc = _current_tts_process
            _current_tts_process = None

    if proc is not None:
        try:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=0.15)
                except Exception:
                    proc.kill()
        except Exception:
            pass

    # On macOS, kill any lingering 'say' processes to guarantee clean voice cut-off
    try:
        import platform, subprocess
        if platform.system() == "Darwin":
            subprocess.run(["killall", "say"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=0.2)
    except Exception:
        pass

def speak_text(text, interrupt=True):
    """
    Speaks the given text using the platform TTS engine.
    Guarantees ZERO voice overlap:
    If a previous utterance is currently speaking, it is cleanly stopped
    before starting the new announcement.
    """
    global _last_spoken_text, _last_spoken_time, _current_tts_process, _tts_generation
    if not text:
        return

    clean_text = str(text).replace("'", "").replace('"', "").strip()
    if not clean_text:
        return

    now = time.time()
    # Deduplication guard: ignore identical prompt within 0.8s (prevents key bounce / double-announce)
    if clean_text == _last_spoken_text and (now - _last_spoken_time < 0.8):
        return
    _last_spoken_text = clean_text
    _last_spoken_time = now

    if interrupt:
        stop_active_speech()

    with _tts_lock:
        _tts_generation += 1
        my_generation = _tts_generation

    def _run_tts(gen, msg):
        global _current_tts_process
        with _tts_lock:
            if gen != _tts_generation:
                return

        proc = None
        try:
            import subprocess, platform
            sys_os = platform.system()
            if sys_os == "Darwin":
                proc = subprocess.Popen(
                    ["say", "-r", "190", msg],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
            elif sys_os == "Linux":
                proc = subprocess.Popen(
                    ["espeak", "-s", "160", msg],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
            elif sys_os == "Windows":
                ps_script = f"Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('{msg}')"
                proc = subprocess.Popen(
                    ["powershell", "-NoProfile", "-Command", ps_script],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
        except Exception:
            proc = None

        if proc is None:
            return

        with _tts_lock:
            if gen != _tts_generation:
                try:
                    proc.terminate()
                    proc.kill()
                except Exception:
                    pass
                return
            _current_tts_process = proc

        try:
            proc.wait(timeout=6.0)
        except Exception:
            pass
        finally:
            with _tts_lock:
                if _current_tts_process is proc:
                    _current_tts_process = None

    t = threading.Thread(target=_run_tts, args=(my_generation, clean_text), daemon=True)
    t.start()

def create_synthesized_sounds():
    try:
        if not pygame.mixer.get_init():
            pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=512)
        
        sample_rate = 44100
        # Tick beep (880 Hz, 60ms)
        n_samples_tick = int(sample_rate * 0.06)
        t_tick = np.linspace(0, 0.06, n_samples_tick, endpoint=False)
        wave_tick = (0.25 * np.sin(2 * np.pi * 880 * t_tick) * 32767).astype(np.int16)
        stereo_tick = np.column_stack((wave_tick, wave_tick))
        tick_sound = pygame.sndarray.make_sound(stereo_tick)

        # Success chime (587 Hz -> 880 Hz, 160ms)
        n_samples_succ = int(sample_rate * 0.16)
        t_succ = np.linspace(0, 0.16, n_samples_succ, endpoint=False)
        freq_ramp = np.linspace(587.33, 880.0, n_samples_succ)
        wave_succ = (0.30 * np.sin(2 * np.pi * freq_ramp * t_succ) * 32767).astype(np.int16)
        stereo_succ = np.column_stack((wave_succ, wave_succ))
        succ_sound = pygame.sndarray.make_sound(stereo_succ)

        return {"success": succ_sound, "tick": tick_sound}
    except Exception as e:
        return {"success": None, "tick": None}

# ==============================================================================
# REAL-TIME KIOSK HTTP REST & SERVER-SENT EVENTS (SSE) SERVER (PORT 8085)
# ==============================================================================
_GLOBAL_KIOSK_REF = None
_SSE_CLIENTS = []
_SSE_LOCK = threading.Lock()

def broadcast_kiosk_event(event_type, payload):
    data_str = json.dumps(payload)
    data = f"event: {event_type}\ndata: {data_str}\n\ndata: {data_str}\n\n".encode('utf-8')
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

    def handle_error(self, request, client_address):
        exc_type, exc_value, _ = sys.exc_info()
        if exc_type in (ConnectionResetError, ConnectionAbortedError, BrokenPipeError, TimeoutError, OSError):
            return
        if isinstance(exc_value, OSError) and getattr(exc_value, 'winerror', None) in (10053, 10054, 10058, 10060, 32):
            return
        super().handle_error(request, client_address)

class KioskHTTPRequestHandler(BaseHTTPRequestHandler):
    def handle(self):
        try:
            super().handle()
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError, TimeoutError, OSError):
            pass
        except Exception:
            pass

    def finish(self):
        try:
            super().finish()
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError, TimeoutError, OSError):
            pass
        except Exception:
            pass

    def _send_cors_headers(self, status=200, content_type="application/json"):
        try:
            self.send_response(status)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, HEAD")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
            self.send_header("Content-Type", content_type)
        except Exception:
            pass

    def do_OPTIONS(self):
        try:
            self._send_cors_headers(200)
            self.end_headers()
        except Exception:
            pass

    def do_HEAD(self):
        try:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            if path in ["/api/kiosk/status", "/api/kiosk/live", "/api/scan_tray", "/api/kiosk/model", "/api/model/info"]:
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
        except Exception:
            pass

    def do_GET(self):
        try:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            if path in ["/api/kiosk/status", "/api/kiosk/live", "/api/scan_tray"]:
                self._send_cors_headers(200, "application/json")
                self.end_headers()
                if _GLOBAL_KIOSK_REF is not None:
                    state_data = _GLOBAL_KIOSK_REF.get_live_kiosk_data()
                else:
                    state_data = {
                        "status": "SUCCESS",
                        "kiosk_state": "IDLE",
                        "student": None,
                        "active_student": None,
                        "cart_items": [],
                        "cart": [],
                        "total_amount": 0.0,
                        "timestamp": time.time(),
                        "model_info": {
                            "filename": "novalunch_yolo-2.pt",
                            "classes_count": 41,
                            "confidence_threshold": 0.80,
                            "status": "Active"
                        }
                    }
                try:
                    self.wfile.write(json.dumps(state_data).encode('utf-8'))
                except Exception:
                    pass

            elif path in ["/api/kiosk/model", "/api/model/info"]:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                metadata = _GLOBAL_KIOSK_REF.get_model_metadata() if _GLOBAL_KIOSK_REF else {}
                if not metadata:
                    classes_list = []
                    model = get_yolo_model()
                    if model and hasattr(model, 'names'):
                        names = model.names
                        if isinstance(names, dict):
                            classes_list = [names[k] for k in sorted(names.keys())]
                        elif isinstance(names, list):
                            classes_list = names
                    model_size_mb = "115.4 MB"
                    try:
                        p = RESOLVED_YOLO_PATH
                        if p and os.path.exists(p):
                            model_size_mb = f"{os.path.getsize(p) / (1024 * 1024):.1f} MB"
                    except Exception:
                        pass
                    metadata = {
                        "filename": Path(RESOLVED_YOLO_PATH).name if RESOLVED_YOLO_PATH else "novalunch_yolo-2.pt",
                        "size": model_size_mb,
                        "class_count": len(classes_list),
                        "classes": classes_list,
                        "confidence_cutoff": 0.80,
                        "status": "Active" if len(classes_list) > 0 else "Standby"
                    }
                try:
                    self.wfile.write(json.dumps(metadata).encode('utf-8'))
                except Exception:
                    pass
                return

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
                        try:
                            self.wfile.write(jpeg_bytes)
                        except Exception:
                            pass
                        return
                self._send_cors_headers(404, "application/json")
                self.end_headers()
                try:
                    self.wfile.write(json.dumps({"error": "Camera frame unavailable"}).encode('utf-8'))
                except Exception:
                    pass

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
                        try:
                            self.wfile.write(jpeg_bytes)
                        except Exception:
                            pass
                        return
                self._send_cors_headers(404, "application/json")
                self.end_headers()
                try:
                    self.wfile.write(json.dumps({"error": "Camera frame unavailable"}).encode('utf-8'))
                except Exception:
                    pass

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

            elif path in ["/api/kiosk/events", "/api/kiosk/stream"]:
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
                    try:
                        self.wfile.write(f"event: kiosk_update\ndata: {json.dumps(init_payload)}\n\ndata: {json.dumps(init_payload)}\n\n".encode('utf-8'))
                        self.wfile.flush()
                    except Exception:
                        pass

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
                try:
                    self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))
                except Exception:
                    pass
        except Exception:
            pass

    def do_POST(self):
        try:
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
                        _GLOBAL_KIOSK_REF.cart_manual_override_lock = False
                        _GLOBAL_KIOSK_REF.transition_to_state(STATE_IDLE)
                    elif action == "scan":
                        _GLOBAL_KIOSK_REF.execute_simulation_step(2)
                    elif action == "pay":
                        _GLOBAL_KIOSK_REF.cart_manual_override_lock = False
                        _GLOBAL_KIOSK_REF.execute_simulation_step(4)
                    elif action == "pay_later":
                        _GLOBAL_KIOSK_REF.cart_manual_override_lock = False
                        _GLOBAL_KIOSK_REF.execute_pay_later_checkout()
                    elif action == "update_cart":
                        new_cart = req_data.get("cart", [])
                        _GLOBAL_KIOSK_REF.cart_items = new_cart
                        _GLOBAL_KIOSK_REF.cart_manual_override_lock = bool(new_cart)
                        _GLOBAL_KIOSK_REF.total_amount = sum(float(item.get("price", 0)) * int(item.get("qty", 1)) for item in new_cart)
                        st_payload = req_data.get("student")
                        if st_payload and isinstance(st_payload, dict):
                            _GLOBAL_KIOSK_REF.active_student = {
                                "id": st_payload.get("studentId") or st_payload.get("id", ""),
                                "name": st_payload.get("name", "Student"),
                                "email": st_payload.get("email", ""),
                                "rfidUid": st_payload.get("rfidUid") or st_payload.get("rfid_uid", ""),
                                "balance": float(st_payload.get("balance", 0.0)),
                                "daily_limit": float(st_payload.get("daily_limit", 200.0))
                            }
                        else:
                            _GLOBAL_KIOSK_REF.active_student = None
                        if new_cart:
                            if _GLOBAL_KIOSK_REF.current_state in [STATE_IDLE, STATE_GREET]:
                                _GLOBAL_KIOSK_REF.current_state = STATE_SCANNING
                            _GLOBAL_KIOSK_REF.status_message = f"Live POS Cart Synced: {len(new_cart)} item(s) (₱{_GLOBAL_KIOSK_REF.total_amount:.2f})"
                        else:
                            _GLOBAL_KIOSK_REF.status_message = "Tap Student RFID Card on Reader to Begin"
                        _GLOBAL_KIOSK_REF.notify_pos_update()
                    elif action in ["confirm_payment", "complete_checkout"]:
                        _GLOBAL_KIOSK_REF.cart_manual_override_lock = False
                        st = req_data.get("student")
                        amt = float(req_data.get("amount", _GLOBAL_KIOSK_REF.total_amount))
                        passed_cart = req_data.get("cart")
                        if passed_cart and isinstance(passed_cart, list):
                            _GLOBAL_KIOSK_REF.cart_items = passed_cart
                        
                        order_number = req_data.get("order_number") or req_data.get("orderNo")
                        is_synced = req_data.get("synced_cloud", False)

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
                            tx_id = order_number or f"TXN_{int(time.time())}_{student_id.replace('-', '')}"
                            _GLOBAL_KIOSK_REF.db_manager.record_transaction(
                                tx_id, student_id, _GLOBAL_KIOSK_REF.cart_items, amt,
                                _GLOBAL_KIOSK_REF.latest_tray_image, payment_method="rfid"
                            )
                            if is_synced:
                                try:
                                    conn = sqlite3.connect(_GLOBAL_KIOSK_REF.db_manager.sqlite_path)
                                    conn.execute("UPDATE pending_transactions SET sync_status = 'SYNCED' WHERE transaction_id = ?", (tx_id,))
                                    conn.commit()
                                    conn.close()
                                except Exception:
                                    pass

                        _GLOBAL_KIOSK_REF.total_amount = amt
                        _GLOBAL_KIOSK_REF.status_message = "Payment confirmed. Please claim your meal."
                        _GLOBAL_KIOSK_REF.current_state = STATE_SETTLEMENT
                        _GLOBAL_KIOSK_REF.state_timer = time.time()
                        _GLOBAL_KIOSK_REF.notify_pos_update()
                    elif action == "update_product":
                        prod = req_data.get("product")
                        if prod and isinstance(prod, dict):
                            db_mgr = _GLOBAL_KIOSK_REF.db_manager if (_GLOBAL_KIOSK_REF and _GLOBAL_KIOSK_REF.db_manager) else _GLOBAL_DB_MANAGER
                            if db_mgr:
                                db_mgr.upsert_product(prod)
                            print(f"[KIOSK API] 🔄 Live product dynamic sync: {prod.get('name')} (ai_label: {prod.get('ai_label') or prod.get('aiLabel')}, price: ₱{prod.get('price')})")
                            _GLOBAL_KIOSK_REF.notify_pos_update()
                    elif action == "sync_catalog":
                        catalog = req_data.get("catalog", [])
                        if catalog and isinstance(catalog, list):
                            db_mgr = _GLOBAL_KIOSK_REF.db_manager if (_GLOBAL_KIOSK_REF and _GLOBAL_KIOSK_REF.db_manager) else _GLOBAL_DB_MANAGER
                            if db_mgr:
                                for prod in catalog:
                                    db_mgr.upsert_product(prod)
                            print(f"[KIOSK API] 🔄 Catalog batch dynamically synced: {len(catalog)} item(s)")
                            _GLOBAL_KIOSK_REF.notify_pos_update()

                self._send_cors_headers(200, "application/json")
                self.end_headers()
                resp = {"status": "SUCCESS", "action": action, "data": _GLOBAL_KIOSK_REF.get_live_kiosk_data() if _GLOBAL_KIOSK_REF else None}
                try:
                    self.wfile.write(json.dumps(resp).encode('utf-8'))
                except Exception:
                    pass

            elif path in ["/api/cache_offline", "/api/offline_sync"]:
                catalog = req_data.get("catalog") or req_data.get("products")
                if catalog and isinstance(catalog, list):
                    db_mgr = _GLOBAL_KIOSK_REF.db_manager if (_GLOBAL_KIOSK_REF and _GLOBAL_KIOSK_REF.db_manager) else _GLOBAL_DB_MANAGER
                    if db_mgr:
                        for prod in catalog:
                            db_mgr.upsert_product(prod)
                        print(f"[KIOSK API] 🔄 Offline cache received {len(catalog)} catalog items.")
                self._send_cors_headers(200, "application/json")
                self.end_headers()
                try:
                    self.wfile.write(json.dumps({"status": "SUCCESS", "message": "Offline cache synced"}).encode('utf-8'))
                except Exception:
                    pass
            else:
                self._send_cors_headers(404, "application/json")
                self.end_headers()
                try:
                    self.wfile.write(json.dumps({"error": "Not Found"}).encode('utf-8'))
                except Exception:
                    pass
        except Exception:
            pass

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
    def __init__(self, cam_index=None):
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
        logo_candidates = [
            SRC_DIR / "assets" / "images" / "branding" / "school no bg.png",
            PROJECT_ROOT / "src" / "assets" / "images" / "branding" / "school no bg.png",
            PROJECT_ROOT / "assets" / "images" / "branding" / "school no bg.png",
            SCRIPT_DIR / "school no bg.png",
            Path("src/assets/images/branding/school no bg.png"),
            Path("assets/images/branding/school no bg.png")
        ]
        logo_path = None
        for lc in logo_candidates:
            if Path(lc).exists():
                logo_path = str(Path(lc).resolve())
                break
        if logo_path and os.path.exists(logo_path):
            try:
                raw = pygame.image.load(logo_path).convert_alpha()
                h = 48
                w = int(raw.get_width() * (h / float(raw.get_height())))
                self.logo_surface = pygame.transform.smoothscale(raw, (w, h))
            except Exception:
                pass

        # Distance-Legible Typography System (Optimized for 2–3 ft standing distance)
        self.font_brand_sub = pygame.font.SysFont("Helvetica Neue", 13, bold=True)
        self.font_title = pygame.font.SysFont("Helvetica Neue", 22, bold=True)
        self.font_subtitle = pygame.font.SysFont("Helvetica Neue", 15)
        self.font_subtitle_bold = pygame.font.SysFont("Helvetica Neue", 15, bold=True)
        self.font_header = pygame.font.SysFont("Helvetica Neue", 18, bold=True)
        self.font_body = pygame.font.SysFont("Helvetica Neue", 16)
        self.font_body_bold = pygame.font.SysFont("Helvetica Neue", 16, bold=True)
        self.font_large = pygame.font.SysFont("Helvetica Neue", 32, bold=True)
        self.font_footer = pygame.font.SysFont("Helvetica Neue", 13)
        self.font_timer_large = pygame.font.SysFont("Helvetica Neue", 38, bold=True)
        self.font_timer_badge = pygame.font.SysFont("Helvetica Neue", 14, bold=True)
        self.font_badge = pygame.font.SysFont("Helvetica Neue", 13, bold=True)

        # State Variables
        self.current_state = STATE_IDLE
        self.active_student = None
        self.active_preorders = []
        self.cart_items = []
        self.total_amount = 0.0
        self.state_timer = 0.0
        self.scan_start_time = 0.0
        self.detection_history = deque(maxlen=30)
        self.status_message = "Tap Student RFID Card on Reader to Begin"
        self.latest_tray_image = ""
        self.cart_manual_override_lock = False
        self.error_message = None
        self._last_settlement_info = None

        # Vision Model Back-Office Configuration (novalunch_yolo-2.pt)
        self.conf_threshold = 0.80
        self.model = get_yolo_model()
        self.model_path = RESOLVED_YOLO_PATH
        if self.model_path:
            self.model_filename = Path(self.model_path).name
        else:
            self.model_filename = "novalunch_yolo-2.pt"

        # Stability & Motion
        self.countdown_remaining = 5.0
        self.last_tick_sec = 5
        self.motion_detected = False
        self.motion_voice_alerted = False
        self.greet_audio_spoken = False
        self.stable_start_time = 0.0
        self.stability_started_at = 0.0
        self.last_detection_hash = ""

        # Hardware Buffer
        self.rfid_scan_buffer = ""
        self.last_key_time = 0
        self.rfid_anti_passback_cache = {}
        self.last_rfid_tap_timestamp = 0

        # Pay Later State (Strict 3-Tap Flow without 5-second countdown timer)
        self.awaiting_pay_later_confirm = False   # True = waiting for RFID tap confirmation (no timer)
        self.pay_later_timer = 0.0

        # Subsystems
        self.camera_thread = CameraThread(cam_index=cam_index)
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

    @property
    def class_names(self):
        c = getattr(self.camera_thread, 'class_names', {})
        if not c:
            model = get_yolo_model()
            if model is not None:
                c = getattr(model, 'names', {})
        return c or {}

    @property
    def menu_catalog_by_ai_label(self):
        return getattr(self.camera_thread, 'menu_catalog_by_ai_label', {})

    @property
    def state(self):
        return STATE_NAMES.get(self.current_state, "IDLE")

    @state.setter
    def state(self, val):
        if isinstance(val, int):
            self.transition_to_state(val)
        elif isinstance(val, str):
            for k, v in STATE_NAMES.items():
                if v.upper() == val.upper():
                    self.transition_to_state(k)
                    break

    def speak_text(self, text):
        speak_text(text)

    def speak_prompt(self, text):
        speak_text(text)

    def stop_speech(self):
        stop_active_speech()

    def fetch_student_by_rfid(self, rfid_uid):
        try:
            if hasattr(self, 'supabase') and self.supabase:
                res = self.supabase.table('profiles').select('*').eq('rfid_uid', str(rfid_uid).strip()).maybeSingle().execute()
                if res and res.data:
                    fresh_student = res.data
                    self.db_manager.upsert_student(fresh_student)
                    return fresh_student
        except Exception as cloud_err:
            logger.warning(f"[CLOUD SYNC] Supabase read failed on RFID tap: {cloud_err}")
        return self.db_manager.fetch_student_by_rfid(rfid_uid)

    def get_model_metadata(self):
        classes_list = []
        model = getattr(self, 'model', None) or get_yolo_model()
        if model and hasattr(model, 'names'):
            names = model.names
            if isinstance(names, dict):
                classes_list = [names[k] for k in sorted(names.keys())]
            elif isinstance(names, list):
                classes_list = names

        # Calculate actual file size in MB
        model_size_mb = "115.4 MB"
        try:
            model_path = getattr(self, 'model_path', None) or RESOLVED_YOLO_PATH
            if model_path and os.path.exists(model_path):
                size_mb = os.path.getsize(model_path) / (1024 * 1024)
                model_size_mb = f"{size_mb:.1f} MB"
        except Exception:
            pass

        return {
            "filename": getattr(self, "model_filename", "novalunch_yolo-2.pt"),
            "size": model_size_mb,
            "class_count": len(classes_list),
            "classes": classes_list,
            "confidence_cutoff": float(getattr(self, "conf_threshold", 0.80)),
            "status": "Active" if len(classes_list) > 0 else "Standby"
        }

    def get_live_kiosk_data(self):
        """Returns JSON-serializable snapshot of live kiosk state for Cashier POS.

        Standardized payload (Wave 3 spec):
          - `cart_items`:         Normalized list with id/name/price/quantity fields for Cashier Order Tally.
                                  Populated from active YOLO detections or manual additions.
          - `cart`:               Raw internal cart_items list (backward compatibility).
          - `active_student`:     Top-level student field alias.
          - `total_amount`:       Rounded float total.
          - `state`:              Current state string ('IDLE', 'SCANNING', etc.)
          - `kiosk_state`:        Human-readable state string.
          - `student_new_balance`:New balance after deduction (present only on SETTLEMENT event).
          - `status`:             Always 'SUCCESS' when kiosk is alive.
        """
        detections = []
        ai_engine = "YOLOv8 Engine"
        fps = 60
        if hasattr(self, 'camera_thread') and self.camera_thread:
            # Always read directly from YOLO inference pipeline — never from a fallback
            detections = self.camera_thread.get_latest_detections()
            ai_engine, fps, _ = self.camera_thread.get_ai_status()

        # Settlement persistence: the cart is intentionally NOT blanked here. The settled
        # order stays in the payload so the Cashier POS Order Tally keeps showing it
        # through the settlement display; it is cleared by transition_to_state(STATE_IDLE).
        raw_cart = list(self.cart_items)

        # Standardized cart_items payload: id / name / price / quantity
        normalized_cart_items = [
            {
                "id":         str(item.get("id") or item.get("product_id") or item.get("name")),
                "product_id": str(item.get("product_id") or item.get("id") or item.get("name")),
                "name":       item.get("name", "Unknown Item"),
                "label":      item.get("label") or item.get("ai_label") or "",
                "category":   item.get("category", "ITEM"),
                "price":      float(item.get("price", 0.0)),
                "quantity":   int(item.get("quantity", item.get("qty", 1))),
                "qty":        int(item.get("quantity", item.get("qty", 1)))
            }
            for item in raw_cart
        ] if raw_cart else []

        # Canonical student projection merged over the raw profile so legacy consumers
        # (rfidUid, student_id_number, …) keep working alongside the documented fields.
        student_payload = None
        if getattr(self, "active_student", None):
            raw_student = dict(self.active_student)
            raw_student.update({
                "id":       raw_student.get("id") or raw_student.get("student_id") or raw_student.get("student_id_number"),
                "name":     raw_student.get("name") or raw_student.get("full_name"),
                "rfid_uid": raw_student.get("rfid_uid") or raw_student.get("rfidUid"),
                "balance":  float(raw_student.get("balance", 0.0) or 0.0)
            })
            student_payload = raw_student

        total_amount = float(round(self.total_amount, 2))

        payload = {
            "status": "SUCCESS",
            "state": self.state,
            "kiosk_state": STATE_NAMES.get(self.current_state, "UNKNOWN"),
            "current_state_id": self.current_state,
            "active_student": student_payload,
            "student": student_payload,
            # Standardized normalized cart sourced directly from YOLO inference
            "cart_items": normalized_cart_items,
            # `items` alias: parallel key consumed by the Cashier POS cart stream
            "items": normalized_cart_items,
            # Raw cart preserved for backward compatibility with legacy polling
            "cart": normalized_cart_items,
            "detections": detections,
            "ai_engine": ai_engine,
            "camera_online": True,
            "fps": fps,
            "total_amount": total_amount,
            "total": total_amount,
            "items_count": len(normalized_cart_items) if normalized_cart_items else 0,
            "countdown_remaining": round(self.countdown_remaining, 1),
            "status_message": self.status_message,
            "preorders_count": len(self.active_preorders) if self.active_preorders else 0,
            # Pay Later double-tap pending state for CFD display
            "awaiting_pay_later_confirm": getattr(self, 'awaiting_pay_later_confirm', False),
            "model_info": self.get_model_metadata(),
            "timestamp": time.time()
        }

        # Attach post-deduction wallet balance on SETTLEMENT so connected web
        # portals immediately refresh the virtual RFID pass without a reload.
        if self.current_state == STATE_SETTLEMENT and hasattr(self, '_last_settled_new_balance'):
            payload["student_new_balance"] = self._last_settled_new_balance
            payload["student_id_settled"] = getattr(self, '_last_settled_student_id', None)
            info = getattr(self, "_last_settlement_info", None)
            if info:
                payload["settlement"] = info
                payload["wallet_balance"] = info.get("remaining")
                payload["amount_paid"] = info.get("paid")

        return payload

    def notify_pos_update(self):
        """Broadcasts live cart/state update to all connected Cashier POS terminals."""
        payload = self.get_live_kiosk_data()
        # `cart_items` / `items` / `total` are always mirrored from the live cart —
        # including through SETTLEMENT, so the Cashier Order Tally holds the settled
        # order until the kiosk returns to STATE_IDLE and clears it.
        payload["cart_items"] = [
            {
                "id":         str(ci.get("id") or ci.get("product_id") or ci.get("name")),
                "product_id": str(ci.get("product_id") or ci.get("id") or ci.get("name")),
                "name":       ci.get("name", "Unknown Item"),
                "label":      ci.get("label") or ci.get("ai_label") or "",
                "category":   ci.get("category", "ITEM"),
                "price":      float(ci.get("price", 0.0)),
                "quantity":   int(ci.get("quantity", ci.get("qty", 1))),
                "qty":        int(ci.get("quantity", ci.get("qty", 1)))
            } for ci in self.cart_items
        ]
        payload["items"] = payload["cart_items"]
        payload["cart"] = payload["cart_items"]
        payload["total_amount"] = float(self.total_amount)
        payload["total"] = float(self.total_amount)
        payload["state"] = self.state
        payload["kiosk_state"] = STATE_NAMES.get(self.current_state, "UNKNOWN")
        broadcast_kiosk_event("kiosk_update", payload)

    def lookup_pos_item(self, raw_label):
        """Instance-level access to the module catalog resolver (used by the live sync)."""
        return lookup_pos_item(raw_label)

    def build_cart_snapshot(self, current_detections):
        """Projects one frame of YOLO detections onto the canonical POS cart shape.

        Detections are grouped by AI label so N objects of the same class collapse into a
        single line with `quantity == N`. A label is only admitted when it resolves to a
        priced, non-archived catalog product — an unresolved label is DROPPED rather than
        injected as a phantom line item, so it can never be charged to a student.
        """
        label_counts = {}
        label_seed = {}
        for det in current_detections or []:
            if isinstance(det, dict):
                lbl = str(det.get("ai_label") or det.get("label") or det.get("name") or "").strip().lower()
                seed = det
            else:
                lbl = str(det).strip().lower()
                seed = None
            if not lbl:
                continue
            label_counts[lbl] = label_counts.get(lbl, 0) + 1
            if lbl not in label_seed:
                label_seed[lbl] = seed

        synced_cart = []
        # Sorted by label for frame-to-frame determinism: unsorted dict order flips with
        # the YOLO output order, which would emit a spurious SSE broadcast every frame.
        for lbl in sorted(label_counts):
            count = int(label_counts[lbl])
            seed = label_seed.get(lbl) or {}
            # The camera thread already resolves detections to catalog products; only fall
            # back to the catalog resolver (an extra SQLite read) when it did not.
            item = seed if float(seed.get("price", 0.0) or 0.0) > 0.0 else (self.lookup_pos_item(lbl) or {})

            price = float(item.get("price", 0.0) or 0.0)
            prod_id = str(item.get("id") or item.get("product_id") or "").strip()
            if (price <= 0.0
                    or not prod_id
                    or item.get("requires_cashier_review")
                    or item.get("category") == "UNKNOWN"
                    or "unmapped" in prod_id.lower()):
                continue

            synced_cart.append({
                "id":         prod_id,
                "product_id": prod_id,
                "name":       item.get("name") or lbl.replace('_', ' ').title(),
                "label":      lbl,
                "ai_label":   lbl,
                "category":   item.get("category", "ITEM"),
                "price":      price,
                "stock":      int(item.get("stock", 50) or 0),
                "quantity":   count,
                "qty":        count
            })
        return synced_cart

    def sync_cart_from_detections(self, current_detections):
        """Mirror the live tray onto the Cashier POS Order Tally in real time.

        Runs on every camera frame while the tray is being scanned (STATE_SCANNING /
        STATE_STABILITY_COUNTDOWN) so the cashier sees the order build up immediately —
        without waiting for stability settlement or an RFID tap. Returns True when the
        cart actually changed and a broadcast was emitted.
        """
        synced_cart = self.build_cart_snapshot(current_detections)
        if synced_cart == self.cart_items:
            return False
        self.cart_items = synced_cart
        self.total_amount = round(sum(float(i.get('price', 0.0) or 0.0) * int(i.get('quantity', i.get('qty', 1)) or 1) for i in (self.cart_items or [])), 2)
        self.notify_pos_update()
        return True

    def _decrement_cloud_stock(self, p_id, q_deduct):
        """Supabase cloud layer of the dual stock decrement (best-effort, never raises).

        Prefers the in-process Supabase SDK, then falls back to a direct REST PATCH so the
        decrement still lands when the SDK client is unavailable. The `products_stock_sync`
        trigger mirrors `stock` into `stock_quantity` and flips availability server-side.
        """
        try:
            if not _is_uuid_like(p_id):
                logger.info(f"[STOCK DEDUCT] {p_id} is edge-local only; cloud decrement skipped")
                return
            if getattr(self, 'supabase', None):
                res = self.supabase.table("products").select("stock").eq("id", str(p_id)).maybeSingle().execute()
                if res and res.data:
                    current_stock = int(res.data.get("stock") or 0)
                    new_stock = max(0, current_stock - q_deduct)
                    self.supabase.table("products").update({"stock": new_stock}).eq("id", str(p_id)).execute()
                    logger.info(f"[STOCK DEDUCT] Supabase {p_id}: {current_stock} -> {new_stock}")
                    return
            get_url = f"{SUPABASE_URL}/rest/v1/products?id=eq.{urllib.parse.quote(str(p_id))}&select=id,stock"
            req = urllib.request.Request(get_url, headers={
                "apikey": SUPABASE_ANON_KEY,
                "Authorization": f"Bearer {SUPABASE_ANON_KEY}"
            })
            with urllib.request.urlopen(req, timeout=5) as resp:
                p_data = json.loads(resp.read().decode('utf-8'))
                if p_data and len(p_data) > 0:
                    cur_stk = int(p_data[0].get('stock') or 0)
                    n_stk = max(0, cur_stk - q_deduct)
                    patch_url = f"{SUPABASE_URL}/rest/v1/products?id=eq.{urllib.parse.quote(str(p_id))}"
                    p_req = urllib.request.Request(
                        patch_url,
                        data=json.dumps({"stock": n_stk}).encode('utf-8'),
                        headers={
                            "apikey": SUPABASE_ANON_KEY,
                            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                            "Content-Type": "application/json",
                            "Prefer": "return=minimal"
                        },
                        method="PATCH"
                    )
                    urllib.request.urlopen(p_req, timeout=5)
                    logger.info(f"[STOCK DEDUCT] Supabase REST {p_id}: {cur_stk} -> {n_stk}")
        except Exception as cloud_err:
            logger.warning(f"[STOCK DEDUCT WARN] Cloud stock update failed for {p_id}: {cloud_err}")

    def recalculate_total(self):
        valid_items = [
            it for it in self.cart_items 
            if float(it.get("price", 0.0) or 0.0) > 0.0
            and not it.get("requires_cashier_review")
            and it.get("category") != "UNKNOWN"
            and "unmapped" not in str(it.get("id", "")).lower()
            and "unmapped" not in str(it.get("name", "")).lower()
        ]
        self.cart_items = valid_items
        self.total_amount = round(sum(float(item.get("price", 0.0) or 0.0) * int(item.get("quantity", item.get("qty", 1)) or 1) for item in (self.cart_items or [])), 2)
        self.notify_pos_update()

    def execute_simulation_step(self, step):
        if step == 1:
            # Step 1: RFID Tap
            # No synthetic customer is ever injected. Until a real card resolves an
            # identity, active_student stays None and the session remains unregistered.
            if not self.active_student:
                self.active_student = None
            if self.active_student:
                self.active_preorders = self.db_manager.get_active_preorders(self.active_student.get("id"), self.active_student.get("name"))
                if self.active_preorders:
                    self.transition_to_state(STATE_PREORDER_ANNOUNCEMENT)
                else:
                    self.transition_to_state(STATE_GREET)
            else:
                self.transition_to_state(STATE_GREET)

        elif step == 2:
            # Step 2: AI Scan
            if not self.active_student:
                self.execute_simulation_step(1)
            self.cart_manual_override_lock = False
            self.transition_to_state(STATE_SCANNING)

        elif step == 3:
            # Step 3: Payment Confirmation
            # Cart MUST only contain items detected by YOLO — no phantom injection.
            # If cart is empty, stay in STATE_SCANNING and alert the student.
            if not self.active_student:
                self.execute_simulation_step(1)
            if not self.cart_items:
                self.status_message = "No items detected on counter. Please place food on the scanning platform."
                self.notify_pos_update()
                return
            self.cart_manual_override_lock = True
            self.transition_to_state(STATE_PAYMENT_CONFIRMATION)

        elif step == 4:
            # Step 4: Settlement
            if self.current_state == STATE_PAYMENT_CONFIRMATION:
                self.execute_rfid_checkout()
            else:
                self.transition_to_state(STATE_SETTLEMENT)

    def transition_to_state(self, new_state):
        self.current_state = new_state
        self.state_timer = time.time()

        if new_state == STATE_IDLE:
            stop_active_speech()
            self.active_student = None
            self.active_preorders = []
            self.cart_items = []
            self.total_amount = 0.0
            self.countdown_remaining = 5.0
            self.motion_detected = False
            self.motion_voice_alerted = False
            self.greet_audio_spoken = False
            self.stable_start_time = 0.0
            self.last_detection_hash = ""
            self.cart_manual_override_lock = False
            self.awaiting_pay_later_confirm = False
            self.error_message = None
            self.status_message = "Welcome to NovaLunch! Tap Student RFID Card to begin."

        elif new_state == STATE_PREORDER_ANNOUNCEMENT:
            # New identity: never inherit the previous customer's tray. Required now that
            # the settled cart survives into STATE_SETTLEMENT — a tap inside the thank-you
            # window would otherwise start the next session holding a paid order.
            self.cart_items = []
            self.total_amount = 0.0
            self.last_detection_hash = ""
            self.stable_start_time = 0.0
            st_name = self.active_student.get("name", "Student") if self.active_student else "Student"
            first_po = self.active_preorders[0] if self.active_preorders else {}
            item_name = first_po.get("name") or first_po.get("item") or "Reserved Meal"
            shelf_loc = first_po.get("shelf") or first_po.get("shelf_location") or "Shelf B2"
            self.status_message = f"🍱 ACTIVE PRE-ORDER FOUND: Collect from {shelf_loc}!"
            if not self.greet_audio_spoken:
                speak_text(f"Hello {st_name.split()[0]}! Your pre-order for {item_name} is ready at {shelf_loc}.")
                self.greet_audio_spoken = True

        elif new_state == STATE_GREET:
            # New session boundary — drop any cart carried over from a settled order.
            self.cart_items = []
            self.total_amount = 0.0
            self.last_detection_hash = ""
            self.stable_start_time = 0.0
            # No synthetic customer fallback: an unresolved session stays anonymous.
            if not self.active_student:
                self.active_student = None
            st_name = (self.active_student or {}).get("name") or None
            self.status_message = f"Hello {st_name}! Place food items on scanning platform." if st_name else "Tap Student RFID Card on Reader to Begin"
            self.stable_start_time = 0.0
            self.last_detection_hash = ""
            if not self.greet_audio_spoken:
                if st_name:
                    speak_text(f"Welcome {str(st_name).split()[0]}! Place your tray on the platform.")
                else:
                    speak_text("Please tap your student card on the reader to begin.")
                self.greet_audio_spoken = True

        elif new_state == STATE_SCANNING:
            self.countdown_remaining = 5.0
            self.stable_start_time = 0.0
            self.last_detection_hash = ""
            self.cart_manual_override_lock = False
            live_items = self.camera_thread.get_latest_detections()
            valid_items = self.build_cart_snapshot(live_items)
            if valid_items:
                self.cart_items = valid_items
                self.recalculate_total()
                self.status_message = f"AI Detected {len(self.cart_items)} item(s). Calibrating stability..."
            else:
                self.cart_items = []
                self.total_amount = 0.0
                st_name = (self.active_student or {}).get("name")
                if st_name:
                    bal = float(self.active_student.get("balance", 0.0) or self.active_student.get("wallet_balance", 0.0) or 0.0)
                    self.status_message = f"Welcome {st_name}! Balance: ₱{bal:.2f}. Place food on platform."
                else:
                    self.status_message = "⚠️ No items detected on counter. Please place food on the scanning platform."

            # Save snapshot
            try:
                trays_dir = str((SRC_DIR / "ai_engine" / "trays_queue").resolve())
                os.makedirs(trays_dir, exist_ok=True)
                student_id = self.active_student.get("id", "GUEST") if self.active_student else "GUEST"
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
            self.stability_started_at = time.time()
            self.countdown_remaining = 5.0
            self.last_tick_sec = 5
            self.motion_voice_alerted = False
            self.status_message = f"🟢 AI Scanning items (5.0s)... Hold tray steady"

        elif new_state == STATE_PAYMENT_CONFIRMATION:
            # Never lock an empty cart: an empty tray stays in STATE_SCANNING.
            if not self.cart_items:
                self.current_state = STATE_SCANNING
                self.state_timer = time.time()
                self.cart_manual_override_lock = False
                self.status_message = "⚠️ No items detected on counter. Please place food on the scanning platform."
                speak_text("No items detected on counter. Please place your food on the scanning platform.")
                self.notify_pos_update()
                return
            self.cart_manual_override_lock = True
            cnt = sum(i.get("qty", 1) for i in self.cart_items)
            self.status_message = f"🟢 Scanned {cnt} item(s) (₱{self.total_amount:.2f}) — Ready for Payment Confirmation"

        elif new_state == STATE_SETTLEMENT:
            self.status_message = "Payment have been confirmed please claim your order."

        elif new_state == STATE_ERROR:
            self.cart_items = []
            self.total_amount = 0.0
            self.cart_manual_override_lock = False
            self.status_message = getattr(self, "error_message", None) or "⚠️ UNREGISTERED RFID CARD — PLEASE REGISTER AT THE CANTEEN OFFICE"

        self.notify_pos_update()

    def execute_pay_later_checkout(self):
        """Zero-Touch Pay Later Settlement triggered by double-tap RFID (Wave 3)."""
        if not self.active_student or self.total_amount <= 0:
            return

        # Always clear any pending double-tap state on entry
        self.awaiting_pay_later_confirm = False

        # Check if Pay Later is permitted for this student
        if self.active_student.get("pay_later_allowance") is False or self.active_student.get("allow_pay_later") is False:
            self.status_message = "PAY LATER DISABLED — PARENT/ADMIN PERMISSION REQUIRED"
            speak_text("Pay later is disabled for this account. Please settle with cash or card reload.")
            self.notify_pos_update()
            return

        # Check credit limit ceiling
        cur_liability = float(self.active_student.get("credit_liability", self.active_student.get("pay_later_balance", 0.0)) or 0.0)
        limit = float(self.active_student.get("max_credit_limit", self.active_student.get("credit_limit", 300.0)) or 300.0)
        if cur_liability + self.total_amount > limit:
            self.status_message = f"PAY LATER CEILING REACHED (₱{limit:.2f} MAX) — SETTLEMENT REQUIRED"
            speak_text("Credit limit exceeded. Please settle account balance at cashier.")
            self.notify_pos_update()
            return

        # Check 5x Pay Later limit per student
        current_pay_later_count = self.active_student.get("pay_later_count", 0)
        if current_pay_later_count >= 5:
            self.status_message = "PAY LATER LIMIT REACHED (5/5 USED) — DEBT CLEARANCE REQUIRED"
            speak_text("Pay later limit reached. Please settle existing balance at cashier.")
            self.notify_pos_update()
            return

        student_id = str(self.active_student.get("id", "") or self.active_student.get("student_id_number", "STU"))
        st_name = self.active_student.get("name", "Student")
        tx_id = f"TXN_PAYLATER_{int(time.time())}_{student_id.replace('-', '')}"
        settled_amount = self.total_amount

        self.active_student["pay_later_count"] = current_pay_later_count + 1
        self.active_student["pay_later_balance"] = cur_liability + settled_amount
        self.active_student["credit_liability"] = cur_liability + settled_amount

        # Persist updated pay-later count & liability to accounts cache
        students = self.db_manager.load_accounts()
        for s in students:
            if s.get("student_id_number") == student_id or s.get("id") == student_id:
                s["pay_later_count"] = self.active_student["pay_later_count"]
                s["pay_later_balance"] = self.active_student["pay_later_balance"]
                s["credit_liability"] = self.active_student["pay_later_balance"]
                break
        self.db_manager.save_accounts(students)

        self.db_manager.record_transaction(tx_id, student_id, self.cart_items, settled_amount, self.latest_tray_image, payment_method="pay_later")

        # Immediate cloud order synchronization
        if hasattr(self.db_manager, 'sync_worker') and self.db_manager.sync_worker:
            threading.Thread(target=self.db_manager.sync_worker.sync_pending_transactions, daemon=True).start()

        # Update Supabase profiles.credit_liability directly
        def _update_cloud_pay_later():
            try:
                patch_url = f"{SUPABASE_URL}/rest/v1/profiles?student_id_number=eq.{urllib.parse.quote(student_id)}"
                patch_req = urllib.request.Request(
                    patch_url,
                    data=json.dumps({
                        "credit_liability": cur_liability + settled_amount,
                        "pay_later_count": current_pay_later_count + 1
                    }).encode('utf-8'),
                    headers={
                        "apikey": SUPABASE_ANON_KEY,
                        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                        "Content-Type": "application/json",
                        "Prefer": "return=minimal"
                    },
                    method="PATCH"
                )
                urllib.request.urlopen(patch_req, timeout=5)
            except Exception as pl_err:
                logger.warning(f"[PAY LATER WARN] Cloud credit_liability update failed: {pl_err}")
        threading.Thread(target=_update_cloud_pay_later, daemon=True).start()

        # Dual-layer stock decrement for pay-later settlement
        for item in list(self.cart_items):
            prod_id = item.get("id") or item.get("product_id")
            qty = int(item.get("quantity") or item.get("qty") or 1)
            if prod_id:
                self.db_manager.decrement_product_stock(prod_id, qty)

        pay_later_count = self.active_student.get('pay_later_count', current_pay_later_count + 1)
        self.status_message = f"SAFETY NET APPROVED: P{settled_amount:.2f} Charged to Pay Later ({st_name}) [{pay_later_count}/5]"
        if self.sounds.get("success"):
            try:
                self.sounds["success"].play()
            except Exception:
                pass
        speak_text(f"Safety net approved. Charged to pay later. Thank you {st_name.split()[0]}!")

        # Settlement persistence: keep the settled cart in the broadcast so the Cashier
        # Order Tally holds the order through the settlement display. transition_to_state
        # (STATE_IDLE) after the thank-you screen clears it.
        self.detection_history.clear()
        self.last_detection_hash = ""
        # Transition BEFORE clearing active_student so the settlement payload is complete
        self.transition_to_state(STATE_SETTLEMENT)
        self.active_student = None
        self.notify_pos_update()          # Broadcast settlement event with the settled cart

    def execute_rfid_checkout(self):
        """Hardened 2-Tap RFID Settlement: Deducts balance, records transaction, and settles order."""
        if not self.cart_items or self.total_amount <= 0.0:
            self.status_message = "EMPTY TRAY — Place meal items on platform before tapping card."
            self.notify_pos_update()
            return

        if not self.active_student or not self.active_student.get('id'):
            logger.warning("[RFID] Unregistered card in checkout")
            self.state = STATE_ERROR
            self.error_message = "⚠️ Unregistered RFID Card. Please register card at office."
            self.status_message = self.error_message
            self.speak_text("Unregistered card. Please register at the canteen office.")
            self.notify_pos_update()
            return

        # Clear any pending Pay Later confirmation state
        self.awaiting_pay_later_confirm = False
        self.cart_manual_override_lock = False

        # ── Balance Calculation ────────────────────────────────────────────────
        previous_balance = float(self.active_student.get("balance") or self.active_student.get("wallet_balance") or 0.0)
        charge_amount = float(self.total_amount)
        new_balance = max(0.0, round(previous_balance - charge_amount, 2))

        student_id = str(self.active_student.get("id") or self.active_student.get("student_id_number") or "STU-2026")
        student_uuid = str(self.active_student.get("uuid") or "").strip()
        st_name = self.active_student.get("name", "Student")
        rfid_uid = str(self.active_student.get("rfidUid") or self.active_student.get("rfid_uid") or "").strip()

        if previous_balance < charge_amount:
            self.status_message = f"INSUFFICIENT BALANCE (Req P{charge_amount:.2f}, Bal P{previous_balance:.2f}) — USE PAY LATER"
            speak_text(f"Insufficient balance for {st_name.split()[0]}. Please use pay later at cashier.")
            self.notify_pos_update()
            return

        # Update active student balance in memory immediately
        self.active_student["balance"] = new_balance
        self.active_student["wallet_balance"] = new_balance

        # ── Local SQLite: Deduct balance in accounts JSON cache and students table ──
        self.db_manager.deduct_student_balance(student_id, charge_amount)
        self.db_manager.update_student_balance_sqlite(rfid_uid, student_id, new_balance)

        tx_id = f"TXN_{int(time.time())}_{student_id.replace('-', '')}"
        self.db_manager.record_transaction(
            tx_id, student_id, self.cart_items, charge_amount,
            self.latest_tray_image, payment_method="rfid"
        )

        # Immediate cloud order synchronization
        if hasattr(self.db_manager, 'sync_worker') and self.db_manager.sync_worker:
            threading.Thread(target=self.db_manager.sync_worker.sync_pending_transactions, daemon=True).start()

        # ── Supabase Cloud: Update wallet balance immediately (non-blocking) ────
        def _update_supabase_balance():
            try:
                # Prefer the atomic Supabase RPC to avoid race conditions
                if student_uuid:
                    rpc_url = f"{SUPABASE_URL}/rest/v1/rpc/fn_deduct_wallet_balance"
                    rpc_req = urllib.request.Request(
                        rpc_url,
                        data=json.dumps({"p_user_id": student_uuid, "p_amount": charge_amount}).encode('utf-8'),
                        headers={
                            "apikey": SUPABASE_ANON_KEY,
                            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                            "Content-Type": "application/json"
                        },
                        method="POST"
                    )
                    with urllib.request.urlopen(rpc_req, timeout=5) as rpc_resp:
                        if rpc_resp.status in (200, 201, 204):
                            print(f"[CHECKOUT] Supabase wallet deducted via RPC for UUID={student_uuid}, amount=P{charge_amount:.2f}")
                            return
                # Fallback: direct PATCH on the profiles row. NOTE: the cloud
                # schema stores the wallet balance in `profiles.balance` (mirrored
                # into `wallets.balance`) — there is no `wallet_balance` column,
                # so PATCHing one would silently no-op.
                if student_id:
                    patch_url = f"{SUPABASE_URL}/rest/v1/profiles?student_id_number=eq.{urllib.parse.quote(student_id)}"
                    patch_req = urllib.request.Request(
                        patch_url,
                        data=json.dumps({"balance": new_balance}).encode('utf-8'),
                        headers={
                            "apikey": SUPABASE_ANON_KEY,
                            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                            "Content-Type": "application/json",
                            "Prefer": "return=minimal"
                        },
                        method="PATCH"
                    )
                    with urllib.request.urlopen(patch_req, timeout=5) as patch_resp:
                        if patch_resp.status in (200, 204):
                            print(f"[CHECKOUT] Supabase profiles.balance updated for {student_id}, new_balance=P{new_balance:.2f}")
                            # Keep the mirrored wallets row in sync when it exists
                            if student_uuid:
                                try:
                                    w_url = f"{SUPABASE_URL}/rest/v1/wallets?user_id=eq.{urllib.parse.quote(student_uuid)}"
                                    w_req = urllib.request.Request(
                                        w_url,
                                        data=json.dumps({"balance": new_balance}).encode('utf-8'),
                                        headers={
                                            "apikey": SUPABASE_ANON_KEY,
                                            "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
                                            "Content-Type": "application/json",
                                            "Prefer": "return=minimal"
                                        },
                                        method="PATCH"
                                    )
                                    with urllib.request.urlopen(w_req, timeout=5) as w_resp:
                                        if w_resp.status in (200, 204):
                                            print(f"[CHECKOUT] Supabase wallets.balance synced for UUID={student_uuid}")
                                except Exception as w_err:
                                    print(f"[CHECKOUT NOTICE] wallets mirror skipped: {w_err}")
            except Exception as e:
                print(f"[CHECKOUT WARN] Supabase balance update deferred (will sync via OfflineSyncWorker): {e}")
        threading.Thread(target=_update_supabase_balance, daemon=True).start()

        # ── Dual-Layer Stock Decrement: local SQLite + Supabase cloud ──────────
        # Runs immediately after the balance deduction so an edge-settled sale is
        # reflected in inventory even when the cloud is unreachable (the local SQLite
        # write is synchronous; the cloud write is best-effort on a worker thread).
        for item in list(self.cart_items):
            p_id = item.get("id") or item.get("product_id")
            qty = int(item.get("quantity") or item.get("qty") or 1)
            if not p_id:
                continue
            # Layer 1: local SQLite edge catalog (authoritative while offline)
            self.db_manager.decrement_product_stock(p_id, qty)
            # Layer 2: Supabase cloud catalog
            threading.Thread(target=self._decrement_cloud_stock, args=(str(p_id), qty), daemon=True).start()

        # ── CFD Settlement Status: Show paid amount + remaining balance ─────────
        self.status_message = (
            f"✅ PAYMENT APPROVED | Paid: P{charge_amount:.2f} | "
            f"Remaining Balance: P{new_balance:.2f} | Student: {st_name}"
        )

        # Structured settlement record consumed by the CFD settlement popup and
        # broadcast to every connected web portal.
        self._last_settlement_info = {
            "paid": round(charge_amount, 2),
            "remaining": round(new_balance, 2),
            "previous_balance": round(previous_balance, 2),
            "student_name": st_name,
            "student_id": student_id,
            "rfid_uid": rfid_uid
        }

        if self.sounds.get("success"):
            try:
                self.sounds["success"].play()
            except Exception:
                pass

        # ── Voice Feedback: Paid amount + remaining balance ────────────────────
        speak_text(
            f"Payment approved. Paid {int(charge_amount)} pesos. "
            f"Remaining balance {int(new_balance)} pesos."
        )

        # Store settlement metadata so get_live_kiosk_data can attach it to the SETTLEMENT event
        self._last_settled_new_balance = new_balance
        self._last_settled_student_id = student_id

        # ── Settlement Persistence: broadcast WITH the settled cart intact ──────
        # The Cashier POS Order Tally must keep showing the paid order while the CFD
        # displays the settlement screen. self.cart_items is deliberately left intact;
        # it is cleared by transition_to_state(STATE_IDLE) after the thank-you screen,
        # whose IDLE broadcast is what empties the tally.
        self.detection_history.clear()
        self.last_detection_hash = ""
        # Transition BEFORE clearing active_student so student_new_balance is in the broadcast
        self.transition_to_state(STATE_SETTLEMENT)
        self.active_student = None
        self.notify_pos_update()   # Broadcast settlement event with student_new_balance

    def handle_rfid_tap(self, scanned_uid=None):
        now = time.time()
        if scanned_uid:
            clean = str(scanned_uid).strip().replace("NL-QR-", "").replace("QR-", "")
            last_tap = self.rfid_anti_passback_cache.get(clean, 0)
            if now - last_tap < 1.0:
                return  # Hardware debounce
            self.rfid_anti_passback_cache[clean] = now

            # ── Payment Settlement Tap (Tap 2 / Tap 3) ───────────────────────────
            # Active student is set, cart has items, and student taps card to pay or confirm Pay Later.
            is_payment_tap = (
                self.active_student is not None
                and (
                    self.current_state == STATE_PAYMENT_CONFIRMATION
                    or (self.current_state in [STATE_SCANNING, STATE_STABILITY_COUNTDOWN] and len(self.cart_items) > 0 and self.total_amount > 0)
                )
            )

            if is_payment_tap:
                # Ensure cart is locked and state is in STATE_PAYMENT_CONFIRMATION
                if self.current_state != STATE_PAYMENT_CONFIRMATION:
                    self.cart_manual_override_lock = True
                    self.transition_to_state(STATE_PAYMENT_CONFIRMATION)

                active_uid = str(self.active_student.get("rfidUid") or self.active_student.get("rfid_uid") or "").strip()
                active_id = str(self.active_student.get("id") or self.active_student.get("student_id_number") or "").strip()

                is_match = False
                if active_uid and (clean.upper() == active_uid.upper() or clean.lstrip('0') == active_uid.lstrip('0')):
                    is_match = True
                elif clean == active_id:
                    is_match = True
                else:
                    scanned_student = self.fetch_student_by_rfid(clean)
                    if not scanned_student or not scanned_student.get('id'):
                        logger.warning(f"[RFID] Unregistered card tapped: {clean}")
                        self.state = STATE_ERROR
                        self.status_message = f"⚠️ Unregistered RFID Card ({clean}). Please register card at office."
                        self.speak_prompt("Unregistered card. Please register at the canteen office.")
                        self.notify_pos_update()
                        return
                    if scanned_student and (scanned_student.get("id") == self.active_student.get("id") or scanned_student.get("student_id_number") == self.active_student.get("student_id_number")):
                        is_match = True

                if is_match:
                    curr_bal = float(self.active_student.get("balance", 0.0) or self.active_student.get("wallet_balance", 0.0) or 0.0)

                    if curr_bal >= self.total_amount:
                        # Sufficient balance — proceed with standard RFID settlement
                        self.awaiting_pay_later_confirm = False
                        self.execute_rfid_checkout()
                        return
                    else:
                        # Insufficient balance — check Pay Later eligibility
                        credit_liability = float(self.active_student.get('credit_liability', self.active_student.get('pay_later_balance', 0.0)) or 0.0)
                        credit_limit = float(self.active_student.get('max_credit_limit', self.active_student.get('credit_limit', 300.0)) or 300.0)
                        projected_debt = credit_liability + self.total_amount
                        allow_pay_later = (
                            self.active_student.get('allow_pay_later', True) is not False
                            and self.active_student.get('pay_later_allowance', True) is not False
                        )
                        current_pay_later_count = int(self.active_student.get("pay_later_count", 0) or 0)

                        if allow_pay_later and projected_debt <= credit_limit and current_pay_later_count < 5:
                            if not getattr(self, 'awaiting_pay_later_confirm', False):
                                # First tap with insufficient funds (Tap 2): enter persistent confirmation without timer
                                self.awaiting_pay_later_confirm = True
                                self.status_message = (
                                    f"Insufficient balance (₱{curr_bal:.2f}). "
                                    f"Tap your RFID card again to charge ₱{self.total_amount:.2f} to Pay Later emergency balance."
                                )
                                # Spoken prompt without timer
                                self.speak_prompt("Insufficient balance. Tap your RFID card again to confirm Pay Later.")
                                self.notify_pos_update()
                                return
                            else:
                                # Second tap (Tap 3): student confirmed intent to use Pay Later
                                self.awaiting_pay_later_confirm = False
                                self.execute_pay_later_checkout()
                                return
                        else:
                            # Exceeded credit ceiling or disabled
                            if not allow_pay_later:
                                self.status_message = "Pay Later is disabled for this student account."
                                self.speak_prompt("Pay later is disabled for this account.")
                            elif current_pay_later_count >= 5:
                                self.status_message = "Pay Later emergency limit (5 meals) reached."
                                self.speak_prompt("Pay later meal limit reached. Please reload your account.")
                            else:
                                self.status_message = f"Credit limit exceeded (Limit: ₱{credit_limit:.2f}, Balance: ₱{curr_bal:.2f})."
                                self.speak_prompt("Credit limit reached. Please reload your account.")
                            self.awaiting_pay_later_confirm = False
                            self.notify_pos_update()
                            return
                else:
                    self.status_message = "TRANSACTION IN PROGRESS — PLEASE TAP WITH THE SAME CARD TO CONFIRM"
                    self.speak_prompt("Transaction in progress. Please tap with the same student card.")
                    self.notify_pos_update()
                    return

            # Prevent mid-transaction overwrite by another card during settlement
            if self.current_state == STATE_SETTLEMENT and self.active_student:
                return

            # Cart Latching Rule: an RFID tap during scan/stability must never
            # synthesize cart items. With 0 detected items we stay in STATE_SCANNING.
            if self.current_state in [STATE_SCANNING, STATE_STABILITY_COUNTDOWN] and not self.cart_items:
                self.transition_to_state(STATE_SCANNING)
                self.status_message = "⚠️ No items detected on counter. Please place food on the scanning platform."
                self.speak_prompt("No items detected on counter. Please place your food on the scanning platform.")
                self.notify_pos_update()
                return

            # ── Tap 1 (Identify & Start): Hardware RFID resolution ────────────────
            student = self.fetch_student_by_rfid(clean)
            if not student or not student.get('id'):
                logger.warning(f"[RFID] Unregistered card tapped: {clean}")
                self.state = STATE_ERROR
                self.status_message = f"⚠️ Unregistered RFID Card ({clean}). Please register card at office."
                self.speak_prompt("Unregistered card. Please register at the canteen office.")
                self.notify_pos_update()
                return

            self.active_student = student
            self.cart_manual_override_lock = False
            self.awaiting_pay_later_confirm = False
            bal = float(student.get("balance", 0.0) or student.get("wallet_balance", 0.0) or 0.0)
            student.setdefault("wallet_balance", bal)
            st_name = student.get('name', 'Student')

            self.active_preorders = self.db_manager.get_active_preorders(student.get("id"), student.get("name"))
            if self.active_preorders:
                self.transition_to_state(STATE_PREORDER_ANNOUNCEMENT)
            else:
                self.transition_to_state(STATE_SCANNING)
                if bal <= 0:
                    self.status_message = f"Welcome {st_name}! Low/Zero Balance (₱{bal:.2f}). Place food on platform."
                else:
                    self.status_message = f"Welcome {st_name}! Balance: ₱{bal:.2f}. Place food on platform."
                self.speak_prompt(f"Welcome {str(st_name).split()[0]}! Balance is {int(bal)} pesos. Please place your food on the scanning platform.")
            self.notify_pos_update()
            return

        # Keyboard / simulation step navigation (requires explicit simulation advance)
        if self.current_state == STATE_IDLE:
            self.status_message = "⚠️ Please tap an RFID badge to begin transaction."
            self.notify_pos_update()
        elif self.current_state == STATE_ERROR:
            self.transition_to_state(STATE_IDLE)
        elif self.current_state == STATE_PREORDER_ANNOUNCEMENT:
            self.transition_to_state(STATE_GREET)
        elif self.current_state == STATE_GREET:
            self.transition_to_state(STATE_SCANNING)
        elif self.current_state == STATE_SCANNING:
            if len(self.cart_items) > 0 and self.total_amount > 0:
                self.transition_to_state(STATE_STABILITY_COUNTDOWN)
            else:
                # 0 detected items — never lock an empty cart, stay in STATE_SCANNING
                self.status_message = "⚠️ No items detected on counter. Please place food on the scanning platform."
                speak_text("No items detected on counter. Please place your food on the scanning platform.")
                self.notify_pos_update()
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            self.cart_manual_override_lock = True
            self.transition_to_state(STATE_PAYMENT_CONFIRMATION)
        elif self.current_state == STATE_PAYMENT_CONFIRMATION:
            self.execute_rfid_checkout()
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
            st_name = self.active_student.get("name", "Student")
            st_id = self.active_student.get("id", "")
            bal = float(self.active_student.get("balance", 0.0) or 0.0)

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

                # Draw Boundary Reticles for all detected food items (both active and standby)
                detections = self.camera_thread.get_latest_detections() or self.cart_items
                if detections:
                    h_f, w_f = cam_frame.shape[:2]
                    scale_x = 682.0 / float(w_f)
                    scale_y = 410.0 / float(h_f)

                    is_active_session = (self.current_state != STATE_IDLE and self.active_student is not None)

                    for item in detections:
                        if not item or not item.get("name"):
                            continue
                        if float(item.get("price", 0.0) or 0.0) <= 0.0:
                            continue
                        if item.get("requires_cashier_review") or item.get("category") == "UNKNOWN":
                            continue
                        if "unmapped" in str(item.get("id", "")).lower() or "unmapped" in str(item.get("name", "")).lower():
                            continue

                        bx, by, bw, bh = item.get("bbox", [100, 100, 150, 150])
                        rx = max(34, min(34 + 682 - 40, 34 + int(bx * scale_x)))
                        ry = max(150, min(150 + 410 - 30, 150 + int(by * scale_y)))
                        rw = max(40, min(682 - (rx - 34), int(bw * scale_x)))
                        rh = max(30, min(410 - (ry - 150), int(bh * scale_y)))

                        box_color = COLOR_ROSE_VIBRANT if is_active_session else COLOR_CYAN_HUD
                        pygame.draw.rect(self.screen, box_color, (rx, ry, rw, rh), width=2, border_radius=6)

                        # High-tech corner bracket notches
                        notch = min(12, min(rw, rh) // 3)
                        notch_color = COLOR_WHITE if is_active_session else COLOR_GOLD_ACCENT
                        pygame.draw.line(self.screen, notch_color, (rx, ry), (rx + notch, ry), 3)
                        pygame.draw.line(self.screen, notch_color, (rx, ry), (rx, ry + notch), 3)
                        pygame.draw.line(self.screen, notch_color, (rx + rw, ry), (rx + rw - notch, ry), 3)
                        pygame.draw.line(self.screen, notch_color, (rx + rw, ry), (rx + rw, ry + notch), 3)
                        pygame.draw.line(self.screen, notch_color, (rx, ry + rh), (rx + notch, ry + rh), 3)
                        pygame.draw.line(self.screen, notch_color, (rx, ry + rh), (rx, ry + rh - notch), 3)
                        pygame.draw.line(self.screen, notch_color, (rx + rw, ry + rh), (rx + rw - notch, ry + rh), 3)
                        pygame.draw.line(self.screen, notch_color, (rx + rw, ry + rh), (rx + rw, ry + rh - notch), 3)

                        conf_pct = int(item.get('conf', 0.95) * 100)
                        tag_str = f" {item.get('name', 'Item')} ({conf_pct}%) • ₱{float(item.get('price', 0.0) or 0.0):.2f} "
                        tag_surf = self.font_subtitle_bold.render(tag_str, True, COLOR_WHITE)
                        tag_y = ry - 24 if ry >= 174 else ry + rh + 2
                        tag_bg = pygame.Rect(rx, tag_y, tag_surf.get_width() + 6, 22)
                        tag_bg_color = COLOR_MAROON_DARK if is_active_session else (15, 23, 42)
                        pygame.draw.rect(self.screen, tag_bg_color, tag_bg, border_radius=4)
                        self.screen.blit(tag_surf, (rx + 3, tag_y + 2))

                # In Standby mode, show sleek status badge overlay
                if self.current_state == STATE_IDLE:
                    if detections:
                        standby_badge = self.font_subtitle_bold.render(
                            f"🟢 AI FOOD DETECTED ({len(detections)}) • TAP STUDENT RFID CARD TO CHECKOUT",
                            True, COLOR_GOLD_LIGHT
                        )
                    else:
                        standby_badge = self.font_subtitle_bold.render(
                            "STANDBY MODE • PLACE TRAY OR TAP STUDENT RFID CARD",
                            True, COLOR_GOLD_LIGHT
                        )
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
        elif self.current_state == STATE_PAYMENT_CONFIRMATION:
            self.render_payment_confirmation_banner(video_area)
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

    def render_payment_confirmation_banner(self, video_area):
        if getattr(self, 'awaiting_pay_later_confirm', False):
            banner = pygame.Rect(video_area.centerx - 270, video_area.centery - 45, 540, 90)
            pygame.draw.rect(self.screen, COLOR_AMBER_BG, banner, border_radius=16)
            pygame.draw.rect(self.screen, COLOR_GOLD_ACCENT, banner, width=2, border_radius=16)
            t1 = self.font_large.render("⚠️ INSUFFICIENT WALLET BALANCE", True, COLOR_MAROON_DARK)
            t2 = self.font_subtitle_bold.render("Tap RFID Card Again to Confirm Pay Later", True, COLOR_MAROON_HEADER)
            self.screen.blit(t1, (banner.centerx - t1.get_width() // 2, banner.y + 14))
            self.screen.blit(t2, (banner.centerx - t2.get_width() // 2, banner.y + 50))
            return

        banner = pygame.Rect(video_area.centerx - 230, video_area.centery - 40, 460, 80)
        pygame.draw.rect(self.screen, COLOR_EMERALD_BG, banner, border_radius=16)
        pygame.draw.rect(self.screen, COLOR_EMERALD, banner, width=2, border_radius=16)
        t1 = self.font_large.render("✓ TRAY SCANNED & LOCKED", True, COLOR_EMERALD)
        t2 = self.font_subtitle_bold.render("Tap Student RFID Card to Confirm Payment", True, COLOR_TEXT_MAIN)
        self.screen.blit(t1, (banner.centerx - t1.get_width() // 2, banner.y + 12))
        self.screen.blit(t2, (banner.centerx - t2.get_width() // 2, banner.y + 48))

    def render_settlement_banner(self, video_area):
        # Two-line layout: title, paid amount, remaining balance, student subtitle
        banner = pygame.Rect(video_area.centerx - 290, video_area.centery - 78, 580, 156)
        pygame.draw.rect(self.screen, COLOR_EMERALD_BG, banner, border_radius=18)
        pygame.draw.rect(self.screen, COLOR_EMERALD, banner, width=2, border_radius=18)

        info = getattr(self, "_last_settlement_info", None) or {}

        t1 = self.font_large.render("\u2705 PAYMENT APPROVED", True, COLOR_EMERALD)
        self.screen.blit(t1, (banner.centerx - t1.get_width() // 2, banner.y + 12))

        if info:
            t2 = self.font_subtitle_bold.render(f"Paid: \u20B1{float(info.get('paid', 0.0)):.2f}", True, COLOR_TEXT_MAIN)
            t3 = self.font_subtitle_bold.render(
                f"Remaining Balance: \u20B1{float(info.get('remaining', 0.0)):.2f}", True, COLOR_TEXT_MAIN
            )
            t4 = self.font_brand_sub.render(f"Student: {info.get('student_name', 'Student')}", True, COLOR_EMERALD)
        else:
            t2 = self.font_subtitle_bold.render("Payment confirmed. Please claim your order.", True, COLOR_TEXT_MAIN)
            t3 = self.font_brand_sub.render("Enjoy your meal!", True, COLOR_EMERALD)
            t4 = None

        self.screen.blit(t2, (banner.centerx - t2.get_width() // 2, banner.y + 56))
        self.screen.blit(t3, (banner.centerx - t3.get_width() // 2, banner.y + 84))
        if t4:
            self.screen.blit(t4, (banner.centerx - t4.get_width() // 2, banner.y + 116))

    def render_toolbar(self):
        """Renders an interactive, guided 3-step progress bar for students."""
        # Step 1: Tap ID
        if self.active_student is not None or self.current_state in [
            STATE_GREET, STATE_PREORDER_ANNOUNCEMENT, STATE_SCANNING,
            STATE_STABILITY_COUNTDOWN, STATE_PAYMENT_CONFIRMATION, STATE_SETTLEMENT
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
        if self.current_state in [STATE_PAYMENT_CONFIRMATION, STATE_SETTLEMENT] or (
            len(self.cart_items) > 0 and self.cart_manual_override_lock
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

        # Step 3: Cashier Pay / Confirmation
        if self.current_state == STATE_SETTLEMENT:
            s3_state = "DONE"
            s3_sub = f"Paid ₱{self.total_amount:.2f}"
        elif self.current_state == STATE_PAYMENT_CONFIRMATION:
            s3_state = "ACTIVE"
            s3_sub = f"Pay ₱{self.total_amount:.2f}"
        elif len(self.cart_items) > 0 and self.current_state != STATE_IDLE:
            s3_state = "PENDING"
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

        standby_detections = aggregate_detections(self.camera_thread.get_latest_detections()) if self.current_state == STATE_IDLE else []
        valid_cart = [
            it for it in self.cart_items 
            if float(it.get("price", 0.0) or 0.0) > 0.0
            and not it.get("requires_cashier_review")
            and it.get("category") != "UNKNOWN"
            and "unmapped" not in str(it.get("id", "")).lower()
            and "unmapped" not in str(it.get("name", "")).lower()
        ]
        if self.current_state == STATE_IDLE and standby_detections:
            for idx, item in enumerate(standby_detections[:5]):
                row_y = 200 + (idx * 44)
                if idx % 2 == 0:
                    pygame.draw.rect(self.screen, COLOR_CARD_ALT, (775, row_y - 2, 460, 38), border_radius=6)
                cat_tag = self.font_brand_sub.render(f"[{item.get('category', 'ITEM')}]", True, COLOR_CYAN_HUD)
                self.screen.blit(cat_tag, (785, row_y + 9))

                name = self.font_body_bold.render(item.get("name", "Item"), True, COLOR_TEXT_MAIN)
                qty = self.font_body.render(f"x{item.get('qty', 1)}", True, COLOR_TEXT_MAIN)
                price_val = float(item.get('price', 0.0) or 0.0)
                price = self.font_body_bold.render(f"₱{price_val * int(item.get('qty', 1) or 1):.2f}", True, COLOR_GOLD_ACCENT)

                self.screen.blit(name, (840, row_y + 8))
                self.screen.blit(qty, (1065, row_y + 8))
                self.screen.blit(price, (1165, row_y + 8))

            auth_hint = self.font_subtitle_bold.render("🟢 Food Detected • Tap Student RFID to Authenticate & Pay", True, COLOR_EMERALD)
            self.screen.blit(auth_hint, (750 + (510 - auth_hint.get_width()) // 2, 435))
        elif not valid_cart:
            empty = self.font_body.render("Standby Mode: Tap Student RFID Card", True, COLOR_TEXT_MUTED)
            self.screen.blit(empty, (750 + (510 - empty.get_width()) // 2, 280))
            hint = self.font_subtitle.render("Place food items on counter after card is tapped.", True, COLOR_TEXT_MUTED)
            self.screen.blit(hint, (750 + (510 - hint.get_width()) // 2, 308))
        else:
            for idx, item in enumerate(valid_cart[:6]):
                row_y = 200 + (idx * 44)
                if idx % 2 == 0:
                    pygame.draw.rect(self.screen, COLOR_CARD_ALT, (775, row_y - 2, 460, 38), border_radius=6)
                cat_tag = self.font_brand_sub.render(f"[{item.get('category', 'ITEM')}]", True, COLOR_GOLD_ACCENT)
                self.screen.blit(cat_tag, (785, row_y + 9))

                name = self.font_body_bold.render(item.get("name", "Item"), True, COLOR_TEXT_MAIN)
                qty = self.font_body.render(f"x{item.get('qty', 1)}", True, COLOR_TEXT_MAIN)
                price_val = float(item.get('price', 0.0) or 0.0)
                price = self.font_body_bold.render(f"₱{price_val * int(item.get('qty', 1) or 1):.2f}", True, COLOR_ROSE_VIBRANT)

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
        if getattr(self, 'awaiting_pay_later_confirm', False):
            bg, txt, fg = COLOR_GOLD_ACCENT, "Insufficient Balance — Tap RFID Card Again to Confirm Pay Later", COLOR_MAROON_DARK
        elif self.current_state == STATE_IDLE:
            bg, txt, fg = COLOR_CARD_ALT, "Tap Student RFID Card to begin...", COLOR_TEXT_MUTED
        elif self.current_state in [STATE_GREET, STATE_SCANNING] and len(self.cart_items) == 0:
            bg, txt, fg = COLOR_MAROON_HEADER, "AI Overhead Vision Scanning Active...", COLOR_WHITE
        elif self.current_state == STATE_STABILITY_COUNTDOWN:
            bg = COLOR_AMBER_BG if self.motion_detected else COLOR_ROSE_VIBRANT
            txt = "⚠️ Motion Detected — Keep Hands Off" if self.motion_detected else f"⏳ AI Scanning ({self.countdown_remaining:.1f}s remaining)"
            fg = COLOR_MAROON_HEADER if self.motion_detected else COLOR_WHITE
        elif self.current_state == STATE_PAYMENT_CONFIRMATION:
            bg, txt, fg = COLOR_EMERALD, "✓ Cart Locked — Tap RFID Card to Confirm", COLOR_WHITE
        elif len(self.cart_items) > 0 and self.current_state != STATE_SETTLEMENT:
            bg, txt, fg = COLOR_EMERALD, "✓ Scanned Items Ready — Confirm at Cashier POS", COLOR_WHITE
        elif self.current_state == STATE_SETTLEMENT:
            bg, txt, fg = COLOR_EMERALD, "✓ Payment Confirmed — Please Claim Your Order!", COLOR_WHITE
        else:
            bg, txt, fg = COLOR_ROSE_ALERT, "⚡ Insufficient Balance — Tap RFID Card to Confirm Pay Later", COLOR_WHITE

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
        st_name = self.active_student.get("name", "Student") if self.active_student else "Student"
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
        overlay = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT - 84), pygame.SRCALPHA)
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
        card_y = 84 + ((SCREEN_HEIGHT - 84 - card_h) // 2)
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
        if getattr(self, 'awaiting_pay_later_confirm', False):
            prompt_bg = COLOR_GOLD_ACCENT
            prompt_txt = "Insufficient Balance — Tap RFID Card Again to Confirm Pay Later"
            prompt_fg = COLOR_MAROON_DARK
        elif has_balance:
            prompt_bg = COLOR_EMERALD
            prompt_txt = "👆  TAP YOUR RFID CARD NOW TO CONFIRM"
            prompt_fg = COLOR_WHITE
        else:
            prompt_bg = COLOR_GOLD_ACCENT
            prompt_txt = "⚠️  BALANCE LOW — TAP RFID CARD TO USE PAY LATER"
            prompt_fg = COLOR_MAROON_DARK

        btn_rect = pygame.Rect(card_x + 28, prompt_y, card_w - 56, 46)
        pygame.draw.rect(self.screen, prompt_bg, btn_rect, border_radius=14)
        p_surf = self.font_body_bold.render(prompt_txt, True, prompt_fg)
        self.screen.blit(p_surf, (btn_rect.centerx - p_surf.get_width() // 2, btn_rect.centery - p_surf.get_height() // 2))

    def render_footer(self):
        # Developer debug shortcuts footer bar removed for clean, production-grade presentation
        pass

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
                        for it in (self.cart_items or []):
                            it_name = it.get("name", "")
                            if "Chicken" in it_name:
                                it["name"] = "Pork Adobo with Rice"
                                it["ai_label"] = "pork_adobo"
                                break
                            elif "Pork" in it_name:
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
                        success, active_cam = self.camera_thread.switch_camera()
                        if success:
                            self.status_message = f"📷 Camera Switched to Index {active_cam}"
                        else:
                            self.status_message = f"⚠️ Camera {active_cam} Not Found (Active: Index {getattr(self.camera_thread, 'cam_index', 0)})"
                    elif event.key == pygame.K_d:
                        sim_state = self.camera_thread.toggle_simulation()
                        self.status_message = f"Demo Synthetic AI Simulation: {'ENABLED' if sim_state else 'DISABLED'}"

                    if event.unicode and (event.unicode.isalnum() or event.unicode in ['-', '_', ':']):
                        now = time.time()
                        if now - self.last_key_time > 1.2:
                            self.rfid_scan_buffer = ""
                        self.rfid_scan_buffer += event.unicode
                        self.last_key_time = now

                elif event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
                    pos = event.pos
                    if hasattr(self, 'pay_later_btn_rect') and self.pay_later_btn_rect.collidepoint(pos) and self.current_state in [STATE_PAYMENT_CONFIRMATION, STATE_SCANNING, STATE_STABILITY_COUNTDOWN, STATE_SETTLEMENT]:
                        self.execute_pay_later_checkout()
                    elif self.btn_step1.collidepoint(pos):
                        self.execute_simulation_step(1)
                    elif self.btn_step2.collidepoint(pos):
                        self.execute_simulation_step(2)
                    elif self.btn_step3.collidepoint(pos):
                        if self.current_state == STATE_PAYMENT_CONFIRMATION:
                            self.execute_rfid_checkout()
                        else:
                            self.execute_simulation_step(3)
                    elif self.btn_step4.collidepoint(pos):
                        self.execute_simulation_step(4)

            # Auto-transitions & Live Scanned Food Summary Sync
            now = time.time()

            # Pay Later Persistent Confirmation Mode (5-Second Timer Permanently Removed)
            # The prompt stays persistent until confirmed by Tap 3, cleared from tray,
            # or the 60-second session inactivity timeout expires.
            if getattr(self, 'awaiting_pay_later_confirm', False):
                if not self.cart_items:
                    # Tray was cleared by student
                    print("[KIOSK] Tray cleared during Pay Later confirmation. Resetting Pay Later mode.")
                    self.awaiting_pay_later_confirm = False
                    if self.current_state == STATE_PAYMENT_CONFIRMATION:
                        self.transition_to_state(STATE_SCANNING)

            if self.current_state in [STATE_GREET, STATE_SCANNING, STATE_STABILITY_COUNTDOWN, STATE_PAYMENT_CONFIRMATION]:
                session_ttl = 60.0 if getattr(self, 'awaiting_pay_later_confirm', False) else (45.0 if self.cart_items else 20.0)
                if now - self.state_timer >= session_ttl:
                    print(f"[KIOSK] Inactivity timeout expired ({session_ttl}s). Resetting to IDLE.")
                    self.awaiting_pay_later_confirm = False
                    self.transition_to_state(STATE_IDLE)

            # ── Real-Time Tray Mirroring → Cashier POS Order Tally ────────────────
            # Every active frame during scanning mirrors the live detections straight onto
            # self.cart_items and broadcasts them, so the cashier tally tracks the physical
            # tray without waiting for stability settlement or an RFID tap.
            if self.current_state in (STATE_GREET, STATE_SCANNING, STATE_STABILITY_COUNTDOWN):
                self.sync_cart_from_detections(self.camera_thread.get_latest_detections())

            if self.current_state == STATE_IDLE:
                # Standby Mode: Do NOT scan food items or update cart until student taps card
                if self.cart_items and not self.cart_manual_override_lock:
                    self.cart_items = []
                    self.total_amount = 0.0

            elif self.current_state == STATE_PREORDER_ANNOUNCEMENT and (now - self.state_timer >= 8.0):
                self.transition_to_state(STATE_IDLE)

            elif self.current_state in [STATE_GREET, STATE_SCANNING]:
                # Wave 3 Task 4: 10-second idle scanner timeout polish
                # If STATE_SCANNING with 0 cart items for 10+ seconds, announce & reset to IDLE
                if self.current_state == STATE_SCANNING and len(self.cart_items) == 0 and (now - self.state_timer >= 10.0):
                    print("[KIOSK] 10-second scanner timeout: no items detected. Returning to IDLE.")
                    speak_text("No items detected. Session timed out.")
                    self.cart_items = []
                    self.active_student = None
                    self.notify_pos_update()    # Broadcast empty cart before reset
                    self.transition_to_state(STATE_IDLE)
                elif not self.cart_manual_override_lock:
                    valid_items = self.build_cart_snapshot(self.camera_thread.get_latest_detections())
                    total_price = sum(float(it.get("price", 0.0) or 0.0) * int(it.get("qty", 1) or 1) for it in (valid_items or []))

                    if len(valid_items) > 0 and total_price > 0.0:
                        # Stability hash based strictly on Item_ID:Quantity (no bbox coordinates or raw confidence scores)
                        curr_hash = "-".join(sorted([
                            f"{str(item.get('product_id') or item.get('id') or item.get('name'))}:{item.get('qty', 1)}"
                            for item in valid_items
                        ]))
                        if curr_hash == self.last_detection_hash:
                            if self.stable_start_time == 0.0:
                                self.stable_start_time = now
                            elif now - self.stable_start_time >= 1.2:
                                # The live mirror above already owns cart_items; the hash only
                                # gates the transition into the stability countdown.
                                self.transition_to_state(STATE_STABILITY_COUNTDOWN)
                        else:
                            self.last_detection_hash = curr_hash
                            self.stable_start_time = now
                    else:
                        # 0 valid menu items on tray: stay in steady STATE_SCANNING without initiating or looping countdown timer
                        self.last_detection_hash = ""
                        self.stable_start_time = 0.0
                        if self.cart_items:
                            self.cart_items = []
                            self.total_amount = 0.0
                            self.notify_pos_update()
                        if self.current_state == STATE_SCANNING:
                            self.status_message = "Waiting for tray... Place food on scanning platform."

            elif self.current_state == STATE_STABILITY_COUNTDOWN:
                if time.time() - getattr(self, 'stability_started_at', now) >= 10.0:
                    # 10s Stability countdown ceiling reached: lock cart and transition to payment confirmation
                    self.countdown_remaining = 0.0
                    self.cart_manual_override_lock = True
                    cnt = sum(i.get("qty", 1) for i in self.cart_items)
                    self.status_message = f"🟢 Scanned {cnt} item(s) (₱{self.total_amount:.2f}) — Ready for Payment Confirmation"
                    if self.cart_items:
                        item_names = [f"{it.get('qty', 1)} {it.get('name', 'Item')}" for it in (self.cart_items or [])]
                        speak_text(f"Detected: {', '.join(item_names)}. Total is {int(self.total_amount)} pesos. Please confirm payment.")
                    self.transition_to_state(STATE_PAYMENT_CONFIRMATION)
                else:
                    valid_items = self.build_cart_snapshot(self.camera_thread.get_latest_detections())
                    total_price = sum(float(it.get("price", 0.0) or 0.0) * int(it.get("qty", 1) or 1) for it in (valid_items or []))

                    # Only trigger and tick the stability countdown if len(valid_cart_items) > 0 AND total price > 0
                    if len(valid_items) == 0 or total_price <= 0.0:
                        # 0 valid menu items on tray: keep the kiosk in steady STATE_SCANNING without initiating or looping countdown timer
                        self.cart_items = []
                        self.total_amount = 0.0
                        self.last_detection_hash = ""
                        self.stable_start_time = 0.0
                        self.countdown_remaining = 5.0
                        self.motion_detected = False
                        self.transition_to_state(STATE_SCANNING)
                    else:
                        # Frame stability hash based strictly on Item_ID:Quantity
                        curr_hash = "-".join(sorted([
                            f"{str(item.get('product_id') or item.get('id') or item.get('name'))}:{item.get('qty', 1)}"
                            for item in valid_items
                        ]))
                        if curr_hash != self.last_detection_hash:
                            # Real item change on tray: reset countdown. The live mirror
                            # above is the single writer of cart_items during scanning,
                            # so the new order is already broadcast to the Cashier POS.
                            self.last_detection_hash = curr_hash
                            self.countdown_remaining = 5.0
                            self.last_tick_sec = 5

                        if self.motion_detected:
                            self.countdown_remaining = 5.0
                        else:
                            self.motion_voice_alerted = False
                            self.countdown_remaining -= dt
                            curr_sec = int(math.ceil(self.countdown_remaining))
                            if curr_sec < self.last_tick_sec and curr_sec >= 1:
                                self.last_tick_sec = curr_sec
                            if self.countdown_remaining <= 0.0:
                                # Countdown finished — lock cart and transition cleanly to payment confirmation (Step 3) without bouncing back to scanning
                                self.cart_manual_override_lock = True
                                cnt = sum(i.get("qty", 1) for i in self.cart_items)
                                self.status_message = f"🟢 Scanned {cnt} item(s) (₱{self.total_amount:.2f}) — Ready for Payment Confirmation"
                                if self.cart_items:
                                    item_names = [f"{it.get('qty', 1)} {it.get('name', 'Item')}" for it in (self.cart_items or [])]
                                    speak_text(f"Detected: {', '.join(item_names)}. Total is {int(self.total_amount)} pesos. Please confirm payment.")
                                self.transition_to_state(STATE_PAYMENT_CONFIRMATION)

            elif self.current_state == STATE_PAYMENT_CONFIRMATION:
                # Order summary is locked in Step 3 (Payment Confirmation)
                pass

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

KioskApp = NovaLunchKioskGUI

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="NovaLunch Student Kiosk CFD Monitor")
    parser.add_argument("--cam-index", "--camera", "-c", type=int, default=None,
                        help="Camera device index (default: KIOSK_CAM_INDEX env or 0)")
    args, unknown = parser.parse_known_args()

    app = NovaLunchKioskGUI(cam_index=args.cam_index)
    app.run()
