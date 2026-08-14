/**
 * CashierManagement.js  v2
 *
 * All data comes from the server-rendered DOM (data-* attributes on .payment-row).
 * API endpoints are clearly marked and ready for wiring.
 *
 * Backend contact points:
 *   POST /api/payment/approve   { id, cashier_id }
 *   POST /api/payment/decline   { id, cashier_id, reason }
 *   POST /api/payment/onsite      { student_id, student_name, grade_section,
 *                                    amount, payment_mode (always "cash"),
 *                                    fee_type, cashier_id }
 *   POST /api/payment/payment-due { student_id, student_name, grade_section,
 *                                    amount_due, due_datetime, cashier_id }
 *   GET  /api/student/lookup?q=   { id or LRN }
 *   POST /api/auth/logout
 */

'use strict';

/* ============================================================
   CONFIG — replace with values injected by the server
   e.g. via a <script> block in the HTML:
     window.APP_CONFIG = { schoolName: "...", cashierName: "...", ... };
============================================================ */
const CONFIG = window.APP_CONFIG ?? {
    schoolName: 'Saint Joseph',
    cashierName: '',
    cashierRole: 'Cashier Desk',
    cashierId: null,
    loginUrl: 'login.html',
    approveUrl: 'CashierManagement.php?action=approve',
    declineUrl: 'CashierManagement.php?action=decline',
    onsiteUrl: 'CashierManagement.php?action=onsite',
    paymentDueUrl: 'CashierManagement.php?action=payment-due',
    lookupUrl: 'CashierManagement.php?action=lookup',
    suggestUrl: 'CashierManagement.php?action=suggest',
    markViewedUrl: 'CashierManagement.php?action=mark-viewed',
    walletLookupUrl: 'CashierManagement.php?action=wallet-lookup',
    topupUrl: 'CashierManagement.php?action=topup',
    logoutUrl: 'CashierManagement.php?action=logout',
    countdownSec: 10,
};

/* ============================================================
   STATE
============================================================ */
let currentRow = null;
let currentData = {};
let countdownInterval = null;
let timeLeft = CONFIG.countdownSec;

/* ============================================================
   DOM REFERENCES
============================================================ */
const reviewModal = document.getElementById('reviewModal');
const onsiteModal = document.getElementById('onsiteModal');
const topupModal = document.getElementById('topupModal');
const paymentDueModal = document.getElementById('paymentDueModal');
const logoutModal = document.getElementById('logoutModal');
const actionRow = document.getElementById('action-row');
const declineConfirmRow = document.getElementById('decline-confirm-row');
const declineReasonWrap = document.getElementById('decline-reason-wrap');
const declineReasonInput = document.getElementById('decline-reason');
const countdownBox = document.getElementById('countdown-box');
const timerDisplay = document.getElementById('timer-display');
const progressFill = document.getElementById('progress-fill');
const toastStack = document.getElementById('toast-stack');
const proofArea = document.getElementById('proof-area');
const noResults = document.getElementById('no-results');
const emptyState = document.getElementById('empty-state');
const searchCount = document.getElementById('search-count');

/* ============================================================
   INIT
============================================================ */
document.addEventListener('DOMContentLoaded', () => {

    // ---- Date ----
    const opts = { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' };
    const dateEl = document.getElementById('today-date');
    if (dateEl) dateEl.textContent = new Date().toLocaleDateString('en-PH', opts);

    // ---- Populate cashier info from config/session ----
    const nameEl = document.getElementById('cashier-name');
    const roleEl = document.getElementById('cashier-role');
    const initialsEl = document.getElementById('cashier-initials');
    const schoolEl = document.getElementById('sidebar-school-name');

    if (nameEl) nameEl.textContent = CONFIG.cashierName || 'Cashier';
    if (roleEl) roleEl.textContent = CONFIG.cashierRole || 'Cashier Desk';
    if (schoolEl) schoolEl.textContent = CONFIG.schoolName || 'Saint Joseph';
    if (initialsEl) initialsEl.textContent = getInitials(CONFIG.cashierName || 'C');

    // ---- Show empty state if table is empty ----
    const rows = document.querySelectorAll('.payment-row');
    if (rows.length === 0 && emptyState) emptyState.classList.add('visible');

    // ---- Stats & count ----
    updateStats();
    updateSearchCount();

    // ---- Init payments pagination ----
    paymentsInit();

    // ---- Proof image zoom toggle ----
    proofArea.addEventListener('click', (e) => {
        if (e.target.tagName === 'IMG') e.target.classList.toggle('zoomed');
    });

    // ---- Overlay click closes modals ----
    reviewModal.addEventListener('click', (e) => { if (e.target === reviewModal) closeModal(); });
    onsiteModal.addEventListener('click', (e) => { if (e.target === onsiteModal) closeOnsiteModal(); });
    topupModal.addEventListener('click', (e) => { if (e.target === topupModal) closeTopupModal(); });
    paymentDueModal.addEventListener('click', (e) => { if (e.target === paymentDueModal) closePaymentDueModal(); });
    logoutModal.addEventListener('click', (e) => { if (e.target === logoutModal) closeLogoutModal(); });
    document.getElementById('historyModal').addEventListener('click', (e) => {
        if (e.target === document.getElementById('historyModal')) closeHistoryModal();
    });
    // Close typeahead suggestions when clicking anywhere — no longer needed (broadcast modal has no typeahead)

    // ---- ESC closes any open modal ----
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') { closeModal(); closeOnsiteModal(); closeTopupModal(); closePaymentDueModal(); closeLogoutModal(); closeHistoryModal(); }
    });
});

/* ============================================================
   HELPERS
============================================================ */
function getInitials(name) {
    if (!name) return '?';
    const parts = name.trim().split(/\s+/);
    return (parts[0][0] + (parts[1]?.[0] ?? '')).toUpperCase();
}

/* ============================================================
   STATS
============================================================ */
function updateStats() {
    const rows = document.querySelectorAll('.payment-row');
    let pending = 0, enrolled = 0, onsite = 0;

    rows.forEach(row => {
        const status = row.getAttribute('data-status')?.toLowerCase();
        const type = row.getAttribute('data-type')?.toLowerCase();
        if (status === 'enrolled') enrolled++;
        else if (status !== 'declined') pending++;
        if (type === 'onsite') onsite++;
    });

    document.getElementById('stat-pending').textContent = pending;
    document.getElementById('stat-enrolled').textContent = enrolled;
    document.getElementById('stat-total').textContent = rows.length;
    document.getElementById('stat-onsite').textContent = onsite;
}

/* ============================================================
   MANAGE PAYMENTS — PAGINATION (10 per page)
============================================================ */
const PAYMENTS_PER_PAGE = 10;
let paymentsAllRows = [];
let paymentsFiltered = [];
let paymentsPage = 1;

function paymentsInit() {
    paymentsAllRows = Array.from(document.querySelectorAll('.payment-row'));
    paymentsFiltered = [...paymentsAllRows];
    paymentsPage = 1;
    paymentsRender();
    paymentsRenderPagination();
    updatePaymentsCountLabel();
}

function paymentsRender() {
    paymentsAllRows.forEach(r => r.classList.add('hidden'));
    const start = (paymentsPage - 1) * PAYMENTS_PER_PAGE;
    const slice = paymentsFiltered.slice(start, start + PAYMENTS_PER_PAGE);
    slice.forEach(r => r.classList.remove('hidden'));
    // Empty state
    if (emptyState) emptyState.classList.toggle('visible', paymentsAllRows.length === 0);
    if (noResults) noResults.classList.toggle('visible', paymentsFiltered.length === 0 && paymentsAllRows.length > 0);
}

