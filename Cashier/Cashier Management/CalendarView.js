/**
 * CalendarView.js  — Payment Calendar Module
 *
 * Drop this file in the same folder as CashierManagement.js
 * and add ONE line to index at bottom of CashierManagement.php:
 *
 *   <script src="CalendarView.js"></script>
 *
 * This script reads from:
 *   window.CAL_DATA.payments  — array from PHP (payment submissions)
 *   window.CAL_DATA.dues      — array from PHP (payment due notices)
 *
 * And calls the existing cashier approve/decline API endpoints via CONFIG.
 */

'use strict';

/* ============================================================
   CALENDAR STATE
============================================================ */
const CAL = {
    year:  new Date().getFullYear(),
    month: new Date().getMonth(),  // 0-indexed

};

/* ============================================================
   INIT — called once DOM is ready
============================================================ */
function calInit() {
    if (!document.getElementById('view-calendar')) return;
    calRender();
}

/* ============================================================
   NAVIGATION
============================================================ */
function calPrev() {
    CAL.month--;
    if (CAL.month < 0) { CAL.month = 11; CAL.year--; }
    calRender();
}
function calNext() {
    CAL.month++;
    if (CAL.month > 11) { CAL.month = 0; CAL.year++; }
    calRender();
}
function calGoToday() {
    const now = new Date();
    CAL.year  = now.getFullYear();
    CAL.month = now.getMonth();
    calRender();
}

/* ============================================================
   RENDER CALENDAR
============================================================ */
function calRender() {
    const monthNames = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December'
    ];

    // Month label
    const lbl = document.getElementById('cal-month-label');
    if (lbl) lbl.textContent = monthNames[CAL.month] + ' ' + CAL.year;

    // Build event map: 'YYYY-MM-DD' → { payments: [], dues: [] }
    const eventMap = calBuildEventMap();

    // Figure out first/last day of month
    const firstDay = new Date(CAL.year, CAL.month, 1);
    const lastDay  = new Date(CAL.year, CAL.month + 1, 0);
    let startDow   = firstDay.getDay(); // 0=Sun
    const totalDays = lastDay.getDate();

    const today = new Date();
    const todayKey = dateKey(today);

    const grid = document.getElementById('cal-days-grid');
    if (!grid) return;

    let html = '';

    // Leading faded days from previous month
    const prevMonthLast = new Date(CAL.year, CAL.month, 0).getDate();
    for (let i = startDow - 1; i >= 0; i--) {
        html += `<div class="cal-day faded"><div class="cal-day-num">${prevMonthLast - i}</div></div>`;
    }

    // Days of the current month
    for (let d = 1; d <= totalDays; d++) {
        const key     = `${CAL.year}-${String(CAL.month + 1).padStart(2,'0')}-${String(d).padStart(2,'0')}`;
        const events  = eventMap[key] || { payments: [], dues: [] };
        const hasEvts = events.payments.length > 0 || events.dues.length > 0;
        const isToday = (key === todayKey);

        let cls = 'cal-day';
        if (isToday)  cls += ' today';
        if (hasEvts)  cls += ' has-events';

        const dateLabel = new Date(CAL.year, CAL.month, d).toLocaleDateString('en-PH', {
            weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
        });

        html += `<div class="${cls}" data-key="${key}" data-label="${dateLabel}"`;
        if (hasEvts) html += ` onclick="calOpenDay(this)"`;
        html += `><div class="cal-day-num">${d}</div>`;

        // Show up to 3 chips
        let chipCount = 0;
        for (const p of events.payments) {
            if (chipCount >= 3) break;
            const type  = calPaymentChipType(p.status);
            const name  = p.student.split(' ')[0]; // first name only for chip
            html += `<div class="cal-event-chip ${type}" title="${p.student}">
                <span class="chip-dot"></span>${name}
            </div>`;
            chipCount++;
        }
        for (const due of events.dues) {
            if (chipCount >= 3) break;
            html += `<div class="cal-event-chip due" title="Due: ${due.student}">
                <span class="chip-dot"></span>${due.student.split(' ')[0]}
            </div>`;
            chipCount++;
        }
        const remaining = events.payments.length + events.dues.length - chipCount;
        if (remaining > 0) {
            html += `<span class="cal-more-link">+${remaining} more</span>`;
        }

        html += `</div>`;
    }

    // Trailing faded days
    const totalCells = Math.ceil((startDow + totalDays) / 7) * 7;
    const trailingDays = totalCells - (startDow + totalDays);
    for (let i = 1; i <= trailingDays; i++) {
        html += `<div class="cal-day faded"><div class="cal-day-num">${i}</div></div>`;
    }

    grid.innerHTML = html;
    calCloseDetail();
}

