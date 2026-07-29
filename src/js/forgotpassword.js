/* ============================================================
   forgotpassword.js
   Multi-step: Email → New Password → OTP → Success
   ============================================================ */

"use strict";

// ── Helpers ──────────────────────────────────────────────────
const $ = id => document.getElementById(id);
const steps = ['step-email','step-password','step-otp','step-success'];

function showStep(id) {
  steps.forEach(s => {
    const el = $(s);
    if (el) {
      if (s === id) {
        el.classList.remove('hidden');
        el.style.animation = 'none';
        void el.offsetHeight; // reflow
        el.style.animation = '';
      } else {
        el.classList.add('hidden');
      }
    }
  });
}

function setLoading(btn, textEl, loaderEl, on) {
  btn.disabled = on;
  textEl.classList.toggle('hidden', on);
  loaderEl.classList.toggle('hidden', !on);
}

function showError(id, msg) {
  const el = $(id);
  if (el) el.textContent = msg;
}

function clearErrors(...ids) {
  ids.forEach(id => { const el = $(id); if (el) el.textContent = ''; });
}

function markFieldError(inputId, hasError) {
  const input = document.getElementById(inputId);
  if (input) input.classList.toggle('error-state', hasError);
}

// ── State ─────────────────────────────────────────────────────
let userEmail      = '';
let newPasswordVal = '';
let countdownTimer = null;

// ── STEP 1: Email Form ────────────────────────────────────────
const emailForm   = $('emailForm');
const sendOtpBtn  = $('sendOtpBtn');
const emailInput  = $('email');

emailForm.addEventListener('submit', async e => {
  e.preventDefault();
  clearErrors('emailError');
  markFieldError('email', false);

  const email = emailInput.value.trim();
  if (!email) {
    showError('emailError', 'Please enter your email address.');
    markFieldError('email', true);
    return;
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    showError('emailError', 'Please enter a valid email address.');
    markFieldError('email', true);
    return;
  }

  const btnText   = sendOtpBtn.querySelector('.btn-text');
  const btnLoader = sendOtpBtn.querySelector('.btn-loader');
  setLoading(sendOtpBtn, btnText, btnLoader, true);

  try {
    const res  = await fetch('forgotpassword.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ action: 'check_email', email })
    });
    const data = await res.json();

    if (data.success) {
      userEmail = email;
      showStep('step-password');
    } else {
      showError('emailError', data.message || 'No account found with that email.');
      markFieldError('email', true);
    }
  } catch {
    showError('emailError', 'Network error. Please try again.');
  } finally {
    setLoading(sendOtpBtn, btnText, btnLoader, false);
  }
});

// ── STEP 2: Password Strength ─────────────────────────────────
const newPwInput = $('newPassword');
const bar        = $('strengthBar');
const label      = $('strengthLabel');
const rules = {
  length:  { el: $('rule-length'),  re: /.{8,}/        },
  upper:   { el: $('rule-upper'),   re: /[A-Z]/         },
  lower:   { el: $('rule-lower'),   re: /[a-z]/         },
  number:  { el: $('rule-number'),  re: /[0-9]/         },
  special: { el: $('rule-special'), re: /[^A-Za-z0-9]/  },
};
const strengthLabels = ['–','Weak','Fair','Good','Strong'];
const strengthClasses = ['','s1','s2','s3','s4'];

function checkStrength(pw) {
  let score = 0;
  for (const key in rules) {
    const r = rules[key];
    const pass = r.re.test(pw);
    r.el.classList.toggle('pass', pass);
    const icon = r.el.querySelector('.rule-icon');
    icon.textContent = pass ? '✓' : '✕';
    if (pass) score++;
  }
  bar.className = 'strength-bar-fill ' + (pw.length ? strengthClasses[score] || 's4' : '');
  const s = pw.length ? Math.min(score, 4) : 0;
  label.textContent  = strengthLabels[s];
  label.className    = 'strength-label ' + (pw.length ? strengthClasses[s] : '');
  return score;
}

