<?php
/**
 * SJC Portal — reset_password.php
 * ─────────────────────────────────────────────────────────
 * Location: C:\xampp\htdocs\Login\reset_password.php
 *           (same folder as login.php, forgot_password.php)
 *
 * User lands here from the link in the reset email.
 * PHP validates the token on page load, then shows:
 *   · The password form (valid token)
 *   · An error panel (invalid / expired token)
 */

session_start();
require_once 'logindb.php'; // $conn (PDO)

// ── Validate token on page load ───────────────────────────
$tokenRaw   = trim($_GET['token'] ?? '');
$tokenValid = false;
$tokenError = '';
$userId     = 0;

if ($tokenRaw === '') {
    $tokenError = 'No reset token found. Please use the full link from your email.';
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
            $tokenError = 'This reset link has expired. Password reset links are valid for 1 hour. Please request a new one from the login page.';
        } else {
            $tokenValid = true;
            $userId     = (int)$row['user_id'];
            // Store in session so do_reset_password.php can trust it
            $_SESSION['reset_token_hash'] = $tokenHash;
            $_SESSION['reset_user_id']    = $userId;
        }
    } catch (PDOException $e) {
        error_log('[reset_password] Token lookup: ' . $e->getMessage());
        $tokenError = 'A database error occurred. Please try again.';
    }
}
?>
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
    :root {
      --maroon:     #1a0000;
      --maroon-mid: #3d0808;
      --gold:       #c9a84c;
      --gold-light: #e2c97e;
      --gold-dim:   #7a6129;
      --bg:         rgba(255,255,255,0.04);
      --bg-hov:     rgba(255,255,255,0.07);
      --bdr:        rgba(201,168,76,0.18);
      --bdr-hov:    rgba(201,168,76,0.40);
      --txt:        #f0ead6;
      --txt-mid:    #9ea8b4;
      --txt-dim:    #5c6978;
      --red:        #e05c5c;
      --green:      #4caf79;
      --t:          0.25s cubic-bezier(.4,0,.2,1);
    }
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'DM Sans', sans-serif;
      background: var(--maroon);
      color: var(--txt);
      min-height: 100vh;
      display: flex; align-items: center; justify-content: center;
      overflow-x: hidden;
    }

    /* Background */
    .bg { position: fixed; inset: 0; z-index: 0; overflow: hidden; }
    .bg-orb {
      position: absolute; border-radius: 50%;
      filter: blur(90px); opacity: 0.09;
      animation: drift 20s ease-in-out infinite alternate;
    }
    .bg-orb-1 { width:500px;height:500px;background:radial-gradient(circle,#c9a84c,transparent 70%);top:-180px;left:-80px; }
    .bg-orb-2 { width:400px;height:400px;background:radial-gradient(circle,#5c1010,transparent 70%);bottom:-140px;right:-60px;animation-direction:alternate-reverse; }
    @keyframes drift { to { transform: translate(30px,20px); } }
    .bg-grid {
      position: absolute; inset: 0;
      background-image: linear-gradient(rgba(201,168,76,0.03) 1px, transparent 1px),
                        linear-gradient(90deg, rgba(201,168,76,0.03) 1px, transparent 1px);
      background-size: 48px 48px;
    }

    /* Card */
    .wrap { position:relative;z-index:1;width:100%;padding:2rem 1rem;display:flex;align-items:center;justify-content:center; }
    .card {
      width:100%;max-width:455px;
      background:linear-gradient(160deg,rgba(255,255,255,0.05),rgba(255,255,255,0.02));
      border:1px solid var(--bdr);border-radius:18px;
      padding:2.6rem 2.4rem;
      box-shadow:0 32px 80px rgba(0,0,0,0.55),0 8px 24px rgba(0,0,0,0.35);
      backdrop-filter:blur(20px);
      animation:cardIn .5s cubic-bezier(.16,1,.3,1) both;
    }
    @keyframes cardIn { from{opacity:0;transform:translateY(22px) scale(.97)} to{opacity:1;transform:none} }
    .card::before {
      content:'';display:block;height:2px;width:54px;
      background:linear-gradient(90deg,transparent,var(--gold),transparent);
      margin:0 auto 2rem;border-radius:99px;
    }

    /* Header */
    .hd { text-align:center;margin-bottom:1.8rem; }
    .logo { height:66px;width:auto;margin-bottom:1.1rem;filter:drop-shadow(0 4px 14px rgba(201,168,76,0.22)); }
    .card-title { font-family:'Cormorant Garamond',serif;font-size:1.85rem;font-weight:600;color:var(--gold-light);letter-spacing:.02em;line-height:1.2;margin-bottom:.5rem; }
    .card-sub { font-size:.875rem;color:var(--txt-mid);line-height:1.65;max-width:330px;margin:0 auto; }

    /* Fields */
    .fg { display:flex;flex-direction:column;gap:5px;margin-bottom:1.1rem; }
    .fl { font-size:.75rem;font-weight:500;letter-spacing:.08em;text-transform:uppercase;color:var(--txt-mid); }
    .iw { position:relative;display:flex;align-items:center; }
    .ic { position:absolute;left:13px;color:var(--gold-dim);line-height:0;pointer-events:none;transition:color var(--t); }
    .fi {
      width:100%;background:var(--bg);border:1px solid var(--bdr);border-radius:10px;
      padding:.8rem 2.8rem .8rem 2.65rem;
      font-family:'DM Sans',sans-serif;font-size:.95rem;color:var(--txt);
      outline:none;transition:border-color var(--t),background var(--t),box-shadow var(--t);
    }
    .fi::placeholder { color:var(--txt-dim); }
    .fi:focus { border-color:var(--gold);background:var(--bg-hov);box-shadow:0 0 0 3px rgba(201,168,76,.12); }
    .iw:focus-within .ic { color:var(--gold); }
    .fi.err { border-color:var(--red);box-shadow:0 0 0 3px rgba(224,92,92,.11); }
    .toggle-eye { position:absolute;right:12px;background:none;border:none;cursor:pointer;color:var(--txt-dim);line-height:0;padding:4px;transition:color var(--t); }
    .toggle-eye:hover { color:var(--gold); }
    .ferr { font-size:.76rem;color:var(--red);min-height:1em; }

    /* Strength */
    .srow { display:flex;align-items:center;gap:9px;margin:-0.2rem 0 .9rem; }
    .strk { flex:1;height:4px;border-radius:99px;background:rgba(255,255,255,.07);overflow:hidden; }
    .sfill { height:100%;width:0%;border-radius:99px;background:var(--red);transition:width .3s ease,background .3s ease; }
    .sfill.s1{width:25%;background:#e05c5c} .sfill.s2{width:50%;background:#e09a4c}
    .sfill.s3{width:75%;background:#d4c94c} .sfill.s4{width:100%;background:var(--green)}
    .slbl { font-size:.73rem;font-weight:500;min-width:46px;text-align:right;color:var(--txt-dim);transition:color .25s; }
    .slbl.s1{color:#e05c5c} .slbl.s2{color:#e09a4c} .slbl.s3{color:#d4c94c} .slbl.s4{color:var(--green)}

    /* Guidelines */
    .gl { background:rgba(201,168,76,.04);border:1px solid rgba(201,168,76,.11);border-radius:10px;padding:.85rem 1.1rem;margin-bottom:1.3rem; }
    .gl-title { font-size:.69rem;font-weight:600;letter-spacing:.09em;text-transform:uppercase;color:var(--gold-dim);margin-bottom:.5rem; }
    .rules { list-style:none;display:flex;flex-direction:column;gap:4px; }
    .rule { font-size:.8rem;color:var(--txt-dim);display:flex;align-items:center;gap:7px;transition:color var(--t); }
    .rdot { width:15px;height:15px;border-radius:50%;border:1px solid currentColor;display:inline-flex;align-items:center;justify-content:center;font-size:.6rem;font-weight:700;flex-shrink:0; }
    .rule.pass { color:var(--green); }
    .rule.pass .rdot { background:rgba(76,175,121,.12); }

    /* Button */
    .btn {
      display:flex;align-items:center;justify-content:center;gap:7px;
      width:100%;padding:.87rem 1.5rem;margin-top:1.35rem;
      background:linear-gradient(135deg,#b8892a 0%,#e2c97e 50%,#b8892a 100%);
      background-size:200% 100%;background-position:100% 0;
      border:none;border-radius:10px;
      color:var(--maroon);font-family:'DM Sans',sans-serif;
      font-size:.93rem;font-weight:700;letter-spacing:.04em;cursor:pointer;
      transition:background-position .4s ease,box-shadow var(--t),transform var(--t),opacity var(--t);
      box-shadow:0 4px 22px rgba(201,168,76,.26);
    }
    .btn:hover:not(:disabled) { background-position:0 0;box-shadow:0 6px 30px rgba(201,168,76,.4);transform:translateY(-1px); }
    .btn:active { transform:translateY(0); }
    .btn:disabled { opacity:.5;cursor:not-allowed; }
    .spinner { width:17px;height:17px;border:2px solid rgba(26,0,0,.3);border-top-color:var(--maroon);border-radius:50%;animation:spin .7s linear infinite;display:none; }
    @keyframes spin { to { transform:rotate(360deg); } }

    /* Error / Success panels */
    .ebox { display:none;background:rgba(224,92,92,.09);border:1px solid rgba(224,92,92,.32);color:#e88;font-size:.84rem;line-height:1.55;border-radius:8px;padding:11px 15px;margin-bottom:.5rem; }

    .invalid-panel { text-align:center;padding:.8rem 0 .4rem; }
    .invalid-icon { width:62px;height:62px;border-radius:50%;background:rgba(224,92,92,.09);border:1px solid rgba(224,92,92,.28);display:flex;align-items:center;justify-content:center;margin:0 auto 1rem;color:var(--red); }
    .invalid-msg { color:var(--txt-mid);font-size:.88rem;line-height:1.65;margin-bottom:1.4rem; }

    .success-panel { text-align:center;padding:.6rem 0; }
    .success-icon { width:66px;height:66px;border-radius:50%;background:rgba(76,175,121,.09);border:1px solid rgba(76,175,121,.28);display:flex;align-items:center;justify-content:center;margin:0 auto 1rem;color:var(--green);animation:popIn .4s cubic-bezier(.34,1.56,.64,1); }
    @keyframes popIn { from{opacity:0;transform:scale(.5)} to{opacity:1;transform:scale(1)} }
    .success-title { font-family:'Cormorant Garamond',serif;font-size:1.5rem;font-weight:600;color:var(--gold-light);margin-bottom:.45rem; }
    .success-msg { color:var(--txt-mid);font-size:.86rem;line-height:1.65;margin-bottom:1.4rem; }

    .btn-back {
      display:block;text-align:center;text-decoration:none;
      padding:.82rem;border:1px solid var(--bdr);border-radius:10px;
      color:var(--txt-mid);font-family:'DM Sans',sans-serif;font-size:.87rem;
      transition:border-color var(--t),color var(--t),background var(--t);
      margin-top:1rem;
    }
    .btn-back:hover { border-color:var(--gold-dim);color:var(--gold-light);background:var(--bg); }

    .hidden { display:none !important; }

    @media(max-width:500px){
      .card{padding:2rem 1.3rem;}
      .card-title{font-size:1.5rem;}
    }
  </style>
</head>
<body>

<div class="bg">
  <div class="bg-orb bg-orb-1"></div>
  <div class="bg-orb bg-orb-2"></div>
  <div class="bg-grid"></div>
</div>

<div class="wrap">
  <div class="card">

    <div class="hd">
      <!-- Logo path: same relative location as Maininterface.html uses -->
      <img src="Login Media/school no bg.png" alt="SJC" class="logo"
           onerror="this.style.display='none'" />
      <h1 class="card-title" id="cardTitle">Set New Password</h1>
      <p class="card-sub" id="cardSub">Choose a strong, secure password for your account.</p>
    </div>

    <!-- Invalid / expired token panel -->
    <div class="invalid-panel hidden" id="invalidPanel">
      <div class="invalid-icon">
        <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/>
          <line x1="12" y1="16" x2="12.01" y2="16"/>
        </svg>
      </div>
      <p class="invalid-msg" id="invalidMsg"></p>
      <a href="Maininterface.html" class="btn-back">← Back to Login</a>
    </div>

    <!-- Password form -->
    <div id="formSection">
      <div class="ebox" id="ebox"></div>

      <!-- New Password -->
      <div class="fg">
        <label class="fl" for="newPw">New Password</label>
        <div class="iw">
          <span class="ic">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
            </svg>
          </span>
          <input type="password" id="newPw" class="fi" placeholder="Enter new password" autocomplete="new-password" />
          <button type="button" class="toggle-eye" data-target="newPw" aria-label="Show/hide password">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>
            </svg>
          </button>
        </div>
        <span class="ferr" id="newPwErr"></span>
      </div>

      <!-- Strength meter -->
      <div class="srow">
        <div class="strk"><div class="sfill" id="sfill"></div></div>
        <span class="slbl" id="slbl">–</span>
      </div>

      <!-- Guidelines -->
      <div class="gl">
        <p class="gl-title">Strong password checklist</p>
        <ul class="rules">
          <li class="rule" id="r-len"><span class="rdot">✕</span> At least 8 characters</li>
          <li class="rule" id="r-up"> <span class="rdot">✕</span> One uppercase letter (A–Z)</li>
          <li class="rule" id="r-lo"> <span class="rdot">✕</span> One lowercase letter (a–z)</li>
          <li class="rule" id="r-num"><span class="rdot">✕</span> One number (0–9)</li>
          <li class="rule" id="r-sp"> <span class="rdot">✕</span> One special character (!@#$%…)</li>
        </ul>
      </div>

      <!-- Confirm Password -->
      <div class="fg">
        <label class="fl" for="confirmPw">Confirm New Password</label>
        <div class="iw">
          <span class="ic">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
            </svg>
          </span>
          <input type="password" id="confirmPw" class="fi" placeholder="Repeat new password" autocomplete="new-password" />
          <button type="button" class="toggle-eye" data-target="confirmPw" aria-label="Show/hide password">
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
              <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>
            </svg>
          </button>
        </div>
        <span class="ferr" id="confirmPwErr"></span>
      </div>

      <button type="button" class="btn" id="submitBtn">
        <span id="btnLbl">Reset Password</span>
        <span class="spinner" id="spinner"></span>
      </button>
    </div>

    <!-- Success panel -->
    <div class="success-panel hidden" id="successPanel">
      <div class="success-icon">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
          <polyline points="22 4 12 14.01 9 11.01"/>
        </svg>
      </div>
      <p class="success-title">Password Updated!</p>
      <p class="success-msg">Your password has been reset successfully. You can now sign in with your new credentials.</p>
      <a href="Maininterface.html" class="btn-back" style="border-color:rgba(76,175,121,.3);color:var(--green);">
        Back to Login →
      </a>
    </div>

  </div>
</div>

<!-- Pass PHP token validation result to JS -->
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
  const p = document.getElementById('invalidPanel');
  p.classList.remove('hidden');
  document.getElementById('invalidMsg').textContent = TOKEN_ERROR;
}

// ── Toggle password visibility ────────────────────────────
document.querySelectorAll('.toggle-eye').forEach(btn => {
  btn.addEventListener('click', () => {
    const inp = document.getElementById(btn.dataset.target);
    inp.type = inp.type === 'password' ? 'text' : 'password';
    btn.style.opacity = inp.type === 'text' ? '0.45' : '1';
  });
});

// ── Password strength ─────────────────────────────────────
const pwRules = [
  { id: 'r-len', re: /.{8,}/        },
  { id: 'r-up',  re: /[A-Z]/         },
  { id: 'r-lo',  re: /[a-z]/         },
  { id: 'r-num', re: /[0-9]/         },
  { id: 'r-sp',  re: /[^A-Za-z0-9]/ },
];
const sLabels  = ['–','Weak','Fair','Good','Strong'];
const sCls     = ['','s1','s2','s3','s4'];

function checkStrength(pw) {
  let score = 0;
  pwRules.forEach(r => {
    const ok = r.re.test(pw);
    const el = document.getElementById(r.id);
    el.classList.toggle('pass', ok);
    el.querySelector('.rdot').textContent = ok ? '✓' : '✕';
    if (ok) score++;
  });
  const fill = document.getElementById('sfill');
  const lbl  = document.getElementById('slbl');
  const s    = pw.length ? Math.min(score, 4) : 0;
  fill.className = 'sfill ' + (pw.length ? sCls[score] || 's4' : '');
  lbl.textContent = sLabels[s];
  lbl.className   = 'slbl ' + (pw.length ? sCls[s] : '');
  return score;
}

document.getElementById('newPw').addEventListener('input', () => {
  checkStrength(document.getElementById('newPw').value);
  document.getElementById('newPw').classList.remove('err');
  document.getElementById('newPwErr').textContent = '';
});
document.getElementById('confirmPw').addEventListener('input', () => {
  document.getElementById('confirmPw').classList.remove('err');
  document.getElementById('confirmPwErr').textContent = '';
});

// ── Submit ────────────────────────────────────────────────
document.getElementById('submitBtn').addEventListener('click', async () => {
  const pw   = document.getElementById('newPw').value;
  const cpw  = document.getElementById('confirmPw').value;
  const ebox = document.getElementById('ebox');

  // Clear all errors
  ebox.style.display = 'none';
  ['newPw','confirmPw'].forEach(id => document.getElementById(id).classList.remove('err'));
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

  // Loading
  const btn     = document.getElementById('submitBtn');
  const lbl     = document.getElementById('btnLbl');
  const spinner = document.getElementById('spinner');
  btn.disabled       = true;
  lbl.textContent    = 'Resetting…';
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
      ebox.textContent   = data.message || 'Could not reset password. Please try again.';
      ebox.style.display = 'block';
      btn.disabled = false;
      lbl.textContent = 'Reset Password';
      spinner.style.display = 'none';
    }
  } catch {
    ebox.textContent   = 'Network error. Please check your connection and try again.';
    ebox.style.display = 'block';
    btn.disabled = false;
    lbl.textContent = 'Reset Password';
    spinner.style.display = 'none';
  }
});
</script>

</body>
</html>