function calPaymentChipType(status) {
    if (!status) return 'pending';
    const s = status.toLowerCase();
    if (s === 'verified' || s === 'reflected_to_enrollment') return 'paid';
    if (s === 'rejected') return 'rejected';
    return 'pending';
}

function dateKey(d) {
    return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

/* ============================================================
   BUILD EVENT MAP from window.CAL_DATA
============================================================ */
function calBuildEventMap() {
    const data = window.CAL_DATA || { payments: [], dues: [] };
    const map  = {};

    function ensureDay(key) {
        if (!map[key]) map[key] = { payments: [], dues: [] };
    }

    for (const p of (data.payments || [])) {
        if (!p.date) continue;
        const key = p.date.substring(0, 10);
        ensureDay(key);
        map[key].payments.push(p);
    }

    for (const due of (data.dues || [])) {
        if (!due.due_date) continue;
        const key = due.due_date.substring(0, 10);
        ensureDay(key);
        map[key].dues.push(due);
    }

    return map;
}

/* ============================================================
   DAY DETAIL PANEL
============================================================ */
function calOpenDay(cell) {
    const key    = cell.getAttribute('data-key');
    const label  = cell.getAttribute('data-label');
    const events = calBuildEventMap()[key] || { payments: [], dues: [] };

    const panel = document.getElementById('cal-day-detail');
    if (!panel) return;

    // Header date
    document.getElementById('cal-detail-date').textContent = label;

    // Build body
    const body   = document.getElementById('cal-detail-body');
    let   inner  = '';

    if (events.payments.length === 0 && events.dues.length === 0) {
        inner = `<div class="cal-detail-empty">No payment activity on this day.</div>`;
    }

    if (events.payments.length > 0) {
        inner += `<div class="cal-section-label">Payments</div>`;
        for (const p of events.payments) {
            const chipType   = calPaymentChipType(p.status);
            const badgeLabel = chipType === 'paid' ? 'Approved' : chipType === 'rejected' ? 'Rejected' : 'Pending';
            const badgeCss   = chipType === 'paid' ? 'enrolled' : chipType === 'rejected' ? 'declined' : 'pending';
            const initials   = p.student.split(' ').map(w=>w[0]||'').join('').substring(0,2).toUpperCase();
            const timeStr    = p.date ? new Date(p.date).toLocaleTimeString('en-PH', { hour:'2-digit', minute:'2-digit' }) : '—';
            const canAction  = (chipType === 'pending');

            inner += `
            <div class="cal-pmt-card" data-pmtid="${p.id}">
                <div class="cal-pmt-top">
                    <div class="cal-pmt-avatar">${initials}</div>
                    <div>
                        <div class="cal-pmt-name">${escHtml(p.student)}</div>
                        <div class="cal-pmt-section">${escHtml(p.grade_section || '—')}</div>
                    </div>
                    <span class="status-badge ${badgeCss} cal-pmt-badge" style="margin-left:auto;">${badgeLabel}</span>
                </div>
                <div class="cal-pmt-details">
                    <div class="cal-pmt-detail-row">
                        <span class="cal-pmt-detail-label">LRN</span>
                        <span class="cal-pmt-detail-val">${escHtml(p.lrn || '—')}</span>
                    </div>
                    <div class="cal-pmt-detail-row">
                        <span class="cal-pmt-detail-label">Time of Payment</span>
                        <span class="cal-pmt-detail-val">${timeStr}</span>
                    </div>
                    <div class="cal-pmt-detail-row">
                        <span class="cal-pmt-detail-label">Reference No.</span>
                        <span class="cal-pmt-detail-val">${escHtml(p.ref || '—')}</span>
                    </div>
                    <div class="cal-pmt-detail-row">
                        <span class="cal-pmt-detail-label">Amount</span>
                        <span class="cal-pmt-detail-val">${p.amount ? '₱' + parseFloat(p.amount).toLocaleString('en-PH', {minimumFractionDigits:2}) : '—'}</span>
                    </div>
                </div>
                ${canAction ? `
                <div class="cal-pmt-actions">
                    <button class="cal-btn-view-proof" onclick="calViewProof(${p.id}, event)">View</button>
                    <button class="cal-btn-approve" onclick="calApprove(${p.id}, '${escAttr(p.student)}', this, event)">Approve</button>
                    <button class="cal-btn-reject"  onclick="calInitReject(${p.id}, '${escAttr(p.student)}', event)">Reject</button>
                </div>` : (p.img ? `
                <div class="cal-pmt-actions">
                    <button class="cal-btn-view-proof" onclick="calViewProof(${p.id}, event)">View</button>
                </div>` : '')}
            </div>`;
        }
    }

    if (events.dues.length > 0) {
        inner += `<div class="cal-section-label">Payment Due Notices</div>`;
        for (const due of events.dues) {
            const timeStr = due.due_date ? new Date(due.due_date + (due.due_date.length === 10 ? 'T00:00:00' : '')).toLocaleTimeString('en-PH', { hour:'2-digit', minute:'2-digit' }) : '—';
            inner += `
            <div class="cal-due-card">
                <div class="cal-due-title">Due Notice</div>
                <div class="cal-due-name">${escHtml(due.student)}</div>
                <div class="cal-due-section">${escHtml(due.grade_section || '—')}</div>
                <div class="cal-due-amount">₱${parseFloat(due.amount_due || 0).toLocaleString('en-PH', {minimumFractionDigits:2})} due at ${timeStr}</div>
            </div>`;
        }
    }

    body.innerHTML = inner;

    // Position panel near the clicked cell, but keep it in-viewport
    const rect = cell.getBoundingClientRect();
    panel.style.display = 'flex';
    panel.classList.add('visible');

    const pw = 380;
    let left = rect.right + 10;
    if (left + pw > window.innerWidth - 16) left = rect.left - pw - 10;
    if (left < 8) left = 8;

    let top = rect.top;
    const ph = Math.min(panel.scrollHeight, window.innerHeight * 0.8);
    if (top + ph > window.innerHeight - 16) top = window.innerHeight - ph - 16;
    if (top < 8) top = 8;

    panel.style.left = left + 'px';
    panel.style.top  = top  + 'px';
    panel.style.width = pw  + 'px';
}

function calCloseDetail() {
    const panel = document.getElementById('cal-day-detail');
    if (panel) { panel.classList.remove('visible'); panel.style.display = 'none'; }
}

/* ============================================================
   APPROVE MODAL
============================================================ */
function calApprove(id, studentName, btn, event) {
    event && event.stopPropagation();

    // Populate and show the approval confirmation modal
    document.getElementById('cal-modal-approve-name').textContent = studentName;
    document.getElementById('cal-modal-approve').classList.add('visible');

    // Wire the confirm button (replace previous listener to avoid stacking)
    const confirmBtn = document.getElementById('cal-modal-approve-confirm');
    const newConfirm = confirmBtn.cloneNode(true);
    confirmBtn.parentNode.replaceChild(newConfirm, confirmBtn);
    newConfirm.addEventListener('click', () => calDoApprove(id, studentName, btn));
}

async function calDoApprove(id, studentName, btn) {
    calCloseApproveModal();
    btn.disabled    = true;
    btn.textContent = 'Approving…';

    try {
        await apiCall(CONFIG.approveUrl, { id, cashier_id: CONFIG.cashierId });
        showToast(`Payment approved for <strong>${studentName}</strong>.`, 'success');
        calUpdateCardStatus(id, 'verified', btn);
        calRender();
    } catch (err) {
        showToast(err.message || 'Approval failed. Please retry.', 'danger');
        btn.disabled    = false;
        btn.textContent = 'Approve';
    }
}

function calCloseApproveModal() {
    document.getElementById('cal-modal-approve').classList.remove('visible');
}

function calUpdateCardStatus(id, status, triggerEl) {
    const card = triggerEl.closest('.cal-pmt-card');
    if (!card) return;
    const badge = card.querySelector('.cal-pmt-badge');
    if (badge) { badge.className = 'status-badge enrolled cal-pmt-badge'; badge.textContent = 'Approved'; }
    const actRow = card.querySelector('.cal-pmt-actions');
    if (actRow) actRow.remove();
    // Update the CAL_DATA in-memory so chip re-renders correctly
    if (window.CAL_DATA && window.CAL_DATA.payments) {
        const p = window.CAL_DATA.payments.find(x => x.id === id);
        if (p) p.status = status;
    }
}

/* ============================================================
   REJECT MODAL
============================================================ */
function calInitReject(id, studentName, event) {
    event && event.stopPropagation();

    // Populate and show the decline confirmation modal
    document.getElementById('cal-modal-decline-name').textContent = studentName;
    document.getElementById('cal-modal-decline-reason').value = '';
    document.getElementById('cal-modal-decline').classList.add('visible');
    document.getElementById('cal-modal-decline-reason').focus();

    // Wire the confirm button fresh each time
    const confirmBtn = document.getElementById('cal-modal-decline-confirm');
    const newConfirm = confirmBtn.cloneNode(true);
    confirmBtn.parentNode.replaceChild(newConfirm, confirmBtn);
    newConfirm.addEventListener('click', () => {
        const reason = document.getElementById('cal-modal-decline-reason').value.trim();
        calDoReject(id, studentName, reason);
    });
}

async function calDoReject(id, studentName, reason) {
    calCloseDeclineModal();

    // Find the reject button inside the matching card to give feedback
    const card = document.querySelector(`.cal-pmt-card[data-pmtid="${id}"]`);
    const btn  = card ? card.querySelector('.cal-btn-reject') : null;
    if (btn) { btn.disabled = true; btn.textContent = 'Rejecting…'; }

    try {
        await apiCall(CONFIG.declineUrl, { id, cashier_id: CONFIG.cashierId, reason });
        showToast(`Payment rejected for <strong>${studentName}</strong>.`, 'danger');
        if (btn) calUpdateCardStatus(id, 'rejected', btn);
        if (window.CAL_DATA && window.CAL_DATA.payments) {
            const p = window.CAL_DATA.payments.find(x => x.id === id);
            if (p) p.status = 'rejected';
        }
        calRender();
    } catch (err) {
        showToast(err.message || 'Rejection failed. Please retry.', 'danger');
        if (btn) { btn.disabled = false; btn.textContent = 'Reject'; }
    }
}

function calCloseDeclineModal() {
    document.getElementById('cal-modal-decline').classList.remove('visible');
}

/* ============================================================
   VIEW DETAIL MODAL (mirrors Review Proof of Payment)
============================================================ */
function calViewProof(id, event) {
    event && event.stopPropagation();

    // Find payment object from CAL_DATA
    const data = window.CAL_DATA || {};
    const p = (data.payments || []).find(x => x.id == id);
    if (!p) return;

    // ── Proof image ──────────────────────────────────────────
    const proofArea   = document.getElementById('cal-view-proof-area');
    const proofOpenBtn = document.getElementById('cal-view-proof-open-btn');

    if (p.img) {
        const base = (typeof CONFIG !== 'undefined' && CONFIG.proofBaseUrl) ? CONFIG.proofBaseUrl : '/';
        const url  = base + p.img.replace(/^\//, '');
        proofArea.innerHTML = `<img src="${escHtml(url)}" alt="Proof – ${escHtml(p.student)}" onclick="this.classList.toggle('zoomed')" title="Click to zoom">`;
        proofOpenBtn.href = url;
        proofOpenBtn.classList.remove('hidden');
    } else {
        proofArea.innerHTML = `
            <div class="proof-placeholder">
                <svg width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                    <path d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                </svg>
                <p>No proof of payment image uploaded.</p>
            </div>`;
        proofOpenBtn.classList.add('hidden');
    }

    // ── Student Information ──────────────────────────────────
    document.getElementById('cal-view-student-name').textContent    = p.student || '—';
    document.getElementById('cal-view-grade-section').textContent   = p.grade_section || '—';

    // Enrollment status — format nicely
    const esRaw = p.enrollment_status || '';
    let esLabel = esRaw;
    if      (esRaw === 'enrolled')       esLabel = 'Enrolled';
    else if (esRaw === 'registered')     esLabel = 'Registered (Pending)';
    else if (esRaw === 'not_enrolled')   esLabel = 'Not Enrolled';
    else if (esRaw === 'pending')        esLabel = 'Pending';
    else if (esRaw)                      esLabel = esRaw.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    document.getElementById('cal-view-enrollment-status').textContent = esLabel || '—';

    // ── Payment Details ──────────────────────────────────────
    document.getElementById('cal-view-ref-number').textContent  = p.ref || '—';
    document.getElementById('cal-view-amount').textContent      = p.amount
        ? '₱' + parseFloat(p.amount).toLocaleString('en-PH', { minimumFractionDigits: 2 })
        : '—';

    // Payment type — format nicely
    const ptRaw = p.payment_type || '';
    let ptLabel = ptRaw;
    if      (ptRaw === 'full')    ptLabel = 'Full Payment';
    else if (ptRaw === 'partial') ptLabel = 'Partial Payment';
    else if (ptRaw === 'onsite')  ptLabel = 'On-Site Payment';
    else if (ptRaw)               ptLabel = ptRaw.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
    document.getElementById('cal-view-payment-type').textContent = ptLabel || '—';

    // Submitted date
    document.getElementById('cal-view-date-time').textContent = p.date
        ? new Date(p.date).toLocaleString('en-PH', {
              year: 'numeric', month: '2-digit', day: '2-digit',
              hour: '2-digit', minute: '2-digit', second: '2-digit',
              hour12: false
          }).replace(',', '')
        : '—';

    // ── Open modal ───────────────────────────────────────────
    const modal = document.getElementById('cal-view-modal');
    if (modal) modal.classList.add('active');
}

function calCloseViewModal() {
    const modal = document.getElementById('cal-view-modal');
    if (modal) modal.classList.remove('active');
}

// Legacy lightbox stub — overlay kept in DOM but no longer used as primary view
function calCloseProof() {
    const overlay = document.getElementById('cal-proof-overlay');
    if (overlay) overlay.classList.remove('visible');
}

/* ============================================================
   HELPERS
============================================================ */
function escHtml(str) {
    if (!str) return '';
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function escAttr(str) {
    if (!str) return '';
    return String(str).replace(/'/g,"\\'").replace(/"/g,'&quot;');
}

/* ============================================================
   WIRE UP — runs after DOM ready
============================================================ */
document.addEventListener('DOMContentLoaded', () => {
    calInit();

    // Close detail when clicking outside
    document.addEventListener('click', (e) => {
        const panel = document.getElementById('cal-day-detail');
        if (!panel) return;
        if (panel.classList.contains('visible') && !panel.contains(e.target)) {
            const isCalDay = e.target.closest('.cal-day');
            if (!isCalDay) calCloseDetail();
        }
    });

    // Close proof overlay on overlay-background click (legacy overlay still in DOM)
    const overlay = document.getElementById('cal-proof-overlay');
    if (overlay) overlay.addEventListener('click', (e) => {
        if (e.target === overlay) calCloseProof();
    });

    // Backdrop click closes view modal
    const viewModal = document.getElementById('cal-view-modal');
    if (viewModal) viewModal.addEventListener('click', (e) => {
        if (e.target === viewModal) calCloseViewModal();
    });

    // ESC closes panel / overlay / modals
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            calCloseDetail();
            calCloseViewModal();
            calCloseApproveModal();
            calCloseDeclineModal();
        }
    });

    // Backdrop click closes modals
    const approveModal = document.getElementById('cal-modal-approve');
    if (approveModal) approveModal.addEventListener('click', (e) => {
        if (e.target === approveModal) calCloseApproveModal();
    });
    const declineModal = document.getElementById('cal-modal-decline');
    if (declineModal) declineModal.addEventListener('click', (e) => {
        if (e.target === declineModal) calCloseDeclineModal();
    });
});