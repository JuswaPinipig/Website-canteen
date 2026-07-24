'use strict';

/* ── CONFIG ── */
const API_BASE = '../../Student/student enrollment/api';
const AUTO_REFRESH_INTERVAL = 30000; // 30 seconds

/* ── STATE ── */
let currentPaymentData   = [];       // Full payment history array
let currentTrackerId     = null;     // Active payment submission ID for tracker
let autoRefreshTimer     = null;     // setInterval reference
let selectedFile         = null;     // File object for upload
let selectedBankFile     = null;     // File object for bank upload
let selectedPaymentMethod = null;    // 'gcash' | 'bank'
let currentReceiptImgSrc = '';       // Receipt image URL for modal
let currentReceiptRef    = '';       // Reference number currently viewed

/* ══════════════════════════════════════════════════════════
   1) INIT — Directly reveal portal, no loading screen
══════════════════════════════════════════════════════════ */
document.addEventListener('DOMContentLoaded', function() {
    initDashboard();
});


/* ══════════════════════════════════════════════════════════
   3) DASHBOARD INIT — Orchestrates all data fetches
══════════════════════════════════════════════════════════ */
async function initDashboard() {
    await Promise.all([
        loadEnrollmentStatus(),
        loadPaymentTracker(),
        loadPaymentHistory()
    ]);
    startAutoRefresh();
}

/* Auto-refresh payment tracker every 30 seconds */
function startAutoRefresh() {
    if (autoRefreshTimer) clearInterval(autoRefreshTimer);
    autoRefreshTimer = setInterval(() => {
        loadPaymentTracker(true);
    }, AUTO_REFRESH_INTERVAL);
}


/* ══════════════════════════════════════════════════════════
   4) API CALLS
══════════════════════════════════════════════════════════ */

/**
 * GET: /api/dashboard.php
 * Returns: { student_name, lrn, grade_level, section, academic_year, enrollment_status }
 */
async function fetchDashboard() {
    const res  = await fetch(`${API_BASE}/dashboard.php`, { credentials:'include' });
    const data = await res.json();
    if (!data.success) throw new Error(data.message || 'Failed');
    return data;
}

/**
 * GET: /api/enrollment_status.php
 * Returns: { success, student_name, lrn, grade_level, section, academic_year, status }
 */
async function loadEnrollmentStatus() {
    try {
        const data = await fetchDashboard();
        renderEnrollmentCard(data);
    } catch (e) {
        console.error('[Enrollment Status]', e);
        renderEnrollmentCardError();
    }
}

/**
 * GET: /api/payment_history.php
 * Returns: { success, payments: [...] }
 */
async function loadPaymentHistory() {
    try {
        const res  = await fetch(`${API_BASE}/payment_history.php`, { credentials:'include' });
        const data = await res.json();
        if (!data.success) throw new Error(data.message);
        currentPaymentData = data.payments || [];
        renderPaymentHistory(currentPaymentData);
        renderEnrollmentTimeline(data.enrollment_history || []);
        /* Sync count badge to current tab */
        const activeTab = document.querySelector('.history-tab.active')?.dataset.tab ?? 'table';
        updateHistoryCount(activeTab);
    } catch (e) {
        console.error('[Payment History]', e);
        renderPaymentHistoryError();
    }
}

/**
 * GET: /api/payment_tracker.php
 * Returns: { success, has_active, submission }
 */
async function loadPaymentTracker(silent = false) {
    try {
        const res  = await fetch(`${API_BASE}/payment_tracker.php`, { credentials:'include' });
        const data = await res.json();
        if (!data.success) throw new Error(data.message);
        renderPaymentTracker(data);
        if (data.has_active) {
            currentTrackerId = data.submission?.id ?? null;
            window._lastTrackerSub = data.submission ?? null;
        } else {
            window._lastTrackerSub = null;
        }
    } catch (e) {
        if (!silent) console.error('[Payment Tracker]', e);
    }
}

/* Open transaction detail from tracker card Details button */
function openTrackerDetail() {
    const sub = window._lastTrackerSub;
    if (!sub) return;
    // Use tracker data directly (now includes type/amount), fall back to history if needed
    const full = currentPaymentData.find(p => p.id === sub.id);
    openTransactionDetails(
        sub.reference_number,
        sub.submitted_at_formatted,
        sub.payment_type_label || (full ? full.payment_type_label : ''),
        '—',
        sub.amount_formatted || (full ? (full.amount_formatted || '—') : '—'),
        sub.id,
        sub.status,
        sub.rejection_reason || '',
        sub.confirmed_at_formatted || '',
        full ? (full.receipt_pdf_path || '') : ''
    );
}

/**
 * POST: /api/upload_payment.php
 * FormData: proof_image, reference_number, payment_type, amount
 */
async function submitPaymentProof(formData) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000); // 30s timeout
    try {
        const res = await fetch(`${API_BASE}/upload_payment.php`, {
            method: 'POST',
            credentials: 'include',
            body: formData,
            signal: controller.signal
        });
        clearTimeout(timeout);
        const text = await res.text();
        try {
            return JSON.parse(text);
        } catch {
            console.error('[upload] Non-JSON response:', text);
            return { success: false, message: 'Unexpected server response. Please try again.' };
        }
    } catch (err) {
        clearTimeout(timeout);
        if (err.name === 'AbortError') {
            return { success: false, message: 'Request timed out. Please check your connection and try again.' };
        }
        throw err;
    }
}

/**
 * GET: /api/receipt_image.php?id={id}
 * Returns: { success, image_url, reference_number }
 */
async function fetchReceiptImage(submissionId) {
    const res  = await fetch(`${API_BASE}/receipt_image.php?id=${submissionId}`, { credentials:'include' });
    return await res.json();
}

/**
 * GET: /api/download_receipt.php?id={id}
 * Triggers PDF download
 */
function downloadOfficialReceiptById(submissionId) {
    window.open(`${API_BASE}/download_receipt.php?id=${submissionId}`, '_blank');
}


/* ══════════════════════════════════════════════════════════
   5) RENDER FUNCTIONS
══════════════════════════════════════════════════════════ */

function renderEnrollmentCard(data) {
    document.getElementById('statusStudentName').textContent = data.student_name || '—';
    document.getElementById('statusLRN').textContent         = data.lrn          || '—';
    document.getElementById('statusAY').textContent          = data.academic_year || '—';
    document.getElementById('statusGrade').textContent       = data.grade_level  || '—';
    document.getElementById('statusSection').textContent     = data.section       || '—';

    /* Header badge */
    document.getElementById('headerStudentName').textContent = data.student_name || 'Student';
    const initial = (data.student_name || 'S').charAt(0).toUpperCase();
    document.getElementById('headerAvatar').textContent = initial;

    /* Enrollment status badge */
    const badge = document.getElementById('enrollmentBadge');
    const pulse = document.getElementById('statusPulse');
    const card  = document.getElementById('statusCard');
    const statusMap = {
        enrolled:        { label:'Enrolled',        cls:'status-enrolled',    pulseColor:'var(--green)' },
        registered:      { label:'Registered',      cls:'status-registered',  pulseColor:'var(--orange)' },
        pending:         { label:'Pending Approval',cls:'status-registered',  pulseColor:'var(--orange)' },
        pending_payment: { label:'Pending Payment', cls:'status-pending',     pulseColor:'var(--blue)' },
        payment_review:  { label:'Under Review',    cls:'status-review',      pulseColor:'var(--gold)' }
    };
    const s = statusMap[data.status] || { label: data.status, cls:'status-registered', pulseColor:'var(--orange)' };
    window._currentEnrollmentStatus = data.status;
    badge.textContent = s.label;
    badge.className   = `badge-status ${s.cls}`;
    pulse.style.background = s.pulseColor;
    pulse.style.setProperty('--pulse-color', s.pulseColor);
    /* Update ::after in status-pulse via inline approach */
    card.setAttribute('data-status', data.status);
}

function renderEnrollmentCardError() {
    document.getElementById('statusStudentName').textContent = 'Unable to load';
}

