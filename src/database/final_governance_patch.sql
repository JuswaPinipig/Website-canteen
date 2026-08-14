-- ==============================================================================
-- NOVALUNCH CANTEEN — FINAL GOVERNANCE COMPLETION PATCH
-- SAFE TO RE-RUN: All statements are idempotent (IF NOT EXISTS / ON CONFLICT).
-- Does NOT require supabase_schema.sql to have been run first.
-- ==============================================================================

-- Guard: ensure extensions exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Guard: ensure canteen_settings table exists
CREATE TABLE IF NOT EXISTS public.canteen_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.canteen_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read canteen settings" ON public.canteen_settings;
CREATE POLICY "Public read canteen settings" ON public.canteen_settings FOR SELECT USING (true);

-- ------------------------------------------------------------------------------
-- 1. DISCOUNT POLICY (Replaces hardcoded 10%/20% in CashierView)
--    Allows admin to change discount rates without touching code.
-- ------------------------------------------------------------------------------
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'discount_policy',
    '{
        "student_discount_pct": 10,
        "senior_pwd_discount_pct": 20,
        "student_discount_enabled": true,
        "senior_pwd_discount_enabled": true
    }',
    'POS discount percentages for Student and Senior/PWD categories. Fully configurable via Admin Governance panel.'
)
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 2. PARENT NOTIFICATION DEFAULTS
--    Governs which events trigger push notifications to parent accounts.
-- ------------------------------------------------------------------------------
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'parent_notification_defaults',
    '{
        "on_every_purchase": true,
        "on_daily_cap_80_pct": true,
        "on_allergen_flag": true,
        "on_pay_later_use": true,
        "on_override_approved": true
    }',
    'Default parent push notification event triggers for linked student activity'
)
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 3. GOVERNANCE OVERRIDES AUDIT LOG TABLE
--    Creates the table if it does not exist yet (handles fresh Supabase projects
--    where supabase_schema.sql has not been run). Then replaces the CHECK
--    constraint to include all override_type strings the portal JS produces.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.governance_overrides (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    cashier_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    override_type TEXT NOT NULL,
    reason TEXT NOT NULL,
    approved_by_pin BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_gov_overrides_student ON public.governance_overrides(student_id);
CREATE INDEX IF NOT EXISTS idx_gov_overrides_cashier ON public.governance_overrides(cashier_id);
CREATE INDEX IF NOT EXISTS idx_gov_overrides_created ON public.governance_overrides(created_at DESC);

ALTER TABLE public.governance_overrides ENABLE ROW LEVEL SECURITY;

-- Drop the old narrow CHECK first (safe if it does not exist)
ALTER TABLE public.governance_overrides
    DROP CONSTRAINT IF EXISTS governance_overrides_override_type_check;

-- Add the full set of type strings the portal JS currently emits
ALTER TABLE public.governance_overrides
    ADD CONSTRAINT governance_overrides_override_type_check
    CHECK (override_type IN (
        'calorie_limit',
        'allergen_block',
        'spending_limit',
        'pay_later_cap',
        'restricted_category',
        'weekly_limit',
        'DIETARY_OVERRIDE',
        'PAY_LATER_CEILING_OVERRIDE',
        'DAILY_SPENDING_CAP_OVERRIDE'
    ));

-- RLS policy: cashiers and admins can insert; owner can read their own
DROP POLICY IF EXISTS "Governance overrides: insert by staff" ON public.governance_overrides;
CREATE POLICY "Governance overrides: insert by staff"
    ON public.governance_overrides FOR INSERT
    TO authenticated
    WITH CHECK (true);

DROP POLICY IF EXISTS "Governance overrides: read own" ON public.governance_overrides;
CREATE POLICY "Governance overrides: read own"
    ON public.governance_overrides FOR SELECT
    TO authenticated
    USING (student_id = auth.uid() OR cashier_id = auth.uid());

-- ------------------------------------------------------------------------------
-- 4. Per-parent notification preferences table
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    on_every_purchase BOOLEAN DEFAULT TRUE,
    on_daily_cap_80_pct BOOLEAN DEFAULT TRUE,
    on_allergen_flag BOOLEAN DEFAULT TRUE,
    on_pay_later_use BOOLEAN DEFAULT TRUE,
    on_override_approved BOOLEAN DEFAULT TRUE,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id)
);

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Notification prefs: owner only" ON public.notification_preferences;
CREATE POLICY "Notification prefs: owner only"
    ON public.notification_preferences FOR ALL
    TO authenticated
    USING (user_id = auth.uid());

