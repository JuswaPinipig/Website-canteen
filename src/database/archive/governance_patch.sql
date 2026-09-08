-- ==============================================================================
-- NOVALUNCH CANTEEN — DATA GOVERNANCE PATCH
-- Run AFTER supabase_schema.sql and security_hardening.sql
-- Eliminates all hardcoded fallback dependencies by enforcing NOT NULL defaults
-- and adding missing canteen_settings configuration keys.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Enforce NOT NULL on products.calories to eliminate JS magic-number fallbacks
--    (was: || 320, || 420, || 480 in client code)
-- ------------------------------------------------------------------------------
UPDATE public.products SET calories = 0 WHERE calories IS NULL;

ALTER TABLE public.products
    ALTER COLUMN calories SET NOT NULL,
    ALTER COLUMN calories SET DEFAULT 0;

-- Safety trigger: clamp NULL/negative to 0
CREATE OR REPLACE FUNCTION public.fn_guard_product_calories()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.calories IS NULL OR NEW.calories < 0 THEN
        NEW.calories := 0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_products_calories_guard ON public.products;
CREATE TRIGGER trg_products_calories_guard
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.fn_guard_product_calories();

-- ------------------------------------------------------------------------------
-- 2. Add 'balance' mirror column to profiles if missing
--    (Referenced by fn_deduct_wallet_balance in security_hardening.sql)
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS balance NUMERIC(10,2) DEFAULT 0.00;

-- ------------------------------------------------------------------------------
-- 3. Ensure wallets.daily_limit is NOT NULL so JS fallback || 200 never fires
-- ------------------------------------------------------------------------------
UPDATE public.wallets SET daily_limit = 200.00 WHERE daily_limit IS NULL;
ALTER TABLE public.wallets ALTER COLUMN daily_limit SET NOT NULL;
ALTER TABLE public.wallets ALTER COLUMN daily_limit SET DEFAULT 200.00;

-- ------------------------------------------------------------------------------
-- 4. Ensure profiles.credit_limit is NOT NULL so JS fallback || 500 never fires
-- ------------------------------------------------------------------------------
UPDATE public.profiles SET credit_limit = 500.00 WHERE credit_limit IS NULL;
ALTER TABLE public.profiles ALTER COLUMN credit_limit SET NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN credit_limit SET DEFAULT 500.00;

-- Ensure max_daily_calories NOT NULL
UPDATE public.profiles SET max_daily_calories = 1800 WHERE max_daily_calories IS NULL;
ALTER TABLE public.profiles ALTER COLUMN max_daily_calories SET NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN max_daily_calories SET DEFAULT 1800;

-- Ensure weekly_limit NOT NULL
UPDATE public.profiles SET weekly_limit = 1000.00 WHERE weekly_limit IS NULL;
ALTER TABLE public.profiles ALTER COLUMN weekly_limit SET NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN weekly_limit SET DEFAULT 1000.00;

-- ------------------------------------------------------------------------------
-- 5. Add weekly tracking columns to wallets
-- ------------------------------------------------------------------------------
ALTER TABLE public.wallets
    ADD COLUMN IF NOT EXISTS weekly_spent NUMERIC(10,2) DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS last_weekly_reset_date DATE DEFAULT CURRENT_DATE;

-- ------------------------------------------------------------------------------
-- 6. New canteen_settings keys (upsert-safe)
-- ------------------------------------------------------------------------------

-- 6A. Diet filter thresholds (replaces hardcoded <= 300 kcal, >= 20g protein)
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'diet_filter_thresholds',
    '{"low_calorie_max": 300, "high_protein_min": 20}',
    'Calorie and protein thresholds for Student Menu dietary filter buttons'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 6B. Global default daily spending limit (ensure structure)
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'daily_spending_default',
    '{"amount": 200.00}',
    'Default daily wallet spending limit applied to new student accounts at registration'
)
ON CONFLICT (key) DO NOTHING;

-- 6C. Global default health parameters (ensure structure)
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'dietary_defaults',
    '{"default_daily_calories": 1800, "default_allergen_mode": "SOFT_WARN"}',
    'Default health guardrail values applied to new student profiles at registration'
)
ON CONFLICT (key) DO NOTHING;

-- 6D. AI kiosk mode — ensure review_confidence is an explicit editable field
INSERT INTO public.canteen_settings (key, value, description) VALUES
(
    'ai_kiosk_mode',
    '{"enabled": true, "auto_checkout": false, "min_confidence": 0.80, "review_confidence": 0.50}',
    'AI Vision Kiosk settings. min_confidence = auto-accept. review_confidence = flag-for-cashier.'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- ------------------------------------------------------------------------------
-- 7. fn_get_student_weekly_spent — for Parent Portal weekly burn-rate view
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_get_student_weekly_spent(p_user_id UUID)
RETURNS NUMERIC AS $$
    SELECT COALESCE(SUM(ABS(amount)), 0)
    FROM public.wallet_transactions
    WHERE user_id = p_user_id
      AND transaction_type = 'purchase'
      AND created_at >= NOW() - INTERVAL '7 days';
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ------------------------------------------------------------------------------
-- 8. Extend governance_overrides override_type CHECK constraint
-- ------------------------------------------------------------------------------
ALTER TABLE public.governance_overrides
    DROP CONSTRAINT IF EXISTS governance_overrides_override_type_check;

ALTER TABLE public.governance_overrides
    ADD CONSTRAINT governance_overrides_override_type_check
    CHECK (override_type IN (
        'calorie_limit',
        'allergen_block',
        'spending_limit',
        'pay_later_cap',
        'restricted_category',
        'weekly_limit'
    ));

-- ------------------------------------------------------------------------------
-- 9. Index for weekly transaction queries (Parent portal performance)
-- ------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_type_created
    ON public.wallet_transactions (user_id, transaction_type, created_at DESC);

-- ==============================================================================
-- END GOVERNANCE PATCH
-- ==============================================================================
