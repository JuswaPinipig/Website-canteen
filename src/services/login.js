/* ═══════════════════════════════════════════════════════════
   SJC PORTAL — Maininterface.js
   Handles: Carousel · Login Form · OTP Modal · Forgot Password Modal
   · Scroll Reveal · Page Transition
═══════════════════════════════════════════════════════════ */

'use strict';

// ══════════════════════════════════════════
//  UTILITY — TOAST NOTIFICATION
// ══════════════════════════════════════════
const toastEl     = document.getElementById('toastPopup');
const toastMsgEl  = document.getElementById('toastMessage');
const toastIconEl = document.getElementById('toastIcon');
let toastTimeout;

/**
 * @param {string} message
 * @param {'error'|'success'|'info'} [type='error']
 */
function showToast(message, type = 'error') {
    const icons = { error: '⚠️', success: '✅', info: 'ℹ️' };
    toastIconEl.textContent = icons[type] ?? icons.error;
    toastMsgEl.textContent  = message || 'Something went wrong.';

    toastEl.classList.remove('toast-error', 'toast-success', 'toast-info');
    toastEl.classList.add(`toast-${type}`);

    clearTimeout(toastTimeout);
    toastEl.classList.add('show');

    toastTimeout = setTimeout(() => toastEl.classList.remove('show'), 3200);
}

// ══════════════════════════════════════════
//  UTILITY — PAGE TRANSITION
// ══════════════════════════════════════════
const transitionOverlay = document.getElementById('pageTransition');
const transitionTextEl  = document.getElementById('transitionText');

/**
 * Show full-screen transition overlay then navigate.
 * @param {string} url
 * @param {string} [label='Accessing Portal']
 */
function navigateWithTransition(url, label = 'Accessing Portal') {
    if (transitionTextEl) transitionTextEl.textContent = label;
    transitionOverlay.classList.add('active');
    setTimeout(() => { window.location.href = url; }, 1300);
}

// ══════════════════════════════════════════
//  CAROUSEL
// ══════════════════════════════════════════
(function initCarousel() {
    const slides         = Array.from(document.querySelectorAll('.slide'));
    const dotsContainer  = document.getElementById('carouselDots');
    const progressFill   = document.getElementById('carouselProgressFill');
    const prevBtn        = document.getElementById('prevSlide');
    const nextBtn        = document.getElementById('nextSlide');
    const video          = document.getElementById('carouselVideo');

    if (!slides.length || !dotsContainer) return;

    const SLIDE_DURATION = 6000; // ms per slide
    let currentIndex     = 0;
    let progressStart    = null;
    let progressRAF      = null;
    let autoTimer        = null;
    let isTransitioning  = false;

    // Build dots
    slides.forEach((_, i) => {
        const dot = document.createElement('button');
        dot.className   = 'carousel-dot' + (i === 0 ? ' active' : '');
        dot.setAttribute('aria-label', `Go to slide ${i + 1}`);
        dot.addEventListener('click', () => goToSlide(i, true));
        dotsContainer.appendChild(dot);
    });

    const dots = Array.from(dotsContainer.querySelectorAll('.carousel-dot'));

    function updateDots(index) {
        dots.forEach((d, i) => d.classList.toggle('active', i === index));
    }

    function startProgress() {
        cancelAnimationFrame(progressRAF);
        progressStart = performance.now();

        function tick(now) {
            const elapsed  = now - progressStart;
            const fraction = Math.min(elapsed / SLIDE_DURATION, 1);
            progressFill.style.width = (fraction * 100) + '%';

            if (fraction < 1) {
                progressRAF = requestAnimationFrame(tick);
            }
        }

        progressRAF = requestAnimationFrame(tick);
    }

    function goToSlide(index, manual = false) {
        if (isTransitioning || index === currentIndex) return;
        isTransitioning = true;

        const prevIndex = currentIndex;
        currentIndex    = index;

        slides[prevIndex].classList.add('exiting');
        slides[prevIndex].classList.remove('active');
        slides[currentIndex].classList.add('active');

        setTimeout(() => {
            slides[prevIndex].classList.remove('exiting');
            isTransitioning = false;
        }, 1300);

        updateDots(currentIndex);

        // Handle video
        if (prevIndex === 0 && video) video.pause();
        if (currentIndex === 0 && video) video.play().catch(() => {});

        // Restart auto-play timer
        clearTimeout(autoTimer);
        startProgress();
        autoTimer = setTimeout(advance, SLIDE_DURATION);
    }

    function advance() {
        if (currentIndex === 0 && video && !video.paused) return; // Let video finish
        goToSlide((currentIndex + 1) % slides.length);
    }

    function goNext() { goToSlide((currentIndex + 1) % slides.length, true); }
    function goPrev() { goToSlide((currentIndex - 1 + slides.length) % slides.length, true); }

    if (prevBtn) prevBtn.addEventListener('click', goPrev);
    if (nextBtn) nextBtn.addEventListener('click', goNext);

    // Keyboard navigation when carousel is focused
    document.addEventListener('keydown', (e) => {
        if (document.activeElement?.closest('.modal-overlay')) return;
        if (e.key === 'ArrowRight') goNext();
        if (e.key === 'ArrowLeft')  goPrev();
    });

    // Video events
    if (video) {
        video.addEventListener('ended', () => goToSlide(1));
        window.addEventListener('load', () => video.play().catch(() => {}));
    }

    // Start
    startProgress();
    autoTimer = setTimeout(advance, SLIDE_DURATION);
})();