-- ------------------------------------------------------------------------------
-- 5. Track daily calorie consumption on profiles
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS daily_calories_spent INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_calorie_reset_date DATE DEFAULT CURRENT_DATE;

-- Auto-reset trigger: zeros daily_calories_spent when the date changes
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

-- Backfill any existing rows that have NULL values
UPDATE public.profiles
    SET daily_calories_spent = 0,
        last_calorie_reset_date = CURRENT_DATE
    WHERE daily_calories_spent IS NULL OR last_calorie_reset_date IS NULL;

-- ------------------------------------------------------------------------------
-- 6. Discount audit columns on orders
-- ------------------------------------------------------------------------------
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS discount_type TEXT DEFAULT 'NONE',
    ADD COLUMN IF NOT EXISTS discount_pct NUMERIC(5, 2) DEFAULT 0.00;

-- ------------------------------------------------------------------------------
-- 7. Soft-delete status on products
-- ------------------------------------------------------------------------------
ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

ALTER TABLE public.products
    DROP CONSTRAINT IF EXISTS products_status_check;
ALTER TABLE public.products
    ADD CONSTRAINT products_status_check
    CHECK (status IN ('active', 'archived', 'out_of_stock'));

-- Backfill: unavailable products should be archived
UPDATE public.products
    SET status = 'archived'
    WHERE is_available = FALSE AND (status = 'active' OR status IS NULL);

-- ------------------------------------------------------------------------------
-- 8. RPC: fn_add_student_calories
--    Called from the portal after each purchase to track daily calorie intake.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_add_student_calories(
    p_student_id UUID,
    p_calories INT
)
RETURNS VOID AS $$
BEGIN
    -- Reset to zero if it is a new day before accumulating
    UPDATE public.profiles
    SET last_calorie_reset_date = CURRENT_DATE,
        daily_calories_spent = 0
    WHERE id = p_student_id
      AND (last_calorie_reset_date IS NULL OR last_calorie_reset_date < CURRENT_DATE);

    -- Accumulate today's calories
    UPDATE public.profiles
    SET daily_calories_spent = COALESCE(daily_calories_spent, 0) + p_calories,
        updated_at = NOW()
    WHERE id = p_student_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 9. HARDWARE TOPOLOGY & DEVICE MAPPINGS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hardware_mappings (
    terminal_id TEXT PRIMARY KEY,
    camera_id TEXT NOT NULL,
    pos_register_id TEXT NOT NULL,
    location_name TEXT DEFAULT 'Main Canteen Counter',
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'offline')),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.hardware_mappings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read hardware mappings" ON public.hardware_mappings;
CREATE POLICY "Public read hardware mappings" ON public.hardware_mappings FOR SELECT USING (true);

INSERT INTO public.hardware_mappings (terminal_id, camera_id, pos_register_id, location_name, status) VALUES
('TERM-01', 'CAM-OVERHEAD-01', 'POS-REG-01', 'Main Counter POS #1', 'active'),
('TERM-02', 'CAM-KIOSK-02', 'POS-EXPRESS-02', 'Express Self-Checkout Kiosk #2', 'active')
ON CONFLICT (terminal_id) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 10. PRE-ORDER PICKUP TIME SLOTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.preorder_slots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slot_name TEXT NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    prep_lead_minutes INT DEFAULT 30,
    max_orders INT DEFAULT 25,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.preorder_slots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public read preorder slots" ON public.preorder_slots;