function paymentsRenderPagination() {
    const container = document.getElementById('payments-pagination');
    if (!container) return;
    const totalPages = Math.ceil(paymentsFiltered.length / PAYMENTS_PER_PAGE);
    if (totalPages <= 1) { container.innerHTML = ''; return; }

    let html = '';
    html += `<button class="hpag-btn hpag-arrow${paymentsPage === 1 ? ' disabled' : ''}" onclick="paymentsGoPage(${paymentsPage - 1})" ${paymentsPage === 1 ? 'disabled' : ''}>
        <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
    </button>`;

    const delta = 2;
    const pages = [];
    for (let p = 1; p <= totalPages; p++) {
        if (p === 1 || p === totalPages || (p >= paymentsPage - delta && p <= paymentsPage + delta)) pages.push(p);
    }
    let prev = null;
    pages.forEach(p => {
        if (prev !== null && p - prev > 1) html += `<span class="hpag-ellipsis">…</span>`;
        html += `<button class="hpag-btn${p === paymentsPage ? ' active' : ''}" onclick="paymentsGoPage(${p})">${p}</button>`;
        prev = p;
    });

    html += `<button class="hpag-btn hpag-arrow${paymentsPage === totalPages ? ' disabled' : ''}" onclick="paymentsGoPage(${paymentsPage + 1})" ${paymentsPage === totalPages ? 'disabled' : ''}>
        <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24"><path d="M9 18l6-6-6-6"/></svg>
    </button>`;

    container.innerHTML = html;
}

function paymentsGoPage(p) {
    const totalPages = Math.ceil(paymentsFiltered.length / PAYMENTS_PER_PAGE);
    if (p < 1 || p > totalPages) return;
    paymentsPage = p;
    paymentsRender();
    paymentsRenderPagination();
    const tbl = document.getElementById('payment-tbody');
    if (tbl) tbl.closest('.table-scroll')?.scrollTo({ top: 0, behavior: 'smooth' });
}

function updatePaymentsCountLabel() {
    const el = document.getElementById('payments-count-label');
    if (!el) return;
    const total = paymentsAllRows.length;
    const shown = paymentsFiltered.length;
    if (!total) { el.textContent = ''; return; }
    el.textContent = shown < total ? `${shown} of ${total} records` : `${total} record${total !== 1 ? 's' : ''}`;
}

/* ============================================================
   STUDENT TOP-UP HISTORY — PAGINATION (10 per page)
============================================================ */
const TOPUP_PER_PAGE = 10;
let topupAllRows = [];
let topupFiltered = [];
let topupPage = 1;

function topupHistoryInit() {
    topupAllRows = Array.from(document.querySelectorAll('.topup-row'));
    topupFiltered = [...topupAllRows];
    topupPage = 1;
    topupHistoryRender();
    topupHistoryRenderPagination();
    updateTopupCountLabel();
}

function topupHistoryRender() {
    topupAllRows.forEach(r => r.classList.add('hidden'));
    const start = (topupPage - 1) * TOPUP_PER_PAGE;
    const slice = topupFiltered.slice(start, start + TOPUP_PER_PAGE);
    slice.forEach(r => r.classList.remove('hidden'));

    const emptyEl = document.getElementById('topup-empty-state');
    const noRes = document.getElementById('topup-no-results');
    if (emptyEl) emptyEl.closest('tr')?.classList.toggle('hidden', topupAllRows.length !== 0);
    if (noRes) noRes.classList.toggle('visible', topupFiltered.length === 0 && topupAllRows.length > 0);
}

function topupHistoryRenderPagination() {
    const container = document.getElementById('topup-pagination');
    if (!container) return;
    const totalPages = Math.ceil(topupFiltered.length / TOPUP_PER_PAGE);
    if (totalPages <= 1) { container.innerHTML = ''; return; }

    let html = '';
    html += `<button class="hpag-btn hpag-arrow${topupPage === 1 ? ' disabled' : ''}" onclick="topupHistoryGoPage(${topupPage - 1})" ${topupPage === 1 ? 'disabled' : ''}>
        <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
    </button>`;

    const delta = 2;
    const pages = [];
    for (let p = 1; p <= totalPages; p++) {
        if (p === 1 || p === totalPages || (p >= topupPage - delta && p <= topupPage + delta)) pages.push(p);
    }
    let prev = null;
    pages.forEach(p => {
        if (prev !== null && p - prev > 1) html += `<span class="hpag-ellipsis">…</span>`;
        html += `<button class="hpag-btn${p === topupPage ? ' active' : ''}" onclick="topupHistoryGoPage(${p})">${p}</button>`;
        prev = p;
    });

    html += `<button class="hpag-btn hpag-arrow${topupPage === totalPages ? ' disabled' : ''}" onclick="topupHistoryGoPage(${topupPage + 1})" ${topupPage === totalPages ? 'disabled' : ''}>
        <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24"><path d="M9 18l6-6-6-6"/></svg>
    </button>`;

    container.innerHTML = html;
}

function topupHistoryGoPage(p) {
    const totalPages = Math.ceil(topupFiltered.length / TOPUP_PER_PAGE);
    if (p < 1 || p > totalPages) return;
    topupPage = p;
    topupHistoryRender();
    topupHistoryRenderPagination();
    const tbl = document.getElementById('topup-tbody');
    if (tbl) tbl.closest('.table-scroll')?.scrollTo({ top: 0, behavior: 'smooth' });
}

function updateTopupCountLabel() {
    const el = document.getElementById('topup-count-label');
    if (!el) return;
    const total = topupAllRows.length;
    const shown = topupFiltered.length;
    if (!total) { el.textContent = ''; return; }
    el.textContent = shown < total ? `${shown} of ${total} records` : `${total} record${total !== 1 ? 's' : ''}`;
}

function topupLiveSearch(query) {
    const q = query.trim().toLowerCase();
    topupFiltered = topupAllRows.filter(row => {
        const cashier = row.getAttribute('data-cashier')?.toLowerCase() ?? '';
        const student = row.getAttribute('data-student')?.toLowerCase() ?? '';
        const lrn = row.getAttribute('data-lrn')?.toLowerCase() ?? '';
        return !q || cashier.includes(q) || student.includes(q) || lrn.includes(q);
    });
    topupPage = 1;
    topupHistoryRender();
    topupHistoryRenderPagination();
    updateTopupCountLabel();
}

/**
 * Injects a server-returned top-up record as a new row at the top of the
 * Student Top-Up History table, so the list reflects the new entry
 * immediately without a full page reload.
 */
function injectTopupRow(r) {
    const tbody = document.getElementById('topup-tbody');
    if (!tbody) return;

    const modeMap = { cash: ['cash', 'Cash'], gcash: ['gcash', 'GCash'], bank_transfer: ['bank-transfer', 'Bank Transfer'] };
    const [modeClass, modeLabel] = modeMap[r.payment_mode] ?? ['gcash', r.payment_mode ?? '—'];
    const initials = getInitials(r.student_name);
    const dateFmt = new Date(r.created_at).toLocaleString('en-PH', {
        month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true,
    });

    const tr = document.createElement('tr');
    tr.className = 'topup-row';
    tr.dataset.cashier = r.cashier_name ?? '';
    tr.dataset.student = r.student_name ?? '';
    tr.dataset.lrn = r.lrn ?? '';

    tr.innerHTML = `
        <td>${r.cashier_name ?? '—'}</td>
        <td>
            <div class="student-cell">
                <div class="student-avatar">${initials}</div>
                <span class="student-name">${r.student_name}</span>
            </div>
        </td>
        <td><span class="ref-badge">${r.lrn ?? '—'}</span></td>
        <td class="amount-cell is-topup-credit">+₱${parseFloat(r.amount_added).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
        <td><span class="type-badge ${modeClass}">${modeLabel}</span></td>
        <td class="date-cell">${dateFmt}</td>
    `;

    tbody.insertBefore(tr, tbody.firstChild);
    document.getElementById('topup-empty-state')?.closest('tr')?.classList.add('hidden');
    topupHistoryInit();
}

