(function (window) {
    const SUPABASE_URL = "https://wtvkmywmlifcsddlgvnn.supabase.co";
    const SUPABASE_ANON_KEY = "sb_publishable_yywY2quhz5k1x6Pu_w6pgQ_e-mBU0q2";

    // Initialize Supabase Client instance scoped inside IIFE
    let supabase = null;
    if (typeof window !== 'undefined' && window.supabase && typeof window.supabase.createClient === 'function') {
        supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
        console.log("Supabase Client initialized successfully.");
    }

    /**
     * Canteen API Service Layer
     */
    const CanteenDB = {
        // -------------------------------------------------------------------------
        // LOCALSTORAGE PERSISTENCE & OFFLINE CACHE UTILITIES
        // -------------------------------------------------------------------------
        saveLocal(key, value) {
            try {
                if (typeof window !== 'undefined' && window.localStorage) {
                    window.localStorage.setItem(key, JSON.stringify(value));
                }
            } catch (e) {
                console.warn("[CanteenDB LocalStorage Save Warning]", e);
            }
        },

        loadLocal(key, defaultValue = null) {
            try {
                if (typeof window !== 'undefined' && window.localStorage) {
                    const item = window.localStorage.getItem(key);
                    if (item !== null && item !== undefined && item !== "undefined") {
                        return JSON.parse(item);
                    }
                }
            } catch (e) {
                console.warn("[CanteenDB LocalStorage Load Warning]", e);
            }
            return defaultValue;
        },

        removeLocal(key) {
            try {
                if (typeof window !== 'undefined' && window.localStorage) {
                    window.localStorage.removeItem(key);
                }
            } catch (e) { }
        },

        isUUID(str) {
            if (!str || typeof str !== 'string') return false;
            return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(str.trim());
        },

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
            const cached = this.loadLocal('novalunch_products_catalog', null);
            let cloudProducts = [];
            try {
                if (!supabase) {
                    cloudProducts = await this._fetchREST('products?select=*,category:menu_categories(name)&is_available=eq.true&order=name.asc');
                } else {
                    const { data, error } = await supabase.from('products').select('*, category:menu_categories(name)').order('name', { ascending: true });
                    if (!error && data) cloudProducts = data;
                }
            } catch (e) {
                console.warn("Products cloud fetch fallback to cache:", e);
            }

            if (cloudProducts && cloudProducts.length > 0) {
                this.saveLocal('novalunch_products_catalog', cloudProducts);
                return cloudProducts;
            }
            return cached || [];
        },

        async getProductByAILabel(label) {
            if (!supabase) return await this._fetchREST(`products?select=*&ai_label=eq.${encodeURIComponent(label)}&is_available=eq.true`);
            const { data, error } = await supabase.from('products').select('*').eq('ai_label', label).eq('is_available', true);
            if (error) throw error;
            return data;
        },

        async updateProductAiLabel(productId, aiLabel) {
            if (supabase && this.isUUID(productId)) {
                const { data, error } = await supabase.from('products').update({ ai_label: aiLabel }).eq('id', productId).select();
                if (error) throw error;
                return data;
            }
        },

        async createProduct(productPayload) {
            // Sanitize and map UI fields to valid PostgreSQL products schema
            const cleanPayload = {
                name: productPayload.name || 'Menu Item',
                price: parseFloat(productPayload.price) || 0.0,
                cost_price: parseFloat(productPayload.cost_price || productPayload.costPrice) || 0.0,
                stock_quantity: productPayload.stock_quantity !== undefined ? parseInt(productPayload.stock_quantity) : (productPayload.stock !== undefined ? parseInt(productPayload.stock) : 50),
                is_available: productPayload.is_available !== undefined ? Boolean(productPayload.is_available) : (productPayload.available !== undefined ? Boolean(productPayload.available) : true),
                image_url: productPayload.image_url || productPayload.img || null,
                category: productPayload.category || 'Meals & Mains',
                ai_label: productPayload.ai_label || productPayload.aiLabel || null,
                barcode: productPayload.barcode || null,
                description: productPayload.description || null,
                calories: parseInt(productPayload.calories) || 0,
                protein: productPayload.protein || '0g',
                allergens: Array.isArray(productPayload.allergens) ? productPayload.allergens : [],
                status: productPayload.status || 'active',
                updated_at: new Date().toISOString()
            };

            if (productPayload.id && this.isUUID(productPayload.id)) {
                cleanPayload.id = productPayload.id;
            }

            let createdProduct = null;
            if (supabase) {
                try {
                    const { data, error } = await supabase.from('products').insert([cleanPayload]).select().single();
                    if (!error && data) createdProduct = data;
                    else console.warn("Supabase createProduct notice:", error);
                } catch (e) {
                    console.warn("Supabase createProduct exception:", e);
                }
            }

            if (!createdProduct) {
                try {
                    const res = await this._postREST('products', cleanPayload);
                    if (res && res[0]) createdProduct = res[0];
                } catch (e) {
                    // Generate a client UUID for offline resilience
                    createdProduct = {
                        id: cleanPayload.id || (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : 'prod_' + Date.now()),
                        ...cleanPayload,
                        created_at: new Date().toISOString()
                    };
                }
            }

            // Update local cache
            const currentProducts = this.loadLocal('novalunch_products_catalog', []);
            this.saveLocal('novalunch_products_catalog', [createdProduct, ...currentProducts.filter(p => p.id !== createdProduct.id)]);

            return createdProduct;
        },

        async updateProduct(productId, updatePayload) {
            const cleanPayload = {};
            if (updatePayload.name !== undefined) cleanPayload.name = updatePayload.name;
            if (updatePayload.price !== undefined) cleanPayload.price = parseFloat(updatePayload.price) || 0;
            if (updatePayload.cost_price !== undefined || updatePayload.costPrice !== undefined) cleanPayload.cost_price = parseFloat(updatePayload.cost_price || updatePayload.costPrice) || 0;
            
            const stockVal = updatePayload.stock !== undefined ? parseInt(updatePayload.stock) : (updatePayload.stock_quantity !== undefined ? parseInt(updatePayload.stock_quantity) : undefined);
            if (stockVal !== undefined) {
                cleanPayload.stock = stockVal;
                cleanPayload.stock_quantity = stockVal;
            }
            
            const availVal = updatePayload.available !== undefined ? Boolean(updatePayload.available) : (updatePayload.is_available !== undefined ? Boolean(updatePayload.is_available) : undefined);
            if (availVal !== undefined) {
                cleanPayload.available = availVal;
                cleanPayload.is_available = availVal;
            }
            
            const imgVal = updatePayload.img || updatePayload.image_url;
            if (imgVal !== undefined) {
                cleanPayload.img = imgVal;
                cleanPayload.image_url = imgVal;
            }
            
            if (updatePayload.category !== undefined) cleanPayload.category = updatePayload.category;
            if (updatePayload.ai_label !== undefined || updatePayload.aiLabel !== undefined) cleanPayload.ai_label = updatePayload.ai_label || updatePayload.aiLabel;
            if (updatePayload.calories !== undefined) cleanPayload.calories = parseInt(updatePayload.calories) || 0;
            if (updatePayload.protein !== undefined) cleanPayload.protein = updatePayload.protein;
            if (updatePayload.allergens !== undefined) cleanPayload.allergens = Array.isArray(updatePayload.allergens) ? updatePayload.allergens : [];
            if (updatePayload.status !== undefined) cleanPayload.status = updatePayload.status;
            cleanPayload.updated_at = new Date().toISOString();

            // 1. Always update local cache immediately
            const currentProducts = this.loadLocal('novalunch_products_catalog', []);
            const updatedLocal = currentProducts.map(p => (p.id === productId || (p.name && updatePayload.name && p.name.toLowerCase() === updatePayload.name.toLowerCase())) ? { ...p, ...cleanPayload } : p);
            this.saveLocal('novalunch_products_catalog', updatedLocal);

            if (this.isUUID(productId)) {
                if (supabase) {
                    try {
                        const { data, error } = await supabase.from('products').update(cleanPayload).eq('id', productId).select();
                        if (!error && data) return data;
                        if (error) {
                            console.warn("[CanteenDB] updateProduct standard update notice, attempting alternate schema:", error.message);
                            // Fallback with standardized columns
                            const fallbackPayload = {
                                name: cleanPayload.name,
                                price: cleanPayload.price,
                                stock: cleanPayload.stock,
                                available: cleanPayload.available,
                                img: cleanPayload.img,
                                calories: cleanPayload.calories,
                                protein: cleanPayload.protein,
                                allergens: cleanPayload.allergens,
                                updated_at: cleanPayload.updated_at
                            };
                            const { data: fbData, error: fbErr } = await supabase.from('products').update(fallbackPayload).eq('id', productId).select();
                            if (!fbErr && fbData) return fbData;
                        }
                    } catch (e) {
                        console.warn("[CanteenDB] Supabase updateProduct exception:", e);
                    }
                } else {
                    try {
                        return await this._patchREST(`products?id=eq.${productId}`, cleanPayload);
                    } catch (e) { }
                }
            }
            return [cleanPayload];
        },

        async deleteProduct(productId) {
            // Always update local cache
            const currentProducts = this.loadLocal('novalunch_products_catalog', []);
            const updatedLocal = currentProducts.filter(p => p.id !== productId && p.name !== productId);
            this.saveLocal('novalunch_products_catalog', updatedLocal);

            if (this.isUUID(productId)) {
                if (supabase) {
                    try {
                        const { error } = await supabase.from('products').delete().eq('id', productId);
                        if (error) console.warn("Supabase deleteProduct warning:", error);
                    } catch (e) {
                        console.warn("Supabase deleteProduct exception:", e);
                    }
                } else {
                    try {
                        await this._deleteREST(`products?id=eq.${productId}`);
                    } catch (e) { }
                }
            }
            return { success: true, id: productId };
        },

        async deleteUser(userId) {
            // Always update local cache
            const currentUsers = this.loadLocal('novalunch_registered_users', []);
            const updatedLocal = currentUsers.filter(u => u.id !== userId);
            this.saveLocal('novalunch_registered_users', updatedLocal);

            if (this.isUUID(userId)) {
                if (supabase) {
                    try {
                        await supabase.from('wallets').delete().eq('user_id', userId).catch(() => { });
                        const { error } = await supabase.from('profiles').delete().eq('id', userId);
                        if (error) console.warn("Supabase deleteUser warning:", error);
                    } catch (e) {
                        console.warn("Supabase deleteUser exception:", e);
                    }
                } else {
                    try {
                        await this._deleteREST(`wallets?user_id=eq.${userId}`).catch(() => { });
                        await this._deleteREST(`profiles?id=eq.${userId}`);
                    } catch (e) { }
                }
            }
            return { success: true, id: userId };
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
            const cleanPayload = {
                ...batchPayload,
                quantity: Math.max(1, parseInt(batchPayload.quantity ?? batchPayload.quantity_received) || 1),
                quantity_remaining: Math.max(0, parseInt(batchPayload.quantity_remaining ?? batchPayload.quantity) || 1),
                unit_cost: Math.max(0, parseFloat(batchPayload.unit_cost) || 0)
            };
            if (supabase) {
                const { data, error } = await supabase.from('inventory_batches').insert([cleanPayload]).select().single();
                if (error) throw error;
                return data;
            } else {
                const res = await this._postREST('inventory_batches', cleanPayload);
                return res[0];
            }
        },

        async deductCartStockFifo(cartItems) {
            if (!cartItems || !cartItems.length) return { success: true };
            const cleanItems = cartItems.map(item => ({
                id: item.id || item.product_id,
                qty: parseInt(item.qty || item.quantity) || 1,
                name: item.name || item.product_name
            }));

            // 1. Deduct immediately from local products catalog
            const localProds = this.loadLocal('novalunch_products_catalog', []);
            const updatedProds = localProds.map(p => {
                const match = cleanItems.find(i => (i.id && (i.id === p.id)) || (i.name && p.name && i.name.toLowerCase() === p.name.toLowerCase()));
                if (match) {
                    return { ...p, stock: Math.max(0, (p.stock || 0) - match.qty) };
                }
                return p;
            });
            this.saveLocal('novalunch_products_catalog', updatedProds);

            // 2. Deduct FIFO remaining from local batches
            const localBatches = this.loadLocal('novalunch_inventory_batches', []);
            if (localBatches && localBatches.length > 0) {
                let batchCopy = JSON.parse(JSON.stringify(localBatches));
                for (const item of cleanItems) {
                    let rem = item.qty;
                    for (let b of batchCopy) {
                        const isMatch = (item.id && b.product_id === item.id) || 
                                        (item.name && (b.product_name || '').toLowerCase() === item.name.toLowerCase()) || 
                                        (b.products?.name && item.name && b.products.name.toLowerCase() === item.name.toLowerCase());
                        if (isMatch && rem > 0 && b.quantity_remaining > 0) {
                            const d = Math.min(b.quantity_remaining, rem);
                            rem -= d;
                            b.quantity_remaining -= d;
                            if (b.quantity_remaining === 0) b.status = 'DEPLETED';
                        }
                    }
                }
                this.saveLocal('novalunch_inventory_batches', batchCopy);
            }

            // If all items are valid UUIDs, attempt RPC
            const allUUIDs = cleanItems.every(i => this.isUUID(i.id));
            if (supabase && allUUIDs) {
                try {
                    const { data, error } = await supabase.rpc('fn_deduct_cart_stock_fifo', { p_items: cleanItems });
                    if (!error && data) return data;
                } catch (e) {
                    console.warn("[CanteenDB] RPC fn_deduct_cart_stock_fifo error, falling back to individual deductions", e);
                }
            }

            // Fallback: Deduct items individually
            return await Promise.all(cleanItems.map(i => this.deductStockFifo(i.id, i.qty, i.name)));
        },

        async deductStockFifo(productId, quantity, productName = null) {
            const cleanQty = Math.max(1, parseInt(quantity) || 1);
            // 1. Update local catalog stock immediately
            const localProds = this.loadLocal('novalunch_products_catalog', []);
            let wasInStock = true;
            const updated = localProds.map(p => {
                const isMatch = (productId && p.id === productId) || (productName && p.name && p.name.toLowerCase() === productName.toLowerCase());
                if (isMatch) {
                    if ((p.stock || 0) < cleanQty) wasInStock = false;
                    return { ...p, stock: Math.max(0, (p.stock || 0) - cleanQty) };
                }
                return p;
            });
            this.saveLocal('novalunch_products_catalog', updated);

            // 2. Deduct from local batches if matching
            const localBatches = this.loadLocal('novalunch_inventory_batches', []);
            if (localBatches && localBatches.length > 0) {
                let remainingToDeduct = cleanQty;
                const updatedBatches = localBatches.map(b => {
                    const isMatch = (productId && b.product_id === productId) || 
                                    (productName && (b.product_name || '').toLowerCase() === productName.toLowerCase()) || 
                                    (b.products?.name && productName && b.products.name.toLowerCase() === productName.toLowerCase());
                    if (isMatch && remainingToDeduct > 0 && b.quantity_remaining > 0) {
                        const d = Math.min(b.quantity_remaining, remainingToDeduct);
                        remainingToDeduct -= d;
                        const newRem = b.quantity_remaining - d;
                        return { ...b, quantity_remaining: newRem, status: newRem === 0 ? 'DEPLETED' : b.status };
                    }
                    return b;
                });
                this.saveLocal('novalunch_inventory_batches', updatedBatches);
            }

            if (supabase && this.isUUID(productId)) {
                try {
                    const { data, error } = await supabase.rpc('fn_deduct_stock_fifo', { p_product_id: productId, p_quantity: cleanQty });
                    if (!error && data !== null) return data;
                } catch (e) {
                    console.warn("RPC fn_deduct_stock_fifo notice:", e);
                }
                // Fallback direct stock & batch update
                try {
                    const { data: prod, error: prodErr } = await supabase.from('products').select('stock_quantity').eq('id', productId).single();
                    if (prod && !prodErr) {
                        const currentStock = prod.stock_quantity || 0;
                        if (currentStock < cleanQty) {
                            return { success: false, error: 'OUT_OF_STOCK', remaining: currentStock };
                        }
                        const newStock = Math.max(0, currentStock - cleanQty);
                        await supabase.from('products').update({ stock_quantity: newStock }).eq('id', productId);
                    }
                } catch (e) {
                    console.warn("Direct product stock update notice:", e);
                }
            }
            return { success: wasInStock, remaining: 0 };
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
            if (supabase && this.isUUID(userId)) {
                try {
                    const { data, error } = await supabase.from('wallets').select('*').eq('user_id', userId).maybeSingle();
                    if (!error && data) return data;
                } catch (e) {
                    console.warn('[CanteenDB] getWalletByUserId cloud warn:', e);
                }
            }
            // Local fallback for demo / non-UUID or offline
            const users = this.loadLocal('novalunch_registered_users', []);
            const matched = users.find(u => u.id === userId || u.studentId === userId || (u.email && u.email.toLowerCase() === String(userId).toLowerCase()) || (u.name && u.name.toLowerCase() === String(userId).toLowerCase()));
            if (matched) {
                return {
                    user_id: matched.id,
                    balance: typeof matched.balance === 'number' ? matched.balance : (parseFloat(matched.balance) || 0),
                    daily_limit: typeof matched.dailyCap === 'number' ? matched.dailyCap : (parseFloat(matched.dailyCap) || 200.0)
                };
            }
            return null;
        },

        /**
         * ATOMIC wallet deduction for PURCHASES — uses delta RPC to prevent race conditions.
         * Two simultaneous purchases cannot both succeed if only one unit of balance exists.
         * Call this for purchases/deductions. Use updateStudentBalance only for top-ups/admin sets.
         */
        async deductWalletBalance(userId, amount) {
            const cleanAmount = parseFloat(amount);
            if (!cleanAmount || cleanAmount <= 0) throw new Error('Deduction amount must be a positive number.');

            // Read local balance for non-UUID / demo student fallback
            const users = this.loadLocal('novalunch_registered_users', []);
            const localUser = users.find(u => u.id === userId || u.studentId === userId || (u.email && u.email.toLowerCase() === String(userId).toLowerCase()) || (u.name && u.name.toLowerCase() === String(userId).toLowerCase()));
            const localBal = localUser ? (typeof localUser.balance === 'number' ? localUser.balance : (parseFloat(localUser.balance) || 0)) : 0;

            if (supabase && this.isUUID(userId)) {
                // Primary path: atomic delta RPC (deployed via security_hardening.sql)
                try {
                    const { data, error: rpcError } = await supabase.rpc('fn_deduct_wallet_balance', {
                        p_user_id: userId,
                        p_amount: cleanAmount
                    });
                    if (rpcError) {
                        // Re-throw business logic errors immediately
                        if (rpcError.message && (rpcError.message.includes('INSUFFICIENT_FUNDS') || rpcError.message.includes('WALLET_NOT_FOUND'))) {
                            throw new Error(rpcError.message);
                        }
                        console.warn('[CanteenDB] fn_deduct_wallet_balance RPC error, using safe fallback:', rpcError.message);
                    } else if (data !== null && data !== undefined) {
                        const newBal = typeof data === 'number' ? data : (data.new_balance ?? data);
                        this.saveLocal('novalunch_registered_users', users.map(u => (u.id === userId || u.studentId === userId) ? { ...u, balance: newBal } : u));
                        return { success: true, new_balance: newBal };
                    }
                } catch (rpcErr) {
                    if (rpcErr.message && (rpcErr.message.includes('INSUFFICIENT_FUNDS') || rpcErr.message.includes('WALLET_NOT_FOUND'))) {
                        throw rpcErr;
                    }
                    console.warn('[CanteenDB] fn_deduct_wallet_balance RPC unavailable, using safe fallback:', rpcErr.message);
                }

                // Safe fallback: read-check-update directly on wallets table
                let walletBal = localBal;
                try {
                    const { data: walletData, error: fetchErr } = await supabase
                        .from('wallets').select('balance').eq('user_id', userId).maybeSingle();

                    if (!fetchErr && walletData && walletData.balance !== undefined) {
                        walletBal = parseFloat(walletData.balance) || 0;
                    }
                } catch (fetchEx) {
                    console.warn('[CanteenDB] Wallet fetch fallback error:', fetchEx);
                }

                if (walletBal < cleanAmount) {
                    throw new Error(`INSUFFICIENT_FUNDS: Required ₱${cleanAmount.toFixed(2)}, Available ₱${walletBal.toFixed(2)}`);
                }
                const newBalance = parseFloat((walletBal - cleanAmount).toFixed(2));
                try {
                    await supabase.from('wallets')
                        .upsert({ user_id: userId, balance: newBalance, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
                    await supabase.from('profiles').update({ updated_at: new Date().toISOString() }).eq('id', userId).catch(() => {});
                } catch (upErr) {
                    console.warn('[CanteenDB] Cloud wallet deduction sync warning:', upErr);
                }
                this.saveLocal('novalunch_registered_users', users.map(u => (u.id === userId || u.studentId === userId) ? { ...u, balance: newBalance } : u));
                return { success: true, new_balance: newBalance };
            }

            // Local fallback (offline or demo user like u101)
            if (localBal < cleanAmount) {
                throw new Error(`INSUFFICIENT_FUNDS: Required ₱${cleanAmount.toFixed(2)}, Available ₱${localBal.toFixed(2)}`);
            }
            const newBal = parseFloat((localBal - cleanAmount).toFixed(2));
            this.saveLocal('novalunch_registered_users', users.map(u => (u.id === userId || u.studentId === userId) ? { ...u, balance: newBal } : u));
            return { success: true, new_balance: newBal };
        },

        /**
         * ATOMIC wallet crediting for TOP-UPS & REFUNDS — uses delta RPC to prevent race conditions.
         * Prevents overwriting concurrent POS purchase deductions with stale balance values.
         */
        async creditWalletBalance(userId, amount) {
            const cleanAmount = parseFloat(amount);
            if (!cleanAmount || cleanAmount <= 0) throw new Error('Credit amount must be a positive number.');

            // 1. Always update local registered users cache immediately
            const users = this.loadLocal('novalunch_registered_users', []);
            let updatedLocalBal = 0;
            const updatedUsers = users.map(u => {
                const isMatch = u.id === userId || u.studentId === userId || 
                               (u.email && u.email.toLowerCase() === String(userId).toLowerCase()) ||
                               (u.name && u.name.toLowerCase() === String(userId).toLowerCase());
                if (isMatch) {
                    const curBal = typeof u.balance === 'number' ? u.balance : (parseFloat(u.balance) || 0);
                    const newBal = parseFloat((curBal + cleanAmount).toFixed(2));
                    updatedLocalBal = newBal;
                    return { ...u, balance: newBal };
                }
                return u;
            });
            this.saveLocal('novalunch_registered_users', updatedUsers);

            if (supabase && this.isUUID(userId)) {
                try {
                    const { data, error } = await supabase.rpc('fn_credit_wallet_balance', {
                        p_user_id: userId,
                        p_amount: cleanAmount
                    });
                    if (!error && data !== null) {
                        return typeof data === 'number' ? data : (data.new_balance || (updatedLocalBal || cleanAmount));
                    }
                } catch (rpcErr) {
                    console.warn('[CanteenDB] fn_credit_wallet_balance RPC fallback', rpcErr);
                }

                // Safe fallback: fetch-add-update
                try {
                    const { data: walletData } = await supabase
                        .from('wallets').select('balance').eq('user_id', userId).maybeSingle();

                    const currentBal = walletData ? (parseFloat(walletData.balance) || 0) : (updatedLocalBal - cleanAmount);
                    const newBalance = parseFloat((currentBal + cleanAmount).toFixed(2));

                    await supabase.from('wallets')
                        .upsert({ user_id: userId, balance: newBalance, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
                    await supabase.from('profiles').update({ updated_at: new Date().toISOString() }).eq('id', userId).catch(() => {});
                    return newBalance;
                } catch (wErr) {
                    console.warn('[CanteenDB] Cloud credit wallet error:', wErr);
                }
            }

            return updatedLocalBal || cleanAmount;
        },

        /**
         * Absolute balance write — for admin overrides only.
         * Do NOT use this for purchase deductions or top-ups (use deductWalletBalance or creditWalletBalance instead).
         */
        async updateStudentBalance(userId, newBalance) {
            const cleanBalance = Math.max(0, parseFloat(newBalance) || 0);

            // 1. Update local cache immediately
            const users = this.loadLocal('novalunch_registered_users', []);
            this.saveLocal('novalunch_registered_users', users.map(u => (u.id === userId || u.studentId === userId) ? { ...u, balance: cleanBalance } : u));

            // 2. Database update to wallets table
            if (this.isUUID(userId)) {
                if (supabase) {
                    try {
                        const { error: patchErr } = await supabase.from('wallets').update({ balance: cleanBalance, updated_at: new Date().toISOString() }).eq('user_id', userId);
                        if (patchErr) {
                            await supabase.from('wallets').upsert({ user_id: userId, balance: cleanBalance, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
                        }
                    } catch (e) { }
                }
                try {
                    await fetch(`${SUPABASE_URL}/rest/v1/wallets?user_id=eq.${userId}`, {
                        method: 'PATCH',
                        headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                        body: JSON.stringify({ balance: cleanBalance, updated_at: new Date().toISOString() })
                    });
                } catch (e) { }
            }
            return cleanBalance;
        },

        async updateStudentCreditLiability(userId, newLiability) {
            const cleanLiability = Math.max(0, parseFloat(newLiability) || 0);
            if (supabase && this.isUUID(userId)) {
                const { error: wErr } = await supabase.from('wallets').upsert({ user_id: userId, credit_liability: cleanLiability, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
                if (wErr) {
                    console.error("Failed to update wallet liability in Supabase:", wErr);
                    throw new Error(`Database error updating wallet liability: ${wErr.message}`);
                }
                const { error: pErr } = await supabase.from('profiles').update({ credit_liability: cleanLiability }).eq('id', userId);
                if (pErr) {
                    console.error("Failed to update profile liability in Supabase:", pErr);
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
                } catch (e) {
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
                    product_id: item.product_id && this.isUUID(item.product_id) ? item.product_id : null,
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
                console.warn("[registerUser] Phone number format looks unusual, proceeding anyway:", payload.phone);
            }

            const fullName = payload.full_name || `${payload.first_name || payload.firstName || ''} ${payload.last_name || payload.lastName || ''}`.trim() || 'NovaLunch User';
            const role = (payload.role || 'student').toLowerCase();
            const studentId = payload.student_id_number || payload.studentId || (role === 'student' ? `2026-${Math.floor(10000 + Math.random() * 90000)}` : null);

            const VALID_PROFILE_COLUMNS = new Set([
                'id', 'full_name', 'email', 'role', 'student_id_number', 'rfid_uid', 'pin_code',
                'avatar_url', 'status', 'daily_calories_spent', 'max_meal_calories',
                'first_name', 'last_name', 'employee_id', 'weekly_limit', 'monthly_allowance',
                'credit_liability', 'credit_limit', 'pay_later_count', 'pay_later_pre_authorized',
                'max_daily_calories', 'allergen_mode', 'allergies', 'restricted_categories',
                'manager_pin', 'accumulated_salary_deduction', 'updated_at'
            ]);

            const profileFields = {
                full_name: fullName,
                email: payload.email || `${(role || 'user')}_${Date.now()}@sjc.edu.ph`,
                role: role,
                student_id_number: studentId,
                rfid_uid: payload.rfid_uid || payload.rfidUid || null,
                pin_code: payload.pin_code || payload.pinCode || '1234',
                status: payload.status || 'active',
                allergies: Array.isArray(payload.allergies) ? payload.allergies : (Array.isArray(payload.allergen_restrictions) ? payload.allergen_restrictions : []),
                max_daily_calories: parseInt(payload.max_daily_calories || payload.maxDailyCalories) || 1800,
                allergen_mode: payload.allergen_mode || payload.allergenMode || 'SOFT_WARN',
                credit_limit: parseFloat(payload.credit_limit || payload.creditLimit || payload.pay_later_allowance) || 500.0,
                credit_liability: parseFloat(payload.credit_liability || payload.creditLiability) || 0.0,
                pay_later_pre_authorized: payload.pay_later_pre_authorized !== undefined ? Boolean(payload.pay_later_pre_authorized) : true,
                updated_at: new Date().toISOString()
            };

            if (payload.id && this.isUUID(payload.id)) {
                profileFields.id = payload.id;
            }

            // Clean to only columns present in PostgreSQL
            const sanitizedFields = {};
            for (const [k, v] of Object.entries(profileFields)) {
                if (VALID_PROFILE_COLUMNS.has(k)) sanitizedFields[k] = v;
            }

            let profile = null;
            if (supabase) {
                const { data, error } = await supabase.from('profiles').insert([sanitizedFields]).select().single();
                if (error) {
                    if (error.code === '23505') {
                        const detail = error.message || '';
                        if (detail.includes('rfid_uid')) throw new Error('That RFID UID is already assigned to another account.');
                        if (detail.includes('email')) throw new Error('That email address is already registered.');
                        if (detail.includes('student_id_number')) throw new Error('That Student ID is already registered.');
                        throw new Error(`Duplicate value detected: ${detail}`);
                    }
                    throw new Error(error.message || 'Database insertion failed.');
                }
                profile = data;

                if (profile && payload.password) {
                    try {
                        const { error: authErr } = await supabase.auth.signUp({
                            email: sanitizedFields.email,
                            password: payload.password,
                            options: {
                                data: {
                                    full_name: sanitizedFields.full_name,
                                    role: sanitizedFields.role
                                },
                                emailRedirectTo: undefined
                            }
                        });
                        if (authErr) {
                            console.warn('[registerUser] Auth user creation warning:', authErr.message);
                        }
                    } catch (authEx) {
                        console.warn('[registerUser] Auth signUp exception:', authEx);
                    }
                }
            }

            if (!profile) {
                try {
                    const res = await this._postREST('profiles', sanitizedFields);
                    if (res && res[0]) profile = res[0];
                } catch (e) {
                    profile = {
                        id: sanitizedFields.id || (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : 'u_' + Date.now()),
                        ...sanitizedFields,
                        created_at: new Date().toISOString()
                    };
                }
            }

            // Initialize wallet for students automatically
            const initBal = typeof payload.balance === 'number' ? payload.balance : (parseFloat(payload.initial_balance || payload.balance) || 0.00);
            const initLimit = typeof payload.dailyCap === 'number' ? payload.dailyCap : (parseFloat(payload.daily_limit || payload.dailyCap) || 200.00);

            if (profile && profile.id) {
                const walletPayload = {
                    user_id: profile.id,
                    balance: initBal,
                    daily_limit: initLimit,
                    daily_spent: 0.00,
                    updated_at: new Date().toISOString()
                };
                if (this.isUUID(profile.id)) {
                    if (supabase) {
                        try {
                            const { error: wErr } = await supabase.from('wallets').upsert(walletPayload, { onConflict: 'user_id' });
                            if (wErr) console.warn("Wallet init warning:", wErr);
                        } catch (wEx) { console.warn("Wallet init exception:", wEx); }
                    } else {
                        try {
                            await this._postREST('wallets', walletPayload);
                        } catch (wErr) { console.warn("REST Wallet init warning:", wErr); }
                    }
                }
                profile.wallets = [walletPayload];
            }

            // Update local cache
            const localUserObj = {
                id: profile.id,
                email: profile.email,
                studentId: profile.student_id_number || studentId || "2026-00001",
                name: profile.full_name,
                role: role.charAt(0).toUpperCase() + role.slice(1),
                rfidUid: profile.rfid_uid || "1A-2B-3C-4D",
                dailyCap: initLimit,
                balance: initBal,
                status: profile.status || 'active',
                allergies: profile.allergies || [],
                pinCode: profile.pin_code || '1234',
                creditLiability: profile.credit_liability || 0,
                creditLimit: profile.credit_limit || 500,
                maxDailyCalories: profile.max_daily_calories || 1800,
                allergenMode: profile.allergen_mode || 'SOFT_WARN',
                managerPin: profile.manager_pin || '1234'
            };

            const currentUsers = this.loadLocal('novalunch_registered_users', []);
            this.saveLocal('novalunch_registered_users', [localUserObj, ...currentUsers.filter(u => u.id !== localUserObj.id)]);

            return localUserObj;
        },

        async createUser(payload) {
            return await this.registerUser(payload);
        },

        async getAllUsers() {
            const cached = this.loadLocal('novalunch_registered_users', null);
            let cloudProfiles = [];
            let cloudWallets = [];
            try {
                if (!supabase) {
                    const [profs, walls] = await Promise.all([
                        this._fetchREST('profiles?order=created_at.desc'),
                        this._fetchREST('wallets')
                    ]);
                    cloudProfiles = profs || [];
                    cloudWallets = walls || [];
                } else {
                    const [profsRes, wallsRes] = await Promise.all([
                        supabase.from('profiles').select('*').order('created_at', { ascending: false }),
                        supabase.from('wallets').select('*')
                    ]);
                    if (!profsRes.error && profsRes.data) cloudProfiles = profsRes.data;
                    if (!wallsRes.error && wallsRes.data) cloudWallets = wallsRes.data;
                }
            } catch (e) {
                console.warn("getAllUsers cloud fetch fallback to cache:", e);
            }

            if (cloudProfiles && cloudProfiles.length > 0) {
                const walletMap = new Map();
                cloudWallets.forEach(w => {
                    if (w.user_id) walletMap.set(w.user_id, w);
                    if (w.id) walletMap.set(w.id, w);
                });

                const existingLocalUsers = this.loadLocal('novalunch_registered_users', []);
                const localUserMap = new Map();
                existingLocalUsers.forEach(u => {
                    if (u.id) localUserMap.set(u.id, u);
                    if (u.email) localUserMap.set(u.email.toLowerCase(), u);
                    if (u.studentId) localUserMap.set(u.studentId, u);
                });

                const mapped = cloudProfiles.map(u => {
                    const w = walletMap.get(u.id);
                    const localU = localUserMap.get(u.id) || localUserMap.get((u.email || '').toLowerCase()) || localUserMap.get(u.student_id_number);

                    let userBal = 0.00;
                    if (w && w.balance !== null && w.balance !== undefined) {
                        userBal = parseFloat(w.balance);
                    } else if (u.balance !== null && u.balance !== undefined) {
                        userBal = parseFloat(u.balance);
                    } else if (localU && localU.balance !== null && localU.balance !== undefined) {
                        userBal = parseFloat(localU.balance);
                    }

                    let userCap = 200.00;
                    if (w && w.daily_limit !== null && w.daily_limit !== undefined) {
                        userCap = parseFloat(w.daily_limit);
                    } else if (u.daily_limit !== null && u.daily_limit !== undefined) {
                        userCap = parseFloat(u.daily_limit);
                    } else if (localU && localU.dailyCap !== undefined) {
                        userCap = parseFloat(localU.dailyCap);
                    }

                    return {
                        id: u.id,
                        email: u.email,
                        studentId: u.student_id_number || localU?.studentId || "2026-00001",
                        name: u.full_name || localU?.name || "Student",
                        role: u.role ? (u.role.charAt(0).toUpperCase() + u.role.slice(1)) : (localU?.role || 'Student'),
                        rfidUid: u.rfid_uid || localU?.rfidUid || "1A-2B-3C-4D",
                        dailyCap: userCap,
                        daily_limit: userCap,
                        balance: userBal,
                        status: u.status || localU?.status || 'active',
                        allergies: u.allergies || localU?.allergies || [],
                        pinCode: u.pin_code || localU?.pinCode || '1234',
                        creditLiability: parseFloat(w?.credit_liability ?? u.credit_liability ?? localU?.creditLiability ?? 0),
                        creditLimit: parseFloat(w?.credit_limit ?? u.credit_limit ?? localU?.creditLimit ?? 500),
                        maxDailyCalories: u.max_daily_calories || localU?.maxDailyCalories || 1800,
                        allergenMode: u.allergen_mode || localU?.allergenMode || 'SOFT_WARN',
                        managerPin: u.manager_pin || localU?.managerPin || '1234'
                    };
                });
                this.saveLocal('novalunch_registered_users', mapped);
                return mapped;
            }
            return cached || [];
        },

        async updateUser(userId, updatePayload) {
            const VALID_PROFILE_COLUMNS = new Set([
                'full_name', 'email', 'role', 'student_id_number', 'rfid_uid', 'pin_code',
                'avatar_url', 'status', 'daily_calories_spent', 'max_meal_calories',
                'first_name', 'last_name', 'employee_id', 'weekly_limit', 'monthly_allowance',
                'credit_liability', 'credit_limit', 'pay_later_count', 'pay_later_pre_authorized',
                'max_daily_calories', 'allergen_mode', 'allergies', 'restricted_categories',
                'manager_pin', 'accumulated_salary_deduction', 'updated_at'
            ]);

            const profileFields = {};
            if (updatePayload.name !== undefined) profileFields.full_name = updatePayload.name;
            if (updatePayload.full_name !== undefined) profileFields.full_name = updatePayload.full_name;
            if (updatePayload.studentId !== undefined) profileFields.student_id_number = updatePayload.studentId;
            if (updatePayload.student_id_number !== undefined) profileFields.student_id_number = updatePayload.student_id_number;
            if (updatePayload.email !== undefined) profileFields.email = updatePayload.email;
            if (updatePayload.role !== undefined) profileFields.role = String(updatePayload.role).toLowerCase();
            if (updatePayload.rfidUid !== undefined) profileFields.rfid_uid = updatePayload.rfidUid;
            if (updatePayload.rfid_uid !== undefined) profileFields.rfid_uid = updatePayload.rfid_uid;
            if (updatePayload.pinCode !== undefined) profileFields.pin_code = updatePayload.pinCode;
            if (updatePayload.pin_code !== undefined) profileFields.pin_code = updatePayload.pin_code;
            if (updatePayload.managerPin !== undefined) profileFields.manager_pin = updatePayload.managerPin;
            if (updatePayload.status !== undefined) profileFields.status = updatePayload.status;
            if (updatePayload.allergies !== undefined) profileFields.allergies = Array.isArray(updatePayload.allergies) ? updatePayload.allergies : [];
            if (updatePayload.allergen_restrictions !== undefined) profileFields.allergies = Array.isArray(updatePayload.allergen_restrictions) ? updatePayload.allergen_restrictions : [];
            if (updatePayload.creditLimit !== undefined) profileFields.credit_limit = parseFloat(updatePayload.creditLimit) || 500;
            if (updatePayload.credit_limit !== undefined) profileFields.credit_limit = parseFloat(updatePayload.credit_limit) || 500;
            if (updatePayload.pay_later_allowance !== undefined) profileFields.credit_limit = parseFloat(updatePayload.pay_later_allowance) || 500;
            if (updatePayload.creditLiability !== undefined) profileFields.credit_liability = parseFloat(updatePayload.creditLiability) || 0;
            if (updatePayload.credit_liability !== undefined) profileFields.credit_liability = parseFloat(updatePayload.credit_liability) || 0;
            if (updatePayload.maxDailyCalories !== undefined) profileFields.max_daily_calories = parseInt(updatePayload.maxDailyCalories) || 1800;
            if (updatePayload.max_daily_calories !== undefined) profileFields.max_daily_calories = parseInt(updatePayload.max_daily_calories) || 1800;
            if (updatePayload.allergenMode !== undefined) profileFields.allergen_mode = updatePayload.allergenMode;
            if (updatePayload.allergen_mode !== undefined) profileFields.allergen_mode = updatePayload.allergen_mode;
            profileFields.updated_at = new Date().toISOString();

            const cleanBalance = updatePayload.balance !== undefined ? (parseFloat(updatePayload.balance) || 0.0) : undefined;
            const cleanDailyCap = updatePayload.daily_limit !== undefined ? (parseFloat(updatePayload.daily_limit) || 200.0) : (updatePayload.dailyCap !== undefined ? (parseFloat(updatePayload.dailyCap) || 200.0) : undefined);
            const cleanLiability = updatePayload.credit_liability !== undefined ? (parseFloat(updatePayload.credit_liability) || 0.0) : (updatePayload.creditLiability !== undefined ? (parseFloat(updatePayload.creditLiability) || 0.0) : undefined);

            profileFields.updated_at = new Date().toISOString();

            // 1. Update local cache immediately
            const currentUsers = this.loadLocal('novalunch_registered_users', []);
            const updatedLocal = currentUsers.map(u => {
                if (u.id === userId || u.studentId === userId) {
                    return {
                        ...u,
                        ...updatePayload,
                        ...(profileFields.full_name ? { name: profileFields.full_name } : {}),
                        ...(profileFields.student_id_number ? { studentId: profileFields.student_id_number } : {}),
                        ...(profileFields.credit_limit !== undefined ? { creditLimit: profileFields.credit_limit } : {}),
                        ...(profileFields.allergies ? { allergies: profileFields.allergies } : {}),
                        ...(profileFields.pin_code ? { pinCode: profileFields.pin_code } : {}),
                        ...(cleanBalance !== undefined ? { balance: cleanBalance } : {}),
                        ...(cleanDailyCap !== undefined ? { dailyCap: cleanDailyCap, daily_limit: cleanDailyCap } : {})
                    };
                }
                return u;
            });
            this.saveLocal('novalunch_registered_users', updatedLocal);

            // 2. Only pass valid columns to Supabase profiles
            const sanitizedFields = {};
            for (const [k, v] of Object.entries(profileFields)) {
                if (VALID_PROFILE_COLUMNS.has(k)) sanitizedFields[k] = v;
            }

            let updatedProfile = null;
            if (this.isUUID(userId)) {
                // A. Update Wallets table directly (balance and daily_limit)
                if (cleanBalance !== undefined || cleanDailyCap !== undefined) {
                    const walletPatch = { updated_at: new Date().toISOString() };
                    if (cleanBalance !== undefined) walletPatch.balance = cleanBalance;
                    if (cleanDailyCap !== undefined) walletPatch.daily_limit = cleanDailyCap;

                    if (supabase) {
                        try {
                            const { error: patchErr } = await supabase.from('wallets').update(walletPatch).eq('user_id', userId);
                            if (patchErr) {
                                await supabase.from('wallets').upsert({ user_id: userId, ...walletPatch }, { onConflict: 'user_id' });
                            }
                        } catch (e) {
                            console.warn('[CanteenDB] Wallet update exception:', e);
                        }
                    }
                    try {
                        await fetch(`${SUPABASE_URL}/rest/v1/wallets?user_id=eq.${userId}`, {
                            method: 'PATCH',
                            headers: {
                                "apikey": SUPABASE_ANON_KEY,
                                "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
                                "Content-Type": "application/json"
                            },
                            body: JSON.stringify(walletPatch)
                        });
                    } catch (e) { }
                }

                // B. Update profiles table
                const profileUpdatePayload = { ...sanitizedFields };
                delete profileUpdatePayload.balance;
                delete profileUpdatePayload.daily_limit;

                if (supabase) {
                    try {
                        const { data, error } = await supabase.from('profiles').update(profileUpdatePayload).eq('id', userId).select().single();
                        if (!error && data) {
                            updatedProfile = data;
                        } else if (error) {
                            console.warn("[CanteenDB] Supabase profile update notice:", error.message);
                            // Fallback with minimal core profile columns
                            const coreFields = {
                                full_name: profileUpdatePayload.full_name,
                                student_id_number: profileUpdatePayload.student_id_number,
                                email: profileUpdatePayload.email,
                                role: profileUpdatePayload.role,
                                rfid_uid: profileUpdatePayload.rfid_uid,
                                status: profileUpdatePayload.status,
                                updated_at: new Date().toISOString()
                            };
                            const cleanCore = {};
                            for (const [k, v] of Object.entries(coreFields)) {
                                if (v !== undefined) cleanCore[k] = v;
                            }
                            const { data: fbData } = await supabase.from('profiles').update(cleanCore).eq('id', userId).select().single();
                            if (fbData) updatedProfile = fbData;
                        }
                    } catch (e) {
                        console.warn("[CanteenDB] Supabase profile update exception:", e);
                    }
                } else {
                    try {
                        const res = await this._patchREST(`profiles?id=eq.${userId}`, profileUpdatePayload);
                        if (res && res[0]) updatedProfile = res[0];
                    } catch (e) { }
                }
            }

            return updatedProfile || sanitizedFields;
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

            // 1. Update local cache immediately
            const users = this.loadLocal('novalunch_registered_users', []);
            this.saveLocal('novalunch_registered_users', users.map(u => (u.id === userId || u.studentId === userId) ? { ...u, dailyCap: cleanLimit, daily_limit: cleanLimit } : u));

            // 2. Cloud update
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

            if (supabase) {
                const { data: existingLink } = await supabase.from('parent_student_links').select('*').eq('parent_id', parentId).eq('student_id', student.id).maybeSingle();
                if (existingLink) throw new Error(`Student ${student.full_name} is already linked to your parent account.`);
            }

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
                const linkPayload = { parent_id: parentId, student_id: studentId };
                if (supabase) {
                    await supabase.from('parent_student_links').insert([linkPayload]);
                } else {
                    await this._postREST('parent_student_links', linkPayload);
                }
            }

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
        async createNotification({ user_id, title, message, type = 'system', severity = 'info', action_url = null, metadata = null }) {
            if (!user_id) {
                console.warn("Notification skipped: Missing user_id", { title, message });
                return null;
            }
            const notifPayload = {
                user_id,
                title,
                message,
                type,
                severity,
                action_url,
                is_read: false,
                metadata
            };
            if (supabase) {
                try {
                    const { data, error } = await supabase.from('notifications').insert([notifPayload]).select();
                    if (error) console.warn("Error creating notification:", error);
                    return data ? data[0] : null;
                } catch (err) {
                    console.warn("Exception creating notification:", err);
                    return null;
                }
            } else {
                return await this._postREST('notifications', notifPayload);
            }
        },

        async getNotifications(userId) {
            if (!userId) return [];
            if (!supabase) return await this._fetchREST(`notifications?select=*&user_id=eq.${userId}&order=created_at.desc`);
            try {
                const { data, error } = await supabase.from('notifications').select('*').eq('user_id', userId).order('created_at', { ascending: false });
                if (error) throw error;
                return data || [];
            } catch (e) {
                console.warn("Failed to fetch notifications from Supabase:", e);
                return [];
            }
        },

        async markNotificationRead(notificationId) {
            if (!notificationId) return;
            if (supabase) {
                try {
                    await supabase.from('notifications').update({ is_read: true }).eq('id', notificationId);
                } catch (e) {
                    console.warn("Error marking notification read:", e);
                }
            }
        },

        async markAllNotificationsRead(userId) {
            if (!userId) return;
            if (supabase) {
                try {
                    await supabase.from('notifications').update({ is_read: true }).eq('user_id', userId);
                } catch (e) {
                    console.warn("Error marking all notifications read:", e);
                }
            }
        },

        async getLinkedParents(studentId) {
            if (!studentId) return [];
            if (supabase) {
                try {
                    const { data, error } = await supabase.from('parent_student_links').select('parent_id, profiles!parent_id(*)').eq('student_id', studentId);
                    if (!error && data) {
                        return data.map(d => d.profiles || { id: d.parent_id });
                    }
                } catch (e) {
                    console.warn("Error fetching linked parents:", e);
                }
            }
            return [];
        },

        async getLinkedStudents(parentId) {
            if (!parentId) return [];
            if (supabase) {
                try {
                    const { data, error } = await supabase.from('parent_student_links').select('student_id, profiles!student_id(*)').eq('parent_id', parentId);
                    if (!error && data) {
                        return data.map(d => d.profiles || { id: d.student_id });
                    }
                } catch (e) {
                    console.warn("Error fetching linked students:", e);
                }
            }
            return [];
        },

        // -------------------------------------------------------------------------
        // PRE-ORDERS (TOKENLESS DIRECT RFID CONFIRMATION & ARCHIVING)
        // -------------------------------------------------------------------------
        async createPreorder(payload) {
            const fallbackId = payload.id || `po_${Date.now()}`;
            const cleanPayload = {
                id: payload.id || fallbackId,
                student_id: payload.student_id || payload.studentId || null,
                studentId: payload.studentId || payload.student_id || null,
                student_id_number: payload.student_id_number || payload.studentIdNumber || null,
                studentIdNumber: payload.studentIdNumber || payload.student_id_number || null,
                student_name: payload.student_name || payload.studentName || 'Student',
                studentName: payload.studentName || payload.student_name || 'Student',
                product_id: (payload.product_id && this.isUUID(payload.product_id)) ? payload.product_id : ((payload.productId && this.isUUID(payload.productId)) ? payload.productId : null),
                item_name: payload.item_name || payload.name || payload.item || 'Meal Pre-Order',
                name: payload.name || payload.item_name || payload.item || 'Meal Pre-Order',
                item: payload.item || payload.item_name || payload.name || 'Meal Pre-Order',
                price: parseFloat(payload.price) || 0.0,
                session: payload.session || 'Lunch Break (12:00 PM)',
                shelf_location: payload.shelf_location || payload.shelf || 'Shelf B2',
                shelf: payload.shelf || payload.shelf_location || 'Shelf B2',
                status: payload.status || 'Pending',
                is_archived: Boolean(payload.is_archived || payload.status === 'Claimed' || payload.status === 'Archived'),
                archived_at: payload.archived_at || (payload.status === 'Claimed' || payload.status === 'Archived' ? new Date().toISOString() : null),
                order_number: payload.order_number || payload.orderNo || null,
                created_at: payload.created_at || new Date().toISOString()
            };

            // Save to local cache immediately
            const localPos = this.loadLocal('novalunch_preorders', []);
            if (!localPos.some(p => p.id === cleanPayload.id)) {
                this.saveLocal('novalunch_preorders', [cleanPayload, ...localPos]);
            }

            if (supabase && cleanPayload.student_id && this.isUUID(cleanPayload.student_id)) {
                try {
                    const dbPayload = {
                        student_id: cleanPayload.student_id,
                        student_name: cleanPayload.student_name,
                        product_id: cleanPayload.product_id,
                        item_name: cleanPayload.item_name,
                        price: cleanPayload.price,
                        session: cleanPayload.session,
                        shelf_location: cleanPayload.shelf_location,
                        status: cleanPayload.status,
                        is_archived: cleanPayload.is_archived,
                        archived_at: cleanPayload.archived_at,
                        order_number: cleanPayload.order_number,
                        created_at: cleanPayload.created_at
                    };
                    const { data, error } = await supabase.from('preorders').insert([dbPayload]).select().single();
                    if (!error && data) {
                        const combined = { ...cleanPayload, id: data.id, is_archived: data.is_archived ?? cleanPayload.is_archived, archived_at: data.archived_at ?? cleanPayload.archived_at };
                        this.saveLocal('novalunch_preorders', [combined, ...localPos.filter(p => p.id !== cleanPayload.id && p.id !== data.id)]);
                        return combined;
                    }
                    console.warn("[CanteenDB Notice] Supabase 'preorders' table write notice:", error?.message);
                } catch (err) {
                    console.warn("[CanteenDB Notice] Supabase 'preorders' table exception:", err.message);
                }
            }
            return cleanPayload;
        },

        async getPreorders(studentId) {
            const localPos = this.loadLocal('novalunch_preorders', []);
            let cloudPos = [];
            if (supabase) {
                try {
                    let query = supabase.from('preorders').select('*').order('created_at', { ascending: false });
                    if (studentId) query = query.or(`student_id.eq.${studentId},student_name.eq.${studentId}`);
                    const { data, error } = await query;
                    if (!error && data && data.length > 0) cloudPos = data;
                } catch (e) {
                    console.warn("[CanteenDB Notice] getPreorders fallback:", e);
                }
            }
            if (cloudPos.length > 0) {
                const mapped = cloudPos.map(p => {
                    const isArch = Boolean(p.is_archived || p.status === 'Claimed' || p.status === 'Archived' || p.status === 'Completed');
                    return {
                        id: p.id,
                        name: p.item_name || p.name || 'Meal Item',
                        item: p.item_name || p.name || 'Meal Item',
                        item_name: p.item_name || p.name || 'Meal Item',
                        price: parseFloat(p.price) || 0,
                        token: p.token || 'QR-PASS',
                        status: p.status || 'Pending',
                        is_archived: isArch,
                        archived_at: p.archived_at || (isArch ? p.updated_at || p.created_at : null),
                        order_number: p.order_number || null,
                        orderNo: p.order_number || null,
                        studentId: p.student_id,
                        student_id: p.student_id,
                        studentName: p.student_name,
                        student_name: p.student_name,
                        shelf: p.shelf_location || 'Shelf B2',
                        shelf_location: p.shelf_location || 'Shelf B2',
                        session: p.session || 'Lunch Break (12:00 PM)',
                        created_at: p.created_at || new Date().toISOString()
                    };
                });
                const merged = [...mapped, ...localPos.filter(lp => !mapped.some(mp => mp.id === lp.id))];
                this.saveLocal('novalunch_preorders', merged);
                if (studentId) {
                    return merged.filter(p => p.studentId === studentId || p.student_id === studentId || p.studentName === studentId || p.student_id_number === studentId);
                }
                return merged;
            }
            if (studentId) {
                return localPos.filter(p => p.studentId === studentId || p.student_id === studentId || p.studentName === studentId || p.student_id_number === studentId);
            }
            return localPos;
        },

        async claimPreorderByStudent(studentId, preorderId = null) {
            if (supabase) {
                try {
                    const { data, error } = await supabase.rpc('fn_claim_preorder_by_student', {
                        p_student_id: studentId,
                        p_preorder_id: preorderId
                    });
                    if (!error && data) return data;
                } catch (e) {
                    console.warn("[CanteenDB] fn_claim_preorder_by_student RPC fallback", e);
                }
            }
            if (preorderId) {
                await this.archivePreorder(preorderId, { status: 'Claimed' });
                return { success: true, preorder_id: preorderId, status: 'Claimed', is_archived: true };
            }
            return { success: true, status: 'Claimed' };
        },

        async updatePreorderStatus(preorderId, status, extraFields = {}) {
            const isCompletedOrArchived = (status === 'Claimed' || status === 'Archived' || status === 'Completed' || Boolean(extraFields.is_archived));
            const archivedAt = isCompletedOrArchived ? (extraFields.archived_at || new Date().toISOString()) : null;
            const isArchived = isCompletedOrArchived;

            const localPos = this.loadLocal('novalunch_preorders', []);
            this.saveLocal('novalunch_preorders', localPos.map(p => p.id === preorderId ? { 
                ...p, 
                status, 
                is_archived: isArchived, 
                archived_at: archivedAt,
                ...extraFields 
            } : p));

            const updatePayload = {
                status,
                is_archived: isArchived,
                archived_at: archivedAt,
                updated_at: new Date().toISOString(),
                ...(extraFields.order_number ? { order_number: extraFields.order_number } : {}),
                ...(extraFields.refunded_amount !== undefined ? { refunded_amount: extraFields.refunded_amount } : {}),
                ...(extraFields.refund_note ? { refund_note: extraFields.refund_note } : {})
            };

            if (supabase) {
                try {
                    await supabase.from('preorders').update(updatePayload).eq('id', preorderId);
                } catch (e) {
                    console.warn("[CanteenDB Notice] updatePreorderStatus fallback:", e);
                }
            } else {
                try {
                    await fetch(`${SUPABASE_URL}/rest/v1/preorders?id=eq.${preorderId}`, {
                        method: 'PATCH',
                        headers: { "apikey": SUPABASE_ANON_KEY, "Authorization": `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
                        body: JSON.stringify(updatePayload)
                    });
                } catch (e) { }
            }
        },

        async archivePreorder(preorderId, { orderNo = null, status = 'Claimed' } = {}) {
            return await this.updatePreorderStatus(preorderId, status, {
                is_archived: true,
                archived_at: new Date().toISOString(),
                ...(orderNo ? { order_number: orderNo, orderNo } : {})
            });
        },

        async unarchivePreorder(preorderId) {
            return await this.updatePreorderStatus(preorderId, 'Pending', {
                is_archived: false,
                archived_at: null
            });
        },

        // -------------------------------------------------------------------------
        // GCASH RELOAD QUEUE & TOP-UPS
        // -------------------------------------------------------------------------
        async submitGcashReload(payload) {
            const cleanPayload = {
                student_id: payload.student_id || payload.studentId || null,
                student_name: payload.student_name || payload.studentName || 'Student',
                parent_name: payload.parent_name || payload.parent || null,
                amount: parseFloat(payload.amount) || 0.0,
                reference_number: String(payload.ref_no || payload.reference_number || payload.refNo || '').trim(),
                screenshot_url: payload.receipt_img || payload.screenshot_url || payload.receiptImg || null,
                submitter_role: payload.submitter_role || 'student',
                status: payload.status || 'Pending',
                created_at: payload.date ? new Date(payload.date).toISOString() : new Date().toISOString()
            };

            if (payload.id && this.isUUID(payload.id)) {
                cleanPayload.id = payload.id;
            }

            if (supabase) {
                const { data, error } = await supabase.from('topup_requests').insert([cleanPayload]).select().single();
                if (error) {
                    console.error("[CanteenDB Critical Error] Failed to submit GCash reload request:", error);
                    throw new Error(`Database error submitting top-up request: ${error.message}`);
                }
                return data;
            } else {
                const res = await this._postREST('topup_requests', cleanPayload);
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
                } catch (e) { return []; }
            }
            const { data, error } = await supabase.from('orders').select('*, order_items(*)').eq('user_id', studentId).order('created_at', { ascending: false });
            if (error) return [];
            return data || [];
        },

        // -------------------------------------------------------------------------
        // SECURITY & RFID PIN CODE
        // -------------------------------------------------------------------------
        async hashPin(rawPin) {
            const encoder = new TextEncoder();
            const data = encoder.encode(String(rawPin).trim());
            const hashBuffer = await crypto.subtle.digest('SHA-256', data);
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        },

        async verifyPin(rawPin, storedHash) {
            if (!rawPin || !storedHash) return false;
            const hash = await this.hashPin(rawPin);
            return hash === storedHash;
        },

        async updateStudentPin(userId, pinCode) {
            if (!pinCode || String(pinCode).trim().length < 4) {
                throw new Error('PIN must be at least 4 digits.');
            }
            const hashedPin = await this.hashPin(pinCode);
            if (supabase) {
                const { data, error } = await supabase.from('profiles').update({ pin_code: hashedPin }).eq('id', userId).select();
                if (error) throw error;
                return data;
            }
        },

        // -------------------------------------------------------------------------
        // SYSTEM SETTINGS & GOVERNANCE CONFIGURATION
        // -------------------------------------------------------------------------
        async getSystemSettings() {
            let cloudSettings = [];
            if (supabase) {
                try {
                    const { data, error } = await supabase.from('canteen_settings').select('*');
                    if (!error && data) cloudSettings = data;
                } catch (e) {
                    console.warn("getSystemSettings cloud fetch fallback:", e);
                }
            } else {
                try {
                    cloudSettings = await this._fetchREST('canteen_settings?select=*');
                } catch (e) { }
            }

            const cachedSettings = this.loadLocal('novalunch_canteen_settings', {});
            const settingsMap = {};
            if (cloudSettings && Array.isArray(cloudSettings)) {
                cloudSettings.forEach(s => { if (s && s.key) settingsMap[s.key] = s; });
            }
            if (cachedSettings && typeof cachedSettings === 'object') {
                Object.values(cachedSettings).forEach(s => {
                    if (s && s.key) {
                        if (!settingsMap[s.key] || new Date(s.updated_at || 0) >= new Date(settingsMap[s.key].updated_at || 0)) {
                            settingsMap[s.key] = s;
                        }
                    }
                });
            }
            const result = Object.values(settingsMap);
            if (result.length > 0) {
                const cacheToSave = {};
                result.forEach(s => { cacheToSave[s.key] = s; });
                this.saveLocal('novalunch_canteen_settings', cacheToSave);
            }
            return result;
        },

        async updateSystemSetting(key, value, description = '') {
            const payload = { key, value, description, updated_at: new Date().toISOString() };

            const cachedSettings = this.loadLocal('novalunch_canteen_settings', {});
            cachedSettings[key] = payload;
            this.saveLocal('novalunch_canteen_settings', cachedSettings);

            if (supabase) {
                try {
                    const { data, error } = await supabase.from('canteen_settings').upsert([payload]).select();
                    if (error) console.warn("Error updating system setting in Supabase:", error);
                    return data;
                } catch (e) {
                    console.warn("Exception updating system setting:", e);
                }
            } else {
                try {
                    return await this._postREST('canteen_settings', payload);
                } catch (e) { }
            }
            return [payload];
        },

        // -------------------------------------------------------------------------
        // PRE-ORDER SLOTS MANAGEMENT
        // -------------------------------------------------------------------------
        async getPreorderSlots() {
            const cached = this.loadLocal('novalunch_preorder_slots', null);
            let cloudSlots = [];
            if (!supabase) {
                try { cloudSlots = await this._fetchREST('preorder_slots?select=*&order=start_time.asc'); } catch (e) { }
            } else {
                try {
                    const { data, error } = await supabase.from('preorder_slots').select('*').order('start_time', { ascending: true });
                    if (!error && data) cloudSlots = data;
                } catch (e) { }
            }
            if (cloudSlots && cloudSlots.length > 0) {
                this.saveLocal('novalunch_preorder_slots', cloudSlots);
                return cloudSlots;
            }
            return cached || [];
        },

        async savePreorderSlot(slotPayload) {
            const currentSlots = this.loadLocal('novalunch_preorder_slots', []);
            const updatedSlots = [slotPayload, ...currentSlots.filter(s => s.id !== slotPayload.id)];
            this.saveLocal('novalunch_preorder_slots', updatedSlots);

            if (supabase) {
                try {
                    const { data, error } = await supabase.from('preorder_slots').upsert([slotPayload]).select();
                    if (!error && data) return data;
                } catch (e) { }
            }
            return [slotPayload];
        },

        // -------------------------------------------------------------------------
        // HARDWARE TOPOLOGY & TERMINAL MAPPINGS
        // -------------------------------------------------------------------------
        async getHardwareMappings() {
            const cached = this.loadLocal('novalunch_hardware_mappings', null);
            let cloudData = [];
            if (!supabase) {
                try { cloudData = await this._fetchREST('hardware_mappings?select=*'); } catch (e) { }
            } else {
                try {
                    const { data, error } = await supabase.from('hardware_mappings').select('*');
                    if (!error && data) cloudData = data;
                } catch (e) { }
            }

            if (cached && Array.isArray(cached) && cached.length > 0) {
                if (cloudData && cloudData.length > 0) {
                    const merged = cached.map(c => {
                        const foundCloud = cloudData.find(d => d.terminal_id === c.terminal_id);
                        return foundCloud ? { ...c, ...foundCloud, camera_device_index: c.camera_device_index, rfid_reader_port: c.rfid_reader_port } : c;
                    });
                    return merged;
                }
                return cached;
            }

            if (cloudData && cloudData.length > 0) {
                const mapped = cloudData.map(d => ({
                    terminal_id: d.terminal_id,
                    pos_register_name: d.location_name || d.pos_register_name || 'POS Counter',
                    assigned_station: d.location_name || 'Main Hall',
                    camera_device_index: 0,
                    rfid_reader_port: 'COM3',
                    is_online: d.status !== 'offline'
                }));
                this.saveLocal('novalunch_hardware_mappings', mapped);
                return mapped;
            }

            const defaults = [
                { terminal_id: 'POS-TERM-01', pos_register_name: 'Main Canteen Register 1', camera_device_index: 0, rfid_reader_port: 'COM3', assigned_station: 'Hot Kitchen', is_online: true },
                { terminal_id: 'POS-TERM-02', pos_register_name: 'Express Beverage Bar 2', camera_device_index: 1, rfid_reader_port: 'COM4', assigned_station: 'Cold Prep', is_online: true },
                { terminal_id: 'AI-KIOSK-MAIN', pos_register_name: 'Self-Service Vision Kiosk 1', camera_device_index: 0, rfid_reader_port: 'COM5', assigned_station: 'Main Hall', is_online: true }
            ];
            this.saveLocal('novalunch_hardware_mappings', defaults);
            return defaults;
        },

        async updateHardwareMapping(terminalId, payload) {
            const currentMappings = this.loadLocal('novalunch_hardware_mappings', [
                { terminal_id: 'POS-TERM-01', pos_register_name: 'Main Canteen Register 1', camera_device_index: 0, rfid_reader_port: 'COM3', assigned_station: 'Hot Kitchen', is_online: true },
                { terminal_id: 'POS-TERM-02', pos_register_name: 'Express Beverage Bar 2', camera_device_index: 1, rfid_reader_port: 'COM4', assigned_station: 'Cold Prep', is_online: true },
                { terminal_id: 'AI-KIOSK-MAIN', pos_register_name: 'Self-Service Vision Kiosk 1', camera_device_index: 0, rfid_reader_port: 'COM5', assigned_station: 'Main Hall', is_online: true }
            ]);

            const idx = currentMappings.findIndex(m => m.terminal_id === terminalId);
            if (idx >= 0) {
                currentMappings[idx] = { ...currentMappings[idx], ...payload, updated_at: new Date().toISOString() };
            } else {
                currentMappings.push({ terminal_id: terminalId, ...payload, updated_at: new Date().toISOString() });
            }
            this.saveLocal('novalunch_hardware_mappings', currentMappings);

            const dbPayload = { terminal_id: terminalId, updated_at: new Date().toISOString() };
            if (payload.status) dbPayload.status = payload.status;
            if (payload.pos_register_name) dbPayload.location_name = payload.pos_register_name;
            if (payload.location_name) dbPayload.location_name = payload.location_name;

            if (supabase) {
                try {
                    await supabase.from('hardware_mappings').upsert([dbPayload]);
                } catch (e) {
                    console.warn("Hardware mapping cloud update note:", e);
                }
            }
            return currentMappings;
        },

        // -------------------------------------------------------------------------
        // STUDENT SUBSIDIES & ALLOWANCES
        // -------------------------------------------------------------------------
        async getStudentSubsidies(studentId = null) {
            if (!supabase) {
                try {
                    return await this._fetchREST(`student_subsidies?select=*${studentId ? `&student_id=eq.${studentId}` : ''}`);
                } catch (e) { return []; }
            }
            let query = supabase.from('student_subsidies').select('*');
            if (studentId) query = query.eq('student_id', studentId);
            const { data, error } = await query;
            if (error) return [];
            return data || [];
        },

        async saveStudentSubsidy(subsidyPayload) {
            if (supabase) {
                const { data, error } = await supabase.from('student_subsidies').upsert([subsidyPayload]).select();
                if (error) throw error;
                return data;
            } else {
                return await this._postREST('student_subsidies', subsidyPayload);
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

        async logGovernanceOverride(studentId, cashierId, overrideType, reason, approvedByPin = false, cameraFrameUrl = null, originalItems = null) {
            const payload = {
                student_id: studentId,
                cashier_id: cashierId || null,
                override_type: overrideType,
                reason: reason,
                approved_by_pin: approvedByPin,
                camera_frame_url: cameraFrameUrl || null,
                original_ai_detected_items: originalItems || null,
                created_at: new Date().toISOString()
            };
            if (supabase) {
                await supabase.from('governance_overrides').insert([payload]).catch(e => console.warn("Governance override log error:", e));
            } else {
                await this._postREST('governance_overrides', payload).catch(e => console.warn("REST Governance override log error:", e));
            }
        },

        async syncOfflineTransaction(clientUuid, terminalId, studentId, amount, sequenceNum, payload) {
            if (supabase) {
                try {
                    const { data, error } = await supabase.rpc('fn_sync_offline_transaction', {
                        p_client_uuid: clientUuid,
                        p_terminal_id: terminalId,
                        p_student_id: studentId,
                        p_amount: parseFloat(amount),
                        p_sequence_num: parseInt(sequenceNum) || 1,
                        p_payload: payload || {}
                    });
                    if (!error && data) return data;
                } catch (e) {
                    console.warn("fn_sync_offline_transaction RPC fallback", e);
                }
            }
            const record = { client_uuid: clientUuid, terminal_id: terminalId, student_id: studentId, amount, sequence_num: sequenceNum, payload, status: 'SYNCED' };
            return { success: true, status: 'CLEARED_LOCAL', record };
        },

        async reconcileTuitionPayLaterBatch(studentIds, adminId = null) {
            if (supabase) {
                const { data, error } = await supabase.rpc('fn_reconcile_tuition_pay_later_batch', {
                    p_student_ids: Array.isArray(studentIds) ? studentIds : [studentIds],
                    p_admin_id: adminId
                });
                if (error) throw error;
                return data;
            }
            const batchRef = 'TUITION-BATCH-' + Date.now();
            return { success: true, batch_ref: batchRef, students_reconciled: studentIds.length, total_debt_reconciled: 0.00 };
        },

        async fetchTuitionReconciliationBatches() {
            if (!supabase) {
                try { return await this._fetchREST('tuition_reconciliation_batches?select=*&order=created_at.desc'); } catch (e) { return []; }
            }
            const { data, error } = await supabase.from('tuition_reconciliation_batches').select('*').order('created_at', { ascending: false });
            if (error) return [];
            return data || [];
        },

        async logCameraHeartbeat(terminalId, status = 'ACTIVE', fps = 30) {
            const payload = { terminal_id: terminalId, status, details: { fps, timestamp: new Date().toISOString() } };
            if (supabase) {
                await supabase.from('system_audit_logs').insert([{ actor_id: null, actor_name: terminalId, actor_role: 'HARDWARE_CAMERA', action_type: 'CAMERA_HEARTBEAT', details: payload.details }]).catch(e => { });
            }
        },

        // -------------------------------------------------------------------------
        // OPERATIONAL REMEDIATION API HELPERS
        // -------------------------------------------------------------------------
        async generateStudentDynamicQR(studentId) {
            if (supabase) {
                const { data, error } = await supabase.rpc('fn_generate_student_dynamic_qr', { p_student_id: studentId });
                if (error) throw error;
                return data;
            }
            const token = 'NL-QR-' + Math.random().toString(36).substring(2, 14).toUpperCase();
            const expiresAt = new Date(Date.now() + 60000).toISOString();
            await this.updateUser(studentId, { dynamic_qr_token: token, dynamic_qr_expires_at: expiresAt });
            return { token, expires_at: expiresAt, student_id: studentId };
        },

        async togglePayLaterPreAuth(studentId, enabled, limit = 200.00) {
            if (supabase) {
                const { error } = await supabase.rpc('fn_toggle_pay_later_pre_auth', {
                    p_student_id: studentId,
                    p_enabled: Boolean(enabled),
                    p_limit: parseFloat(limit) || 200.00
                });
                if (error) throw error;
                return { success: true };
            }
            return await this.updateUser(studentId, { pay_later_pre_authorized: Boolean(enabled), pay_later_pre_auth_limit: parseFloat(limit) || 200.00 });
        },

        async processGCashWebhook(arg1, arg2, arg3, arg4 = 'SIG-INSTANT-OK') {
            let referenceNo, userId, amount, signature;
            if (typeof arg1 === 'object' && arg1 !== null) {
                const p = arg1.payload || arg1;
                referenceNo = p.ref_no || p.reference_number || p.referenceNo || `GC-${Date.now()}`;
                userId = p.student_id || p.studentId || p.userId || p.user_id;
                amount = parseFloat(p.amount) || 0.0;
                signature = arg1.signature || arg4;
            } else {
                referenceNo = arg1;
                userId = arg2;
                amount = parseFloat(arg3) || 0.0;
                signature = arg4;
            }

            if (supabase && userId) {
                try {
                    const { data, error } = await supabase.rpc('fn_process_gcash_webhook', {
                        p_reference_no: String(referenceNo),
                        p_user_id: userId,
                        p_amount: amount,
                        p_signature: signature
                    });
                    if (!error && data) return data;
                } catch (e) {
                    console.warn("[CanteenDB] fn_process_gcash_webhook fallback", e);
                }
            }
            if (userId && amount > 0) {
                const newBal = await this.creditWalletBalance(userId, amount);
                return { success: true, reference_no: referenceNo, new_balance: newBal };
            }
            return { success: true, reference_no: referenceNo };
        },

        async fetchCategorySpendingRules(studentId) {
            if (!supabase) {
                try { return await this._fetchREST(`category_spending_rules?select=*&student_id=eq.${studentId}`); } catch (e) { return []; }
            }
            const { data, error } = await supabase.from('category_spending_rules').select('*').eq('student_id', studentId);
            if (error) return [];
            return data || [];
        },

        async saveCategorySpendingRule(parentId, studentId, categoryName, isBlocked, dailyCap = null, exemptNutrition = true) {
            const payload = {
                parent_id: parentId,
                student_id: studentId,
                category_name: categoryName,
                is_blocked: Boolean(isBlocked),
                daily_cap: dailyCap !== null ? parseFloat(dailyCap) : null,
                exempt_nutrition_meals: Boolean(exemptNutrition),
                updated_at: new Date().toISOString()
            };
            if (supabase) {
                const { data, error } = await supabase.from('category_spending_rules').upsert([payload]).select();
                if (error) throw error;
                return data;
            } else {
                return await this._postREST('category_spending_rules', payload);
            }
        },

        async submitMealDispute(arg1, arg2, arg3, arg4, arg5 = null) {
            let orderId, parentId, studentId, reason, details, photoUrl;
            if (typeof arg1 === 'object' && arg1 !== null) {
                orderId = arg1.order_id || arg1.orderId || null;
                parentId = arg1.parent_id || arg1.parentId || null;
                studentId = arg1.student_id || arg1.studentId || null;
                reason = arg1.reason || arg1.dispute_reason || 'AI Tray Recognition Error';
                details = arg1.details || arg1.reason_details || '';
                photoUrl = arg1.photo_url || arg1.photoUrl || null;
            } else {
                orderId = arg1;
                parentId = arg2;
                studentId = arg3;
                reason = arg4;
                photoUrl = arg5;
                details = '';
            }

            const payload = {
                order_id: String(orderId || `ORD-${Date.now()}`),
                student_id: studentId && this.isUUID(studentId) ? studentId : null,
                parent_id: parentId && this.isUUID(parentId) ? parentId : null,
                dispute_reason: reason || 'AI Tray Recognition Error',
                details: details || '',
                photo_url: photoUrl || null,
                status: 'PENDING',
                created_at: new Date().toISOString()
            };

            if (supabase) {
                const { data, error } = await supabase.from('meal_disputes').insert([payload]).select().single();
                if (error) {
                    console.warn("[CanteenDB] Supabase meal dispute write notice:", error?.message);
                }
                return data || payload;
            } else {
                const res = await this._postREST('meal_disputes', payload).catch(e => [payload]);
                return res[0] || payload;
            }
        },

        async createMealDispute(payload) {
            return await this.submitMealDispute(payload);
        },

        async fetchMealDisputes(parentId = null) {
            if (!supabase) {
                try { return await this._fetchREST(`meal_disputes?select=*${parentId ? `&parent_id=eq.${parentId}` : ''}`); } catch (e) { return []; }
            }
            let query = supabase.from('meal_disputes').select('*').order('created_at', { ascending: false });
            if (parentId) query = query.eq('parent_id', parentId);
            const { data, error } = await query;
            if (error) return [];
            return data || [];
        },

        async getMealDisputes(parentId = null) {
            return await this.fetchMealDisputes(parentId);
        },

        async resolveMealDispute(disputeId, action, adminNotes = '', adminId = null, refundAmount = 0, studentId = null) {
            const isApproved = action === 'APPROVED' || action === 'APPROVED_REFUND';
            const finalStatus = isApproved ? 'APPROVED' : 'REJECTED';
            const payload = {
                status: finalStatus,
                admin_notes: adminNotes || (isApproved ? 'Approved by Admin' : 'Rejected per policy'),
                resolved_at: new Date().toISOString()
            };

            let updateResult = null;
            if (supabase) {
                try {
                    const { data } = await supabase.from('meal_disputes').update(payload).eq('id', disputeId).select().single();
                    updateResult = data;
                } catch (e) {
                    console.warn('[CanteenDB] resolveMealDispute fallback:', e);
                }
            } else {
                try {
                    updateResult = await this._patchREST(`meal_disputes?id=eq.${disputeId}`, payload);
                } catch (e) { }
            }

            if (isApproved && refundAmount > 0 && studentId) {
                await this.creditWalletBalance(studentId, refundAmount).catch(e => console.warn("Refund wallet credit error", e));
                await this.logSystemAudit(adminId, 'Admin Manager', 'ADMIN', 'DISPUTE_REFUND_APPROVED', {
                    disputeId,
                    studentId,
                    amount: refundAmount,
                    notes: adminNotes
                }).catch(e => { });
            } else {
                await this.logSystemAudit(adminId, 'Admin Manager', 'ADMIN', 'DISPUTE_REJECTED', {
                    disputeId,
                    notes: adminNotes
                }).catch(e => { });
            }

            return updateResult || { id: disputeId, ...payload };
        },

        async processUnifiedRefund({ refundId, disputeId = null, orderId = null, studentId, amount, reason, reasonCategory = 'MANUAL_REFUND', method = 'RFID_WALLET', restocked = false, productId = null, adminId = null, adminName = 'Admin' }) {
            const refundAmt = parseFloat(amount) || 0;
            if (refundAmt <= 0) throw new Error('Refund amount must be greater than zero.');

            let newBalance = null;
            if (method === 'RFID_WALLET' && studentId) {
                newBalance = await this.creditWalletBalance(studentId, refundAmt);
            }

            if (restocked && productId) {
                try {
                    if (supabase) {
                        await supabase.rpc('fn_increment_product_stock', { p_product_id: productId, p_qty: 1 });
                    }
                } catch (e) {
                    console.warn('[CanteenDB] Product restock RPC notice:', e);
                }
            }

            if (orderId) {
                try {
                    await this.updateOrderStatus(orderId, 'REFUNDED');
                } catch (e) { }
            }

            if (disputeId) {
                try {
                    await this.resolveMealDispute(disputeId, 'APPROVED', reason, adminId, 0, null);
                } catch (e) { }
            }

            await this.logSystemAudit(adminId, adminName, 'ADMIN', 'REFUND_PROCESSED', {
                refundId,
                orderId,
                disputeId,
                studentId,
                amount: refundAmt,
                method,
                reason,
                reasonCategory,
                restocked
            }).catch(e => { });

            return {
                success: true,
                refundId,
                newBalance,
                status: 'APPROVED',
                processedAt: new Date().toISOString()
            };
        },

        async createSISTuitionBatch(adminId) {
            if (supabase) {
                const { data, error } = await supabase.rpc('fn_create_sis_tuition_batch', { p_admin_id: adminId });
                if (error) throw error;
                return data;
            }
            const batchCode = 'SIS-BATCH-' + Date.now();
            const payload = { batch_code: batchCode, total_amount: 1250.00, student_count: 5, status: 'EXPORTED' };
            return payload;
        },

        async fetchSISTuitionBatches() {
            if (!supabase) {
                try { return await this._fetchREST('sis_tuition_batches?select=*&order=created_at.desc'); } catch (e) { return []; }
            }
            const { data, error } = await supabase.from('sis_tuition_batches').select('*, sis_tuition_batch_items(*)').order('created_at', { ascending: false });
            if (error) return [];
            return data || [];
        },

        async submitShiftReconciliation(cashierId, declaredCash, systemCash, digitalTotal, notes = '') {
            const declared = parseFloat(declaredCash) || 0;
            const system = parseFloat(systemCash) || 0;
            const variance = declared - system;
            const payload = {
                cashier_id: cashierId,
                declared_cash: declared,
                system_cash: system,
                digital_total: parseFloat(digitalTotal) || 0,
                variance: variance,
                notes: notes,
                created_at: new Date().toISOString()
            };
            if (supabase) {
                const { data, error } = await supabase.from('cashier_shift_reconciliations').insert([payload]).select().single();
                if (error) throw error;
                return data;
            } else {
                const res = await this._postREST('cashier_shift_reconciliations', payload);
                return res[0];
            }
        },

        async fetchShiftReconciliations() {
            if (!supabase) {
                try { return await this._fetchREST('cashier_shift_reconciliations?select=*&order=created_at.desc'); } catch (e) { return []; }
            }
            const { data, error } = await supabase.from('cashier_shift_reconciliations').select('*, cashier:profiles!cashier_id(full_name)').order('created_at', { ascending: false });
            if (error) return [];
            return data || [];
        },

        async logSystemAudit(actorId, actorName, actorRole, actionType, details = {}) {
            const payload = {
                actor_id: actorId || null,
                actor_name: actorName || 'System',
                actor_role: actorRole || 'ADMIN',
                action_type: actionType,
                details: details,
                created_at: new Date().toISOString()
            };
            if (supabase) {
                await supabase.from('system_audit_logs').insert([payload]).catch(e => console.warn("System audit log error:", e));
            } else {
                await this._postREST('system_audit_logs', payload).catch(e => console.warn("REST System audit log error:", e));
            }
        },

        async fetchSystemAuditLogs() {
            if (!supabase) {
                try { return await this._fetchREST('system_audit_logs?select=*&order=created_at.desc&limit=50'); } catch (e) { return []; }
            }
            const { data, error } = await supabase.from('system_audit_logs').select('*').order('created_at', { ascending: false }).limit(50);
            if (error) return [];
            return data || [];
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
            } catch (err) {
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
            } catch (err) {
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
            } catch (err) {
                console.warn(`[CanteenDB REST Patch Error] ${endpoint}:`, err);
                throw err;
            }
        },

        async _deleteREST(endpoint) {
            try {
                const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
                    method: "DELETE",
                    headers: {
                        "apikey": SUPABASE_ANON_KEY,
                        "Authorization": `Bearer ${SUPABASE_ANON_KEY}`
                    }
                });
                if (!res.ok) {
                    const errBody = await res.json().catch(() => ({ message: res.statusText }));
                    throw new Error(errBody.message || `Database delete failed (${res.status})`);
                }
                return true;
            } catch (err) {
                console.warn(`[CanteenDB REST Delete Error] ${endpoint}:`, err);
                throw err;
            }
        },

        getClient() {
            return supabase;
        }
    };

    // Export to window scope
    if (typeof window !== 'undefined') {
        window.SUPABASE_URL = SUPABASE_URL;
        window.SUPABASE_ANON_KEY = SUPABASE_ANON_KEY;
        window.CanteenDB = CanteenDB;
    }
})(typeof window !== 'undefined' ? window : this);
