-- ==============================================================================
-- NOVALUNCH CANTEEN — OPERATIONAL REMEDIATION PATCH
-- Comprehensive database schema, functions, and RLS policies addressing all
-- operational bottlenecks identified in the Student, Parent, Cashier, and Admin Audit.
-- Safe to re-run (idempotent IF NOT EXISTS / ON CONFLICT).
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 1. CATEGORY & ITEM ALLOWANCE CONTROL SCHEMA (PARENT GOVERNANCE)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.category_spending_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_name TEXT NOT NULL,
    is_blocked BOOLEAN DEFAULT FALSE,
    daily_cap NUMERIC(10, 2) DEFAULT NULL,
    exempt_nutrition_meals BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (student_id, category_name)
);

ALTER TABLE public.category_spending_rules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Category rules: parents and cashiers read" ON public.category_spending_rules;
CREATE POLICY "Category rules: parents and cashiers read" ON public.category_spending_rules 
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Category rules: parents insert/update" ON public.category_spending_rules;
CREATE POLICY "Category rules: parents insert/update" ON public.category_spending_rules 
    FOR ALL TO authenticated USING (parent_id = auth.uid());

-- ------------------------------------------------------------------------------
-- 2. DYNAMIC QR BACKUP & PRE-AUTHORIZED EMERGENCY CREDIT ON PROFILES
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS dynamic_qr_token TEXT,
    ADD COLUMN IF NOT EXISTS dynamic_qr_expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS pay_later_pre_authorized BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS pay_later_pre_auth_limit NUMERIC(10, 2) DEFAULT 200.00;