/* ============================================================
   LIVE SEARCH
============================================================ */
function liveSearch(query) {
    const q = query.trim().toLowerCase();
    paymentsFiltered = paymentsAllRows.filter(row => {
        const name = row.getAttribute('data-student')?.toLowerCase() ?? '';
        const ref = row.getAttribute('data-ref')?.toLowerCase() ?? '';
        const studentId = row.getAttribute('data-student-id')?.toLowerCase() ?? '';
        const lrn = row.getAttribute('data-lrn')?.toLowerCase() ?? '';
        return !q || name.includes(q) || ref.includes(q) || studentId.includes(q) || lrn.includes(q);
    });
    paymentsPage = 1;
    paymentsRender();
    paymentsRenderPagination();
    updatePaymentsCountLabel();
    updateSearchCount(paymentsFiltered.length, paymentsAllRows.length, q);
}
function updateSearchCount(visible, total, q) {
    if (!q || q === '') {
        const t = document.querySelectorAll('.payment-row').length;
        searchCount.textContent = t + ' record' + (t !== 1 ? 's' : '');
    } else {
        searchCount.textContent = visible + ' of ' + total + ' matched';
    }
}

/* ============================================================
   REVIEW MODAL — OPEN / CLOSE
============================================================ */
function openReviewModal(btn) {
    currentRow = btn.closest('.payment-row');
    currentData = {
        id: currentRow.getAttribute('data-id'),
        name: currentRow.getAttribute('data-student'),
        ref: currentRow.getAttribute('data-ref'),
        date: currentRow.getAttribute('data-date'),
        img: currentRow.getAttribute('data-img'),
        enrollmentStatus: currentRow.getAttribute('data-enrollment-status') || '',
        amount: currentRow.getAttribute('data-amount') || '',
        confirmedAmount: currentRow.getAttribute('data-confirmed-amount') || '',
        paymentType: currentRow.getAttribute('data-type') || '',
        bankName: currentRow.getAttribute('data-bank-name') || '',
        gradeSection: currentRow.getAttribute('data-grade-section') || '',
    };

    // Mark as viewed — calls backend which sets status → under_review
    // and signals student's portal that cashier has opened this submission
    apiCall(CONFIG.markViewedUrl, { id: currentData.id }).catch(() => { });
    // Update row status label in table immediately
    const statusBadge = currentRow.querySelector('.status-badge');
    if (statusBadge && statusBadge.textContent.trim() === 'Pending') {
        statusBadge.textContent = 'Under Review';
    }

    // Student info
    document.getElementById('modal-student-name').textContent = currentData.name;
    document.getElementById('modal-grade-section').textContent = currentData.gradeSection || '—';

    // Enrollment status with badge
    const enrollStatusEl = document.getElementById('modal-enrollment-status');
    const enrollLabel = currentData.enrollmentStatus === 'enrolled' ? 'Enrolled' : 'Registered (Pending)';
    const enrollClass = currentData.enrollmentStatus === 'enrolled' ? 'enrolled' : 'pending';
    enrollStatusEl.innerHTML = `<span class="status-badge ${enrollClass}">${enrollLabel}</span>`;

    // Payment details
    document.getElementById('modal-ref-number').textContent = currentData.ref || '—';
    document.getElementById('modal-date-time').textContent = currentData.date || '—';

    const amountVal = currentData.amount ? '₱' + parseFloat(currentData.amount).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : '—';
    document.getElementById('modal-amount').textContent = amountVal;

    const ch = currentData.paymentType || 'gcash';
    const chLabel = ch === 'onsite' ? 'On-Site Cash'
        : ch === 'bank_transfer' ? ('Bank Transfer' + (currentData.bankName ? ' – ' + currentData.bankName : ''))
            : 'GCash';
    document.getElementById('modal-payment-type').textContent = chLabel;

    // Proof image — currentData.img is the relative DB path (e.g. "uploads/payment_proofs/...")
    // We prefix with proofBaseUrl (default "/") so it resolves correctly from any page depth.
    const proofOpenBtn = document.getElementById('proof-open-btn');
    if (currentData.img) {
        const imgUrl = (CONFIG.proofBaseUrl ?? '/') + currentData.img.replace(/^\//, '');
        proofArea.innerHTML = `<img src="${imgUrl}" alt="Proof of Payment for ${currentData.name}" title="Click to zoom">`;
        proofOpenBtn.href = imgUrl;
        proofOpenBtn.classList.remove('hidden');
    } else {
        proofArea.innerHTML = `
            <div class="proof-placeholder">
                <svg width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                    <path d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                </svg>
                <p>No image uploaded</p>
            </div>`;
        proofOpenBtn.classList.add('hidden');
    }

    resetModalUI();
    reviewModal.classList.add('active');
}

function closeModal() {
    reviewModal.classList.remove('active');
    cancelApproval();
}

function resetModalUI() {
    actionRow.style.display = 'flex';
    declineConfirmRow.classList.remove('visible');
    declineReasonWrap.classList.remove('visible');
    declineReasonInput.value = '';
    countdownBox.classList.remove('visible');
    clearInterval(countdownInterval);
    progressFill.style.width = '100%';
}

/* ============================================================
   DECLINE FLOW
============================================================ */
function initiateDecline() {
    // Show reason box + confirm buttons
    declineReasonWrap.classList.add('visible');
    actionRow.style.display = 'none';
    declineConfirmRow.classList.add('visible');
}

function cancelDecline() {
    declineReasonWrap.classList.remove('visible');
    declineReasonInput.value = '';
    declineConfirmRow.classList.remove('visible');
    actionRow.style.display = 'flex';
}

async function finalizeDecline() {
    const reason = declineReasonInput.value.trim();

    // → API: POST /api/payment/decline
    try {
        await apiCall(CONFIG.declineUrl, {
            id: currentData.id,
            cashier_id: CONFIG.cashierId,
            reason: reason,
        });
    } catch (err) {
        showToast(err.message || 'Network error — please try again.', 'danger');
        return;
    }

    showToast(`Payment declined for <strong>${currentData.name}</strong>. Student will be notified.`, 'danger');

    // Update DOM
    const badge = currentRow.querySelector('.status-badge');
    if (badge) { badge.className = 'status-badge declined'; badge.textContent = 'Declined'; }
    currentRow.setAttribute('data-status', 'Declined');
    const reviewBtn = currentRow.querySelector('.btn-review');
    if (reviewBtn) { reviewBtn.disabled = true; reviewBtn.textContent = 'Declined'; reviewBtn.classList.add('reviewed'); }

    updateStats();
    closeModal();
}

/* ============================================================
   APPROVE — COUNTDOWN FLOW
============================================================ */
function initiateApproval() {
    actionRow.style.display = 'none';
    countdownBox.classList.add('visible');

    timeLeft = CONFIG.countdownSec;
    timerDisplay.textContent = timeLeft;
    progressFill.style.width = '100%';
    progressFill.style.transition = 'width 1s linear';

    countdownInterval = setInterval(() => {
        timeLeft--;
        timerDisplay.textContent = timeLeft;
        progressFill.style.width = `${(timeLeft / CONFIG.countdownSec) * 100}%`;
        if (timeLeft <= 0) { clearInterval(countdownInterval); finalizeApproval(); }
    }, 1000);
}

function cancelApproval() {
    clearInterval(countdownInterval);
    resetModalUI();
}

function forceApprove() {
    clearInterval(countdownInterval);
    finalizeApproval();
}

async function finalizeApproval() {

    // → API: POST /api/payment/approve
    try {
        await apiCall(CONFIG.approveUrl, {
            id: currentData.id,
            cashier_id: CONFIG.cashierId,
        });
    } catch (err) {
        showToast(err.message || 'Network error — could not save approval. Please retry.', 'danger');
        cancelApproval();
        return;
    }

    const wasEnrolled = currentData.enrollmentStatus === 'enrolled';
    const toastMsg = wasEnrolled
        ? `Payment approved for <strong>${currentData.name}</strong>. Stored in transaction history.`
        : `Payment approved for <strong>${currentData.name}</strong>. Student is now <strong>Enrolled</strong>.`;
    showToast(toastMsg, 'success');

    const badge = currentRow.querySelector('.status-badge');
    if (badge) { badge.className = 'status-badge enrolled'; badge.textContent = 'Enrolled'; }
    currentRow.setAttribute('data-status', 'enrolled');

    const reviewBtn = currentRow.querySelector('.btn-review');
    if (reviewBtn) { reviewBtn.disabled = true; reviewBtn.textContent = 'Approved'; reviewBtn.classList.add('reviewed'); }

    updateStats();
    closeModal();
}

/* ============================================================
   HISTORY — ACCORDION + FILTER + SEARCH + PAGINATION
============================================================ */

const HISTORY_PER_PAGE = 10;
let historyAllItems = [];   // all .hacc-item elements
let historyFiltered = [];   // after filter + search
let historyPage = 1;
let historyActiveFilter = 'all';
let historySearchQuery = '';

function historyInit() {
    historyAllItems = Array.from(document.querySelectorAll('#history-accordion .hacc-item'));
    historyFiltered = [...historyAllItems];
    historyPage = 1;
    historyRender();
    historyRenderPagination();
    updateHistoryCountLabel();
}

/** Status filter — called by filter buttons */
function historyFilter(filter, btn) {
    historyActiveFilter = filter;
    // Toggle active class on buttons
    document.querySelectorAll('.hfilt-btn').forEach(b => b.classList.remove('active'));
    if (btn) btn.classList.add('active');
    historyApplyFilters();
}

/** Name or reference number live search */
function historySearchRef(query) {
    historySearchQuery = query.trim().toLowerCase();
    const clearBtn = document.getElementById('history-search-clear');
    if (clearBtn) clearBtn.style.display = historySearchQuery ? '' : 'none';
    historyApplyFilters();
}

function clearHistorySearch() {
    const input = document.getElementById('history-search');
    if (input) input.value = '';
    historySearchRef('');
}

/** Apply both active filter and search query together */
function historyApplyFilters() {
    // Reattach any items inside group wrappers back to accordion root first
    const accordion = document.getElementById('history-accordion');
    if (accordion) {
        accordion.querySelectorAll('.hacc-name-group .hacc-item').forEach(el => accordion.appendChild(el));
    }
    historyFiltered = historyAllItems.filter(item => {
        // Status filter
        const status = item.getAttribute('data-status') ?? '';
        let statusMatch = true;
        if (historyActiveFilter === 'approved') {
            statusMatch = status === 'verified' || status === 'reflected_to_enrollment';
        } else if (historyActiveFilter === 'rejected') {
            statusMatch = status === 'rejected';
        } else if (historyActiveFilter === 'pending') {
            statusMatch = status === 'uploaded' || status === 'under_review' || status === 'pending' || status === 'submitted';
        }
        // Name OR reference number search
        let searchMatch = true;
        if (historySearchQuery) {
            const name = item.getAttribute('data-student')?.toLowerCase() ?? '';
            const ref = item.getAttribute('data-ref')?.toLowerCase() ?? '';
            searchMatch = name.includes(historySearchQuery) || ref.includes(historySearchQuery);
        }
        return statusMatch && searchMatch;
    });
    historyPage = 1;
    historyRender();
    historyRenderPagination();
    updateHistoryCountLabel();
}

function historyRender() {
    // Hide all items first
    historyAllItems.forEach(el => {
        el.style.display = 'none';
        el.classList.remove('hacc-open');
    });

    const accordion = document.getElementById('history-accordion');

    // Remove any existing group wrappers and empty state
    accordion.querySelectorAll('.hacc-name-group, .history-empty').forEach(el => el.remove());

    const emptyEl = document.getElementById('history-empty-search');
    if (emptyEl) emptyEl.remove();

    if (historyFiltered.length === 0) {
        const div = document.createElement('div');
        div.id = 'history-empty-search';
        div.className = 'history-empty';
        div.innerHTML = `<svg width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg><p>No records match your search.</p>`;
        accordion.appendChild(div);
        return;
    }

    // Detect if search query uniquely targets a student name (all results share the same student name)
    const uniqueNames = [...new Set(historyFiltered.map(el => el.getAttribute('data-student')?.toLowerCase()))];
    const isNameSearch = historySearchQuery.length > 0 && uniqueNames.length === 1 &&
        uniqueNames[0].includes(historySearchQuery);

    if (isNameSearch) {
        // ── GROUPED MODE ──
        // Group results by student name (handles edge case of same name diff students via LRN)
        const groups = {};
        historyFiltered.forEach(el => {
            const key = el.getAttribute('data-student') || '—';
            if (!groups[key]) groups[key] = [];
            groups[key].push(el);
        });

        Object.entries(groups).forEach(([studentName, items]) => {
            const initials = studentName.split(' ').map(w => w[0] ?? '').join('').substring(0, 2).toUpperCase();
            const lrn = items[0].getAttribute('data-lrn') || '—';

            const groupWrapper = document.createElement('div');
            groupWrapper.className = 'hacc-name-group';

            const approvedCount = items.filter(i => i.getAttribute('data-status') === 'verified' || i.getAttribute('data-status') === 'reflected_to_enrollment').length;
            const rejectedCount = items.filter(i => i.getAttribute('data-status') === 'rejected').length;

            groupWrapper.innerHTML = `
                <div class="hacc-group-header" onclick="toggleNameGroup(this)">
                    <div class="hacc-avatar hacc-group-avatar">${initials}</div>
                    <div class="hacc-identity">
                        <span class="hacc-name">${studentName}</span>
                        <span class="hacc-meta">
                            <span class="hacc-lrn">LRN: ${lrn}</span>
                            <span class="hacc-sep">·</span>
                            <span class="hacc-lrn">${items.length} transaction${items.length !== 1 ? 's' : ''}</span>
                            ${approvedCount ? `<span class="hacc-sep">·</span><span class="hacc-group-chip approved-chip">${approvedCount} approved</span>` : ''}
                            ${rejectedCount ? `<span class="hacc-sep">·</span><span class="hacc-group-chip rejected-chip">${rejectedCount} rejected</span>` : ''}
                        </span>
                    </div>
                    <span class="hacc-chevron hacc-group-chevron">
                        <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>
                    </span>
                </div>
                <div class="hacc-group-body"></div>
            `;

            const groupBody = groupWrapper.querySelector('.hacc-group-body');
            items.forEach(el => {
                el.style.display = '';
                groupBody.appendChild(el);
            });

            accordion.appendChild(groupWrapper);

            // Auto-expand group when searching
            groupWrapper.classList.add('hacc-group-open');
        });

        // In grouped mode, hide pagination
        const pag = document.getElementById('history-pagination');
        if (pag) pag.innerHTML = '';
    } else {
        // ── FLAT MODE (normal, ungrouped) ──
        const start = (historyPage - 1) * HISTORY_PER_PAGE;
        const slice = historyFiltered.slice(start, start + HISTORY_PER_PAGE);
        slice.forEach(el => {
            el.style.display = '';
            // Move back to accordion root if it was inside a group
            if (el.parentElement !== accordion) accordion.appendChild(el);
        });
    }
}

function toggleNameGroup(header) {
    const group = header.closest('.hacc-name-group');
    group.classList.toggle('hacc-group-open');
}

function historyRenderPagination() {
    const container = document.getElementById('history-pagination');
    if (!container) return;

    // In grouped name-search mode, pagination is hidden (historyRender handles it)
    const uniqueNames = [...new Set(historyFiltered.map(el => el.getAttribute('data-student')?.toLowerCase()))];
    const isNameSearch = historySearchQuery.length > 0 && uniqueNames.length === 1 &&
        uniqueNames[0].includes(historySearchQuery);
    if (isNameSearch) { container.innerHTML = ''; return; }

    const totalPages = Math.ceil(historyFiltered.length / HISTORY_PER_PAGE);
    if (totalPages <= 1) { container.innerHTML = ''; return; }

    let html = '';
    // Prev
    html += `<button class="hpag-btn hpag-arrow${historyPage === 1 ? ' disabled' : ''}" onclick="historyGoPage(${historyPage - 1})" ${historyPage === 1 ? 'disabled' : ''}>
        <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg>
    </button>`;

    // Page numbers — smart windowing
    const delta = 2;
    const pages = [];
    for (let p = 1; p <= totalPages; p++) {
        if (p === 1 || p === totalPages || (p >= historyPage - delta && p <= historyPage + delta)) {
            pages.push(p);
        }
    }
    let prev = null;
    pages.forEach(p => {
        if (prev !== null && p - prev > 1) {
            html += `<span class="hpag-ellipsis">…</span>`;
        }
        html += `<button class="hpag-btn${p === historyPage ? ' active' : ''}" onclick="historyGoPage(${p})">${p}</button>`;
        prev = p;
    });

    // Next
    html += `<button class="hpag-btn hpag-arrow${historyPage === totalPages ? ' disabled' : ''}" onclick="historyGoPage(${historyPage + 1})" ${historyPage === totalPages ? 'disabled' : ''}>
        <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24"><path d="M9 18l6-6-6-6"/></svg>
    </button>`;

    container.innerHTML = html;
}

function historyGoPage(p) {
    const totalPages = Math.ceil(historyFiltered.length / HISTORY_PER_PAGE);
    if (p < 1 || p > totalPages) return;
    historyPage = p;
    // Reattach any items that may be inside group wrappers back to accordion before re-rendering
    const accordion = document.getElementById('history-accordion');
    accordion.querySelectorAll('.hacc-name-group .hacc-item').forEach(el => accordion.appendChild(el));
    historyRender();
    historyRenderPagination();
    // Scroll accordion back to top
    if (accordion) accordion.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function updateHistoryCountLabel() {
    const el = document.getElementById('history-count-label');
    if (!el) return;
    const total = historyAllItems.length;
    const filtered = historyFiltered.length;
    if (!total) { el.textContent = ''; return; }
    el.textContent = filtered < total
        ? `${filtered} of ${total} records`
        : `${total} record${total !== 1 ? 's' : ''}`;
}

function toggleAccordion(header) {
    const item = header.closest('.hacc-item');
    const isOpen = item.classList.contains('hacc-open');
    // Close all open items on same page
    document.querySelectorAll('.hacc-item.hacc-open').forEach(el => el.classList.remove('hacc-open'));
    if (!isOpen) item.classList.add('hacc-open');
}

/* ============================================================
   HISTORY DETAIL MODAL (opened from accordion "View Receipt")
============================================================ */
function openHistoryModalFromAccordion(btn) {
    const img = btn.getAttribute('data-img') || '';
    const name = btn.getAttribute('data-student') || '—';
    const lrn = btn.getAttribute('data-lrn') || '—';
    const gradeSection = btn.getAttribute('data-grade-section') || '—';
    const ref = btn.getAttribute('data-ref') || '—';
    const amount = btn.getAttribute('data-confirmed-amount') || btn.getAttribute('data-amount') || '';
    const pType = btn.getAttribute('data-payment-type') || '';
    const hChannel = btn.getAttribute('data-type') || 'gcash';
    const date = btn.getAttribute('data-date') || '—';
    const status = btn.getAttribute('data-status') || '';
    const reason = btn.getAttribute('data-rejection-reason') || '';

    document.getElementById('hist-student-name').textContent = name;
    const histGradeEl = document.getElementById('hist-grade-section');
    const histLrnEl = document.getElementById('hist-lrn');
    if (histGradeEl) histGradeEl.textContent = gradeSection;
    if (histLrnEl) histLrnEl.textContent = lrn;

    document.getElementById('hist-ref-number').textContent = ref;
    document.getElementById('hist-date-time').textContent = date;

    const amtFmt = amount ? '₱' + parseFloat(amount).toLocaleString('en-PH', { minimumFractionDigits: 2 }) : '—';
    document.getElementById('hist-amount').textContent = amtFmt;

    const hChLabel = hChannel === 'onsite' ? 'On-Site Cash' : hChannel === 'bank_transfer' ? 'Bank Transfer' : 'GCash';
    document.getElementById('hist-payment-type').textContent = hChLabel;

    const isRejected = status === 'rejected';
    const resultEl = document.getElementById('hist-result');
    resultEl.innerHTML = isRejected
        ? '<span class="status-badge declined">Rejected</span>'
        : '<span class="status-badge enrolled">Approved</span>';

    const reasonRow = document.getElementById('hist-reason-row');
    if (isRejected && reason) {
        reasonRow.style.display = '';
        document.getElementById('hist-reason').textContent = reason;
    } else {
        reasonRow.style.display = 'none';
    }

    const histProofArea = document.getElementById('history-proof-area');
    const histProofOpenBtn = document.getElementById('history-proof-open-btn');
    if (img) {
        const imgUrl = (CONFIG.proofBaseUrl ?? '/') + img.replace(/^\//, '');
        histProofArea.innerHTML = `<img src="${imgUrl}" alt="Proof" title="Click to zoom">`;
        histProofOpenBtn.href = imgUrl;
        histProofOpenBtn.classList.remove('hidden');
    } else {
        histProofArea.innerHTML = `
            <div class="proof-placeholder">
                <svg width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                    <path d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                </svg>
                <p>No image available</p>
            </div>`;
        histProofOpenBtn.classList.add('hidden');
    }

    document.getElementById('historyModal').classList.add('active');
}

function closeHistoryModal() {
    document.getElementById('historyModal').classList.remove('active');
}


/* ============================================================
   NAV VIEW SWITCHING
============================================================ */
document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.nav-link[data-view]').forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();
            const target = link.getAttribute('data-view');
            document.querySelectorAll('.nav-link').forEach(l => l.classList.remove('active'));
            link.classList.add('active');
            document.querySelectorAll('.view-panel').forEach(p => p.classList.remove('active'));
            const panel = document.getElementById('view-' + target);
            if (panel) panel.classList.add('active');

            // Update topbar title
            const titles = { payments: 'Proof of Payment Review', history: 'Transaction History', topup: 'Student Top-Up History' };
            const h1 = document.querySelector('.topbar-left h1');
            if (h1 && titles[target]) h1.textContent = titles[target];

            // Init history accordion + pagination when switching to that tab
            if (target === 'history') historyInit();
            // Re-render payments pagination (search may have changed)
            if (target === 'payments') paymentsInit();
            // Init top-up history pagination
            if (target === 'topup') topupHistoryInit();
        });
    });

    // Also init if history panel is visible on first load
    if (document.getElementById('view-history')?.classList.contains('active')) historyInit();
    if (document.getElementById('view-topup')?.classList.contains('active')) topupHistoryInit();
});

