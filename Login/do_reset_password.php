<?php
/**
 * SJC Portal — do_reset_password.php
 * ─────────────────────────────────────────────────────────
 * Location: C:\xampp\htdocs\Login\do_reset_password.php
 *           (same folder as login.php, reset_password.php)
 *
 * Called via AJAX by reset_password.php after the user
 * submits their new password.
 *
 * Security:
 *   · Token was validated on page load by reset_password.php
 *     and stored in $_SESSION['reset_token_hash'] + ['reset_user_id']
 *   · This endpoint re-checks the token is still live in DB
 *   · Password rules are enforced server-side (mirrors front-end)
 *   · Token is deleted immediately after use (single-use only)
 */

session_start();
header('Content-Type: application/json');

require_once 'logindb.php'; // $conn (PDO) — same folder

// ── PHPMailer ─────────────────────────────────────────────
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as MailException;

require_once 'PHPMailer-7.0.2/src/Exception.php';
require_once 'PHPMailer-7.0.2/src/PHPMailer.php';
require_once 'PHPMailer-7.0.2/src/SMTP.php';

function respond(array $payload): void {
    echo json_encode($payload);
    exit;
}

// ── Guard: POST only ──────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(['success' => false, 'message' => 'Invalid request method.']);
}

// ── Guard: session must have reset context ────────────────
if (empty($_SESSION['reset_token_hash']) || empty($_SESSION['reset_user_id'])) {
    respond(['success' => false, 'message' => 'Session expired. Please request a new reset link from the login page.']);
}

$tokenHash = $_SESSION['reset_token_hash'];
$userId    = (int)$_SESSION['reset_user_id'];

