// ═══════════════════════════════════════════════
//  SJC STUDENT PORTAL — student.js
//  Fetches student data from student.php (JSON API)
//  then drives the loading screen + page population
// ═══════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', async function () {

    /* ─── 1. SPAWN PARTICLES ─────────────────── */
    (function spawnParticles() {
        const container = document.getElementById('particles');
        if (!container) return;
        for (let i = 0; i < 30; i++) {
            const p = document.createElement('div');
            p.className = 'particle';
            const size = Math.random() * 4 + 2;
            p.style.cssText = `
                width:${size}px; height:${size}px;
                left:${Math.random() * 100}%;
                bottom:${Math.random() * 30}%;
                --dur:${(Math.random() * 4 + 3).toFixed(1)}s;
                --delay:${(Math.random() * 4).toFixed(1)}s;
                --op:${(Math.random() * 0.3 + 0.1).toFixed(2)};
            `;
            container.appendChild(p);
        }
    })();

    /* ─── 2. FETCH STUDENT DATA FROM PHP API ─── */
    let student = {
        first_name:          'Josephite',
        last_name:           '',
        lrn:                 '',
        grade_label:         'Grade Level',
        status:              'enrolled',
        enrollment_type:     'new',
        school_year:         '2025-2026',
        locked_registration: false,
        locked_verified:     false,
        locked_balance:      false,
        payment_deadline:    null,
    };

    try {
        const res = await fetch('../Student/student.php');

        if (res.status === 401) {
            window.location.href = 'login.html';
            return;
        }

        if (res.ok) {
            const data = await res.json();
            if (!data.error) {
                student = { ...student, ...data };
            }
        }
    } catch (err) {
        console.warn('student.php unavailable, using defaults:', err);
    }

    /* ─── 3. INJECT DATA INTO LOADING SCREEN ─── */
    const loadingNameEl = document.getElementById('loadingStudentName');
    if (loadingNameEl) loadingNameEl.textContent = student.first_name;

    const loadingYearEl = document.getElementById('loadingYear');
    if (loadingYearEl) loadingYearEl.textContent = 'S.Y. ' + student.school_year;

    /* ─── 4. INJECT DATA INTO WELCOME CARD ────── */
    const welcomeNameEl = document.getElementById('welcomeName');
    if (welcomeNameEl) welcomeNameEl.textContent = student.first_name + '!';

    const syBadgeEl = document.getElementById('syBadgeYear');
    if (syBadgeEl) syBadgeEl.textContent = 'Active · S.Y. ' + student.school_year;

    const syHeaderEl = document.getElementById('syHeaderYear');
    if (syHeaderEl) syHeaderEl.textContent = 'S.Y. ' + student.school_year;

    const lrnChipEl = document.getElementById('lrnChip');
    if (lrnChipEl) lrnChipEl.textContent = student.lrn ? 'LRN: ' + student.lrn : 'Student';

    const gradeChipEl = document.getElementById('gradeChip');
    if (gradeChipEl) gradeChipEl.textContent = student.grade_label;

    /* ─── 5A. DOCUMENTS UNDER REVIEW POPUP (pending only) ───────────
       Appears once per login session for students whose status is
       'pending' or 'registered' (locked_registration = true).
       sessionStorage key is cleared on logout so it reappears next login.
    ────────────────────────────────────────────── */
    if (student.locked_registration) {
        const popupKey = 'sjc_reg_popup_shown';
        if (!sessionStorage.getItem(popupKey)) {
            sessionStorage.setItem(popupKey, '1');
            setTimeout(() => showRegistrationPopup(), 800);
        }
    }

    function showRegistrationPopup() {
        const existing = document.getElementById('regPopupOverlay');
        if (existing) existing.remove();

        const overlay = document.createElement('div');
        overlay.id        = 'regPopupOverlay';
        overlay.className = 'lock-modal-overlay';
        overlay.innerHTML = `
            <div class="lock-modal-box reg-popup-box" role="dialog" aria-modal="true" aria-labelledby="regPopupTitle">
                <div class="lock-modal-icon lock-icon--registration">
                    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
                        <polyline points="14 2 14 8 20 8"/>
                        <line x1="16" y1="13" x2="8" y2="13"/>
                        <line x1="16" y1="17" x2="8" y2="17"/>
                    </svg>
                </div>
                <h3 class="lock-modal-title" id="regPopupTitle">Documents Under Review</h3>
                <p class="lock-modal-message">
                    For new students, please kindly wait while the documents you submitted through the website are being reviewed by the Registrar's Office.<br><br>
                    Once your documents have been approved, a confirmation email will be sent to your personal email address. After receiving approval, you may proceed with enrollment and settle your enrollment fee.
                </p>
                <button class="lock-modal-btn" id="regPopupClose">Understood</button>
            </div>`;

        document.body.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('active'));

        function closePopup() {
            overlay.classList.remove('active');
            setTimeout(() => overlay.remove(), 320);
        }

        document.getElementById('regPopupClose').addEventListener('click', closePopup);
        overlay.addEventListener('click', (e) => { if (e.target === overlay) closePopup(); });
        document.addEventListener('keydown', function escHandler(e) {
            if (e.key === 'Escape') { closePopup(); document.removeEventListener('keydown', escHandler); }
        });
    }

    /* ─── 5B. PAYMENT / TRANSACTION WARNING MODAL (pending only) ────
       When a student whose status is 'pending' navigates to any
       Enrollment, Payment, or Transaction page, intercept the click and
       show a confirmation modal: "Proceed Anyway" or "Cancel".
       Only applies while locked_registration is true (pending status).
    ────────────────────────────────────────────── */
    if (student.locked_registration) {
        // Match hrefs that lead to enrollment, payment, or transaction pages
        const PAYMENT_PATHS = [
            /student\s*enroll/i,
            /payment/i,
            /transaction/i,
            /fee/i,
        ];

        document.querySelectorAll('a[href]').forEach(link => {
            const href = link.getAttribute('href') || '';
            const isPaymentLink = PAYMENT_PATHS.some(rx => rx.test(href));
            if (!isPaymentLink) return;

            link.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopImmediatePropagation();
                showPaymentWarningModal(href);
            });
        });
    }

    function showPaymentWarningModal(destination) {
        const existing = document.getElementById('paymentWarningOverlay');
        if (existing) existing.remove();

        const overlay = document.createElement('div');
        overlay.id        = 'paymentWarningOverlay';
        overlay.className = 'lock-modal-overlay';
        overlay.innerHTML = `
            <div class="lock-modal-box reg-popup-box" role="dialog" aria-modal="true" aria-labelledby="paymentWarningTitle">
                <div class="lock-modal-icon lock-icon--warning">
                    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
                        <line x1="12" y1="9" x2="12" y2="13"/>
                        <line x1="12" y1="17" x2="12.01" y2="17"/>
                    </svg>
                </div>
                <h3 class="lock-modal-title" id="paymentWarningTitle">Registration Pending Approval</h3>
                <p class="lock-modal-message">
                    You're accessing payment and transaction features. Your registration is still awaiting approval from the Registrar's Office.<br><br>
                    Kindly await the registrar's review of your submitted documents before proceeding with enrollment or payment.
                </p>
                <div class="lock-modal-actions">
                    <button class="lock-modal-btn lock-modal-btn--ghost" id="paymentWarnCancel">Cancel</button>
                    <button class="lock-modal-btn lock-modal-btn--proceed" id="paymentWarnProceed">Proceed Anyway</button>
                </div>
            </div>`;

        document.body.appendChild(overlay);
        requestAnimationFrame(() => overlay.classList.add('active'));

        function closeWarning() {
            overlay.classList.remove('active');
            setTimeout(() => overlay.remove(), 320);
        }

        document.getElementById('paymentWarnCancel').addEventListener('click', closeWarning);
        document.getElementById('paymentWarnProceed').addEventListener('click', function () {
            closeWarning();
            setTimeout(() => { window.location.href = destination; }, 180);
        });
        overlay.addEventListener('click', (e) => { if (e.target === overlay) closeWarning(); });
        document.addEventListener('keydown', function escHandler(e) {
            if (e.key === 'Escape') { closeWarning(); document.removeEventListener('keydown', escHandler); }
        });
    }

    /* ─── 5C. REGISTRAR APPROVAL BANNER (registered status only) ────
       Shown once per login session when a student's status has been
       updated to 'registered' (documents approved, not yet paid).
       Prompts them to proceed to Enrollment to settle the fee.
       Uses sessionStorage → reappears each login until status advances.
    ────────────────────────────────────────────── */
    if (student.status === 'registered') {
        const approvalBannerKey = 'sjc_approval_banner_shown';
        if (!sessionStorage.getItem(approvalBannerKey)) {
            sessionStorage.setItem(approvalBannerKey, '1');
            showApprovalBanner();
        }
    }

    function showApprovalBanner() {
        // Remove any existing approval banner
        const existing = document.getElementById('approvalBanner');
        if (existing) existing.remove();

        const header = document.getElementById('portalHeader');
        if (!header) return;

        const banner = document.createElement('div');
        banner.id        = 'approvalBanner';
        banner.className = 'approval-banner';
        banner.setAttribute('role', 'alert');
        banner.setAttribute('aria-live', 'polite');
        banner.innerHTML = `
            <div class="approval-banner-content">
                <div class="approval-banner-icon">
                    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
                        <polyline points="22 4 12 14.01 9 11.01"/>
                    </svg>
                </div>
                <p class="approval-banner-text">
                    <strong>Your registration has been approved by the registrar.</strong>
                    Please proceed to the
                    <a href="../Student/student enrollment/studentenroll.html" class="approval-banner-link">Enrollment</a>
                    section to settle your enrollment fee and gain full portal access.
                </p>
            </div>
            <button class="approval-banner-close" id="approvalBannerClose" aria-label="Dismiss banner">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
                    <line x1="18" y1="6" x2="6" y2="18"/>
                    <line x1="6" y1="6" x2="18" y2="18"/>
                </svg>
            </button>`;

        // Insert directly after the header
        header.insertAdjacentElement('afterend', banner);

        // Animate in after next paint
        requestAnimationFrame(() => {
            requestAnimationFrame(() => banner.classList.add('approval-banner--visible'));
        });

        document.getElementById('approvalBannerClose').addEventListener('click', () => {
            banner.classList.add('approval-banner--dismissed');
            setTimeout(() => banner.remove(), 420);
        });
    }


    /* ─── 5D. ON-HOLD BANNER (rejected status only) ───────────
       Shown persistently (no dismiss) when registration_status = 'rejected'.
       The student cannot act on this themselves — they just need to wait
       for an email from the registrar, so we always show it each login.
    ─────────────────────────────────────────────── */
    if (student.locked_hold) {
        showHoldBanner();
    }

    function showHoldBanner() {
        const existing = document.getElementById('holdBanner');
        if (existing) return; // already shown

        const header = document.getElementById('portalHeader');
        if (!header) return;

        const banner = document.createElement('div');
        banner.id        = 'holdBanner';
        banner.className = 'hold-banner';
        banner.setAttribute('role', 'alert');
        banner.setAttribute('aria-live', 'polite');
        banner.innerHTML = `
            <div class="hold-banner-content">
                <div class="hold-banner-icon">
                    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round">
                        <circle cx="12" cy="12" r="10"/>
                        <line x1="12" y1="8" x2="12" y2="12"/>
                        <line x1="12" y1="16" x2="12.01" y2="16"/>
                    </svg>
                </div>
                <p class="hold-banner-text">
                    <strong>Your account is currently on hold.</strong>
                    Some features may be restricted. Please check your email for updates from the registrar regarding your account status.
                </p>
            </div>`;

        // Insert directly after the header
        header.insertAdjacentElement('afterend', banner);

        // Animate in after next paint
        requestAnimationFrame(() => {
            requestAnimationFrame(() => banner.classList.add('hold-banner--visible'));
        });
    }

    /* ─── 5E. PAYMENT DEADLINE BANNER ───────────────────────────────────
       Shown when the admin has set a payments deadline in system_deadlines.
       Visible to all enrolled students (or those with a pending balance).
       Dismissible per session. Reminds students to upload proof of payment
       — we do NOT process transactions, only proof-of-payment uploads.
    ─────────────────────────────────────────────── */
    if (student.payment_deadline) {
        const deadlineBannerKey = 'sjc_deadline_banner_dismissed';
        if (!sessionStorage.getItem(deadlineBannerKey)) {
            showPaymentDeadlineBanner(student.payment_deadline);
        }
    }

    function showPaymentDeadlineBanner(rawDeadline) {
        const existing = document.getElementById('paymentDeadlineBanner');
        if (existing) return;

        // Format the date nicely: "June 10, 2026"
        const d = new Date(rawDeadline);
        const formattedDate = isNaN(d.getTime())
            ? rawDeadline
            : d.toLocaleDateString('en-PH', { year: 'numeric', month: 'long', day: 'numeric' });

        const header = document.getElementById('portalHeader');
        if (!header) return;

        const banner = document.createElement('div');
        banner.id        = 'paymentDeadlineBanner';
        banner.className = 'deadline-banner';
        banner.setAttribute('role', 'alert');
        banner.setAttribute('aria-live', 'polite');
        banner.innerHTML = `
            <div class="deadline-banner-content">
                <div class="deadline-banner-icon">
                    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round">
                        <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
                        <line x1="16" y1="2" x2="16" y2="6"/>
                        <line x1="8" y1="2" x2="8" y2="6"/>
                        <line x1="3" y1="10" x2="21" y2="10"/>
                    </svg>
                </div>
                <div class="deadline-banner-body">
                    <p class="deadline-banner-text">
                        Please settle your payment on or before <strong>${formattedDate}</strong> to avoid late payment fees.
                        To submit your payment, proceed to the
                        <a href="../Student/student enrollment/studentenroll.html" class="deadline-banner-link">Enrollment</a>
                        page and upload your proof of payment.
                    </p>
                    <p class="deadline-banner-due">Payment Deadline: <strong>${formattedDate}</strong></p>
                </div>
            </div>
            <button class="deadline-banner-close" id="deadlineBannerClose" aria-label="Dismiss banner">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
                    <line x1="18" y1="6" x2="6" y2="18"/>
                    <line x1="6" y1="6" x2="18" y2="18"/>
                </svg>
            </button>`;

        header.insertAdjacentElement('afterend', banner);

        requestAnimationFrame(() => {
            requestAnimationFrame(() => banner.classList.add('deadline-banner--visible'));
        });

        document.getElementById('deadlineBannerClose').addEventListener('click', () => {
            sessionStorage.setItem('sjc_deadline_banner_dismissed', '1');
            banner.classList.add('deadline-banner--dismissed');
            setTimeout(() => banner.remove(), 420);
        });
    }

    /* ─── 6. REGISTRATION BANNER ─────────────────────────────────────
       • locked_registration (pending/registered): no banner — popup handles it.
       • locked_verified (approved, must pay):     amber "settle fee" banner.
       • locked_balance (enrolled, unpaid dues):   same amber banner variant.
       Dismissed state lives in sessionStorage (resets on next login).
    ────────────────────────────────────────────── */
    const banner      = document.getElementById('registrationBanner');
    const bannerClose = document.getElementById('regBannerClose');
    const bannerText  = banner ? banner.querySelector('.reg-banner-text') : null;

    const showBanner = student.locked_verified || student.locked_balance;

    if (banner && showBanner) {
        // Update banner message for verified/balance state
        if (bannerText) {
            bannerText.innerHTML = `Registered students must settle their balance or enrollment fee to gain full access to the portal.
                Kindly select the <a href="../Student/student enrollment/studentenroll.html" class="reg-banner-link">Enrollment</a> section to view and settle your enrollment fee.`;
        }

        banner.style.display = '';
        requestAnimationFrame(() => {
            requestAnimationFrame(() => banner.classList.add('reg-banner--visible'));
        });

        if (bannerClose) {
            bannerClose.addEventListener('click', () => {
                banner.classList.add('reg-banner--dismissed');
                setTimeout(() => { banner.style.display = 'none'; }, 400);
            });
        }
    }

    /* ─── 7. LOCK CARDS IF NEEDED ────────────────────────────────────
       All three lock states (registration, verified, balance) block
       restricted cards. Each shows a different modal message on click.
    ────────────────────────────────────────────── */
    const isLocked = student.locked_registration || student.locked_verified || student.locked_balance || student.locked_hold;
    const lockType = student.locked_registration ? 'registration'
                   : student.locked_verified     ? 'verified'
                   : student.locked_balance       ? 'balance'
                   : null;

    if (isLocked) {
        document.querySelectorAll('.portal-card[data-restricted]').forEach(card => {
            card.classList.add('card--locked');
            card.setAttribute('data-lock-type', lockType);
        });
    }

    // Modal message per lock type
    const LOCK_MESSAGES = {
        registration: {
            title:   'Documents Under Review',
            message: 'This feature will be available once your submitted documents have been reviewed and approved by the Registrar\'s Office. You may access <strong>Enrollment Viewing</strong> and <strong>Profile Viewing</strong> in the meantime.',
            icon:    `<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
                        <polyline points="14 2 14 8 20 8"/>
                        <line x1="16" y1="13" x2="8" y2="13"/>
                        <line x1="16" y1="17" x2="8" y2="17"/>
                      </svg>`,
        },
        verified: {
            title:   'Enrollment Fee Required',
            message: 'Your documents have been approved! To unlock full portal access, please proceed to the <strong>Enrollment</strong> section and settle your enrollment fee.',
            icon:    `<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
                        <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                      </svg>`,
        },
        balance: {
            title:   'Outstanding Balance',
            message: 'Access to this feature is temporarily unavailable due to an outstanding balance. Please settle your balance with the school cashier to continue using student portal services.',
            icon:    `<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <circle cx="12" cy="12" r="10"/>
                        <line x1="12" y1="8" x2="12" y2="12"/>
                        <line x1="12" y1="16" x2="12.01" y2="16"/>
                      </svg>`,
        },
        hold: {
            title:   'Account On Hold',
            message: 'Your account is currently on hold. This feature is restricted while your registration is being reviewed. Please check your email for updates from the Registrar&#39;s Office.',
            icon:    `<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
                        <circle cx="12" cy="12" r="10"/>
                        <line x1="12" y1="8" x2="12" y2="12"/>
                        <line x1="12" y1="16" x2="12.01" y2="16"/>
                      </svg>`,
        },
    };

    // Intercept clicks on locked cards
    document.querySelectorAll('.portal-card').forEach(card => {
        card.addEventListener('click', function (e) {
            if (!card.classList.contains('card--locked')) return;
            e.preventDefault();
            e.stopImmediatePropagation();

            const type = card.getAttribute('data-lock-type') || lockType;
            showLockModal(type);
        });
    });

    function showLockModal(type) {
        const cfg = LOCK_MESSAGES[type] || LOCK_MESSAGES.balance;

        // Remove any existing modal
        const existing = document.getElementById('lockModal');
        if (existing) existing.remove();

        const overlay = document.createElement('div');
        overlay.id        = 'lockModal';
        overlay.className = 'lock-modal-overlay';
        overlay.innerHTML = `
            <div class="lock-modal-box" role="dialog" aria-modal="true">
                <div class="lock-modal-icon lock-icon--${type}">${cfg.icon}</div>
                <h3 class="lock-modal-title">${cfg.title}</h3>
                <p class="lock-modal-message">${cfg.message}</p>
                <button class="lock-modal-btn" id="lockModalClose">Got it</button>
            </div>`;

        document.body.appendChild(overlay);

        // Animate in
        requestAnimationFrame(() => overlay.classList.add('active'));

        function closeModal() {
            overlay.classList.remove('active');
            setTimeout(() => overlay.remove(), 320);
        }

        document.getElementById('lockModalClose').addEventListener('click', closeModal);
        overlay.addEventListener('click', function (e) {
            if (e.target === overlay) closeModal();
        });
        document.addEventListener('keydown', function escHandler(e) {
            if (e.key === 'Escape') { closeModal(); document.removeEventListener('keydown', escHandler); }
        });
    }

    /* ─── 7. ANIMATED LOADING BAR ───────────────  */
    const loadingScreen  = document.getElementById('loadingScreen');
    const loadingBar     = document.getElementById('loadingBar');
    const loadingPercent = document.getElementById('loadingPercent');
    const portalHeader   = document.getElementById('portalHeader');

    const alreadySeen = sessionStorage.getItem('sjc_portal_loaded');

    if (alreadySeen) {
        if (loadingScreen) loadingScreen.remove();
        if (portalHeader)  portalHeader.classList.add('visible');
    } else {
        sessionStorage.setItem('sjc_portal_loaded', '1');

        const totalDuration = 2600;
        const intervalMs    = 40;
        const totalSteps    = totalDuration / intervalMs;
        let step = 0;

        function easeProgress(t) {
            return t < 0.6 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
        }

        const barInterval = setInterval(() => {
            step++;
            const progress = Math.round(easeProgress(step / totalSteps) * 100);
            if (loadingBar)     loadingBar.style.width     = progress + '%';
            if (loadingPercent) loadingPercent.textContent = progress + '%';

            if (step >= totalSteps) {
                clearInterval(barInterval);
                setTimeout(dismissLoadingScreen, 350);
            }
        }, intervalMs);

        function dismissLoadingScreen() {
            if (loadingScreen) loadingScreen.classList.add('fade-out');
            if (portalHeader)  setTimeout(() => portalHeader.classList.add('visible'), 200);
            setTimeout(() => { if (loadingScreen) loadingScreen.remove(); }, 900);
        }
    }

    /* ─── 8. LOGOUT OVERLAY ──────────────────────  */
    const logoutBtn     = document.getElementById('logoutTrigger');
    const logoutOverlay = document.getElementById('logoutOverlay');

    if (logoutBtn && logoutOverlay) {
        logoutBtn.addEventListener('click', function (e) {
            e.preventDefault();
            // Clear the loading-screen flag AND all per-session modal flags so
            // every modal/banner reappears correctly on the student's next login.
            sessionStorage.removeItem('sjc_portal_loaded');
            sessionStorage.removeItem('sjc_reg_popup_shown');
            sessionStorage.removeItem('sjc_approval_banner_shown');
            sessionStorage.removeItem('sjc_deadline_banner_dismissed');
            logoutOverlay.classList.add('active');
            setTimeout(() => {
                window.location.href = 'login.html';
            }, 1800);
        });
    }

    /* ─── 9. CARD RIPPLE ─────────────────────────  */
    if (!document.getElementById('rippleStyle')) {
        const s = document.createElement('style');
        s.id = 'rippleStyle';
        s.textContent = '@keyframes rippleAnim { to { transform:scale(1); opacity:0; } }';
        document.head.appendChild(s);
    }

    document.querySelectorAll('.portal-card').forEach(card => {
        card.addEventListener('click', function (e) {
            if (card.classList.contains('card--locked')) return; // no ripple on locked
            const ripple = document.createElement('span');
            const rect   = card.getBoundingClientRect();
            const size   = Math.max(rect.width, rect.height) * 1.5;
            ripple.style.cssText = `
                position:absolute; border-radius:50%; pointer-events:none; z-index:10;
                width:${size}px; height:${size}px;
                left:${e.clientX - rect.left - size / 2}px;
                top:${e.clientY - rect.top  - size / 2}px;
                background:rgba(107,15,26,0.07);
                transform:scale(0); animation:rippleAnim 0.55s ease;
            `;
            card.appendChild(ripple);
            ripple.addEventListener('animationend', () => ripple.remove());
        });
    });

});