function renderEnrollmentTimeline(history) {
    const container = document.getElementById('enrollmentTimeline');
    const countEl   = document.getElementById('historyCount');
    countEl.textContent = `${history.length} Record${history.length !== 1 ? 's' : ''}`;

    if (!history.length) {
        container.innerHTML = `
            <div class="table-empty" style="padding:20px 0;">
                <p style="font-size:0.82rem;color:var(--text-muted);">No enrollment history found.</p>
            </div>`;
        return;
    }

    container.innerHTML = history.map((item, idx) => `
        <div class="timeline-item clickable"
             onclick="openTransactionDetails(
                '${esc(item.reference_number)}',
                '${esc(item.date)}',
                '${esc(item.payment_type)}',
                '${esc(item.cashier_name)}',
                '${esc(item.amount_formatted)}',
                ${item.submission_id || 0},
                '${esc(item.status)}',
                '${esc(item.rejection_reason || '')}',
                '${esc(item.confirmed_at || '')}',
                '${esc(item.receipt_pdf_path || '')}'
             )">
            <div class="timeline-marker ${idx === 0 ? 'active' : ''}"></div>
            <div class="timeline-content">
                <div class="timeline-main">
                    <span class="ay-text">${esc(item.academic_year)}</span>
                    <span class="status-pill ${getHistoryPillClass(item.status)}">${esc(formatStatus(item.status))}</span>
                </div>
                <p class="semester-subtext">${esc(item.grade_level)} • Click to view transaction</p>
            </div>
        </div>
    `).join('');
}

function renderPaymentHistory(payments) {
    const container = document.getElementById('paymentHistoryContainer');
    if (!payments.length) {
        container.innerHTML = `
            <div class="table-empty">
                <div class="table-empty-icon">💳</div>
                <p>No payment records yet</p>
                <span>Upload a payment proof using the "Submit Payment Proof" button above. Once submitted, it will appear here.</span>
            </div>`;
        return;
    }

    container.innerHTML = `
        <table class="payment-table" id="paymentTable">
            <thead>
                <tr>
                    <th>Date</th>
                    <th>Reference No.</th>
                    <th>Type</th>
                    <th>Amount</th>
                    <th>Status</th>
                    <th></th>
                </tr>
            </thead>
            <tbody id="paymentTableBody">
                ${renderPaymentRows(payments)}
            </tbody>
        </table>`;
}

function renderPaymentRows(payments) {
    return payments.map(p => `
        <tr onclick="openTransactionDetails(
            '${esc(p.reference_number)}',
            '${esc(p.submitted_date)}',
            '${esc(p.payment_type_label || formatStatus(p.payment_type))}',
            '${esc(p.cashier_name || '—')}',
            '${esc(p.amount_formatted || '—')}',
            ${p.id || 0},
            '${esc(p.status)}',
            '${esc(p.rejection_reason || '')}',
            '${esc(p.confirmed_at || '')}',
            '${esc(p.receipt_pdf_path || '')}'
        )">
            <td>${esc(p.submitted_date)}</td>
            <td><span class="table-ref">${esc(p.reference_number)}</span></td>
            <td>${esc(p.payment_type_label || formatStatus(p.payment_type))}</td>
            <td><span class="table-amount">${esc(p.amount_formatted || 'Pending')}</span></td>
            <td><span class="status-pill ${getHistoryPillClass(p.status)}">${esc(formatStatus(p.status))}</span></td>
            <td><button class="table-action-btn">View</button></td>
        </tr>
    `).join('');
}

function renderPaymentHistoryError() {
    document.getElementById('paymentHistoryContainer').innerHTML = `
        <div class="table-empty">
            <div class="table-empty-icon">⚠️</div>
            <p>Failed to load payment history</p>
            <span>Please refresh the page and try again.</span>
        </div>`;
}

function renderPaymentTracker(data) {
    const card = document.getElementById('trackerCard');

    if (!data.has_active) {
        card.innerHTML = `
            <div class="tracker-empty">
                <div class="tracker-empty-icon">📋</div>
                <p>No active payment submission to track.</p>
                <span>Submit a proof of payment to see live status here.</span>
            </div>`;
        return;
    }

    const sub   = data.submission;

    // ── Check if this outcome was already dismissed by the student ──
    const dismissKey = `tracker_dismissed_${sub.id}_${sub.status}`;
    if (localStorage.getItem(dismissKey) === '1') {
        card.innerHTML = `
            <div class="tracker-empty">
                <div class="tracker-empty-icon">📋</div>
                <p>No active payment submission to track.</p>
                <span>Submit a proof of payment to see live status here.</span>
            </div>`;
        return;
    }

    const steps = buildStepperSteps(sub);

    const isVerified = sub.status === 'verified' || sub.status === 'reflected_to_enrollment';
    const isRejected = sub.status === 'rejected';

    // ── Outcome banners ──
    const rejectionBanner = isRejected ? `
        <div class="tracker-rejection-notice" style="background:#fff0f0;border:1px solid #fca5a5;border-radius:8px;padding:12px 16px;margin:12px 0;display:flex;gap:10px;align-items:flex-start;">
            <span style="font-size:1.1rem;">⚠️</span>
            <div style="flex:1;">
                <strong style="color:#b91c1c;font-size:0.85rem;">Payment Rejected</strong>
                <p style="color:#7f1d1d;font-size:0.82rem;margin-top:4px;">${esc(sub.rejection_reason)}</p>
            </div>
        </div>` : '';

    const approvedBanner = isVerified ? `
        <div class="tracker-approved-notice" style="background:#f0fdf4;border:1px solid #86efac;border-radius:8px;padding:12px 16px;margin:12px 0;display:flex;gap:10px;align-items:flex-start;">
            <span style="font-size:1.1rem;">✅</span>
            <div style="flex:1;">
                <strong style="color:#15803d;font-size:0.85rem;">Payment Approved!</strong>
                <p style="color:#166534;font-size:0.82rem;margin-top:4px;">Your payment has been verified by the cashier. Your enrollment status has been updated.</p>
                <a href="api/download_receipt.php?id=${sub.id}" target="_blank"
                   style="display:inline-flex;align-items:center;gap:5px;margin-top:8px;font-size:0.8rem;font-weight:600;color:#15803d;text-decoration:underline;cursor:pointer;">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                    Download Receipt
                </a>
            </div>
        </div>` : '';

    // ── Dismiss / Got it button ──
    const dismissBtn = (isRejected || isVerified) ? `
        <div style="display:flex;justify-content:flex-end;margin-top:16px;">
            <button
                class="tracker-dismiss-btn ${isRejected ? 'tracker-dismiss-rejected' : 'tracker-dismiss-approved'}"
                onclick="dismissTracker(${sub.id}, '${esc(sub.status)}')"
            >
                ${isRejected
                    ? `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg> Dismiss`
                    : `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg> Got it, Dismiss`
                }
            </button>
        </div>` : '';

    card.innerHTML = `
        <div class="tracker-live">
            <div class="tracker-ref-header">
                <div>
                    <div class="tracker-ref-label">Tracking Reference</div>
                    <div class="tracker-ref-value">${esc(sub.reference_number)}</div>
                </div>
                <div style="display:flex;align-items:center;gap:10px;">
                    <span class="status-pill ${getHistoryPillClass(sub.status)}">${esc(formatStatus(sub.status))}</span>
                    <button class="tracker-view-btn" onclick="openTrackerDetail()" title="View Details">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                        Details
                    </button>
                </div>
            </div>
            ${rejectionBanner}
            ${approvedBanner}
            <div class="stepper">
                ${steps.map(step => `
                    <div class="step-item ${step.state}">
                        <div class="step-dot">${step.state === 'done' ? '✓' : (step.state === 'rejected' ? '✕' : step.num)}</div>
                        <div class="step-label">${step.label}</div>
                        <div class="step-time">${step.time || ''}</div>
                    </div>
                `).join('')}
            </div>
            <div class="tracker-processing-note">
                ⏱ ${sub.status === 'uploaded' || sub.status === 'under_review'
                    ? 'Estimated review time: 1–2 business days. Payments submitted before 3:00 PM are usually verified the same day.'
                    : isVerified
                    ? 'Your payment has been verified. Please allow a few moments for enrollment status to update.'
                    : 'Your submission requires attention. Please review the rejection reason above.'}
            </div>
            ${dismissBtn}
        </div>`;
}

/* ══════════════════════════════════════════════════════════
   6) HELPERS
══════════════════════════════════════════════════════════ */

/**
 * Dismiss the payment tracker for a specific outcome.
 * Uses localStorage so the card stays gone across page reloads,
 * until the student submits a new payment.
 */