/* ============================================================
   ON-SITE PAYMENT MODAL (legacy — kept for backward compatibility)
============================================================ */
function openOnsiteModal() {
    clearOnsiteForm();
    onsiteModal.classList.add('active');
    initPesoInput();
}

function closeOnsiteModal() {
    onsiteModal.classList.remove('active');
}

function clearOnsiteForm() {
    ['os-student-id', 'os-student-name', 'os-grade-section', 'os-amount'].forEach(id => {
        const el = document.getElementById(id);
        if (el) { el.value = ''; el.readOnly = false; el.classList.remove('field-locked'); }
    });
    document.getElementById('os-fee-type').value = '';
}

/* ============================================================
   STUDENT TOP-UP MODAL
   Cashier-side ID/wallet credit. Cashiers can only ADD funds — the
   amount field stays disabled until a student is found, and the
   server independently caps each transaction at the admin-set limit
   (cafeteria_settings.max_topup_amount). There is no deduct control.
============================================================ */
let topupSelectedStudentId = null;
let topupMaxAmount = 0;   // 0 = no admin-set limit

function openTopupModal() {
    clearTopupForm();
    topupModal.classList.add('active');
    initTopupPesoInput();
}

function closeTopupModal() {
    topupModal.classList.remove('active');
    hideTopupSuggestions();
}

