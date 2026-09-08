#!/usr/bin/env python3
"""
==============================================================================
NOVALUNCH — SUPABASE LIVE DATABASE HEALTH & SCHEMA AUDITOR
==============================================================================
Checks if your live Supabase project is up-to-date and matches the schema
and functions required by the NovaLunch application.
==============================================================================
"""

import urllib.request
import urllib.error
import json
import sys

SUPABASE_URL = "https://wtvkmywmlifcsddlgvnn.supabase.co"
SUPABASE_ANON_KEY = "sb_publishable_yywY2quhz5k1x6Pu_w6pgQ_e-mBU0q2"

HEADERS = {
    "apikey": SUPABASE_ANON_KEY,
    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
    "Content-Type": "application/json"
}

REQUIRED_TABLES = [
    ("profiles", ["id", "email", "full_name", "role", "balance", "daily_limit", "credit_liability", "rfid_uid", "student_id_number"]),
    ("wallets", ["id", "user_id", "balance", "credit_liability", "daily_limit", "daily_spent"]),
    ("menu_categories", ["id", "name", "is_active"]),
    ("products", ["id", "name", "price", "stock", "stock_quantity", "is_available", "calories", "allergens"]),
    ("inventory_batches", ["id", "product_id", "batch_number", "quantity_remaining", "expiration_date", "status"]),
    ("inventory_logs", ["id", "product_id", "quantity", "change_type"]),
    ("orders", ["id", "order_number", "final_amount", "order_status", "payment_method"]),
    ("order_items", ["id", "order_id", "product_id", "quantity", "unit_price", "total_price"]),
    ("wallet_transactions", ["id", "user_id", "amount", "transaction_type", "payment_channel"]),
    ("preorders", ["id", "student_id", "item_name", "status", "pickup_slot"]),
    ("preorder_slots", ["id", "slot_name", "start_time", "end_time", "is_active"]),
    ("meal_disputes", ["id", "order_id", "status", "dispute_reason"]),
    ("dispute_tickets", ["id", "ticket_number", "status"]),
    ("cashier_shift_reconciliations", ["id", "cashier_id", "cash_sales", "variance"]),
    ("parent_student_links", ["id", "parent_id", "student_id"]),
    ("parent_student_link_requests", ["id", "parent_email", "student_id_number", "status"]),
    ("notifications", ["id", "user_id", "title", "message"]),
    ("notification_preferences", ["id", "user_id"]),
    ("canteen_settings", ["key", "value"]),
    ("hardware_mappings", ["terminal_id", "status"]),
    ("governance_overrides", ["id", "student_id", "override_type", "reason"]),
    ("topup_requests", ["id", "amount", "reference_number", "status"]),
    ("kds_tickets", ["id", "order_id", "ticket_number", "status"]),
    ("ai_detection_logs", ["id", "detected_items", "confidence_score"]),
    ("audit_logs", ["id", "action", "created_at"]),
    ("system_audit_logs", ["id", "action_type"]),
    ("offline_transaction_queue", ["id", "device_id", "offline_reference", "status"]),
    ("offline_balance_reservations", ["id", "reservation_token", "reserved_amount"]),
    ("student_subsidies", ["id", "student_id", "amount"]),
    ("category_spending_rules", ["id", "student_id"]),
    ("category_spending_limits", ["id", "student_id", "category_slug"]),
    ("student_allergen_guardrails", ["id", "student_id", "allergen_tag"]),
    ("recipe_bom", ["id", "menu_item_id", "quantity_required"]),
    ("sis_tuition_batches", ["id", "batch_reference", "total_amount"]),
    ("tuition_reconciliation_batches", ["id", "batch_reference", "total_debt_cleared"]),
    ("tuition_batch_exports", ["id", "batch_reference", "export_format"])
]