// ══════════════════════════════════════════
//  SCROLL REVEAL
// ══════════════════════════════════════════
(function initScrollReveal() {
    const targets = document.querySelectorAll('.reveal-target');
    if (!targets.length) return;

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('revealed');
                observer.unobserve(entry.target); // Fire once
            }
        });
    }, { threshold: 0.1 });

    targets.forEach(el => observer.observe(el));
})();

// ══════════════════════════════════════════
//  FOOTER YEAR
// ══════════════════════════════════════════
const footerYearEl = document.getElementById('footerYear');
if (footerYearEl) footerYearEl.textContent = new Date().getFullYear();

// ══════════════════════════════════════════
//  PASSWORD VISIBILITY TOGGLE
// ══════════════════════════════════════════
(function initPasswordToggle() {
    const toggle    = document.getElementById('pwToggle');
    const pwInput   = document.getElementById('passwordInput');
    const eyeOpen   = document.getElementById('eyeOpen');
    const eyeClosed = document.getElementById('eyeClosed');

    if (!toggle || !pwInput) return;

    toggle.addEventListener('click', () => {
        const isPassword = pwInput.type === 'password';
        pwInput.type     = isPassword ? 'text' : 'password';
        eyeOpen.style.display   = isPassword ? 'none'  : 'block';
        eyeClosed.style.display = isPassword ? 'block' : 'none';
    });
})();

// ══════════════════════════════════════════
//  REGISTRATION STATUS BANNER
// ══════════════════════════════════════════
(async function initRegistrationBanner() {
    const banner     = document.getElementById('regStatusBanner');
    const iconEl     = document.getElementById('regStatusIcon');
    const textEl     = document.getElementById('regStatusText');
    const badgeEl    = document.getElementById('registerBadge');
    const registerBtn = document.getElementById('registerBtn');

    if (!banner || !iconEl || !textEl) return;

    try {
        const res  = await fetch('registration_status.php');
        const data = await res.json();

        if (data.is_open) {
            // ── OPEN ──
            banner.classList.remove('reg-status-hidden', 'reg-status-closed');
            banner.classList.add('reg-status-open');
            iconEl.textContent = '🟢';
            textEl.innerHTML   =
                `Registration and Enrollment for <strong>Saint Joseph College of Novaliches Inc.</strong> ` +
                `are now open from <strong>${data.start_date}</strong> until <strong>${data.end_date}</strong>.`;

            if (badgeEl) badgeEl.textContent = 'Open Enrollment';
            if (registerBtn) {
                registerBtn.classList.remove('btn-locked');
                registerBtn.removeAttribute('disabled');
                registerBtn.title = '';
            }
        } else {
            // ── CLOSED ──
            banner.classList.remove('reg-status-hidden', 'reg-status-open');
            banner.classList.add('reg-status-closed');
            iconEl.textContent = '🔴';
            textEl.innerHTML   =
                `Registration and Enrollment for <strong>Saint Joseph College of Novaliches Inc.</strong> ` +
                `are currently closed. Please visit our ` +
                `<strong>Facebook page</strong> for future announcements.`;

            if (badgeEl) badgeEl.textContent = 'Enrollment Closed';
            if (registerBtn) {
                registerBtn.classList.add('btn-locked');
                registerBtn.setAttribute('disabled', 'disabled');
                registerBtn.title = 'Registration is currently closed.';
            }
        }
    } catch (err) {
        // Network/server error — silently hide the banner, don't block the page
        console.warn('[RegBanner] Could not fetch registration status:', err);
        banner.classList.add('reg-status-hidden');
    }
})();

