-- ==============================================================================
-- NOVALUNCH CANTEEN POS & SYSTEM — COMPLETE ALL-IN-ONE SAFE MIGRATION SCRIPT
-- ==============================================================================
-- Project: NovaLunch (Saint Joseph College Canteen System)
-- Target Database: Supabase / PostgreSQL (Project: wtvkmywmlifcsddlgvnn)
--
-- SAFE TO RUN ON ANY DATABASE (BLANK OR EXISTING):
--   - Uses CREATE TABLE IF NOT EXISTS (never drops existing data)
--   - Uses ALTER TABLE ADD COLUMN IF NOT EXISTS (adds missing columns safely)
--   - Uses CREATE OR REPLACE FUNCTION (updates RPC logic without data loss)
--   - Uses ON CONFLICT DO NOTHING (preserves existing settings and records)
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- 2. CORE SYSTEM TABLES
-- ------------------------------------------------------------------------------

-- User Profiles
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    role TEXT NOT NULL DEFAULT 'student',
    student_id_number TEXT UNIQUE,
    employee_id TEXT UNIQUE,
    rfid_uid TEXT UNIQUE,
    barcode_id TEXT UNIQUE,
    daily_limit NUMERIC(10,2) DEFAULT 200.00,
    weekly_limit NUMERIC(10,2) DEFAULT 1000.00,
    monthly_allowance NUMERIC(10,2) DEFAULT 4000.00,
    balance NUMERIC(10,2) DEFAULT 350.00,
    credit_liability NUMERIC(10,2) DEFAULT 0.00,
    credit_limit NUMERIC(10,2) DEFAULT 500.00,
    pay_later_count INT DEFAULT 0,
    pay_later_pre_authorized BOOLEAN DEFAULT TRUE,
    daily_calories_spent INT DEFAULT 0,
    max_daily_calories INT DEFAULT 1800,
    max_meal_calories INT DEFAULT 800,
    allergen_mode TEXT DEFAULT 'SOFT_WARN',
    allergies JSONB DEFAULT '[]'::jsonb,
    restricted_categories JSONB DEFAULT '[]'::jsonb,
    pin_code TEXT,
    manager_pin TEXT DEFAULT '1234',
    accumulated_salary_deduction NUMERIC(10,2) DEFAULT 0.00,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure all modern profile columns exist if table was created in an older migration
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS employee_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS weekly_limit NUMERIC(10,2) DEFAULT 1000.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS monthly_allowance NUMERIC(10,2) DEFAULT 4000.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS credit_liability NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS credit_limit NUMERIC(10,2) DEFAULT 500.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pay_later_count INT DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pay_later_pre_authorized BOOLEAN DEFAULT TRUE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS daily_calories_spent INT DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS max_daily_calories INT DEFAULT 1800;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS max_meal_calories INT DEFAULT 800;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS allergen_mode TEXT DEFAULT 'SOFT_WARN';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS allergies JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS restricted_categories JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pin_code TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS manager_pin TEXT DEFAULT '1234';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS accumulated_salary_deduction NUMERIC(10,2) DEFAULT 0.00;

-- Wallets
CREATE TABLE IF NOT EXISTS public.wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    balance NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    credit_balance NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    daily_limit NUMERIC(10,2) DEFAULT 200.00,
    weekly_limit NUMERIC(10,2) DEFAULT 1000.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Menu Categories