CREATE POLICY "Public read preorder slots" ON public.preorder_slots FOR SELECT USING (true);

INSERT INTO public.preorder_slots (slot_name, start_time, end_time, prep_lead_minutes, max_orders, is_active) VALUES
('Morning Recess Slot (10:00 AM)', '10:00:00', '10:30:00', 20, 30, true),
('Lunch Slot A (11:30 AM)', '11:30:00', '12:15:00', 30, 40, true),
('Lunch Slot B (12:15 PM)', '12:15:00', '1:00:00', 30, 40, true)
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------------------------
-- 11. STUDENT SUBSIDIES & AUTO-EXPIRING ALLOWANCES
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.student_subsidies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    subsidy_name TEXT NOT NULL,
    amount NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
    frequency TEXT DEFAULT 'DAILY' CHECK (frequency IN ('DAILY', 'WEEKLY', 'MONTHLY', 'ONE_TIME')),
    expires_daily BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.student_subsidies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Owner read subsidies" ON public.student_subsidies;
CREATE POLICY "Owner read subsidies" ON public.student_subsidies FOR SELECT USING (true);

-- ------------------------------------------------------------------------------
-- 12. NUTRITIONAL COLUMNS ON PRODUCTS & PROFILES
-- ------------------------------------------------------------------------------
ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS calories INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS protein TEXT DEFAULT '0g',
    ADD COLUMN IF NOT EXISTS allergens JSONB DEFAULT '[]'::jsonb;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS max_meal_calories INT DEFAULT 800;

-- ------------------------------------------------------------------------------
-- 13. ADDITIONAL GOVERNANCE SETTINGS IN CANTEEN_SETTINGS
-- ------------------------------------------------------------------------------
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'yolo_vision_policy',
    '{
        "min_confidence": 0.85,
        "review_confidence": 0.50,
        "auto_checkout": false,
        "model_version": "v2.1"
    }',
    'AI YOLO Vision Camera scanning confidence cutoffs and auto-checkout behavior.'
),
(
    'gcash_policy',
    '{
        "auto_approve_max_amount": 500,
        "require_receipt_screenshot": true,
        "manual_review_threshold": 500,
        "pending_credit_grant_minutes": 15
    }',
    'GCash top-up auto-approval ceilings and verification queue rules.'
),
(
    'pay_later_policy',
    '{
        "global_credit_cap": 300,
        "consecutive_day_limit": 2,
        "allow_override": true,
        "auto_settle_on_topup": true
    }',
    'Global Pay Later emergency borrowing limit and automated ledger rules.'
),
(
    'dietary_defaults',
    '{
        "default_daily_calories": 1800,
        "default_meal_calories": 800,
        "default_allergen_mode": "SOFT_WARN"
    }',
    'Default health, calorie, and allergen enforcement thresholds.'
),
(
    'preorder_timeslot_policy',
    '{
        "enabled": true,
        "lead_time_minutes": 30,
        "max_preorders_per_slot": 25
    }',
    'Kitchen preparation lead times and time slot pre-order capacity limits.'
),
(
    'subsidy_policy',
    '{
        "school_subsidy_enabled": true,
        "default_daily_subsidy": 50.00,
        "subsidy_expires_daily": true
    }',
    'School/Corporate voucher allowance and auto-expiring balance policies.'
),
(
    'parent_policy',
    '{
        "parent_cap_overrides_pay_later": true,
        "privacy_autocrop_faces": true,
        "dispute_window_hours": 48
    }',
    'Parent governance precedence over student emergency borrowing & privacy protections.'
),
(
    'inventory_policy',
    '{
        "low_stock_threshold_pct": 10,
        "auto_freeze_preorders": true
    }',
    'Inventory depletion controls and automatic pre-order blocking triggers.'
),
(
    'rfid_policy',
    '{
        "debounce_ms": 800,
        "require_avatar_verification": true
    }',
    'RFID tap debouncing and visual POS identity verification policies.'
),
(
    'camera_policy',
    '{
        "fallback_timeout_ms": 1500,
        "crop_tray_bounding_box_only": true,
        "min_confidence_auto_swap": 0.75
    }',
    'Camera stream health monitoring and privacy auto-cropping rules.'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();

