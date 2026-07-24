<?php
/**
 * SJC Portal — login.php
 * ─────────────────────────────────────────────────────────
 * Handles credential verification, trusted-device check, and OTP dispatch.
 *
 * Flow:
 *   1. Validate POST fields (email, password)
 *   2. Look up user in logindb.users — verify password + active
 *   3. ★ NEW: Check if this browser has a valid trusted_device cookie
 *        → If trusted and not expired → skip OTP, log straight in
 *        → If not trusted / expired   → send OTP (same as before)
 *   4. OTP path: generate code → email → return otp_required=true
 *
 * The JS sends one extra hidden field with every login POST:
 *   device_fp — a lightweight browser fingerprint string
 *   (User-Agent + Accept-Language + platform, joined client-side)
 * We combine it with the cookie token on the server for the lookup.
 */

session_start();
header('Content-Type: application/json');

require_once 'logindb.php'; // $conn (PDO)

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as MailException;

require_once 'PHPMailer-7.0.2/src/Exception.php';
require_once 'PHPMailer-7.0.2/src/PHPMailer.php';
require_once 'PHPMailer-7.0.2/src/SMTP.php';

// ── Helper: JSON exit ────────────────────────────────────
function respond(array $payload): void {
    echo json_encode($payload);
    exit;
}

// ── Guard: POST only ─────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(['success' => false, 'message' => 'Invalid request method.']);
}

// ── 1. Read & sanitise inputs ────────────────────────────
$email      = trim($_POST['email']       ?? '');
$password   = trim($_POST['password']    ?? '');
$rememberMe = !empty($_POST['remember_me']);

if ($email === '' || $password === '') {
    respond(['success' => false, 'message' => 'Please fill in all fields.']);
}

// ── 2. Look up user ───────────────────────────────────────
$stmt = $conn->prepare(
    "SELECT u.id, u.email, u.password_hash, u.role, u.personal_email, u.is_active,
            r.redirect_url
     FROM   users u
     LEFT   JOIN role_redirects r ON r.role = u.role
     WHERE  u.email = ?
     LIMIT  1"
);
$stmt->execute([$email]);
$user = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$user || !password_verify($password, $user['password_hash'])) {
    respond(['success' => false, 'message' => 'Invalid email or password.']);
}

if (!(bool)$user['is_active']) {
    respond(['success' => false, 'message' => 'Your account has been deactivated. Please contact the administrator.']);
}

$role      = strtolower(trim($user['role']));
$userId    = (int)$user['id'];
$redirect  = $user['redirect_url'] ?? '';

// ── 3. ★ Trusted-device check ────────────────────────────
// The cookie `trusted_device` holds a raw 64-char hex token.
// We SHA-256 it and look it up in trusted_devices.
// If found, not expired, and belongs to this user → skip OTP.
if (!empty($_COOKIE['trusted_device'])) {
    $rawToken  = $_COOKIE['trusted_device'];
    $tokenHash = hash('sha256', $rawToken);

    try {
        $tdStmt = $conn->prepare(
            "SELECT id, expires_at
             FROM   trusted_devices
             WHERE  token_hash = ?
               AND  user_id    = ?
               AND  expires_at > NOW()
             LIMIT  1"
        );
        $tdStmt->execute([$tokenHash, $userId]);
        $trusted = $tdStmt->fetch(PDO::FETCH_ASSOC);

        if ($trusted) {
            // ✅ Trusted device — touch last_seen and log straight in
            $conn->prepare(
                "UPDATE trusted_devices SET last_seen_at = NOW() WHERE id = ?"
            )->execute([$trusted['id']]);

            // Build session exactly as loginverify.php would
            $sessionToken = bin2hex(random_bytes(32));
            $conn->prepare(
                "UPDATE users SET session_token = ?, session_token_created_at = NOW() WHERE id = ?"
            )->execute([$sessionToken, $userId]);

            $_SESSION['user_id']       = $userId;
            $_SESSION['user_email']    = $user['email'];
            $_SESSION['user_role']     = $role;
            $_SESSION['role']          = $role;
            $_SESSION['logged_in']     = true;
            $_SESSION['session_token'] = $sessionToken;

            // Resolve role-specific IDs (same logic as loginverify.php)
            resolveRoleSession($role, $userId, $conn);

            respond([
                'success'        => true,
                'otp_required'   => false,
                'trusted_device' => true,
                'redirect'       => $redirect,
                'message'        => 'Recognised device. Logging you in.',
            ]);
        }
    } catch (PDOException $e) {
        error_log('[login] trusted_device check: ' . $e->getMessage());
        // Non-fatal — fall through to OTP
    }
}

