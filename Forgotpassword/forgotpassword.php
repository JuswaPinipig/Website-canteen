<?php
/**
 * forgotpassword.php
 * Actions: check_email | send_otp | verify_otp
 * Uses PHPMailer 7.0.2
 */

declare(strict_types=1);

session_start();
header('Content-Type: application/json');

// ── Database config ───────────────────────────────────────────
define('DB_HOST', '127.0.0.1');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_NAME', 'school_system');

// ── PHPMailer autoload ────────────────────────────────────────
// Adjust path if needed — assumes PHPMailer-7.0.2 sits in the same directory
require_once __DIR__ . '/../PHPMailer-7.0.2/src/Exception.php';
require_once __DIR__ . '/../PHPMailer-7.0.2/src/PHPMailer.php';
require_once __DIR__ . '/../PHPMailer-7.0.2/src/SMTP.php';

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

// ── SMTP config — fill in your credentials ────────────────────
define('SMTP_HOST',     'smtp.gmail.com');
define('SMTP_PORT',     587);
define('SMTP_USERNAME', 'your_school_email@gmail.com'); // TODO: fill
define('SMTP_PASSWORD', 'your_app_password');           // TODO: fill
define('SMTP_FROM',     'your_school_email@gmail.com');
define('SMTP_FROM_NAME','SJC School System');

// ── School logo path (absolute on server) ─────────────────────
define('LOGO_PATH', __DIR__ . '/Forgotpassword media/school no bg.png');
define('LOGO_CID',  'school_logo');

// ── OTP settings ──────────────────────────────────────────────
define('OTP_EXPIRY_SECONDS', 600); // 10 minutes

// ═══════════════════════════════════════════════════════════════
function json_out(bool $success, string $message, array $extra = []): void
{
    echo json_encode(array_merge(['success' => $success, 'message' => $message], $extra));
    exit;
}

function db(): mysqli
{
    static $conn = null;
    if ($conn === null) {
        $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
        $conn->set_charset('utf8mb4');
        if ($conn->connect_error) {
            json_out(false, 'Database connection failed.');
        }
    }
    return $conn;
}

// ── Validate input ────────────────────────────────────────────
$action = trim($_POST['action'] ?? '');
$email  = trim($_POST['email']  ?? '');

if (empty($action)) {
    json_out(false, 'No action specified.');
}

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    json_out(false, 'Invalid email address.');
}

// ═══════════════════════════════════════════════════════════════
//  ACTION: check_email
// ═══════════════════════════════════════════════════════════════
if ($action === 'check_email') {
    $db   = db();
    $stmt = $db->prepare(
        "SELECT id, role, personal_email, school_email, email
         FROM users
         WHERE (email = ? OR school_email = ? OR personal_email = ?)
           AND is_active = 1
         LIMIT 1"
    );
    $stmt->bind_param('sss', $email, $email, $email);
    $stmt->execute();
    $result = $stmt->get_result();

    if ($result->num_rows === 0) {
        json_out(false, 'No active account found with that email address.');
    }

    $user = $result->fetch_assoc();

    // Store email in session for later steps
    $_SESSION['fp_email']   = $email;
    $_SESSION['fp_user_id'] = $user['id'];
    $_SESSION['fp_role']    = $user['role'];

    json_out(true, 'Email found.');
}

