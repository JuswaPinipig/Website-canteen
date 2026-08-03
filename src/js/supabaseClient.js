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

    async updateProductAiLabel(productId, aiLabel) {
        if (supabase) {
            const { data, error } = await supabase.from('products').update({ ai_label: aiLabel }).eq('id', productId).select();
            if (error) console.warn("Error updating AI label:", error);
            return data;
        }
    },

    // -------------------------------------------------------------------------
    // INVENTORY BATCH & EXPIRY MANAGEMENT
    // -------------------------------------------------------------------------
    async getInventoryBatches() {
        if (!supabase) return await this._fetchREST('inventory_batches?select=*,products(name)');
        try {
            const { data, error } = await supabase.from('v_inventory_batch_monitor').select('*');
            if (!error && data && data.length > 0) return data;
        } catch (e) {
            console.warn("View v_inventory_batch_monitor fallback", e);
        }
        const { data, error } = await supabase.from('inventory_batches').select('*, products(name)');
        if (error) throw error;
        return data || [];
    },

    async addInventoryBatch(batchPayload) {
        if (supabase) {
            const { data, error } = await supabase.from('inventory_batches').insert([batchPayload]).select().single();
            if (error) throw error;
            return data;
        } else {
            const res = await this._postREST('inventory_batches', batchPayload);
            return res[0];
        }
    },

    async deductStockFifo(productId, quantity) {
        if (supabase) {
            try {
                const { data, error } = await supabase.rpc('fn_deduct_stock_fifo', { p_product_id: productId, p_quantity: quantity });
                if (!error) return data;
            } catch (e) {
                console.warn("RPC fn_deduct_stock_fifo error", e);
            }
            // Fallback direct stock update
            const { data: prod } = await supabase.from('products').select('stock_quantity').eq('id', productId).single();
            if (prod) {
                const newStock = Math.max(0, (prod.stock_quantity || 0) - quantity);
                await supabase.from('products').update({ stock_quantity: newStock }).eq('id', productId);
            }
        }
    },

    async logSpoilage(batchId, quantity, reason, loggedBy) {
        if (supabase) {
            try {
                const { data, error } = await supabase.rpc('fn_log_spoilage', {
                    p_batch_id: batchId,
                    p_quantity: quantity,
                    p_reason: reason,
                    p_logged_by: loggedBy
                });
                if (!error) return data;
            } catch (e) {
                console.warn("RPC fn_log_spoilage fallback", e);
            }
            // Fallback direct log insert
            return await supabase.from('inventory_logs').insert([{
                batch_id: batchId,
                action_type: 'SPOILAGE',
                quantity_changed: -quantity,
                reason: reason,
                logged_by: loggedBy
            }]);
        }
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
    // USER REGISTRATION & AUTH PROFILE HELPERS
    // -------------------------------------------------------------------------
    async registerUser(payload) {
        // payload: { email, full_name, first_name, last_name, role, student_id_number, rfid_uid, pin_code, initial_balance, daily_limit }
        const { initial_balance, daily_limit, ...profileFields } = payload;

        let profile;
        if (supabase) {
            const { data, error } = await supabase.from('profiles').insert([profileFields]).select().single();
            if (error) throw error;
            profile = data;
        } else {
            const res = await this._postREST('profiles', profileFields);
            profile = res[0];
        }

        // Initialize wallet for students automatically
        if ((payload.role?.toLowerCase() === 'student') && profile && profile.id) {
            const walletPayload = {
                user_id: profile.id,
                balance: typeof initial_balance === 'number' ? initial_balance : (parseFloat(initial_balance) || 0.00),
                daily_limit: typeof daily_limit === 'number' ? daily_limit : (parseFloat(daily_limit) || 200.00),
                daily_spent: 0.00
            };
            if (supabase) {
                await supabase.from('wallets').insert([walletPayload]);
            } else {
                await this._postREST('wallets', walletPayload);
            }
        }

        // Emit Welcome Notification
        await this.createNotification({
            user_id: profile.id,
            title: "Welcome to NovaLunch!",
            message: `Your ${payload.role.toUpperCase()} account has been created successfully.`,
            type: "account_created"
        });

        return profile;
    },

    // -------------------------------------------------------------------------
    // PARENT-STUDENT LINKING REQUEST WORKFLOW
    // -------------------------------------------------------------------------
    async sendParentLinkRequest(parentId, studentIdentifier) {
        // Search student by student_id_number or email
        let student = null;
        if (supabase) {
            const { data } = await supabase
                .from('profiles')
                .select('*')
                .eq('role', 'student')
                .or(`student_id_number.eq.${studentIdentifier},email.eq.${studentIdentifier}`)
                .maybeSingle();
            student = data;
        } else {
            const res = await this._fetchREST(`profiles?select=*&role=eq.student&or=(student_id_number.eq.${encodeURIComponent(studentIdentifier)},email.eq.${encodeURIComponent(studentIdentifier)})`);
            student = res.length > 0 ? res[0] : null;
        }

        if (!student) {
            throw new Error(`No student found matching ID or Email "${studentIdentifier}". Please verify credentials.`);
        }

        // Check if already linked
        if (supabase) {
            const { data: existingLink } = await supabase.from('parent_student_links').select('*').eq('parent_id', parentId).eq('student_id', student.id).maybeSingle();
            if (existingLink) throw new Error(`Student ${student.full_name} is already linked to your parent account.`);
        }

        // Create pending link request
        const reqPayload = {
            parent_id: parentId,
            student_id: student.id,
            student_id_number: student.student_id_number || studentIdentifier,
            status: 'pending'
        };

        let linkReq;
        if (supabase) {
            const { data, error } = await supabase.from('parent_student_link_requests').insert([reqPayload]).select().single();
            if (error) {
                if (error.code === '23505') throw new Error(`A link request for ${student.full_name} is already pending approval.`);
                throw error;
            }
            linkReq = data;
        } else {
            const res = await this._postREST('parent_student_link_requests', reqPayload);
            linkReq = res[0];
        }

        // Send Notification to Student
        await this.createNotification({
            user_id: student.id,
            title: "Parent Account Link Request",
            message: `A parent account has requested to link to your canteen account. Please review and confirm.`,
            type: "link_request",
            metadata: { request_id: linkReq.id, parent_id: parentId }
        });

        return { request: linkReq, student };
    },

    async getPendingLinkRequests(studentId) {
        if (!supabase) {
            return await this._fetchREST(`parent_student_link_requests?select=*,parent:profiles!parent_id(*)&student_id=eq.${studentId}&status=eq.pending`);
        }
        const { data, error } = await supabase.from('parent_student_link_requests').select('*, parent:profiles!parent_id(*)').eq('student_id', studentId).eq('status', 'pending');
        if (error) throw error;
        return data || [];
    },

    async respondToLinkRequest(requestId, parentId, studentId, accept, studentName = 'Student') {
        const newStatus = accept ? 'accepted' : 'rejected';
        
        if (supabase) {
            const { error } = await supabase.from('parent_student_link_requests').update({ status: newStatus, updated_at: new Date().toISOString() }).eq('id', requestId);
            if (error) throw error;
        }

        if (accept) {
            // Create active link record
            const linkPayload = { parent_id: parentId, student_id: studentId };
            if (supabase) {
                await supabase.from('parent_student_links').insert([linkPayload]);
            } else {
                await this._postREST('parent_student_links', linkPayload);
            }
        }

        // Notify parent
        await this.createNotification({
            user_id: parentId,
            title: accept ? "Link Request Accepted! 🎉" : "Link Request Declined",
            message: accept ? `${studentName} accepted your account link request.` : `${studentName} declined your account link request.`,
            type: accept ? "link_accepted" : "link_rejected"
        });

        return { status: newStatus };
    },

    // -------------------------------------------------------------------------
    // UNIVERSAL NOTIFICATIONS
    // -------------------------------------------------------------------------
    async createNotification({ user_id, title, message, type = 'system', metadata = null }) {
        const notifPayload = { user_id, title, message, type, is_read: false, metadata };
        if (supabase) {
            const { data, error } = await supabase.from('notifications').insert([notifPayload]).select();
            if (error) console.warn("Error creating notification:", error);
            return data;
        } else {
            return await this._postREST('notifications', notifPayload);
        }
    },

    async getNotifications(userId) {
        if (!supabase) return await this._fetchREST(`notifications?select=*&user_id=eq.${userId}&order=created_at.desc`);
        const { data, error } = await supabase.from('notifications').select('*').eq('user_id', userId).order('created_at', { ascending: false });
        if (error) throw error;
        return data || [];
    },

    async markNotificationRead(notificationId) {
        if (supabase) {
            await supabase.from('notifications').update({ is_read: true }).eq('id', notificationId);
        }
    },

    async markAllNotificationsRead(userId) {
        if (supabase) {
            await supabase.from('notifications').update({ is_read: true }).eq('user_id', userId);
        }
    },

    // -------------------------------------------------------------------------
    // REST FALLBACK UTILITIES
    // -------------------------------------------------------------------------
    async _fetchREST(endpoint) {
        try {
            const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
                headers: {
                    "apikey": SUPABASE_ANON_KEY,
                    "Authorization": `Bearer ${SUPABASE_ANON_KEY}`
                }
            });
            if (!res.ok) {
                const errBody = await res.json().catch(() => ({ message: res.statusText }));
                throw new Error(errBody.message || `Database query failed (${res.status})`);
            }
            return await res.json();
        } catch(err) {
            console.warn(`[CanteenDB REST Fetch Error] ${endpoint}:`, err);
            throw err;
        }
    },

    async _postREST(endpoint, body) {
        try {
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
            if (!res.ok) {
                const errBody = await res.json().catch(() => ({ message: res.statusText }));
                throw new Error(errBody.message || `Database save failed (${res.status})`);
            }
            return await res.json();
        } catch(err) {
            console.warn(`[CanteenDB REST Post Error] ${endpoint}:`, err);
            throw err;
        }
    }
};

// Export to window scope for traditional script tagging
if (typeof window !== 'undefined') {
    window.SUPABASE_URL = SUPABASE_URL;
    window.SUPABASE_ANON_KEY = SUPABASE_ANON_KEY;
    window.CanteenDB = CanteenDB;
}
