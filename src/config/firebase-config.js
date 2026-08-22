/**
 * NovaLunch — Firebase Integration Engine & Edge Sync Client
 * Centralized Firebase Realtime Database & Cloud Storage API
 */

import { initializeApp } from "https://www.gstatic.com/firebasejs/10.7.1/firebase-app.js";
import { 
    getDatabase, ref, set, get, update, push, onValue, query, orderByChild, equalTo, runTransaction
} from "https://www.gstatic.com/firebasejs/10.7.1/firebase-database.js";
import { 
    getStorage, ref as storageRef, uploadBytes, getDownloadURL 
} from "https://www.gstatic.com/firebasejs/10.7.1/firebase-storage.js";

// Firebase configuration for NovaLunch
const firebaseConfig = {
    apiKey: "AIzaSyB_NOVALUNCH_DEMO_KEY_2026",
    authDomain: "novalunch-stjoseph.firebaseapp.com",
    databaseURL: "https://novalunch-stjoseph-default-rtdb.firebaseio.com",
    projectId: "novalunch-stjoseph",
    storageBucket: "novalunch-stjoseph.appspot.com",
    messagingSenderId: "987654321012",
    appId: "1:987654321012:web:novalunch2026key"
};

// Initialize Firebase App
const app = initializeApp(firebaseConfig);
export const db = getDatabase(app);
export const storage = getStorage(app);

// Local State Store / Edge Cache
export const localStore = {
    students: {
        "2023-01900": {
            student_id: "2023-01900",
            full_name: "Juan Dela Cruz",
            grade_level: 11,
            rfid_tag_hash: "9A-4F-21-C8",
            credit_balance: 350.00,
            pay_later_allowance: true,
            pay_later_balance: 0.00,
            daily_spend_limit: 200.00,
            daily_spent_today: 45.00
        },
        "2023-01901": {
            student_id: "2023-01901",
            full_name: "Maria Santos",
            grade_level: 10,
            rfid_tag_hash: "3B-12-89-FA",
            credit_balance: 180.50,
            pay_later_allowance: false,
            pay_later_balance: 0.00,
            daily_spend_limit: 150.00,
            daily_spent_today: 0.00
        }
    },
    transactions: [],
    preOrders: [],
    gcashTopups: []
};

// =====================================
// 1. STUDENTS API
// =====================================
export async function getStudentByRfid(rfidTag) {
    try {
        const studentRef = ref(db, 'students');
        const q = query(studentRef, orderByChild('rfid_tag_hash'), equalTo(rfidTag));
        const snapshot = await get(q);
        if (snapshot.exists()) {
            const data = snapshot.val();
            const key = Object.keys(data)[0];
            return data[key];
        }
    } catch (e) {
        console.warn("Firebase offline or unreachable, checking local edge cache...", e);
    }
    // Edge cache lookup
    return Object.values(localStore.students).find(s => s.rfid_tag_hash === rfidTag || s.student_id === rfidTag);
}

export async function updateStudentBalance(studentId, newBalance, newSpentToday = null, newPayLater = null) {
    const studentRef = ref(db, `students/std_${studentId.replace('-', '_')}`);
    try {
        await runTransaction(studentRef, (currentData) => {
            if (currentData) {
                currentData.credit_balance = newBalance;
                if (newSpentToday !== null) currentData.daily_spent_today = newSpentToday;
                if (newPayLater !== null) currentData.pay_later_balance = newPayLater;
                return currentData;
            }
            return {
                student_id: studentId,
                credit_balance: newBalance,
                daily_spent_today: newSpentToday || 0,
                pay_later_balance: newPayLater || 0
            };
        });
    } catch (e) {
        console.warn("Firebase transaction update pending connection. Updated in local store.", e);
    }

    if (localStore.students[studentId]) {
        localStore.students[studentId].credit_balance = newBalance;
        if (newSpentToday !== null) localStore.students[studentId].daily_spent_today = newSpentToday;
        if (newPayLater !== null) localStore.students[studentId].pay_later_balance = newPayLater;
    }
}

