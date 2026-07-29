-- ==============================================================================
-- CANTEEN POS & RFID SYSTEM - COMPLETE DUMMY DATA SEED SCRIPT
-- Execute this SQL in your Supabase SQL Editor (https://supabase.com/dashboard)
-- ==============================================================================

-- 1. SEED PROFILES (Users: Students, Parents, Cashiers, Admins)
INSERT INTO public.profiles (id, email, full_name, role, student_id_number, rfid_uid, status) VALUES
('b1010000-0000-0000-0000-000000000101', 'juan.delacruz@sjc.edu.ph', 'Juan Dela Cruz', 'student', '2023-01900', '9A-4F-21-C8', 'active'),
('b1020000-0000-0000-0000-000000000102', 'sophia.delacruz@sjc.edu.ph', 'Sophia Dela Cruz', 'student', '2023-01988', '7B-3E-11-F4', 'active'),
('b1030000-0000-0000-0000-000000000103', 'mark.santos@sjc.edu.ph', 'Mark Anthony Santos', 'student', '2023-02104', '5C-2A-88-D1', 'active'),
('b1040000-0000-0000-0000-000000000104', 'beatriz.ramos@sjc.edu.ph', 'Beatriz Ramos', 'student', '2023-03011', '3D-11-99-B0', 'active'),
('b1050000-0000-0000-0000-000000000105', 'gabriel.santos@sjc.edu.ph', 'Gabriel Santos', 'student', '2023-04910', '4C-88-12-F9', 'active'),
('b2010000-0000-0000-0000-000000000201', 'maria.delacruz@gmail.com', 'Maria Santos Dela Cruz', 'parent', NULL, NULL, 'active'),
('b2020000-0000-0000-0000-000000000202', 'carlos.delacruz@gmail.com', 'Carlos Dela Cruz', 'parent', NULL, NULL, 'active'),
('b3010000-0000-0000-0000-000000000301', 'cashier1@sjc.edu.ph', 'Elena Rostata (POS #01)', 'cashier', NULL, NULL, 'active'),
('b4010000-0000-0000-0000-000000000401', 'admin@sjc.edu.ph', 'System Administrator', 'admin', NULL, NULL, 'active')
ON CONFLICT (id) DO UPDATE SET
  full_name = EXCLUDED.full_name,
  rfid_uid = EXCLUDED.rfid_uid,
  status = EXCLUDED.status;

-- 2. SEED WALLETS (Student RFID Balances & Daily Caps)
INSERT INTO public.wallets (user_id, balance, daily_limit, daily_spent) VALUES
('b1010000-0000-0000-0000-000000000101', 350.00, 200.00, 75.00),
('b1020000-0000-0000-0000-000000000102', 420.00, 250.00, 0.00),
('b1030000-0000-0000-0000-000000000103', 85.00, 150.00, 45.00),
('b1040000-0000-0000-0000-000000000104', 120.00, 200.00, 0.00),
('b1050000-0000-0000-0000-000000000105', 500.00, 300.00, 0.00)
ON CONFLICT (user_id) DO UPDATE SET
  balance = EXCLUDED.balance,
  daily_limit = EXCLUDED.daily_limit;

-- 3. SEED PARENT-STUDENT LINKS
INSERT INTO public.parent_student_links (parent_id, student_id) VALUES
('b2010000-0000-0000-0000-000000000201', 'b1010000-0000-0000-0000-000000000101'),
('b2020000-0000-0000-0000-000000000202', 'b1020000-0000-0000-0000-000000000102')
ON CONFLICT DO NOTHING;

-- 4. SEED PRODUCTS (Canteen Menu Items with Images & AI Vision Labels)
INSERT INTO public.products (id, category_id, name, description, price, cost_price, stock_quantity, ai_label, barcode, image_url, is_available) VALUES
('a1111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Classic Cheeseburger', 'Grilled Beef Patty & Cheddar Cheese', 75.00, 45.00, 50, 'burger', '480000000001', 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=400&q=80', true),
('a2222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Crispy Chicken Rice Bowl', 'Plated Fried Chicken & Rice w/ Gravy', 85.00, 50.00, 60, 'fried_chicken', '480000000002', 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=400&q=80', true),
('a3333333-3333-3333-3333-333333333333', '33333333-3333-3333-3333-333333333333', 'Ham & Cheese Sandwich', 'Toasted Whole Wheat Sandwich', 45.00, 25.00, 40, 'sandwich', '480000000003', 'https://images.unsplash.com/photo-1528735602780-2552fd46c7af?auto=format&fit=crop&w=400&q=80', true),
('a4444444-4444-4444-4444-444444444444', '22222222-2222-2222-2222-222222222222', 'Mineral Water (500ml)', 'Chilled Purified Drinking Water', 20.00, 10.00, 150, 'water_bottle', '480000000004', 'https://images.unsplash.com/photo-1548839140-29a749e1cf4e?auto=format&fit=crop&w=400&q=80', true),
('a5555555-5555-5555-5555-555555555555', '22222222-2222-2222-2222-222222222222', 'Iced Fruit Juice (350ml)', 'Fresh Juice Cup', 30.00, 15.00, 80, 'juice_box', '480000000005', 'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=400&q=80', true),
('a6666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', 'Fresh Red Apple', 'Organic Crisp Whole Apple', 25.00, 15.00, 40, 'apple', '480000000006', 'https://images.unsplash.com/photo-1560806887-1e4cd0b6cbd6?auto=format&fit=crop&w=400&q=80', true),
('a7777777-7777-7777-7777-777777777777', '11111111-1111-1111-1111-111111111111', 'Beef Pares w/ Garlic Rice', 'Slow-cooked Tender Beef', 90.00, 55.00, 25, 'beef_pares', '480000000007', 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=400&q=80', true),
('a8888888-8888-8888-8888-888888888888', '33333333-3333-3333-3333-333333333333', 'Choco Chip Cookie', 'Freshly Baked Chocolate Cookie', 18.00, 9.00, 90, 'cookie', '480000000008', 'https://images.unsplash.com/photo-1499636136210-6f4ee915583e?auto=format&fit=crop&w=400&q=80', true),
('a9999999-9999-9999-9999-999999999999', '11111111-1111-1111-1111-111111111111', 'Spaghetti Bolognese', 'Sweet-style Pinoy Pasta', 65.00, 35.00, 30, 'spaghetti', '480000000009', 'https://images.unsplash.com/photo-1551183053-bf91a1d81141?auto=format&fit=crop&w=400&q=80', true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  price = EXCLUDED.price,
  image_url = EXCLUDED.image_url,
  is_available = EXCLUDED.is_available;

-- 5. SEED ORDERS
INSERT INTO public.orders (id, order_number, user_id, cashier_id, total_amount, discount_amount, final_amount, payment_method, payment_status, order_source, order_status) VALUES
('c1010000-0000-0000-0000-000000000101', 'ORD-2026-9001', 'b1010000-0000-0000-0000-000000000101', 'b3010000-0000-0000-0000-000000000301', 95.00, 0.00, 95.00, 'rfid', 'paid', 'cashier_pos', 'completed'),
('c1020000-0000-0000-0000-000000000102', 'ORD-2026-9002', 'b1020000-0000-0000-0000-000000000102', 'b3010000-0000-0000-0000-000000000301', 85.00, 0.00, 85.00, 'rfid', 'paid', 'ai_kiosk', 'completed')
ON CONFLICT (id) DO NOTHING;

-- Done seeding database!
