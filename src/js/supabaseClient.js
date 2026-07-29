/**
 * Supabase Client Configuration & Helper Utilities
 * Project: Web-based Canteen System (POS, AI Detection, RFID)
 */

const SUPABASE_URL = "https://wtvkmywmlifcsddlgvnn.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_yywY2quhz5k1x6Pu_w6pgQ_e-mBU0q2";

// Initialize Supabase Client instance if window.supabase SDK is loaded
let supabase = null;

if (typeof window !== 'undefined' && window.supabase) {
    supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    console.log("Supabase Client initialized successfully.");
}

/**
 * Canteen API Service Layer
 */
const CanteenDB = {
    // -------------------------------------------------------------------------
    // MENU & PRODUCTS
    // -------------------------------------------------------------------------
    async getCategories() {
        if (!supabase) return await this._fetchREST('menu_categories?select=*&is_active=eq.true&order=sort_order.asc');
        const { data, error } = await supabase.from('menu_categories').select('*').eq('is_active', true).order('sort_order', { ascending: true });
        if (error) throw error;
        return data;
    },

    async getProducts() {
        if (!supabase) return await this._fetchREST('products?select=*,category:menu_categories(name)&is_available=eq.true&order=name.asc');
        const { data, error } = await supabase.from('products').select('*, category:menu_categories(name)').eq('is_available', true).order('name', { ascending: true });
        if (error) throw error;
        return data;
    },

    async getProductByAILabel(label) {
        if (!supabase) return await this._fetchREST(`products?select=*&ai_label=eq.${encodeURIComponent(label)}&is_available=eq.true`);
        const { data, error } = await supabase.from('products').select('*').eq('ai_label', label).eq('is_available', true);
        if (error) throw error;
        return data;
    },

    // -------------------------------------------------------------------------
    // RFID & USER WALLETS
    // -------------------------------------------------------------------------
    async getUserByRFID(rfidUid) {
        if (!supabase) {
            const res = await this._fetchREST(`profiles?select=*,wallets(*)&rfid_uid=eq.${encodeURIComponent(rfidUid)}&status=eq.active`);
            return res.length > 0 ? res[0] : null;
        }
        const { data, error } = await supabase.from('profiles').select('*, wallets(*)').eq('rfid_uid', rfidUid).eq('status', 'active').single();
        if (error) return null;
        return data;
    },

    async getWalletByUserId(userId) {
        if (!supabase) {
            const res = await this._fetchREST(`wallets?select=*&user_id=eq.${userId}`);
            return res.length > 0 ? res[0] : null;
        }
        const { data, error } = await supabase.from('wallets').select('*').eq('user_id', userId).single();
        if (error) throw error;
        return data;
    },

    // -------------------------------------------------------------------------
    // POS TRANSACTIONS & ORDERS
    // -------------------------------------------------------------------------
    async createOrder(orderPayload) {
        // orderPayload: { order_number, user_id, cashier_id, total_amount, discount_amount, final_amount, payment_method, order_source, items: [...] }
        const { items, ...orderHeader } = orderPayload;
        
        let order;
        if (supabase) {
            const { data, error } = await supabase.from('orders').insert([orderHeader]).select().single();
            if (error) throw error;
            order = data;
        } else {
            const res = await this._postREST('orders', orderHeader);
            order = res[0];
        }

        if (items && items.length > 0) {
            const formattedItems = items.map(item => ({
                order_id: order.id,
                product_id: item.product_id,
                product_name: item.product_name,
                unit_price: item.unit_price,
                quantity: item.quantity,
                subtotal: item.unit_price * item.quantity
            }));

            if (supabase) {
                const { error: itemsErr } = await supabase.from('order_items').insert(formattedItems);
                if (itemsErr) console.error("Error inserting order items:", itemsErr);
            } else {
                await this._postREST('order_items', formattedItems);
            }
        }

        return order;
    },

    // -------------------------------------------------------------------------
    // AI CAMERA DETECTION LOGS
    // -------------------------------------------------------------------------
    async logAIDetection(detectionPayload) {
        // payload: { image_url, detected_objects, confidence_score, matched_product_ids, order_id }
        if (supabase) {
            const { data, error } = await supabase.from('ai_detection_logs').insert([detectionPayload]).select();
            if (error) console.warn("Error logging AI detection:", error);
            return data;
        } else {
            return await this._postREST('ai_detection_logs', detectionPayload);
        }
    },

    // -------------------------------------------------------------------------
    // REST FALLBACK UTILITIES
    // -------------------------------------------------------------------------
    async _fetchREST(endpoint) {
        const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
            headers: {
                "apikey": SUPABASE_ANON_KEY,
                "Authorization": `Bearer ${SUPABASE_ANON_KEY}`
            }
        });
        if (!res.ok) throw new Error(`HTTP error! status: ${res.status}`);
        return await res.json();
    },

    async _postREST(endpoint, body) {
        const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
            method: "POST",
            headers: {
                "apikey": SUPABASE_ANON_KEY,
                "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
                "Content-Type": "application/json",
                "Prefer": "return=representation"
            },
            body: JSON.stringify(body)
        });
        if (!res.ok) throw new Error(`HTTP error! status: ${res.status}`);
        return await res.json();
    }
};

// Export to window scope for traditional script tagging
if (typeof window !== 'undefined') {
    window.SUPABASE_URL = SUPABASE_URL;
    window.SUPABASE_ANON_KEY = SUPABASE_ANON_KEY;
    window.CanteenDB = CanteenDB;
}