// =====================================
// 2. TRANSACTIONS API
// =====================================
export async function recordTransaction(txnData) {
    const txnId = `txn_${Date.now()}`;
    const payload = {
        timestamp: new Date().toISOString(),
        student_id: txnData.student_id,
        items_purchased: txnData.items,
        total_amount: txnData.total_amount,
        payment_method: txnData.payment_method, // "RFID_CREDIT" | "PAY_LATER" | "CASH_BACKUP"
        tray_image_url: txnData.tray_image_url || "",
        sync_status: navigator.onLine ? "SYNCED" : "EDGE_CACHED"
    };

    try {
        if (navigator.onLine) {
            await set(ref(db, `transactions/${txnId}`), payload);
        } else {
            // Push to python backend offline edge SQLite buffer
            await fetch('http://localhost:8085/api/cache_offline', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ transaction_id: txnId, ...payload })
            });
        }
    } catch (e) {
        console.warn("Network error during transaction, stored locally.", e);
    }

    localStore.transactions.unshift({ transaction_id: txnId, ...payload });
    return { transaction_id: txnId, ...payload };
}

// =====================================
// 3. PRE-ORDERS API
// =====================================
export async function createPreOrder(studentId, orderDate, items) {
    const preOrderId = `ord_${Date.now()}`;
    const payload = {
        student_id: studentId,
        order_date: orderDate,
        items: items,
        status: "PENDING", // "PENDING" | "CLAIMED" | "CANCELLED"
        claim_timestamp: null
    };

    try {
        await set(ref(db, `pre_orders/${preOrderId}`), payload);
    } catch (e) {
        console.warn("Using local store for pre-order", e);
    }

    localStore.preOrders.unshift({ pre_order_id: preOrderId, ...payload });
    return { pre_order_id: preOrderId, ...payload };
}

export async function claimPreOrder(preOrderId) {
    const updates = {
        status: "CLAIMED",
        claim_timestamp: new Date().toISOString()
    };
    try {
        await update(ref(db, `pre_orders/${preOrderId}`), updates);
    } catch (e) {
        console.warn("Local update claim", e);
    }
}

// =====================================
// 4. GCASH TOP-UPS API
// =====================================
export async function submitGCashTopup(parentId, studentId, amount, receiptFileOrUrl) {
    const topupId = `top_${Date.now()}`;
    let receiptUrl = typeof receiptFileOrUrl === 'string' ? receiptFileOrUrl : "";

    if (receiptFileOrUrl instanceof File) {
        try {
            const fileRef = storageRef(storage, `receipts/${topupId}_${receiptFileOrUrl.name}`);
            await uploadBytes(fileRef, receiptFileOrUrl);
            receiptUrl = await getDownloadURL(fileRef);
        } catch (e) {
            console.warn("Storage upload fallback to mock URL", e);
            receiptUrl = `https://firebasestorage.googleapis.com/v0/b/novalunch.appspot.com/o/receipts%2Freceipt_${Date.now()}.jpg?alt=media`;
        }
    }

    const payload = {
        parent_id: parentId,
        student_id: studentId,
        amount: parseFloat(amount),
        receipt_proof_url: receiptUrl || "https://images.unsplash.com/photo-1554224155-8d04cb21cd6c?w=600&auto=format&fit=crop",
        status: "PENDING", // "PENDING" | "APPROVED" | "REJECTED"
        verified_by: null,
        created_at: new Date().toISOString()
    };

    try {
        await set(ref(db, `gcash_topups/${topupId}`), payload);
    } catch (e) {
        console.warn("Top-up cached locally", e);
    }

    localStore.gcashTopups.unshift({ topup_id: topupId, ...payload });
    return { topup_id: topupId, ...payload };
}

export async function approveGCashTopup(topupId, adminId) {
    const topup = localStore.gcashTopups.find(t => t.topup_id === topupId);
    if (topup) {
        topup.status = "APPROVED";
        topup.verified_by = adminId;

        // Atomic transaction credit for student account in Firebase RTDB
        const studentKey = `std_${topup.student_id.replace('-', '_')}`;
        const balRef = ref(db, `students/${studentKey}/credit_balance`);
        try {
            await runTransaction(balRef, (currentVal) => {
                return (parseFloat(currentVal) || 0) + topup.amount;
            });
        } catch (e) {
            console.warn("Firebase RTDB balance transaction warning:", e);
        }

        const student = localStore.students[topup.student_id];
        if (student) {
            student.credit_balance += topup.amount;
        }
    }

    try {
        await update(ref(db, `gcash_topups/${topupId}`), {
            status: "APPROVED",
            verified_by: adminId,
            reviewed_at: new Date().toISOString()
        });
    } catch (e) {
        console.warn("Local update topup approval", e);
    }
}
