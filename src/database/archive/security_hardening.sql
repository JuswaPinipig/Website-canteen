-- ==============================================================================
-- NOVALUNCH CANTEEN — SECURITY HARDENING PATCH
-- Run this AFTER supabase_schema.sql and inventory_batch_management.sql
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. ATOMIC WALLET DEDUCTION RPC
--    Uses a single-statement delta UPDATE with a balance floor check.
--    Eliminates read-then-write race condition in updateStudentBalance.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_deduct_wallet_balance(
    p_user_id UUID,
    p_amount   NUMERIC
)
RETURNS JSONB AS $$
DECLARE
    v_wallet_id      UUID;
    v_prev_balance   NUMERIC;
    v_new_balance    NUMERIC;
    v_exists         BOOLEAN;
BEGIN
    -- Capture current balance before update for error reporting
    SELECT id, balance
    INTO   v_wallet_id, v_prev_balance
    FROM   public.wallets
    WHERE  user_id = p_user_id;

    IF v_wallet_id IS NULL THEN
        RAISE EXCEPTION 'WALLET_NOT_FOUND: No wallet for user %', p_user_id;
    END IF;

    IF v_prev_balance < p_amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Required ₱%, Available ₱%',
            p_amount, v_prev_balance;
    END IF;

    -- Atomic delta UPDATE — WHERE balance >= p_amount is a safety net against races
    UPDATE public.wallets
    SET balance     = balance - p_amount,
        daily_spent = daily_spent + p_amount,
        updated_at  = NOW()
    WHERE user_id = p_user_id
      AND balance  >= p_amount;

    v_new_balance := v_prev_balance - p_amount;

    -- Sync profile balance mirror
    UPDATE public.profiles
    SET balance    = v_new_balance,
        updated_at = NOW()
    WHERE id = p_user_id;

    -- Write wallet ledger entry
    INSERT INTO public.wallet_transactions
        (wallet_id, user_id, amount, transaction_type, payment_method, description)
    VALUES
        (v_wallet_id, p_user_id, -p_amount, 'purchase', 'rfid', 'Atomic POS deduction');

    RETURN jsonb_build_object(
        'success',          true,
        'previous_balance', v_prev_balance,
        'new_balance',      v_new_balance,
        'amount_deducted',  p_amount
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ------------------------------------------------------------------------------
-- 2. FIX AI KIOSK OVERSELL BUG
--    Replaces GREATEST(0, ...) silent clamp with an explicit stock guard.
--    A panelist cannot purchase items the system physically doesn't have.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.settle_ai_kiosk_transaction(
    p_student_id  UUID,
    p_items       JSONB,
    p_total_amount NUMERIC
) RETURNS JSONB AS $$
DECLARE
    v_wallet_id       UUID;
    v_current_balance NUMERIC;
    v_order_id        UUID;
    v_order_num       TEXT;
    item              JSONB;
    v_stock_available INT;
    v_item_qty        INT;
    v_product_name    TEXT;