function clearTopupForm() {
    topupSelectedStudentId = null;
    topupMaxAmount = 0;

    const idInput = document.getElementById('tu-student-id');
    if (idInput) idInput.value = '';

    ['tu-student-name', 'tu-grade-section'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });

    const amountInput = document.getElementById('tu-amount');
    if (amountInput) {
        amountInput.value = '';
        amountInput.dataset.raw = '';
        amountInput.disabled = true;
    }

    const modeSelect = document.getElementById('tu-payment-mode');
    if (modeSelect) modeSelect.value = '';

    const balanceEl = document.getElementById('tu-current-balance');
    if (balanceEl) balanceEl.textContent = '—';

    hideTopupSuggestions();

    const hintEl = document.getElementById('tu-limit-hint');
    if (hintEl) { hintEl.textContent = ''; hintEl.classList.remove('over-limit'); }

    const noteEl = document.getElementById('topup-limit-note');
    if (noteEl) noteEl.textContent = "Cashiers can only load funds onto a student's ID. Deductions are admin-only.";

    const submitBtn = document.querySelector('.btn-topup-submit');
    if (submitBtn) submitBtn.disabled = true;
}

/** Peso formatter for the top-up amount field (same behavior as on-site amount) */
function initTopupPesoInput() {
    const input = document.getElementById('tu-amount');
    if (!input) return;

    input.addEventListener('input', () => {
        let raw = input.value.replace(/[^0-9.]/g, '');
        const parts = raw.split('.');
        if (parts.length > 2) raw = parts[0] + '.' + parts.slice(1).join('');
        if (parts[1]?.length > 2) raw = parts[0] + '.' + parts[1].slice(0, 2);
        input.dataset.raw = raw;
        input.value = raw;
        validateTopupAmount();
    });

    input.addEventListener('blur', () => {
        const num = parseFloat(input.dataset.raw ?? input.value);
        if (!isNaN(num) && num > 0) input.value = num.toFixed(2);
    });

    input.addEventListener('focus', () => {
        input.value = input.dataset.raw ?? input.value.replace(/,/g, '');
    });
}