-- ------------------------------------------------------------------------------
-- 14. EXTEND GOVERNANCE OVERRIDES WITH CAMERA SNAPSHOT & AUDIT METADATA
-- ------------------------------------------------------------------------------
ALTER TABLE public.governance_overrides
    ADD COLUMN IF NOT EXISTS camera_frame_url TEXT,
    ADD COLUMN IF NOT EXISTS original_ai_detected_items JSONB,
    ADD COLUMN IF NOT EXISTS manager_pin_verified BOOLEAN DEFAULT FALSE;

-- ------------------------------------------------------------------------------
-- 15. OFFLINE TRANSACTION QUEUE & DETERMINISTIC CONFLICT RESOLUTION
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.offline_transaction_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_uuid UUID NOT NULL UNIQUE,
    terminal_id TEXT NOT NULL,
    student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    sequence_num INT NOT NULL,
    payload JSONB NOT NULL,
    status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SYNCED', 'DOUBLE_SPEND_DEBT_MIGRATED', 'FAILED')),
    synced_at TIMESTAMPTZ,
    error_log TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.offline_transaction_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public offline queue policy" ON public.offline_transaction_queue;
CREATE POLICY "Public offline queue policy" ON public.offline_transaction_queue FOR ALL USING (true);

-- RPC Procedure: fn_sync_offline_transaction
CREATE OR REPLACE FUNCTION public.fn_sync_offline_transaction(
    p_client_uuid UUID,
    p_terminal_id TEXT,
    p_student_id UUID,
    p_amount NUMERIC,
    p_sequence_num INT,
    p_payload JSONB
)
RETURNS JSONB AS $$
DECLARE
    v_current_bal NUMERIC(10,2);
    v_current_debt NUMERIC(10,2);
    v_new_bal NUMERIC(10,2);
    v_new_debt NUMERIC(10,2);
    v_already_processed BOOLEAN;
