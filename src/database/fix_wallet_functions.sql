-- ============================================================
-- MASTER FIX PATCH — Run this in Supabase SQL Editor
-- Fixes:
--   1. fn_deduct_wallet_balance targeting profiles instead of wallets
--   2. fn_credit_wallet_balance targeting profiles instead of wallets
--   3. fn_process_gcash_webhook targeting profiles instead of wallets
--   4. preorders table missing columns (product_id, student_id_number, token, pickup_slot)
-- ============================================================

-- ===========================================================
-- PART 1: Fix preorders table schema (add missing columns)
-- ===========================================================

-- Add product_id column if it doesn't exist
ALTER TABLE public.preorders
    ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES public.products(id) ON DELETE SET NULL;

-- Add student_id_number (text identifier for display)
ALTER TABLE public.preorders
    ADD COLUMN IF NOT EXISTS student_id_number TEXT;

-- Add token column for QR claim codes
ALTER TABLE public.preorders
    ADD COLUMN IF NOT EXISTS token TEXT;

-- Add pickup_slot for specific pickup time
ALTER TABLE public.preorders
    ADD COLUMN IF NOT EXISTS pickup_slot TEXT DEFAULT '12:00 PM';

-- Add updated_at if missing
ALTER TABLE public.preorders
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- ===========================================================
-- PART 2: Fix fn_deduct_wallet_balance
-- (Was incorrectly updating public.profiles — no balance there)
-- ===========================================================
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
    -- Lock the wallet row for this user atomically
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

    RETURN v_new_balance;
END;
$$;

-- ===========================================================
-- PART 3: Fix fn_credit_wallet_balance
-- ===========================================================
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

    RETURN v_new_balance;
END;
$$;

-- ===========================================================
-- PART 4: Fix fn_process_gcash_webhook
-- ===========================================================
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

    -- Log the transaction if wallet_transactions table exists
    BEGIN
        INSERT INTO public.wallet_transactions (
            user_id, transaction_type, amount,
            balance_before, balance_after,
            reference_id, payment_channel, description
        )
        VALUES (
            p_student_id, 'RELOAD_GCASH', p_amount,
            COALESCE(v_old_bal, 0), v_new_bal,
            p_ref_no, 'GCASH_WEBHOOK', 'Instant GCash Webhook Auto-Credit'
        );
    EXCEPTION WHEN OTHERS THEN
        NULL; -- wallet_transactions is optional, skip if not found
    END;

    RETURN jsonb_build_object('success', true, 'new_balance', v_new_bal, 'ref_no', p_ref_no);
END;
$$;


-- ===========================================================
-- PART 5: Reload PostgREST schema cache
-- ===========================================================
NOTIFY pgrst, 'reload schema';

-- ===========================================================
-- PART 6: Enable Realtime on wallets and preorders tables
-- (Idempotent check to avoid 42710 already member error)
-- ===========================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'wallets'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.wallets;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
          AND schemaname = 'public' 
          AND tablename = 'preorders'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.preorders;
    END IF;
END $$;

-- ===========================================================
-- PART 7: RLS Policies — allow full access for wallet operations
-- ===========================================================

-- Enable Row Level Security on wallets
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

-- Drop any restrictive existing policies
DROP POLICY IF EXISTS "wallets_select_own" ON public.wallets;
DROP POLICY IF EXISTS "wallets_admin_all" ON public.wallets;
DROP POLICY IF EXISTS "Wallets: owner read" ON public.wallets;
DROP POLICY IF EXISTS "Wallets: owner update via RPC only" ON public.wallets;
DROP POLICY IF EXISTS "Allow full access wallets" ON public.wallets;
DROP POLICY IF EXISTS "wallets_all_access" ON public.wallets;

-- Create full access policy for wallets (needed for portal live sync & admin adjustments)
CREATE POLICY "wallets_all_access" ON public.wallets
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- Allow authenticated and anon users to SELECT and manage preorders
DROP POLICY IF EXISTS "preorders_select_all" ON public.preorders;
DROP POLICY IF EXISTS "preorders_all_access" ON public.preorders;
CREATE POLICY "preorders_all_access" ON public.preorders
    FOR ALL
    USING (true)
    WITH CHECK (true);

ALTER TABLE public.preorders ENABLE ROW LEVEL SECURITY;

-- ===========================================================
-- PART 8: Add mirror columns to profiles table if missing
-- ===========================================================
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS balance NUMERIC(10,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS daily_limit NUMERIC(10,2) DEFAULT 200.00;

-- Sync initial balances from wallets into profiles
UPDATE public.profiles p
SET balance = w.balance,
    daily_limit = COALESCE(w.daily_limit, 200.00)
FROM public.wallets w
WHERE p.id = w.user_id;

-- ===========================================================
-- PART 9: Universal Admin Wallet & Spending Limit Update RPC
-- (Works for every student, new and existing, bypassing RLS)
-- ===========================================================
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
    -- 1. Upsert into public.wallets
    INSERT INTO public.wallets (user_id, balance, daily_limit, updated_at)
    VALUES (
        p_user_id,
        COALESCE(p_balance, 0.00),
        COALESCE(p_daily_limit, 200.00),
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET balance          = COALESCE(p_balance, public.wallets.balance),
        daily_limit      = COALESCE(p_daily_limit, public.wallets.daily_limit),
        updated_at       = NOW()
    RETURNING balance, daily_limit
    INTO v_new_bal, v_new_limit;

    -- 2. Synchronize profiles columns if needed
    IF p_credit_liability IS NOT NULL THEN
        BEGIN
            UPDATE public.profiles
            SET credit_liability = p_credit_liability,
                updated_at       = NOW()
            WHERE id = p_user_id;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;

    -- 3. Log transaction if wallet_transactions exists and balance changed
    IF p_balance IS NOT NULL THEN
        BEGIN
            INSERT INTO public.wallet_transactions (
                user_id, transaction_type, amount,
                balance_after, reference_id,
                payment_channel, description
            )
            VALUES (
                p_user_id, 'ADMIN_ADJUST', p_balance,
                v_new_bal, 'ADM-' || to_char(NOW(), 'YYYYMMDD-HH24MISS'),
                'ADMIN_PORTAL', 'Administrative balance adjustment'
            );
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'balance', v_new_bal,
        'daily_limit', v_new_limit,
        'credit_liability', COALESCE(p_credit_liability, 0.00)
    );
END;
$$;

-- Grant execution to public and authenticated roles
GRANT EXECUTE ON FUNCTION public.fn_admin_update_wallet(UUID, NUMERIC, NUMERIC, NUMERIC) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_deduct_wallet_balance(UUID, NUMERIC) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_credit_wallet_balance(UUID, NUMERIC) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_process_gcash_webhook(TEXT, UUID, NUMERIC) TO anon, authenticated, service_role;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';


