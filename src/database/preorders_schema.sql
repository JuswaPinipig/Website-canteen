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
    status TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending', 'Preparing', 'Ready', 'Claimed', 'Completed', 'Archived', 'Cancelled')),
    is_archived BOOLEAN DEFAULT FALSE,
    archived_at TIMESTAMPTZ,
    order_number TEXT,
    refunded_amount NUMERIC(10, 2) DEFAULT 0.00,
    refund_note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Migration safety for existing tables
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'preorders' AND column_name = 'is_archived') THEN
        ALTER TABLE public.preorders ADD COLUMN is_archived BOOLEAN DEFAULT FALSE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'preorders' AND column_name = 'archived_at') THEN
        ALTER TABLE public.preorders ADD COLUMN archived_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'preorders' AND column_name = 'order_number') THEN
        ALTER TABLE public.preorders ADD COLUMN order_number TEXT;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_preorders_student ON public.preorders(student_id);
CREATE INDEX IF NOT EXISTS idx_preorders_status ON public.preorders(status);
CREATE INDEX IF NOT EXISTS idx_preorders_token ON public.preorders(token);
CREATE INDEX IF NOT EXISTS idx_preorders_archived ON public.preorders(is_archived);
CREATE INDEX IF NOT EXISTS idx_preorders_student_archived ON public.preorders(student_id, is_archived);

-- Enable RLS
ALTER TABLE public.preorders ENABLE ROW LEVEL SECURITY;

-- Allow read/write for canteen operations
CREATE POLICY "Allow public read preorders" ON public.preorders FOR SELECT USING (true);
CREATE POLICY "Allow public insert preorders" ON public.preorders FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update preorders" ON public.preorders FOR UPDATE USING (true);
CREATE POLICY "Allow public delete preorders" ON public.preorders FOR DELETE USING (true);