BEGIN
    -- Check idempotency by client_uuid
    SELECT EXISTS(
        SELECT 1 FROM public.offline_transaction_queue WHERE client_uuid = p_client_uuid AND status = 'SYNCED'
    ) INTO v_already_processed;

    IF v_already_processed THEN
        RETURN jsonb_build_object('success', true, 'status', 'ALREADY_SYNCED');
    END IF;

    -- Fetch current wallet state
    SELECT balance, credit_liability INTO v_current_bal, v_current_debt
    FROM public.wallets WHERE user_id = p_student_id FOR UPDATE;

    IF NOT FOUND THEN
        SELECT balance, credit_liability INTO v_current_bal, v_current_debt
        FROM public.profiles WHERE id = p_student_id FOR UPDATE;
    END IF;

    v_current_bal := COALESCE(v_current_bal, 0.00);
    v_current_debt := COALESCE(v_current_debt, 0.00);

    IF v_current_bal >= p_amount THEN
        -- Sufficient balance: deduct normally
        v_new_bal := v_current_bal - p_amount;
        UPDATE public.wallets SET balance = v_new_bal, updated_at = NOW() WHERE user_id = p_student_id;
        UPDATE public.profiles SET balance = v_new_bal, updated_at = NOW() WHERE id = p_student_id;

        INSERT INTO public.offline_transaction_queue (client_uuid, terminal_id, student_id, amount, sequence_num, payload, status, synced_at)
        VALUES (p_client_uuid, p_terminal_id, p_student_id, p_amount, p_sequence_num, p_payload, 'SYNCED', NOW())
        ON CONFLICT (client_uuid) DO UPDATE SET status = 'SYNCED', synced_at = NOW();

        RETURN jsonb_build_object('success', true, 'status', 'CLEARED_NORMAL', 'remaining_balance', v_new_bal);
    ELSE
        -- Insufficient balance due to offline multi-terminal usage: Migrate excess to Pay Later tuition liability
        v_new_debt := v_current_debt + (p_amount - v_current_bal);
        UPDATE public.wallets SET balance = 0.00, credit_liability = v_new_debt, updated_at = NOW() WHERE user_id = p_student_id;
        UPDATE public.profiles SET balance = 0.00, credit_liability = v_new_debt, updated_at = NOW() WHERE id = p_student_id;

        INSERT INTO public.offline_transaction_queue (client_uuid, terminal_id, student_id, amount, sequence_num, payload, status, synced_at, error_log)
        VALUES (p_client_uuid, p_terminal_id, p_student_id, p_amount, p_sequence_num, p_payload, 'DOUBLE_SPEND_DEBT_MIGRATED', NOW(), 'Offline balance exhausted. Converted excess to tuition Pay Later liability.')
        ON CONFLICT (client_uuid) DO UPDATE SET status = 'DOUBLE_SPEND_DEBT_MIGRATED', synced_at = NOW();

        RETURN jsonb_build_object('success', true, 'status', 'DEBT_MIGRATED', 'new_liability', v_new_debt);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 16. TUITION BATCH RECONCILIATION FOR EMERGENCY PAY LATER DEBTS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tuition_reconciliation_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_ref TEXT UNIQUE NOT NULL,
    total_debt_reconciled NUMERIC(10, 2) NOT NULL CHECK (total_debt_reconciled >= 0),
    student_count INT NOT NULL CHECK (student_count >= 0),
    status TEXT DEFAULT 'SETTLED' CHECK (status IN ('PENDING', 'EXPORTED', 'SETTLED')),
    admin_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.tuition_reconciliation_batches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public tuition batches policy" ON public.tuition_reconciliation_batches;
CREATE POLICY "Public tuition batches policy" ON public.tuition_reconciliation_batches FOR ALL USING (true);

