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

    async createProduct(productPayload) {
        if (supabase) {
            const { data, error } = await supabase.from('products').insert([productPayload]).select().single();
            if (error) throw error;
            return data;
        } else {
            const res = await this._postREST('products', productPayload);
            return res[0];
        }
    },

    async updateProduct(productId, updatePayload) {
        if (supabase) {
            const { data, error } = await supabase.from('products').update(updatePayload).eq('id', productId).select();
            if (error) {
                console.warn("Error updating product:", error);
                throw error;
            }
            return data;
        } else {
            return await this._patchREST(`products?id=eq.${productId}`, updatePayload);
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
                if (!error && data !== null) return data;
            } catch (e) {
                console.warn("RPC fn_deduct_stock_fifo error", e);
            }
            // Fallback direct stock & batch update
            try {
                const { data: prod } = await supabase.from('products').select('stock_quantity').eq('id', productId).single();
                if (prod) {
                    const newStock = Math.max(0, (prod.stock_quantity || 0) - quantity);
                    await supabase.from('products').update({ stock_quantity: newStock }).eq('id', productId);
                }

                // Fallback batch deduction (FIFO by expiration_date)
                const { data: batches } = await supabase.from('inventory_batches')
                    .select('*')
                    .eq('product_id', productId)
                    .gt('quantity_remaining', 0)
                    .order('expiration_date', { ascending: true });

                if (batches && batches.length > 0) {
                    let qtyToDeduct = quantity;
                    for (const batch of batches) {
                        if (qtyToDeduct <= 0) break;
                        const deductFromThis = Math.min(batch.quantity_remaining, qtyToDeduct);
                        const newRem = batch.quantity_remaining - deductFromThis;
                        const newStatus = newRem === 0 ? 'DEPLETED' : batch.status;
                        await supabase.from('inventory_batches')
                            .update({ quantity_remaining: newRem, status: newStatus })
                            .eq('id', batch.id);
                        qtyToDeduct -= deductFromThis;
                    }
                }
            } catch (fallbackErr) {
                console.warn("Fallback direct stock update warning:", fallbackErr);
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

    async updateStudentBalance(userId, newBalance) {
        const cleanBalance = Math.max(0, parseFloat(newBalance) || 0);
        if (supabase) {
            try {
                await supabase.from('wallets').update({ balance: cleanBalance, updated_at: new Date().toISOString() }).eq('user_id', userId);
            } catch(e) {
                console.warn("Error updating wallets table balance:", e);
            }
            try {
                await supabase.from('profiles').update({ balance: cleanBalance }).eq('id', userId);
            } catch(e) {
                console.warn("Error updating profiles table balance:", e);
            }
        } else {
            try {
                await fetch(`${SUPABASE_URL}/rest/v1/wallets?user_id=eq.${userId}`, {
                    method: 'PATCH',
                    headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                    body: JSON.stringify({ balance: cleanBalance })
                });
            } catch(e) {}
        }
        return cleanBalance;
    },

    async updateStudentCreditLiability(userId, newLiability) {
        const cleanLiability = Math.max(0, parseFloat(newLiability) || 0);
        if (supabase) {
            try {
                await supabase.from('wallets').update({ credit_liability: cleanLiability, updated_at: new Date().toISOString() }).eq('user_id', userId);
            } catch(e) {
                console.warn("Error updating wallets table liability:", e);
            }
            try {
                await supabase.from('profiles').update({ credit_liability: cleanLiability }).eq('id', userId);
            } catch(e) {
                console.warn("Error updating profiles table liability:", e);
            }
        } else {
            try {
                await fetch(`${SUPABASE_URL}/rest/v1/wallets?user_id=eq.${userId}`, {
                    method: 'PATCH',
                    headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                    body: JSON.stringify({ credit_liability: cleanLiability })
                });
            } catch(e) {}
        }
        return cleanLiability;
    },

    async settleStudentDebt(userId, amountPaid, paymentMethod = 'cash', cashierId = null) {
        if (supabase) {
            try {
                const { data, error } = await supabase.rpc('settle_pay_later_liability', {
                    p_user_id: userId,
                    p_amount: amountPaid,
                    p_payment_method: paymentMethod.toLowerCase(),
                    p_cashier_id: cashierId
                });
                if (!error && data) return data;
            } catch(e) {
                console.warn("RPC settle_pay_later_liability fallback", e);
            }
        }
        // Fallback update
        const wallet = await this.getWalletByUserId(userId).catch(() => null);
        const currentDebt = wallet ? (parseFloat(wallet.credit_liability) || 0) : 0;
        const newDebt = Math.max(0, currentDebt - amountPaid);
        await this.updateStudentCreditLiability(userId, newDebt);
        return { success: true, remaining_liability: newDebt };
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

    async getAllUsers() {
        if (!supabase) {
            try {
                return await this._fetchREST('profiles?select=*,wallets(*)&order=created_at.desc');
            } catch (e) { return []; }
        }
        const { data, error } = await supabase.from('profiles').select('*, wallets(*)').order('created_at', { ascending: false });
        if (error) return [];
        return data || [];
    },

    async updateUser(userId, updatePayload) {
        // Separate profile fields from wallet fields
        const { balance, daily_limit, credit_liability, dailyCap, creditLimit, ...profileFields } = updatePayload;
        
        let updatedProfile = null;
        if (supabase) {
            const { data, error } = await supabase.from('profiles').update(profileFields).eq('id', userId).select().single();
            if (error) console.warn("Supabase profile update warning:", error);
            updatedProfile = data;
        } else {
            try {
                const res = await this._patchREST(`profiles?id=eq.${userId}`, profileFields);
                updatedProfile = res[0];
            } catch (e) {
                console.warn("REST profile update warning:", e);
            }
        }

        // Update Wallet fields if balance, daily_limit, or credit_liability is provided
        const cleanBalance = balance !== undefined ? (parseFloat(balance) || 0.0) : undefined;
        const cleanDailyCap = daily_limit !== undefined ? (parseFloat(daily_limit) || 200.0) : (dailyCap !== undefined ? (parseFloat(dailyCap) || 200.0) : undefined);
        const cleanLiability = credit_liability !== undefined ? (parseFloat(credit_liability) || 0.0) : undefined;

        const walletPatch = {};
        if (cleanBalance !== undefined) walletPatch.balance = cleanBalance;
        if (cleanDailyCap !== undefined) walletPatch.daily_limit = cleanDailyCap;
        if (cleanLiability !== undefined) walletPatch.credit_liability = cleanLiability;

        if (Object.keys(walletPatch).length > 0) {
            walletPatch.updated_at = new Date().toISOString();
            if (supabase) {
                await supabase.from('wallets').update(walletPatch).eq('user_id', userId).catch(e => console.warn("Wallet update error:", e));
            } else {
                try {
                    await fetch(`${SUPABASE_URL}/rest/v1/wallets?user_id=eq.${userId}`, {
                        method: 'PATCH',
                        headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                        body: JSON.stringify(walletPatch)
                    });
                } catch (e) {}
            }
        }

        return updatedProfile;
    },

    async archiveUser(userId) {
        return await this.updateUser(userId, { status: 'archived' });
    },

    async updateUserDailyLimit(userId, newLimit) {
        const cleanLimit = Math.max(0, parseFloat(newLimit) || 0);
        return await this.updateUser(userId, { daily_limit: cleanLimit, dailyCap: cleanLimit });
    },

    async updateUserRfid(userId, rfidUid) {
        return await this.updateUser(userId, { rfid_uid: rfidUid });
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
    // PRE-ORDERS & EXPRESS CLAIM TOKENS
    // -------------------------------------------------------------------------
    async createPreorder(payload) {
        // payload: { student_id, item_name, price, token, status, created_at }
        if (supabase) {
            const { data, error } = await supabase.from('preorders').insert([payload]).select().single();
            if (error) {
                console.warn("Preorder Cloud DB insert warning, falling back local:", error);
                return payload;
            }
            return data;
        } else {
            try {
                const res = await this._postREST('preorders', payload);
                return res[0];
            } catch (e) {
                console.warn("Preorder REST API fallback warning:", e);
                return payload;
            }
        }
    },

    async getPreorders(studentId) {
        if (!supabase) {
            try {
                return await this._fetchREST(`preorders?select=*${studentId ? `&student_id=eq.${studentId}` : ''}&order=created_at.desc`);
            } catch (e) { return []; }
        }
        let query = supabase.from('preorders').select('*').order('created_at', { ascending: false });
        if (studentId) query = query.eq('student_id', studentId);
        const { data, error } = await query;
        if (error) return [];
        return data || [];
    },

    async updatePreorderStatus(preorderId, status) {
        if (supabase) {
            await supabase.from('preorders').update({ status, updated_at: new Date().toISOString() }).eq('id', preorderId);
        } else {
            try {
                await fetch(`${SUPABASE_URL}/rest/v1/preorders?id=eq.${preorderId}`, {
                    method: 'PATCH',
                    headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                    body: JSON.stringify({ status })
                });
            } catch(e) {}
        }
    },

    // -------------------------------------------------------------------------
    // GCASH RELOAD QUEUE & TOP-UPS
    // -------------------------------------------------------------------------
    async submitGcashReload(payload) {
        // payload: { id, parent_name, student_name, student_id, amount, date, ref_no, status, receipt_img, submitter_role }
        if (supabase) {
            const { data, error } = await supabase.from('topup_requests').insert([payload]).select().single();
            if (error) {
                console.warn("GCash reload Cloud DB insert warning:", error);
                return payload;
            }
            return data;
        } else {
            try {
                const res = await this._postREST('topup_requests', payload);
                return res[0];
            } catch (e) {
                return payload;
            }
        }
    },

    async getGcashQueue() {
        if (!supabase) {
            try {
                return await this._fetchREST('topup_requests?select=*&order=created_at.desc');
            } catch (e) { return []; }
        }
        const { data, error } = await supabase.from('topup_requests').select('*').order('created_at', { ascending: false });
        if (error) return [];
        return data || [];
    },

    async updateGcashReloadStatus(reloadId, status, adminNote = '') {
        if (supabase) {
            await supabase.from('topup_requests').update({ status, admin_note: adminNote, reviewed_at: new Date().toISOString() }).eq('id', reloadId);
        }
    },

    // -------------------------------------------------------------------------
    // STUDENT ORDERS & E-RECEIPTS
    // -------------------------------------------------------------------------
    async getStudentOrders(studentId) {
        if (!supabase) {
            try {
                return await this._fetchREST(`orders?select=*,order_items(*)&user_id=eq.${studentId}&order=created_at.desc`);
            } catch(e) { return []; }
        }
        const { data, error } = await supabase.from('orders').select('*, order_items(*)').eq('user_id', studentId).order('created_at', { ascending: false });
        if (error) return [];
        return data || [];
    },

    // -------------------------------------------------------------------------
    // SECURITY & RFID PIN CODE
    // -------------------------------------------------------------------------
    async updateStudentPin(userId, pinCode) {
        if (supabase) {
            const { data, error } = await supabase.from('profiles').update({ pin_code: pinCode }).eq('id', userId).select();
            if (error) throw error;
            return data;
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
    },

    async _patchREST(endpoint, body) {
        try {
            const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
                method: "PATCH",
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
                throw new Error(errBody.message || `Database update failed (${res.status})`);
            }
            return await res.json();
        } catch(err) {
            console.warn(`[CanteenDB REST Patch Error] ${endpoint}:`, err);
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