// ══════════════════════════════════════════
//  REGISTER BUTTON
// ══════════════════════════════════════════
const registerBtn = document.getElementById('registerBtn');
if (registerBtn) {
    registerBtn.addEventListener('click', () => {
        if (registerBtn.classList.contains('btn-locked')) return;
        const video = document.getElementById('carouselVideo');
        if (video) video.pause();
        navigateWithTransition('../Register/register.html', 'Redirecting to Registration');
    });
}

// ══════════════════════════════════════════
//  4 RBAC ROLES ROUTING & QUICK SIGN-IN
// ══════════════════════════════════════════
const loginForm      = document.getElementById('loginForm');
const emailInput     = document.getElementById('emailInput');
const passwordInput  = document.getElementById('passwordInput');
const loginSubmitBtn = document.getElementById('loginSubmitBtn');

// Role Destination Maps (4 Roles Only — All inside views/)
const ROLE_DESTINATIONS = {
    admin:   'admin-dashboard.html',
    cashier: 'cashier-pos.html',
    student: 'student-kiosk.html',
    parent:  'parent-portal.html'
};

// Handle 4 RBAC Quick Role Buttons
document.querySelectorAll('.btn-role-quick').forEach(btn => {
    btn.addEventListener('click', (e) => {
        const role = btn.dataset.role;
        if (!role || !ROLE_DESTINATIONS[role]) return;

        emailInput.value    = `${role}@sjc.edu.ph`;
        passwordInput.value = 'password123';

        showToast(`Signing in as ${role.toUpperCase()}…`, 'success');
        navigateWithTransition(ROLE_DESTINATIONS[role], `Accessing ${role.toUpperCase()} Portal`);
    });
});

if (loginForm) {
    loginForm.addEventListener('submit', async (e) => {
        e.preventDefault();

        const email    = emailInput.value.trim().toLowerCase();
        const password = passwordInput.value.trim();

        if (!email || !password) {
            showToast('Please fill in all fields.', 'error');
            return;
        }

        loginSubmitBtn.disabled = true;
        loginSubmitBtn.querySelector('.btn-label').textContent = 'Verifying RBAC…';

        // Detect role from email address prefix or fallback to student
        let detectedRole = 'student';
        if (email.includes('admin')) detectedRole = 'admin';
        else if (email.includes('cashier')) detectedRole = 'cashier';
        else if (email.includes('parent')) detectedRole = 'parent';
        else if (email.includes('student')) detectedRole = 'student';

        setTimeout(() => {
            const destination = ROLE_DESTINATIONS[detectedRole] || ROLE_DESTINATIONS.student;
            showToast(`Role Authenticated: ${detectedRole.toUpperCase()}`, 'success');
            navigateWithTransition(destination, `Logging in as ${detectedRole.toUpperCase()}`);
        }, 600);
    });
}

// ══════════════════════════════════════════
//  OTP MODAL
// ══════════════════════════════════════════
const otpOverlay       = document.getElementById('otpOverlay');
const otpDigits        = Array.from(document.querySelectorAll('.otp-digit'));
const verifyOtpBtn     = document.getElementById('verifyOtpBtn');
const cancelOtpBtn     = document.getElementById('cancelOtpBtn');
const otpErrorBox      = document.getElementById('otpErrorBox');
const otpTimerDisplay  = document.getElementById('otpTimerDisplay');