-- RPC Procedure: fn_reconcile_tuition_pay_later_batch
CREATE OR REPLACE FUNCTION public.fn_reconcile_tuition_pay_later_batch(
    p_student_ids UUID[],
    p_admin_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_batch_ref TEXT;
    v_total_reconciled NUMERIC(10,2) := 0.00;
    v_count INT := 0;
    v_rec RECORD;
BEGIN
    v_batch_ref := 'TUITION-BATCH-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS');

    FOR v_rec IN 
        SELECT id, COALESCE(credit_liability, 0.00) AS debt 
        FROM public.profiles 
        WHERE id = ANY(p_student_ids) AND COALESCE(credit_liability, 0.00) > 0
    LOOP
        v_total_reconciled := v_total_reconciled + v_rec.debt;
        v_count := v_count + 1;

        -- Zero out liability after tuition batch migration
        UPDATE public.wallets SET credit_liability = 0.00, updated_at = NOW() WHERE user_id = v_rec.id;
        UPDATE public.profiles SET credit_liability = 0.00, updated_at = NOW() WHERE id = v_rec.id;
    END LOOP;

    IF v_count > 0 THEN
        INSERT INTO public.tuition_reconciliation_batches (batch_ref, total_debt_reconciled, student_count, status, admin_id)
        VALUES (v_batch_ref, v_total_reconciled, v_count, 'SETTLED', p_admin_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'batch_ref', v_batch_ref,
        'students_reconciled', v_count,
        'total_debt_reconciled', v_total_reconciled
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==============================================================================
-- END FINAL GOVERNANCE PATCH
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 17. FOOD SPOILAGE & PHYSICAL WASTE AUDIT SCHEMA
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.canteen_spoilage_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    product_name TEXT NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    reason_code TEXT NOT NULL CHECK (reason_code IN ('EXPIRED', 'DROPPED_TRAY', 'PREPARATION_ERROR', 'QUALITY_DEFECT', 'OTHER')),
    logged_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_spoilage_logs_product ON public.canteen_spoilage_logs(product_id);
CREATE INDEX IF NOT EXISTS idx_spoilage_logs_created ON public.canteen_spoilage_logs(created_at DESC);

ALTER TABLE public.canteen_spoilage_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read spoilage logs" ON public.canteen_spoilage_logs;
CREATE POLICY "Public read spoilage logs" ON public.canteen_spoilage_logs FOR SELECT USING (true);

DROP POLICY IF EXISTS "Staff insert spoilage logs" ON public.canteen_spoilage_logs;
CREATE POLICY "Staff insert spoilage logs" ON public.canteen_spoilage_logs FOR INSERT TO authenticated WITH CHECK (true);

-- RPC: fn_log_spoilage_and_deduct_stock
CREATE OR REPLACE FUNCTION public.fn_log_spoilage_and_deduct_stock(
    p_product_id UUID,
    p_product_name TEXT,
    p_quantity INT,
    p_reason_code TEXT,
    p_logged_by UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_current_stock INT;
    v_new_stock INT;
BEGIN
    SELECT stock_quantity INTO v_current_stock
    FROM public.products WHERE id = p_product_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Product not found');
    END IF;

    v_new_stock := GREATEST(0, COALESCE(v_current_stock, 0) - p_quantity);

    UPDATE public.products
    SET stock_quantity = v_new_stock,
        status = CASE WHEN v_new_stock = 0 THEN 'out_of_stock' ELSE status END,
        updated_at = NOW()
    WHERE id = p_product_id;

    INSERT INTO public.canteen_spoilage_logs (product_id, product_name, quantity, reason_code, logged_by, notes)
    VALUES (p_product_id, p_product_name, p_quantity, p_reason_code, p_logged_by, p_notes);

    RETURN jsonb_build_object(
        'success', true,
        'product_id', p_product_id,
        'new_stock', v_new_stock,
        'deducted', p_quantity
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 18. ATOMIC STOCK RESERVATION & 10% THRESHOLD LOCK PROCEDURE
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_reserve_stock_and_lock(
    p_product_id UUID,
    p_requested_qty INT,
    p_threshold_pct INT DEFAULT 10
)
RETURNS JSONB AS $$
DECLARE
    v_total_stock INT;
    v_initial_stock INT;
    v_remaining_stock INT;
    v_threshold_units INT;
    v_is_locked BOOLEAN := FALSE;
BEGIN
    SELECT stock_quantity, COALESCE(initial_stock, stock_quantity) INTO v_total_stock, v_initial_stock
    FROM public.products WHERE id = p_product_id FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Product not found');
    END IF;

    IF v_total_stock < p_requested_qty THEN
        RETURN jsonb_build_object('success', false, 'message', 'Insufficient stock', 'available', v_total_stock);
    END IF;

    v_remaining_stock := v_total_stock - p_requested_qty;
    v_threshold_units := CEIL(COALESCE(v_initial_stock, 100) * (p_threshold_pct::NUMERIC / 100.0));

    IF v_remaining_stock <= v_threshold_units THEN
        v_is_locked := TRUE;
    END IF;

    UPDATE public.products
    SET stock_quantity = v_remaining_stock,
        status = CASE 
            WHEN v_remaining_stock = 0 THEN 'out_of_stock'
            ELSE status
        END,
        updated_at = NOW()
    WHERE id = p_product_id;

    RETURN jsonb_build_object(
        'success', true,
        'product_id', p_product_id,
        'remaining_stock', v_remaining_stock,
        'is_locked_for_preorders', v_is_locked,
        'threshold_units', v_threshold_units
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;



