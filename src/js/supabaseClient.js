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
    Validators: {
        isValidEmail(email) {
            if (!email || typeof email !== 'string') return false;
            return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
        },
        isValidPhone(phone) {
            if (!phone) return true;
            return /^(09|\+639)\d{9}$|^0\d{9,10}$/.test(phone.trim());
        },
        isValidStudentId(id) {
            if (!id || typeof id !== 'string') return false;
            return id.trim().length >= 3 && id.trim().length <= 30;
        },
        isValidRfidHex(rfid) {
            if (!rfid) return true;
            return /^[A-Fa-f0-9\-\:]{4,32}$/.test(rfid.trim());
        }
    },

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
                const { data: prod, error: prodErr } = await supabase.from('products').select('stock_quantity').eq('id', productId).single();
                if (prodErr || !prod) {
                    throw new Error(`Product ${productId} not found for inventory deduction.`);
                }
                const currentStock = prod.stock_quantity || 0;
                if (currentStock < quantity) {
                    throw new Error(`Insufficient stock for product ${productId}. Requested: ${quantity}, Available: ${currentStock}`);
                }
                const newStock = Math.max(0, currentStock - quantity);
                await supabase.from('products').update({ stock_quantity: newStock }).eq('id', productId);

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
                console.error("Fallback direct stock update error:", fallbackErr);
                throw fallbackErr;
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
            // Fallback direct log insert & batch/stock adjustment
            const { data: batch } = await supabase.from('inventory_batches').select('*').eq('id', batchId).single();
            if (batch) {
                const newQty = Math.max(0, (batch.quantity_remaining || 0) - quantity);
                const newStatus = newQty === 0 ? 'DEPLETED' : batch.status;
                await supabase.from('inventory_batches').update({ quantity_remaining: newQty, status: newStatus }).eq('id', batchId);
                
                if (batch.product_id) {
                    const { data: prod } = await supabase.from('products').select('stock_quantity').eq('id', batch.product_id).single();
                    if (prod) {
                        const newProdStock = Math.max(0, (prod.stock_quantity || 0) - quantity);
                        await supabase.from('products').update({ stock_quantity: newProdStock }).eq('id', batch.product_id);
                    }
                }
            }

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
            const { error: wErr } = await supabase.from('wallets').update({ balance: cleanBalance, updated_at: new Date().toISOString() }).eq('user_id', userId);
            if (wErr) {
                console.error("Failed to update wallet balance in Supabase:", wErr);
                throw new Error(`Database error updating wallet balance: ${wErr.message}`);
            }
            const { error: pErr } = await supabase.from('profiles').update({ balance: cleanBalance, updated_at: new Date().toISOString() }).eq('id', userId);
            if (pErr) {
                console.error("Failed to update profile balance in Supabase:", pErr);
                throw new Error(`Database error updating profile balance: ${pErr.message}`);
            }
        } else {
            const res1 = await fetch(`${SUPABASE_URL}/rest/v1/wallets?user_id=eq.${userId}`, {
                method: 'PATCH',
                headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                body: JSON.stringify({ balance: cleanBalance })
            });
            if (!res1.ok) {
                throw new Error(`REST API error updating wallet balance (Status ${res1.status})`);
            }
            const res2 = await fetch(`${SUPABASE_URL}/rest/v1/profiles?id=eq.${userId}`, {
                method: 'PATCH',
                headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                body: JSON.stringify({ balance: cleanBalance })
            });
            if (!res2.ok) {
                throw new Error(`REST API error updating profile balance (Status ${res2.status})`);
            }
        }
        return cleanBalance;
    },

    async updateStudentCreditLiability(userId, newLiability) {
        const cleanLiability = Math.max(0, parseFloat(newLiability) || 0);
        if (supabase) {
            const { error: wErr } = await supabase.from('wallets').update({ credit_liability: cleanLiability, updated_at: new Date().toISOString() }).eq('user_id', userId);
            if (wErr) {
                console.error("Failed to update wallet liability in Supabase:", wErr);
                throw new Error(`Database error updating wallet liability: ${wErr.message}`);
            }
            const { error: pErr } = await supabase.from('profiles').update({ credit_liability: cleanLiability }).eq('id', userId);
            if (pErr) {
                console.error("Failed to update profile liability in Supabase:", pErr);
                throw new Error(`Database error updating profile liability: ${pErr.message}`);
            }
        } else {
            const res = await fetch(`${SUPABASE_URL}/rest/v1/wallets?user_id=eq.${userId}`, {
                method: 'PATCH',
                headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                body: JSON.stringify({ credit_liability: cleanLiability })
            });
            if (!res.ok) {
                throw new Error(`REST API error updating wallet liability (Status ${res.status})`);
            }
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
                if (itemsErr) {
                    console.error("Error inserting order items:", itemsErr);
                    throw new Error(`Failed to save order line items: ${itemsErr.message}`);
                }
            } else {
                await this._postREST('order_items', formattedItems);
            }
        }

        return order;
    },

    async updateOrderStatus(orderId, status, currentStatus = null) {
        const cleanStatus = String(status || '').toLowerCase().trim();
        const ALLOWED_TRANSITIONS = {
            'pending': ['preparing', 'cancelled', 'completed'],
            'preparing': ['ready', 'cancelled', 'completed'],
            'ready': ['claimed', 'completed'],
            'claimed': [],
            'completed': [],
            'cancelled': []
        };

        if (currentStatus) {
            const cleanCurrent = String(currentStatus).toLowerCase().trim();
            const allowedNext = ALLOWED_TRANSITIONS[cleanCurrent];
            if (allowedNext && !allowedNext.includes(cleanStatus)) {
                throw new Error(`Invalid state transition: Cannot change order status from '${currentStatus}' to '${status}'.`);
            }
        }

        if (supabase) {
            const { data, error } = await supabase.from('orders').update({ order_status: cleanStatus, updated_at: new Date().toISOString() }).or(`id.eq.${orderId},order_number.eq.${orderId}`).select();
            if (error) {
                console.error(`[CanteenDB Error] Failed to update status for order ${orderId}:`, error);
                throw new Error(`Database operation failed: ${error.message}`);
            }
            return data;
        } else {
            const res = await fetch(`${SUPABASE_URL}/rest/v1/orders?or=(id.eq.${orderId},order_number.eq.${orderId})`, {
                method: 'PATCH',
                headers: { 
                    "apikey": SUPABASE_ANON_KEY, 
                    "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, 
                    "Content-Type": "application/json" 
                },
                body: JSON.stringify({ order_status: cleanStatus, updated_at: new Date().toISOString() })
            });
            if (!res.ok) {
                const errBody = await res.json().catch(() => ({ message: res.statusText }));
                throw new Error(`REST API update failed (Status ${res.status}): ${errBody.message}`);
            }
            return await res.json();
        }
    },

    async updateKdsOrderStatus(orderId, status) {
        if (supabase) {
            const { data, error } = await supabase.from('kds_tickets').update({ status, updated_at: new Date().toISOString() }).eq('id', orderId).select();
            if (error) console.warn("Error updating KDS status in Supabase:", error);
            return data;
        }
    },

    async deductInventory(orderItems) {
        if (!orderItems || !orderItems.length) return;
        for (const item of orderItems) {
            if (item.id || item.product_id) {
                await this.deductStockFifo(item.id || item.product_id, item.qty || item.quantity || 1);
            }
        }
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
        // payload: { email, full_name, first_name, last_name, role, student_id_number, rfid_uid, pin_code, initial_balance, daily_limit, password }
        if (payload.email && !this.Validators.isValidEmail(payload.email)) {
            throw new Error("Invalid email address format. Please enter a valid email address (e.g. user@example.com).");
        }
        if (payload.role?.toLowerCase() === 'student' && payload.student_id_number && !this.Validators.isValidStudentId(payload.student_id_number)) {
            throw new Error("Invalid Student ID format. Student ID must be between 3 and 30 characters.");
        }
        if (payload.phone && !this.Validators.isValidPhone(payload.phone)) {
            throw new Error("Invalid phone number format. Please provide a valid mobile number.");
        }

        const { initial_balance, daily_limit, first_name, last_name, password, tempPassword, ...profileFields } = payload;

        if (!profileFields.full_name && (first_name || last_name)) {
            profileFields.full_name = `${first_name || ''} ${last_name || ''}`.trim();
        }

        const authPass = password || tempPassword || 'SJC#2026!';

        // Create Supabase Auth account if online
        if (supabase && profileFields.email) {
            try {
                const { data: authData, error: authError } = await supabase.auth.signUp({
                    email: profileFields.email,
                    password: authPass,
                    options: {
                        data: {
                            full_name: profileFields.full_name,
                            role: profileFields.role || 'student'
                        }
                    }
                });
                if (authError) {
                    console.warn("Supabase Auth signUp note:", authError.message);
                } else if (authData?.user?.id) {
                    profileFields.id = authData.user.id;
                }
            } catch(aErr) {
                console.warn("Supabase Auth sign up exception:", aErr);
            }
        }

        let profile;
        if (supabase) {
            const { data, error } = await supabase.from('profiles').insert([profileFields]).select().single();
            if (error) {
                console.error("Supabase profile registration error:", error);
                throw new Error(error.message || `Database error creating account for ${profileFields.email}`);
            }
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
                await supabase.from('wallets').insert([walletPayload]).catch(wErr => console.warn("Wallet init warning:", wErr));
            } else {
                await this._postREST('wallets', walletPayload).catch(wErr => console.warn("REST Wallet init warning:", wErr));
            }
        }

        // Emit Welcome Notification
        await this.createNotification({
            user_id: profile.id,
            title: "Welcome to NovaLunch!",
            message: `Your ${(payload.role || 'user').toUpperCase()} account has been created successfully.`,
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
        const { balance, daily_limit, credit_liability, dailyCap, creditLimit, first_name, last_name, firstName, lastName, ...profileFields } = updatePayload;
        
        let updatedProfile = null;
        if (supabase) {
            const { data, error } = await supabase.from('profiles').update(profileFields).eq('id', userId).select().single();
            if (error) {
                console.error("Supabase profile update error:", error);
                throw new Error(error.message || `Database error updating profile`);
            }
            updatedProfile = data;
        } else {
            const res = await this._patchREST(`profiles?id=eq.${userId}`, profileFields);
            updatedProfile = res[0];
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

    async unarchiveUser(userId) {
        return await this.updateUser(userId, { status: 'active' });
    },

    async archiveProduct(prodId) {
        return await this.updateProduct(prodId, { is_available: false, status: 'archived' });
    },

    async unarchiveProduct(prodId) {
        return await this.updateProduct(prodId, { is_available: true, status: 'active' });
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
        const cleanIdentifier = String(studentIdentifier || '').trim();
        if (!cleanIdentifier) {
            throw new Error("Student Identifier cannot be empty. Please enter a valid Student ID or Email.");
        }
        // Search student by student_id_number, email, or id
        let student = null;
        if (supabase) {
            const { data } = await supabase
                .from('profiles')
                .select('*')
                .eq('role', 'student')
                .or(`student_id_number.eq.${cleanIdentifier},email.eq.${cleanIdentifier},id.eq.${cleanIdentifier}`)
                .maybeSingle();
            student = data;
        } else {
            const res = await this._fetchREST(`profiles?select=*&role=eq.student&or=(student_id_number.eq.${encodeURIComponent(cleanIdentifier)},email.eq.${encodeURIComponent(cleanIdentifier)},id.eq.${encodeURIComponent(cleanIdentifier)})`);
            student = res.length > 0 ? res[0] : null;
        }

        if (!student) {
            throw new Error(`No student found matching ID or Email "${cleanIdentifier}". Please verify credentials.`);
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
                console.error("[CanteenDB Critical Error] Failed to persist pre-order in Supabase:", error);
                throw new Error(`Database error saving pre-order: ${error.message}`);
            }
            return data;
        } else {
            const res = await this._postREST('preorders', payload);
            if (!res || !res.length) {
                throw new Error("Failed to persist pre-order via REST API.");
            }
            return res[0];
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
                console.error("[CanteenDB Critical Error] Failed to submit GCash reload request:", error);
                throw new Error(`Database error submitting top-up request: ${error.message}`);
            }
            return data;
        } else {
            const res = await this._postREST('topup_requests', payload);
            if (!res || !res.length) {
                throw new Error("Failed to submit top-up request via REST API.");
            }
            return res[0];
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
    // SYSTEM SETTINGS & GOVERNANCE CONFIGURATION
    // -------------------------------------------------------------------------
    async getSystemSettings() {
        if (!supabase) {
            try { return await this._fetchREST('canteen_settings?select=*'); } catch(e) { return []; }
        }
        const { data, error } = await supabase.from('canteen_settings').select('*');
        if (error) return [];
        return data || [];
    },

    async updateSystemSetting(key, value, description = '') {
        const payload = { key, value, description, updated_at: new Date().toISOString() };
        if (supabase) {
            const { data, error } = await supabase.from('canteen_settings').upsert([payload]).select();
            if (error) console.warn("Error updating system setting:", error);
            return data;
        } else {
            return await this._postREST('canteen_settings', payload);
        }
    },

    // -------------------------------------------------------------------------
    // PRE-ORDER SLOTS MANAGEMENT
    // -------------------------------------------------------------------------
    async getPreorderSlots() {
        if (!supabase) {
            try { return await this._fetchREST('preorder_slots?select=*&order=start_time.asc'); } catch(e) { return []; }
        }
        const { data, error } = await supabase.from('preorder_slots').select('*').order('start_time', { ascending: true });
        if (error) return [];
        return data || [];
    },

    async savePreorderSlot(slotPayload) {
        if (supabase) {
            const { data, error } = await supabase.from('preorder_slots').upsert([slotPayload]).select();
            if (error) throw error;
            return data;
        } else {
            return await this._postREST('preorder_slots', slotPayload);
        }
    },

    // -------------------------------------------------------------------------
    // HARDWARE TOPOLOGY & TERMINAL MAPPINGS
    // -------------------------------------------------------------------------
    async getHardwareMappings() {
        if (!supabase) {
            try { return await this._fetchREST('hardware_mappings?select=*'); } catch(e) { return []; }
        }
        const { data, error } = await supabase.from('hardware_mappings').select('*');
        if (error) return [];
        return data || [];
    },

    async updateHardwareMapping(terminalId, payload) {
        const fullPayload = { terminal_id: terminalId, ...payload, updated_at: new Date().toISOString() };
        if (supabase) {
            const { data, error } = await supabase.from('hardware_mappings').upsert([fullPayload]).select();
            if (error) throw error;
            return data;
        } else {
            return await this._postREST('hardware_mappings', fullPayload);
        }
    },

    // -------------------------------------------------------------------------
    // AUDIT LOGS FOR MANAGER OVERRIDES & POLICY EXCEPTIONS
    // -------------------------------------------------------------------------
    async logAuditEvent(action, actorId, entityType, entityId, details = {}) {
        const auditPayload = {
            actor_id: actorId || null,
            action: action,
            entity_type: entityType,
            entity_id: String(entityId || ''),
            details: details,
            created_at: new Date().toISOString()
        };
        if (supabase) {
            await supabase.from('audit_logs').insert([auditPayload]).catch(e => console.warn("Audit log warning:", e));
        } else {
            await this._postREST('audit_logs', auditPayload).catch(e => console.warn("REST Audit log warning:", e));
        }
    },

    async updateStudentHealthGuardrails(studentId, { max_daily_calories, allergen_restrictions, allergen_mode }) {
        const payload = {};
        if (max_daily_calories !== undefined) payload.max_daily_calories = parseInt(max_daily_calories) || 1800;
        if (allergen_restrictions !== undefined) payload.allergen_restrictions = Array.isArray(allergen_restrictions) ? allergen_restrictions : [];
        if (allergen_mode !== undefined) payload.allergen_mode = allergen_mode;
        return await this.updateUser(studentId, payload);
    },

    async updateStudentFinancialCaps(studentId, { daily_limit, weekly_limit, credit_limit, pay_later_allowance, restricted_categories }) {
        const payload = {};
        if (daily_limit !== undefined) payload.daily_limit = Math.max(0, parseFloat(daily_limit) || 0);
        if (weekly_limit !== undefined) payload.weekly_limit = Math.max(0, parseFloat(weekly_limit) || 0);
        if (credit_limit !== undefined) payload.credit_limit = Math.max(0, parseFloat(credit_limit) || 0);
        if (pay_later_allowance !== undefined) payload.pay_later_allowance = Boolean(pay_later_allowance);
        if (restricted_categories !== undefined) payload.restricted_categories = Array.isArray(restricted_categories) ? restricted_categories : [];
        return await this.updateUser(studentId, payload);
    },

    async logGovernanceOverride(studentId, cashierId, overrideType, reason, approvedByPin = false) {
        const payload = {
            student_id: studentId,
            cashier_id: cashierId || null,
            override_type: overrideType,
            reason: reason,
            approved_by_pin: approvedByPin,
            created_at: new Date().toISOString()
        };
        if (supabase) {
            await supabase.from('governance_overrides').insert([payload]).catch(e => console.warn("Governance override log error:", e));
        } else {
            await this._postREST('governance_overrides', payload).catch(e => console.warn("REST Governance override log error:", e));
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
