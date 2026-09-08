-- ==============================================================================
-- CANTEEN POS & INVENTORY SYSTEM - BATCH & EXPIRY MANAGEMENT MIGRATION
-- Project: NovaLunch Canteen POS System
-- Target: Supabase / PostgreSQL
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. ENUMS & SCHEMA EXTENSIONS FOR PRODUCT TYPES & INVENTORY LOGS
-- ------------------------------------------------------------------------------

-- Ensure product_type column on public.products
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'product_type') THEN
        ALTER TABLE public.products ADD COLUMN product_type TEXT NOT NULL DEFAULT 'packaged_good' CHECK (product_type IN ('ulam_meal', 'packaged_good'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'shelf_life_hours') THEN
        ALTER TABLE public.products ADD COLUMN shelf_life_hours INT DEFAULT NULL; -- For Ulam/Daily Meals (e.g. 6 hours)
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'warning_threshold_days') THEN
        ALTER TABLE public.products ADD COLUMN warning_threshold_days INT DEFAULT 3; -- For Packaged Goods (e.g. 3 days before expiry)
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'warning_threshold_hours') THEN
        ALTER TABLE public.products ADD COLUMN warning_threshold_hours INT DEFAULT 1; -- For Ulam (e.g. 1 hour before meal batch expiry)
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'unit_name') THEN
        ALTER TABLE public.products ADD COLUMN unit_name TEXT DEFAULT 'pcs'; -- 'serving' for ulam, 'pack'/'bottle'/'pcs' for packaged
    END IF;
END $$;

-- ------------------------------------------------------------------------------
-- 2. INVENTORY BATCHES TABLE (Multi-batch stock & expiry tracking)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    batch_number TEXT UNIQUE NOT NULL,
    initial_quantity INT NOT NULL CHECK (initial_quantity > 0),
    current_quantity INT NOT NULL CHECK (current_quantity >= 0),
    unit_cost NUMERIC(10, 2) DEFAULT 0.00 CHECK (unit_cost >= 0),
    manufactured_date TIMESTAMPTZ DEFAULT NOW(),
    expiry_date TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'near_expiry', 'expired', 'depleted', 'spoiled')),
    prepared_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_batches_product ON public.inventory_batches(product_id);
CREATE INDEX IF NOT EXISTS idx_batches_expiry ON public.inventory_batches(expiry_date);
CREATE INDEX IF NOT EXISTS idx_batches_status ON public.inventory_batches(status);

-- ------------------------------------------------------------------------------
-- 3. INVENTORY LOGS TABLE (Audit trail for intake, POS sales, spoilage)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.inventory_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    batch_id UUID REFERENCES public.inventory_batches(id) ON DELETE SET NULL,
    change_type TEXT NOT NULL CHECK (change_type IN ('batch_intake', 'pos_sale', 'spoilage_waste', 'manual_adjustment', 'expired_disposal')),
    quantity_changed INT NOT NULL, -- positive for intake, negative for sales/spoilage
    previous_stock INT NOT NULL,
    new_stock INT NOT NULL,
    performed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inv_logs_product ON public.inventory_logs(product_id);
CREATE INDEX IF NOT EXISTS idx_inv_logs_created ON public.inventory_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inv_logs_performed_by ON public.inventory_logs(performed_by);


-- ------------------------------------------------------------------------------
-- 4. FUNCTION: SYNC PRODUCT AGGREGATE STOCK QUANTITY FROM ACTIVE BATCHES
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_sync_product_stock(p_product_id UUID)
RETURNS VOID AS $$
DECLARE
    v_total_stock INT;
BEGIN
    SELECT COALESCE(SUM(current_quantity), 0)
    INTO v_total_stock
    FROM public.inventory_batches
    WHERE product_id = p_product_id
      AND status IN ('active', 'near_expiry');

    UPDATE public.products
    SET stock_quantity = v_total_stock,
        is_available = (v_total_stock > 0),
        updated_at = NOW()
    WHERE id = p_product_id;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-sync product stock when batches change
