-- ==============================================================================
-- NOVALUNCH CANTEEN POS & SYSTEM — OPERATIONAL REMEDIATION V3 MIGRATION PATCH
-- ==============================================================================
-- Project: NovaLunch (Saint Joseph College Canteen System)
-- Purpose:
--   1. Single-call Atomic Multi-Item FIFO Stock Deduction RPC (`fn_deduct_cart_stock_fifo`)
--   2. Schema reconciliation for `meal_disputes` & `topup_requests`
--   3. Unique reference number enforcement for GCash/Maya top-up submissions
--   4. Tokenless Pre-order status updates & RFID handover support
-- ==============================================================================

-- 1. ATOMIC CART FIFO STOCK DEDUCTION FUNCTION
-- Processes all cart line items in a single ACID transaction with row-level locking.
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
        RETURN jsonb_build_object('success', true, 'message', 'No items to deduct', 'items', '[]'::jsonb);
    END IF;

    -- Loop through each item in the cart
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_prod_id := (v_item->>'id')::UUID;
        v_qty_needed := COALESCE((v_item->>'qty')::INT, (v_item->>'quantity')::INT, 1);

        IF v_prod_id IS NOT NULL AND v_qty_needed > 0 THEN
            -- Lock and fetch product record
            SELECT stock INTO v_current_stock
            FROM public.products
            WHERE id = v_prod_id
            FOR UPDATE;

            IF FOUND THEN
                -- Deduct master product stock
                UPDATE public.products
                SET stock = GREATEST(0, stock - v_qty_needed),
                    updated_at = NOW()
                WHERE id = v_prod_id;

                -- Deduct inventory batches in FIFO order by expiration_date
                v_qty_to_deduct := v_qty_needed;
                FOR v_batch IN
                    SELECT id, quantity_remaining, status
                    FROM public.inventory_batches
                    WHERE product_id = v_prod_id
                      AND quantity_remaining > 0
                      AND status != 'DEPLETED'
                    ORDER BY expiration_date ASC, created_at ASC
                    FOR UPDATE
                LOOP
                    EXIT WHEN v_qty_to_deduct <= 0;

                    IF v_batch.quantity_remaining <= v_qty_to_deduct THEN
                        v_qty_to_deduct := v_qty_to_deduct - v_batch.quantity_remaining;
                        UPDATE public.inventory_batches
                        SET quantity_remaining = 0,
                            status = 'DEPLETED',
                            updated_at = NOW()
                        WHERE id = v_batch.id;
                    ELSE
                        v_rem_in_batch := v_batch.quantity_remaining - v_qty_to_deduct;
                        v_qty_to_deduct := 0;
                        UPDATE public.inventory_batches
                        SET quantity_remaining = v_rem_in_batch,
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

-- 2. SCHEMA RECONCILIATION FOR MEAL DISPUTES
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS photo_url TEXT;
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS details TEXT;
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS admin_notes TEXT;
ALTER TABLE public.meal_disputes ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

-- 3. SCHEMA RECONCILIATION FOR TOPUP REQUESTS
ALTER TABLE public.topup_requests ADD COLUMN IF NOT EXISTS parent_name TEXT;
ALTER TABLE public.topup_requests ADD COLUMN IF NOT EXISTS submitter_role TEXT DEFAULT 'student';
ALTER TABLE public.topup_requests ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;
ALTER TABLE public.topup_requests ADD COLUMN IF NOT EXISTS receipt_img TEXT;

-- 4. UNIQUE INDEX ON GCASH/MAYA REFERENCE NUMBER (PREVENTS DUPLICATE SUBMISSIONS)
CREATE UNIQUE INDEX IF NOT EXISTS uq_topup_ref_no 
ON public.topup_requests(reference_number) 
WHERE status != 'REJECTED' AND status != 'Rejected';

-- 5. ATOMIC PRE-ORDER HANDOVER RPC (TOKENLESS RFID CONFIRMATION)
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
