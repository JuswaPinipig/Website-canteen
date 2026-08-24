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
