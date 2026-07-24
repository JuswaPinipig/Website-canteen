<?php
/**
 * SJC Portal — forgot_password.php
 * ─────────────────────────────────────────────────────────
 * Receives the email from the Forgot Password modal on the
 * login page, generates a secure reset token, stores it in
 * the DB, then sends a branded reset-link email via PHPMailer.
 *
 * Flow (matches login.php architecture):
 *   1. Validate email
 *   2. Look up user in school_system.users
 *   3. Generate secure token → store hash in password_reset_tokens
 *   4. Send branded email with reset link via PHPMailer
 *   5. Always return generic success (prevents user enumeration)
 */

session_start();
header('Content-Type: application/json');

require_once 'logindb.php'; // $conn (PDO) → school_system

// ── PHPMailer ─────────────────────────────────────────────
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as MailException;

require_once '../PHPMailer-7.0.2/src/Exception.php';
require_once '../PHPMailer-7.0.2/src/PHPMailer.php';
require_once '../PHPMailer-7.0.2/src/SMTP.php';

// ── Helper ────────────────────────────────────────────────
function respond(array $payload): void {
    echo json_encode($payload);
    exit;
}

// ── Guard: POST only ──────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(['success' => false, 'message' => 'Invalid request method.']);
}

// ── 1. Read & validate email ──────────────────────────────
$email = trim($_POST['email'] ?? '');

if ($email === '') {
    respond(['success' => false, 'message' => 'Please enter your school email address.']);
}

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    respond(['success' => false, 'message' => 'Please enter a valid email address.']);
}