// ── 4. No trusted device — send OTP ──────────────────────
$personalEmail = trim($user['personal_email'] ?? '');
$otpTarget     = filter_var($personalEmail, FILTER_VALIDATE_EMAIL)
                    ? $personalEmail
                    : $user['email'];

$otp       = str_pad(random_int(0, 999999), 6, '0', STR_PAD_LEFT);
$otpHash   = password_hash($otp, PASSWORD_BCRYPT);
$otpExpiry = time() + 300; // 5 minutes

$_SESSION['otp_hash']        = $otpHash;
$_SESSION['otp_expiry']      = $otpExpiry;
$_SESSION['otp_user_id']     = $userId;
$_SESSION['otp_role']        = $role;
$_SESSION['otp_email']       = $user['email'];
$_SESSION['otp_redirect']    = $redirect;
$_SESSION['otp_remember_me'] = $rememberMe;

$sent = sendOtpEmail($otpTarget, $otp, $role);

if (!$sent['success']) {
    foreach (['otp_hash','otp_expiry','otp_user_id','otp_role','otp_email','otp_redirect','otp_remember_me'] as $k) {
        unset($_SESSION[$k]);
    }
    respond(['success' => false, 'message' => 'Could not send verification code. ' . $sent['error']]);
}

respond([
    'success'      => true,
    'otp_required' => true,
    'message'      => 'A verification code has been sent to your registered email address.',
]);


