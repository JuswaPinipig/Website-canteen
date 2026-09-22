-- ==============================================================================
-- NOVALUNCH CANTEEN POS & RFID SYSTEM — UNIFIED MASTER DATABASE SCHEMA
-- ==============================================================================
-- Project: NovaLunch (Saint Joseph College Canteen System)
-- Target Database: Supabase / PostgreSQL 14+ (Project: wtvkmywmlifcsddlgvnn)
-- Version: 3.0 (Consolidated Master Schema & Concurrency Hardening)
--
-- CHARACTERISTICS:
--   - 100% Idempotent: Safe to execute on a blank or existing database.
--   - Safe Column Adapters: Automatically reconciles schema across all versions.
--   - Atomic Procedures: Row-level locking (FOR UPDATE) on wallets, stock & pre-orders.
--   - Universal Compatibility: Supports Web Portal, Cashier POS, KDS, & Edge Hardware.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. DATABASE EXTENSIONS
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- 2. CORE SYSTEM TABLES & RECONCILIATION
-- ------------------------------------------------------------------------------

-- User Profiles (Auth & Identity)
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
    last_calorie_reset_date DATE DEFAULT CURRENT_DATE,
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

-- Column reconciliations for profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS employee_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS rfid_uid TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS student_id_number TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS barcode_id TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS daily_limit NUMERIC(10,2) DEFAULT 200.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS weekly_limit NUMERIC(10,2) DEFAULT 1000.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS monthly_allowance NUMERIC(10,2) DEFAULT 4000.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS balance NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS credit_liability NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS credit_limit NUMERIC(10,2) DEFAULT 500.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pay_later_count INT DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pay_later_pre_authorized BOOLEAN DEFAULT TRUE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS daily_calories_spent INT DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_calorie_reset_date DATE DEFAULT CURRENT_DATE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS max_daily_calories INT DEFAULT 1800;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS max_meal_calories INT DEFAULT 800;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS allergen_mode TEXT DEFAULT 'SOFT_WARN';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS allergies JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS restricted_categories JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pin_code TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS manager_pin TEXT DEFAULT '1234';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS accumulated_salary_deduction NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

-- Digital Wallets
CREATE TABLE IF NOT EXISTS public.wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    balance NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    credit_balance NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    credit_liability NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    daily_limit NUMERIC(10,2) DEFAULT 200.00,
    daily_spent NUMERIC(10,2) DEFAULT 0.00,
    weekly_limit NUMERIC(10,2) DEFAULT 1000.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS balance NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS credit_balance NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS credit_liability NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS daily_limit NUMERIC(10,2) NOT NULL DEFAULT 200.00;
ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS daily_spent NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS weekly_limit NUMERIC(10,2) DEFAULT 1000.00;
ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

-- Menu Categories
CREATE TABLE IF NOT EXISTS public.menu_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    display_order INT DEFAULT 0,
    sort_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.menu_categories ADD COLUMN IF NOT EXISTS sort_order INT DEFAULT 0;
ALTER TABLE public.menu_categories ADD COLUMN IF NOT EXISTS display_order INT DEFAULT 0;
ALTER TABLE public.menu_categories ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

-- Products & Menu Catalog
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'Meals & Mains',
    category_id UUID REFERENCES public.menu_categories(id) ON DELETE SET NULL,
    price NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    stock INT NOT NULL DEFAULT 0,
    stock_quantity INT NOT NULL DEFAULT 0,
    available BOOLEAN DEFAULT TRUE,
    is_available BOOLEAN DEFAULT TRUE,
    product_type TEXT DEFAULT 'packaged_good',
    calories INT DEFAULT 0,
    protein TEXT DEFAULT '0g',
    allergens JSONB DEFAULT '[]'::jsonb,
    image_url TEXT,
    img TEXT,
    ai_label TEXT,
    description TEXT,
    barcode TEXT,
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'Meals & Mains';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.menu_categories(id) ON DELETE SET NULL;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS price NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS stock INT NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS stock_quantity INT NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS available BOOLEAN DEFAULT TRUE;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT TRUE;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS product_type TEXT DEFAULT 'packaged_good';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS img TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS image_url TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS ai_label TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS protein TEXT DEFAULT '0g';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS allergens JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS calories INT DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

-- Inventory Batches (FIFO Stock Management)
CREATE TABLE IF NOT EXISTS public.inventory_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    batch_number TEXT NOT NULL DEFAULT 'BATCH-001',
    quantity_added INT NOT NULL DEFAULT 0,
    initial_quantity INT NOT NULL DEFAULT 0,
    quantity_remaining INT NOT NULL DEFAULT 0,
    current_quantity INT NOT NULL DEFAULT 0,
    unit_cost NUMERIC(10,2) DEFAULT 0.00,
    expiration_date DATE NOT NULL DEFAULT (CURRENT_DATE + INTERVAL '30 days'),
    expiry_date TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days'),
    status TEXT NOT NULL DEFAULT 'FRESH',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS batch_number TEXT DEFAULT 'BATCH-001';
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS quantity_added INT DEFAULT 0;
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS initial_quantity INT DEFAULT 0;
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS quantity_remaining INT DEFAULT 0;
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS current_quantity INT DEFAULT 0;
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS expiration_date DATE DEFAULT (CURRENT_DATE + INTERVAL '30 days');
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS expiry_date TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days');
ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'FRESH';

-- Inventory Audit Logs
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
    total_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    subtotal_amount NUMERIC(10,2) DEFAULT 0.00,
    discount_amount NUMERIC(10,2) DEFAULT 0.00,
    discount_label TEXT,
    discount_type TEXT DEFAULT 'NONE',
    discount_pct NUMERIC(5,2) DEFAULT 0.00,
    final_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    payment_method TEXT NOT NULL DEFAULT 'cash',
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

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_number TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS student_name TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS subtotal_amount NUMERIC(10,2);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_label TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_type TEXT DEFAULT 'NONE';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_pct NUMERIC(5,2) DEFAULT 0.00;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS final_amount NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS total_amount NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'COMPLETED';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_status TEXT DEFAULT 'COMPLETED';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_source TEXT DEFAULT 'POS_REGISTER_01';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cash_tendered NUMERIC(10,2);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cash_change NUMERIC(10,2);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tray_photo_url TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS is_voided BOOLEAN DEFAULT FALSE;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS void_reason TEXT;