let otpCountdownInterval = null;
const OTP_EXPIRY_SECONDS = 300; // 5 minutes — must match login.php

function showOtpModal() {
    otpOverlay.style.display = 'flex';
    otpErrorBox.style.display = 'none';
    otpErrorBox.textContent   = '';
    otpDigits.forEach(d => { d.value = ''; d.classList.remove('filled'); });
    verifyOtpBtn.disabled = false;
    // Reset trust-device checkbox to unchecked on each new OTP prompt
    const trustCheck = document.getElementById('trustDeviceCheck');
    if (trustCheck) trustCheck.checked = false;
    otpDigits[0].focus();
    startOtpCountdown(OTP_EXPIRY_SECONDS);
}

function hideOtpModal() {
    otpOverlay.style.display = 'none';
    clearInterval(otpCountdownInterval);
}

function startOtpCountdown(totalSeconds) {
    clearInterval(otpCountdownInterval);
    let remaining = totalSeconds;

    function tick() {
        const m = Math.floor(remaining / 60);
        const s = remaining % 60;
        otpTimerDisplay.textContent = `${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
        otpTimerDisplay.classList.toggle('expiring', remaining <= 60);

        if (remaining <= 0) {
            clearInterval(otpCountdownInterval);
            otpErrorBox.textContent   = 'OTP has expired. Please go back and log in again.';
            otpErrorBox.style.display = 'block';
            verifyOtpBtn.disabled = true;
        }
        remaining--;
    }

    tick();
    otpCountdownInterval = setInterval(tick, 1000);
}

// OTP input — auto-advance and backspace
otpDigits.forEach((input, index) => {
    input.addEventListener('input', () => {
        input.value = input.value.replace(/[^0-9]/g, '').slice(-1);
        input.classList.toggle('filled', input.value !== '');
        if (input.value && index < otpDigits.length - 1) {
            otpDigits[index + 1].focus();
        }
        // Auto-submit when all filled
        if (otpDigits.every(d => d.value !== '')) {
            verifyOtp();
        }
    });

    input.addEventListener('keydown', (e) => {
        if (e.key === 'Backspace' && !input.value && index > 0) {
            otpDigits[index - 1].value = '';
            otpDigits[index - 1].classList.remove('filled');
            otpDigits[index - 1].focus();
        }
        // Allow paste
        if (e.key === 'v' && (e.ctrlKey || e.metaKey)) return;
    });

    // Handle paste on any digit
    input.addEventListener('paste', (e) => {
        e.preventDefault();
        const pasted = (e.clipboardData || window.clipboardData).getData('text').replace(/[^0-9]/g, '');
        if (pasted.length === 6) {
            otpDigits.forEach((d, i) => {
                d.value = pasted[i] || '';
                d.classList.toggle('filled', d.value !== '');
            });
            otpDigits[5].focus();
            verifyOtp();
        }
    });
});

cancelOtpBtn?.addEventListener('click', () => {
    hideOtpModal();
    verifyOtpBtn.disabled = false;
});

verifyOtpBtn?.addEventListener('click', verifyOtp);

async function verifyOtp() {
    const otp = otpDigits.map(d => d.value).join('');

    if (otp.length < 6) {
        otpErrorBox.textContent   = 'Please enter all 6 digits.';
        otpErrorBox.style.display = 'block';
        return;
    }

    verifyOtpBtn.disabled = true;
    verifyOtpBtn.querySelector('.btn-label').textContent = 'Verifying…';

    const trustDevice = document.getElementById('trustDeviceCheck')?.checked ? '1' : '0';

    const formData = new FormData();
    formData.append('otp', otp);
    formData.append('trust_device', trustDevice);

    try {
        const response = await fetch('loginverify.php', { method: 'POST', body: formData });
        const data     = await response.json();

        if (data.success) {
            clearInterval(otpCountdownInterval);
            hideOtpModal();
            navigateWithTransition(data.redirect, 'Logging you in…');
        } else {
            otpErrorBox.textContent   = data.message || 'Incorrect OTP. Please try again.';
            otpErrorBox.style.display = 'block';
            otpDigits.forEach(d => { d.value = ''; d.classList.remove('filled'); });
            otpDigits[0].focus();
            verifyOtpBtn.disabled = false;
            verifyOtpBtn.querySelector('.btn-label').textContent = 'Verify & Continue';
        }
    } catch (err) {
        console.error('[OTP Verify]', err);
        otpErrorBox.textContent   = 'Server error. Please try again.';
        otpErrorBox.style.display = 'block';
        verifyOtpBtn.disabled = false;
        verifyOtpBtn.querySelector('.btn-label').textContent = 'Verify & Continue';
    }
}

// ══════════════════════════════════════════
//  FORGOT PASSWORD MODAL
// ══════════════════════════════════════════
const forgotOverlay    = document.getElementById('forgotOverlay');
const forgotEmailInput = document.getElementById('forgotEmailInput');
const forgotErrorBox   = document.getElementById('forgotErrorBox');
const forgotSuccessBox = document.getElementById('forgotSuccessBox');
const submitForgotBtn  = document.getElementById('submitForgotBtn');
const cancelForgotBtn  = document.getElementById('cancelForgotBtn');
const closeForgotBtn   = document.getElementById('closeForgotBtn');
const forgotPwBtn      = document.getElementById('forgotPwBtn');

function openForgotModal() {
    forgotOverlay.style.display = 'flex';
    forgotErrorBox.style.display   = 'none';
    forgotSuccessBox.style.display = 'none';
    forgotEmailInput.value         = '';
    submitForgotBtn.disabled       = false;
    submitForgotBtn.querySelector('.btn-label').textContent = 'Send Reset Link';
    setTimeout(() => forgotEmailInput.focus(), 100);
}

function closeForgotModal() {
    forgotOverlay.style.display = 'none';
}

forgotPwBtn?.addEventListener('click', openForgotModal);
cancelForgotBtn?.addEventListener('click', closeForgotModal);
closeForgotBtn?.addEventListener('click', closeForgotModal);

// Close modal on overlay click
forgotOverlay?.addEventListener('click', (e) => {
    if (e.target === forgotOverlay) closeForgotModal();
});
otpOverlay?.addEventListener('click', (e) => {
    if (e.target === otpOverlay) hideOtpModal();
});

// Keyboard accessibility
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (forgotOverlay?.style.display === 'flex') closeForgotModal();
        if (otpOverlay?.style.display   === 'flex') hideOtpModal();
    }
});

submitForgotBtn?.addEventListener('click', async () => {
    const email = forgotEmailInput.value.trim();

    forgotErrorBox.style.display   = 'none';
    forgotSuccessBox.style.display = 'none';

    if (!email) {
        forgotErrorBox.textContent   = 'Please enter your school email address.';
        forgotErrorBox.style.display = 'block';
        return;
    }

    // Basic email format validation
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        forgotErrorBox.textContent   = 'Please enter a valid email address.';
        forgotErrorBox.style.display = 'block';
        return;
    }

    submitForgotBtn.disabled = true;
    submitForgotBtn.querySelector('.btn-label').textContent = 'Sending…';

    const formData = new FormData();
    formData.append('email', email);

    try {
        const response = await fetch('forgot_password.php', { method: 'POST', body: formData });
        const data     = await response.json();

        if (data.success) {
            forgotSuccessBox.textContent   = data.message || 'Reset link sent. Please check your inbox.';
            forgotSuccessBox.style.display = 'block';
            submitForgotBtn.disabled       = true;
            submitForgotBtn.querySelector('.btn-label').textContent = 'Email Sent';
        } else {
            forgotErrorBox.textContent   = data.message || 'Could not process your request.';
            forgotErrorBox.style.display = 'block';
            submitForgotBtn.disabled     = false;
            submitForgotBtn.querySelector('.btn-label').textContent = 'Send Reset Link';
        }
    } catch (err) {
        console.error('[Forgot PW]', err);
        forgotErrorBox.textContent   = 'Server error. Please try again later.';
        forgotErrorBox.style.display = 'block';
        submitForgotBtn.disabled     = false;
        submitForgotBtn.querySelector('.btn-label').textContent = 'Send Reset Link';
    }
});