function dismissTracker(submissionId, status) {
    const dismissKey = `tracker_dismissed_${submissionId}_${status}`;
    localStorage.setItem(dismissKey, '1');

    const card = document.getElementById('trackerCard');
    // Animate out then show empty state
    card.style.transition = 'opacity 0.3s ease';
    card.style.opacity = '0';
    setTimeout(() => {
        card.style.opacity = '';
        card.style.transition = '';
        card.innerHTML = `
            <div class="tracker-empty">
                <div class="tracker-empty-icon">📋</div>
                <p>No active payment submission to track.</p>
                <span>Submit a proof of payment to see live status here.</span>
            </div>`;
    }, 300);
}
function esc(str) {
    if (str === null || str === undefined) return '';
    return String(str)
        .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
        .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

function formatStatus(status) {
    const map = {
        uploaded:                 'Uploaded',
        under_review:             'Under Review',
        verified:                 'Verified',
        rejected:                 'Rejected',
        reflected_to_enrollment:  'Reflected',
        payment_review:           'Under Review',
        confirmed:                'Confirmed',
        enrolled:                 'Enrolled',
        registered:               'Registered',
        pending_payment:          'Pending',
        full:                     'Full Payment',
        partial:                  'Partial'
    };
    return map[status] || (status ? status.replace(/_/g,' ') : '—');
}

function getHistoryPillClass(status) {
    const map = {
        uploaded:                'status-review-pil',
        under_review:            'status-review-pil',
        verified:                'status-completed',
        reflected_to_enrollment: 'status-completed',
        confirmed:               'status-completed',
        enrolled:                'status-completed',
        rejected:                'status-rejected-pil',
        registered:              'status-pending-pil',
        pending_payment:         'status-pending-pil',
        payment_review:          'status-review-pil'
    };
    return map[status] || 'status-pending-pil';
}

function buildStepperSteps(sub) {
    const allSteps = [
        { key:'uploaded',                label:'Uploaded',  num:'1' },
        { key:'under_review',            label:'Review',    num:'2' },
        { key:'verified',                label:'Verified',  num:'3' },
        { key:'reflected_to_enrollment', label:'Reflected', num:'4' }
    ];
    const order   = allSteps.map(s => s.key);
    const rejected = sub.status === 'rejected';
    const current  = rejected ? 'under_review' : sub.status;
    const currentIdx = order.indexOf(current);

    return allSteps.map((step, idx) => {
        let state = 'pending';
        if (idx < currentIdx) state = 'done';
        else if (idx === currentIdx) state = rejected ? 'rejected' : 'active';
        return { ...step, state, time: getStepTime(sub, step.key) };
    });
}

function getStepTime(sub, key) {
    const map = {
        uploaded:                sub.submitted_at_formatted || '',
        under_review:            sub.review_started_at_formatted || '',
        verified:                sub.confirmed_at_formatted || '',
        reflected_to_enrollment: sub.reflected_to_enrollment_at_formatted || ''
    };
    return map[key] || '';
}


/* ══════════════════════════════════════════════════════════
   7) UPLOAD MODAL
══════════════════════════════════════════════════════════ */
function openUploadModal() {
    if (window._currentEnrollmentStatus === 'pending') {
        const modal = document.getElementById('pendingRegistrationModal');
        if (modal) { modal.style.display = 'flex'; modal.classList.add('active'); document.body.style.overflow = 'hidden'; }
        return;
    }
    const txModal = document.getElementById('transactionModal');
    if (txModal.classList.contains('active')) closeTransactionModal();

    const modal = document.getElementById('uploadModal');
    modal.style.display = 'flex';
    modal.classList.add('active');
    document.body.style.overflow = 'hidden';
    resetUpload();
}

function closePendingRegistrationModal() {
    const modal = document.getElementById('pendingRegistrationModal');
    if (!modal) return;
    modal.classList.remove('active');
    setTimeout(() => { modal.style.display = 'none'; document.body.style.overflow = ''; }, 300);
}

function closeUploadModal() {
    const modal = document.getElementById('uploadModal');
    modal.style.display = 'none';
    modal.classList.remove('active');
    document.body.style.overflow = '';
    resetUpload();
}

function resetUpload() {
    selectedFile         = null;
    selectedBankFile     = null;
    selectedPaymentMethod = null;

    // Reset all steps
    setStepVisible('uploadStep0', true);
    setStepVisible('uploadStep1Gcash', false);
    setStepVisible('uploadStep1Bank', false);
    setStepVisible('uploadStep2', false);

    // Reset method card selection state
    document.getElementById('methodGcash')?.classList.remove('selected');
    document.getElementById('methodBank')?.classList.remove('selected');
    document.getElementById('gcashCheck')?.classList.remove('visible');
    document.getElementById('bankCheck')?.classList.remove('visible');
    const mBtn = document.getElementById('methodProceedBtn');
    if (mBtn) mBtn.disabled = true;

    // Reset GCash form
    const refInput = document.getElementById('refNumberInput');
    if (refInput) { refInput.value = ''; refInput.classList.remove('error'); }
    const amtInput = document.getElementById('amountInput');
    if (amtInput) amtInput.value = '';
    const proceedBtn = document.getElementById('proceedBtn');
    if (proceedBtn) proceedBtn.disabled = true;
    const dropZone = document.getElementById('dropZone');
    if (dropZone) { const p = dropZone.querySelector('p'); const s = dropZone.querySelector('span'); if (p) p.textContent = 'Click to browse or drag image here'; if (s) s.textContent = 'JPG, PNG, WEBP — max 5MB'; }
    const proofUpload = document.getElementById('proofUpload');
    if (proofUpload) proofUpload.value = '';

    // Reset bank form
    const bankRef = document.getElementById('bankRefInput');
    if (bankRef) { bankRef.value = ''; bankRef.classList.remove('error'); }
    const bankSel = document.getElementById('bankNameSelect');
    if (bankSel) bankSel.value = 'BDO';

    const bankAmt = document.getElementById('bankAmountInput');
    if (bankAmt) bankAmt.value = '';
    const bankProceed = document.getElementById('bankProceedBtn');
    if (bankProceed) bankProceed.disabled = true;
    const bankDrop = document.getElementById('bankDropZone');
    if (bankDrop) { const p = bankDrop.querySelector('p'); const s = bankDrop.querySelector('span'); if (p) p.textContent = 'Click to browse or drag image here'; if (s) s.textContent = 'JPG, PNG, WEBP — max 5MB'; }
    const bankProof = document.getElementById('bankProofUpload');
    if (bankProof) bankProof.value = '';

    // Reset image preview
    const imgPrev = document.getElementById('imagePreview');
    if (imgPrev) imgPrev.src = '';

    // Stepper reset
    updateStepper(0);
}

function setStepVisible(id, visible) {
    const el = document.getElementById(id);
    if (el) el.style.display = visible ? 'block' : 'none';
}

function updateStepper(activeIdx) {
    [0,1,2].forEach(i => {
        const ind = document.getElementById(`uStep${i+1}Ind`);
        if (!ind) return;
        ind.classList.toggle('active', i === activeIdx);
        ind.classList.toggle('done', i < activeIdx);
    });
}

/* ── Method Selection ── */
function selectPaymentMethod(method) {
    selectedPaymentMethod = method;
    document.getElementById('methodGcash').classList.toggle('selected', method === 'gcash');
    document.getElementById('methodBank').classList.toggle('selected', method === 'bank');
    document.getElementById('gcashCheck').classList.toggle('visible', method === 'gcash');
    document.getElementById('bankCheck').classList.toggle('visible', method === 'bank');
    document.getElementById('methodProceedBtn').disabled = false;
}

function handleMethodProceed() {
    if (!selectedPaymentMethod) return;
    setStepVisible('uploadStep0', false);
    if (selectedPaymentMethod === 'gcash') {
        setStepVisible('uploadStep1Gcash', true);
        updateStepper(1);
    } else {
        setStepVisible('uploadStep1Bank', true);
        updateStepper(1);
    }
}

function goBackToMethodSelect() {
    setStepVisible('uploadStep1Gcash', false);
    setStepVisible('uploadStep1Bank', false);
    setStepVisible('uploadStep0', true);
    updateStepper(0);
}

/* ── Copy to clipboard ── */
function copyToClipboard(text, el) {
    navigator.clipboard.writeText(text).catch(() => {});
    const orig = el.innerHTML;
    el.innerHTML = text + ' <svg class="copy-icon" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#1A7A3C" stroke-width="3"><polyline points="20 6 9 17 4 12"/></svg>';
    el.style.color = 'var(--green)';
    setTimeout(() => { el.innerHTML = orig; el.style.color = ''; }, 2000);
}

/* ── GCash file input ── */
document.getElementById('proofUpload').addEventListener('change', function(e) {
    const file = e.target.files[0];
    if (!file) return;
    const allowedTypes = ['image/jpeg','image/jpg','image/png','image/webp'];
    if (!allowedTypes.includes(file.type)) { showToast('Invalid Format', 'Only JPG, PNG, and WEBP files are allowed.', 'error'); this.value = ''; return; }
    if (file.size > 5 * 1024 * 1024) { showToast('File Too Large', 'Please upload an image smaller than 5MB.', 'error'); this.value = ''; return; }
    selectedFile = file;
    const dropZone = document.getElementById('dropZone');
    dropZone.querySelector('p').textContent = file.name;
    dropZone.querySelector('span').textContent = (file.size / 1024).toFixed(0) + ' KB — click to change';
    checkProceedReady();
});

document.getElementById('refNumberInput').addEventListener('input', function() {
    this.value = this.value.replace(/\D/g, '');
    const hint = this.closest('.form-field')?.querySelector('.field-hint');
    if (hint) {
        const len = this.value.length;
        if (len === 0) { hint.textContent = 'Enter the 13-digit GCash reference number from your receipt'; hint.style.color = ''; }
        else if (len < 13) { hint.textContent = `${len} / 13 digits entered`; hint.style.color = 'var(--text-muted)'; }
        else { hint.textContent = '✓ 13 digits — Reference number format is valid'; hint.style.color = 'var(--green)'; }
    }
    checkProceedReady();
});

function checkProceedReady() {
    const ref  = document.getElementById('refNumberInput').value.trim();
    const proc = document.getElementById('proceedBtn');
    if (proc) proc.disabled = !(ref.length === 13 && /^\d{13}$/.test(ref) && selectedFile);
}

/* ── Drag-and-drop GCash ── */
const dropZoneEl = document.getElementById('dropZone');
['dragenter','dragover'].forEach(evt => dropZoneEl.addEventListener(evt, e => { e.preventDefault(); dropZoneEl.classList.add('dragover'); }));
['dragleave','drop'].forEach(evt => dropZoneEl.addEventListener(evt, e => {
    e.preventDefault(); dropZoneEl.classList.remove('dragover');
    if (e.type === 'drop' && e.dataTransfer.files.length) {
        document.getElementById('proofUpload').files = e.dataTransfer.files;
        document.getElementById('proofUpload').dispatchEvent(new Event('change'));
    }
}));

/* ── Bank file input ── */
document.getElementById('bankProofUpload').addEventListener('change', function(e) {
    const file = e.target.files[0];
    if (!file) return;
    const allowedTypes = ['image/jpeg','image/jpg','image/png','image/webp'];
    if (!allowedTypes.includes(file.type)) { showToast('Invalid Format', 'Only JPG, PNG, and WEBP files are allowed.', 'error'); this.value = ''; return; }
    if (file.size > 5 * 1024 * 1024) { showToast('File Too Large', 'Please upload an image smaller than 5MB.', 'error'); this.value = ''; return; }
    selectedBankFile = file;
    const dropZone = document.getElementById('bankDropZone');
    dropZone.querySelector('p').textContent = file.name;
    dropZone.querySelector('span').textContent = (file.size / 1024).toFixed(0) + ' KB — click to change';
    checkBankProceedReady();
});

document.getElementById('bankRefInput').addEventListener('input', function() {
    this.value = this.value.replace(/\D/g, '').slice(0, 20);
    const hint = this.closest('.form-field')?.querySelector('.field-hint');
    if (hint) {
        const len = this.value.length;
        if (len === 0)        { hint.textContent = 'Enter the 16–20 digit bank transaction number (numbers only)'; hint.style.color = ''; }
        else if (len < 16)    { hint.textContent = `${len} / 16–20 digits entered`; hint.style.color = 'var(--text-muted)'; }
        else                  { hint.textContent = '✓ Reference number format is valid'; hint.style.color = 'var(--green)'; }
    }
    checkBankProceedReady();
});

/* ── Show/hide "Other" text field based on select value ── */
function handleBankSelectChange() {
    checkBankProceedReady();
}

function checkBankProceedReady() {
    const ref = document.getElementById('bankRefInput').value.trim();
    const btn = document.getElementById('bankProceedBtn');
    if (btn) btn.disabled = !(ref.length >= 16 && ref.length <= 20 && /^\d+$/.test(ref) && selectedBankFile);
}

/* ── Drag-and-drop Bank ── */
const bankDropZoneEl = document.getElementById('bankDropZone');
['dragenter','dragover'].forEach(evt => bankDropZoneEl.addEventListener(evt, e => { e.preventDefault(); bankDropZoneEl.classList.add('dragover'); }));
['dragleave','drop'].forEach(evt => bankDropZoneEl.addEventListener(evt, e => {
    e.preventDefault(); bankDropZoneEl.classList.remove('dragover');
    if (e.type === 'drop' && e.dataTransfer.files.length) {
        document.getElementById('bankProofUpload').files = e.dataTransfer.files;
        document.getElementById('bankProofUpload').dispatchEvent(new Event('change'));
    }
}));

/* ── GCash: Proceed to preview ── */
function handleProceedToPreview() {
    const refInput = document.getElementById('refNumberInput');
    const ref = refInput.value.trim();
    if (!ref) { refInput.classList.add('error'); showToast('Reference Required', 'Please enter your GCash reference number.', 'error'); refInput.focus(); return; }
    if (!/^\d{13}$/.test(ref)) { refInput.classList.add('error'); showToast('Invalid Reference Number', 'GCash reference number must be exactly 13 digits.', 'error'); refInput.focus(); return; }
    if (!selectedFile) { showToast('Receipt Required', 'Please upload your payment receipt image.', 'error'); return; }
    refInput.classList.remove('error');

    const payType = document.querySelector('input[name="paymentType"]:checked')?.value || 'partial';
    const amount  = document.getElementById('amountInput').value || '—';

    document.getElementById('previewMethod').textContent  = 'GCash';
    document.getElementById('previewRefNo').textContent   = ref;
    document.getElementById('previewPayType').textContent = payType === 'full' ? 'Full Payment' : 'Partial Payment';
    document.getElementById('previewAmount').textContent  = amount !== '—' ? '₱' + parseFloat(amount).toLocaleString('en-PH', {minimumFractionDigits:2}) : '—';
    const bankNameRow = document.getElementById('bankNameRow');
    if (bankNameRow) bankNameRow.style.display = 'none';

    const reader = new FileReader();
    reader.onload = (ev) => {
        document.getElementById('imagePreview').src = ev.target.result;
        setStepVisible('uploadStep1Gcash', false);
        setStepVisible('uploadStep2', true);
        updateStepper(2);
    };
    reader.readAsDataURL(selectedFile);
}

/* ── Bank: Proceed to preview ── */
function handleBankProceedToPreview() {
    const bankRef    = document.getElementById('bankRefInput');
    const ref        = bankRef.value.trim();
    const bankName   = 'BDO';

    if (!ref || !/^\d{16,20}$/.test(ref)) {
        bankRef.classList.add('error');
        showToast('Invalid Reference', 'Bank reference number must be 16–20 digits (numbers only).', 'error');
        bankRef.focus();
        return;
    }
    if (!selectedBankFile) {
        showToast('Receipt Required', 'Please upload your bank receipt image.', 'error');
        return;
    }

    bankRef.classList.remove('error');

    const payType = document.querySelector('input[name="bankPaymentType"]:checked')?.value || 'partial';
    const amount  = document.getElementById('bankAmountInput').value || '—';

    document.getElementById('previewMethod').textContent   = 'Bank Transfer';
    document.getElementById('previewBankName').textContent = bankName;
    document.getElementById('previewRefNo').textContent    = ref;
    document.getElementById('previewPayType').textContent  = payType === 'full' ? 'Full Payment' : 'Partial Payment';
    document.getElementById('previewAmount').textContent   = amount !== '—' ? '₱' + parseFloat(amount).toLocaleString('en-PH', {minimumFractionDigits:2}) : '—';
    const bankNameRow = document.getElementById('bankNameRow');
    if (bankNameRow) bankNameRow.style.display = 'flex';

    // Use bankFile as the active selectedFile for submission
    selectedFile = selectedBankFile;

    const reader = new FileReader();
    reader.onload = (ev) => {
        document.getElementById('imagePreview').src = ev.target.result;
        setStepVisible('uploadStep1Bank', false);
        setStepVisible('uploadStep2', true);
        updateStepper(2);
    };
    reader.readAsDataURL(selectedBankFile);
}

/* ── Confirm and submit to backend ── */
async function handleConfirmUpload() {
    const confirmBtn  = document.getElementById('confirmSubmitBtn');
    const confirmText = document.getElementById('confirmBtnText');
    const confirmLoad = document.getElementById('confirmBtnLoader');

    confirmBtn.disabled   = true;
    confirmText.style.display = 'none';
    confirmLoad.style.display = 'inline-block';

    // Pick correct form values based on method
    let ref, payType, amount;
    if (selectedPaymentMethod === 'bank') {
        ref     = document.getElementById('bankRefInput').value.trim();
        payType = document.querySelector('input[name="bankPaymentType"]:checked')?.value || 'partial';
        amount  = document.getElementById('bankAmountInput').value || '';
    } else {
        ref     = document.getElementById('refNumberInput').value.trim();
        payType = document.querySelector('input[name="paymentType"]:checked')?.value || 'partial';
        amount  = document.getElementById('amountInput').value || '';
    }

    const formData = new FormData();
    formData.append('proof_image',       selectedFile);
    formData.append('reference_number',  ref);
    formData.append('payment_type',      payType);
    formData.append('payment_channel',   selectedPaymentMethod === 'bank' ? 'bank_transfer' : 'gcash');
    if (amount) formData.append('amount', amount);
    if (selectedPaymentMethod === 'bank') {
        formData.append('bank_name', 'BDO');
    }

    try {
        const data = await submitPaymentProof(formData);
        if (data.success) {
            closeUploadModal();
            showToast('Submission Received ✓', 'Your payment proof is now under review. You will be notified once confirmed.', 'success');
            loadPaymentTracker();
            loadPaymentHistory();
            loadEnrollmentStatus();
            return; // exit before finally restores button (modal is closed)
        } else {
            showToast('Submission Failed', data.message || 'Please check your inputs and try again.', 'error');
        }
    } catch (err) {
        showToast('Network Error', 'Could not connect to server. Please try again.', 'error');
    } finally {
        // Always restore button unless modal was closed (success path returns early)
        confirmBtn.disabled       = false;
        confirmText.style.display = 'inline';
        confirmLoad.style.display = 'none';
    }
}


/* ══════════════════════════════════════════════════════════
   8) TRANSACTION DETAIL MODAL
══════════════════════════════════════════════════════════ */
let activeSubmissionId = null;

let _txCloseTimer = null;

function openTransactionDetails(ref, date, type, cashier, amount, submissionId, status, rejectionReason, confirmedAt, pdfPath) {
    /* Cancel any in-flight close timer so it can't hide the modal after we open it */
    if (_txCloseTimer) { clearTimeout(_txCloseTimer); _txCloseTimer = null; }

    /* Close the upload modal if it happens to be open */
    const upModal = document.getElementById('uploadModal');
    if (upModal.classList.contains('active')) {
        upModal.style.display = 'none';
        upModal.classList.remove('active');
        document.body.style.overflow = '';
    }

    const modal = document.getElementById('transactionModal');
    activeSubmissionId = submissionId || null;

    /* Inject data */
    document.getElementById('t-ref').textContent       = ref    || '—';
    document.getElementById('t-date-header').textContent = 'Issued on ' + (date || '—');
    document.getElementById('t-type').textContent      = type   || '—';
    document.getElementById('t-amount').textContent    = amount || '—';
    document.getElementById('t-confirmed').textContent = confirmedAt || 'Pending';

    /* Rejection block */
    const rejBlock = document.getElementById('rejectionBlock');
    if (status === 'rejected' && rejectionReason) {
        document.getElementById('rejectionReason').textContent = rejectionReason;
        rejBlock.style.display = 'flex';
    } else {
        rejBlock.style.display = 'none';
    }

    /* Mini tracker */
    renderMiniTracker(status);

    /* PDF download button: show only when verified */
    const pdfBtn = document.getElementById('downloadPdfBtn');
    pdfBtn.style.display = (status === 'verified' || status === 'reflected_to_enrollment') ? 'flex' : 'none';

    /* Unsend button: show only for 'uploaded' status (not yet under review) */
    const unsendBtn = document.getElementById('unsendBtn');
    unsendBtn.style.display = (status === 'uploaded') ? 'flex' : 'none';
    unsendBtn.setAttribute('data-status', status);

    /* Current receipt ref for image modal */
    currentReceiptRef = ref;

    /* Show */
    modal.style.display = 'flex';
    modal.classList.add('active');
    document.body.style.overflow = 'hidden';
    setTimeout(() => document.getElementById('transactionCard').style.opacity = '1', 10);
}

function renderMiniTracker(currentStatus) {
    const steps = [
        { key:'uploaded',                label:'Uploaded' },
        { key:'under_review',            label:'Under Review' },
        { key:'verified',                label:'Verified' },
        { key:'reflected_to_enrollment', label:'Reflected to Enrollment' }
    ];
    const order       = steps.map(s => s.key);
    const isRejected  = currentStatus === 'rejected';
    const activeKey   = isRejected ? 'under_review' : currentStatus;
    const currentIdx  = order.indexOf(activeKey);

    const container = document.getElementById('miniTracker');
    container.innerHTML = steps.map((step, idx) => {
        let state = 'pending';
        if (idx < currentIdx) state = 'done';
        else if (idx === currentIdx) state = isRejected ? 'rejected' : 'active';
        return `
            <div class="mini-step-row">
                <div class="mini-step-dot ${state}"></div>
                <span class="mini-step-label${state === 'pending' ? ' muted' : ''}">${step.label}</span>
            </div>`;
    }).join('');
}

function closeTransactionModal() {
    const modal = document.getElementById('transactionModal');
    modal.classList.remove('active');
    _txCloseTimer = setTimeout(() => {
        modal.style.display = 'none';
        document.getElementById('transactionCard').style.opacity = '';
        document.body.style.overflow = '';
        _txCloseTimer = null;
    }, 300);
}

function viewActualReceipt() {
    if (!activeSubmissionId) {
        showToast('No Receipt', 'Receipt image is not available yet.', 'error');
        return;
    }

    /* Fetch actual receipt URL from backend */
    fetchReceiptImage(activeSubmissionId).then(data => {
        if (data.success) {
            openReceiptImageModal(data.image_url, data.reference_number);
        } else {
            showToast('Receipt Not Found', data.message || 'Receipt image unavailable.', 'error');
        }
    }).catch(() => {
        showToast('Error', 'Could not load receipt image.', 'error');
    });
}

function downloadOfficialReceipt() {
    if (!activeSubmissionId) {
        showToast('Not Available', 'PDF receipt is only available for confirmed payments.', 'error');
        return;
    }
    downloadOfficialReceiptById(activeSubmissionId);
}

/* ── UNSEND SUBMISSION ── */
async function confirmUnsendSubmission() {
    if (!activeSubmissionId) return;
    const confirmed = window.confirm(
        'Are you sure you want to unsend this payment submission?\n\n' +
        'This will permanently remove it from the system. Only do this if you submitted by mistake.'
    );
    if (!confirmed) return;

    const unsendBtn = document.getElementById('unsendBtn');
    unsendBtn.disabled = true;
    unsendBtn.textContent = 'Removing...';

    try {
        const res = await fetch(`${API_BASE}/cancel_submission.php`, {
            method: 'POST',
            credentials: 'include',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ submission_id: activeSubmissionId })
        });
        const data = await res.json();
        if (data.success) {
            closeTransactionModal();
            showToast('Submission Removed', 'Your payment submission has been unsent successfully.', 'success');
            loadPaymentTracker();
            loadPaymentHistory();
            loadEnrollmentStatus();
        } else {
            showToast('Cannot Unsend', data.message || 'This submission can no longer be unsent.', 'error');
            unsendBtn.disabled = false;
            unsendBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="9 14 4 9 9 4"/><path d="M20 20v-7a4 4 0 00-4-4H4"/></svg> Unsend Submission';
        }
    } catch (err) {
        showToast('Network Error', 'Could not connect to server. Please try again.', 'error');
        unsendBtn.disabled = false;
        unsendBtn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="9 14 4 9 9 4"/><path d="M20 20v-7a4 4 0 00-4-4H4"/></svg> Unsend Submission';
    }
}