// ── 2. Look up user ───────────────────────────────────────
// Check school_email, personal_email, and email columns —
// the same columns login.php uses for the OTP target.
try {
    $stmt = $conn->prepare(
        "SELECT id, role, personal_email, email
         FROM   users
         WHERE  (email = ? OR school_email = ? OR personal_email = ?)
           AND  is_active = 1
         LIMIT  1"
    );
    $stmt->execute([$email, $email, $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (PDOException $e) {
    error_log('[forgot_password] DB lookup failed: ' . $e->getMessage());
    respond(['success' => false, 'message' => 'A database error occurred. Please try again.']);
}

// ── 3. Generate token & send email (only if user exists) ──
if ($user) {

    // Determine which address receives the email
    // (mirrors login.php: prefer personal_email if valid)
    $personal   = trim($user['personal_email'] ?? '');
    $sendTo     = filter_var($personal, FILTER_VALIDATE_EMAIL) ? $personal : $user['email'];

    // Secure random token — store the hash, send the raw token
    $rawToken   = bin2hex(random_bytes(32));
    $tokenHash  = hash('sha256', $rawToken);
    $expiresAt  = date('Y-m-d H:i:s', time() + 3600); // 1 hour

    // ── Store token in DB ─────────────────────────────────
    try {
        // Delete any existing un-used tokens for this user
        $del = $conn->prepare("DELETE FROM password_reset_tokens WHERE user_id = ?");
        $del->execute([$user['id']]);

        // Insert new token
        $ins = $conn->prepare(
            "INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
             VALUES (?, ?, ?)"
        );
        $ins->execute([$user['id'], $tokenHash, $expiresAt]);
    } catch (PDOException $e) {
        error_log('[forgot_password] Token store failed: ' . $e->getMessage());
        respond(['success' => false, 'message' => 'Could not create reset token. Please try again.']);
    }

    // ── Build reset URL ───────────────────────────────────
    // Resolves to  http://localhost/Forgotpassword/reset_password.php?token=...
    $baseUrl  = rtrim(
        (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? 'https' : 'http')
        . '://' . $_SERVER['HTTP_HOST']
        . dirname($_SERVER['SCRIPT_NAME']),
        '/'
    );
    $resetUrl = $baseUrl . '/reset_password.php?token=' . urlencode($rawToken);

    // ── Send email ────────────────────────────────────────
    $roleLabel = ucfirst(str_replace('_', ' ', $user['role']));
    $year      = date('Y');
    $logoSrc   = 'https://i.imgur.com/kR21xJw.png'; // same as login.php

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
        $mail->addAddress($sendTo);

        $mail->CharSet  = 'UTF-8';
        $mail->isHTML(true);
        $mail->Subject  = '[SJC Portal] Password Reset Request';
        $mail->Body     = buildResetEmailHtml($resetUrl, $roleLabel, $year, $logoSrc);
        $mail->AltBody  = "Reset your SJC Portal password by visiting:\n{$resetUrl}\n\nThis link expires in 1 hour. If you did not request this, you can safely ignore this email.";

        $mail->send();

    } catch (MailException $e) {
        error_log('[forgot_password] Mail send failed: ' . $mail->ErrorInfo);
        // We still fall through to the generic success response —
        // never reveal to the caller that the email failed (prevents enumeration).
    }
}

// ── 4. Always return generic success ─────────────────────
// Never confirm whether the email exists in the system.
respond([
    'success' => true,
    'message' => 'If that email address is registered with us, a password reset link has been sent. Please check your inbox and spam folder.',
]);


// ═════════════════════════════════════════════════════════
//  BUILD RESET EMAIL HTML
//  Design matches login.php OTP email exactly:
//    · Deep maroon (#1a0000) header
//    · Gold (#c9a84c) accents
//    · School logo top-left
//    · Inline styles only
// ═════════════════════════════════════════════════════════
function buildResetEmailHtml(
    string $resetUrl,
    string $roleLabel,
    string $year,
    string $logoSrc
): string {

    $logoTag = $logoSrc !== ''
        ? '<img src="' . htmlspecialchars($logoSrc) . '"
                 alt="SJC Logo" width="60" height="60"
                 style="display:block;width:60px;height:60px;object-fit:contain;
                        border-radius:50%;background:rgba(255,255,255,0.07);
                        border:1.5px solid rgba(201,168,76,0.35);padding:4px;">'
        : '';

    $safeUrl = htmlspecialchars($resetUrl, ENT_QUOTES, 'UTF-8');

    return <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>SJC Portal &#8212; Password Reset</title>
</head>
<body style="margin:0;padding:0;background-color:#f0ece6;-webkit-text-size-adjust:100%;">

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background-color:#f0ece6;min-width:100%;">
    <tr>
      <td align="center" style="padding:36px 16px 48px;">

        <!-- Email card -->
        <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
               style="max-width:560px;width:100%;background:#ffffff;border-radius:14px;
                      overflow:hidden;box-shadow:0 4px 32px rgba(26,0,0,0.13);">

          <!-- HEADER -->
          <tr>
            <td style="background:linear-gradient(160deg,#1a0000 0%,#3d0808 60%,#5c1010 100%);
                       padding:28px 36px 24px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td width="64" valign="middle" style="padding-right:16px;">
                    {$logoTag}
                  </td>
                  <td valign="middle">
                    <p style="margin:0 0 2px;font-family:Georgia,'Times New Roman',serif;
                               font-size:17px;font-weight:normal;letter-spacing:2.5px;
                               color:#c9a84c;line-height:1.2;">
                      SAINT JOSEPH COLLEGE
                    </p>
                    <p style="margin:0;font-family:Georgia,'Times New Roman',serif;
                               font-size:11px;font-weight:normal;letter-spacing:1.5px;
                               color:rgba(201,168,76,0.6);line-height:1.2;">
                      OF NOVALICHES, INC.
                    </p>
                    <p style="margin:6px 0 0;font-family:Arial,sans-serif;font-size:10px;
                               letter-spacing:2px;color:rgba(255,255,255,0.35);
                               text-transform:uppercase;line-height:1;">
                      OFFICIAL PORTAL
                    </p>
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
                      Password Reset
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
                Reset Your Password
              </p>
              <p style="margin:0 0 28px;font-family:Arial,sans-serif;font-size:13px;
                         color:#6b5f55;line-height:1.7;">
                We received a request to reset the password for your
                <strong style="color:#1a0000;">SJC Student &amp; Faculty Portal</strong> account.
                Click the button below to choose a new password.
                This link is valid for <strong style="color:#1a0000;">1 hour</strong>.
              </p>

              <!-- CTA Button -->
              <table role="presentation" cellpadding="0" cellspacing="0" border="0"
                     style="margin:0 auto 32px;">
                <tr>
                  <td style="border-radius:8px;background:#1a0000;">
                    <a href="{$safeUrl}"
                       style="display:inline-block;padding:16px 40px;
                              font-family:Arial,sans-serif;font-size:14px;
                              font-weight:700;letter-spacing:1px;
                              color:#c9a84c;text-decoration:none;
                              border-radius:8px;
                              border:1.5px solid rgba(201,168,76,0.4);">
                      Reset My Password &rarr;
                    </a>
                  </td>
                </tr>
              </table>

              <!-- Fallback URL -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#fdf9f2;border:1px solid #e8dfc8;border-radius:8px;
                            margin-bottom:28px;">
                <tr>
                  <td style="padding:16px 20px;">
                    <p style="margin:0 0 6px;font-family:Arial,sans-serif;font-size:11px;
                               font-weight:700;color:#1a0000;letter-spacing:1px;
                               text-transform:uppercase;">
                      Button not working?
                    </p>
                    <p style="margin:0 0 8px;font-family:Arial,sans-serif;font-size:12px;
                               color:#5a4e46;line-height:1.6;">
                      Copy and paste this link into your browser:
                    </p>
                    <p style="margin:0;font-family:'Courier New',monospace;font-size:11px;
                               color:#3a6fa8;word-break:break-all;line-height:1.6;">
                      {$safeUrl}
                    </p>
                  </td>
                </tr>
              </table>

              <!-- Security warning -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#fff5f5;border:1px solid #f0d0d0;
                            border-left:4px solid #a81c1c;border-radius:6px;">
                <tr>
                  <td style="padding:16px 20px;">
                    <p style="margin:0;font-family:Arial,sans-serif;font-size:12px;
                               color:#7a2020;line-height:1.7;">
                      <strong>&#9888; Security Notice &mdash;</strong>
                      If you did not request a password reset, you can safely ignore this email
                      &mdash; your password will <em>not</em> change. Never share this link with
                      anyone. SJC staff will never ask for your reset link.
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
