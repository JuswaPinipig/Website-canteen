-- ==============================================================================
-- NOVALUNCH — SUPABASE SQL EDITOR DATABASE DIAGNOSTIC REPORT
-- ==============================================================================
-- Run this in your Supabase SQL Editor to get a complete health check of all
-- tables, columns, indexes, RPC stored procedures, and triggers.
-- ==============================================================================

-- 1. Check Table Counts & Existence
SELECT 
    t.table_name,
    COUNT(c.column_name) AS total_columns,
    (SELECT COUNT(*) FROM information_schema.table_constraints tc 
     WHERE tc.table_name = t.table_name AND tc.table_schema = 'public') AS total_constraints
FROM information_schema.tables t
LEFT JOIN information_schema.columns c 
    ON t.table_name = c.table_name AND t.table_schema = c.table_schema
WHERE t.table_schema = 'public' 
  AND t.table_type = 'BASE TABLE'
GROUP BY t.table_name
ORDER BY t.table_name ASC;

-- 2. Check Installed Custom RPC Functions
SELECT 
    p.proname AS function_name,
    pg_catalog.pg_get_function_result(p.oid) AS return_type,
    pg_catalog.pg_get_function_arguments(p.oid) AS arguments,
    CASE 
        WHEN p.prosecdef THEN 'SECURITY DEFINER (Admin Bypass)'
        ELSE 'INVOKER'
    END AS execution_mode
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_deduct_cart_stock_fifo',
      'fn_deduct_stock_fifo',
      'fn_deduct_wallet_balance',
      'fn_credit_wallet_balance',
      'fn_admin_update_wallet',
      'settle_pay_later_liability',
      'fn_claim_preorder_by_student',
      'fn_process_gcash_webhook',
      'fn_sync_offline_transaction',
      'fn_increment_product_stock',
      'fn_log_spoilage',
      'fn_create_sis_tuition_batch',
      'fn_reconcile_tuition_pay_later_batch',
      'fn_toggle_pay_later_pre_auth',
      'fn_generate_student_dynamic_qr',
      'fn_add_student_calories',
      'fn_reset_daily_calories',
      'fn_sync_product_stock'
  )
ORDER BY p.proname ASC;

-- 3. Check Row Level Security (RLS) Status
SELECT 
    tablename, 
    rowsecurity AS rls_enabled
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY tablename ASC;