/* ══════════════════════════════════════════════════════════
   9) RECEIPT IMAGE MODAL
══════════════════════════════════════════════════════════ */
function openReceiptImageModal(imgSrc, refNumber) {
    const modal = document.getElementById('receiptImageModal');
    document.getElementById('receiptPreviewImg').src   = imgSrc;
    document.getElementById('receiptRefLabel').textContent = refNumber || '';
    modal.style.display = 'flex';
}

function closeReceiptImageModal() {
    const modal = document.getElementById('receiptImageModal');
    modal.style.display = 'none';
    document.getElementById('receiptPreviewImg').src = '';
}


/* ══════════════════════════════════════════════════════════
   10) PAYMENT SEARCH / FILTER
══════════════════════════════════════════════════════════ */
function filterPayments() {
    const query  = document.getElementById('paymentSearch').value.toLowerCase().trim();
    const tbody  = document.getElementById('paymentTableBody');
    if (!tbody) return;

    const filtered = query
        ? currentPaymentData.filter(p =>
            (p.reference_number || '').toLowerCase().includes(query) ||
            (p.cashier_name    || '').toLowerCase().includes(query)  ||
            (p.payment_type    || '').toLowerCase().includes(query)
          )
        : currentPaymentData;

    tbody.innerHTML = renderPaymentRows(filtered);
}


