/**
 * NOVALUNCH CANTEEN — PARENT PORTAL JAVASCRIPT
 * Features:
 * - GCash Top-Up submission with receipt photo proof
 * - Real-time Visual Tray Feed snapshots
 * - Advance meal reservation pre-orders
 * - Balance & dietary expenditure logs
 */

import { submitGCashTopup, createPreOrder, localStore } from './firebase-config.js';

document.addEventListener('DOMContentLoaded', () => {
    const gcashForm = document.getElementById('gcashForm');
    const topupAlert = document.getElementById('topupAlert');
    const btnQuickTopup = document.getElementById('btnQuickTopup');

    // 1. Quick GCash Topup Scroll / Trigger
    if (btnQuickTopup) {
        btnQuickTopup.addEventListener('click', () => {
            const sec = document.getElementById('topupSection');
            if (sec) sec.scrollIntoView({ behavior: 'smooth' });
        });
    }

    // 2. Submit GCash Topup Proof
    if (gcashForm) {
        gcashForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const studentId = document.getElementById('topupStudentId').value;
            const amount = document.getElementById('topupAmount').value;
            const fileInput = document.getElementById('topupFile');
            const file = fileInput.files[0];

            try {
                const res = await submitGCashTopup("parent_maria", studentId, amount, file || "mock_receipt_url");
                if (topupAlert) {
                    topupAlert.style.display = 'block';
                    topupAlert.textContent = `✅ Top-up request for ₱${amount} submitted! Top-Up ID: ${res.topup_id}. Awaiting Canteen Admin verification.`;
                }
                gcashForm.reset();
            } catch (err) {
                alert("Failed to submit top-up: " + err.message);
            }
        });
    }

    // 3. Pre-order meal reservation handlers
    const reserveButtons = document.querySelectorAll('.btn-reserve-meal');
    const preorderDateTabs = document.querySelectorAll('#preorderDateTabs button');
    let selectedOrderDate = '2026-07-29';

    preorderDateTabs.forEach(tab => {
        tab.addEventListener('click', () => {
            preorderDateTabs.forEach(t => t.classList.remove('active'));
            tab.classList.add('active');
            selectedOrderDate = tab.dataset.date;
        });
    });

    reserveButtons.forEach(btn => {
        btn.addEventListener('click', async () => {
            const itemName = btn.dataset.item;
            const price = parseFloat(btn.dataset.price);

            const result = await createPreOrder("2023-01900", selectedOrderDate, [{
                item_name: itemName,
                unit_price: price,
                qty: 1
            }]);

            alert(`🎉 Pre-order reserved for ${selectedOrderDate}!\nMeal: ${itemName} (₱${price.toFixed(2)})\nPre-Order ID: ${result.pre_order_id}`);
        });
    });
});
