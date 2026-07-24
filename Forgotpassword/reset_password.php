<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Reset Password — SJC Portal</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@400;500;600;700&family=DM+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
  <style>
    /* ── Variables ───────────────────────────────────────── */
    :root {
      --maroon:      #1a0000;
      --maroon-mid:  #3d0808;
      --gold:        #c9a84c;
      --gold-light:  #e2c97e;
      --gold-dim:    #7a6129;
      --surface:     rgba(255,255,255,0.04);
      --surface-hov: rgba(255,255,255,0.07);
      --border:      rgba(201,168,76,0.18);
      --border-hov:  rgba(201,168,76,0.40);
      --text-prime:  #f0ead6;
      --text-mid:    #9ea8b4;
      --text-dim:    #5c6978;
      --error:       #e05c5c;
      --success:     #4caf79;
      --radius:      12px;
      --t:           0.26s cubic-bezier(.4,0,.2,1);
    }

    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'DM Sans', sans-serif;
      background: var(--maroon);
      color: var(--text-prime);
      min-height: 100vh;
      display: flex; align-items: center; justify-content: center;
      overflow-x: hidden;
    }

    /* ── Background ─────────────────────────────────────── */
    .bg {
      position: fixed; inset: 0; z-index: 0; overflow: hidden;
    }
    .bg-orb {
      position: absolute; border-radius: 50%;
      filter: blur(90px); opacity: 0.10;
    }
    .bg-orb-1 {
      width: 500px; height: 500px;
      background: radial-gradient(circle, #c9a84c, transparent 70%);
      top: -200px; left: -100px;
      animation: drift 18s ease-in-out infinite alternate;
    }
    .bg-orb-2 {
      width: 400px; height: 400px;
      background: radial-gradient(circle, #5c1010, transparent 70%);
      bottom: -150px; right: -80px;
      animation: drift 22s ease-in-out infinite alternate-reverse;
    }
    @keyframes drift {
      from { transform: translate(0,0); }
      to   { transform: translate(30px, 20px); }
    }
    .bg-grid {
      position: absolute; inset: 0;
      background-image:
        linear-gradient(rgba(201,168,76,0.03) 1px, transparent 1px),
        linear-gradient(90deg, rgba(201,168,76,0.03) 1px, transparent 1px);
      background-size: 48px 48px;
    }

    /* ── Card ────────────────────────────────────────────── */
    .page-wrap {
      position: relative; z-index: 1;
      width: 100%; padding: 2rem 1rem;
      display: flex; align-items: center; justify-content: center;
    }
    .card {
      width: 100%; max-width: 460px;
      background: linear-gradient(160deg, rgba(255,255,255,0.05), rgba(255,255,255,0.02));
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 2.6rem 2.4rem;
      box-shadow: 0 32px 80px rgba(0,0,0,0.55), 0 8px 24px rgba(0,0,0,0.35);
      backdrop-filter: blur(20px);
      animation: cardIn 0.5s cubic-bezier(.16,1,.3,1) both;
    }
    @keyframes cardIn {
      from { opacity: 0; transform: translateY(22px) scale(0.97); }
      to   { opacity: 1; transform: translateY(0) scale(1); }
    }

    /* top gold rule */
    .card::before {
      content: '';
      display: block; height: 2px; width: 56px;
      background: linear-gradient(90deg, transparent, var(--gold), transparent);
      margin: 0 auto 2rem; border-radius: 99px;
    }

    /* ── Header ──────────────────────────────────────────── */
    .header { text-align: center; margin-bottom: 2rem; }
    .logo {
      height: 68px; width: auto;
      margin-bottom: 1.2rem;
      filter: drop-shadow(0 4px 16px rgba(201,168,76,0.25));
    }
    .card-title {
      font-family: 'Cormorant Garamond', serif;
      font-size: 1.9rem; font-weight: 600;
      color: var(--gold-light);
      letter-spacing: 0.02em; line-height: 1.2;
      margin-bottom: 0.55rem;
    }
    .card-sub {
      font-size: 0.875rem; color: var(--text-mid);
      line-height: 1.65; max-width: 340px; margin: 0 auto;
    }

    /* ── Fields ──────────────────────────────────────────── */
    .field-group { display: flex; flex-direction: column; gap: 5px; margin-bottom: 1.1rem; }
    .field-label {
      font-size: 0.76rem; font-weight: 500;
      letter-spacing: 0.08em; text-transform: uppercase;
      color: var(--text-mid);
    }
    .input-wrap { position: relative; display: flex; align-items: center; }
    .icon-left {
      position: absolute; left: 13px;
      color: var(--gold-dim); line-height: 0;
      pointer-events: none;
      transition: color var(--t);
    }
    .field-input {
      width: 100%;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 0.8rem 2.8rem 0.8rem 2.7rem;
      font-family: 'DM Sans', sans-serif;
      font-size: 0.95rem; color: var(--text-prime);
      outline: none;
      transition: border-color var(--t), background var(--t), box-shadow var(--t);
    }
    .field-input::placeholder { color: var(--text-dim); }
    .field-input:focus {
      border-color: var(--gold);
      background: var(--surface-hov);
      box-shadow: 0 0 0 3px rgba(201,168,76,0.13);
    }
    .input-wrap:focus-within .icon-left { color: var(--gold); }
    .field-input.err { border-color: var(--error); box-shadow: 0 0 0 3px rgba(224,92,92,0.12); }

    .toggle-eye {
      position: absolute; right: 12px;
      background: none; border: none; cursor: pointer;
      color: var(--text-dim); line-height: 0; padding: 4px;
      transition: color var(--t);
    }
    .toggle-eye:hover { color: var(--gold); }

    .field-err { font-size: 0.77rem; color: var(--error); min-height: 1em; }

    /* ── Password Strength ───────────────────────────────── */
    .strength-row {
      display: flex; align-items: center; gap: 9px;
      margin: -0.3rem 0 0.9rem;
    }
    .strength-track {
      flex: 1; height: 4px; border-radius: 99px;
      background: rgba(255,255,255,0.07); overflow: hidden;
    }
    .strength-fill {
      height: 100%; width: 0%; border-radius: 99px;
      background: var(--error);
      transition: width 0.33s ease, background 0.33s ease;
    }
    .strength-fill.s1 { width: 25%; background: #e05c5c; }
    .strength-fill.s2 { width: 50%; background: #e09a4c; }
    .strength-fill.s3 { width: 75%; background: #d4c94c; }
    .strength-fill.s4 { width: 100%; background: var(--success); }
    .strength-lbl {
      font-size: 0.74rem; font-weight: 500;
      min-width: 48px; text-align: right; color: var(--text-dim);
      transition: color 0.28s;
    }
    .strength-lbl.s1 { color: #e05c5c; }
    .strength-lbl.s2 { color: #e09a4c; }
    .strength-lbl.s3 { color: #d4c94c; }
    .strength-lbl.s4 { color: var(--success); }

    /* ── Guidelines ──────────────────────────────────────── */
    .guidelines {
      background: rgba(201,168,76,0.04);
      border: 1px solid rgba(201,168,76,0.11);
      border-radius: 10px;
      padding: 0.9rem 1.1rem;
      margin-bottom: 1.3rem;
    }
    .guidelines-title {
      font-size: 0.7rem; font-weight: 600;
      letter-spacing: 0.09em; text-transform: uppercase;
      color: var(--gold-dim); margin-bottom: 0.55rem;
    }
    .rules { list-style: none; display: flex; flex-direction: column; gap: 4px; }
    .rule {
      font-size: 0.81rem; color: var(--text-dim);
      display: flex; align-items: center; gap: 7px;
      transition: color var(--t);
    }
    .rule-dot {
      width: 15px; height: 15px; border-radius: 50%;
      border: 1px solid currentColor;
      display: inline-flex; align-items: center; justify-content: center;
      font-size: 0.62rem; font-weight: 700; flex-shrink: 0;
    }
    .rule.pass { color: var(--success); }
    .rule.pass .rule-dot { background: rgba(76,175,121,0.12); }

    /* ── Button ──────────────────────────────────────────── */
    .btn-primary {
      display: flex; align-items: center; justify-content: center; gap: 7px;
      width: 100%; padding: 0.88rem 1.5rem; margin-top: 1.4rem;
      background: linear-gradient(135deg, #b8892a 0%, #e2c97e 50%, #b8892a 100%);
      background-size: 200% 100%;
      background-position: 100% 0;
      border: none; border-radius: 10px;
      color: var(--maroon);
      font-family: 'DM Sans', sans-serif;
      font-size: 0.93rem; font-weight: 700; letter-spacing: 0.04em;
      cursor: pointer;
      transition: background-position 0.4s ease, box-shadow var(--t), transform var(--t), opacity var(--t);
      box-shadow: 0 4px 24px rgba(201,168,76,0.28);
    }
    .btn-primary:hover:not(:disabled) {
      background-position: 0 0;
      box-shadow: 0 6px 32px rgba(201,168,76,0.42);
      transform: translateY(-1px);
    }
    .btn-primary:active { transform: translateY(0); }
    .btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }

    .spinner {
      width: 17px; height: 17px;
      border: 2px solid rgba(26,0,0,0.3);
      border-top-color: var(--maroon);
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
      display: none;
    }
    @keyframes spin { to { transform: rotate(360deg); } }

    /* ── State panels ────────────────────────────────────── */
    .error-box, .success-panel { display: none; border-radius: 8px; padding: 12px 16px; }
    .error-box {
      background: rgba(224,92,92,0.1);
      border: 1px solid rgba(224,92,92,0.35);
      color: #e88;
      font-size: 0.85rem; line-height: 1.55;
      margin-bottom: 0.5rem;
    }
    /* ── Expired / invalid token panel ──────────────────── */
    .invalid-panel {
      text-align: center; padding: 1rem 0 0.5rem;
    }
    .invalid-icon {
      width: 64px; height: 64px; border-radius: 50%;
      background: rgba(224,92,92,0.1);
      border: 1px solid rgba(224,92,92,0.3);
      display: flex; align-items: center; justify-content: center;
      margin: 0 auto 1.1rem;
      color: var(--error);
    }

    /* ── Success panel ───────────────────────────────────── */
    .success-panel {
      text-align: center; padding-top: 0.5rem;
    }
    .success-icon {
      width: 68px; height: 68px; border-radius: 50%;
      background: rgba(76,175,121,0.1);
      border: 1px solid rgba(76,175,121,0.3);
      display: flex; align-items: center; justify-content: center;
      margin: 0 auto 1.1rem;
      color: var(--success);
      animation: popIn 0.4s cubic-bezier(.34,1.56,.64,1);
    }
    @keyframes popIn {
      from { opacity: 0; transform: scale(0.5); }
      to   { opacity: 1; transform: scale(1); }
    }

    .btn-back {
      display: block; text-align: center; text-decoration: none;
      margin-top: 1.1rem;
      padding: 0.85rem;
      border: 1px solid var(--border);
      border-radius: 10px;
      color: var(--text-mid);
      font-family: 'DM Sans', sans-serif;
      font-size: 0.88rem;
      transition: border-color var(--t), color var(--t), background var(--t);
    }
    .btn-back:hover { border-color: var(--gold-dim); color: var(--gold-light); background: var(--surface); }

    .hidden { display: none !important; }

    @media (max-width: 500px) {
      .card { padding: 2rem 1.3rem; }
      .card-title { font-size: 1.55rem; }
    }
  </style>
</head>
<body>

<div class="bg">
  <div class="bg-orb bg-orb-1"></div>
  <div class="bg-orb bg-orb-2"></div>
  <div class="bg-grid"></div>
</div>

<div class="page-wrap">
  <div class="card" id="mainCard">

    <div class="header">
      <img src="../Login/Login Media/school no bg.png" alt="SJC Logo" class="logo" />
      <h1 class="card-title" id="cardTitle">Set New Password</h1>
      <p class="card-sub" id="cardSub">Choose a strong password for your account.</p>
    </div>

    <!-- Invalid / expired token state (shown by PHP if token bad) -->
    <div class="invalid-panel hidden" id="invalidPanel">
      <div class="invalid-icon">
        <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/>
          <line x1="12" y1="16" x2="12.01" y2="16"/>
        </svg>
      </div>
      <p id="invalidMsg" style="color:var(--text-mid);font-size:0.9rem;line-height:1.6;margin-bottom:1.4rem;"></p>
      <a href="../Login/Maininterface.html" class="btn-back">← Back to Login</a>
    </div>

    <!-- Password form (hidden when token invalid) -->
    <div id="formSection">
      <div class="error-box" id="errorBox"></div>

      <!-- New Password -->
      <div class="field-group">
        <label class="field-label" for="newPw">New Password</label>
        <div class="input-wrap">
          <span class="icon-left">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <rect x="3" y="11" width="18" height="11" rx="2"/>
              <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
            </svg>
          </span>
          <input type="password" id="newPw" class="field-input" placeholder="Enter new password" autocomplete="new-password" />
          <button type="button" class="toggle-eye" data-target="newPw" aria-label="Toggle">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>
            </svg>
          </button>
        </div>
        <span class="field-err" id="newPwErr"></span>
      </div>

      <!-- Strength meter -->
      <div class="strength-row" id="strengthRow">
        <div class="strength-track"><div class="strength-fill" id="strengthFill"></div></div>
        <span class="strength-lbl" id="strengthLbl">–</span>
      </div>

      <!-- Guidelines checklist -->
      <div class="guidelines">
        <p class="guidelines-title">Strong password checklist</p>
        <ul class="rules">
          <li class="rule" id="r-len"><span class="rule-dot">✕</span> At least 8 characters</li>
          <li class="rule" id="r-up"> <span class="rule-dot">✕</span> One uppercase letter (A–Z)</li>
          <li class="rule" id="r-lo"> <span class="rule-dot">✕</span> One lowercase letter (a–z)</li>
          <li class="rule" id="r-num"><span class="rule-dot">✕</span> One number (0–9)</li>
          <li class="rule" id="r-sp"> <span class="rule-dot">✕</span> One special character (!@#$%…)</li>
        </ul>
      </div>

      <!-- Confirm Password -->
      <div class="field-group">
        <label class="field-label" for="confirmPw">Confirm New Password</label>
        <div class="input-wrap">
          <span class="icon-left">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
            </svg>
          </span>
          <input type="password" id="confirmPw" class="field-input" placeholder="Repeat new password" autocomplete="new-password" />
          <button type="button" class="toggle-eye" data-target="confirmPw" aria-label="Toggle">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>
            </svg>
          </button>
        </div>
        <span class="field-err" id="confirmPwErr"></span>
      </div>

      <button type="button" class="btn-primary" id="submitBtn">
        <span id="btnLabel">Reset Password</span>
        <span class="spinner" id="btnSpinner"></span>
      </button>
    </div>

    <!-- Success state -->
    <div class="success-panel hidden" id="successPanel">
      <div class="success-icon">
        <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
          <polyline points="22 4 12 14.01 9 11.01"/>
        </svg>
      </div>
      <h2 style="font-family:'Cormorant Garamond',serif;font-size:1.55rem;font-weight:600;color:var(--gold-light);margin-bottom:0.5rem;">
        Password Updated!
      </h2>
      <p style="color:var(--text-mid);font-size:0.88rem;line-height:1.6;margin-bottom:1.4rem;">
        Your password has been successfully reset. You can now log in with your new credentials.
      </p>
      <a href="../Login/Maininterface.html" class="btn-back" style="border-color:rgba(76,175,121,0.35);color:var(--success);">
        Back to Login →
      </a>
    </div>

  </div>
</div>

<!-- Inject PHP token validation result as JS vars -->
<?php
/**
 * Token validation block — runs on page load.
 * If the token is invalid or expired, we surface the error in JS.
 */
session_start();
require_once 'logindb.php';

$tokenRaw   = trim($_GET['token'] ?? '');
$tokenValid = false;
$tokenError = '';
$userId     = 0;

if ($tokenRaw === '') {
    $tokenError = 'No reset token provided. Please use the link from your email.';
} else {
    $tokenHash = hash('sha256', $tokenRaw);
    try {
        $stmt = $conn->prepare(
            "SELECT prt.user_id, prt.expires_at
             FROM   password_reset_tokens prt
             JOIN   users u ON u.id = prt.user_id AND u.is_active = 1
             WHERE  prt.token_hash = ?
             LIMIT  1"
        );
        $stmt->execute([$tokenHash]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$row) {
            $tokenError = 'This reset link is invalid or has already been used. Please request a new one.';
        } elseif (strtotime($row['expires_at']) < time()) {
            $tokenError = 'This reset link has expired. Password reset links are valid for 1 hour. Please request a new one.';
            // Clean up expired token
            $del = $conn->prepare("DELETE FROM password_reset_tokens WHERE token_hash = ?");
            $del->execute([$tokenHash]);
        } else {
            $tokenValid = true;
            $userId     = (int)$row['user_id'];
            // Store in session so the AJAX endpoint can trust it
            $_SESSION['reset_token_hash'] = $tokenHash;
            $_SESSION['reset_user_id']    = $userId;
        }
    } catch (PDOException $e) {
        error_log('[reset_password] Token lookup failed: ' . $e->getMessage());
        $tokenError = 'A database error occurred. Please try again.';
    }
}
?>
<script>
  const TOKEN_VALID = <?= $tokenValid ? 'true' : 'false' ?>;
  const TOKEN_ERROR = <?= json_encode($tokenError) ?>;
</script>

<script>
'use strict';

// ── Show invalid state if token bad ──────────────────────
if (!TOKEN_VALID) {
  document.getElementById('formSection').classList.add('hidden');
  document.getElementById('cardTitle').textContent = 'Link Invalid or Expired';
  document.getElementById('cardSub').textContent   = '';
  const panel = document.getElementById('invalidPanel');
  panel.classList.remove('hidden');
  document.getElementById('invalidMsg').textContent = TOKEN_ERROR;
}

// ── Toggle password visibility ────────────────────────────
document.querySelectorAll('.toggle-eye').forEach(btn => {
  btn.addEventListener('click', () => {
    const input = document.getElementById(btn.dataset.target);
    input.type = input.type === 'password' ? 'text' : 'password';
    btn.style.opacity = input.type === 'text' ? '0.5' : '1';
  });
});

// ── Strength checker ──────────────────────────────────────
const pwRules = [
  { id: 'r-len', re: /.{8,}/        },
  { id: 'r-up',  re: /[A-Z]/         },
  { id: 'r-lo',  re: /[a-z]/         },
  { id: 'r-num', re: /[0-9]/         },
  { id: 'r-sp',  re: /[^A-Za-z0-9]/ },
];
const sLabels  = ['–','Weak','Fair','Good','Strong'];
const sClasses = ['', 's1', 's2', 's3', 's4'];

function checkStrength(pw) {
  let score = 0;
  pwRules.forEach(r => {
    const ok  = r.re.test(pw);
    const el  = document.getElementById(r.id);
    el.classList.toggle('pass', ok);
    el.querySelector('.rule-dot').textContent = ok ? '✓' : '✕';
    if (ok) score++;
  });
  const fill = document.getElementById('strengthFill');
  const lbl  = document.getElementById('strengthLbl');
  const s    = pw.length ? Math.min(score, 4) : 0;
  fill.className = 'strength-fill ' + (pw.length ? sClasses[score] || 's4' : '');
  lbl.textContent = sLabels[s];
  lbl.className   = 'strength-lbl ' + (pw.length ? sClasses[s] : '');
  return score;
}

document.getElementById('newPw').addEventListener('input', () => {
  checkStrength(document.getElementById('newPw').value);
  document.getElementById('newPw').classList.remove('err');
  document.getElementById('newPwErr').textContent = '';
});

// ── Submit ────────────────────────────────────────────────
document.getElementById('submitBtn').addEventListener('click', async () => {
  const pw  = document.getElementById('newPw').value;
  const cpw = document.getElementById('confirmPw').value;
  const errBox = document.getElementById('errorBox');

  // Clear errors
  errBox.style.display = 'none';
  ['newPw','confirmPw'].forEach(id => {
    document.getElementById(id).classList.remove('err');
  });
  document.getElementById('newPwErr').textContent    = '';
  document.getElementById('confirmPwErr').textContent = '';

  const score = checkStrength(pw);

  if (!pw) {
    document.getElementById('newPwErr').textContent = 'Please enter a new password.';
    document.getElementById('newPw').classList.add('err');
    return;
  }
  if (score < 3) {
    document.getElementById('newPwErr').textContent = 'Password is too weak — please meet at least 3 requirements.';
    document.getElementById('newPw').classList.add('err');
    return;
  }
  if (!cpw) {
    document.getElementById('confirmPwErr').textContent = 'Please confirm your new password.';
    document.getElementById('confirmPw').classList.add('err');
    return;
  }
  if (pw !== cpw) {
    document.getElementById('confirmPwErr').textContent = 'Passwords do not match.';
    document.getElementById('confirmPw').classList.add('err');
    return;
  }

  // Loading state
  const btn     = document.getElementById('submitBtn');
  const lblEl   = document.getElementById('btnLabel');
  const spinner = document.getElementById('btnSpinner');
  btn.disabled      = true;
  lblEl.textContent = 'Resetting…';
  spinner.style.display = 'inline-block';

  try {
    const fd = new FormData();
    fd.append('new_password', pw);

    const res  = await fetch('do_reset_password.php', { method: 'POST', body: fd });
    const data = await res.json();

    if (data.success) {
      document.getElementById('formSection').classList.add('hidden');
      document.getElementById('successPanel').classList.remove('hidden');
      document.getElementById('cardTitle').textContent = 'Password Updated';
      document.getElementById('cardSub').textContent   = '';
    } else {
      errBox.textContent   = data.message || 'Could not reset password. Please try again.';
      errBox.style.display = 'block';
      btn.disabled = false;
      lblEl.textContent = 'Reset Password';
      spinner.style.display = 'none';
    }
  } catch {
    errBox.textContent   = 'Network error. Please check your connection and try again.';
    errBox.style.display = 'block';
    btn.disabled = false;
    lblEl.textContent = 'Reset Password';
    spinner.style.display = 'none';
  }
});
</script>

</body>
</html>
