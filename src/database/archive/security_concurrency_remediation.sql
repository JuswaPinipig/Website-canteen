-- ==============================================================================
-- NOVALUNCH CANTEEN POS - DATABASE INTEGRITY, SECURITY & CONCURRENCY PATCH
-- Version: 2.9 (Bulletproof Schema Adapter & Safe Indexing)
-- Target: Supabase / PostgreSQL 14+
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. SAFE COLUMN PROVISIONING (Universal Column Provisioner)
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    -- Ensure columns on public.wallets
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'wallets') THEN
        ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS balance NUMERIC(10,2) NOT NULL DEFAULT 0.00;
        ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS daily_limit NUMERIC(10,2) NOT NULL DEFAULT 200.00;
        ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS daily_spent NUMERIC(10,2) NOT NULL DEFAULT 0.00;
        ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS credit_liability NUMERIC(10,2) NOT NULL DEFAULT 0.00;
        ALTER TABLE public.wallets ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Ensure columns on public.profiles
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS balance NUMERIC(10,2) DEFAULT 0.00;
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS daily_limit NUMERIC(10,2) DEFAULT 200.00;
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS credit_liability NUMERIC(10,2) DEFAULT 0.00;
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS credit_limit NUMERIC(10,2) DEFAULT 500.00;
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pay_later_count INT DEFAULT 0;
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS pay_later_pre_authorized BOOLEAN DEFAULT TRUE;
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS rfid_uid TEXT;
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS student_id_number TEXT;
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'student';
        ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Ensure columns on public.products
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
        ALTER TABLE public.products ADD COLUMN IF NOT EXISTS price NUMERIC(10,2) NOT NULL DEFAULT 0.00;
        ALTER TABLE public.products ADD COLUMN IF NOT EXISTS stock_quantity INT NOT NULL DEFAULT 0;
        ALTER TABLE public.products ADD COLUMN IF NOT EXISTS product_type TEXT DEFAULT 'packaged_good';
        ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_available BOOLEAN DEFAULT TRUE;
        ALTER TABLE public.products ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Ensure columns on public.inventory_batches
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_batches') THEN
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS batch_number TEXT DEFAULT 'BATCH-001';
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS expiration_date TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days');
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS expiry_date TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days');
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS quantity_remaining INT DEFAULT 0;
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS current_quantity INT DEFAULT 0;
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS quantity_added INT DEFAULT 0;
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS initial_quantity INT DEFAULT 0;
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'ACTIVE';
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(10,2) DEFAULT 0.00;
        ALTER TABLE public.inventory_batches ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

        UPDATE public.inventory_batches 
        SET expiry_date = COALESCE(expiry_date, expiration_date, NOW() + INTERVAL '30 days'),
            expiration_date = COALESCE(expiration_date, expiry_date, NOW() + INTERVAL '30 days')
        WHERE expiry_date IS NULL OR expiration_date IS NULL;

        UPDATE public.inventory_batches
        SET current_quantity = GREATEST(0, COALESCE(current_quantity, quantity_remaining, 0)),
            quantity_remaining = GREATEST(0, COALESCE(quantity_remaining, current_quantity, 0))
        WHERE current_quantity IS NULL OR quantity_remaining IS NULL;
    END IF;

    -- Ensure columns on public.preorders
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'preorders') THEN
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
        ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
        ALTER TABLE public.preorders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Ensure columns on public.orders
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders') THEN
        ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_number TEXT;
        ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS final_amount NUMERIC(10,2) DEFAULT 0.00;
        ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS total_amount NUMERIC(10,2) DEFAULT 0.00;
        ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_amount NUMERIC(10,2) DEFAULT 0.00;
        ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_status TEXT DEFAULT 'completed';
        ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash';
        ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Ensure columns on public.order_items
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'order_items') THEN
        ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS unit_price NUMERIC(10,2) NOT NULL DEFAULT 0.00;
        ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS quantity INT NOT NULL DEFAULT 1;
        ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS total_price NUMERIC(10,2) DEFAULT 0.00;
        ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS subtotal NUMERIC(10,2) DEFAULT 0.00;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 2. DATA INTEGRITY & NUMERIC CHECK CONSTRAINTS