/** Client-side check against the admin limit — purely a UX hint; the server re-checks. */
function validateTopupAmount() {
    const input = document.getElementById('tu-amount');
    const hintEl = document.getElementById('tu-limit-hint');
    const submitBtn = document.querySelector('.btn-topup-submit');
    const amount = parseFloat(input?.dataset.raw ?? input?.value);

    let ok = topupSelectedStudentId && amount > 0;

    if (hintEl) {
        if (topupMaxAmount > 0 && amount > topupMaxAmount) {
            hintEl.textContent = `Exceeds the admin-set limit of ₱${topupMaxAmount.toLocaleString('en-PH', { minimumFractionDigits: 2 })} per transaction.`;
            hintEl.classList.add('over-limit');
            ok = false;
        } else {
            hintEl.classList.remove('over-limit');
            hintEl.textContent = topupMaxAmount > 0
                ? `Up to ₱${topupMaxAmount.toLocaleString('en-PH', { minimumFractionDigits: 2 })} per transaction.`
                : '';
        }
    }

    if (submitBtn) submitBtn.disabled = !ok;
}

async function lookupTopupStudent() {
    const query = document.getElementById('tu-student-id').value.trim();
    if (!query) { showToast('Enter a Student ID or LRN to look up.', 'info'); return; }

    const nameInput = document.getElementById('tu-student-name');
    const sectionInput = document.getElementById('tu-grade-section');
    const balanceEl = document.getElementById('tu-current-balance');
    const amountInput = document.getElementById('tu-amount');
    const btn = document.querySelector('#topupModal .btn-lookup');

    if (btn) { btn.innerHTML = 'Searching…'; btn.disabled = true; }
    topupSelectedStudentId = null;
    if (amountInput) amountInput.disabled = true;
    document.querySelector('.btn-topup-submit').disabled = true;

    // → API: GET CashierManagement.php?action=wallet-lookup&q=<query>
    try {
        const res = await fetch(`${CONFIG.walletLookupUrl}&q=${encodeURIComponent(query)}`);
        const data = await res.json();

        topupMaxAmount = parseFloat(data.max_topup_amount) || 0;

        if (data.found) {
            nameInput.value = data.name ?? '';
            sectionInput.value = data.grade_section ?? '';
            balanceEl.textContent = '₱' + parseFloat(data.balance ?? 0).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

            topupSelectedStudentId = data.student_id;
            if (amountInput) amountInput.disabled = false;

            const noteEl = document.getElementById('topup-limit-note');
            if (noteEl) {
                noteEl.textContent = topupMaxAmount > 0
                    ? `Cashiers can only load funds onto a student's ID, up to ₱${topupMaxAmount.toLocaleString('en-PH', { minimumFractionDigits: 2 })} per transaction. Deductions are admin-only.`
                    : "Cashiers can only load funds onto a student's ID. Deductions are admin-only.";
            }

            showToast(`Found: <strong>${data.name}</strong>`, 'success');
            validateTopupAmount();
        } else {
            nameInput.value = '';
            sectionInput.value = '';
            balanceEl.textContent = '—';
            showToast('No student found with that ID or LRN.', 'danger');
        }
    } catch {
        showToast('Could not reach the server. Please try again.', 'danger');
    } finally {
        if (btn) {
            btn.innerHTML = `
                <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
                </svg> Look Up`;
            btn.disabled = false;
        }
    }
}

// ------------------------------------------------------------------
// Student Top-Up: live search-prediction (typeahead) for the
// Student ID / LRN / Name / Section field.
//
// Reuses the existing `suggest` endpoint (CONFIG.suggestUrl), which
// matches on first/last/middle name, LRN, student ID prefix, and
// (as of this change) section name — so cashiers no longer have to
// know a student's exact ID to start a top-up.
// ------------------------------------------------------------------
let topupSuggestDebounce = null;
let topupSuggestAbort = null;
let topupSuggestItems = [];
let topupSuggestActiveIndex = -1;

function hideTopupSuggestions() {
    const list = document.getElementById('tu-suggest-list');
    if (!list) return;
    list.hidden = true;
    list.innerHTML = '';
    topupSuggestItems = [];
    topupSuggestActiveIndex = -1;
}

function onTopupSearchInput(rawValue) {
    const query = rawValue.trim();

    // A fresh keystroke invalidates any previously selected student —
    // force a re-lookup/re-selection before Add Credit is allowed.
    topupSelectedStudentId = null;
    const amountInput = document.getElementById('tu-amount');
    if (amountInput) amountInput.disabled = true;
    const submitBtn = document.querySelector('.btn-topup-submit');
    if (submitBtn) submitBtn.disabled = true;

    clearTimeout(topupSuggestDebounce);

    if (query.length < 2) {
        hideTopupSuggestions();
        return;
    }

    topupSuggestDebounce = setTimeout(() => fetchTopupSuggestions(query), 200);
}

async function fetchTopupSuggestions(query) {
    if (topupSuggestAbort) topupSuggestAbort.abort();
    topupSuggestAbort = new AbortController();

    try {
        const res = await fetch(`${CONFIG.suggestUrl}&q=${encodeURIComponent(query)}`, {
            signal: topupSuggestAbort.signal
        });
        const data = await res.json();
        renderTopupSuggestions(data.suggestions ?? [], query);
    } catch (err) {
        if (err.name !== 'AbortError') hideTopupSuggestions();
    }
}

function highlightMatch(text, query) {
    if (!text) return '—';
    const i = text.toLowerCase().indexOf(query.toLowerCase());
    if (i === -1) return escapeHtml(text);
    return `${escapeHtml(text.slice(0, i))}<mark>${escapeHtml(text.slice(i, i + query.length))}</mark>${escapeHtml(text.slice(i + query.length))}`;
}

function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str ?? '';
    return div.innerHTML;
}

function renderTopupSuggestions(items, query) {
    const list = document.getElementById('tu-suggest-list');
    if (!list) return;

    topupSuggestItems = items;
    topupSuggestActiveIndex = -1;

    if (!items.length) {
        list.innerHTML = `<div class="typeahead-empty">No matching students.</div>`;
        list.hidden = false;
        return;
    }

    list.innerHTML = items.map((it, idx) => `
        <div class="typeahead-item" data-idx="${idx}" onclick="selectTopupSuggestion(${idx})">
            <div class="typeahead-item-main">
                <span class="typeahead-name">${highlightMatch(it.name, query)}</span>
                <span class="typeahead-lrn">${highlightMatch(it.lrn || '—', query)}</span>
            </div>
            <div class="typeahead-section">${highlightMatch(it.grade_section || '—', query)}</div>
        </div>
    `).join('');

    list.hidden = false;
}