// ── 1. Re-validate token in DB (still live, not expired) ──
try {
    $stmt = $conn->prepare(
        "SELECT user_id FROM password_reset_tokens
            WHERE token_hash = ? AND used_at IS NULL
            LIMIT  1"
    );
    $stmt->execute([$tokenHash]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (PDOException $e) {
    error_log('[do_reset_password] Token re-check: ' . $e->getMessage());
    respond(['success' => false, 'message' => 'Database error. Please try again.']);
}

if (!$row || (int)$row['user_id'] !== $userId) {
    respond(['success' => false, 'message' => 'Reset link is invalid or has expired. Please request a new one from the login page.']);
}

// ── 1b. Fetch user email & role for the confirmation email ─
try {
    $userStmt = $conn->prepare(
        "SELECT email, personal_email, role FROM users WHERE id = ? LIMIT 1"
    );
    $userStmt->execute([$userId]);
    $userRow = $userStmt->fetch(PDO::FETCH_ASSOC);
} catch (PDOException $e) {
    error_log('[do_reset_password] User fetch: ' . $e->getMessage());
    $userRow = null;
}

// ── 2. Read & validate new password ───────────────────────
$newPassword = $_POST['new_password'] ?? '';

if ($newPassword === '') {
    respond(['success' => false, 'message' => 'Password cannot be empty.']);
}
if (strlen($newPassword) < 8) {
    respond(['success' => false, 'message' => 'Password must be at least 8 characters.']);
}
if (!preg_match('/[A-Z]/', $newPassword)) {
    respond(['success' => false, 'message' => 'Password must contain at least one uppercase letter.']);
}
if (!preg_match('/[a-z]/', $newPassword)) {
    respond(['success' => false, 'message' => 'Password must contain at least one lowercase letter.']);
}
if (!preg_match('/[0-9]/', $newPassword)) {
    respond(['success' => false, 'message' => 'Password must contain at least one number.']);
}
if (!preg_match('/[^A-Za-z0-9]/', $newPassword)) {
    respond(['success' => false, 'message' => 'Password must contain at least one special character.']);
}

// ── 3. Hash & update password ─────────────────────────────
$passwordHash = password_hash($newPassword, PASSWORD_BCRYPT);

try {
    $upd = $conn->prepare(
        "UPDATE users
         SET    password_hash = ?, updated_at = NOW(), is_first_login = 0
         WHERE  id = ? AND is_active = 1"
    );
    $upd->execute([$passwordHash, $userId]);

    if ($upd->rowCount() < 1) {
        respond(['success' => false, 'message' => 'Could not update password. Account may be inactive.']);
    }
} catch (PDOException $e) {
    error_log('[do_reset_password] Password update: ' . $e->getMessage());
    respond(['success' => false, 'message' => 'Database error. Please try again.']);
}

// ── 4. Invalidate ALL sessions + remember-me tokens ───────
// Changing password generates a brand new session_token in the DB.
// Any device that still has the OLD session_token in its $_SESSION
// will fail the auth.php check on their next page load → auto-logout.
// We also delete all remember-me tokens so persistent cookies stop working.
$newSessionToken = bin2hex(random_bytes(32));

try {
    $conn->prepare(
        "UPDATE users
         SET    session_token = ?, session_token_created_at = NOW()
         WHERE  id = ?"
    )->execute([$newSessionToken, $userId]);
} catch (PDOException $e) {
    error_log('[do_reset_password] session_token rotate: ' . $e->getMessage());
    // Non-fatal — password was already changed; log the error and continue
}

try {
    // Delete all "remember me" tokens for this user across all devices
    $conn->prepare(
        "DELETE FROM remember_me_tokens WHERE user_id = ?"
    )->execute([$userId]);
} catch (PDOException $e) {
    error_log('[do_reset_password] remember_me revoke: ' . $e->getMessage());
    // Non-fatal
}

// ── 4b. Invalidate all trusted-device tokens ──────────────
// After a password reset, every device must re-verify with OTP.
// This covers the security rules:
//   · Password changed / reset → require OTP again
//   · Account recovery         → require OTP again
//   · Admin resets security    → admin can call this same path
try {
    $conn->prepare(
        "DELETE FROM trusted_devices WHERE user_id = ?"
    )->execute([$userId]);
} catch (PDOException $e) {
    error_log('[do_reset_password] trusted_devices revoke: ' . $e->getMessage());
    // Non-fatal
}
try {
    $conn->prepare("UPDATE password_reset_tokens SET used_at = NOW() WHERE token_hash = ?")
        ->execute([$tokenHash]);
} catch (PDOException $e) {
    error_log('[do_reset_password] Token delete: ' . $e->getMessage());
    // Non-fatal — token will expire naturally after 1 hour
}

// ── 5. Send password-changed confirmation email ───────────
if ($userRow) {
    $personal  = trim($userRow['personal_email'] ?? '');
    $sendTo    = filter_var($personal, FILTER_VALIDATE_EMAIL) ? $personal : $userRow['email'];
    $roleLabel = ucfirst(str_replace('_', ' ', $userRow['role'] ?? 'User'));
    $changedAt = date('F j, Y \a\t g:i A'); // e.g. "April 28, 2026 at 3:45 PM"
    $year      = date('Y');
    $logoSrc   = 'https://i.imgur.com/kR21xJw.png';

    $mail = new PHPMailer(true);
    try {
        $mail->isSMTP();
        $mail->Host       = getenv('MAIL_HOST')        ?: 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = getenv('MAIL_USERNAME')    ?: 'columbina234@gmail.com';
        $mail->Password   = getenv('MAIL_PASSWORD')    ?: 'pzvtbdpxrrofpptv';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = (int)(getenv('MAIL_PORT')  ?: 587);

        $mail->setFrom(
            getenv('MAIL_FROM_ADDRESS') ?: 'columbina234@gmail.com',
            getenv('MAIL_FROM_NAME')    ?: 'Saint Joseph College'
        );
        $mail->addAddress($sendTo);

        $mail->CharSet  = 'UTF-8';
        $mail->isHTML(true);
        $mail->Subject  = '[SJC Portal] Your Password Was Changed';
        $mail->Body     = buildPasswordChangedEmail($changedAt, $roleLabel, $year, $logoSrc);
        $mail->AltBody  = "Your SJC Portal password was successfully changed on {$changedAt}.\n\n"
                        . "If you did not make this change, please contact the school administrator immediately "
                        . "at your school's main office so your account can be secured.";

        $mail->send();
    } catch (MailException $e) {
        error_log('[do_reset_password] Confirmation mail: ' . $mail->ErrorInfo);
        // Non-fatal — password was already changed successfully
    }
}

// ── 6. Clear reset session keys ───────────────────────────
unset($_SESSION['reset_token_hash'], $_SESSION['reset_user_id']);

respond(['success' => true, 'message' => 'Password reset successfully.']);


// ═════════════════════════════════════════════════════════
//  EMAIL HTML — Password Changed Confirmation
//  · Matches the maroon/gold design of forgot_password.php
// ═════════════════════════════════════════════════════════
function buildPasswordChangedEmail(string $changedAt, string $roleLabel, string $year, string $logoSrc): string
{
    $logoTag = $logoSrc
        ? '<img src="' . htmlspecialchars($logoSrc) . '" alt="SJC Logo" width="60" height="60"
                 style="display:block;width:60px;height:60px;object-fit:contain;border-radius:50%;
                        background:rgba(255,255,255,0.07);border:1.5px solid rgba(201,168,76,0.35);padding:4px;">'
        : '';

    $safeChangedAt = htmlspecialchars($changedAt, ENT_QUOTES, 'UTF-8');

    return <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>SJC Portal &#8212; Password Changed</title>
</head>
<body style="margin:0;padding:0;background-color:#f0ece6;-webkit-text-size-adjust:100%;mso-line-height-rule:exactly;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background-color:#f0ece6;min-width:100%;">
    <tr><td align="center" style="padding:36px 16px 48px;">

      <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
             style="max-width:560px;width:100%;background:#ffffff;border-radius:14px;
                    overflow:hidden;box-shadow:0 4px 32px rgba(26,0,0,0.13);">

        <!-- HEADER -->
        <tr>
          <td style="background:linear-gradient(160deg,#1a0000 0%,#3d0808 60%,#5c1010 100%);padding:28px 36px 24px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td width="64" valign="middle" style="padding-right:16px;">{$logoTag}</td>
                <td valign="middle">
                  <p style="margin:0 0 2px;font-family:Georgia,'Times New Roman',serif;font-size:17px;
                             font-weight:normal;letter-spacing:2.5px;color:#c9a84c;line-height:1.2;">
                    SAINT JOSEPH COLLEGE</p>
                  <p style="margin:0;font-family:Georgia,'Times New Roman',serif;font-size:11px;
                             font-weight:normal;letter-spacing:1.5px;color:rgba(201,168,76,0.6);line-height:1.2;">
                    OF NOVALICHES, INC.</p>
                  <p style="margin:6px 0 0;font-family:Arial,sans-serif;font-size:10px;letter-spacing:2px;
                             color:rgba(255,255,255,0.35);text-transform:uppercase;line-height:1;">
                    OFFICIAL PORTAL</p>
                </td>
              </tr>
            </table>
            <div style="height:1px;background:linear-gradient(90deg,rgba(201,168,76,0.7),rgba(201,168,76,0.1));
                         margin-top:22px;"></div>
          </td>
        </tr>

        <!-- SUBJECT STRIP -->
        <tr>
          <td style="background:#f9f5ef;padding:14px 36px;border-bottom:1px solid #ede8de;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td valign="middle">
                  <span style="display:inline-block;background:#1a0000;color:#c9a84c;font-family:Arial,sans-serif;
                               font-size:10px;font-weight:700;letter-spacing:2px;padding:4px 10px;
                               border-radius:3px;text-transform:uppercase;">{$roleLabel} Portal</span>
                </td>
                <td valign="middle" align="right">
                  <span style="font-family:Arial,sans-serif;font-size:11px;color:#9a8a78;letter-spacing:0.5px;">
                    Security Notification</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- SUCCESS BADGE -->
        <tr>
          <td align="center" style="padding:32px 36px 0;">
            <div style="display:inline-block;background:#f0faf4;border:1.5px solid #a8d5b5;
                         border-radius:50%;width:64px;height:64px;line-height:64px;text-align:center;
                         font-size:28px;">
              &#10003;
            </div>
          </td>
        </tr>

        <!-- BODY -->
        <tr>
          <td style="padding:20px 36px 36px;">
            <p style="margin:0 0 6px;font-family:Georgia,'Times New Roman',serif;font-size:22px;
                       color:#1a0000;font-weight:normal;line-height:1.3;text-align:center;">
              Password Successfully Changed</p>
            <p style="margin:0 0 28px;font-family:Arial,sans-serif;font-size:13px;color:#6b5f55;
                       line-height:1.7;text-align:center;">
              Your <strong style="color:#1a0000;">SJC Student &amp; Faculty Portal</strong> password
              was updated on:</p>

            <!-- Timestamp box -->
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                   style="background:#f9f5ef;border:1px solid #e8dfc8;border-left:4px solid #c9a84c;
                          border-radius:8px;margin-bottom:28px;">
              <tr>
                <td style="padding:16px 20px;">
                  <p style="margin:0 0 3px;font-family:Arial,sans-serif;font-size:10px;font-weight:700;
                             letter-spacing:1.5px;text-transform:uppercase;color:#7a6129;">
                    Date &amp; Time of Change</p>
                  <p style="margin:0;font-family:Georgia,'Times New Roman',serif;font-size:16px;
                             color:#1a0000;line-height:1.4;">{$safeChangedAt}</p>
                </td>
              </tr>
            </table>

            <p style="margin:0 0 24px;font-family:Arial,sans-serif;font-size:13px;color:#6b5f55;line-height:1.7;">
              If this was you, no further action is needed. You can now log in using your new password.
            </p>

            <!-- Warning box -->
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                   style="background:#fff5f5;border:1px solid #f0d0d0;border-left:4px solid #a81c1c;border-radius:6px;">
              <tr>
                <td style="padding:16px 20px;">
                  <p style="margin:0 0 6px;font-family:Arial,sans-serif;font-size:11px;font-weight:700;
                             letter-spacing:1px;text-transform:uppercase;color:#a81c1c;">
                    &#9888;&nbsp; Wasn't you?</p>
                  <p style="margin:0;font-family:Arial,sans-serif;font-size:12px;color:#7a2020;line-height:1.75;">
                    If you did not make this change, your account may have been accessed without your permission.
                    Please <strong>contact the school administrator immediately</strong> at your school's
                    main office so your account can be secured and your access restored as soon as possible.
                    Do not delay — report it right away.
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
                    Saint Joseph College of Novaliches, Inc.</p>
                  <p style="margin:0;font-family:Arial,sans-serif;font-size:10px;
                             color:rgba(255,255,255,0.35);line-height:1.6;">
                    This is an automated security notification &mdash; please do not reply.
                    &copy; {$year} All rights reserved.</p>
                </td>
                <td align="right" valign="middle">
                  <span style="display:inline-block;width:36px;height:36px;line-height:36px;text-align:center;
                               background:rgba(201,168,76,0.12);border:1px solid rgba(201,168,76,0.25);
                               border-radius:50%;font-family:Georgia,serif;font-size:15px;color:#c9a84c;">
                    &#9670;</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>

      </table>
    </td></tr>
  </table>
</body>
</html>
HTML;
}
?>