-- Order Line Items
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    total_price NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    subtotal NUMERIC(10,2) DEFAULT 0.00,
    calories INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS unit_price NUMERIC(10,2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS quantity INT NOT NULL DEFAULT 1;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS total_price NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS subtotal NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS calories INT DEFAULT 0;

-- Wallet Transactions & Audit Trails
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
    price NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    session TEXT DEFAULT 'Lunch Break',
    pickup_slot TEXT DEFAULT '12:00 PM',
    pickup_time_slot TEXT DEFAULT '12:00 PM',
    pickup_date DATE DEFAULT CURRENT_DATE,
    shelf_location TEXT DEFAULT 'Shelf B2',
    status TEXT NOT NULL DEFAULT 'Pending',
    token TEXT,
    is_archived BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS student_id UUID;
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS student_name TEXT;
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS student_id_number TEXT;
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS item_name TEXT;
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS price NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS session TEXT DEFAULT 'Lunch Break';
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS pickup_slot TEXT DEFAULT '12:00 PM';
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS pickup_date DATE DEFAULT CURRENT_DATE;
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS pickup_time_slot TEXT DEFAULT '12:00 PM';
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS shelf_location TEXT DEFAULT 'Shelf B2';
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'Pending';
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS token TEXT;
ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE;

-- Pre-Order Slots
CREATE TABLE IF NOT EXISTS public.preorder_slots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slot_name TEXT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    prep_lead_minutes INT DEFAULT 30,
    max_orders INT DEFAULT 25,
    max_capacity INT DEFAULT 100,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Meal Disputes & Parent Tickets
CREATE TABLE IF NOT EXISTS public.meal_disputes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id TEXT NOT NULL,
    student_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    student_name TEXT,
    parent_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    dispute_reason TEXT NOT NULL,
    details TEXT,
    photo_url TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING',
    resolution_notes TEXT,
    admin_notes TEXT,
    resolved_by TEXT,
    refund_amount NUMERIC(10,2) DEFAULT 0.00,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS details TEXT;
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS admin_notes TEXT;
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.dispute_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_number VARCHAR(50) UNIQUE NOT NULL,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    disputed_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    dispute_reason VARCHAR(100) NOT NULL,
    parent_notes TEXT,
    tray_photo_url TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING_REVIEW',
    admin_resolution_notes TEXT,
    resolved_by_admin UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Cashier Shift Reconciliations (Z-Reading)
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

-- Verified Parent-Student Links
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
    severity TEXT DEFAULT 'info',
    action_url TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS severity TEXT DEFAULT 'info';
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS action_url TEXT;

-- Notification Preferences
CREATE TABLE IF NOT EXISTS public.notification_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE UNIQUE,
    on_every_purchase BOOLEAN DEFAULT TRUE,
    on_daily_cap_80_pct BOOLEAN DEFAULT TRUE,
    on_allergen_flag BOOLEAN DEFAULT TRUE,
    on_pay_later_use BOOLEAN DEFAULT TRUE,
    on_override_approved BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Canteen Settings & Governance Policies
CREATE TABLE IF NOT EXISTS public.canteen_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Hardware Topology Mappings
CREATE TABLE IF NOT EXISTS public.hardware_mappings (
    terminal_id TEXT PRIMARY KEY,
    camera_id TEXT,
    pos_register_id TEXT,
    pos_register_name TEXT DEFAULT 'Main Counter POS',
    camera_device_index INT DEFAULT 0,
    rfid_reader_port TEXT DEFAULT 'COM3',
    assigned_station TEXT DEFAULT 'Main Counter',
    location_name TEXT DEFAULT 'Main Canteen Counter',
    is_online BOOLEAN DEFAULT TRUE,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'offline')),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Governance Overrides Audit Log
CREATE TABLE IF NOT EXISTS public.governance_overrides (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    cashier_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    override_type TEXT NOT NULL,
    reason TEXT NOT NULL,
    approved_by_pin BOOLEAN DEFAULT FALSE,
    authorized_by TEXT,
    manager_pin_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Topup Requests (GCash/Maya Receipt Uploads)
CREATE TABLE IF NOT EXISTS public.topup_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_name TEXT,
    parent_name TEXT,
    submitter_role TEXT DEFAULT 'student',
    amount NUMERIC(10,2) NOT NULL,
    reference_number TEXT NOT NULL,
    screenshot_url TEXT,
    receipt_img TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING',
    admin_notes TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.topup_requests ADD COLUMN IF NOT EXISTS parent_name TEXT;
ALTER TABLE public.topup_requests ADD COLUMN IF NOT EXISTS submitter_role TEXT DEFAULT 'student';
ALTER TABLE public.topup_requests ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
ALTER TABLE public.topup_requests ADD COLUMN IF NOT EXISTS receipt_img TEXT;

-- Kitchen Display System (KDS) Tickets
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

-- AI Tray Detection Logs
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

-- System Audit Logs
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    action_type TEXT,
    entity_type TEXT,
    entity_id TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    ip_address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.system_audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    user_role TEXT,
    action_type TEXT NOT NULL,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Offline Transaction Queue & Kiosk Balance Reservations
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

CREATE TABLE IF NOT EXISTS public.offline_balance_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id VARCHAR(50) NOT NULL,
    terminal_id VARCHAR(50) NOT NULL,
    reservation_token VARCHAR(64) UNIQUE NOT NULL,
    reserved_amount NUMERIC(10, 2) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_settled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Student Subsidies & Auto-Expiring Allowances
CREATE TABLE IF NOT EXISTS public.student_subsidies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    program_name TEXT,
    subsidy_name TEXT,
    amount NUMERIC(10,2) DEFAULT 0.00,
    daily_subsidy_amount NUMERIC(10,2) DEFAULT 0.00,
    current_cycle_spent NUMERIC(10,2) DEFAULT 0.00,
    frequency TEXT DEFAULT 'DAILY' CHECK (frequency IN ('DAILY', 'WEEKLY', 'MONTHLY', 'ONE_TIME')),
    expires_daily BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Category Spending Rules & Limits
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

CREATE TABLE IF NOT EXISTS public.category_spending_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_slug VARCHAR(50) NOT NULL,
    daily_cap NUMERIC(10, 2) NOT NULL DEFAULT 100.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(student_id, category_slug)
);

-- Hard Medical & Dietary Allergen Guardrails
CREATE TABLE IF NOT EXISTS public.student_allergen_guardrails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    allergen_tag VARCHAR(50) NOT NULL,
    severity_level VARCHAR(20) NOT NULL DEFAULT 'HARD_BLOCK',
    notes TEXT,
    set_by_parent_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Recipe Bill of Materials (BOM) & Yield Tracking