// ═════════════════════════════════════════════════════════
//  HELPER — Role session resolution (mirrors loginverify.php)
//  Called on trusted-device fast-login so the session is
//  identical to a normal OTP login.
// ═════════════════════════════════════════════════════════
function resolveRoleSession(string $role, int $userId, PDO $loginConn): void
{
    if ($role === 'student') {
        try {
            $sc = new PDO("mysql:host=localhost;dbname=school_system;charset=utf8mb4","root","");
            $sc->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $s = $sc->prepare("SELECT id, lrn, enrollment_type, registration_status FROM students WHERE user_id = ? LIMIT 1");
            $s->execute([$userId]);
            $row = $s->fetch(PDO::FETCH_ASSOC);
            if ($row) {
                $_SESSION['student_id']          = (int)$row['id'];
                $_SESSION['lrn']                 = $row['lrn'] ?: null;
                $_SESSION['enrollment_status']   = $row['enrollment_type'];
                $_SESSION['registration_status'] = $row['registration_status'];
            }
        } catch (PDOException $e) { error_log('[login] resolveStudent: '.$e->getMessage()); }
    }

    if ($role === 'admin') {
        try {
            $sc = new PDO("mysql:host=localhost;dbname=school_system;charset=utf8mb4","root","");
            $sc->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $uStmt = $loginConn->prepare("SELECT school_email, personal_email FROM users WHERE id = ? LIMIT 1");
            $uStmt->execute([$userId]);
            $ud = $uStmt->fetch(PDO::FETCH_ASSOC);
            $sc->prepare("INSERT INTO admins (user_id, school_email, personal_email, role) VALUES (?,?,?,'admin')
                          ON DUPLICATE KEY UPDATE school_email=VALUES(school_email),personal_email=VALUES(personal_email),role='admin'")
               ->execute([$userId, $ud['school_email'] ?? null, $ud['personal_email'] ?? null]);
            $r = $sc->prepare("SELECT id FROM admins WHERE user_id = ? LIMIT 1");
            $r->execute([$userId]);
            $ar = $r->fetch(PDO::FETCH_ASSOC);
            if ($ar) $_SESSION['admin_id'] = (int)$ar['id'];
        } catch (PDOException $e) { error_log('[login] resolveAdmin: '.$e->getMessage()); }
    }

    if ($role === 'teacher') {
        try {
            $sc = new PDO("mysql:host=localhost;dbname=school_registrar;charset=utf8mb4","root","");
            $sc->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $s = $sc->prepare("SELECT id FROM teachers WHERE logindb_user_id = ? LIMIT 1");
            $s->execute([$userId]);
            $r = $s->fetch(PDO::FETCH_ASSOC);
            $_SESSION['teacher_id'] = $r ? (int)$r['id'] : $userId;
        } catch (PDOException $e) { $_SESSION['teacher_id'] = $userId; }
    }

    if ($role === 'coordinator') {
        try {
            $sc = new PDO("mysql:host=localhost;dbname=school_system;charset=utf8mb4","root","");
            $sc->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $s = $sc->prepare("SELECT id FROM coordinators WHERE user_id = ? AND is_active = 1 LIMIT 1");
            $s->execute([$userId]);
            $r = $s->fetch(PDO::FETCH_ASSOC);
            if ($r) $_SESSION['coordinator_id'] = (int)$r['id'];
        } catch (PDOException $e) { error_log('[login] resolveCoordinator: '.$e->getMessage()); }
    }

    if ($role === 'cashier') {
        try {
            $sc = new PDO("mysql:host=localhost;dbname=school_system;charset=utf8mb4","root","");
            $sc->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $s = $sc->prepare("SELECT id FROM cashiers WHERE user_id = ? LIMIT 1");
            $s->execute([$userId]);
            $r = $s->fetch(PDO::FETCH_ASSOC);
            if ($r) $_SESSION['cashier_id'] = (int)$r['id'];
        } catch (PDOException $e) { error_log('[login] resolveCashier: '.$e->getMessage()); }
    }
}


// ═════════════════════════════════════════════════════════
//  FUNCTION — Send OTP via PHPMailer (unchanged from original)
// ═════════════════════════════════════════════════════════
function sendOtpEmail(string $toEmail, string $otp, string $role): array {
    $mail = new PHPMailer(true);

    try {
        $mail->isSMTP();
        $mail->Host       = getenv('MAIL_HOST')     ?: 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = getenv('MAIL_USERNAME')  ?: 'columbina234@gmail.com';
        $mail->Password   = getenv('MAIL_PASSWORD')  ?: 'pzvtbdpxrrofpptv';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = (int)(getenv('MAIL_PORT') ?: 587);

        $mail->setFrom(
            getenv('MAIL_FROM_ADDRESS') ?: 'columbina234@gmail.com',
            getenv('MAIL_FROM_NAME')    ?: 'Saint Joseph College'
        );
        $mail->addAddress($toEmail);

        $logoSrc   = 'https://i.imgur.com/kR21xJw.png';
        $roleLabel = ucfirst($role);
        $year      = date('Y');

        $mail->CharSet  = 'UTF-8';
        $mail->isHTML(true);
        $mail->Subject = '[SJC Portal] Your Verification Code';
        $mail->Body    = buildOtpEmailHtml($otp, $roleLabel, $year, $logoSrc);
        $mail->AltBody = "Your SJC Portal login verification code is: {$otp}\nIt expires in 5 minutes. Do not share this code with anyone.";

        $mail->send();
        return ['success' => true, 'error' => ''];

    } catch (MailException $e) {
        return ['success' => false, 'error' => $mail->ErrorInfo];
    }
}

function buildOtpEmailHtml(string $otp, string $roleLabel, string $year, string $logoSrc): string {
    $digits      = str_split($otp);
    $digitBoxes  = '';
    foreach ($digits as $digit) {
        $digitBoxes .= <<<TD
            <td style="padding:0 5px;">
              <span style="display:inline-block;width:44px;height:54px;line-height:54px;
                           text-align:center;font-family:'Courier New',monospace;
                           font-size:28px;font-weight:700;color:#1a0000;
                           background:#fff;border:2px solid #c9a84c;border-radius:8px;
                           letter-spacing:0;">$digit</span>
            </td>
        TD;
    }

    return <<<HTML
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f0ece6;font-family:Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background:#f0ece6;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
               style="background:#ffffff;border-radius:12px;overflow:hidden;
                      box-shadow:0 4px 24px rgba(26,0,0,0.10);">

          <!-- HEADER -->
          <tr>
            <td style="background:#1a0000;padding:28px 36px 22px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td valign="middle">
                    <img src="{$logoSrc}" alt="SJC Logo" width="48" height="48"
                         style="display:inline-block;vertical-align:middle;border-radius:50%;">
                    <span style="display:inline-block;vertical-align:middle;margin-left:12px;
                                 font-family:Georgia,'Times New Roman',serif;font-size:18px;
                                 color:#c9a84c;letter-spacing:1px;">
                      Saint Joseph College
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- SUB-HEADER -->
          <tr>
            <td style="padding:14px 36px 12px;background:#fdf9f2;
                       border-bottom:1px solid #ede8de;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td valign="middle">
                    <span style="display:inline-block;background:#1a0000;color:#c9a84c;
                                 font-family:Arial,sans-serif;font-size:10px;font-weight:700;
                                 letter-spacing:2px;padding:4px 10px;border-radius:3px;
                                 text-transform:uppercase;">
                      {$roleLabel} Portal
                    </span>
                  </td>
                  <td valign="middle" align="right">
                    <span style="font-family:Arial,sans-serif;font-size:11px;
                                 color:#9a8a78;letter-spacing:0.5px;">
                      Verification Code
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- BODY -->
          <tr>
            <td style="padding:40px 36px 36px;">
              <p style="margin:0 0 6px;font-family:Georgia,'Times New Roman',serif;
                         font-size:22px;color:#1a0000;font-weight:normal;line-height:1.3;">
                Your One-Time Password
              </p>
              <p style="margin:0 0 28px;font-family:Arial,sans-serif;font-size:13px;
                         color:#6b5f55;line-height:1.7;">
                A login attempt was made on the <strong style="color:#1a0000;">SJC Student&nbsp;&amp;&nbsp;Faculty Portal</strong>.
                Use the code below to complete your sign-in. This code is valid for
                <strong style="color:#1a0000;">5&nbsp;minutes</strong>.
                Once verified, <strong style="color:#1a0000;">opt in below to trust this device for 14 days</strong>
                and you will not be asked for a code again on this browser.
              </p>

              <!-- OTP digit boxes -->
              <table role="presentation" cellpadding="0" cellspacing="0" border="0"
                     style="margin:0 auto 28px;">
                <tr>{$digitBoxes}</tr>
              </table>

              <!-- Divider -->
              <div style="height:1px;background:linear-gradient(90deg,transparent,#d6c99a,transparent);
                           margin:0 0 28px;"></div>

              <!-- Steps -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#fdf9f2;border:1px solid #e8dfc8;border-radius:8px;margin-bottom:28px;">
                <tr>
                  <td style="padding:20px 24px;">
                    <p style="margin:0 0 12px;font-family:Arial,sans-serif;font-size:12px;
                               font-weight:700;color:#1a0000;letter-spacing:1px;text-transform:uppercase;">
                      How to use this code
                    </p>
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td width="22" valign="top" style="padding-top:1px;">
                          <span style="display:inline-block;width:18px;height:18px;line-height:18px;
                                       text-align:center;background:#1a0000;color:#c9a84c;
                                       font-family:Arial,sans-serif;font-size:10px;font-weight:700;border-radius:50%;">1</span>
                        </td>
                        <td style="padding-left:8px;font-family:Arial,sans-serif;font-size:12px;color:#5a4e46;line-height:1.6;">
                          Return to the SJC Portal login page.
                        </td>
                      </tr>
                      <tr><td colspan="2" style="padding:4px 0;"></td></tr>
                      <tr>
                        <td width="22" valign="top" style="padding-top:1px;">
                          <span style="display:inline-block;width:18px;height:18px;line-height:18px;
                                       text-align:center;background:#1a0000;color:#c9a84c;
                                       font-family:Arial,sans-serif;font-size:10px;font-weight:700;border-radius:50%;">2</span>
                        </td>
                        <td style="padding-left:8px;font-family:Arial,sans-serif;font-size:12px;color:#5a4e46;line-height:1.6;">
                          Enter the 6-digit code exactly as shown above.
                        </td>
                      </tr>
                      <tr><td colspan="2" style="padding:4px 0;"></td></tr>
                      <tr>
                        <td width="22" valign="top" style="padding-top:1px;">
                          <span style="display:inline-block;width:18px;height:18px;line-height:18px;
                                       text-align:center;background:#1a0000;color:#c9a84c;
                                       font-family:Arial,sans-serif;font-size:10px;font-weight:700;border-radius:50%;">3</span>
                        </td>
                        <td style="padding-left:8px;font-family:Arial,sans-serif;font-size:12px;color:#5a4e46;line-height:1.6;">
                          Click <em>Verify</em> — if you check "Trust this device", it will be remembered for 14 days.
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Security warning -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#fff5f5;border:1px solid #f0d0d0;border-left:4px solid #a81c1c;border-radius:6px;">
                <tr>
                  <td style="padding:16px 20px;">
                    <p style="margin:0;font-family:Arial,sans-serif;font-size:12px;color:#7a2020;line-height:1.7;">
                      <strong>&#9888; Security Notice &mdash;</strong>
                      Never share this code with anyone, including SJC staff.
                      The school will <em>never</em> ask for your OTP by phone, chat, or email.
                      If you did not initiate this login, you can safely ignore this message
                      &mdash; your account remains protected.
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- FOOTER -->
          <tr>
            <td style="background:#1a0000;padding:22px 36px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td>
                    <p style="margin:0 0 4px;font-family:Georgia,'Times New Roman',serif;
                               font-size:12px;color:#c9a84c;letter-spacing:1px;">
                      Saint Joseph College of Novaliches, Inc.
                    </p>
                    <p style="margin:0;font-family:Arial,sans-serif;font-size:10px;
                               color:rgba(255,255,255,0.35);line-height:1.6;">
                      This is an automated message &mdash; please do not reply to this email.
                      &copy; {$year} All rights reserved.
                    </p>
                  </td>
                  <td align="right" valign="middle">
                    <span style="display:inline-block;width:36px;height:36px;line-height:36px;
                                 text-align:center;background:rgba(201,168,76,0.12);
                                 border:1px solid rgba(201,168,76,0.25);border-radius:50%;
                                 font-family:Georgia,serif;font-size:15px;color:#c9a84c;">
                      &#9670;
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
HTML;
}
?>