/* ══════════════════════════════════════════════════════════
   11) TOAST SYSTEM
══════════════════════════════════════════════════════════ */
const toastIcons = { success:'✓', error:'✕', warning:'⚠' };

function showToast(title, message, type = 'success') {
    const container = document.getElementById('toastContainer');
    const toast = document.createElement('div');
    toast.className = `premium-toast toast-${type}`;
    toast.innerHTML = `
        <div class="toast-icon">${toastIcons[type] || '•'}</div>
        <div class="toast-content">
            <h4>${esc(title)}</h4>
            <p>${esc(message)}</p>
        </div>
        <div class="toast-timer"></div>`;
    container.appendChild(toast);

    setTimeout(() => {
        toast.classList.add('fade-out');
        setTimeout(() => toast.remove(), 450);
    }, 5000);
}


/* ══════════════════════════════════════════════════════════
   12) GLOBAL CLICK — Close modals on outside click
══════════════════════════════════════════════════════════ */
window.addEventListener('click', function(e) {
    const imgModal     = document.getElementById('receiptImageModal');
    const txModal      = document.getElementById('transactionModal');
    const upModal      = document.getElementById('uploadModal');
    const historyModal = document.getElementById('historyModal');

    if (e.target === imgModal)     closeReceiptImageModal();
    if (e.target === txModal)      closeTransactionModal();
    if (e.target === upModal)      closeUploadModal();
    if (e.target === historyModal) closeHistoryModal();
    const pendingModal = document.getElementById('pendingRegistrationModal');
    if (e.target === pendingModal) closePendingRegistrationModal();
});