CREATE TABLE IF NOT EXISTS public.menu_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    display_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Products & Menu Catalog
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    category_id UUID REFERENCES public.menu_categories(id) ON DELETE SET NULL,
    price NUMERIC(10,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    available BOOLEAN DEFAULT TRUE,
    calories INT DEFAULT 0,
    protein TEXT DEFAULT '0g',
    allergens JSONB DEFAULT '[]'::jsonb,
    image_url TEXT,
    img TEXT,
    ai_label TEXT,
    description TEXT,
    barcode TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'Meals & Mains';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.menu_categories(id) ON DELETE SET NULL;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS img TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS ai_label TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS protein TEXT DEFAULT '0g';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS allergens JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS calories INT DEFAULT 0;

-- Inventory Batches
CREATE TABLE IF NOT EXISTS public.inventory_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    batch_number TEXT NOT NULL,
    quantity_added INT NOT NULL,
    quantity_remaining INT NOT NULL,
    unit_cost NUMERIC(10,2) DEFAULT 0.00,
    expiration_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'FRESH',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Inventory Logs
CREATE TABLE IF NOT EXISTS public.inventory_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    batch_id UUID REFERENCES public.inventory_batches(id) ON DELETE SET NULL,
    change_type TEXT NOT NULL,
    quantity INT NOT NULL,
    remaining_stock INT NOT NULL,
    reason TEXT,
    performed_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Orders
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number TEXT UNIQUE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    student_name TEXT,
    total_amount NUMERIC(10,2) NOT NULL,
    subtotal_amount NUMERIC(10,2),
    discount_amount NUMERIC(10,2) DEFAULT 0.00,
    discount_label TEXT,
    final_amount NUMERIC(10,2) NOT NULL,
    payment_method TEXT NOT NULL,
    payment_status TEXT DEFAULT 'COMPLETED',
    order_status TEXT DEFAULT 'COMPLETED',
    order_source TEXT DEFAULT 'POS_REGISTER_01',
    cash_tendered NUMERIC(10,2),
    cash_change NUMERIC(10,2),
    tray_photo_url TEXT,
    is_voided BOOLEAN DEFAULT FALSE,
    void_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS student_name TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS subtotal_amount NUMERIC(10,2);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_label TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS final_amount NUMERIC(10,2);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'COMPLETED';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_status TEXT DEFAULT 'COMPLETED';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_source TEXT DEFAULT 'POS_REGISTER_01';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cash_tendered NUMERIC(10,2);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cash_change NUMERIC(10,2);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tray_photo_url TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS is_voided BOOLEAN DEFAULT FALSE;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS void_reason TEXT;

-- Order Items
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    quantity INT NOT NULL,
    unit_price NUMERIC(10,2) NOT NULL,
    total_price NUMERIC(10,2) NOT NULL,
    calories INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Wallet Transactions
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID REFERENCES public.wallets(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    transaction_type TEXT NOT NULL,
    amount NUMERIC(10,2) NOT NULL,
    balance_before NUMERIC(10,2) NOT NULL,
    balance_after NUMERIC(10,2) NOT NULL,
    reference_id TEXT,
    payment_channel TEXT DEFAULT 'RFID',
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pre-Orders
CREATE TABLE IF NOT EXISTS public.preorders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_name TEXT,
    student_id_number TEXT,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    item_name TEXT NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    session TEXT DEFAULT 'Lunch Break',
    pickup_slot TEXT DEFAULT '12:00 PM',
    shelf_location TEXT DEFAULT 'Shelf B2',
    status TEXT NOT NULL DEFAULT 'Pending',
    token TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Meal Disputes
CREATE TABLE IF NOT EXISTS public.meal_disputes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id TEXT NOT NULL,
    student_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    student_name TEXT,
    dispute_reason TEXT NOT NULL,
    details TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING',
    resolution_notes TEXT,
    resolved_by TEXT,
    refund_amount NUMERIC(10,2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Cashier Shift Reconciliations (Z-Read)
CREATE TABLE IF NOT EXISTS public.cashier_shift_reconciliations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cashier_id TEXT NOT NULL,
    opening_cash NUMERIC(10,2) NOT NULL,
    cash_sales NUMERIC(10,2) NOT NULL,
    ending_cash NUMERIC(10,2) NOT NULL,
    variance NUMERIC(10,2) NOT NULL,
    expected_cash NUMERIC(10,2),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Parent-Student Link Requests
CREATE TABLE IF NOT EXISTS public.parent_student_link_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    parent_email TEXT NOT NULL,
    student_id_number TEXT NOT NULL,
    student_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    student_name TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Parent-Student Links
CREATE TABLE IF NOT EXISTS public.parent_student_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    relationship TEXT DEFAULT 'Parent',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(parent_id, student_id)
);

-- Notifications
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT DEFAULT 'info',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- System Settings & Policies
CREATE TABLE IF NOT EXISTS public.canteen_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Hardware Topology Mappings
CREATE TABLE IF NOT EXISTS public.hardware_mappings (
    terminal_id TEXT PRIMARY KEY,
    pos_register_name TEXT NOT NULL,
    camera_device_index INT DEFAULT 0,
    rfid_reader_port TEXT DEFAULT 'COM3',
    assigned_station TEXT DEFAULT 'Main Counter',
    is_online BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Preorder Slots
CREATE TABLE IF NOT EXISTS public.preorder_slots (
    id TEXT PRIMARY KEY,
    slot_name TEXT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    max_capacity INT NOT NULL DEFAULT 100,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Governance Overrides
CREATE TABLE IF NOT EXISTS public.governance_overrides (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    override_type TEXT NOT NULL,
    reason TEXT NOT NULL,
    authorized_by TEXT,
    manager_pin_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Offline Transaction Queue
CREATE TABLE IF NOT EXISTS public.offline_transaction_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id TEXT NOT NULL,
    offline_reference TEXT UNIQUE NOT NULL,
    transaction_payload JSONB NOT NULL,
    status TEXT DEFAULT 'QUEUED',
    error_message TEXT,
    synced_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Student Subsidies
CREATE TABLE IF NOT EXISTS public.student_subsidies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    program_name TEXT NOT NULL,
    daily_subsidy_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    current_cycle_spent NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- SIS Tuition Batches
CREATE TABLE IF NOT EXISTS public.sis_tuition_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_reference TEXT UNIQUE NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    student_count INT NOT NULL,
    status TEXT DEFAULT 'EXPORTED_TO_SIS',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- System Audit Logs
CREATE TABLE IF NOT EXISTS public.system_audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    user_role TEXT,
    action_type TEXT NOT NULL,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 2.5 DROP PREVIOUS FUNCTION SIGNATURES TO PREVENT RETURN TYPE CONFLICTS (42P13)
-- ------------------------------------------------------------------------------
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT proname, oid::regprocedure AS func_signature
        FROM pg_proc
        WHERE pronamespace = 'public'::regnamespace
          AND proname IN (
              'fn_deduct_stock_fifo',
              'fn_deduct_wallet_balance',
              'fn_credit_wallet_balance',
              'fn_process_gcash_webhook',
              'fn_sync_offline_transaction',
              'settle_pay_later_liability',
              'settle_ai_kiosk_transaction',
              'fn_increment_product_stock',
              'fn_log_spoilage',
              'fn_log_spoilage_and_deduct_stock',
              'fn_create_sis_tuition_batch',
              'fn_reconcile_tuition_pay_later_batch',
              'fn_toggle_pay_later_pre_auth',
              'fn_generate_student_dynamic_qr',
              'fn_add_student_calories',
              'fn_reset_daily_calories',
              'fn_refresh_batch_expiry_statuses',
              'fn_get_student_weekly_spent',
              'fn_guard_product_calories'
          )
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_signature || ' CASCADE;';
    END LOOP;
END $$;

-- 3. STORED PROCEDURES & ATOMIC RPC FUNCTIONS
-- ------------------------------------------------------------------------------

-- FIFO Stock Batch Deduction
CREATE OR REPLACE FUNCTION public.fn_deduct_stock_fifo(
    p_product_id UUID,
    p_quantity INT,
    p_performed_by TEXT DEFAULT 'POS Cashier'
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_qty_needed INT := p_quantity;
    v_batch RECORD;
    v_deduct INT;
    v_total_remaining INT;
BEGIN
    SELECT COALESCE(SUM(quantity_remaining), 0) INTO v_total_remaining
    FROM public.inventory_batches
    WHERE product_id = p_product_id AND status != 'EXPIRED' AND quantity_remaining > 0;

    IF v_total_remaining < p_quantity THEN
        -- Still allow basic product stock decrement
        UPDATE public.products
        SET stock = GREATEST(0, stock - p_quantity), updated_at = NOW()
        WHERE id = p_product_id;
        RETURN 0;
    END IF;

    FOR v_batch IN
        SELECT id, quantity_remaining
        FROM public.inventory_batches
        WHERE product_id = p_product_id AND status != 'EXPIRED' AND quantity_remaining > 0
        ORDER BY expiration_date ASC, created_at ASC
        FOR UPDATE
    LOOP
        IF v_qty_needed <= 0 THEN
            EXIT;
        END IF;

        IF v_batch.quantity_remaining <= v_qty_needed THEN
            v_deduct := v_batch.quantity_remaining;
            v_qty_needed := v_qty_needed - v_deduct;

            UPDATE public.inventory_batches
            SET quantity_remaining = 0, status = 'DEPLETED', updated_at = NOW()
            WHERE id = v_batch.id;
        ELSE
            v_deduct := v_qty_needed;
            v_qty_needed := 0;

            UPDATE public.inventory_batches
            SET quantity_remaining = quantity_remaining - v_deduct, updated_at = NOW()
            WHERE id = v_batch.id;
        END IF;

        INSERT INTO public.inventory_logs (product_id, batch_id, change_type, quantity, remaining_stock, reason, performed_by)
        VALUES (p_product_id, v_batch.id, 'FIFO_SALE', -v_deduct, 0, 'POS Cashier Checkout', p_performed_by);
    END LOOP;

    UPDATE public.products
    SET stock = (
        SELECT COALESCE(SUM(quantity_remaining), 0)
        FROM public.inventory_batches
        WHERE product_id = p_product_id AND status != 'EXPIRED'
    ),
    updated_at = NOW()
    WHERE id = p_product_id;

    RETURN 1;
END;
$$;

-- Atomic Wallet Balance Deduction
CREATE OR REPLACE FUNCTION public.fn_deduct_wallet_balance(
    p_user_id UUID,
    p_amount NUMERIC(10,2)
)
RETURNS NUMERIC(10,2)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC(10,2);
    v_new_balance     NUMERIC(10,2);
BEGIN
    SELECT balance INTO v_current_balance
    FROM public.wallets
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'WALLET_NOT_FOUND: No wallet exists for user %', p_user_id;
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Balance is % but tried to deduct %', v_current_balance, p_amount;
    END IF;

    UPDATE public.wallets
    SET balance     = balance - p_amount,
        daily_spent = COALESCE(daily_spent, 0) + p_amount,
        updated_at  = NOW()
    WHERE user_id = p_user_id
    RETURNING balance INTO v_new_balance;

    -- Mirror to profiles if column exists
    BEGIN
        UPDATE public.profiles SET balance = v_new_balance, updated_at = NOW() WHERE id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RETURN v_new_balance;
END;
$$;

-- Atomic Wallet Balance Credit
CREATE OR REPLACE FUNCTION public.fn_credit_wallet_balance(
    p_user_id UUID,
    p_amount NUMERIC(10,2)
)
RETURNS NUMERIC(10,2)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_balance NUMERIC(10,2);
BEGIN
    INSERT INTO public.wallets (user_id, balance, updated_at)
    VALUES (p_user_id, p_amount, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET balance    = public.wallets.balance + EXCLUDED.balance,
        updated_at = NOW()
    RETURNING balance INTO v_new_balance;

    -- Mirror to profiles if column exists
    BEGIN
        UPDATE public.profiles SET balance = v_new_balance, updated_at = NOW() WHERE id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RETURN v_new_balance;
END;
$$;

-- Universal Admin Wallet & Spending Limit Update RPC
CREATE OR REPLACE FUNCTION public.fn_admin_update_wallet(
    p_user_id UUID,
    p_balance NUMERIC(10,2) DEFAULT NULL,
    p_daily_limit NUMERIC(10,2) DEFAULT NULL,
    p_credit_liability NUMERIC(10,2) DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_bal NUMERIC(10,2);
    v_new_limit NUMERIC(10,2);
    v_new_liability NUMERIC(10,2);
BEGIN
    INSERT INTO public.wallets (user_id, balance, daily_limit, credit_liability, updated_at)
    VALUES (
        p_user_id,
        COALESCE(p_balance, 0.00),
        COALESCE(p_daily_limit, 200.00),
        COALESCE(p_credit_liability, 0.00),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET balance          = COALESCE(p_balance, public.wallets.balance),
        daily_limit      = COALESCE(p_daily_limit, public.wallets.daily_limit),
        credit_liability = COALESCE(p_credit_liability, public.wallets.credit_liability),
        updated_at       = NOW()
    RETURNING balance, daily_limit, credit_liability
    INTO v_new_bal, v_new_limit, v_new_liability;

    BEGIN
        UPDATE public.profiles
        SET balance          = COALESCE(p_balance, balance),
            daily_limit      = COALESCE(p_daily_limit, daily_limit),
            credit_liability = COALESCE(p_credit_liability, credit_liability),
            updated_at       = NOW()
        WHERE id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'balance', v_new_bal,
        'daily_limit', v_new_limit,
        'credit_liability', v_new_liability
    );
END;
$$;

-- Instant GCash Webhook Auto-Credit
CREATE OR REPLACE FUNCTION public.fn_process_gcash_webhook(
    p_ref_no TEXT,
    p_student_id UUID,
    p_amount NUMERIC(10,2)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_bal NUMERIC(10,2);
    v_old_bal NUMERIC(10,2);
BEGIN
    SELECT balance INTO v_old_bal FROM public.wallets WHERE user_id = p_student_id;

    INSERT INTO public.wallets (user_id, balance, updated_at)
    VALUES (p_student_id, p_amount, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET balance    = public.wallets.balance + p_amount,
        updated_at = NOW()
    RETURNING balance INTO v_new_bal;

    -- Mirror to profiles if column exists
    BEGIN
        UPDATE public.profiles SET balance = v_new_bal, updated_at = NOW() WHERE id = p_student_id;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    INSERT INTO public.wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, reference_id, payment_channel, description)
    VALUES (p_student_id, 'RELOAD_GCASH', p_amount, COALESCE(v_old_bal, 0), v_new_bal, p_ref_no, 'GCASH_WEBHOOK', 'Instant GCash Webhook Auto-Credit');

    RETURN jsonb_build_object('success', true, 'new_balance', v_new_bal, 'ref_no', p_ref_no);
END;
$$;

-- Offline Transaction Sync
CREATE OR REPLACE FUNCTION public.fn_sync_offline_transaction(
    p_device_id TEXT,
    p_offline_reference TEXT,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.offline_transaction_queue (device_id, offline_reference, transaction_payload, status, synced_at)
    VALUES (p_device_id, p_offline_reference, p_payload, 'SYNCED', NOW())
    ON CONFLICT (offline_reference) DO UPDATE
    SET status = 'SYNCED', synced_at = NOW();

    RETURN jsonb_build_object('status', 'SUCCESS', 'offline_ref', p_offline_reference);
END;
$$;

-- Settle Pay Later Liability
CREATE OR REPLACE FUNCTION public.settle_pay_later_liability(
    p_student_id UUID,
    p_repayment_amount NUMERIC,
    p_payment_method TEXT DEFAULT 'cash'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_curr_debt NUMERIC;
    v_curr_bal NUMERIC;
    v_new_debt NUMERIC;
    v_new_bal NUMERIC;
BEGIN
    SELECT credit_liability, balance INTO v_curr_debt, v_curr_bal
    FROM public.profiles
    WHERE id = p_student_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Student not found');
    END IF;

    IF p_repayment_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Repayment amount must be positive');
    END IF;

    IF p_payment_method = 'rfid' THEN
        IF v_curr_bal < p_repayment_amount THEN
            RETURN jsonb_build_object('success', false, 'error', 'Insufficient RFID balance for debt clearance');
        END IF;
        v_new_bal := v_curr_bal - p_repayment_amount;
        v_new_debt := GREATEST(0.00, v_curr_debt - p_repayment_amount);

        UPDATE public.profiles
        SET balance = v_new_bal, credit_liability = v_new_debt, updated_at = NOW()
        WHERE id = p_student_id;
    ELSE
        v_new_debt := GREATEST(0.00, v_curr_debt - p_repayment_amount);
        v_new_bal := v_curr_bal;

        UPDATE public.profiles
        SET credit_liability = v_new_debt, updated_at = NOW()
        WHERE id = p_student_id;
    END IF;

    INSERT INTO public.wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, payment_channel, description)
    VALUES (p_student_id, 'PAY_LATER_SETTLEMENT', p_repayment_amount, v_curr_bal, v_new_bal, UPPER(p_payment_method), 'Pay Later emergency debt repayment clearance');

    RETURN jsonb_build_object('success', true, 'new_debt', v_new_debt, 'new_balance', v_new_bal);
END;
$$;

-- ------------------------------------------------------------------------------
-- 4. INSERT DEFAULT CANTEEN SETTINGS & POLICIES
-- ------------------------------------------------------------------------------
INSERT INTO public.canteen_settings (key, value, description) VALUES
('discount_policy', '{"student_discount_pct": 10, "senior_pwd_discount_pct": 20, "student_discount_enabled": true, "senior_pwd_discount_enabled": true}'::jsonb, 'Standard discount rates'),
('pay_later_policy', '{"global_max_credit": 1000, "max_transactions": 5, "auto_block_on_cap": true}'::jsonb, 'Pay later emergency debt caps'),
('dietary_defaults', '{"default_daily_calories": 1800, "max_single_meal": 800, "low_calorie_cutoff": 300, "high_protein_cutoff": 20}'::jsonb, 'Nutrition & calorie thresholds'),
('ai_kiosk_mode', '{"min_confidence": 0.80, "review_confidence": 0.50, "auto_checkout": true}'::jsonb, 'Overhead tray vision parameters'),
('manager_void_pin', '{"pin": "1234", "pin_hash": "a"}'::jsonb, 'Manager PIN for voids & overrides')
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 5. ENABLE ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.preorders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meal_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canteen_settings ENABLE ROW LEVEL SECURITY;

-- Anonymous / Authenticated Public Reads for POS & Student operations
DO $$ BEGIN
    DROP POLICY IF EXISTS "Public profiles read" ON public.profiles;
    CREATE POLICY "Public profiles read" ON public.profiles FOR SELECT USING (true);

    DROP POLICY IF EXISTS "Public profiles write" ON public.profiles;
    CREATE POLICY "Public profiles write" ON public.profiles FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public products read" ON public.products;
    CREATE POLICY "Public products read" ON public.products FOR SELECT USING (true);

    DROP POLICY IF EXISTS "Public products all" ON public.products;
    CREATE POLICY "Public products all" ON public.products FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public orders all" ON public.orders;
    CREATE POLICY "Public orders all" ON public.orders FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public order_items all" ON public.order_items;
    CREATE POLICY "Public order_items all" ON public.order_items FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public preorders all" ON public.preorders;
    CREATE POLICY "Public preorders all" ON public.preorders FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public disputes all" ON public.meal_disputes;
    CREATE POLICY "Public disputes all" ON public.meal_disputes FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public batches all" ON public.inventory_batches;
    CREATE POLICY "Public batches all" ON public.inventory_batches FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public settings all" ON public.canteen_settings;
    CREATE POLICY "Public settings all" ON public.canteen_settings FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public notifications all" ON public.notifications;
    CREATE POLICY "Public notifications all" ON public.notifications FOR ALL USING (true);
END $$;

-- Complete



-- Category Spending Rules
CREATE TABLE IF NOT EXISTS public.category_spending_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.menu_categories(id) ON DELETE SET NULL,
    max_items_per_day INT DEFAULT 2,
    max_amount_per_day NUMERIC(10,2) DEFAULT 150.00,
    is_blocked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Topup Requests (GCash Receipts Queue)
CREATE TABLE IF NOT EXISTS public.topup_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_name TEXT,
    amount NUMERIC(10,2) NOT NULL,
    reference_number TEXT NOT NULL,
    screenshot_url TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING',
    admin_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- KDS (Kitchen Display System) Tickets
CREATE TABLE IF NOT EXISTS public.kds_tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
    ticket_number TEXT NOT NULL,
    session TEXT DEFAULT 'Lunch Break',
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    status TEXT NOT NULL DEFAULT 'RECEIVED',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- AI Detection Logs
CREATE TABLE IF NOT EXISTS public.ai_detection_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    image_hash TEXT,
    detected_items JSONB NOT NULL DEFAULT '[]'::jsonb,
    confidence_score NUMERIC(5,4),
    latency_ms INT,
    corrected_items JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- General Audit Logs
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tuition Reconciliation Batches
CREATE TABLE IF NOT EXISTS public.tuition_reconciliation_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_reference TEXT UNIQUE NOT NULL,
    total_debt_cleared NUMERIC(10,2) NOT NULL,
    student_count INT NOT NULL,
    cleared_by TEXT NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Batch Expiry Monitor View
CREATE OR REPLACE VIEW public.v_inventory_batch_monitor AS
SELECT
    b.id AS batch_id,
    b.product_id,
    p.name AS product_name,
    COALESCE(p.category, c.name, 'Meals & Mains') AS product_category,
    b.batch_number,
    b.quantity_remaining,
    b.expiration_date,
    b.status,
    CURRENT_DATE AS query_date,
    (b.expiration_date - CURRENT_DATE) AS days_until_expiry,
    CASE
        WHEN b.expiration_date < CURRENT_DATE THEN 'EXPIRED'
        WHEN b.expiration_date = CURRENT_DATE THEN 'EXPIRING_TODAY'
        WHEN b.expiration_date <= CURRENT_DATE + INTERVAL '1 day' THEN 'EXPIRING_TOMORROW'
        WHEN b.expiration_date <= CURRENT_DATE + INTERVAL '3 days' THEN 'NEAR_EXPIRY'
        ELSE 'FRESH'
    END AS computed_expiry_risk
FROM public.inventory_batches b
JOIN public.products p ON b.product_id = p.id
LEFT JOIN public.menu_categories c ON p.category_id = c.id
WHERE b.quantity_remaining > 0;



-- Increment Product Stock
CREATE OR REPLACE FUNCTION public.fn_increment_product_stock(
    p_product_id UUID,
    p_delta INT
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_new_stock INT;
BEGIN
    UPDATE public.products
    SET stock = GREATEST(0, stock + p_delta), updated_at = NOW()
    WHERE id = p_product_id
    RETURNING stock INTO v_new_stock;
    RETURN v_new_stock;
END;
$$;

-- Log Spoilage & Deduct Stock
CREATE OR REPLACE FUNCTION public.fn_log_spoilage(
    p_product_id UUID,
    p_batch_id UUID,
    p_quantity INT,
    p_reason TEXT,
    p_performed_by TEXT DEFAULT 'Inventory Admin'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_unit_cost NUMERIC(10,2) := 0.00;
    v_total_cost NUMERIC(10,2) := 0.00;
BEGIN
    IF p_batch_id IS NOT NULL THEN
        SELECT unit_cost INTO v_unit_cost FROM public.inventory_batches WHERE id = p_batch_id;
        UPDATE public.inventory_batches
        SET quantity_remaining = GREATEST(0, quantity_remaining - p_quantity),
            status = CASE WHEN quantity_remaining - p_quantity <= 0 THEN 'DEPLETED' ELSE status END,
            updated_at = NOW()
        WHERE id = p_batch_id;
    END IF;

    UPDATE public.products
    SET stock = GREATEST(0, stock - p_quantity), updated_at = NOW()
    WHERE id = p_product_id;

    v_total_cost := COALESCE(v_unit_cost, 0.00) * p_quantity;

    INSERT INTO public.inventory_logs (product_id, batch_id, change_type, quantity, remaining_stock, reason, performed_by)
    VALUES (p_product_id, p_batch_id, 'SPOILAGE_DISPOSAL', -p_quantity, 0, p_reason, p_performed_by);

    RETURN jsonb_build_object('success', true, 'quantity_logged', p_quantity, 'total_cost', v_total_cost);
END;
$$;

-- Create SIS Tuition Batch
CREATE OR REPLACE FUNCTION public.fn_create_sis_tuition_batch(
    p_batch_ref TEXT,
    p_total_amount NUMERIC(10,2),
    p_student_count INT,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO public.sis_tuition_batches (batch_reference, total_amount, student_count, status, notes)
    VALUES (p_batch_ref, p_total_amount, p_student_count, 'EXPORTED_TO_SIS', p_notes)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'batch_id', v_id, 'batch_reference', p_batch_ref);
END;
$$;

-- Reconcile Tuition Pay Later Batch
CREATE OR REPLACE FUNCTION public.fn_reconcile_tuition_pay_later_batch(
    p_batch_ref TEXT,
    p_cleared_by TEXT,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_cleared NUMERIC(10,2) := 0.00;
    v_count INT := 0;
BEGIN
    SELECT COALESCE(SUM(credit_liability), 0.00), COUNT(*)
    INTO v_total_cleared, v_count
    FROM public.profiles
    WHERE credit_liability > 0;

    UPDATE public.profiles
    SET credit_liability = 0.00, pay_later_count = 0, updated_at = NOW()
    WHERE credit_liability > 0;

    INSERT INTO public.tuition_reconciliation_batches (batch_reference, total_debt_cleared, student_count, cleared_by, notes)
    VALUES (p_batch_ref, v_total_cleared, v_count, p_cleared_by, p_notes);

    RETURN jsonb_build_object('success', true, 'batch_reference', p_batch_ref, 'total_cleared', v_total_cleared, 'students_reconciled', v_count);
END;
$$;

-- Toggle Pay Later Pre-Authorization
CREATE OR REPLACE FUNCTION public.fn_toggle_pay_later_pre_auth(
    p_student_id UUID,
    p_pre_authorized BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.profiles
    SET pay_later_pre_authorized = p_pre_authorized, updated_at = NOW()
    WHERE id = p_student_id;

    RETURN jsonb_build_object('success', true, 'student_id', p_student_id, 'pay_later_pre_authorized', p_pre_authorized);
END;
$$;

-- Generate Dynamic Student QR
CREATE OR REPLACE FUNCTION public.fn_generate_student_dynamic_qr(
    p_student_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token TEXT;
    v_stud RECORD;
BEGIN
    SELECT id, student_id_number, full_name, balance, daily_limit, credit_liability INTO v_stud
    FROM public.profiles WHERE id = p_student_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Student not found');
    END IF;

    v_token := 'NOVALUNCH-QR-' || p_student_id || '-' || EXTRACT(EPOCH FROM NOW())::BIGINT;
    RETURN jsonb_build_object('success', true, 'token', v_token, 'student', v_stud);
END;
$$;