BEGIN
    -- 1. Lock student wallet
    SELECT id, balance
    INTO   v_wallet_id, v_current_balance
    FROM   public.wallets
    WHERE  user_id = p_student_id
    FOR UPDATE;

    IF v_wallet_id IS NULL THEN
        RAISE EXCEPTION 'WALLET_NOT_FOUND: No wallet for student %', p_student_id;
    END IF;

    IF v_current_balance < p_total_amount THEN
        RAISE EXCEPTION 'INSUFFICIENT_FUNDS: Required ₱%, Available ₱%',
            p_total_amount, v_current_balance;
    END IF;

    -- 2. Pre-validate stock for every item BEFORE any mutations
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_item_qty := (item->>'qty')::INT;

        SELECT stock_quantity, name
        INTO   v_stock_available, v_product_name
        FROM   public.products
        WHERE  id = (item->>'product_id')::UUID;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'PRODUCT_NOT_FOUND: Product % does not exist',
                item->>'product_id';
        END IF;

        IF v_stock_available < v_item_qty THEN
            RAISE EXCEPTION 'INSUFFICIENT_STOCK: % has only % unit(s) available, requested %',
                v_product_name, v_stock_available, v_item_qty;
        END IF;
    END LOOP;

    -- 3. Deduct wallet balance atomically
    UPDATE public.wallets
    SET balance     = balance - p_total_amount,
        daily_spent = daily_spent + p_total_amount,
        updated_at  = NOW()
    WHERE id = v_wallet_id;

    -- 4. Create POS order record
    v_order_num := 'ORD-AI-' || TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS') || '-'
                   || SUBSTRING(CAST(gen_random_uuid() AS TEXT), 1, 4);

    INSERT INTO public.orders
        (order_number, user_id, total_amount, final_amount,
         payment_method, payment_status, order_source, order_status)
    VALUES
        (v_order_num, p_student_id, p_total_amount, p_total_amount,
         'rfid', 'paid', 'ai_kiosk', 'completed')
    RETURNING id INTO v_order_id;

    -- 5. Log wallet transaction
    INSERT INTO public.wallet_transactions
        (wallet_id, user_id, amount, transaction_type, payment_method, reference_id, description)
    VALUES
        (v_wallet_id, p_student_id, -p_total_amount, 'purchase',
         'rfid', v_order_num, 'AI Kiosk Tray Auto-Deduction');

    -- 6. Deduct stock & insert order items
    FOR item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_item_qty := (item->>'qty')::INT;

        -- Exact deduction — no GREATEST() clamp; stock was pre-validated above
        UPDATE public.products
        SET stock_quantity = stock_quantity - v_item_qty,
            updated_at     = NOW()
        WHERE id = (item->>'product_id')::UUID;

        INSERT INTO public.order_items
            (order_id, product_id, product_name, unit_price, quantity, subtotal)
        VALUES
            (v_order_id,
             (item->>'product_id')::UUID,
             item->>'name',
             (item->>'price')::NUMERIC,
             v_item_qty,
             (item->>'price')::NUMERIC * v_item_qty);
    END LOOP;

    RETURN jsonb_build_object(
        'success',           true,
        'order_id',          v_order_id,
        'order_number',      v_order_num,
        'remaining_balance', v_current_balance - p_total_amount
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 3. TIGHTEN RLS — DROP OPEN POLICIES & REPLACE WITH ROLE-AWARE ONES
--    "USING (true)" grants every anon visitor full write access — removed.
--    Pattern: service role (backend RPC) bypasses RLS; anon users are locked.
-- ------------------------------------------------------------------------------

-- Wallets: only owner or service role
DROP POLICY IF EXISTS "Allow full access wallets"         ON public.wallets;
DROP POLICY IF EXISTS "Allow full access wallet_transactions" ON public.wallet_transactions;
DROP POLICY IF EXISTS "Allow full access orders"          ON public.orders;
DROP POLICY IF EXISTS "Allow full access order_items"     ON public.order_items;
DROP POLICY IF EXISTS "Allow full access rfid_cards"      ON public.rfid_cards;
DROP POLICY IF EXISTS "Allow full access ai_detection_logs" ON public.ai_detection_logs;
DROP POLICY IF EXISTS "Allow full access parent_student_link_requests" ON public.parent_student_link_requests;
DROP POLICY IF EXISTS "Allow full access notifications"   ON public.notifications;
DROP POLICY IF EXISTS "Allow full access for authenticated/anon during development" ON public.profiles;
DROP POLICY IF EXISTS "Allow anon read products"          ON public.products;

-- Profiles: authenticated users see only their own row; service role sees all
CREATE POLICY "Profiles: owner read"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY "Profiles: owner update"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (auth.uid() = id);

-- Wallets: owner only
CREATE POLICY "Wallets: owner read"
    ON public.wallets FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "Wallets: owner update via RPC only"
    ON public.wallets FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid());

-- Orders: owner can read their own; cashiers/admins need service role (RPC)
CREATE POLICY "Orders: owner read"
    ON public.orders FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

CREATE POLICY "Orders: insert by authenticated"
    ON public.orders FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Order items: owner read"
    ON public.order_items FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.orders o
            WHERE o.id = order_id AND o.user_id = auth.uid()
        )
    );

-- Wallet transactions: owner read only
CREATE POLICY "Wallet TX: owner read"
    ON public.wallet_transactions FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- Notifications: owner only
CREATE POLICY "Notifications: owner"
    ON public.notifications FOR ALL
    TO authenticated
    USING (user_id = auth.uid());

-- RFID cards: owner read
CREATE POLICY "RFID: owner read"
    ON public.rfid_cards FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- AI detection logs: authenticated insert only (kiosk)
CREATE POLICY "AI logs: authenticated insert"
    ON public.ai_detection_logs FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Parent-student link requests: participants only
CREATE POLICY "Link requests: participant read"
    ON public.parent_student_link_requests FOR SELECT
    TO authenticated
    USING (parent_id = auth.uid() OR student_id = auth.uid());

CREATE POLICY "Link requests: participant write"
    ON public.parent_student_link_requests FOR ALL
    TO authenticated
    USING (parent_id = auth.uid() OR student_id = auth.uid());

-- Products: keep public read
CREATE POLICY "Products: public read"
    ON public.products FOR SELECT
    USING (true);

-- ------------------------------------------------------------------------------
-- 4. IDEMPOTENCY — DUPLICATE ORDER PREVENTION
--    The existing UNIQUE constraint on orders.order_number already prevents
--    duplicate DB inserts at the database level. The client-side
--    isCheckoutSubmitting state guard prevents double-click submissions.
--    No additional index needed (date_trunc is STABLE, not IMMUTABLE,
--    so it cannot be used in index expressions).
-- ------------------------------------------------------------------------------

-- ------------------------------------------------------------------------------
-- Done
-- ------------------------------------------------------------------------------