/* ── ESC key close ── */
window.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closeReceiptImageModal();
        closeTransactionModal();
        closeUploadModal();
        closeHistoryModal();
        closePendingRegistrationModal();
    }
});


/* ══════════════════════════════════════════════════════════
   13) HISTORY SECTION — TAB SWITCHING & SCROLL
══════════════════════════════════════════════════════════ */

function switchHistoryTab(tab, btn) {
    /* Update tab buttons */
    document.querySelectorAll('.history-tab').forEach(t => t.classList.remove('active'));
    btn.classList.add('active');

    /* Toggle panels */
    document.getElementById('tabTable').style.display    = tab === 'table'    ? 'block' : 'none';
    document.getElementById('tabTimeline').style.display = tab === 'timeline' ? 'block' : 'none';

    /* Update the count badge to match the visible panel */
    updateHistoryCount(tab);
}

function updateHistoryCount(tab) {
    const countEl = document.getElementById('historyCount');
    if (!countEl) return;
    if (tab === 'table') {
        const n = currentPaymentData.length;
        countEl.textContent = `${n} Transaction${n !== 1 ? 's' : ''}`;
    }
    // timeline count is set inside renderEnrollmentTimeline
}

function scrollToHistory() {
    openHistoryModal();
}

function openHistoryModal() {
    const modal = document.getElementById('historyModal');
    if (!modal) return;
    modal.style.display = 'flex';
    requestAnimationFrame(() => modal.classList.add('active'));
    document.body.style.overflow = 'hidden';
    /* Refresh data when opening so content is current */
    loadPaymentHistory();
}

function closeHistoryModal() {
    const modal = document.getElementById('historyModal');
    if (!modal) return;
    modal.classList.remove('active');
    setTimeout(() => {
        modal.style.display = 'none';
        document.body.style.overflow = '';
    }, 320);
}


/* ══════════════════════════════════════════════════════════
   14) PDF RECEIPT EXPORT (client-side, no library needed)
   Generates a printer-friendly HTML window and triggers
   window.print() → browser "Save as PDF".
   Falls back to the server-side download_receipt.php for
   verified/reflected payments which have a real receipt.
══════════════════════════════════════════════════════════ */

function downloadOfficialReceipt() {
    if (!activeSubmissionId) {
        showToast('Not Available', 'PDF receipt is only available for confirmed payments.', 'error');
        return;
    }
    /* Server-side receipt for verified payments */
    downloadOfficialReceiptById(activeSubmissionId);
}

/**
 * Generates and opens a printable PDF summary for any transaction
 * regardless of status. Called from the transaction detail modal
 * via the "Download Summary" button.
 */