newPwInput.addEventListener('input', () => {
  checkStrength(newPwInput.value);
  markFieldError('newPassword', false);
  clearErrors('newPasswordError');
});

// Toggle password visibility
document.querySelectorAll('.toggle-pw').forEach(btn => {
  btn.addEventListener('click', () => {
    const target = document.getElementById(btn.dataset.target);
    const isText = target.type === 'text';
    target.type = isText ? 'password' : 'text';
    // swap icon stroke style as visual hint
    btn.querySelector('svg').style.opacity = isText ? '1' : '0.5';
  });
});

// ── STEP 2: Password Form Submit ──────────────────────────────
const passwordForm  = $('passwordForm');
const sendOtpBtn2   = $('sendOtpBtn2');

passwordForm.addEventListener('submit', async e => {
  e.preventDefault();
  clearErrors('newPasswordError','confirmPasswordError');
  markFieldError('newPassword', false);
  markFieldError('confirmPassword', false);

  const pw  = $('newPassword').value;
  const cpw = $('confirmPassword').value;
  const score = checkStrength(pw);

  if (!pw) {
    showError('newPasswordError', 'Please enter a new password.');
    markFieldError('newPassword', true);
    return;
  }
  if (score < 3) {
    showError('newPasswordError', 'Password is too weak. Please meet at least 3 of the requirements.');
    markFieldError('newPassword', true);
    return;
  }
  if (!cpw) {
    showError('confirmPasswordError', 'Please confirm your new password.');
    markFieldError('confirmPassword', true);
    return;
  }
  if (pw !== cpw) {
    showError('confirmPasswordError', 'Passwords do not match.');
    markFieldError('confirmPassword', true);
    return;
  }

  newPasswordVal = pw;

  const btnText   = sendOtpBtn2.querySelector('.btn-text');
  const btnLoader = sendOtpBtn2.querySelector('.btn-loader');
  setLoading(sendOtpBtn2, btnText, btnLoader, true);

  try {
    const res  = await fetch('forgotpassword.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ action: 'send_otp', email: userEmail })
    });
    const data = await res.json();

    if (data.success) {
      $('otpEmailDisplay').textContent = userEmail;
      showStep('step-otp');
      startCountdown();
      $('otpInputs').querySelectorAll('.otp-box')[0].focus();
    } else {
      showError('confirmPasswordError', data.message || 'Failed to send OTP. Try again.');
    }
  } catch {
    showError('confirmPasswordError', 'Network error. Please try again.');
  } finally {
    setLoading(sendOtpBtn2, btnText, btnLoader, false);
  }
});

// ── Back links ────────────────────────────────────────────────
$('backToEmail').addEventListener('click', e => {
  e.preventDefault();
  clearErrors('newPasswordError','confirmPasswordError');
  showStep('step-email');
});

$('backToPassword').addEventListener('click', e => {
  e.preventDefault();
  clearErrors('otpError');
  stopCountdown();
  showStep('step-password');
});

// ── STEP 3: OTP Boxes ─────────────────────────────────────────
const otpBoxes = document.querySelectorAll('.otp-box');

otpBoxes.forEach((box, i) => {
  box.addEventListener('input', e => {
    const val = e.target.value.replace(/\D/g,'');
    box.value = val.slice(-1);
    box.classList.toggle('filled', !!box.value);
    if (val && i < otpBoxes.length - 1) otpBoxes[i + 1].focus();
    clearErrors('otpError');
    otpBoxes.forEach(b => b.classList.remove('error-state'));
  });

  box.addEventListener('keydown', e => {
    if (e.key === 'Backspace') {
      if (!box.value && i > 0) {
        otpBoxes[i - 1].value = '';
        otpBoxes[i - 1].classList.remove('filled');
        otpBoxes[i - 1].focus();
      }
      box.classList.remove('filled');
    }
    if (e.key === 'ArrowLeft' && i > 0) otpBoxes[i - 1].focus();
    if (e.key === 'ArrowRight' && i < otpBoxes.length - 1) otpBoxes[i + 1].focus();
  });

  box.addEventListener('paste', e => {
    e.preventDefault();
    const text = (e.clipboardData || window.clipboardData).getData('text').replace(/\D/g,'');
    [...text].slice(0, 6).forEach((ch, j) => {
      if (otpBoxes[j]) {
        otpBoxes[j].value = ch;
        otpBoxes[j].classList.add('filled');
      }
    });
    const focus = Math.min(text.length, 5);
    otpBoxes[focus].focus();
  });
});

