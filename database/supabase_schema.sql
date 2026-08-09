-- ==============================================================================
-- CANTEEN POS, RFID & AI DETECTION SYSTEM - SUPABASE DATABASE MIGRATION SCRIPT
-- Project: Web-Based Canteen POS System
-- Description: Drops legacy, non-essential school tables and builds a clean,
--              high-performance database schema optimized for POS transactions,
--              RFID wallet payments, and AI vision item detection.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. CLEANUP LEGACY UNNECESSARY TABLES
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS "v_curriculum_assignments" CASCADE;
DROP TABLE IF EXISTS "v_enrollment_counts" CASCADE;
DROP TABLE IF EXISTS "v_registrar_students" CASCADE;
DROP TABLE IF EXISTS "v_section_slots" CASCADE;
DROP TABLE IF EXISTS "v_student_guardian_overview" CASCADE;
DROP TABLE IF EXISTS "v_student_registration_summary" CASCADE;

DROP TABLE IF EXISTS "coordinators" CASCADE;
DROP TABLE IF EXISTS "coordinator_actions" CASCADE;
DROP TABLE IF EXISTS "coordinator_assignment_logs" CASCADE;
DROP TABLE IF EXISTS "class_schedules" CASCADE;
DROP TABLE IF EXISTS "curriculum" CASCADE;
DROP TABLE IF EXISTS "enrollments" CASCADE;
DROP TABLE IF EXISTS "enrollment_logs" CASCADE;
DROP TABLE IF EXISTS "grade_levels" CASCADE;
DROP TABLE IF EXISTS "guardians" CASCADE;
DROP TABLE IF EXISTS "guardian_audit_log" CASCADE;
DROP TABLE IF EXISTS "otp_attempts" CASCADE;
DROP TABLE IF EXISTS "otp_verifications" CASCADE;
DROP TABLE IF EXISTS "password_reset_tokens" CASCADE;
DROP TABLE IF EXISTS "payment_due_notices" CASCADE;
DROP TABLE IF EXISTS "payment_submissions" CASCADE;
DROP TABLE IF EXISTS "principals" CASCADE;
DROP TABLE IF EXISTS "principal_notifications" CASCADE;
DROP TABLE IF EXISTS "privacy_consents" CASCADE;
DROP TABLE IF EXISTS "registrars" CASCADE;
DROP TABLE IF EXISTS "registration_documents" CASCADE;
DROP TABLE IF EXISTS "remember_me_tokens" CASCADE;
DROP TABLE IF EXISTS "role_redirects" CASCADE;
DROP TABLE IF EXISTS "rooms" CASCADE;
DROP TABLE IF EXISTS "school_years" CASCADE;
DROP TABLE IF EXISTS "sections" CASCADE;
DROP TABLE IF EXISTS "section_school_years" CASCADE;
DROP TABLE IF EXISTS "student_grades" CASCADE;
DROP TABLE IF EXISTS "student_guardians" CASCADE;
DROP TABLE IF EXISTS "student_profiles" CASCADE;
DROP TABLE IF EXISTS "student_submissions" CASCADE;
DROP TABLE IF EXISTS "student_wallets" CASCADE;
DROP TABLE IF EXISTS "students" CASCADE;
DROP TABLE IF EXISTS "subjects" CASCADE;
DROP TABLE IF EXISTS "system_deadlines" CASCADE;
DROP TABLE IF EXISTS "teachers" CASCADE;
DROP TABLE IF EXISTS "teacher_notifications" CASCADE;
DROP TABLE IF EXISTS "trusted_devices" CASCADE;

DROP TABLE IF EXISTS "cafeteria_inventory" CASCADE;
DROP TABLE IF EXISTS "cafeteria_products" CASCADE;
DROP TABLE IF EXISTS "cafeteria_settings" CASCADE;
DROP TABLE IF EXISTS "cashiers" CASCADE;
DROP TABLE IF EXISTS "admins" CASCADE;
DROP TABLE IF EXISTS "users" CASCADE;