// ═══════════════════════════════════════════════════════════════
//  ACTION: send_otp
// ═══════════════════════════════════════════════════════════════
if ($action === 'send_otp') {

    // Guard: must have passed check_email first
    if (empty($_SESSION['fp_email']) || $_SESSION['fp_email'] !== $email) {
        json_out(false, 'Session expired. Please start over.');
    }

    // Generate a 6-digit OTP
    $otp     = sprintf('%06d', random_int(0, 999999));
    $expires = time() + OTP_EXPIRY_SECONDS;

    // Store in session (no DB table needed for OTP)
    $_SESSION['fp_otp']         = password_hash($otp, PASSWORD_BCRYPT);
    $_SESSION['fp_otp_expires'] = $expires;

    // ── Build HTML email ──────────────────────────────────────
    $role         = ucfirst(str_replace('_', ' ', $_SESSION['fp_role'] ?? ''));
    $expiryMinutes = OTP_EXPIRY_SECONDS / 60;

    $htmlBody = <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1.0"/>
<title>Password Reset OTP</title>
</head>
<body style="margin:0;padding:0;background:#0D1B2A;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#0D1B2A;padding:40px 0;">
  <tr><td align="center">
    <table width="520" cellpadding="0" cellspacing="0"
           style="background:linear-gradient(160deg,#112236,#0D1B2A);
                  border:1px solid rgba(201,168,76,0.22);
                  border-radius:16px;overflow:hidden;
                  box-shadow:0 20px 60px rgba(0,0,0,0.6);">

      <!-- Top accent bar -->
      <tr><td style="height:3px;background:linear-gradient(90deg,transparent,#C9A84C,transparent);"></td></tr>

      <!-- Logo -->
      <tr><td align="center" style="padding:36px 40px 24px;">
        <img src="cid:school_logo" alt="SJC School System"
             style="height:80px;width:auto;display:block;margin:0 auto;"
             onerror="this.style.display='none'"/>
      </td></tr>

      <!-- Heading -->
      <tr><td align="center" style="padding:0 40px 8px;">
        <h1 style="font-family:Georgia,serif;font-size:26px;font-weight:600;
                   color:#E2C97E;letter-spacing:0.02em;margin:0;">
          Password Reset Request
        </h1>
      </td></tr>

      <!-- Subtitle -->
      <tr><td align="center" style="padding:0 40px 28px;">
        <p style="color:#9EA8B4;font-size:14px;line-height:1.6;margin:8px 0 0;">
          Hello, <strong style="color:#E2C97E;">{$role}</strong>. Use the verification code below
          to complete your password reset. This code expires in <strong style="color:#C9A84C;">{$expiryMinutes} minutes</strong>.
        </p>
      </td></tr>

      <!-- OTP box -->
      <tr><td align="center" style="padding:0 40px 32px;">
        <div style="display:inline-block;
                    background:rgba(201,168,76,0.08);
                    border:1px solid rgba(201,168,76,0.35);
                    border-radius:12px;
                    padding:22px 48px;">
          <span style="font-family:Georgia,serif;font-size:44px;
                       font-weight:700;letter-spacing:14px;
                       color:#E2C97E;">{$otp}</span>
        </div>
      </td></tr>

      <!-- Warning -->
      <tr><td style="padding:0 40px 28px;">
        <p style="color:#5c6978;font-size:12px;line-height:1.6;
                  border-top:1px solid rgba(255,255,255,0.06);
                  padding-top:20px;margin:0;">
          If you did not request a password reset, please ignore this email.
          Do not share this code with anyone — SJC staff will never ask for it.
        </p>
      </td></tr>

      <!-- Footer -->
      <tr><td align="center"
              style="background:rgba(0,0,0,0.25);
                     padding:16px 40px;
                     border-top:1px solid rgba(201,168,76,0.1);">
        <p style="color:#3d4d5c;font-size:11px;margin:0;">
          © {$year} SJC School System &nbsp;·&nbsp; This is an automated message, please do not reply.
        </p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body>
</html>
HTML;

    // Fill in current year
    $year = date('Y');
    $htmlBody = str_replace('{$year}', $year, $htmlBody);

    // ── Send via PHPMailer ────────────────────────────────────
    $mail = new PHPMailer(true);
    try {
        $mail->isSMTP();
        $mail->Host       = SMTP_HOST;
        $mail->SMTPAuth   = true;
        $mail->Username   = SMTP_USERNAME;
        $mail->Password   = SMTP_PASSWORD;
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = SMTP_PORT;

        $mail->setFrom(SMTP_FROM, SMTP_FROM_NAME);
        $mail->addAddress($email);
        $mail->isHTML(true);
        $mail->Subject = 'Your SJC Password Reset Code';
        $mail->Body    = $htmlBody;
        $mail->AltBody = "Your SJC password reset OTP is: {$otp}\nThis code expires in {$expiryMinutes} minutes.";

        // Embed logo
        if (file_exists(LOGO_PATH)) {
            $mail->addEmbeddedImage(LOGO_PATH, LOGO_CID, 'school no bg.png');
        }

        $mail->send();
        json_out(true, 'OTP sent to your email.');

    } catch (Exception $e) {
        // Log error server-side without exposing it
        error_log('PHPMailer error: ' . $mail->ErrorInfo);
        json_out(false, 'Failed to send OTP. Please try again later.');
    }
}

// ═══════════════════════════════════════════════════════════════
//  ACTION: verify_otp
// ═══════════════════════════════════════════════════════════════
if ($action === 'verify_otp') {
    $otp          = trim($_POST['otp']          ?? '');
    $new_password = trim($_POST['new_password'] ?? '');

    // Session guard
    if (empty($_SESSION['fp_email']) || $_SESSION['fp_email'] !== $email) {
        json_out(false, 'Session expired. Please start over.');
    }
    if (empty($_SESSION['fp_otp']) || empty($_SESSION['fp_otp_expires'])) {
        json_out(false, 'No OTP found. Please request a new code.');
    }

    // Expiry check
    if (time() > $_SESSION['fp_otp_expires']) {
        unset($_SESSION['fp_otp'], $_SESSION['fp_otp_expires']);
        json_out(false, 'This OTP has expired. Please request a new one.');
    }

    // OTP match
    if (!password_verify($otp, $_SESSION['fp_otp'])) {
        json_out(false, 'Incorrect OTP. Please check your email and try again.');
    }

    // Password strength (server-side mirror of front-end rules)
    if (strlen($new_password) < 8) {
        json_out(false, 'Password must be at least 8 characters.');
    }
    if (!preg_match('/[A-Z]/', $new_password)) {
        json_out(false, 'Password must contain at least one uppercase letter.');
    }
    if (!preg_match('/[a-z]/', $new_password)) {
        json_out(false, 'Password must contain at least one lowercase letter.');
    }
    if (!preg_match('/[0-9]/', $new_password)) {
        json_out(false, 'Password must contain at least one number.');
    }
    if (!preg_match('/[^A-Za-z0-9]/', $new_password)) {
        json_out(false, 'Password must contain at least one special character.');
    }

    // Update password
    $db           = db();
    $userId       = (int) ($_SESSION['fp_user_id'] ?? 0);
    $passwordHash = password_hash($new_password, PASSWORD_BCRYPT);

    $stmt = $db->prepare(
        "UPDATE users SET password_hash = ?, updated_at = NOW() WHERE id = ? AND is_active = 1"
    );
    $stmt->bind_param('si', $passwordHash, $userId);

    if (!$stmt->execute() || $stmt->affected_rows < 1) {
        json_out(false, 'Could not update password. Please try again.');
    }

    // Clear session OTP data
    unset(
        $_SESSION['fp_email'],
        $_SESSION['fp_user_id'],
        $_SESSION['fp_role'],
        $_SESSION['fp_otp'],
        $_SESSION['fp_otp_expires']
    );

    json_out(true, 'Password reset successfully.');
}

// ── Unknown action ────────────────────────────────────────────
json_out(false, 'Unknown action.');