// ── OTP Form Submit ───────────────────────────────────────────
const otpForm      = $('otpForm');
const verifyOtpBtn = $('verifyOtpBtn');

otpForm.addEventListener('submit', async e => {
  e.preventDefault();
  clearErrors('otpError');
  otpBoxes.forEach(b => b.classList.remove('error-state'));

  const otp = [...otpBoxes].map(b => b.value).join('');
  if (otp.length < 6) {
    showError('otpError', 'Please enter the complete 6-digit code.');
    otpBoxes.forEach(b => { if (!b.value) b.classList.add('error-state'); });
    return;
  }

  const btnText   = verifyOtpBtn.querySelector('.btn-text');
  const btnLoader = verifyOtpBtn.querySelector('.btn-loader');
  setLoading(verifyOtpBtn, btnText, btnLoader, true);

  try {
    const res  = await fetch('forgotpassword.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        action: 'verify_otp',
        email: userEmail,
        otp,
        new_password: newPasswordVal
      })
    });
    const data = await res.json();

    if (data.success) {
      stopCountdown();
      showStep('step-success');
    } else {
      showError('otpError', data.message || 'Invalid or expired OTP. Try again.');
      otpBoxes.forEach(b => b.classList.add('error-state'));
    }
  } catch {
    showError('otpError', 'Network error. Please try again.');
  } finally {
    setLoading(verifyOtpBtn, btnText, btnLoader, false);
  }
});

// ── Countdown ─────────────────────────────────────────────────
const OTP_DURATION = 10 * 60; // 10 minutes

function startCountdown() {
  let remaining = OTP_DURATION;
  const display  = $('countdownDisplay');
  const resendBtn = $('resendOtp');
  display.classList.remove('expired');
  resendBtn.classList.add('disabled');

  stopCountdown();
  countdownTimer = setInterval(() => {
    remaining--;
    const m = String(Math.floor(remaining / 60)).padStart(2,'0');
    const s = String(remaining % 60).padStart(2,'0');
    display.textContent = `${m}:${s}`;

    if (remaining <= 0) {
      clearInterval(countdownTimer);
      display.textContent = 'Expired';
      display.classList.add('expired');
      resendBtn.classList.remove('disabled');
    }
  }, 1000);
}

function stopCountdown() {
  if (countdownTimer) {
    clearInterval(countdownTimer);
    countdownTimer = null;
  }
}

// ── Resend OTP ────────────────────────────────────────────────
$('resendOtp').addEventListener('click', async e => {
  e.preventDefault();
  if ($('resendOtp').classList.contains('disabled')) return;

  $('resendOtp').classList.add('disabled');
  clearErrors('otpError');
  otpBoxes.forEach(b => { b.value = ''; b.classList.remove('filled','error-state'); });

  try {
    const res  = await fetch('forgotpassword.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ action: 'send_otp', email: userEmail })
    });
    const data = await res.json();
    if (data.success) {
      startCountdown();
      otpBoxes[0].focus();
    } else {
      showError('otpError', data.message || 'Could not resend OTP.');
      $('resendOtp').classList.remove('disabled');
    }
  } catch {
    showError('otpError', 'Network error. Please try again.');
    $('resendOtp').classList.remove('disabled');
  }
});