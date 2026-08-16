-- =============================================================================
-- NovaLunch Database & Edge Governance: Remediation v2 Schema
-- =============================================================================
-- Solves operational gaps:
-- 1. Recipe Bill of Materials (BOM) yield linking for raw ingredient tracking.
-- 2. Granular Category-Level Spending Limits & Parent Dietary/Allergen Locks.
-- 3. SIS / Tuition Fee Ledger Batch Exports with timestamped tray photo hashes.
-- 4. In-App Parent Meal Charge Dispute Tickets & Resolution Audit Logs.
-- 5. Multi-terminal offline token reservations to prevent double-spending.
-- =============================================================================

-- 1. Recipe Bill of Materials (BOM) & Inventory Yields
CREATE TABLE IF NOT EXISTS public.recipe_bom (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    menu_item_id UUID NOT NULL, -- References menu_items(id)
    raw_ingredient_id UUID NOT NULL, -- References raw_ingredients(id)
    quantity_required NUMERIC(10, 3) NOT NULL, -- e.g., 0.180 kg chicken
    unit_of_measure VARCHAR(30) NOT NULL DEFAULT 'kg', -- 'kg', 'g', 'L', 'mL', 'pieces'
    wastage_allowance_pct NUMERIC(5, 2) DEFAULT 0.00, -- e.g., 5.00% prep shrinkage
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Category-Specific Spending Limits
CREATE TABLE IF NOT EXISTS public.category_spending_limits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL, -- References profiles(id)
    category_slug VARCHAR(50) NOT NULL, -- 'meals', 'snacks', 'beverages', 'sweets'
    daily_cap NUMERIC(10, 2) NOT NULL DEFAULT 100.00,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(student_id, category_slug)
);

-- 3. Hard Medical & Dietary Allergen Guardrails
CREATE TABLE IF NOT EXISTS public.student_allergen_guardrails (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL, -- References profiles(id)
    allergen_tag VARCHAR(50) NOT NULL, -- 'peanuts', 'shellfish', 'dairy', 'gluten', 'pork', 'eggs'
    severity_level VARCHAR(20) NOT NULL DEFAULT 'HARD_BLOCK', -- 'HARD_BLOCK', 'WARNING_ONLY'
    notes TEXT,
    set_by_parent_id UUID, -- References profiles(id)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. SIS / Tuition Batch Billing Exports
CREATE TABLE IF NOT EXISTS public.tuition_batch_exports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_reference VARCHAR(64) UNIQUE NOT NULL, -- e.g., 'SIS-TUITION-2026-08-BATCH-01'
    export_format VARCHAR(20) NOT NULL DEFAULT 'CSV', -- 'CSV', 'JSON', 'POWERSCHOOL', 'ELLUCIAN'
    total_records INTEGER NOT NULL DEFAULT 0,
    total_pay_later_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    exported_by_admin UUID, -- References profiles(id)
    export_data_payload JSONB NOT NULL, -- Contains student ID, invoice line items, and tray photo URLs
    status VARCHAR(30) NOT NULL DEFAULT 'EXPORTED', -- 'EXPORTED', 'INGESTED_BY_SIS', 'RECONCILED'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. In-App Parent Meal Charge Dispute Tickets
CREATE TABLE IF NOT EXISTS public.dispute_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_number VARCHAR(50) UNIQUE NOT NULL, -- e.g., 'DISP-2026-0814-001'
    order_id UUID NOT NULL, -- References orders(id)
    student_id UUID NOT NULL, -- References profiles(id)
    parent_id UUID NOT NULL, -- References profiles(id)
    disputed_amount NUMERIC(10, 2) NOT NULL,
    dispute_reason VARCHAR(100) NOT NULL, -- 'MISCLASSIFIED_ITEM', 'UNRECEIVED_ITEM', 'WRONG_PORTION', 'UNAUTHORIZED_PAY_LATER'
    parent_notes TEXT,
    tray_photo_url TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING_REVIEW', -- 'PENDING_REVIEW', 'APPROVED_REFUND', 'REJECTED', 'RESOLVED'
    admin_resolution_notes TEXT,
    resolved_by_admin UUID,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Offline Balance Token Reservations (Double-Spend Mitigation)
CREATE TABLE IF NOT EXISTS public.offline_balance_reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id VARCHAR(50) NOT NULL,
    terminal_id VARCHAR(50) NOT NULL,
    reservation_token VARCHAR(64) UNIQUE NOT NULL,
    reserved_amount NUMERIC(10, 2) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    is_settled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexing for high-velocity query performance
CREATE INDEX IF NOT EXISTS idx_recipe_bom_menu ON public.recipe_bom(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_category_spending_student ON public.category_spending_limits(student_id);
CREATE INDEX IF NOT EXISTS idx_allergen_guardrails_student ON public.student_allergen_guardrails(student_id);
CREATE INDEX IF NOT EXISTS idx_dispute_tickets_order ON public.dispute_tickets(order_id);
CREATE INDEX IF NOT EXISTS idx_dispute_tickets_parent ON public.dispute_tickets(parent_id);
