#!/usr/bin/env python3
"""
Catalog Correction & Sanitation Migration Script for NovaLunch
1. Corrects AI vision class cross-wiring
2. Fixes category contamination for Beverages and Snacks & Bakery
3. Restores Classic Cheeseburger to active / unarchived status
4. Permanently deletes bogus 'ugfiuc' record
Applies to both Supabase Cloud PostgreSQL and local novalunch_edge.db (SQLite).
"""

import urllib.request
import urllib.error
import json
import sqlite3
import os

SUPABASE_URL = "https://wtvkmywmlifcsddlgvnn.supabase.co"
SUPABASE_ANON_KEY = "sb_publishable_yywY2quhz5k1x6Pu_w6pgQ_e-mBU0q2"

HEADERS = {
    "apikey": SUPABASE_ANON_KEY,
    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
}

CATEGORY_BEVERAGES_UUID = "22222222-2222-2222-2222-222222222222"
CATEGORY_SNACKS_UUID = "33333333-3333-3333-3333-333333333333"

# Product updates
PRODUCT_UPDATES = [
    {
        "id": "111ac6f3-cca3-479e-86a1-1d1edd28a945",
        "name": "Buttercream Biscuits",
        "payload": {
            "ai_label": "Buttercream_Biscuits",
            "category": "Snacks & Bakery",
            "category_id": CATEGORY_SNACKS_UUID,
            "status": "active",
            "is_available": True,
            "available": True,
            "stock_quantity": 50,
            "stock": 50
        }
    },
    {
        "id": "a3333333-3333-3333-3333-333333333333",
        "name": "Ham & Cheese Sandwich",
        "payload": {
            "ai_label": "sandwich",
            "category": "Snacks & Bakery",
            "category_id": CATEGORY_SNACKS_UUID,
            "status": "active",
            "is_available": True,
            "available": True,
            "stock_quantity": 40,
            "stock": 40
        }
    },
    {
        "id": "a8888888-8888-8888-8888-888888888888",
        "name": "Choco Chip Cookie",
        "payload": {
            "ai_label": "cookie",
            "category": "Snacks & Bakery",
            "category_id": CATEGORY_SNACKS_UUID,
            "status": "active",
            "is_available": True,
            "available": True,
            "stock_quantity": 90,
            "stock": 90
        }
    },
    {
        "id": "a4444444-4444-4444-4444-444444444444",
        "name": "Mineral Water (500ml)",
        "payload": {
            "ai_label": "water_bottle",
            "category": "Beverages",
            "category_id": CATEGORY_BEVERAGES_UUID,
            "status": "active",
            "is_available": True,
            "available": True,
            "stock_quantity": 150,
            "stock": 150
        }
    },
    {
        "id": "a5555555-5555-5555-5555-555555555555",
        "name": "Iced Fruit Juice (350ml)",
        "payload": {
            "ai_label": "juice_box",
            "category": "Beverages",
            "category_id": CATEGORY_BEVERAGES_UUID,
            "status": "active",
            "is_available": True,
            "available": True,
            "stock_quantity": 80,
            "stock": 80
        }
    },
    {
        "id": "a6666666-6666-6666-6666-666666666666",
        "name": "Fresh Red Apple",
        "payload": {
            "ai_label": "apple",
            "category": "Snacks & Bakery",
            "category_id": CATEGORY_SNACKS_UUID,
            "status": "active",
            "is_available": True,
            "available": True,
            "stock_quantity": 40,
            "stock": 40
        }
    },
    {
        "id": "a1111111-1111-1111-1111-111111111111",
        "name": "Classic Cheeseburger",
        "payload": {
            "ai_label": "burger",
            "category": "Meals & Mains",
            "status": "active",
            "is_available": True,
            "available": True,
            "stock_quantity": 40,
            "stock": 40
        }
    }
]

def migrate_supabase():
    print("\n--- 1. SANITIZING SUPABASE CLOUD POSTGRESQL ---")
    
    # 1. Permanently delete dummy record 'ugfiuc'
    try:
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/products?name=eq.ugfiuc",
            headers=HEADERS,
            method="DELETE"
        )
        with urllib.request.urlopen(req) as resp:
            deleted = json.loads(resp.read().decode())
            print(f"  [DELETE] Deleted bogus item 'ugfiuc': {len(deleted)} record(s) removed.")
    except Exception as e:
        print(f"  [DELETE ERROR] Could not delete 'ugfiuc': {e}")

    # 2. Update each product
    for item in PRODUCT_UPDATES:
        pid = item["id"]
        pname = item["name"]
        payload = item["payload"]
        data_bytes = json.dumps(payload).encode("utf-8")
        
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/products?id=eq.{pid}",
            data=data_bytes,
            headers=HEADERS,
            method="PATCH"
        )
        try:
            with urllib.request.urlopen(req) as resp:
                res = json.loads(resp.read().decode())
                if res:
                    row = res[0]
                    print(f"  [UPDATED] {pname:<26} -> AI: {row.get('ai_label'):<22} | Cat: {row.get('category'):<16} | Status: {row.get('status')} | Avail: {row.get('is_available')}")
                else:
                    print(f"  [WARN] No row returned for {pname} (ID: {pid})")
        except urllib.error.HTTPError as e:
            print(f"  [ERROR] Updating {pname}: HTTP {e.code} -> {e.read().decode()}")
        except Exception as e:
            print(f"  [ERROR] Updating {pname}: {e}")

def migrate_sqlite():
    print("\n--- 2. SANITIZING LOCAL SQLITE EDGE DATABASE (novalunch_edge.db) ---")
    db_path = "src/database/novalunch_edge.db"
    if not os.path.exists(db_path):
        print(f"  [SKIP] SQLite DB '{db_path}' not found.")
        return
        
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    
    # 1. Permanently delete 'ugfiuc'
    c.execute("DELETE FROM products WHERE name = 'ugfiuc' OR id = '3aca3d78-9fae-41ee-9e38-d932e9c175ed';")
    print(f"  [DELETE] Removed 'ugfiuc' from SQLite ({c.rowcount} rows).")
    
    # 2. Update products in SQLite
    for item in PRODUCT_UPDATES:
        pid = item["id"]
        pname = item["name"]
        payload = item["payload"]
        
        # In SQLite: is_archived = 0, is_available = 1
        c.execute("""
            UPDATE products
            SET ai_label = ?,
                category = ?,
                is_available = 1,
                is_archived = 0,
                stock = ?
            WHERE id = ? OR name = ?
        """, (payload.get("ai_label"), payload.get("category"), payload.get("stock_quantity", 50), pid, pname))
        print(f"  [UPDATED SQLITE] {pname:<26} ({c.rowcount} row updated)")

    conn.commit()
    conn.close()
    print("  [SUCCESS] SQLite novalunch_edge.db updated.")

if __name__ == "__main__":
    migrate_supabase()
    migrate_sqlite()
    print("\n[MIGRATION COMPLETE] All data sanitization and catalog correction routines executed.")