-- ------------------------------------------------------------------------------
DO $$
BEGIN
    -- Products: Price and stock constraints
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_products_price_non_negative') THEN
        ALTER TABLE public.products ADD CONSTRAINT chk_products_price_non_negative CHECK (price >= 0.00);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_products_stock_non_negative') THEN
        ALTER TABLE public.products ADD CONSTRAINT chk_products_stock_non_negative CHECK (stock_quantity >= 0);
    END IF;

    -- Wallets: Balance, credit liability, and daily limit constraints
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_wallets_balance_non_negative') THEN
        ALTER TABLE public.wallets ADD CONSTRAINT chk_wallets_balance_non_negative CHECK (balance >= 0.00);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_wallets_liability_non_negative') THEN
        ALTER TABLE public.wallets ADD CONSTRAINT chk_wallets_liability_non_negative CHECK (credit_liability >= 0.00);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_wallets_daily_limit_positive') THEN
        ALTER TABLE public.wallets ADD CONSTRAINT chk_wallets_daily_limit_positive CHECK (daily_limit >= 0.00);
    END IF;

    -- Profiles: Daily limit and credit liability constraints
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_profiles_liability_non_negative') THEN
        ALTER TABLE public.profiles ADD CONSTRAINT chk_profiles_liability_non_negative CHECK (credit_liability >= 0.00);
    END IF;

    -- Orders & Order Items: Pricing & Qty constraints
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_final_amount_non_negative') THEN
        ALTER TABLE public.orders ADD CONSTRAINT chk_orders_final_amount_non_negative CHECK (final_amount >= 0.00);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_order_items_qty_positive') THEN
        ALTER TABLE public.order_items ADD CONSTRAINT chk_order_items_qty_positive CHECK (quantity > 0);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_order_items_unit_price_non_negative') THEN
        ALTER TABLE public.order_items ADD CONSTRAINT chk_order_items_unit_price_non_negative CHECK (unit_price >= 0.00);
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 3. HIGH-TRAFFIC PERFORMANCE INDEXES
-- ------------------------------------------------------------------------------
DO $$ BEGIN
    -- Profiles & RFID Lookup
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'rfid_uid') THEN
            CREATE INDEX IF NOT EXISTS idx_profiles_rfid_uid ON public.profiles(rfid_uid) WHERE rfid_uid IS NOT NULL;
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'student_id_number') THEN
            CREATE INDEX IF NOT EXISTS idx_profiles_student_id ON public.profiles(student_id_number) WHERE student_id_number IS NOT NULL;
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'role') THEN
            CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
        END IF;
    END IF;

    -- Wallets
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'wallets') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'wallets' AND column_name = 'user_id') THEN
            CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON public.wallets(user_id);
        END IF;
    END IF;

    -- Orders & Order Items
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'user_id') THEN
            CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders(user_id);
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'created_at') THEN
            CREATE INDEX IF NOT EXISTS idx_orders_created_at_desc ON public.orders(created_at DESC);
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'order_number') THEN
            CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'orders' AND column_name = 'order_status') THEN
            CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(order_status);
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'order_items') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'order_items' AND column_name = 'order_id') THEN
            CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items(order_id);
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'order_items' AND column_name = 'product_id') THEN
            CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items(product_id);
        END IF;
    END IF;

    -- Inventory Batches
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_batches') THEN
        CREATE INDEX IF NOT EXISTS idx_batches_product_id ON public.inventory_batches(product_id);
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'inventory_batches' AND column_name = 'expiry_date') THEN
            CREATE INDEX IF NOT EXISTS idx_batches_product_expiry ON public.inventory_batches(product_id, expiry_date ASC);
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'inventory_batches' AND column_name = 'expiration_date') THEN
            CREATE INDEX IF NOT EXISTS idx_batches_product_expiry ON public.inventory_batches(product_id, expiration_date ASC);
        END IF;
    END IF;

    -- Pre-Orders
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'preorders') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'preorders' AND column_name = 'student_id') THEN
            CREATE INDEX IF NOT EXISTS idx_preorders_student_id ON public.preorders(student_id);
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'preorders' AND column_name = 'status') THEN
            CREATE INDEX IF NOT EXISTS idx_preorders_status ON public.preorders(status);
        END IF;
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'preorders' AND column_name = 'token') THEN
            CREATE INDEX IF NOT EXISTS idx_preorders_token ON public.preorders(token);
        END IF;
    END IF;

    -- Wallet & Audit Transactions
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'wallet_transactions') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'wallet_transactions' AND column_name = 'user_id') THEN
            CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created ON public.wallet_transactions(user_id, created_at DESC);
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'audit_logs' AND column_name = 'user_id') THEN
            CREATE INDEX IF NOT EXISTS idx_audit_logs_user_action ON public.audit_logs(user_id, action, created_at DESC);
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'audit_logs' AND column_name = 'actor_id') THEN
            CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_action ON public.audit_logs(actor_id, action, created_at DESC);
        END IF;
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 4. CONCURRENCY & ATOMIC STORED PROCEDURES (FOR UPDATE GUARDS)
-- ------------------------------------------------------------------------------