function onTopupSearchKeydown(event) {
    const list = document.getElementById('tu-suggest-list');
    if (!list || list.hidden || !topupSuggestItems.length) {
        if (event.key === 'Enter') { event.preventDefault(); lookupTopupStudent(); }
        return;
    }

    if (event.key === 'ArrowDown') {
        event.preventDefault();
        topupSuggestActiveIndex = Math.min(topupSuggestActiveIndex + 1, topupSuggestItems.length - 1);
        updateTopupSuggestActive();
    } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        topupSuggestActiveIndex = Math.max(topupSuggestActiveIndex - 1, 0);
        updateTopupSuggestActive();
    } else if (event.key === 'Enter') {
        event.preventDefault();
        if (topupSuggestActiveIndex >= 0) {
            selectTopupSuggestion(topupSuggestActiveIndex);
        } else {
            lookupTopupStudent();
        }
    } else if (event.key === 'Escape') {
        hideTopupSuggestions();
    }
}

function updateTopupSuggestActive() {
    const list = document.getElementById('tu-suggest-list');
    if (!list) return;
    [...list.querySelectorAll('.typeahead-item')].forEach((el, idx) => {
        el.classList.toggle('active', idx === topupSuggestActiveIndex);
        if (idx === topupSuggestActiveIndex) el.scrollIntoView({ block: 'nearest' });
    });
}

function selectTopupSuggestion(idx) {
    const item = topupSuggestItems[idx];
    if (!item) return;

    const idInput = document.getElementById('tu-student-id');
    // Prefer LRN (what cashiers usually have on hand); fall back to ID.
    if (idInput) idInput.value = item.lrn || item.student_id;

    hideTopupSuggestions();
    lookupTopupStudent();
}

document.addEventListener('click', (e) => {
    const wrap = document.getElementById('tu-student-id')?.closest('.typeahead-wrap');
    if (wrap && !wrap.contains(e.target)) hideTopupSuggestions();
});

async function submitTopup() {
    if (!topupSelectedStudentId) return showToast('Look up a student first.', 'danger');

    const amountInput = document.getElementById('tu-amount');
    const amount = parseFloat(amountInput.dataset.raw ?? amountInput.value);
    const paymentMode = document.getElementById('tu-payment-mode').value;

    if (!amount || amount <= 0) return showToast('Enter a valid amount to add.', 'danger');
    if (topupMaxAmount > 0 && amount > topupMaxAmount) {
        return showToast(`Amount exceeds the admin-set limit of ₱${topupMaxAmount.toLocaleString('en-PH', { minimumFractionDigits: 2 })} per transaction.`, 'danger');
    }
    if (!paymentMode) return showToast('Select the mode of payment.', 'danger');

    const submitBtn = document.querySelector('.btn-topup-submit');
    submitBtn.innerHTML = 'Processing…';
    submitBtn.disabled = true;

    // → API: POST CashierManagement.php?action=topup  (cashier can only credit — never debit)
    try {
        const res = await apiCall(CONFIG.topupUrl, {
            student_id: topupSelectedStudentId,
            amount: amount,
            payment_mode: paymentMode,
            cashier_id: CONFIG.cashierId,
        });

        showToast(
            `Added ₱${amount.toLocaleString('en-PH', { minimumFractionDigits: 2 })} to <strong>${res.student_name}</strong>'s ID. New balance: ₱${parseFloat(res.new_balance).toLocaleString('en-PH', { minimumFractionDigits: 2 })}.`,
            'success'
        );
        closeTopupModal();

        // Reflect the new entry in the Student Top-Up History table immediately
        injectTopupRow(res);

    } catch (err) {
        showToast(err.message || 'Failed to process top-up. Please try again.', 'danger');
    } finally {
        submitBtn.innerHTML = `
            <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24">                <path d="M5 13l4 4L19 7"/>
            </svg> Add Credit`;
        submitBtn.disabled = false;
    }
}

/* ============================================================
   SET PAYMENT DUE MODAL (ANNOUNCEMENT BROADCAST)
   Broadcasts a payment deadline notice to all currently enrolled students.
   Registered (new) students are excluded — they handle enrollment separately.
============================================================ */
function openPaymentDueModal() {
    clearPaymentDueForm();
    paymentDueModal.classList.add('active');
    initDuePesoInput();
    // Pre-fill due datetime to tomorrow at 8:00 AM by default
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    tomorrow.setHours(8, 0, 0, 0);
    const local = tomorrow.toISOString().slice(0, 16);
    const dueDateEl = document.getElementById('pd-due-datetime');
    if (dueDateEl) {
        dueDateEl.min = new Date().toISOString().slice(0, 16);
        dueDateEl.value = local;
    }
}

function closePaymentDueModal() {
    paymentDueModal.classList.remove('active');
}

function clearPaymentDueForm() {
    const amtEl = document.getElementById('pd-amount-due');
    const dateEl = document.getElementById('pd-due-datetime');
    const noteEl = document.getElementById('pd-notice-message');
    if (amtEl) { amtEl.value = ''; if (amtEl.dataset) amtEl.dataset.raw = ''; }
    if (dateEl) { dateEl.value = ''; }
    if (noteEl) { noteEl.value = ''; }
}

/** Peso formatter for the payment-due amount field */
function initDuePesoInput() {
    const input = document.getElementById('pd-amount-due');
    if (!input) return;

    input.addEventListener('input', () => {
        let raw = input.value.replace(/[^0-9.]/g, '');
        const parts = raw.split('.');
        if (parts.length > 2) raw = parts[0] + '.' + parts.slice(1).join('');
        if (parts[1]?.length > 2) raw = parts[0] + '.' + parts[1].slice(0, 2);
        input.dataset.raw = raw;
        input.value = raw;
    });

    input.addEventListener('blur', () => {
        const num = parseFloat(input.dataset.raw ?? input.value);
        if (!isNaN(num) && num > 0) input.value = num.toFixed(2);
    });

    input.addEventListener('focus', () => {
        input.value = input.dataset.raw ?? input.value.replace(/,/g, '');
    });
}

/** Submit the Payment Due Announcement — sends to all enrolled students */
async function submitPaymentDue() {
    const amountInput = document.getElementById('pd-amount-due');
    const amountDue = parseFloat(amountInput.dataset.raw ?? amountInput.value);
    const dueDatetime = document.getElementById('pd-due-datetime').value;
    const noticeMessage = (document.getElementById('pd-notice-message')?.value ?? '').trim();

    // Validation
    if (!amountDue || amountDue <= 0) return showToast('Enter a valid amount due.', 'danger');
    if (!dueDatetime) return showToast('Select a due date and time.', 'danger');

    const submitBtn = document.querySelector('.btn-payment-due-submit');
    submitBtn.innerHTML = 'Sending…';
    submitBtn.disabled = true;

    try {
        const result = await apiCall(CONFIG.paymentDueUrl, {
            amount_due: amountDue,
            due_datetime: dueDatetime,
            notice_message: noticeMessage,
            cashier_id: CONFIG.cashierId,
            broadcast: true,   // flag: send to all enrolled students
        });

        const dueFmt = new Date(dueDatetime).toLocaleString('en-PH', {
            month: 'short', day: 'numeric', year: 'numeric',
            hour: 'numeric', minute: '2-digit', hour12: true,
        });
        const count = result.notified_count ?? 'all enrolled';
        showToast(
            `Payment deadline notice sent to <strong>${count} student${count !== 1 ? 's' : ''}</strong> — due ${dueFmt}.`,
            'success'
        );
        closePaymentDueModal();

    } catch (err) {
        showToast(err.message || 'Failed to send payment notice. Please try again.', 'danger');
    } finally {
        submitBtn.innerHTML = `
            <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24">
                <path d="M5 13l4 4L19 7"/>
            </svg> Send Notice to All Students`;
        submitBtn.disabled = false;
    }
}