-- ------------------------------------------------------------------------------
-- 2. EXTENSIONS & SETUP
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 3. PROFILES TABLE (Multi-role users tied to auth.users)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'student' CHECK (role IN ('admin', 'cashier', 'student', 'parent')),
    student_id_number TEXT UNIQUE,
    rfid_uid TEXT UNIQUE,
    pin_code TEXT,
    avatar_url TEXT,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'inactive')),
    credit_liability NUMERIC(10, 2) DEFAULT 0.00 CHECK (credit_liability >= 0),
    credit_limit NUMERIC(10, 2) DEFAULT 500.00,
    pay_later_allowance BOOLEAN DEFAULT TRUE,
    max_daily_calories INT DEFAULT 1800,
    allergen_mode TEXT DEFAULT 'SOFT_WARN' CHECK (allergen_mode IN ('SOFT_WARN', 'HARD_BLOCK')),
    allergen_restrictions TEXT[] DEFAULT '{}',
    weekly_limit NUMERIC(10, 2) DEFAULT 1000.00,
    restricted_categories UUID[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_rfid ON public.profiles(rfid_uid);
CREATE INDEX IF NOT EXISTS idx_profiles_student_id ON public.profiles(student_id_number);

-- ------------------------------------------------------------------------------
-- 4. PARENT-STUDENT LINK TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parent_student_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (parent_id, student_id)
);

-- ------------------------------------------------------------------------------
-- 4B. PARENT-STUDENT LINK REQUESTS TABLE (Request & Acceptance Flow)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parent_student_link_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_id_number TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (parent_id, student_id)
);

CREATE INDEX IF NOT EXISTS idx_link_req_parent ON public.parent_student_link_requests(parent_id);
CREATE INDEX IF NOT EXISTS idx_link_req_student ON public.parent_student_link_requests(student_id);
CREATE INDEX IF NOT EXISTS idx_link_req_status ON public.parent_student_link_requests(status);

-- ------------------------------------------------------------------------------
-- 4C. SYSTEM NOTIFICATIONS TABLE (Universal notification center across all roles)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'system' CHECK (type IN ('link_request', 'link_accepted', 'link_rejected', 'wallet_topup', 'purchase', 'account_created', 'system')),
    is_read BOOLEAN DEFAULT FALSE,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON public.notifications(is_read);


-- ------------------------------------------------------------------------------
-- 5. WALLETS TABLE (Student balances & daily limits)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    balance NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (balance >= 0),
    daily_limit NUMERIC(10, 2) DEFAULT 200.00,
    daily_spent NUMERIC(10, 2) DEFAULT 0.00,
    credit_liability NUMERIC(10, 2) DEFAULT 0.00 CHECK (credit_liability >= 0),
    last_spent_date DATE DEFAULT CURRENT_DATE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 6. WALLET TRANSACTIONS TABLE (Top-ups, Purchases, Refunds)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_id UUID NOT NULL REFERENCES public.wallets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL, -- Positive for credit/topup, negative for debit/purchase
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('topup', 'purchase', 'refund')),
    payment_method TEXT CHECK (payment_method IN ('rfid', 'wallet', 'cash', 'online', 'system')),
    reference_id TEXT,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON public.wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_created ON public.wallet_transactions(created_at DESC);

-- ------------------------------------------------------------------------------
-- 7. MENU CATEGORIES TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.menu_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    icon TEXT DEFAULT 'fa-utensils',
    sort_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 8. PRODUCTS TABLE (Canteen menu & AI label mapping)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id UUID REFERENCES public.menu_categories(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    description TEXT,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    cost_price NUMERIC(10, 2) DEFAULT 0.00,
    stock_quantity INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    ai_label TEXT, -- AI Detection label (e.g. 'burger', 'apple', 'canned_drink', 'sandwich', 'water_bottle')
    barcode TEXT UNIQUE,
    image_url TEXT,
    calories INT DEFAULT 0,
    allergens TEXT[] DEFAULT '{}',
    protein_grams NUMERIC(5, 1) DEFAULT 0.0,
    carbs_grams NUMERIC(5, 1) DEFAULT 0.0,
    fat_grams NUMERIC(5, 1) DEFAULT 0.0,
    is_available BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_ai_label ON public.products(ai_label);

-- ------------------------------------------------------------------------------
-- 9. ORDERS TABLE (POS & Self-Checkout Sales Transactions)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_number TEXT UNIQUE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    cashier_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    total_amount NUMERIC(10, 2) NOT NULL CHECK (total_amount >= 0),
    discount_amount NUMERIC(10, 2) DEFAULT 0.00,
    final_amount NUMERIC(10, 2) NOT NULL CHECK (final_amount >= 0),
    payment_method TEXT NOT NULL CHECK (payment_method IN ('rfid', 'wallet', 'cash', 'online', 'pay_later')),
    payment_status TEXT NOT NULL DEFAULT 'paid' CHECK (payment_status IN ('paid', 'pending', 'refunded', 'failed')),
    pay_later_note TEXT,
    manager_approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    order_source TEXT NOT NULL DEFAULT 'cashier_pos' CHECK (order_source IN ('cashier_pos', 'ai_kiosk', 'mobile_preorder')),
    order_status TEXT NOT NULL DEFAULT 'completed' CHECK (order_status IN ('completed', 'preparing', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_number ON public.orders(order_number);
CREATE INDEX IF NOT EXISTS idx_orders_user ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created ON public.orders(created_at DESC);

-- ------------------------------------------------------------------------------
-- 10. ORDER ITEMS TABLE (Line items)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    product_name TEXT NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    subtotal NUMERIC(10, 2) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);

-- ------------------------------------------------------------------------------
-- 11. RFID CARDS TABLE (Badge tracking)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rfid_cards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rfid_uid TEXT UNIQUE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'blocked', 'lost')),
    issued_at TIMESTAMPTZ DEFAULT NOW(),
    last_scanned_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_rfid_cards_uid ON public.rfid_cards(rfid_uid);

