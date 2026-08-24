-- ============================================================
-- FIX: Wallet RPC Functions targeting wrong table
-- Run this in Supabase SQL Editor
-- The old functions incorrectly targeted public.profiles
-- which has NO balance column. Balance lives in public.wallets.
-- ============================================================

-- Fix fn_deduct_wallet_balance
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
    -- Lock the wallet row for this user
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

-- Fix fn_credit_wallet_balance
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
    -- Upsert so it works even if wallet row does not exist yet
    INSERT INTO public.wallets (user_id, balance, updated_at)
    VALUES (p_user_id, p_amount, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET balance    = public.wallets.balance + EXCLUDED.balance,
        updated_at = NOW()
    RETURNING balance INTO v_new_balance;

    RETURN v_new_balance;
END;
$$;

-- Fix fn_process_gcash_webhook (also used profiles incorrectly)
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
        NULL; -- wallet_transactions is optional
    END;

    RETURN jsonb_build_object('success', true, 'new_balance', v_new_bal, 'ref_no', p_ref_no);
END;
$$;

-- Reload PostgREST schema cache so changes take effect immediately
NOTIFY pgrst, 'reload schema';