function downloadTransactionSummaryPdf() {
    const ref       = document.getElementById('t-ref').textContent.trim();
    const dateHdr   = document.getElementById('t-date-header').textContent.replace('Issued on ', '').trim();
    const type      = document.getElementById('t-type').textContent.trim();
    const confirmed = document.getElementById('t-confirmed').textContent.trim();
    const amount    = document.getElementById('t-amount').textContent.trim();
    const rejBlock  = document.getElementById('rejectionBlock');
    const rejReason = rejBlock.style.display !== 'none'
        ? document.getElementById('rejectionReason').textContent.trim()
        : null;

    /* Build status from mini tracker */
    const activeDot = document.querySelector('#miniTracker .mini-step-dot.active, #miniTracker .mini-step-dot.rejected');
    const activeLabel = activeDot
        ? activeDot.nextElementSibling?.textContent?.trim() ?? '—'
        : document.querySelector('#miniTracker .mini-step-dot.done:last-of-type')
            ?.nextElementSibling?.textContent?.trim() ?? '—';

    const steps = [...document.querySelectorAll('#miniTracker .mini-step-row')].map(row => {
        const dot   = row.querySelector('.mini-step-dot');
        const label = row.querySelector('.mini-step-label')?.textContent ?? '';
        const state = dot?.classList.contains('done')     ? 'done'
                    : dot?.classList.contains('active')   ? 'active'
                    : dot?.classList.contains('rejected') ? 'rejected'
                    : 'pending';
        return { label, state };
    });

    const isRejected = steps.some(s => s.state === 'rejected');
    const statusText = isRejected ? 'Rejected'
        : steps.filter(s => s.state === 'done').length === steps.length ? 'Completed'
        : 'In Progress';

    const stepRows = steps.map(s => {
        const icon  = s.state === 'done'     ? '✓'
                    : s.state === 'active'   ? '●'
                    : s.state === 'rejected' ? '✕'
                    : '○';
        const color = s.state === 'done'     ? '#1A7A3C'
                    : s.state === 'active'   ? '#800000'
                    : s.state === 'rejected' ? '#C0392B'
                    : '#ABABAB';
        return `<tr>
            <td style="width:28px;text-align:center;color:${color};font-weight:700;">${icon}</td>
            <td style="color:${s.state === 'pending' ? '#ABABAB' : '#1A1A1A'};font-weight:${s.state === 'pending' ? '400' : '600'};">${s.label}</td>
        </tr>`;
    }).join('');

    const rejectionHtml = rejReason
        ? `<div style="background:#FFF0F0;border:1px solid #FECACA;border-radius:8px;padding:14px 16px;margin:16px 0;display:flex;gap:12px;align-items:flex-start;">
               <span style="font-size:1.1rem;">⚠️</span>
               <div>
                   <strong style="color:#B91C1C;display:block;margin-bottom:4px;">Rejection Reason</strong>
                   <span style="color:#7F1D1D;font-size:0.85rem;">${rejReason}</span>
               </div>
           </div>`
        : '';

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Transaction Summary — ${ref}</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{font-family:'Segoe UI',Arial,sans-serif;background:#f0ece8;display:flex;justify-content:center;padding:40px 16px;-webkit-print-color-adjust:exact;print-color-adjust:exact}
  .page{background:#fff;width:100%;max-width:540px;border-radius:12px;box-shadow:0 4px 24px rgba(0,0,0,.12);overflow:hidden}
  .top-bar{background:#800000;color:#fff;padding:20px 28px;display:flex;align-items:center;gap:14px}
  .top-bar .logo-col{display:flex;align-items:center;gap:14px;flex:1}
  .top-bar .school-logo{width:52px;height:52px;object-fit:contain;flex-shrink:0;filter:drop-shadow(0 2px 6px rgba(0,0,0,.3))}
  .top-bar .logo-fallback{width:52px;height:52px;border-radius:50%;background:rgba(201,168,76,0.25);display:flex;align-items:center;justify-content:center;flex-shrink:0}
  .top-bar h1{font-size:1rem;font-weight:700;letter-spacing:.3px}
  .top-bar p{font-size:.75rem;opacity:.75;margin-top:2px}
  .school-row{background:#4a0000;color:#C9A84C;font-size:.72rem;text-align:center;padding:8px 28px;letter-spacing:.4px}
  .body{padding:28px}
  .ref-badge{background:#fff8f0;border:1px solid rgba(201,168,76,.35);border-radius:8px;padding:14px 18px;margin-bottom:20px;display:flex;justify-content:space-between;align-items:center}
  .ref-badge .label{font-size:.72rem;color:#7A7A7A;text-transform:uppercase;letter-spacing:.5px}
  .ref-badge .value{font-size:1rem;font-weight:700;color:#4a0000;letter-spacing:.5px}
  .status-chip{display:inline-block;padding:4px 14px;border-radius:20px;font-size:.72rem;font-weight:700;letter-spacing:.3px;background:${isRejected ? '#FEE2E2' : '#DCFCE7'};color:${isRejected ? '#B91C1C' : '#1A7A3C'}}
  .grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:16px 0}
  .field{background:#FAF8F5;border-radius:8px;padding:12px 14px}
  .field .label{font-size:.7rem;color:#7A7A7A;text-transform:uppercase;letter-spacing:.4px;margin-bottom:4px}
  .field .value{font-size:.88rem;font-weight:700;color:#1A1A1A}
  .amount-box{background:linear-gradient(135deg,#800000,#4a0000);border-radius:10px;padding:18px 20px;display:flex;justify-content:space-between;align-items:center;margin:18px 0;color:#fff}
  .amount-box .label{font-size:.8rem;opacity:.75}
  .amount-box .value{font-size:1.5rem;font-weight:700;color:#E8D08A}
  .tracker-section{border-top:1px solid #F0ECE8;padding-top:18px;margin-top:4px}
  .tracker-section h4{font-size:.72rem;color:#7A7A7A;text-transform:uppercase;letter-spacing:.5px;margin-bottom:12px}
  .tracker-section table{width:100%;border-collapse:collapse}
  .tracker-section td{padding:7px 0;font-size:.82rem;border-bottom:1px solid #F7F5F2}
  .footer{background:#FAF8F5;padding:16px 28px;display:flex;justify-content:space-between;align-items:center;font-size:.7rem;color:#ABABAB;border-top:1px solid #F0ECE8}
  @media print{body{background:none;padding:0}.page{box-shadow:none;max-width:100%;border-radius:0}}
</style>
</head>
<body>
<div class="page">
  <div class="top-bar">
    <div class="logo-col">
      <img class="school-logo" src="C:/xampp/htdocs/Cashier/Cashier Management/Cashier Media/school no bg.png" alt="School Logo"
           onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">
      <div class="logo-fallback" style="display:none">
        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#C9A84C" stroke-width="1.5"><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2"/><rect x="9" y="3" width="6" height="4" rx="2"/><path d="M9 12h6M9 16h4"/></svg>
      </div>
      <div><h1>Transaction Summary</h1><p>Student Payment Portal — Official Record</p></div>
    </div>
  </div>
  <div class="school-row">ST. JOSEPH COLLEGE OF NOVALICHES, INC.</div>
  <div class="body">
    <div class="ref-badge">
      <div><div class="label">Reference Number</div><div class="value">${ref}</div></div>
      <span class="status-chip">${statusText}</span>
    </div>
    <div class="grid">
      <div class="field"><div class="label">Date Submitted</div><div class="value">${dateHdr}</div></div>
      <div class="field"><div class="label">Payment Type</div><div class="value">${type}</div></div>
      <div class="field"><div class="label">Confirmed On</div><div class="value">${confirmed}</div></div>
      <div class="field"><div class="label">Current Status</div><div class="value">${statusText}</div></div>
    </div>
    <div class="amount-box">
      <span class="label">Amount</span>
      <span class="value">${amount}</span>
    </div>
    ${rejectionHtml}
    <div class="tracker-section">
      <h4>Payment Progress</h4>
      <table>${stepRows}</table>
    </div>
  </div>
  <div class="footer">
    <span>Generated: ${new Date().toLocaleString('en-PH')}</span>
    <span>SJC Student Portal · For verification contact the cashier's office</span>
  </div>
</div>
<script>window.addEventListener('load',()=>{window.print()});<\/script>
</body>
</html>`;

    const win = window.open('', '_blank');
    if (!win) {
        showToast('Popup Blocked', 'Please allow popups to download the summary.', 'error');
        return;
    }
    win.document.write(html);
    win.document.close();
}

/* ══════════════════════════════════════════════════════════
   COR MODAL — Year picker + download
══════════════════════════════════════════════════════════ */

let selectedCorYearId = null;

/**
 * Open the COR modal and fetch available enrolled years.
 */
async function openCorModal() {
    // Block only truly pending (not yet approved) students
    const status = window._currentEnrollmentStatus;
    if (status === 'pending') {
        document.getElementById('pendingRegistrationModal').style.display = 'flex';
        return;
    }

    selectedCorYearId = null;

    // Show modal, reset to loading state
    const overlay = document.getElementById('corModal');
    overlay.classList.add('active');
    document.body.style.overflow = 'hidden';

    document.getElementById('corYearsLoading').style.display  = 'block';
    document.getElementById('corNoEnrollment').style.display  = 'none';
    document.getElementById('corYearsList').style.display     = 'none';
    const sel = document.getElementById('corYearSelect');
    sel.innerHTML = '<option value="">— Select School Year —</option>';
    document.getElementById('corDownloadBtn').disabled        = true;

    try {
        const res  = await fetch(`${API_BASE}/get_cor_years.php`, { credentials: 'include' });
        const data = await res.json();

        document.getElementById('corYearsLoading').style.display = 'none';

        if (!data.success || !data.years || data.years.length === 0) {
            document.getElementById('corNoEnrollment').style.display = 'block';
            return;
        }

        renderCorYearOptions(data.years);
        document.getElementById('corYearsList').style.display = 'block';

    } catch (e) {
        document.getElementById('corYearsLoading').style.display = 'none';
        document.getElementById('corNoEnrollment').style.display = 'block';
        console.error('[COR Modal]', e);
    }
}

/**
 * Populate the <select> dropdown with year options.
 */
function renderCorYearOptions(years) {
    const sel = document.getElementById('corYearSelect');
    // Keep placeholder as first option
    sel.innerHTML = '<option value="">— Select School Year —</option>';

    years.forEach(yr => {
        const opt = document.createElement('option');
        opt.value = yr.school_year_id;
        opt.textContent = yr.label + (yr.is_active ? ' (Current)' : '');
        sel.appendChild(opt);
    });
}

/**
 * Called when the <select> value changes.
 */
function selectCorYear(yearId) {
    selectedCorYearId = yearId || null;
    document.getElementById('corDownloadBtn').disabled = !selectedCorYearId;
}

/**
 * Open the COR PDF in a new tab.
 */
function downloadSelectedCor() {
    if (!selectedCorYearId) return;
    window.open(`${API_BASE}/download_cor.php?year_id=${selectedCorYearId}`, '_blank');
}

function closeCorModal() {
    document.getElementById('corModal').classList.remove('active');
    document.body.style.overflow = '';
}

// Close on overlay click (outside card)
document.addEventListener('DOMContentLoaded', function () {
    document.getElementById('corModal').addEventListener('click', function (e) {
        if (e.target === this) closeCorModal();
    });
});

/* ══════════════════════════════════════════════════════════
   PAYMENT HISTORY VIEWER (PHV)
   Shows approved & rejected transactions in a dedicated modal
   with a detail slide-in for each transaction.
══════════════════════════════════════════════════════════ */

let _phvAllData    = [];   // full filtered list (approved + rejected)
let _phvFilter     = 'all';
let _phvActiveItem = null; // item currently shown in detail

/* ── Open / Close ─────────────────────────────────────────── */
function openPaymentHistoryViewer() {
    const modal = document.getElementById('phvModal');
    modal.style.display = 'flex';
    modal.classList.add('active');
    document.body.style.overflow = 'hidden';
    _phvFilter = 'all';

    // Reset filter buttons
    document.querySelectorAll('.phv-filter-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.filter === 'all');
    });

    // If we already have data from the main history load, use it; else fetch
    if (currentPaymentData.length > 0) {
        _renderPhvList(currentPaymentData);
    } else {
        _phvShowLoading();
        loadPaymentHistory().then(() => _renderPhvList(currentPaymentData));
    }
}

function closePaymentHistoryViewer() {
    const modal = document.getElementById('phvModal');
    modal.classList.remove('active');
    setTimeout(() => {
        modal.style.display = 'none';
        document.body.style.overflow = '';
    }, 300);
}

/* ── Rendering ────────────────────────────────────────────── */
function _phvShowLoading() {
    document.getElementById('phvLoading').style.display = 'flex';
    document.getElementById('phvList').style.display    = 'none';
    document.getElementById('phvEmpty').style.display   = 'none';
}

function _renderPhvList(allPayments) {
    // Only approved and rejected
    const finalized = allPayments.filter(p =>
        ['verified','reflected_to_enrollment','rejected'].includes(p.status)
    );
    _phvAllData = finalized;

    _updatePhvSummaryChips(finalized);
    _applyPhvFilter();
}

function _updatePhvSummaryChips(items) {
    const approved = items.filter(p => ['verified','reflected_to_enrollment'].includes(p.status)).length;
    const rejected = items.filter(p => p.status === 'rejected').length;
    const container = document.getElementById('phvSummaryChips');
    container.innerHTML = `
        ${approved > 0 ? `<div class="phv-chip approved">✓ ${approved} Approved</div>` : ''}
        ${rejected > 0 ? `<div class="phv-chip rejected">✕ ${rejected} Rejected</div>` : ''}
    `;
}

function filterPhv(filter, btn) {
    _phvFilter = filter;
    document.querySelectorAll('.phv-filter-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    _applyPhvFilter();
}

function _applyPhvFilter() {
    const loading = document.getElementById('phvLoading');
    const list    = document.getElementById('phvList');
    const empty   = document.getElementById('phvEmpty');

    loading.style.display = 'none';

    let items = _phvAllData;
    if (_phvFilter === 'approved') {
        items = items.filter(p => ['verified','reflected_to_enrollment'].includes(p.status));
    } else if (_phvFilter === 'rejected') {
        items = items.filter(p => p.status === 'rejected');
    }

    if (items.length === 0) {
        list.style.display  = 'none';
        empty.style.display = 'flex';
        return;
    }

    empty.style.display = 'none';
    list.style.display  = 'flex';
    list.innerHTML = items.map(p => _buildPhvCard(p)).join('');
}

function _buildPhvCard(p) {
    const isApproved = ['verified','reflected_to_enrollment'].includes(p.status);
    const cardCls    = isApproved ? 'approved-card' : 'rejected-card';
    const statusCls  = isApproved ? 'approved' : 'rejected';
    const statusText = isApproved ? 'Approved' : 'Rejected';
    const iconSvg    = isApproved
        ? '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>'
        : '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';

    const cashier  = esc(p.cashier_name || '—');
    const date     = esc(p.confirmed_at || p.submitted_date || '—');
    const ref      = esc(p.reference_number);
    const amount   = esc(p.amount_formatted || '—');
    const type     = esc(p.payment_type_label || '—');

    // Encode the whole object as a data attribute index
    const idx = _phvAllData.indexOf(p);

    return `
    <div class="phv-tx-card ${cardCls}" onclick="openPhvDetail(${idx})" role="button" tabindex="0">
        <div class="phv-tx-icon">${iconSvg}</div>
        <div class="phv-tx-body">
            <div class="phv-tx-ref">${ref}</div>
            <div class="phv-tx-meta">
                <span>
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
                    ${date}
                </span>
                <span>
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                    ${cashier}
                </span>
                <span>${type}</span>
            </div>
        </div>
        <div class="phv-tx-right">
            <div class="phv-tx-amount">${amount}</div>
            <div class="phv-tx-status ${statusCls}">${statusText}</div>
        </div>
        <div class="phv-tx-chevron">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="9,18 15,12 9,6"/></svg>
        </div>
    </div>`;
}

/* ── Detail View ──────────────────────────────────────────── */
function openPhvDetail(idx) {
    const p = _phvAllData[idx];
    if (!p) return;
    _phvActiveItem = p;

    const isApproved = ['verified','reflected_to_enrollment'].includes(p.status);
    const headerEl   = document.getElementById('phvDetailHeader');
    const fieldsEl   = document.getElementById('phvDetailFields');
    const footerEl   = document.getElementById('phvDetailFooter');

    // Build header
    const statusLabel = isApproved ? 'Payment Approved' : 'Payment Rejected';
    const statusIcon  = isApproved ? '✅' : '❌';
    headerEl.className = 'phv-detail-header ' + (isApproved ? 'approved-header' : 'rejected-header');
    headerEl.innerHTML = `
        <div class="phv-detail-status-row">
            <div class="phv-detail-status-icon">${statusIcon}</div>
            <div>
                <div class="phv-detail-status-label">Transaction Status</div>
                <div class="phv-detail-status-name">${statusLabel}</div>
            </div>
        </div>
        <div class="phv-detail-ref">${esc(p.reference_number)}</div>
        <div class="phv-detail-amount">
            <div class="phv-detail-amount-label">Amount Paid</div>
            <div class="phv-detail-amount-value">${esc(p.amount_formatted || '—')}</div>
        </div>
    `;

    // Build fields
    fieldsEl.innerHTML = `
        <div class="phv-field-row">
            <span class="phv-field-label">Cashier</span>
            <span class="phv-field-value">${esc(p.cashier_name || '—')}</span>
        </div>
        <div class="phv-field-row">
            <span class="phv-field-label">Date &amp; Time</span>
            <span class="phv-field-value">${esc(p.confirmed_at || '—')}</span>
        </div>
        <div class="phv-field-row">
            <span class="phv-field-label">Reference No.</span>
            <span class="phv-field-value mono">${esc(p.reference_number)}</span>
        </div>
        <div class="phv-field-row">
            <span class="phv-field-label">Payment Type</span>
            <span class="phv-field-value">${esc(p.payment_type_label || formatStatus(p.payment_type))}</span>
        </div>
        <div class="phv-field-row">
            <span class="phv-field-label">Date Submitted</span>
            <span class="phv-field-value">${esc(p.submitted_date || '—')}</span>
        </div>
    `;

    // Rejection reason block (injected before footer, not inside fields)
    const detailCard = document.getElementById('phvDetailCard');
    // Remove any existing rejection block
    const existingRej = detailCard.querySelector('.phv-rejection-block');
    if (existingRej) existingRej.remove();

    if (!isApproved && p.rejection_reason) {
        const rejEl = document.createElement('div');
        rejEl.className = 'phv-rejection-block';
        rejEl.innerHTML = `
            <div class="rj-icon">⚠️</div>
            <div>
                <strong>Reason for Rejection</strong>
                <p>${esc(p.rejection_reason)}</p>
            </div>
        `;
        detailCard.insertBefore(rejEl, footerEl);
    }

    // Build footer
    footerEl.innerHTML = '';
    if (isApproved) {
        const dlBtn = document.createElement('button');
        dlBtn.className = 'phv-download-btn';
        dlBtn.innerHTML = `
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
            Download Official Receipt
        `;
        dlBtn.onclick = () => downloadOfficialReceiptById(p.id);
        footerEl.appendChild(dlBtn);
    }

    const imgBtn = document.createElement('button');
    imgBtn.className = 'phv-view-img-btn';
    imgBtn.innerHTML = `
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
        View Receipt Image
    `;
    imgBtn.onclick = _phvViewReceiptImage;
    footerEl.appendChild(imgBtn);

    // Open detail modal
    const detailModal = document.getElementById('phvDetailModal');
    detailModal.style.display = 'flex';
    detailModal.classList.add('active');
    document.body.style.overflow = 'hidden';
}

function closePhvDetail() {
    const detailModal = document.getElementById('phvDetailModal');
    detailModal.classList.remove('active');
    setTimeout(() => {
        detailModal.style.display = 'none';
        _phvActiveItem = null;
    }, 300);
}

async function _phvViewReceiptImage() {
    if (!_phvActiveItem || !_phvActiveItem.id) {
        showToast('No Receipt', 'Receipt image not available.', 'error');
        return;
    }
    try {
        const data = await fetchReceiptImage(_phvActiveItem.id);
        if (data.success) {
            // Set the active submission for the existing image modal
            activeSubmissionId = _phvActiveItem.id;
            currentReceiptRef  = _phvActiveItem.reference_number;
            openReceiptImageModal(data.image_url, data.reference_number);
        } else {
            showToast('Receipt Not Found', data.message || 'Image unavailable.', 'error');
        }
    } catch (e) {
        showToast('Error', 'Could not load receipt image.', 'error');
    }
}

// Close PHV overlay on backdrop click
document.addEventListener('DOMContentLoaded', function() {
    document.getElementById('phvModal').addEventListener('click', function(e) {
        if (e.target === this) closePaymentHistoryViewer();
    });
    document.getElementById('phvDetailModal').addEventListener('click', function(e) {
        if (e.target === this) closePhvDetail();
    });
});