-- A. Atomic Wallet Balance Deduction with Concurrency Lock
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

    -- Strict row-level lock on the target wallet
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

    -- Synchronize profile mirror
    UPDATE public.profiles 
    SET balance = v_new_balance, 
        updated_at = NOW() 
    WHERE id = p_user_id;

    RETURN v_new_balance;
END;
$$;

-- B. Atomic FIFO Inventory Stock Deduction with Row Locks
CREATE OR REPLACE FUNCTION public.fn_deduct_stock_fifo(
    p_product_id UUID,
    p_quantity_to_deduct INT,
    p_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    batches_used JSONB
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_available INT;
    v_remaining_needed INT := p_quantity_to_deduct;
    v_batch RECORD;
    v_deduct_amount INT;
    v_used_list JSONB := '[]'::JSONB;
    v_product_name TEXT;
    v_prev_total_stock INT;
    v_new_total_stock INT;
BEGIN
    IF p_quantity_to_deduct <= 0 THEN
        RETURN QUERY SELECT FALSE, 'ERR_INVALID_QTY: Deduction quantity must be positive', '[]'::JSONB;
        RETURN;
    END IF;

    -- Acquire exclusive lock on the master product record to serialize deductions
    SELECT name, stock_quantity INTO v_product_name, v_prev_total_stock
    FROM public.products
    WHERE id = p_product_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'ERR_PRODUCT_NOT_FOUND: Product does not exist', '[]'::JSONB;
        RETURN;
    END IF;

    -- Calculate current active, non-expired batch stock
    SELECT COALESCE(SUM(GREATEST(0, COALESCE(quantity_remaining, current_quantity, 0))), 0)
    INTO v_total_available
    FROM public.inventory_batches
    WHERE product_id = p_product_id
      AND UPPER(status) IN ('ACTIVE', 'NEAR_EXPIRY', 'FRESH')
      AND COALESCE(quantity_remaining, current_quantity, 0) > 0;

    IF v_total_available < p_quantity_to_deduct THEN
        RETURN QUERY SELECT FALSE, 
            'ERR_INSUFFICIENT_STOCK: Requested ' || p_quantity_to_deduct || ' ' || v_product_name || '(s), but only ' || v_total_available || ' available.',
            '[]'::JSONB;
        RETURN;
    END IF;

    -- Iterate and lock batches in strict FIFO order (earliest expiry first)
    FOR v_batch IN
        SELECT id, batch_number, 
               GREATEST(0, COALESCE(quantity_remaining, current_quantity, 0)) AS cur_qty, 
               COALESCE(expiry_date, expiration_date) AS exp_date, status
        FROM public.inventory_batches
        WHERE product_id = p_product_id
          AND UPPER(status) IN ('ACTIVE', 'NEAR_EXPIRY', 'FRESH')
          AND COALESCE(quantity_remaining, current_quantity, 0) > 0
        ORDER BY COALESCE(expiry_date, expiration_date, NOW()) ASC, created_at ASC
        FOR UPDATE
    LOOP
        EXIT WHEN v_remaining_needed <= 0;

        IF v_batch.cur_qty >= v_remaining_needed THEN
            v_deduct_amount := v_remaining_needed;
        ELSE
            v_deduct_amount := v_batch.cur_qty;
        END IF;

        UPDATE public.inventory_batches
        SET current_quantity = GREATEST(0, v_batch.cur_qty - v_deduct_amount),
            quantity_remaining = GREATEST(0, v_batch.cur_qty - v_deduct_amount),
            status = CASE 
                WHEN (v_batch.cur_qty - v_deduct_amount) <= 0 THEN 'DEPLETED'
                ELSE status
            END,
            updated_at = NOW()
        WHERE id = v_batch.id;

        v_remaining_needed := v_remaining_needed - v_deduct_amount;

        v_used_list := v_used_list || jsonb_build_object(
            'batch_id', v_batch.id,
            'batch_number', v_batch.batch_number,
            'quantity_deducted', v_deduct_amount,
            'expiry_date', v_batch.exp_date
        );
    END LOOP;

    -- Recalculate aggregate stock
    SELECT COALESCE(SUM(GREATEST(0, COALESCE(quantity_remaining, current_quantity, 0))), 0)
    INTO v_new_total_stock
    FROM public.inventory_batches
    WHERE product_id = p_product_id
      AND UPPER(status) IN ('ACTIVE', 'NEAR_EXPIRY', 'FRESH');

    UPDATE public.products
    SET stock_quantity = v_new_total_stock,
        is_available = (v_new_total_stock > 0),
        updated_at = NOW()
    WHERE id = p_product_id;

    -- Write audit trail log
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_logs') THEN
        INSERT INTO public.inventory_logs (
            product_id, batch_id, change_type, quantity, remaining_stock, performed_by, reason
        ) VALUES (
            p_product_id, NULL, 'pos_sale', -p_quantity_to_deduct,
            v_new_total_stock, p_user_id::text, 'POS express checkout deduction'
        );
    END IF;

    RETURN QUERY SELECT TRUE, 'SUCCESS: Stock deducted successfully', v_used_list;
END;
$$;

-- C. Atomic Multi-Item Cart FIFO Deduction
CREATE OR REPLACE FUNCTION public.fn_deduct_cart_stock_fifo(p_items JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item JSONB;
    v_prod_id UUID;
    v_qty INT;
    v_res RECORD;
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := (v_item->>'id')::UUID;
        v_qty     := COALESCE((v_item->>'qty')::INT, (v_item->>'quantity')::INT, 1);

        IF v_prod_id IS NOT NULL THEN
            SELECT success, message INTO v_res FROM public.fn_deduct_stock_fifo(v_prod_id, v_qty);
            IF NOT v_res.success THEN
                RAISE EXCEPTION '%', v_res.message;
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'message', 'Cart stock successfully deducted atomically');
END;
$$;

-- D. Atomic Debt Settlement with Wallet & Profile Concurrency Locks
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
BEGIN
    IF p_repayment_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Repayment amount must be positive');
    END IF;

    -- Concurrently lock both profile and wallet records
    SELECT credit_liability, balance INTO v_curr_debt, v_curr_bal
    FROM public.profiles
    WHERE id = p_student_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Student profile not found');
    END IF;

    PERFORM 1 FROM public.wallets WHERE user_id = p_student_id FOR UPDATE;

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

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'wallet_transactions') THEN
        INSERT INTO public.wallet_transactions (
            user_id, transaction_type, amount, balance_before, balance_after, payment_channel, description
        ) VALUES (
            p_student_id, 'PAY_LATER_SETTLEMENT', p_repayment_amount, v_curr_bal, v_new_bal, UPPER(p_payment_method), 'Pay Later emergency debt repayment clearance'
        );
    END IF;

    RETURN jsonb_build_object('success', true, 'remaining_liability', v_new_debt, 'new_balance', v_new_bal);