CREATE TABLE IF NOT EXISTS public.recipe_bom (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    menu_item_id UUID NOT NULL,
    raw_ingredient_id UUID NOT NULL,
    quantity_required NUMERIC(10, 3) NOT NULL,
    unit_of_measure VARCHAR(30) NOT NULL DEFAULT 'kg',
    wastage_allowance_pct NUMERIC(5, 2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- SIS Tuition Batches & Export Ledgers
CREATE TABLE IF NOT EXISTS public.sis_tuition_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_reference TEXT UNIQUE NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL,
    student_count INT NOT NULL,
    status TEXT DEFAULT 'EXPORTED_TO_SIS',
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tuition_reconciliation_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_reference TEXT UNIQUE NOT NULL,
    total_debt_cleared NUMERIC(10,2) NOT NULL,
    student_count INT NOT NULL,
    cleared_by TEXT NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tuition_batch_exports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_reference VARCHAR(64) UNIQUE NOT NULL,
    export_format VARCHAR(20) NOT NULL DEFAULT 'CSV',
    total_records INTEGER NOT NULL DEFAULT 0,
    total_pay_later_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    exported_by_admin UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    export_data_payload JSONB NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'EXPORTED',
    created_at TIMESTAMPTZ DEFAULT NOW()
);


-- Universal Column Reconcilers (Ensures existing tables receive any missing columns)
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS camera_id TEXT;
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS pos_register_id TEXT;
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS pos_register_name TEXT DEFAULT 'Main Counter POS';
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS camera_device_index INT DEFAULT 0;
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS rfid_reader_port TEXT DEFAULT 'COM3';
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS assigned_station TEXT DEFAULT 'Main Counter';
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS location_name TEXT DEFAULT 'Main Canteen Counter';
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT TRUE;
ALTER TABLE public.hardware_mappings ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

ALTER TABLE public.preorder_slots ADD COLUMN IF NOT EXISTS slot_name TEXT;
ALTER TABLE public.preorder_slots ADD COLUMN IF NOT EXISTS start_time TIME;
ALTER TABLE public.preorder_slots ADD COLUMN IF NOT EXISTS end_time TIME;
ALTER TABLE public.preorder_slots ADD COLUMN IF NOT EXISTS prep_lead_minutes INT DEFAULT 30;
ALTER TABLE public.preorder_slots ADD COLUMN IF NOT EXISTS max_orders INT DEFAULT 25;
ALTER TABLE public.preorder_slots ADD COLUMN IF NOT EXISTS max_capacity INT DEFAULT 100;
ALTER TABLE public.preorder_slots ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS wallet_id UUID REFERENCES public.wallets(id) ON DELETE SET NULL;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS transaction_type TEXT;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS amount NUMERIC(10,2);
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS balance_before NUMERIC(10,2);
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS balance_after NUMERIC(10,2);
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS reference_id TEXT;
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS payment_channel TEXT DEFAULT 'RFID';
ALTER TABLE public.wallet_transactions ADD COLUMN IF NOT EXISTS description TEXT;

ALTER TABLE public.inventory_logs ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES public.products(id) ON DELETE SET NULL;
ALTER TABLE public.inventory_logs ADD COLUMN IF NOT EXISTS batch_id UUID REFERENCES public.inventory_batches(id) ON DELETE SET NULL;
ALTER TABLE public.inventory_logs ADD COLUMN IF NOT EXISTS change_type TEXT;
ALTER TABLE public.inventory_logs ADD COLUMN IF NOT EXISTS quantity INT;
ALTER TABLE public.inventory_logs ADD COLUMN IF NOT EXISTS remaining_stock INT;
ALTER TABLE public.inventory_logs ADD COLUMN IF NOT EXISTS reason TEXT;
ALTER TABLE public.inventory_logs ADD COLUMN IF NOT EXISTS performed_by TEXT;

ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS cashier_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL;
ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS override_type TEXT;
ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS reason TEXT;
ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS approved_by_pin BOOLEAN DEFAULT FALSE;
ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS authorized_by TEXT;
ALTER TABLE public.governance_overrides ADD COLUMN IF NOT EXISTS manager_pin_verified BOOLEAN DEFAULT FALSE;

ALTER TABLE public.kds_tickets ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE;
ALTER TABLE public.kds_tickets ADD COLUMN IF NOT EXISTS ticket_number TEXT;
ALTER TABLE public.kds_tickets ADD COLUMN IF NOT EXISTS session TEXT DEFAULT 'Lunch Break';
ALTER TABLE public.kds_tickets ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.kds_tickets ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'RECEIVED';

ALTER TABLE public.ai_detection_logs ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL;
ALTER TABLE public.ai_detection_logs ADD COLUMN IF NOT EXISTS image_hash TEXT;
ALTER TABLE public.ai_detection_logs ADD COLUMN IF NOT EXISTS detected_items JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.ai_detection_logs ADD COLUMN IF NOT EXISTS confidence_score NUMERIC(5,4);
ALTER TABLE public.ai_detection_logs ADD COLUMN IF NOT EXISTS latency_ms INT;
ALTER TABLE public.ai_detection_logs ADD COLUMN IF NOT EXISTS corrected_items JSONB;

ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS action TEXT;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS action_type TEXT;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS entity_type TEXT;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS entity_id TEXT;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS details JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS ip_address TEXT;

ALTER TABLE public.system_audit_logs ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.system_audit_logs ADD COLUMN IF NOT EXISTS user_role TEXT;
ALTER TABLE public.system_audit_logs ADD COLUMN IF NOT EXISTS action_type TEXT;
ALTER TABLE public.system_audit_logs ADD COLUMN IF NOT EXISTS details JSONB DEFAULT '{}'::jsonb;

ALTER TABLE public.offline_transaction_queue ADD COLUMN IF NOT EXISTS device_id TEXT;
ALTER TABLE public.offline_transaction_queue ADD COLUMN IF NOT EXISTS offline_reference TEXT;
ALTER TABLE public.offline_transaction_queue ADD COLUMN IF NOT EXISTS transaction_payload JSONB;
ALTER TABLE public.offline_transaction_queue ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'QUEUED';
ALTER TABLE public.offline_transaction_queue ADD COLUMN IF NOT EXISTS error_message TEXT;
ALTER TABLE public.offline_transaction_queue ADD COLUMN IF NOT EXISTS synced_at TIMESTAMPTZ;

ALTER TABLE public.offline_balance_reservations ADD COLUMN IF NOT EXISTS student_id VARCHAR(50);
ALTER TABLE public.offline_balance_reservations ADD COLUMN IF NOT EXISTS terminal_id VARCHAR(50);
ALTER TABLE public.offline_balance_reservations ADD COLUMN IF NOT EXISTS reservation_token VARCHAR(64);
ALTER TABLE public.offline_balance_reservations ADD COLUMN IF NOT EXISTS reserved_amount NUMERIC(10,2);
ALTER TABLE public.offline_balance_reservations ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE public.offline_balance_reservations ADD COLUMN IF NOT EXISTS is_settled BOOLEAN DEFAULT FALSE;

ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS program_name TEXT;
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS subsidy_name TEXT;
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS amount NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS daily_subsidy_amount NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS current_cycle_spent NUMERIC(10,2) DEFAULT 0.00;
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS frequency TEXT DEFAULT 'DAILY';
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS expires_daily BOOLEAN DEFAULT TRUE;
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;
ALTER TABLE public.student_subsidies ADD COLUMN IF NOT EXISTS active BOOLEAN DEFAULT TRUE;

ALTER TABLE public.category_spending_rules ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.category_spending_rules ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.menu_categories(id) ON DELETE SET NULL;
ALTER TABLE public.category_spending_rules ADD COLUMN IF NOT EXISTS max_items_per_day INT DEFAULT 2;
ALTER TABLE public.category_spending_rules ADD COLUMN IF NOT EXISTS max_amount_per_day NUMERIC(10,2) DEFAULT 150.00;
ALTER TABLE public.category_spending_rules ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN DEFAULT FALSE;

ALTER TABLE public.category_spending_limits ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.category_spending_limits ADD COLUMN IF NOT EXISTS category_slug VARCHAR(50);
ALTER TABLE public.category_spending_limits ADD COLUMN IF NOT EXISTS daily_cap NUMERIC(10,2) DEFAULT 100.00;
ALTER TABLE public.category_spending_limits ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;

ALTER TABLE public.student_allergen_guardrails ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.student_allergen_guardrails ADD COLUMN IF NOT EXISTS allergen_tag VARCHAR(50);
ALTER TABLE public.student_allergen_guardrails ADD COLUMN IF NOT EXISTS severity_level VARCHAR(20) DEFAULT 'HARD_BLOCK';
ALTER TABLE public.student_allergen_guardrails ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.student_allergen_guardrails ADD COLUMN IF NOT EXISTS set_by_parent_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.recipe_bom ADD COLUMN IF NOT EXISTS menu_item_id UUID;
ALTER TABLE public.recipe_bom ADD COLUMN IF NOT EXISTS raw_ingredient_id UUID;
ALTER TABLE public.recipe_bom ADD COLUMN IF NOT EXISTS quantity_required NUMERIC(10,3);
ALTER TABLE public.recipe_bom ADD COLUMN IF NOT EXISTS unit_of_measure VARCHAR(30) DEFAULT 'kg';
ALTER TABLE public.recipe_bom ADD COLUMN IF NOT EXISTS wastage_allowance_pct NUMERIC(5,2) DEFAULT 0.00;

ALTER TABLE public.sis_tuition_batches ADD COLUMN IF NOT EXISTS batch_reference TEXT;
ALTER TABLE public.sis_tuition_batches ADD COLUMN IF NOT EXISTS total_amount NUMERIC(10,2);
ALTER TABLE public.sis_tuition_batches ADD COLUMN IF NOT EXISTS student_count INT;
ALTER TABLE public.sis_tuition_batches ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'EXPORTED_TO_SIS';
ALTER TABLE public.sis_tuition_batches ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.tuition_reconciliation_batches ADD COLUMN IF NOT EXISTS batch_reference TEXT;
ALTER TABLE public.tuition_reconciliation_batches ADD COLUMN IF NOT EXISTS total_debt_cleared NUMERIC(10,2);
ALTER TABLE public.tuition_reconciliation_batches ADD COLUMN IF NOT EXISTS student_count INT;
ALTER TABLE public.tuition_reconciliation_batches ADD COLUMN IF NOT EXISTS cleared_by TEXT;
ALTER TABLE public.tuition_reconciliation_batches ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.tuition_batch_exports ADD COLUMN IF NOT EXISTS batch_reference VARCHAR(64);
ALTER TABLE public.tuition_batch_exports ADD COLUMN IF NOT EXISTS export_format VARCHAR(20) DEFAULT 'CSV';
ALTER TABLE public.tuition_batch_exports ADD COLUMN IF NOT EXISTS total_records INTEGER DEFAULT 0;
ALTER TABLE public.tuition_batch_exports ADD COLUMN IF NOT EXISTS total_pay_later_amount NUMERIC(12,2) DEFAULT 0.00;
ALTER TABLE public.tuition_batch_exports ADD COLUMN IF NOT EXISTS exported_by_admin UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.tuition_batch_exports ADD COLUMN IF NOT EXISTS export_data_payload JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.tuition_batch_exports ADD COLUMN IF NOT EXISTS status VARCHAR(30) DEFAULT 'EXPORTED';

ALTER TABLE public.cashier_shift_reconciliations ADD COLUMN IF NOT EXISTS cashier_id TEXT;
ALTER TABLE public.cashier_shift_reconciliations ADD COLUMN IF NOT EXISTS opening_cash NUMERIC(10,2);
ALTER TABLE public.cashier_shift_reconciliations ADD COLUMN IF NOT EXISTS cash_sales NUMERIC(10,2);
ALTER TABLE public.cashier_shift_reconciliations ADD COLUMN IF NOT EXISTS ending_cash NUMERIC(10,2);
ALTER TABLE public.cashier_shift_reconciliations ADD COLUMN IF NOT EXISTS variance NUMERIC(10,2);
ALTER TABLE public.cashier_shift_reconciliations ADD COLUMN IF NOT EXISTS expected_cash NUMERIC(10,2);
ALTER TABLE public.cashier_shift_reconciliations ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.parent_student_link_requests ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.parent_student_link_requests ADD COLUMN IF NOT EXISTS parent_email TEXT;
ALTER TABLE public.parent_student_link_requests ADD COLUMN IF NOT EXISTS student_id_number TEXT;
ALTER TABLE public.parent_student_link_requests ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.parent_student_link_requests ADD COLUMN IF NOT EXISTS student_name TEXT;
ALTER TABLE public.parent_student_link_requests ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';

ALTER TABLE public.parent_student_links ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.parent_student_links ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.parent_student_links ADD COLUMN IF NOT EXISTS relationship TEXT DEFAULT 'Parent';

ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS on_every_purchase BOOLEAN DEFAULT TRUE;
ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS on_daily_cap_80_pct BOOLEAN DEFAULT TRUE;
ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS on_allergen_flag BOOLEAN DEFAULT TRUE;
ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS on_pay_later_use BOOLEAN DEFAULT TRUE;
ALTER TABLE public.notification_preferences ADD COLUMN IF NOT EXISTS on_override_approved BOOLEAN DEFAULT TRUE;

-- ------------------------------------------------------------------------------
-- 3. DATA INTEGRITY & NUMERIC CHECK CONSTRAINTS
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    -- Products
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_products_price_non_negative') THEN
        ALTER TABLE public.products ADD CONSTRAINT chk_products_price_non_negative CHECK (price >= 0.00);
    END IF;

    -- Wallets
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_wallets_balance_non_negative') THEN
        ALTER TABLE public.wallets ADD CONSTRAINT chk_wallets_balance_non_negative CHECK (balance >= 0.00);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_wallets_liability_non_negative') THEN
        ALTER TABLE public.wallets ADD CONSTRAINT chk_wallets_liability_non_negative CHECK (credit_liability >= 0.00);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_wallets_daily_limit_positive') THEN
        ALTER TABLE public.wallets ADD CONSTRAINT chk_wallets_daily_limit_positive CHECK (daily_limit >= 0.00);
    END IF;

    -- Profiles
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_profiles_liability_non_negative') THEN
        ALTER TABLE public.profiles ADD CONSTRAINT chk_profiles_liability_non_negative CHECK (credit_liability >= 0.00);
    END IF;

    -- Orders & Items
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_final_amount_non_negative') THEN
        ALTER TABLE public.orders ADD CONSTRAINT chk_orders_final_amount_non_negative CHECK (final_amount >= 0.00);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_order_items_qty_positive') THEN
        ALTER TABLE public.order_items ADD CONSTRAINT chk_order_items_qty_positive CHECK (quantity > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_order_items_unit_price_non_negative') THEN
        ALTER TABLE public.order_items ADD CONSTRAINT chk_order_items_unit_price_non_negative CHECK (unit_price >= 0.00);
    END IF;

    -- Governance Overrides Constraints
    ALTER TABLE public.governance_overrides DROP CONSTRAINT IF EXISTS governance_overrides_override_type_check;
    ALTER TABLE public.governance_overrides ADD CONSTRAINT governance_overrides_override_type_check
        CHECK (override_type IN (
            'calorie_limit', 'allergen_block', 'spending_limit', 'pay_later_cap',
            'restricted_category', 'weekly_limit', 'DIETARY_OVERRIDE',
            'PAY_LATER_CEILING_OVERRIDE', 'DAILY_SPENDING_CAP_OVERRIDE', 'CUSTOM'
        ));
END $$;

-- ------------------------------------------------------------------------------
-- 4. HIGH-TRAFFIC PERFORMANCE INDEXES & UNIQUE INDEXES
-- ------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_profiles_rfid_uid ON public.profiles(rfid_uid) WHERE rfid_uid IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_student_id ON public.profiles(student_id_number) WHERE student_id_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);

CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON public.wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created ON public.wallet_transactions(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);
CREATE INDEX IF NOT EXISTS idx_products_ai_label ON public.products(ai_label);
CREATE INDEX IF NOT EXISTS idx_batches_product_id ON public.inventory_batches(product_id);
CREATE INDEX IF NOT EXISTS idx_batches_product_expiry ON public.inventory_batches(product_id, expiration_date ASC);

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at_desc ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(order_status);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items(product_id);

CREATE INDEX IF NOT EXISTS idx_preorders_student_id ON public.preorders(student_id);
CREATE INDEX IF NOT EXISTS idx_preorders_status ON public.preorders(status);
CREATE INDEX IF NOT EXISTS idx_preorders_token ON public.preorders(token);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON public.notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON public.notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_gov_overrides_student ON public.governance_overrides(student_id);
CREATE INDEX IF NOT EXISTS idx_gov_overrides_created ON public.governance_overrides(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_recipe_bom_menu ON public.recipe_bom(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_category_spending_student ON public.category_spending_limits(student_id);
CREATE INDEX IF NOT EXISTS idx_allergen_guardrails_student ON public.student_allergen_guardrails(student_id);
CREATE INDEX IF NOT EXISTS idx_dispute_tickets_order ON public.dispute_tickets(order_id);
CREATE INDEX IF NOT EXISTS idx_dispute_tickets_parent ON public.dispute_tickets(parent_id);


-- Unique Constraints & Conflict Target Indexes
CREATE UNIQUE INDEX IF NOT EXISTS uq_offline_tx_ref ON public.offline_transaction_queue (offline_reference);
CREATE UNIQUE INDEX IF NOT EXISTS uq_wallets_user_id ON public.wallets (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_parent_student_links ON public.parent_student_links (parent_id, student_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_preferences_user ON public.notification_preferences (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_category_spending_limits ON public.category_spending_limits (student_id, category_slug);

-- Enforce unique topup reference numbers (excludes rejected submissions)
CREATE UNIQUE INDEX IF NOT EXISTS uq_topup_ref_no 
ON public.topup_requests(reference_number) 
WHERE status != 'REJECTED' AND status != 'Rejected';

-- ------------------------------------------------------------------------------
-- 5. VIEWS
-- ------------------------------------------------------------------------------
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

-- ------------------------------------------------------------------------------
-- 6. DROP PREVIOUS FUNCTION SIGNATURES (AVOIDS 42P13 CONFLICTS)
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
              'fn_deduct_cart_stock_fifo',
              'fn_deduct_wallet_balance',
              'fn_credit_wallet_balance',
              'fn_admin_update_wallet',
              'fn_process_gcash_webhook',
              'fn_sync_offline_transaction',
              'settle_pay_later_liability',
              'fn_claim_preorder_by_student',
              'fn_increment_product_stock',
              'fn_log_spoilage',
              'fn_create_sis_tuition_batch',
              'fn_reconcile_tuition_pay_later_batch',
              'fn_toggle_pay_later_pre_auth',
              'fn_generate_student_dynamic_qr',
              'fn_add_student_calories',
              'fn_reset_daily_calories',
              'fn_refresh_batch_expiry_statuses'
          )
    ) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_signature || ' CASCADE;';
    END LOOP;
END $$;

-- ------------------------------------------------------------------------------
-- 7. ATOMIC STORED PROCEDURES & PROCEDURAL LOGIC
-- ------------------------------------------------------------------------------

-- A. Daily Calorie Auto-Reset Trigger Function
CREATE OR REPLACE FUNCTION public.fn_reset_daily_calories()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.last_calorie_reset_date IS NULL OR NEW.last_calorie_reset_date < CURRENT_DATE THEN
        NEW.daily_calories_spent := 0;
        NEW.last_calorie_reset_date := CURRENT_DATE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_reset_daily_calories ON public.profiles;
CREATE TRIGGER trg_reset_daily_calories
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.fn_reset_daily_calories();

-- B. Product Stock Dual-Column Synchronization Trigger
CREATE OR REPLACE FUNCTION public.fn_sync_product_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        IF NEW.stock IS DISTINCT FROM OLD.stock THEN
            NEW.stock_quantity := NEW.stock;
        ELSIF NEW.stock_quantity IS DISTINCT FROM OLD.stock_quantity THEN
            NEW.stock := NEW.stock_quantity;
        END IF;
        NEW.is_available := (COALESCE(NEW.stock, NEW.stock_quantity, 0) > 0);
        NEW.available := NEW.is_available;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_product_stock ON public.products;
CREATE TRIGGER trg_sync_product_stock
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.fn_sync_product_stock();

-- C. Single-Call Atomic Multi-Item Cart FIFO Stock Deduction (ACID with Row Locking)
CREATE OR REPLACE FUNCTION public.fn_deduct_cart_stock_fifo(p_items JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_prod_id UUID;
    v_qty_needed INT;
    v_current_stock INT;
    v_batch RECORD;
    v_qty_to_deduct INT;
    v_rem_in_batch INT;
    v_deducted_summary JSONB := '[]'::jsonb;
BEGIN
    IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
        RETURN jsonb_build_object('success', true, 'message', 'No items to deduct', 'deductions', '[]'::jsonb);
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := (v_item->>'id')::UUID;
        v_qty_needed := COALESCE((v_item->>'qty')::INT, (v_item->>'quantity')::INT, 1);

        IF v_prod_id IS NOT NULL AND v_qty_needed > 0 THEN
            -- Acquire row-level lock on the master product
            SELECT stock INTO v_current_stock
            FROM public.products
            WHERE id = v_prod_id
            FOR UPDATE;

            IF FOUND THEN
                UPDATE public.products
                SET stock = GREATEST(0, stock - v_qty_needed),
                    stock_quantity = GREATEST(0, stock_quantity - v_qty_needed),
                    is_available = (GREATEST(0, stock - v_qty_needed) > 0),
                    available = (GREATEST(0, stock - v_qty_needed) > 0),
                    updated_at = NOW()
                WHERE id = v_prod_id;

                v_qty_to_deduct := v_qty_needed;
                FOR v_batch IN
                    SELECT id, quantity_remaining, current_quantity, status
                    FROM public.inventory_batches
                    WHERE product_id = v_prod_id
                      AND COALESCE(quantity_remaining, current_quantity, 0) > 0
                      AND status NOT IN ('DEPLETED', 'EXPIRED')
                    ORDER BY expiration_date ASC, created_at ASC
                    FOR UPDATE
                LOOP
                    EXIT WHEN v_qty_to_deduct <= 0;

                    IF COALESCE(v_batch.quantity_remaining, v_batch.current_quantity, 0) <= v_qty_to_deduct THEN
                        v_qty_to_deduct := v_qty_to_deduct - COALESCE(v_batch.quantity_remaining, v_batch.current_quantity, 0);
                        UPDATE public.inventory_batches
                        SET quantity_remaining = 0,
                            current_quantity = 0,
                            status = 'DEPLETED',
                            updated_at = NOW()
                        WHERE id = v_batch.id;
                    ELSE
                        v_rem_in_batch := COALESCE(v_batch.quantity_remaining, v_batch.current_quantity, 0) - v_qty_to_deduct;
                        v_qty_to_deduct := 0;
                        UPDATE public.inventory_batches
                        SET quantity_remaining = v_rem_in_batch,
                            current_quantity = v_rem_in_batch,
                            updated_at = NOW()
                        WHERE id = v_batch.id;
                    END IF;
                END LOOP;

                v_deducted_summary := v_deducted_summary || jsonb_build_object(
                    'product_id', v_prod_id,
                    'quantity_deducted', v_qty_needed,
                    'remaining_stock', GREATEST(0, v_current_stock - v_qty_needed)
                );
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'deductions', v_deducted_summary,
        'timestamp', NOW()
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

-- D. Single Product FIFO Stock Batch Deduction
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
    v_res JSONB;
BEGIN
    v_res := public.fn_deduct_cart_stock_fifo(jsonb_build_array(jsonb_build_object('id', p_product_id, 'qty', p_quantity)));
    IF (v_res->>'success')::BOOLEAN = TRUE THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;
END;
$$;

-- E. Atomic Wallet Balance Deduction (Strict Row-Level Lock & Profile Sync)
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
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT: Deduction amount must be greater than zero.';
    END IF;

    SELECT balance INTO v_current_balance
    FROM public.wallets
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'WALLET_NOT_FOUND: No wallet exists for user %', p_user_id;
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Available ₱%, required ₱%', v_current_balance, p_amount;
    END IF;

    v_new_balance := ROUND(v_current_balance - p_amount, 2);

    UPDATE public.wallets
    SET balance     = v_new_balance,
        daily_spent = COALESCE(daily_spent, 0) + p_amount,
        updated_at  = NOW()
    WHERE user_id = p_user_id;

    UPDATE public.profiles 
    SET balance = v_new_balance, 
        updated_at = NOW() 
    WHERE id = p_user_id;

    RETURN v_new_balance;
END;
$$;

-- F. Atomic Wallet Top-Up Credit
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
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT: Credit amount must be positive';
    END IF;

    INSERT INTO public.wallets (user_id, balance, updated_at)
    VALUES (p_user_id, p_amount, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET balance    = public.wallets.balance + EXCLUDED.balance,
        updated_at = NOW()
    RETURNING balance INTO v_new_balance;

    UPDATE public.profiles
    SET balance = v_new_balance,
        updated_at = NOW()
    WHERE id = p_user_id;

    RETURN v_new_balance;
END;
$$;

-- G. Universal Admin Wallet & Spending Limit Update RPC
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
    RETURNING balance, daily_limit
    INTO v_new_bal, v_new_limit;

    UPDATE public.profiles
    SET balance = COALESCE(p_balance, balance),
        daily_limit = COALESCE(p_daily_limit, daily_limit),
        credit_liability = COALESCE(p_credit_liability, credit_liability),
        updated_at = NOW()
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'balance', v_new_bal,
        'daily_limit', v_new_limit
    );
END;
$$;

-- H. Atomic Pay Later Emergency Debt Settlement
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
    v_curr_debt NUMERIC(10,2);
    v_curr_bal  NUMERIC(10,2);
    v_new_debt  NUMERIC(10,2);
    v_new_bal   NUMERIC(10,2);
    v_wallet_id UUID;
BEGIN
    IF p_repayment_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Repayment amount must be positive');
    END IF;

    SELECT credit_liability, balance INTO v_curr_debt, v_curr_bal
    FROM public.profiles
    WHERE id = p_student_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Student profile not found');
    END IF;

    SELECT id INTO v_wallet_id FROM public.wallets WHERE user_id = p_student_id FOR UPDATE;

    v_new_debt := GREATEST(0.00, ROUND(COALESCE(v_curr_debt, 0.00) - p_repayment_amount, 2));

    IF LOWER(p_payment_method) = 'rfid' THEN
        IF v_curr_bal < p_repayment_amount THEN
            RETURN jsonb_build_object('success', false, 'error', 'Insufficient RFID wallet balance for debt repayment');
        END IF;

        v_new_bal := ROUND(v_curr_bal - p_repayment_amount, 2);

        UPDATE public.wallets
        SET balance = v_new_bal, credit_liability = v_new_debt, updated_at = NOW()
        WHERE user_id = p_student_id;

        UPDATE public.profiles
        SET balance = v_new_bal, credit_liability = v_new_debt, updated_at = NOW()
        WHERE id = p_student_id;
    ELSE
        v_new_bal := v_curr_bal;

        UPDATE public.wallets
        SET credit_liability = v_new_debt, updated_at = NOW()
        WHERE user_id = p_student_id;

        UPDATE public.profiles
        SET credit_liability = v_new_debt, updated_at = NOW()
        WHERE id = p_student_id;
    END IF;

    IF v_wallet_id IS NOT NULL THEN
        INSERT INTO public.wallet_transactions (
            wallet_id, user_id, transaction_type, amount, balance_before, balance_after, payment_method, payment_channel, description
        ) VALUES (
            v_wallet_id, p_student_id, 'purchase', p_repayment_amount, v_curr_bal, v_new_bal, LOWER(p_payment_method), UPPER(p_payment_method), 'Pay Later emergency debt repayment clearance'
        );
    END IF;

    RETURN jsonb_build_object('success', true, 'remaining_liability', v_new_debt, 'new_balance', v_new_bal);
END;
$$;

-- I. Atomic Pre-Order Handover & Claiming RPC
CREATE OR REPLACE FUNCTION public.fn_claim_preorder_by_student(
    p_student_id UUID,
    p_preorder_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_po RECORD;
BEGIN
    IF p_preorder_id IS NOT NULL THEN
        SELECT * INTO v_po 
        FROM public.preorders 
        WHERE id = p_preorder_id 
          AND status != 'Claimed'
        FOR UPDATE;
    ELSE
        SELECT * INTO v_po 
        FROM public.preorders 
        WHERE student_id = p_student_id 
          AND status IN ('Pending', 'Preparing', 'Ready')
        ORDER BY created_at ASC
        LIMIT 1
        FOR UPDATE;
    END IF;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'No active uncollected pre-order found.');
    END IF;

    UPDATE public.preorders
    SET status = 'Claimed',
        updated_at = NOW()
    WHERE id = v_po.id;

    RETURN jsonb_build_object(
        'success', true,
        'preorder_id', v_po.id,
        'item_name', v_po.item_name,
        'student_id', v_po.student_id,
        'student_name', v_po.student_name,
        'status', 'Claimed',
        'claimed_at', NOW()
    );
END;
$$;

-- J. Instant GCash Webhook Auto-Credit
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

    UPDATE public.profiles SET balance = v_new_bal, updated_at = NOW() WHERE id = p_student_id;

    INSERT INTO public.wallet_transactions (user_id, transaction_type, amount, balance_before, balance_after, reference_id, payment_channel, description)
    VALUES (p_student_id, 'RELOAD_GCASH', p_amount, COALESCE(v_old_bal, 0), v_new_bal, p_ref_no, 'GCASH_WEBHOOK', 'Instant GCash Webhook Auto-Credit');

    RETURN jsonb_build_object('success', true, 'new_balance', v_new_bal, 'ref_no', p_ref_no);
END;
$$;

-- K. Offline Transaction Sync Procedure
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

-- L. Product Stock Increment (Overloaded for p_delta and p_qty)
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
    SET stock = GREATEST(0, stock + p_delta), 
        stock_quantity = GREATEST(0, stock_quantity + p_delta),
        updated_at = NOW()
    WHERE id = p_product_id
    RETURNING stock INTO v_new_stock;
    RETURN v_new_stock;
END;
$$;

-- M. Inventory Spoilage Logging & FIFO Batch Disposal
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
            current_quantity = GREATEST(0, current_quantity - p_quantity),
            status = CASE WHEN quantity_remaining - p_quantity <= 0 THEN 'DEPLETED' ELSE status END,
            updated_at = NOW()
        WHERE id = p_batch_id;
    END IF;

    UPDATE public.products
    SET stock = GREATEST(0, stock - p_quantity), 
        stock_quantity = GREATEST(0, stock_quantity - p_quantity),
        updated_at = NOW()
    WHERE id = p_product_id;

    v_total_cost := COALESCE(v_unit_cost, 0.00) * p_quantity;

    INSERT INTO public.inventory_logs (product_id, batch_id, change_type, quantity, remaining_stock, reason, performed_by)
    VALUES (p_product_id, p_batch_id, 'SPOILAGE_DISPOSAL', -p_quantity, 0, p_reason, p_performed_by);

    RETURN jsonb_build_object('success', true, 'quantity_logged', p_quantity, 'total_cost', v_total_cost);
END;
$$;

-- N. SIS / Tuition Batch Generation & Reconciliation
CREATE OR REPLACE FUNCTION public.fn_create_sis_tuition_batch(
    p_batch_ref TEXT DEFAULT NULL,
    p_total_amount NUMERIC(10,2) DEFAULT NULL,
    p_student_count INT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_admin_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id UUID;
    v_ref TEXT := COALESCE(p_batch_ref, 'SIS-BATCH-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MI'));
    v_tot NUMERIC(10,2) := 0.00;
    v_cnt INT := 0;
BEGIN
    IF p_total_amount IS NULL OR p_student_count IS NULL THEN
        SELECT COALESCE(SUM(credit_liability), 0.00), COUNT(*)
        INTO v_tot, v_cnt
        FROM public.profiles
        WHERE credit_liability > 0;
    ELSE
        v_tot := p_total_amount;
        v_cnt := p_student_count;
    END IF;

    INSERT INTO public.sis_tuition_batches (batch_reference, total_amount, student_count, status, notes)
    VALUES (v_ref, v_tot, v_cnt, 'EXPORTED_TO_SIS', p_notes)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'batch_id', v_id, 'batch_reference', v_ref, 'total_amount', v_tot, 'student_count', v_cnt);
END;
$$;

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

    UPDATE public.wallets
    SET credit_liability = 0.00, updated_at = NOW()
    WHERE credit_liability > 0;

    INSERT INTO public.tuition_reconciliation_batches (batch_reference, total_debt_cleared, student_count, cleared_by, notes)
    VALUES (p_batch_ref, v_total_cleared, v_count, p_cleared_by, p_notes);

    RETURN jsonb_build_object('success', true, 'batch_reference', p_batch_ref, 'total_cleared', v_total_cleared, 'students_reconciled', v_count);
END;
$$;

-- O. Pay Later Pre-Authorization Toggle
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

-- P. Dynamic Student QR Generation
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

-- Q. Student Calorie Accumulator
CREATE OR REPLACE FUNCTION public.fn_add_student_calories(
    p_student_id UUID,
    p_calories INT
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.profiles
    SET last_calorie_reset_date = CURRENT_DATE,
        daily_calories_spent = 0
    WHERE id = p_student_id
      AND (last_calorie_reset_date IS NULL OR last_calorie_reset_date < CURRENT_DATE);

    UPDATE public.profiles
    SET daily_calories_spent = COALESCE(daily_calories_spent, 0) + p_calories,
        updated_at = NOW()
    WHERE id = p_student_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 8. DEFAULT SEED CANTEEN POLICIES & HARDWARE TOPOLOGY
-- ------------------------------------------------------------------------------
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'discount_policy',
    '{"student_discount_pct": 10, "senior_pwd_discount_pct": 20, "student_discount_enabled": true, "senior_pwd_discount_enabled": true}'::jsonb,
    'POS discount percentages for Student and Senior/PWD categories.'
),
(
    'parent_notification_defaults',
    '{"on_every_purchase": true, "on_daily_cap_80_pct": true, "on_allergen_flag": true, "on_pay_later_use": true, "on_override_approved": true}'::jsonb,
    'Default parent push notification triggers for linked student activity.'
),
(
    'pay_later_policy',
    '{"global_max_credit": 1000, "max_transactions": 5, "auto_block_on_cap": true}'::jsonb,
    'Pay later emergency debt caps and thresholds.'
),
(
    'dietary_defaults',
    '{"default_daily_calories": 1800, "max_single_meal": 800, "low_calorie_cutoff": 300, "high_protein_cutoff": 20}'::jsonb,
    'Nutrition, calorie limits, and healthy choice thresholds.'
),
(
    'ai_kiosk_mode',
    '{"min_confidence": 0.80, "review_confidence": 0.50, "auto_checkout": true}'::jsonb,
    'Overhead AI vision parameters for kiosk auto-checkout.'
),
(
    'manager_void_pin',
    '{"pin": "1234", "pin_hash": "a"}'::jsonb,
    'Manager PIN for voids & supervisor overrides.'
)
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.hardware_mappings (terminal_id, camera_id, pos_register_id, pos_register_name, location_name, status) VALUES
('TERM-01', 'CAM-OVERHEAD-01', 'POS-REG-01', 'Main Counter POS #1', 'Main Canteen Counter', 'active'),
('TERM-02', 'CAM-KIOSK-02', 'POS-EXPRESS-02', 'Express Kiosk #2', 'Express Self-Checkout Kiosk #2', 'active')
ON CONFLICT (terminal_id) DO NOTHING;

INSERT INTO public.preorder_slots (slot_name, start_time, end_time, prep_lead_minutes, max_orders, is_active) VALUES
('Morning Recess Slot (10:00 AM)', '10:00:00', '10:30:00', 20, 30, true),
('Lunch Slot A (11:30 AM)', '11:30:00', '12:15:00', 30, 40, true),
('Lunch Slot B (12:15 PM)', '12:15:00', '13:00:00', 30, 40, true)
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------------------------
-- 9. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.preorders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.preorder_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meal_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dispute_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cashier_shift_reconciliations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_student_link_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_student_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canteen_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hardware_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.governance_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topup_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kds_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_detection_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offline_transaction_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offline_balance_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_subsidies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_spending_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category_spending_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_allergen_guardrails ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recipe_bom ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sis_tuition_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tuition_reconciliation_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tuition_batch_exports ENABLE ROW LEVEL SECURITY;

-- Clean Policy Grants for Production Web Portal & POS Edge Terminals
DO $$ BEGIN
    -- Public Profiles
    DROP POLICY IF EXISTS "Public profiles read" ON public.profiles;
    DROP POLICY IF EXISTS "Public profiles write" ON public.profiles;
    CREATE POLICY "Public profiles read" ON public.profiles FOR SELECT USING (true);
    CREATE POLICY "Public profiles write" ON public.profiles FOR ALL USING (true);

    -- Wallets
    DROP POLICY IF EXISTS "Public wallets read" ON public.wallets;
    DROP POLICY IF EXISTS "Public wallets write" ON public.wallets;
    CREATE POLICY "Public wallets read" ON public.wallets FOR SELECT USING (true);
    CREATE POLICY "Public wallets write" ON public.wallets FOR ALL USING (true);

    -- Categories & Products
    DROP POLICY IF EXISTS "Public categories read" ON public.menu_categories;
    DROP POLICY IF EXISTS "Public categories write" ON public.menu_categories;
    CREATE POLICY "Public categories read" ON public.menu_categories FOR SELECT USING (true);
    CREATE POLICY "Public categories write" ON public.menu_categories FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public products read" ON public.products;
    DROP POLICY IF EXISTS "Public products write" ON public.products;
    CREATE POLICY "Public products read" ON public.products FOR SELECT USING (true);
    CREATE POLICY "Public products write" ON public.products FOR ALL USING (true);

    -- Inventory Batches & Logs
    DROP POLICY IF EXISTS "Public batches read" ON public.inventory_batches;
    DROP POLICY IF EXISTS "Public batches write" ON public.inventory_batches;
    CREATE POLICY "Public batches read" ON public.inventory_batches FOR SELECT USING (true);
    CREATE POLICY "Public batches write" ON public.inventory_batches FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public inventory logs all" ON public.inventory_logs;
    CREATE POLICY "Public inventory logs all" ON public.inventory_logs FOR ALL USING (true);

    -- Orders & Items
    DROP POLICY IF EXISTS "Public orders all" ON public.orders;
    CREATE POLICY "Public orders all" ON public.orders FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public order_items all" ON public.order_items;
    CREATE POLICY "Public order_items all" ON public.order_items FOR ALL USING (true);

    -- Transactions & Audits
    DROP POLICY IF EXISTS "Public wallet transactions all" ON public.wallet_transactions;
    CREATE POLICY "Public wallet transactions all" ON public.wallet_transactions FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public audit logs all" ON public.audit_logs;
    CREATE POLICY "Public audit logs all" ON public.audit_logs FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public system audit logs all" ON public.system_audit_logs;
    CREATE POLICY "Public system audit logs all" ON public.system_audit_logs FOR ALL USING (true);

    -- Preorders & Slots
    DROP POLICY IF EXISTS "Public preorders all" ON public.preorders;
    CREATE POLICY "Public preorders all" ON public.preorders FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public preorder slots all" ON public.preorder_slots;
    CREATE POLICY "Public preorder slots all" ON public.preorder_slots FOR ALL USING (true);

    -- Disputes & Topups
    DROP POLICY IF EXISTS "Public meal disputes all" ON public.meal_disputes;
    CREATE POLICY "Public meal disputes all" ON public.meal_disputes FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public dispute tickets all" ON public.dispute_tickets;
    CREATE POLICY "Public dispute tickets all" ON public.dispute_tickets FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public topup requests all" ON public.topup_requests;
    CREATE POLICY "Public topup requests all" ON public.topup_requests FOR ALL USING (true);

    -- Parent Links & Notifications
    DROP POLICY IF EXISTS "Public parent links all" ON public.parent_student_links;
    CREATE POLICY "Public parent links all" ON public.parent_student_links FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public parent link requests all" ON public.parent_student_link_requests;
    CREATE POLICY "Public parent link requests all" ON public.parent_student_link_requests FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public notifications all" ON public.notifications;
    CREATE POLICY "Public notifications all" ON public.notifications FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public notification preferences all" ON public.notification_preferences;
    CREATE POLICY "Public notification preferences all" ON public.notification_preferences FOR ALL USING (true);

    -- Settings, Hardware & Governance
    DROP POLICY IF EXISTS "Public settings all" ON public.canteen_settings;
    CREATE POLICY "Public settings all" ON public.canteen_settings FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public hardware mappings all" ON public.hardware_mappings;
    CREATE POLICY "Public hardware mappings all" ON public.hardware_mappings FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public governance overrides all" ON public.governance_overrides;
    CREATE POLICY "Public governance overrides all" ON public.governance_overrides FOR ALL USING (true);

    -- Offline Queues & Subsidies & SIS Batches
    DROP POLICY IF EXISTS "Public offline queue all" ON public.offline_transaction_queue;
    CREATE POLICY "Public offline queue all" ON public.offline_transaction_queue FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public offline reservations all" ON public.offline_balance_reservations;
    CREATE POLICY "Public offline reservations all" ON public.offline_balance_reservations FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public subsidies all" ON public.student_subsidies;
    CREATE POLICY "Public subsidies all" ON public.student_subsidies FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public category spending rules all" ON public.category_spending_rules;
    CREATE POLICY "Public category spending rules all" ON public.category_spending_rules FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public category spending limits all" ON public.category_spending_limits;
    CREATE POLICY "Public category spending limits all" ON public.category_spending_limits FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public allergen guardrails all" ON public.student_allergen_guardrails;
    CREATE POLICY "Public allergen guardrails all" ON public.student_allergen_guardrails FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public recipe bom all" ON public.recipe_bom;
    CREATE POLICY "Public recipe bom all" ON public.recipe_bom FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public sis batches all" ON public.sis_tuition_batches;
    CREATE POLICY "Public sis batches all" ON public.sis_tuition_batches FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public tuition recon all" ON public.tuition_reconciliation_batches;
    CREATE POLICY "Public tuition recon all" ON public.tuition_reconciliation_batches FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public tuition exports all" ON public.tuition_batch_exports;
    CREATE POLICY "Public tuition exports all" ON public.tuition_batch_exports FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public kds tickets all" ON public.kds_tickets;
    CREATE POLICY "Public kds tickets all" ON public.kds_tickets FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public ai detection logs all" ON public.ai_detection_logs;
    CREATE POLICY "Public ai detection logs all" ON public.ai_detection_logs FOR ALL USING (true);

    DROP POLICY IF EXISTS "Public shift reconciliations all" ON public.cashier_shift_reconciliations;
    CREATE POLICY "Public shift reconciliations all" ON public.cashier_shift_reconciliations FOR ALL USING (true);
END $$;

-- ==============================================================================
-- END OF NOVALUNCH UNIFIED MASTER SCHEMA
-- ==============================================================================