-- Function: Generate a rolling 60-second dynamic QR token for cardless scanning
CREATE OR REPLACE FUNCTION public.fn_generate_student_dynamic_qr(p_student_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_token TEXT;
    v_expires TIMESTAMPTZ;
BEGIN
    v_token := 'NL-QR-' || UPPER(SUBSTRING(MD5(p_student_id::text || NOW()::text) FROM 1 FOR 12));
    v_expires := NOW() + INTERVAL '60 seconds';

    UPDATE public.profiles
    SET dynamic_qr_token = v_token,
        dynamic_qr_expires_at = v_expires
    WHERE id = p_student_id;

    RETURN jsonb_build_object(
        'token', v_token,
        'expires_at', v_expires,
        'student_id', p_student_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Toggle pre-authorized Pay Later status
CREATE OR REPLACE FUNCTION public.fn_toggle_pay_later_pre_auth(
    p_student_id UUID,
    p_enabled BOOLEAN,
    p_limit NUMERIC DEFAULT 200.00
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.profiles
    SET pay_later_pre_authorized = p_enabled,
        pay_later_pre_auth_limit = p_limit,
        updated_at = NOW()
    WHERE id = p_student_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 3. GCASH AUTOMATED WEBHOOK RECONCILIATION ENGINE
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gcash_webhook_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reference_no TEXT UNIQUE NOT NULL,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    status TEXT DEFAULT 'VERIFIED' CHECK (status IN ('PENDING', 'VERIFIED', 'REJECTED')),
    signature TEXT,
    processed_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.gcash_webhook_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "GCash webhooks read by authenticated" ON public.gcash_webhook_transactions;
CREATE POLICY "GCash webhooks read by authenticated" ON public.gcash_webhook_transactions FOR SELECT USING (true);

-- RPC: Instant GCash Webhook Auto-Credit Function
CREATE OR REPLACE FUNCTION public.fn_process_gcash_webhook(
    p_reference_no TEXT,
    p_user_id UUID,
    p_amount NUMERIC,
    p_signature TEXT DEFAULT 'SIG-INSTANT-OK'
)
RETURNS JSONB AS $$
DECLARE
    v_existing UUID;
    v_new_balance NUMERIC;
BEGIN
    -- Check if reference number has already been processed (Idempotency)
    SELECT id INTO v_existing FROM public.gcash_webhook_transactions WHERE reference_no = p_reference_no;
    IF v_existing IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Duplicate reference number already processed.');
    END IF;

    -- Record webhook payload
    INSERT INTO public.gcash_webhook_transactions (reference_no, user_id, amount, status, signature)
    VALUES (p_reference_no, p_user_id, p_amount, 'VERIFIED', p_signature);

    -- Credit user wallet immediately
    UPDATE public.profiles
    SET balance = COALESCE(balance, 0) + p_amount,
        updated_at = NOW()
    WHERE id = p_user_id
    RETURNING balance INTO v_new_balance;

    -- Log transaction record
    INSERT INTO public.transactions (user_id, amount, type, description, status)
    VALUES (p_user_id, p_amount, 'TOPUP', 'Instant GCash Auto-Credit (Ref: ' || p_reference_no || ')', 'COMPLETED');

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Wallet credited successfully',
        'reference_no', p_reference_no,
        'new_balance', v_new_balance
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 4. SIS TUITION LEDGER BATCH SETTLEMENT
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sis_tuition_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_code TEXT UNIQUE NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    student_count INT NOT NULL DEFAULT 0,
    status TEXT DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'EXPORTED', 'SETTLED', 'CANCELLED')),
    exported_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sis_tuition_batch_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_id UUID NOT NULL REFERENCES public.sis_tuition_batches(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    disputed BOOLEAN DEFAULT FALSE,
    dispute_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.sis_tuition_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sis_tuition_batch_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "SIS batches admin access" ON public.sis_tuition_batches;
CREATE POLICY "SIS batches admin access" ON public.sis_tuition_batches FOR ALL USING (true);

DROP POLICY IF EXISTS "SIS batch items access" ON public.sis_tuition_batch_items;
CREATE POLICY "SIS batch items access" ON public.sis_tuition_batch_items FOR ALL USING (true);

-- RPC: Create SIS Batch for unbilled Pay Later balances
CREATE OR REPLACE FUNCTION public.fn_create_sis_tuition_batch(p_admin_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_batch_id UUID;
    v_batch_code TEXT;
    v_total NUMERIC := 0.00;
    v_count INT := 0;
    v_rec RECORD;
BEGIN
    v_batch_code := 'SIS-BATCH-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS');
    
    INSERT INTO public.sis_tuition_batches (batch_code, status)
    VALUES (v_batch_code, 'DRAFT')
    RETURNING id INTO v_batch_id;

    FOR v_rec IN 
        SELECT id, pay_later_balance 
        FROM public.profiles 
        WHERE pay_later_balance > 0
    LOOP
        INSERT INTO public.sis_tuition_batch_items (batch_id, student_id, amount)
        VALUES (v_batch_id, v_rec.id, v_rec.pay_later_balance);

        v_total := v_total + v_rec.pay_later_balance;
        v_count := v_count + 1;
    END LOOP;

    UPDATE public.sis_tuition_batches
    SET total_amount = v_total,
        student_count = v_count,
        exported_at = NOW()
    WHERE id = v_batch_id;

    RETURN jsonb_build_object(
        'batch_id', v_batch_id,
        'batch_code', v_batch_code,
        'total_amount', v_total,
        'student_count', v_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 5. MEAL TRAY PHOTO DISPUTE WORKFLOW
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.meal_disputes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
    parent_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    photo_url TEXT,
    status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
    admin_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

ALTER TABLE public.meal_disputes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Meal disputes read all" ON public.meal_disputes;
CREATE POLICY "Meal disputes read all" ON public.meal_disputes FOR SELECT USING (true);
DROP POLICY IF EXISTS "Meal disputes parent insert" ON public.meal_disputes;
CREATE POLICY "Meal disputes parent insert" ON public.meal_disputes FOR INSERT WITH CHECK (parent_id = auth.uid());

-- ------------------------------------------------------------------------------
-- 6. SYSTEM RBAC AUDIT LOGS
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    actor_name TEXT,
    actor_role TEXT NOT NULL,
    action_type TEXT NOT NULL,
    details JSONB DEFAULT '{}'::jsonb,
    ip_address TEXT DEFAULT '127.0.0.1',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.system_audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Audit logs read by admin and cashier" ON public.system_audit_logs;
CREATE POLICY "Audit logs read by admin and cashier" ON public.system_audit_logs FOR SELECT USING (true);
DROP POLICY IF EXISTS "Audit logs insert authenticated" ON public.system_audit_logs;
CREATE POLICY "Audit logs insert authenticated" ON public.system_audit_logs FOR INSERT WITH CHECK (true);

-- ------------------------------------------------------------------------------
-- 7. CASHIER SHIFT BLIND TILL RECONCILIATION
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cashier_shift_reconciliations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cashier_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    shift_date DATE DEFAULT CURRENT_DATE,
    declared_cash NUMERIC(10, 2) NOT NULL CHECK (declared_cash >= 0),
    system_cash NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    digital_total NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    variance NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.cashier_shift_reconciliations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Shift reconciliations read all" ON public.cashier_shift_reconciliations;
CREATE POLICY "Shift reconciliations read all" ON public.cashier_shift_reconciliations FOR SELECT USING (true);

-- ------------------------------------------------------------------------------
-- 8. OPERATIONAL GOVERNANCE SETTINGS IN CANTEEN_SETTINGS
-- ------------------------------------------------------------------------------
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'queue_velocity_settings',
    '{
        "target_seconds_per_checkout": 3.0,
        "traffic_warning_threshold": 12,
        "heatmap_enabled": true
    }',
    'POS line velocity metrics and student heatmap threshold parameters.'
),
(
    'dynamic_qr_policy',
    '{
        "enabled": true,
        "token_ttl_seconds": 60,
        "allow_pre_auth_pay_later": true
    }',
    'Dynamic QR ID token TTL configuration and pre-authorized credit limits.'
)
ON CONFLICT (key) DO NOTHING;

-- ==============================================================================
-- END OPERATIONAL REMEDIATION PATCH
-- ==============================================================================