/* ============================================================
   PESO INPUT FORMATTER
   Formats the amount field as ₱1,000.00 style while typing.
   The raw numeric value is stored in the element's dataset.
============================================================ */
function initPesoInput() {
    const input = document.getElementById('os-amount');
    if (!input) return;

    input.addEventListener('input', () => {
        // Strip everything except digits and first decimal point
        let raw = input.value.replace(/[^0-9.]/g, '');
        const parts = raw.split('.');
        if (parts.length > 2) raw = parts[0] + '.' + parts.slice(1).join('');

        // Limit to 2 decimal places while typing
        if (parts[1]?.length > 2) raw = parts[0] + '.' + parts[1].slice(0, 2);

        input.dataset.raw = raw;
        input.value = raw;          // keep cursor-friendly while typing
    });

    input.addEventListener('blur', () => {
        const num = parseFloat(input.dataset.raw ?? input.value);
        if (!isNaN(num) && num > 0) {
            input.value = num.toFixed(2);
        }
    });

    input.addEventListener('focus', () => {
        // Show raw number on focus so editing is easy
        input.value = input.dataset.raw ?? input.value.replace(/,/g, '');
    });
}

async function lookupStudent() {
    const query = document.getElementById('os-student-id').value.trim();
    if (!query) { showToast('Enter a Student ID or LRN to look up.', 'info'); return; }

    const nameInput = document.getElementById('os-student-name');
    const sectionInput = document.getElementById('os-grade-section');
    const btn = document.querySelector('.btn-lookup');

    btn.innerHTML = 'Searching…';
    btn.disabled = true;

    // → API: GET /api/student/lookup?q=<query>
    try {
        const res = await fetch(`${CONFIG.lookupUrl}?q=${encodeURIComponent(query)}`);
        const data = await res.json();

        if (data.found) {
            // Auto-fill and lock both fields
            nameInput.value = data.name ?? '';
            sectionInput.value = data.grade_section ?? '';
            nameInput.readOnly = true;
            sectionInput.readOnly = true;
            nameInput.classList.add('field-locked');
            sectionInput.classList.add('field-locked');
            showToast(`Found: <strong>${data.name}</strong>`, 'success');
        } else {
            // Not found — leave editable for manual entry
            nameInput.readOnly = false;
            sectionInput.readOnly = false;
            nameInput.classList.remove('field-locked');
            sectionInput.classList.remove('field-locked');
            showToast('No student found. You may type the details manually.', 'info');
        }
    } catch {
        showToast('Could not reach the server. Please try again.', 'danger');
    } finally {
        btn.innerHTML = `
            <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
            </svg> Look Up`;
        btn.disabled = false;
    }
}

async function submitOnsitePayment() {
    const studentName = document.getElementById('os-student-name').value.trim();
    const studentId = document.getElementById('os-student-id').value.trim();
    const gradeSection = document.getElementById('os-grade-section').value.trim();
    const amountInput = document.getElementById('os-amount');
    const amount = parseFloat(amountInput.dataset.raw ?? amountInput.value);
    const feeType = document.getElementById('os-fee-type').value;

    if (!studentName) return showToast('Student name is required.', 'danger');
    if (!amount || amount <= 0) return showToast('Enter a valid payment amount.', 'danger');
    if (!feeType) return showToast('Select the fee type.', 'danger');

    const submitBtn = document.querySelector('.btn-onsite-submit');
    submitBtn.innerHTML = 'Processing…';
    submitBtn.disabled = true;

    // → API: POST /api/payment/onsite
    try {
        const res = await apiCall(CONFIG.onsiteUrl, {
            student_id: studentId || null,
            student_name: studentName,
            grade_section: gradeSection,
            amount: amount,
            payment_mode: 'cash',      // always cash for on-site
            fee_type: feeType,
            cashier_id: CONFIG.cashierId,
        });

        showToast(`On-site payment recorded for <strong>${studentName}</strong>. Student enrolled.`, 'success');
        closeOnsiteModal();

        // Inject a new row into the table so the UI reflects the new record without a full reload.
        // The server should return the new record's data in res.record — adapt as needed.
        if (res?.record) {
            injectRow(res.record);
            updateStats();
            updateSearchCount();
        }

    } catch {
        showToast('Failed to save payment. Please check your connection.', 'danger');
    } finally {
        submitBtn.innerHTML = `
            <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24">
                <path d="M5 13l4 4L19 7"/>
            </svg> Record &amp; Enroll`;
        submitBtn.disabled = false;
    }
}

/**
 * Injects a server-returned record as a new table row.
 * @param {Object} r  — record object from API response
 */
function injectRow(r) {
    const tbody = document.getElementById('payment-tbody');
    const initials = getInitials(r.student_name);
    const rCh = r.payment_channel || 'gcash';
    const typeClass = rCh === 'onsite' ? 'onsite' : rCh === 'bank_transfer' ? 'bank-transfer' : 'gcash';
    const typeLabel = rCh === 'onsite' ? 'On-Site' : rCh === 'bank_transfer' ? 'Bank Transfer' : 'GCash';

    const tr = document.createElement('tr');
    tr.className = 'payment-row';
    tr.dataset.id = r.id;
    tr.dataset.student = r.student_name;
    tr.dataset.ref = r.reference_number ?? '—';
    tr.dataset.date = r.submitted_at;
    tr.dataset.img = r.proof_url ?? '';
    tr.dataset.status = r.status ?? 'Enrolled';
    tr.dataset.amount = r.amount ?? '';
    tr.dataset.type = r.payment_type ?? 'onsite';

    const amtFmt = r.amount
        ? '₱' + parseFloat(r.amount).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
        : '—';

    tr.innerHTML = `
        <td>
            <div class="student-cell">
                <div class="student-avatar">${initials}</div>
                <span class="student-name">${r.student_name}</span>
            </div>
        </td>
        <td><span class="ref-badge">${r.reference_number ?? '—'}</span></td>
        <td class="amount-cell">${amtFmt}</td>
        <td class="date-cell">${r.submitted_at}</td>
        <td><span class="type-badge ${typeClass}">${typeLabel}</span></td>
        <td><span class="status-badge enrolled">${r.status ?? 'Enrolled'}</span></td>
        <td><button class="btn-review reviewed" disabled>Enrolled</button></td>
    `;

    tbody.insertBefore(tr, tbody.firstChild);
    emptyState?.classList.remove('visible');
    paymentsInit();
}

/* ============================================================
   LOGOUT MODAL
============================================================ */
function openLogoutModal() { logoutModal.classList.add('active'); }
function closeLogoutModal() { logoutModal.classList.remove('active'); }

async function confirmLogout() {
    showToast('Signing you out…', 'success');
    // → API: POST /api/auth/logout
    try { await apiCall(CONFIG.logoutUrl, {}); } catch { /* proceed anyway */ }
    setTimeout(() => { window.location.href = CONFIG.loginUrl; }, 1100);
}

/* ============================================================
   API WRAPPER
   Replace with your preferred fetch/axios pattern.
============================================================ */
async function apiCall(url, body) {
    const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
        body: JSON.stringify(body),
    });
    // Always parse JSON first so we can read the server's real error message on 4xx.
    const data = await res.json();
    if (!res.ok || data.success === false) {
        const msg = data.error || data.message || `Server error (HTTP ${res.status})`;
        throw new Error(msg);
    }
    return data;
}

/* ============================================================
   TOAST NOTIFICATION SYSTEM
============================================================ */
const TOAST_ICONS = {
    success: `<svg width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="M5 13l4 4L19 7"/></svg>`,
    danger: `<svg width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="M6 18L18 6M6 6l12 12"/></svg>`,
    info: `<svg width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>`,
};

function showToast(message, type = 'success') {
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `
        <div class="toast-icon">${TOAST_ICONS[type] ?? TOAST_ICONS.success}</div>
        <span class="toast-msg">${message}</span>
    `;
    toastStack.appendChild(toast);
    setTimeout(() => {
        toast.style.animation = 'toastOut 0.35s ease forwards';
        setTimeout(() => toast.remove(), 380);
    }, 5000);
}