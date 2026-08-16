-- ==============================================================================
-- PRE-ORDERS TABLE SCHEMA FOR SUPABASE / POSTGRESQL
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.preorders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    student_name TEXT,
    item_name TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    token TEXT,
    shelf_location TEXT DEFAULT 'Shelf B2',
    session TEXT DEFAULT 'Lunch Break (12:00 PM)',
    status TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending', 'Preparing', 'Ready', 'Claimed', 'Cancelled')),
    refunded_amount NUMERIC(10, 2) DEFAULT 0.00,
    refund_note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_preorders_student ON public.preorders(student_id);
CREATE INDEX IF NOT EXISTS idx_preorders_status ON public.preorders(status);
CREATE INDEX IF NOT EXISTS idx_preorders_token ON public.preorders(token);

-- Enable RLS
ALTER TABLE public.preorders ENABLE ROW LEVEL SECURITY;

-- Allow read/write for canteen operations
CREATE POLICY "Allow public read preorders" ON public.preorders FOR SELECT USING (true);
CREATE POLICY "Allow public insert preorders" ON public.preorders FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update preorders" ON public.preorders FOR UPDATE USING (true);
CREATE POLICY "Allow public delete preorders" ON public.preorders FOR DELETE USING (true);
