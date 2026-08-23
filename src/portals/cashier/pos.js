/**
 * NOVALUNCH CANTEEN POS — CASHIER PORTAL LOGIC
 * Features:
 * - 13.56MHz RFID Reader Input Listener (Keystroke wedge / tap lookup)
 * - Real-time YOLO Vision Camera Stream & Cart Sync (FR-05)
 * - Pay Later Credit Mode Tagging for Financial Aid (FR-07)
 * - Mobile Pre-Order Claim Alert Handler (FR-06)
 * - Firebase Backend Sync & Offline Edge Fallback
 * - Cashier Verification Controls (manual override, key-in deletion, qty +/-)
 */

import { 
    getStudentByRfid, updateStudentBalance, recordTransaction, localStore, claimPreOrder 
} from './firebase-config.js';

document.addEventListener('DOMContentLoaded', () => {
    // Initial State
    const state = {
        cart: [],
        currentStudent: {
            student_id: "2023-01900",
            full_name: "Juan Dela Cruz",
            grade_level: 11,
            rfid_tag_hash: "9A-4F-21-C8",
            credit_balance: 350.00,
            daily_spent_today: 45.00,
            daily_spend_limit: 200.00,
            pay_later_allowance: true,
            pay_later_balance: 0.00
        },
        selectedCategory: 'all',
        selectedPayment: 'rfid', // default RFID
        aiTrayItems: []
    };

    // BroadcastChannel for Secondary Student Display Monitor
    const studentDisplayChannel = new BroadcastChannel('novalunch_student_display');

    function syncStudentDisplay() {
        studentDisplayChannel.postMessage({
            type: 'CART_UPDATE',
            cart: state.cart,
            student: state.currentStudent,
            subtotal: state.cart.reduce((sum, item) => sum + (item.price * item.qty), 0)
        });
    }

    // DOM Elements
    const productCards = document.querySelectorAll('.product-card');
    const categoryTabs = document.querySelectorAll('.tab-btn');
    const cartItemsContainer = document.getElementById('cartItemsContainer');
    const subtotalEl = document.getElementById('subtotalVal');
    const discountEl = document.getElementById('discountVal');
    const grandTotalEl = document.getElementById('grandTotalVal');
    const checkoutBtn = document.getElementById('checkoutBtn');
    const searchInput = document.getElementById('searchInput');
    const clearCartBtn = document.getElementById('clearCartBtn');
    const paymentButtons = document.querySelectorAll('.pay-btn');

    // Modals
    const aiModal = document.getElementById('aiModal');
    const loadAiBtn = document.getElementById('loadAiBtn');
    const loadAiBtn2 = document.getElementById('loadAiBtn2');
    const confirmAiBtn = document.getElementById('confirmAiBtn');
    const closeAiModalBtn = document.getElementById('closeAiModalBtn');

    const receiptModal = document.getElementById('receiptModal');
    const closeReceiptModalBtn = document.getElementById('closeReceiptModalBtn');

    // 1. Category Filtering
    categoryTabs.forEach(tab => {
        tab.addEventListener('click', () => {
            categoryTabs.forEach(t => t.classList.remove('active'));
            tab.classList.add('active');
            state.selectedCategory = tab.dataset.category;
            filterProducts();
        });
    });

    // 2. Search Input
    if (searchInput) {
        searchInput.addEventListener('input', (e) => {
            filterProducts(e.target.value.toLowerCase().trim());
        });
    }

    function filterProducts(query = '') {
        productCards.forEach(card => {
            const category = card.dataset.category;
            const name = card.dataset.name.toLowerCase();

            const matchesCategory = (state.selectedCategory === 'all' || category === state.selectedCategory);
            const matchesQuery = (name.includes(query));

            if (matchesCategory && matchesQuery) {
                card.style.display = 'flex';
            } else {
                card.style.display = 'none';
            }
        });
    }

    // 3. Add Product to Cart
    productCards.forEach(card => {
        card.addEventListener('click', () => {
            const id = card.dataset.id;
            const name = card.dataset.name;
            const price = parseFloat(card.dataset.price);

            addToCart(id, name, price);
        });
    });

    function addToCart(id, name, price) {
        const existing = state.cart.find(item => item.id === id);
        if (existing) {
            existing.qty += 1;
        } else {
            state.cart.push({ id, name, price, qty: 1 });
        }
        renderCart();
    }

    // 4. Render Cart Items (with Cashier verification & item deletion controls)
    function renderCart() {
        if (!cartItemsContainer) return;

        cartItemsContainer.innerHTML = '';

        if (state.cart.length === 0) {
            cartItemsContainer.innerHTML = `
                <div style="text-align:center; padding: 40px 10px; color: var(--text-muted);">
                    <div style="font-size: 32px; margin-bottom: 8px;">🛒</div>
                    <p style="font-size: 13px; font-weight: 500;">Cart is empty</p>
                    <span style="font-size: 11px;">Select items or scan RFID badge to begin</span>
                </div>
            `;
            updateTotals();
            syncStudentDisplay();
            return;
        }

        state.cart.forEach((item, index) => {
            const row = document.createElement('div');
            row.className = 'cart-item-row';
            row.style.cssText = "display:flex; justify-style:space-between; align-items:center; padding:10px; border-bottom:1px solid var(--border-color);";
            row.innerHTML = `
                <div class="item-details" style="flex:1;">
                    <h5 style="font-size:14px; font-weight:700; margin:0;">${item.name}</h5>
                    <p style="font-size:12px; color:var(--text-secondary); margin:2px 0 0 0;">₱${item.price.toFixed(2)} each</p>
                </div>
                <div class="qty-control" style="display:flex; align-items:center; gap:6px;">
                    <button class="btn-qty btn-minus" data-index="${index}" style="width:26px; height:26px; border-radius:4px; border:1px solid #ccc; background:#fff; cursor:pointer;">-</button>
                    <span class="qty-val" style="font-size:13px; font-weight:700; min-width:18px; text-align:center;">${item.qty}</span>
                    <button class="btn-qty btn-plus" data-index="${index}" style="width:26px; height:26px; border-radius:4px; border:1px solid #ccc; background:#fff; cursor:pointer;">+</button>
                </div>
                <div class="item-line-total" style="font-size:14px; font-weight:800; min-width:70px; text-align:right;">
                    ₱${(item.price * item.qty).toFixed(2)}
                </div>
                <button class="btn-del-item" data-index="${index}" style="background:none; border:none; color:#ef4444; font-size:16px; cursor:pointer; margin-left:8px;" title="Delete Item">🗑️</button>
            `;
            cartItemsContainer.appendChild(row);
        });

        // Event listeners for quantity adjustments & deletion
        document.querySelectorAll('.btn-minus').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const idx = parseInt(btn.dataset.index);
                if (state.cart[idx].qty > 1) {
                    state.cart[idx].qty -= 1;
                } else {
                    state.cart.splice(idx, 1);
                }
                renderCart();
            });
        });

        document.querySelectorAll('.btn-plus').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const idx = parseInt(btn.dataset.index);
                state.cart[idx].qty += 1;
                renderCart();
            });
        });

        document.querySelectorAll('.btn-del-item').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const idx = parseInt(btn.dataset.index);
                state.cart.splice(idx, 1);
                renderCart();
            });
        });

        updateTotals();
        syncStudentDisplay();
    }

    // 5. Update Cart Totals
    function updateTotals() {
        const subtotal = state.cart.reduce((sum, item) => sum + (item.price * item.qty), 0);
        const discount = 0.00;
        const grandTotal = subtotal - discount;

        if (subtotalEl) subtotalEl.textContent = `₱${subtotal.toFixed(2)}`;
        if (discountEl) discountEl.textContent = `₱${discount.toFixed(2)}`;
        if (grandTotalEl) grandTotalEl.textContent = `₱${grandTotal.toFixed(2)}`;
    }

    // 6. Clear Cart
    if (clearCartBtn) {
        clearCartBtn.addEventListener('click', () => {
            state.cart = [];
            renderCart();
        });
    }

    // 7. Payment Method Selector
    paymentButtons.forEach(btn => {
        btn.addEventListener('click', () => {
            paymentButtons.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            state.selectedPayment = btn.dataset.method;
        });
    });

    // 8. RFID Hardware USB Keyboard Wedge Reader Listener
    let rfidBuffer = '';
    let rfidTimer = null;

    document.addEventListener('keydown', (e) => {
        // If typing in search box, bypass RFID handler
        if (document.activeElement === searchInput) return;

        if (e.key === 'Enter') {
            if (rfidBuffer.length >= 4) {
                handleRfidTap(rfidBuffer.trim());
            }
            rfidBuffer = '';
        } else if (e.key.length === 1) {
            rfidBuffer += e.key;
            clearTimeout(rfidTimer);
            rfidTimer = setTimeout(() => { rfidBuffer = ''; }, 500);
        }
    });

    async function handleRfidTap(rfidCode) {
        const student = await getStudentByRfid(rfidCode);
        if (student) {
            state.currentStudent = student;
            updateStudentUI();
            alert(`💳 RFID Tag Read: ${student.full_name} (${student.student_id}) authenticated! Balance: ₱${student.credit_balance.toFixed(2)}`);
        }
    }

    function updateStudentUI() {
        const nameEl = document.getElementById('studentName');
        const lrnEl = document.getElementById('studentLrn');
        const balEl = document.getElementById('studentBalanceVal');
        const spentEl = document.getElementById('studentSpentVal');

        if (nameEl) nameEl.textContent = state.currentStudent.full_name;
        if (lrnEl) lrnEl.textContent = `ID: ${state.currentStudent.student_id} • Grade ${state.currentStudent.grade_level}`;
        if (balEl) balEl.textContent = `₱${state.currentStudent.credit_balance.toFixed(2)}`;
        if (spentEl) spentEl.textContent = `₱${state.currentStudent.daily_spent_today.toFixed(2)} / ₱${state.currentStudent.daily_spend_limit.toFixed(2)}`;
    }

    // 9. AI Vision Camera Trigger & Real-Time Python Kiosk Sync (FR-05)
    let isKioskLive = false;
    const triggerAiScan = async () => {
        try {
            const res = await fetch('http://localhost:8085/api/scan_tray');
            const data = await res.json();
            if (data.status === 'SUCCESS' && data.cart) {
                state.aiTrayItems = data.cart;
                if (data.student) {
                    state.currentStudent = {
                        student_id: data.student.id,
                        full_name: data.student.name,
                        grade_level: 11,
                        rfid_tag_hash: data.student.rfidUid || "9A-4F-21-C8",
                        credit_balance: data.student.balance || 200.00,
                        daily_spent_today: 0.00,
                        daily_spend_limit: data.student.daily_limit || 200.00,
                        pay_later_allowance: true,
                        pay_later_balance: 0.00
                    };
                    updateStudentUI();
                }
            }
        } catch (e) {
            console.warn("Using default simulated AI tray items", e);
            state.aiTrayItems = [
                { id: 'a1111111-1111-1111-1111-111111111111', name: 'Buttercream Biscuits', price: 35.00, confidence: 0.98 },
                { id: 'a4444444-4444-4444-4444-444444444444', name: 'Jack & Jill Magic Chips', price: 25.00, confidence: 0.96 }
            ];
        }
        if (aiModal) aiModal.classList.add('active');
    };

    // Real-Time EventSource Listener to Python Kiosk
    function initKioskRealtimeSync() {
        try {
            const es = new EventSource('http://localhost:8085/api/kiosk/events');
            es.addEventListener('kiosk_update', (e) => {
                try {
                    const data = JSON.parse(e.data);
                    isKioskLive = true;
                    if (data.cart && data.cart.length > 0) {
                        state.aiTrayItems = data.cart;
                    }
                    if (data.student) {
                        state.currentStudent = {
                            student_id: data.student.id,
                            full_name: data.student.name,
                            grade_level: 11,
                            rfid_tag_hash: data.student.rfidUid || "9A-4F-21-C8",
                            credit_balance: data.student.balance || 200.00,
                            daily_spent_today: 0.00,
                            daily_spend_limit: data.student.daily_limit || 200.00,
                            pay_later_allowance: true,
                            pay_later_balance: 0.00
                        };
                        updateStudentUI();
                    }
                } catch (err) {
                    console.warn('[POS KIOSK SYNC] Parse error:', err);
                }
            });
            es.onerror = () => {
                isKioskLive = false;
            };
            window.addEventListener('beforeunload', () => {
                try { es.close(); } catch (e) { }
            });
        } catch (err) {
            console.log('[POS KIOSK SYNC] EventSource unavailable, using manual trigger');
        }
    }
    initKioskRealtimeSync();

    if (loadAiBtn) loadAiBtn.addEventListener('click', triggerAiScan);
    if (loadAiBtn2) loadAiBtn2.addEventListener('click', triggerAiScan);

    if (closeAiModalBtn) {
        closeAiModalBtn.addEventListener('click', () => {
            if (aiModal) aiModal.classList.remove('active');
        });
    }

    if (confirmAiBtn) {
        confirmAiBtn.addEventListener('click', () => {
            state.aiTrayItems.forEach(item => {
                addToCart(item.item_id || item.id, item.item_name || item.name, item.price);
            });
            if (aiModal) aiModal.classList.remove('active');
        });
    }

    // 10. Checkout & Firebase Record Processing
    if (checkoutBtn) {
        checkoutBtn.addEventListener('click', async () => {
            if (state.cart.length === 0) {
                alert('Please add items to the cart before processing payment.');
                return;
            }

            const grandTotal = state.cart.reduce((sum, item) => sum + (item.price * item.qty), 0);
            let payMethodEnum = "RFID_CREDIT";

            if (state.selectedPayment === 'rfid') {
                payMethodEnum = "RFID_CREDIT";
                if (state.currentStudent.credit_balance < grandTotal) {
                    alert(`Insufficient RFID wallet balance! Current balance: ₱${state.currentStudent.credit_balance.toFixed(2)}. Switch to Pay Later or Cash.`);
                    return;
                }
                state.currentStudent.credit_balance -= grandTotal;
                state.currentStudent.daily_spent_today += grandTotal;
                await updateStudentBalance(
                    state.currentStudent.student_id, 
                    state.currentStudent.credit_balance, 
                    state.currentStudent.daily_spent_today
                );
                updateStudentUI();
            } else if (state.selectedPayment === 'paylater') {
                payMethodEnum = "PAY_LATER";
                if (!state.currentStudent.pay_later_allowance) {
                    alert(`Pay Later credit mode is not approved for ${state.currentStudent.full_name}. Select RFID or Cash.`);
                    return;
                }
                const currentPayLaterCount = state.currentStudent.pay_later_count || 0;
                if (currentPayLaterCount >= 5) {
                    alert(`🚫 Pay Later Limit Reached (5/5 Transactions Used)!\n\n${state.currentStudent.full_name} has already utilized all 5 allowed emergency Pay Later transactions. Existing debt must be settled before new credit can be issued.`);
                    return;
                }
                const currentDebt = state.currentStudent.pay_later_balance || 0.0;
                const newDebt = currentDebt + grandTotal;
                if (newDebt > 1000.00) {
                    const proceed = confirm(`⚠️ PAY LATER NOTICE: Cumulative Pay Later balance for ${state.currentStudent.full_name} will reach ₱${newDebt.toFixed(2)}, which exceeds the standard ₱1,000.00 threshold (${currentPayLaterCount + 1}/5 used).\n\nIs it okay to proceed with this Pay Later transaction?`);
                    if (!proceed) return;
                }
                state.currentStudent.pay_later_balance = newDebt;
                state.currentStudent.pay_later_count = currentPayLaterCount + 1;
                await updateStudentBalance(
                    state.currentStudent.student_id, 
                    state.currentStudent.credit_balance, 
                    state.currentStudent.daily_spent_today, 
                    state.currentStudent.pay_later_balance
                );
                alert(`🤝 Transaction tagged under Pay Later allowance for ${state.currentStudent.full_name} (${state.currentStudent.pay_later_count}/5 used). Outstanding credit: ₱${state.currentStudent.pay_later_balance.toFixed(2)}`);
            } else if (state.selectedPayment === 'salary_deduction') {
                payMethodEnum = "SALARY_DEDUCTION";
                state.currentStudent.salary_deduction_balance = (state.currentStudent.salary_deduction_balance || 0) + grandTotal;
                alert(`💼 Transaction charged to Faculty/Staff Salary Deduction for ${state.currentStudent.full_name}. Accumulated: ₱${state.currentStudent.salary_deduction_balance.toFixed(2)}`);
            } else {
                payMethodEnum = "CASH_BACKUP";
            }

            // Save to Firebase backend
            const txnRecord = await recordTransaction({
                student_id: state.currentStudent.student_id,
                items: state.cart,
                total_amount: grandTotal,
                payment_method: payMethodEnum,
                tray_image_url: "https://firebasestorage.googleapis.com/v0/b/novalunch.appspot.com/o/trays%2Fsample_tray_01.jpg?alt=media"
            });

            showReceipt(grandTotal, payMethodEnum, txnRecord.transaction_id);
        });
    }

    function showReceipt(total, payMethod, txnId) {
        if (receiptDetails) {
            const payMethodLabels = {
                RFID_CREDIT: '💳 RFID Wallet Credit',
                CASH_BACKUP: '💵 Cash Backup',
                PAY_LATER: '🤝 Pay Later Credit Mode (Financial Aid)',
                SALARY_DEDUCTION: '💼 Faculty / Staff Salary Deduction'
            };

            let itemsHtml = state.cart.map(i => `
                <div style="display:flex; justify-content:space-between; font-size:13px; padding: 4px 0;">
                    <span>${i.qty}x ${i.name}</span>
                    <span style="font-weight:700;">₱${(i.price * i.qty).toFixed(2)}</span>
                </div>
            `).join('');

            receiptDetails.innerHTML = `
                <div style="text-align:center; padding-bottom:12px; border-bottom:1px dashed #ccc; margin-bottom:12px;">
                    <div style="font-size:20px; color:var(--primary); font-weight:800;">St. Joseph College Canteen</div>
                    <div style="font-size:11px; color:#666;">Official Receipt • Txn ID: ${txnId}</div>
                    <div style="font-size:11px; color:#888;">${new Date().toLocaleString()}</div>
                </div>

                <div style="font-size:12px; margin-bottom:10px;">
                    <strong>Customer:</strong> ${state.currentStudent.full_name} (${state.currentStudent.student_id})<br>
                    <strong>Payment Mode:</strong> ${payMethodLabels[payMethod]}
                </div>

                <div style="margin-bottom:12px;">${itemsHtml}</div>

                <div style="border-top:2px solid var(--primary); padding-top:8px; display:flex; justify-content:space-between; font-size:16px; font-weight:800; color:var(--primary);">
                    <span>Total Paid:</span>
                    <span>₱${total.toFixed(2)}</span>
                </div>

                <div style="margin-top:12px; padding-top:8px; border-top:1px dashed #ccc; text-align:center; font-size:10px; color:#666;">
                    <strong>🔒 Policy Notice:</strong> Cooked lunch meals are strictly non-refundable once served.<br>
                    Thank you for dining at NovaLunch!
                </div>
            `;
        }

        if (receiptModal) receiptModal.classList.add('active');

        // Reset cart & sync student display
        state.cart = [];
        renderCart();
    }

    if (closeReceiptModalBtn) {
        closeReceiptModalBtn.addEventListener('click', () => {
            if (receiptModal) receiptModal.classList.remove('active');
        });
    }

    // Initialize UI
    updateStudentUI();
    renderCart();
});