CREATE OR REPLACE FUNCTION public.trg_sync_product_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM public.fn_sync_product_stock(OLD.product_id);
    ELSE
        PERFORM public.fn_sync_product_stock(NEW.product_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_inventory_batches_sync ON public.inventory_batches;
CREATE TRIGGER trg_inventory_batches_sync
AFTER INSERT OR UPDATE OR DELETE ON public.inventory_batches
FOR EACH ROW EXECUTE FUNCTION public.trg_sync_product_stock();

-- ------------------------------------------------------------------------------
-- 5. FUNCTION: UPDATE EXPIRY STATUSES AUTOMATICALLY
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_refresh_batch_expiry_statuses()
RETURNS VOID AS $$
BEGIN
    -- 1. Mark expired batches (expiry_date <= NOW())
    UPDATE public.inventory_batches b
    SET status = 'expired',
        updated_at = NOW()
    FROM public.products p
    WHERE b.product_id = p.id
      AND b.status IN ('active', 'near_expiry')
      AND b.expiry_date <= NOW();

    -- 2. Mark near-expiry packaged goods
    UPDATE public.inventory_batches b
    SET status = 'near_expiry',
        updated_at = NOW()
    FROM public.products p
    WHERE b.product_id = p.id
      AND p.product_type = 'packaged_good'
      AND b.status = 'active'
      AND b.expiry_date > NOW()
      AND b.expiry_date <= (NOW() + (p.warning_threshold_days || ' days')::INTERVAL);

    -- 3. Mark near-expiry ulam/meals
    UPDATE public.inventory_batches b
    SET status = 'near_expiry',
        updated_at = NOW()
    FROM public.products p
    WHERE b.product_id = p.id
      AND p.product_type = 'ulam_meal'
      AND b.status = 'active'
      AND b.expiry_date > NOW()
      AND b.expiry_date <= (NOW() + (p.warning_threshold_hours || ' hours')::INTERVAL);

    -- 4. Mark depleted batches
    UPDATE public.inventory_batches
    SET status = 'depleted',
        updated_at = NOW()
    WHERE current_quantity = 0
      AND status NOT IN ('depleted', 'spoiled', 'expired');
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------------------------
-- 6. FUNCTION: FIFO STOCK DEDUCTION FOR POS CHECKOUT
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_deduct_stock_fifo(
    p_product_id UUID,
    p_quantity_to_deduct INT,
    p_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    batches_used JSONB
) AS $$
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
    -- Refresh batch statuses first to avoid selling expired goods
    PERFORM public.fn_refresh_batch_expiry_statuses();

    SELECT name, stock_quantity INTO v_product_name, v_prev_total_stock
    FROM public.products
    WHERE id = p_product_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'ERR_PRODUCT_NOT_FOUND: Item does not exist', '[]'::JSONB;
        RETURN;
    END IF;

    -- Calculate current active stock
    SELECT COALESCE(SUM(current_quantity), 0)
    INTO v_total_available
    FROM public.inventory_batches
    WHERE product_id = p_product_id
      AND status IN ('active', 'near_expiry')
      AND current_quantity > 0;

    IF v_total_available < p_quantity_to_deduct THEN
        RETURN QUERY SELECT FALSE, 
            'ERR_INSUFFICIENT_STOCK: Requested ' || p_quantity_to_deduct || ' ' || v_product_name || '(s), but only ' || v_total_available || ' non-expired available.',
            '[]'::JSONB;
        RETURN;
    END IF;

    -- Loop through active batches in FIFO order (oldest non-expired first)
    FOR v_batch IN
        SELECT id, batch_number, current_quantity, expiry_date, status
        FROM public.inventory_batches
        WHERE product_id = p_product_id
          AND status IN ('active', 'near_expiry')
          AND current_quantity > 0
        ORDER BY expiry_date ASC, created_at ASC
    LOOP
        EXIT WHEN v_remaining_needed <= 0;

        IF v_batch.current_quantity >= v_remaining_needed THEN
            v_deduct_amount := v_remaining_needed;
        ELSE
            v_deduct_amount := v_batch.current_quantity;
        END IF;

        -- Update batch quantity
        UPDATE public.inventory_batches
        SET current_quantity = current_quantity - v_deduct_amount,
            status = CASE 
                WHEN (current_quantity - v_deduct_amount) = 0 THEN 'depleted'
                ELSE status
            END,
            updated_at = NOW()
        WHERE id = v_batch.id;

        v_remaining_needed := v_remaining_needed - v_deduct_amount;

        v_used_list := v_used_list || jsonb_build_object(
            'batch_id', v_batch.id,
            'batch_number', v_batch.batch_number,
            'quantity_deducted', v_deduct_amount,
            'expiry_date', v_batch.expiry_date
        );
    END LOOP;

    -- Sync overall product stock
    PERFORM public.fn_sync_product_stock(p_product_id);

    SELECT stock_quantity INTO v_new_total_stock FROM public.products WHERE id = p_product_id;

    -- Write Audit Log
    INSERT INTO public.inventory_logs (
        product_id, batch_id, change_type, quantity_changed, 
        previous_stock, new_stock, performed_by, reason
    ) VALUES (
        p_product_id, NULL, 'pos_sale', -p_quantity_to_deduct, 
        v_prev_total_stock, v_new_total_stock, p_user_id, 'POS Sale Deduction (FIFO)'
    );

    RETURN QUERY SELECT TRUE, 'Deduction successful via FIFO order.', v_used_list;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------------------------
-- 7. FUNCTION: LOG SPOILAGE / WASTE FOR ULAM OR EXPIRED GOODS
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_log_spoilage(
    p_batch_id UUID,
    p_quantity_spoiled INT,
    p_user_id UUID DEFAULT NULL,
    p_reason TEXT DEFAULT 'End of day kitchen spoilage'
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
) AS $$
DECLARE
    v_batch RECORD;
    v_product_id UUID;
    v_prev_stock INT;
    v_new_stock INT;
BEGIN
    SELECT * INTO v_batch
    FROM public.inventory_batches
    WHERE id = p_batch_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'ERR_BATCH_NOT_FOUND: Batch ID does not exist.';
        RETURN;
    END IF;

    IF v_batch.current_quantity < p_quantity_spoiled THEN
        RETURN QUERY SELECT FALSE, 'ERR_INVALID_SPOILAGE_QTY: Cannot spoil more than remaining batch balance (' || v_batch.current_quantity || ').';
        RETURN;
    END IF;

    v_product_id := v_batch.product_id;

    SELECT stock_quantity INTO v_prev_stock FROM public.products WHERE id = v_product_id;

    -- Update batch
    UPDATE public.inventory_batches
    SET current_quantity = current_quantity - p_quantity_spoiled,
        status = CASE 
            WHEN (current_quantity - p_quantity_spoiled) = 0 THEN 'spoiled'
            ELSE status
        END,
        updated_at = NOW()
    WHERE id = p_batch_id;

    -- Sync product stock
    PERFORM public.fn_sync_product_stock(v_product_id);
    SELECT stock_quantity INTO v_new_stock FROM public.products WHERE id = v_product_id;

    -- Log
    INSERT INTO public.inventory_logs (
        product_id, batch_id, change_type, quantity_changed,
        previous_stock, new_stock, performed_by, reason
    ) VALUES (
        v_product_id, p_batch_id, 'spoilage_waste', -p_quantity_spoiled,
        v_prev_stock, v_new_stock, p_user_id, p_reason
    );

    RETURN QUERY SELECT TRUE, 'Spoilage logged successfully.';
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------------------------
-- 8. VIEW: UNIFIED INVENTORY AUDIT & EXPIRY MONITOR
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_inventory_batch_monitor AS
SELECT 
    b.id AS batch_id,
    b.batch_number,
    p.id AS product_id,
    p.name AS product_name,
    p.product_type,
    p.unit_name,
    p.price AS selling_price,
    b.unit_cost,
    b.initial_quantity,
    b.current_quantity,
    b.manufactured_date,
    b.expiry_date,
    b.status AS batch_status,
    CASE 
        WHEN b.expiry_date <= NOW() THEN 0
        ELSE EXTRACT(EPOCH FROM (b.expiry_date - NOW())) / 3600.0
    END AS hours_until_expiry,
    CASE 
        WHEN b.expiry_date <= NOW() THEN 0
        ELSE EXTRACT(DAY FROM (b.expiry_date - NOW()))
    END AS days_until_expiry,
    prof.full_name AS prepared_by_name,
    b.notes,
    b.created_at
FROM public.inventory_batches b
JOIN public.products p ON b.product_id = p.id
LEFT JOIN public.profiles prof ON b.prepared_by = prof.id
ORDER BY b.expiry_date ASC;

-- RLS Security Policies for Inventory Batches and Logs
ALTER TABLE public.inventory_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow full access inventory_batches" ON public.inventory_batches FOR ALL USING (true);
CREATE POLICY "Allow full access inventory_logs" ON public.inventory_logs FOR ALL USING (true);