END;
$$;

-- ------------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS) HARDENING
-- ------------------------------------------------------------------------------
-- Enable RLS on primary tables if they exist
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
        ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'wallets') THEN
        ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'products') THEN
        ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders') THEN
        ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'order_items') THEN
        ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'inventory_batches') THEN
        ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'preorders') THEN
        ALTER TABLE public.preorders ENABLE ROW LEVEL SECURITY;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'canteen_settings') THEN
        ALTER TABLE public.canteen_settings ENABLE ROW LEVEL SECURITY;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'wallet_transactions') THEN
        ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
    END IF;
END $$;

-- Drop and recreate RLS policies cleanly
DO $$ BEGIN
    -- Profiles
    DROP POLICY IF EXISTS "Public profiles write" ON public.profiles;
    DROP POLICY IF EXISTS "Public profiles read" ON public.profiles;
    DROP POLICY IF EXISTS "Profiles viewable by all authenticated" ON public.profiles;
    CREATE POLICY "Profiles viewable by all authenticated" ON public.profiles FOR SELECT USING (true);

    -- Wallets
    DROP POLICY IF EXISTS "Public wallets write" ON public.wallets;
    DROP POLICY IF EXISTS "Wallets viewable by owner and staff" ON public.wallets;
    CREATE POLICY "Wallets viewable by owner and staff" ON public.wallets
        FOR SELECT USING (
            auth.uid() = user_id 
            OR EXISTS (
                SELECT 1 FROM public.profiles 
                WHERE id = auth.uid() AND role IN ('admin', 'cashier', 'staff')
            )
            OR auth.role() = 'anon'
        );

    DROP POLICY IF EXISTS "Wallets modifiable only by admin" ON public.wallets;
    CREATE POLICY "Wallets modifiable only by admin" ON public.wallets
        FOR ALL USING (
            EXISTS (
                SELECT 1 FROM public.profiles 
                WHERE id = auth.uid() AND role IN ('admin')
            )
        );

    -- Products
    DROP POLICY IF EXISTS "Public products all" ON public.products;
    DROP POLICY IF EXISTS "Products readable by all" ON public.products;
    CREATE POLICY "Products readable by all" ON public.products FOR SELECT USING (true);

    DROP POLICY IF EXISTS "Products modifiable by staff and admin" ON public.products;
    CREATE POLICY "Products modifiable by staff and admin" ON public.products
        FOR ALL USING (
            EXISTS (
                SELECT 1 FROM public.profiles 
                WHERE id = auth.uid() AND role IN ('admin', 'cashier', 'staff')
            )
        );

    -- Orders
    DROP POLICY IF EXISTS "Public orders all" ON public.orders;
    DROP POLICY IF EXISTS "Orders viewable by student or staff" ON public.orders;
    CREATE POLICY "Orders viewable by student or staff" ON public.orders
        FOR SELECT USING (
            auth.uid() = user_id 
            OR EXISTS (
                SELECT 1 FROM public.profiles 
                WHERE id = auth.uid() AND role IN ('admin', 'cashier', 'staff')
            )
            OR auth.role() = 'anon'
        );

    DROP POLICY IF EXISTS "Orders insertable by authenticated users and POS" ON public.orders;
    CREATE POLICY "Orders insertable by authenticated users and POS" ON public.orders
        FOR INSERT WITH CHECK (true);

    -- Settings
    DROP POLICY IF EXISTS "Public settings all" ON public.canteen_settings;
    DROP POLICY IF EXISTS "Settings readable by all" ON public.canteen_settings;
    CREATE POLICY "Settings readable by all" ON public.canteen_settings FOR SELECT USING (true);

    DROP POLICY IF EXISTS "Settings editable only by admin" ON public.canteen_settings;
    CREATE POLICY "Settings editable only by admin" ON public.canteen_settings
        FOR ALL USING (
            EXISTS (
                SELECT 1 FROM public.profiles 
                WHERE id = auth.uid() AND role IN ('admin')
            )
        );
END $$;