REQUIRED_RPCS = [
    ("fn_deduct_cart_stock_fifo", {"p_items": []}),
    ("fn_claim_preorder_by_student", {"p_student_id": "00000000-0000-0000-0000-000000000000"}),
    ("fn_admin_update_wallet", {"p_user_id": "00000000-0000-0000-0000-000000000000", "p_balance": 0, "p_daily_limit": 200}),
    ("fn_toggle_pay_later_pre_auth", {"p_student_id": "00000000-0000-0000-0000-000000000000", "p_pre_authorized": True}),
    ("fn_generate_student_dynamic_qr", {"p_student_id": "00000000-0000-0000-0000-000000000000"}),
    ("fn_sync_offline_transaction", {"p_device_id": "TEST", "p_offline_reference": "DIAG_TEST", "p_payload": {}}),
]

def check_table(table_name, columns):
    col_str = ",".join(columns)
    url = f"{SUPABASE_URL}/rest/v1/{table_name}?select={col_str}&limit=1"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            return True, f"OK ({len(data)} rows sampled)", None
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        try:
            err_json = json.loads(err_body)
            msg = err_json.get("message", err_body)
        except Exception:
            msg = err_body
        return False, f"HTTP {e.code}", msg
    except Exception as e:
        return False, "CONNECTION_ERROR", str(e)

def check_rpc(rpc_name, payload):
    url = f"{SUPABASE_URL}/rest/v1/rpc/{rpc_name}"
    data_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data_bytes, headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode())
            return True, "INSTALLED & ACTIVE", None
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        # 404 means the function is NOT deployed in Supabase
        if e.code == 404:
            return False, "MISSING (Not Deployed)", "Function not found in schema cache"
        # 409 / 400 / 500 often means the RPC exists and evaluated parameters (e.g. FK constraint or not found)
        try:
            err_json = json.loads(err_body)
            code = err_json.get("code")
            msg = err_json.get("message", "")
            if code in ("23503", "P0001", "23505") or "violates" in msg or "not found" in msg.lower() or "exception" in msg.lower():
                return True, "INSTALLED & ACTIVE (Logic Executed)", None
            return False, f"HTTP {e.code}", msg
        except Exception:
            return False, f"HTTP {e.code}", err_body
    except Exception as e:
        return False, "CONNECTION_ERROR", str(e)

def main():
    print("\n" + "=" * 70)
    print(" NOVALUNCH SUPABASE LIVE DATABASE AUDIT REPORT")
    print(f" Target Endpoint: {SUPABASE_URL}")
    print("=" * 70 + "\n")

    table_pass = 0
    table_fail = 0

    print("--- 1. TABLE & COLUMN ACCESSIBILITY CHECK ---")
    for table_name, columns in REQUIRED_TABLES:
        ok, status, err = check_table(table_name, columns)
        if ok:
            table_pass += 1
            print(f"  [✓ PASS] public.{table_name:<30} {status}")
        else:
            table_fail += 1
            print(f"  [✗ FAIL] public.{table_name:<30} {status} -> {err}")

    print("\n--- 2. STORED PROCEDURES (RPCs) CHECK ---")
    rpc_pass = 0
    rpc_fail = 0
    for rpc_name, payload in REQUIRED_RPCS:
        ok, status, err = check_rpc(rpc_name, payload)
        if ok:
            rpc_pass += 1
            print(f"  [✓ PASS] {rpc_name:<35} {status}")
        else:
            rpc_fail += 1
            print(f"  [✗ FAIL] {rpc_name:<35} {status} -> {err}")

    print("\n" + "=" * 70)
    print(f" SUMMARY: Tables: {table_pass}/{len(REQUIRED_TABLES)} OK | RPCs: {rpc_pass}/{len(REQUIRED_RPCS)} OK")
    
    if table_fail > 0 or rpc_fail > 0:
        print("\n [!] ACTION RECOMMENDED:")
        print("     Some tables or RPC functions are missing or outdated.")
        print("     Please open the Supabase Dashboard -> SQL Editor and run:")
        print("     src/database/MASTER_SCHEMA.sql")
    else:
        print("\n [✓] PERFECT! Your live Supabase database is 100% synchronized with the code.")
    print("=" * 70 + "\n")

if __name__ == "__main__":
    main()