-- ------------------------------------------------------------------------------
-- 12. AI DETECTION LOGS TABLE (Camera scanning audit)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_detection_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    image_url TEXT,
    detected_objects JSONB, -- Array of detected labels with confidence scores
    confidence_score NUMERIC(5, 4),
    matched_product_ids JSONB,
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 13. CANTEEN SETTINGS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.canteen_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 14. AUDIT LOGS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    details JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 14B. PRE-ORDER PICKUP TIME SLOTS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.preorder_slots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slot_name TEXT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    max_capacity INT NOT NULL DEFAULT 100,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 14C. HARDWARE TERMINAL MAPPINGS TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hardware_mappings (
    terminal_id TEXT PRIMARY KEY,
    pos_register_name TEXT NOT NULL,
    camera_device_index INT DEFAULT 0,
    rfid_reader_port TEXT DEFAULT 'COM3',
    assigned_station TEXT DEFAULT 'Hot Kitchen',
    is_online BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ------------------------------------------------------------------------------
-- 15. AUTOMATIC UPDATED_AT TRIGGER FUNCTION
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE OR REPLACE TRIGGER trg_wallets_updated_at BEFORE UPDATE ON public.wallets FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE OR REPLACE TRIGGER trg_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ------------------------------------------------------------------------------
-- 16. ROW LEVEL SECURITY (RLS) POLICIES
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfid_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_detection_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.canteen_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.parent_student_link_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Allow public read access to active products & categories for POS/Kiosk display
CREATE POLICY "Public read active categories" ON public.menu_categories FOR SELECT USING (is_active = true);
CREATE POLICY "Public read available products" ON public.products FOR SELECT USING (is_available = true);
CREATE POLICY "Public read canteen settings" ON public.canteen_settings FOR SELECT USING (true);

-- Allow authenticated users to view profiles & wallets
CREATE POLICY "Allow anon read products" ON public.products FOR SELECT USING (true);
CREATE POLICY "Allow full access for authenticated/anon during development" ON public.profiles FOR ALL USING (true);
CREATE POLICY "Allow full access wallets" ON public.wallets FOR ALL USING (true);
CREATE POLICY "Allow full access wallet_transactions" ON public.wallet_transactions FOR ALL USING (true);
CREATE POLICY "Allow full access orders" ON public.orders FOR ALL USING (true);
CREATE POLICY "Allow full access order_items" ON public.order_items FOR ALL USING (true);
CREATE POLICY "Allow full access rfid_cards" ON public.rfid_cards FOR ALL USING (true);
CREATE POLICY "Allow full access ai_detection_logs" ON public.ai_detection_logs FOR ALL USING (true);
CREATE POLICY "Allow full access parent_student_link_requests" ON public.parent_student_link_requests FOR ALL USING (true);
CREATE POLICY "Allow full access notifications" ON public.notifications FOR ALL USING (true);

-- ------------------------------------------------------------------------------
-- 17. SEED DATA (Default categories, products, and operational settings)
-- ------------------------------------------------------------------------------

-- Categories
INSERT INTO public.menu_categories (id, name, description, icon, sort_order) VALUES
('11111111-1111-1111-1111-111111111111', 'Meals & Mains', 'Delicious freshly cooked daily meals', 'fa-utensils', 1),
('22222222-2222-2222-2222-222222222222', 'Beverages', 'Refreshing cold and hot drinks', 'fa-glass-water', 2),
('33333333-3333-3333-3333-333333333333', 'Snacks & Bakery', 'Quick bites, chips, and baked goods', 'fa-cookie-bite', 3),
('44444444-4444-4444-4444-444444444444', 'Fruits & Healthy', 'Fresh fruits and healthy salad options', 'fa-apple-whole', 4)
ON CONFLICT (name) DO NOTHING;

-- Products (with AI detection labels)
INSERT INTO public.products (id, category_id, name, description, price, cost_price, stock_quantity, ai_label, barcode, is_available) VALUES
('a1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Classic Cheeseburger', 'Juicy beef patty with cheddar cheese and fresh lettuce', 75.00, 45.00, 50, 'burger', '480000000001', true),
('a2222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Crispy Chicken Bowl', 'Golden fried chicken piece served with garlic rice & gravy', 85.00, 50.00, 60, 'fried_chicken', '480000000002', true),
('a3333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Ham & Cheese Sandwich', 'Toasted bread with slice ham and melted cheese', 45.00, 25.00, 40, 'sandwich', '480000000003', true),
('a4444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'Mineral Water (500ml)', 'Purified cold bottled drinking water', 20.00, 10.00, 150, 'water_bottle', '480000000004', true),
('a5555555-5555-5555-5555-555555555555', '22222222-2222-2222-2222-222222222222', 'Iced Fruit Juice (350ml)', 'Freshly brewed fruit juice drink', 30.00, 15.00, 80, 'juice_box', '480000000005', true),
('a6666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', 'Fresh Red Apple', 'Sweet and crisp organic apple', 25.00, 15.00, 40, 'apple', '480000000006', true)
ON CONFLICT (id) DO NOTHING;

-- Initial Settings
INSERT INTO public.canteen_settings (key, value, description) VALUES
('canteen_status', '{"is_open": true, "message": "Canteen is open for orders"}', 'Operational status of the canteen'),
('daily_spending_default', '{"amount": 200.00}', 'Default daily wallet spending limit for students'),
('tax_rate', '{"percentage": 0.0}', 'Applicable tax percentage for items'),
('ai_kiosk_mode', '{"enabled": true, "auto_checkout": false, "min_confidence": 0.80, "review_confidence": 0.50}', 'Settings for AI Vision Self-Checkout Kiosk'),
('gcash_verification_rules', '{"auto_approve_max": 200.00, "require_receipt_upload": true}', 'Rules for instant vs manual GCash top-up verification'),
('pay_later_policy', '{"global_max_credit": 500.00, "allow_parent_override": true}', 'System-wide Pay Later credit settings'),
('dietary_defaults', '{"default_daily_calories": 1800, "default_allergen_mode": "SOFT_WARN"}', 'Fallback health governance targets')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- ------------------------------------------------------------------------------
-- 17B. GOVERNANCE OVERRIDES AUDIT LOG TABLE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.governance_overrides (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    cashier_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    override_type TEXT NOT NULL CHECK (override_type IN ('calorie_limit', 'allergen_block', 'spending_limit', 'pay_later_cap')),
    reason TEXT NOT NULL,
    approved_by_pin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gov_overrides_student ON public.governance_overrides(student_id);
CREATE INDEX IF NOT EXISTS idx_gov_overrides_cashier ON public.governance_overrides(cashier_id);
CREATE INDEX IF NOT EXISTS idx_gov_overrides_created ON public.governance_overrides(created_at DESC);


-- ------------------------------------------------------------------------------
-- 18. ATOMIC AI KIOSK TRANSACTION SETTLEMENT STORED PROCEDURE
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.settle_ai_kiosk_transaction(
    p_student_id UUID,
    p_items JSONB, -- Array of {"product_id": "...", "name": "...", "qty": 1, "price": 100.00}
    p_total_amount NUMERIC
) RETURNS JSONB AS $$
DECLARE
    v_wallet_id UUID;
    v_current_balance NUMERIC;
    v_order_id UUID;
    v_order_num TEXT;
    item JSONB;
BEGIN
    -- 1. Lock student wallet record for update
    SELECT id, balance INTO v_wallet_id, v_current_balance
    FROM public.wallets
    WHERE user_id = p_student_id
    FOR UPDATE;

    IF v_wallet_id IS NULL THEN
        RAISE EXCEPTION 'WALLET_NOT_FOUND: No wallet associated with student %', p_student_id;
    END IF;

    IF v_current_balance < p_total_amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Required %, Available %', p_total_amount, v_current_balance;
    END IF;

    -- 2. Deduct wallet balance
    UPDATE public.wallets
    SET balance = balance - p_total_amount,
        daily_spent = daily_spent + p_total_amount,
        updated_at = NOW()
    WHERE id = v_wallet_id;

    -- 3. Create POS order record
    v_order_num := 'ORD-AI-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-' || SUBSTRING(CAST(gen_random_uuid() AS TEXT), 1, 4);
    
    INSERT INTO public.orders (order_number, user_id, total_amount, final_amount, payment_method, payment_status, order_source, order_status)
    VALUES (v_order_num, p_student_id, p_total_amount, p_total_amount, 'rfid', 'paid', 'ai_kiosk', 'completed')
    RETURNING id INTO v_order_id;

    -- 4. Record wallet ledger transaction
    INSERT INTO public.wallet_transactions (wallet_id, user_id, amount, transaction_type, payment_method, reference_id, description)
    VALUES (v_wallet_id, p_student_id, -p_total_amount, 'purchase', 'rfid', v_order_num, 'AI Kiosk Tray Auto-Deduction');

    -- 5. Loop through detected tray items: Insert order items & decrement inventory stock
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        -- Decrement inventory stock
        UPDATE public.products
        SET stock_quantity = GREATEST(0, stock_quantity - (item->>'qty')::INT),
            updated_at = NOW()
        WHERE id = (item->>'product_id')::UUID;

        -- Insert order line item
        INSERT INTO public.order_items (order_id, product_id, product_name, unit_price, quantity, subtotal)
        VALUES (
            v_order_id,
            (item->>'product_id')::UUID,
            item->>'name',
            (item->>'price')::NUMERIC,
            (item->>'qty')::INT,
            (item->>'price')::NUMERIC * (item->>'qty')::INT
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order_id,
        'order_number', v_order_num,
        'remaining_balance', v_current_balance - p_total_amount
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 19. ATOMIC PAY LATER TAB REPAYMENT & DEBT SETTLEMENT STORED PROCEDURE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.settle_pay_later_liability(
    p_user_id UUID,
    p_amount NUMERIC,
    p_payment_method TEXT, -- 'cash' | 'rfid' | 'online'
    p_cashier_id UUID DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    v_wallet_id UUID;
    v_current_liability NUMERIC;
    v_current_balance NUMERIC;
    v_new_liability NUMERIC;
BEGIN
    -- 1. Lock wallet record
    SELECT id, credit_liability, balance INTO v_wallet_id, v_current_liability, v_current_balance
    FROM public.wallets
    WHERE user_id = p_user_id
    FOR UPDATE;

    IF v_wallet_id IS NULL THEN
        RAISE EXCEPTION 'WALLET_NOT_FOUND: No wallet associated with student %', p_user_id;
    END IF;

    IF v_current_liability <= 0 THEN
        RAISE EXCEPTION 'NO_OUTSTANDING_DEBT: Student has zero Pay Later debt.';
    END IF;

    -- If paid via RFID wallet balance, ensure sufficient RFID funds
    IF p_payment_method = 'rfid' AND v_current_balance < p_amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_RFID_FUNDS: Available %, Repayment %', v_current_balance, p_amount;
    END IF;

    v_new_liability := GREATEST(0, v_current_liability - p_amount);

    -- 2. Deduct credit liability & deduct wallet balance if RFID payment
    IF p_payment_method = 'rfid' THEN
        UPDATE public.wallets
        SET credit_liability = v_new_liability,
            balance = balance - p_amount,
            updated_at = NOW()
        WHERE id = v_wallet_id;
    ELSE
        UPDATE public.wallets
        SET credit_liability = v_new_liability,
            updated_at = NOW()
        WHERE id = v_wallet_id;
    END IF;

    -- Sync profile table
    UPDATE public.profiles
    SET credit_liability = v_new_liability,
        updated_at = NOW()
    WHERE id = p_user_id;

    -- 3. Log ledger transaction
    INSERT INTO public.wallet_transactions (wallet_id, user_id, amount, transaction_type, payment_method, reference_id, description)
    VALUES (v_wallet_id, p_user_id, p_amount, 'topup', p_payment_method, 'TAB-REPAY-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS'), 'Pay Later Debt Repayment (' || UPPER(p_payment_method) || ')');

    RETURN jsonb_build_object(
        'success', true,
        'previous_liability', v_current_liability,
        'remaining_liability', v_new_liability,
        'amount_paid', p_amount
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Done!


