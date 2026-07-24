<?php
/**
 * PaymentMailer.php
 *
 * PHPMailer 7.0.2 — Automated email notifications for payment approvals.
 *
 * Two email types, driven by enrollment_changed flag from handleApprove():
 *   - 'enrollment'  → Student was registered (pending) and is now enrolled.
 *                     enrollment_changed = true in handleApprove() response.
 *   - 'tuition'     → Student was already enrolled; payment logged to account.
 *                     enrollment_changed = false in handleApprove() response.
 *
 * Usage (drop into handleApprove() after $pdo->commit()):
 *   notifyStudentPayment($pdo, $sub['student_id'], $enrollmentChanged);
 *
 * Requirements:
 *   composer require phpmailer/phpmailer
 *
 * Schema refs used:
 *   students  → first_name, last_name, personal_email
 *   users     → personal_email (fallback)
 *   (students.personal_email is the OTP / notification email per your schema)
 */

// ── PHPMailer loader — works with or without Composer ────────────────────────
// If you installed via Composer, the autoload below is used automatically.
// If you extracted phpmailer-7.0.2.zip manually, place the extracted folder
// next to this file so the path looks like: Cashier/PHPMailer/src/PHPMailer.php
$_composerAutoload = __DIR__ . '/../../vendor/autoload.php';
$_manualSrc        = __DIR__ . '/PHPMailer-7.0.2/src/';

if (file_exists($_composerAutoload)) {
    require_once $_composerAutoload;
} elseif (file_exists($_manualSrc . 'PHPMailer.php')) {
    // All three class files must exist before we load any of them
    require_once $_manualSrc . 'Exception.php';
    require_once $_manualSrc . 'PHPMailer.php';
    require_once $_manualSrc . 'SMTP.php';
} else {
    // PHPMailer not found — define stubs so the app still works without email.
    // Your files are at: Cashier Management\PHPMailer-7.0.2\src\
    // The loader is now correctly pointed at that path.
    // If you still see this error, check that PHPMailer.php exists in that folder.
    error_log('[PaymentMailer] PHPMailer not found at: ' . $_manualSrc . 'PHPMailer.php');
    if (!function_exists('notifyStudentPayment')) {
        function notifyStudentPayment(PDO $pdo, int $studentId, bool $enrollmentChanged): bool { return false; }
        function notifyStudentDecline(PDO $pdo, int $studentId, string $reason): bool { return false; }
    }
    return;
}

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

/* ============================================================
   MAILER CONFIG  — edit these to match your SMTP credentials
============================================================ */
define('MAIL_HOST',       'smtp.gmail.com');           // or smtp.office365.com, etc.
define('MAIL_PORT',       587);                        // 587 = STARTTLS  |  465 = SSL
define('MAIL_USERNAME',   'columbina234@gmail.com');       // your sending account
define('MAIL_PASSWORD',   'utkt bkfs wacd oxql');   // Gmail App Password (not login pw)
define('MAIL_FROM_NAME',  'Saint Joseph College');
define('MAIL_FROM_EMAIL', 'noreply@sjc.edu.ph');
define('PORTAL_URL',      'https://localhost/Login/Maininterface.html');
define('SCHOOL_YEAR',     date('Y'));

/* ============================================================
   PUBLIC ENTRY POINT
   Call this inside handleApprove() after $pdo->commit()
============================================================ */

/**
 * Fetch student contact info and dispatch the correct email.
 *
 * @param PDO  $pdo              Active PDO connection
 * @param int  $studentId        students.id of the approved student
 * @param bool $enrollmentChanged true  → enrollment fee email (newly enrolled)
 *                                false → tuition payment email (already enrolled)
 * @return bool                  true on success, false on mailer failure
 */
function notifyStudentPayment(PDO $pdo, int $studentId, bool $enrollmentChanged): bool
{
    // ── 1. Resolve student name + email from DB ──────────────────────────────
    $stmt = $pdo->prepare("
        SELECT
            s.first_name,
            s.last_name,
            COALESCE(s.personal_email, u.personal_email, u.email) AS recipient_email
        FROM   students s
        LEFT JOIN users u ON u.id = s.user_id
        WHERE  s.id = ?
        LIMIT  1
    ");
    $stmt->execute([$studentId]);
    $student = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$student || empty($student['recipient_email'])) {
        error_log("[PaymentMailer] Cannot send email: no email found for student_id={$studentId}");
        return false;
    }

    $fullName      = trim($student['first_name'] . ' ' . $student['last_name']);
    $recipientEmail = $student['recipient_email'];

    // ── 2. Resolve logo as inline CID attachment ─────────────────────────────
    //    Adjust path to match your actual logo location.
    $logoPath = __DIR__ . '/../Cashier Management/Cashier Media/school no bg.png';
    $hasLogo  = file_exists($logoPath);

    // ── 3. Dispatch ──────────────────────────────────────────────────────────
    $type = $enrollmentChanged ? 'enrollment' : 'tuition';

    return sendPaymentEmail($type, $fullName, $recipientEmail, $logoPath, $hasLogo);
}

/* ============================================================
   MAILER CORE
============================================================ */

/**
 * Build and send the email via PHPMailer.
 *
 * @param string $type           'enrollment' | 'tuition'
 * @param string $studentName    Full name for greeting
 * @param string $recipientEmail Destination email (students.personal_email)
 * @param string $logoPath       Absolute server path to school logo PNG
 * @param bool   $hasLogo        Whether logo file actually exists
 */
function sendPaymentEmail(
    string $type,
    string $studentName,
    string $recipientEmail,
    string $logoPath,
    bool   $hasLogo
): bool {
    $mail = new PHPMailer(true);  // true = throw Exceptions

    try {
        // ── Transport ────────────────────────────────────────────────────────
        $mail->isSMTP();
        $mail->Host       = MAIL_HOST;
        $mail->SMTPAuth   = true;
        $mail->Username   = MAIL_USERNAME;
        $mail->Password   = MAIL_PASSWORD;
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS; // change to SMTPS for port 465
        $mail->Port       = MAIL_PORT;

        // ── Sender / Recipient ───────────────────────────────────────────────
        $mail->setFrom(MAIL_FROM_EMAIL, MAIL_FROM_NAME);
        $mail->addAddress($recipientEmail, $studentName);
        $mail->addReplyTo('admin@sjc.edu.ph', 'SJC Administration');

        // ── Encoding ─────────────────────────────────────────────────────────
        $mail->CharSet  = 'UTF-8';
        $mail->Encoding = 'base64';

        // ── Inline logo ──────────────────────────────────────────────────────
        $logoCid = '';
        if ($hasLogo) {
            $mail->addEmbeddedImage($logoPath, 'sjc_logo', 'school_logo.png', 'base64', 'image/png');
            $logoCid = 'cid:sjc_logo';
        }

        // ── Subject ──────────────────────────────────────────────────────────
        $mail->Subject = getEmailSubject($type);

        // ── Body ─────────────────────────────────────────────────────────────
        $mail->isHTML(true);
        $mail->Body    = buildPaymentEmailHtml($type, $studentName, PORTAL_URL, SCHOOL_YEAR, $logoCid);
        $mail->AltBody = buildPaymentEmailText($type, $studentName, PORTAL_URL);

        $mail->send();

        error_log("[PaymentMailer] Email sent → {$recipientEmail} | type={$type}");
        return true;

    } catch (Exception $e) {
        error_log("[PaymentMailer] Mailer Error → {$mail->ErrorInfo}");
        return false;
    }
}

/* ============================================================
   SUBJECT LINES
============================================================ */

/**
 * Returns the email subject line for the given payment type.
 * Matches the exact subjects specified in your requirements.
 */
function getEmailSubject(string $type): string
{
    return match ($type) {
        'enrollment'  => 'Enrollment Confirmation – Payment Approved',
        'tuition'     => 'Tuition Payment Confirmation – Received Successfully',
        'payment_due' => 'Payment Due Notice – Action Required',
        default       => 'Payment Notification – Saint Joseph College',
    };
}

/* ============================================================
   HTML TEMPLATE
   Consistent with your school branding: #1a0000 maroon + #c9a84c gold.
   Structured for inline-style email clients (Gmail, Outlook, Yahoo).
============================================================ */

/**
 * Builds the full HTML email body.
 *
 * @param string $type          'enrollment' | 'tuition'
 * @param string $studentName   Recipient's full name
 * @param string $portalUrl     Student portal URL
 * @param string $year          School year (used in footer)
 * @param string $logoCid       CID reference for embedded logo, or '' if no logo
 */
function buildPaymentEmailHtml(
    string $type,
    string $studentName,
    string $portalUrl,
    string $year,
    string $logoCid
): string {
    // ── Per-type content variables ───────────────────────────────────────────
    $isEnrollment = $type === 'enrollment';

    $title       = $isEnrollment ? 'Enrollment Confirmation'          : 'Tuition Payment Confirmation';
    $badge       = $isEnrollment ? 'ENROLLMENT'                       : 'TUITION PAYMENT';
    $headline    = $isEnrollment ? 'Your Enrollment Has Been Confirmed' : 'Your Payment Has Been Received';
    $accentLine  = $isEnrollment
        ? 'You are now officially enrolled.'
        : 'Your student account has been updated accordingly.';

    // Main body paragraph — enrollment vs tuition wording kept strictly separate
    if ($isEnrollment) {
        $bodyHtml = <<<HTML
            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                Your proof of payment has been reviewed and approved by the school cashier.
                You are now officially enrolled.
            </p>
            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                You may access your official receipt and enrollment details through your
                student portal. Please log in to view your enrollment status and payment receipt.
            </p>
            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                If changes do not appear immediately, kindly wait a few minutes for system updates.
                If you continue to experience issues, please contact the school administration
                for assistance.
            </p>
        HTML;
    } else {
        $bodyHtml = <<<HTML
            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                We have successfully received and verified your tuition payment.
            </p>
            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                You may view your official receipt and current balance through your student portal.
                If your payment reflects an installment, your remaining balance (if any) will also
                be shown in your account dashboard.
            </p>
            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                Please allow a few minutes for system updates. If you notice any discrepancies,
                kindly contact the school cashier or administration office.
            </p>
        HTML;
    }

    // ── Logo tag ──────────────────────────────────────────────────────────────
    $logoTag = $logoCid
        ? '<img src="' . htmlspecialchars($logoCid) . '" width="54" height="54"
               alt="SJC Logo"
               style="border-radius:50%;object-fit:contain;
                      border:1.5px solid rgba(201,168,76,0.35);padding:3px;">'
        : '';

    // ── Assemble ──────────────────────────────────────────────────────────────
    $safeStudentName = htmlspecialchars($studentName);
    $safePortalUrl   = htmlspecialchars($portalUrl);
    $safeYear        = htmlspecialchars($year);

    return <<<HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>{$title}</title>
    </head>
    <body style="margin:0;padding:0;background-color:#f0ece6;font-family:Arial,Helvetica,sans-serif;">

    <!--[if mso]><table width="100%" cellpadding="0" cellspacing="0"><tr><td><![endif]-->
    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="background-color:#f0ece6;padding:40px 16px;">
        <tr>
            <td align="center">

                <!-- ══ CARD ══════════════════════════════════════════════ -->
                <table width="600" cellpadding="0" cellspacing="0" border="0"
                       style="max-width:600px;width:100%;background:#ffffff;
                              border-radius:14px;overflow:hidden;
                              box-shadow:0 6px 30px rgba(0,0,0,0.15);">

                    <!-- HEADER: maroon bg + gold text + logo -->
                    <tr>
                        <td style="background-color:#1a0000;padding:22px 28px;">
                            <table width="100%" cellpadding="0" cellspacing="0" border="0">
                                <tr>
                                    <td width="66" style="vertical-align:middle;padding-right:14px;">
                                        {$logoTag}
                                    </td>
                                    <td style="vertical-align:middle;">
                                        <div style="color:#c9a84c;font-size:15px;
                                                    font-weight:bold;letter-spacing:2px;
                                                    text-transform:uppercase;">
                                            Saint Joseph College
                                        </div>
                                        <div style="color:#c9a84c;font-size:10px;
                                                    opacity:0.75;letter-spacing:1px;
                                                    margin-top:3px;">
                                            OFFICIAL SCHOOL PORTAL
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>

                    <!-- BADGE ROW -->
                    <tr>
                        <td style="padding:14px 28px;background-color:#f9f5ef;
                                   border-bottom:1px solid #ece4d6;">
                            <span style="display:inline-block;background-color:#1a0000;
                                         color:#c9a84c;padding:4px 12px;font-size:11px;
                                         font-weight:bold;letter-spacing:1px;
                                         border-radius:4px;">
                                {$badge}
                            </span>
                        </td>
                    </tr>

                    <!-- BODY -->
                    <tr>
                        <td style="padding:34px 28px 24px;">

                            <!-- Headline -->
                            <h2 style="margin:0 0 4px;color:#1a0000;font-size:20px;">
                                {$headline}
                            </h2>

                            <!-- Accent line -->
                            <p style="margin:0 0 20px;color:#1a0000;font-size:13px;
                                      font-weight:bold;">
                                {$accentLine}
                            </p>

                            <!-- Salutation -->
                            <p style="margin:0 0 16px;color:#3d3028;font-size:14px;">
                                Dear <strong>{$safeStudentName}</strong>,
                            </p>

                            <!-- Per-type body paragraphs -->
                            {$bodyHtml}

                            <!-- CTA BOX -->
                            <table width="100%" cellpadding="0" cellspacing="0" border="0"
                                   style="margin:26px 0 0;">
                                <tr>
                                    <td style="background-color:#fdf9f2;
                                               border:1px solid #e8dfc8;
                                               border-radius:8px;padding:18px 20px;">
                                        <p style="margin:0 0 12px;font-size:13px;color:#5a4e46;">
                                            Access your receipt and account details here:
                                        </p>
                                        <a href="{$safePortalUrl}"
                                           style="display:inline-block;background-color:#1a0000;
                                                  color:#c9a84c;padding:11px 20px;
                                                  text-decoration:none;border-radius:6px;
                                                  font-size:13px;font-weight:bold;
                                                  letter-spacing:0.5px;">
                                            Open Student Portal
                                        </a>
                                        <p style="margin:12px 0 0;font-size:11px;color:#8a7a72;">
                                            {$safePortalUrl}
                                        </p>
                                    </td>
                                </tr>
                            </table>

                            <!-- Closing -->
                            <p style="margin:24px 0 0;font-size:13px;color:#5a4e46;line-height:1.6;">
                                Thank you for choosing Saint Joseph College of Novaliches.
                            </p>

                        </td>
                    </tr>

                    <!-- FOOTER -->
                    <tr>
                        <td style="background-color:#1a0000;padding:18px 28px;">
                            <p style="margin:0;color:#c9a84c;font-size:11px;line-height:1.6;">
                                &copy; {$safeYear} Saint Joseph College of Novaliches, Inc.
                                &mdash; All rights reserved.<br>
                                <span style="opacity:0.7;font-size:10px;">
                                    This is an automated message. Please do not reply directly to this email.
                                    For concerns, contact the school cashier or administration office.
                                </span>
                            </p>
                        </td>
                    </tr>

                </table>
                <!-- ══ END CARD ══════════════════════════════════════════ -->

            </td>
        </tr>
    </table>
    <!--[if mso]></td></tr></table><![endif]-->

    </body>
    </html>
    HTML;
}

/* ============================================================
   DECLINE — PUBLIC ENTRY POINT
   Call this inside handleDecline() after the UPDATE query.
============================================================ */

/**
 * Fetch student contact info and send a payment rejection email.
 *
 * @param PDO    $pdo        Active PDO connection
 * @param int    $studentId  students.id of the declined student
 * @param string $reason     Cashier's rejection reason (may be empty)
 * @return bool              true on success, false on mailer failure
 */
function notifyStudentDecline(PDO $pdo, int $studentId, string $reason): bool
{
    $stmt = $pdo->prepare("
        SELECT
            s.first_name,
            s.last_name,
            COALESCE(s.personal_email, u.personal_email, u.email) AS recipient_email
        FROM   students s
        LEFT JOIN users u ON u.id = s.user_id
        WHERE  s.id = ?
        LIMIT  1
    ");
    $stmt->execute([$studentId]);
    $student = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$student || empty($student['recipient_email'])) {
        error_log("[PaymentMailer] Cannot send decline email: no email found for student_id={$studentId}");
        return false;
    }

    $fullName       = trim($student['first_name'] . ' ' . $student['last_name']);
    $recipientEmail = $student['recipient_email'];

    $logoPath = __DIR__ . '/../Cashier Management/Cashier Media/school no bg.png';
    $hasLogo  = file_exists($logoPath);

    return sendDeclineEmail($fullName, $recipientEmail, $reason, $logoPath, $hasLogo);
}

/**
 * Build and send the decline/rejection email.
 */
function sendDeclineEmail(
    string $studentName,
    string $recipientEmail,
    string $reason,
    string $logoPath,
    bool   $hasLogo
): bool {
    $mail = new PHPMailer(true);

    try {
        $mail->isSMTP();
        $mail->Host       = MAIL_HOST;
        $mail->SMTPAuth   = true;
        $mail->Username   = MAIL_USERNAME;
        $mail->Password   = MAIL_PASSWORD;
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = MAIL_PORT;

        $mail->setFrom(MAIL_FROM_EMAIL, MAIL_FROM_NAME);
        $mail->addAddress($recipientEmail, $studentName);
        $mail->addReplyTo('admin@sjc.edu.ph', 'SJC Administration');

        $mail->CharSet  = 'UTF-8';
        $mail->Encoding = 'base64';

        $logoCid = '';
        if ($hasLogo) {
            $mail->addEmbeddedImage($logoPath, 'sjc_logo', 'school_logo.png', 'base64', 'image/png');
            $logoCid = 'cid:sjc_logo';
        }

        $mail->Subject = 'Payment Submission Update – Action Required';
        $mail->isHTML(true);
        $mail->Body    = buildDeclineEmailHtml($studentName, $reason, PORTAL_URL, SCHOOL_YEAR, $logoCid);
        $mail->AltBody = buildDeclineEmailText($studentName, $reason, PORTAL_URL);

        $mail->send();
        error_log("[PaymentMailer] Decline email sent → {$recipientEmail}");
        return true;

    } catch (Exception $e) {
        error_log("[PaymentMailer] Decline Mailer Error → {$mail->ErrorInfo}");
        return false;
    }
}

/**
 * HTML body for the decline email.
 */
function buildDeclineEmailHtml(
    string $studentName,
    string $reason,
    string $portalUrl,
    string $year,
    string $logoCid
): string {
    $safeStudentName = htmlspecialchars($studentName);
    $safePortalUrl   = htmlspecialchars($portalUrl);
    $safeYear        = htmlspecialchars($year);
    $safeReason      = $reason ? htmlspecialchars($reason) : 'No specific reason was provided by the cashier.';

    $logoTag = $logoCid
        ? '<img src="' . htmlspecialchars($logoCid) . '" width="54" height="54"
               alt="SJC Logo"
               style="border-radius:50%;object-fit:contain;
                      border:1.5px solid rgba(201,168,76,0.35);padding:3px;">'
        : '';

    return <<<HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Payment Submission Update</title>
    </head>
    <body style="margin:0;padding:0;background-color:#f0ece6;font-family:Arial,Helvetica,sans-serif;">

    <!--[if mso]><table width="100%" cellpadding="0" cellspacing="0"><tr><td><![endif]-->
    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="background-color:#f0ece6;padding:40px 16px;">
        <tr>
            <td align="center">
                <table width="600" cellpadding="0" cellspacing="0" border="0"
                       style="max-width:600px;width:100%;background:#ffffff;
                              border-radius:14px;overflow:hidden;
                              box-shadow:0 6px 30px rgba(0,0,0,0.15);">

                    <!-- HEADER -->
                    <tr>
                        <td style="background-color:#1a0000;padding:22px 28px;">
                            <table width="100%" cellpadding="0" cellspacing="0" border="0">
                                <tr>
                                    <td width="66" style="vertical-align:middle;padding-right:14px;">
                                        {$logoTag}
                                    </td>
                                    <td style="vertical-align:middle;">
                                        <div style="color:#c9a84c;font-size:15px;
                                                    font-weight:bold;letter-spacing:2px;
                                                    text-transform:uppercase;">
                                            Saint Joseph College
                                        </div>
                                        <div style="color:#c9a84c;font-size:10px;
                                                    opacity:0.75;letter-spacing:1px;
                                                    margin-top:3px;">
                                            OFFICIAL SCHOOL PORTAL
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>

                    <!-- BADGE ROW -->
                    <tr>
                        <td style="padding:14px 28px;background-color:#fff5f5;
                                   border-bottom:1px solid #fcd5d5;">
                            <span style="display:inline-block;background-color:#8b0000;
                                         color:#ffffff;padding:4px 12px;font-size:11px;
                                         font-weight:bold;letter-spacing:1px;
                                         border-radius:4px;">
                                PAYMENT DECLINED
                            </span>
                        </td>
                    </tr>

                    <!-- BODY -->
                    <tr>
                        <td style="padding:34px 28px 24px;">

                            <h2 style="margin:0 0 4px;color:#1a0000;font-size:20px;">
                                Your Payment Submission Was Not Approved
                            </h2>
                            <p style="margin:0 0 20px;color:#8b0000;font-size:13px;font-weight:bold;">
                                Please review the reason below and resubmit a corrected payment.
                            </p>

                            <p style="margin:0 0 16px;color:#3d3028;font-size:14px;">
                                Dear <strong>{$safeStudentName}</strong>,
                            </p>

                            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                                We regret to inform you that your recent proof of payment submission
                                has been reviewed by the school cashier and could not be approved at this time.
                            </p>

                            <!-- Reason box -->
                            <table width="100%" cellpadding="0" cellspacing="0" border="0"
                                   style="margin:20px 0;">
                                <tr>
                                    <td style="background-color:#fff5f5;
                                               border-left:4px solid #8b0000;
                                               border-radius:0 6px 6px 0;
                                               padding:14px 18px;">
                                        <p style="margin:0 0 6px;font-size:12px;font-weight:bold;
                                                  color:#8b0000;letter-spacing:0.5px;
                                                  text-transform:uppercase;">
                                            Reason for Decline
                                        </p>
                                        <p style="margin:0;font-size:14px;color:#3d3028;line-height:1.6;">
                                            {$safeReason}
                                        </p>
                                    </td>
                                </tr>
                            </table>

                            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                                Please log in to your student portal to resubmit a valid proof of payment.
                                Make sure to upload a clear and complete copy of your official receipt
                                or transaction confirmation.
                            </p>

                            <!-- CTA BOX -->
                            <table width="100%" cellpadding="0" cellspacing="0" border="0"
                                   style="margin:26px 0 0;">
                                <tr>
                                    <td style="background-color:#fdf9f2;
                                               border:1px solid #e8dfc8;
                                               border-radius:8px;padding:18px 20px;">
                                        <p style="margin:0 0 12px;font-size:13px;color:#5a4e46;">
                                            Log in to resubmit your payment proof:
                                        </p>
                                        <a href="{$safePortalUrl}"
                                           style="display:inline-block;background-color:#1a0000;
                                                  color:#c9a84c;padding:11px 20px;
                                                  text-decoration:none;border-radius:6px;
                                                  font-size:13px;font-weight:bold;
                                                  letter-spacing:0.5px;">
                                            Open Student Portal
                                        </a>
                                        <p style="margin:12px 0 0;font-size:11px;color:#8a7a72;">
                                            {$safePortalUrl}
                                        </p>
                                    </td>
                                </tr>
                            </table>

                            <p style="margin:24px 0 0;font-size:13px;color:#5a4e46;line-height:1.6;">
                                If you believe this is a mistake or need assistance, please contact
                                the school cashier or administration office directly.
                            </p>

                        </td>
                    </tr>

                    <!-- FOOTER -->
                    <tr>
                        <td style="background-color:#1a0000;padding:18px 28px;">
                            <p style="margin:0;color:#c9a84c;font-size:11px;line-height:1.6;">
                                &copy; {$safeYear} Saint Joseph College of Novaliches, Inc.
                                &mdash; All rights reserved.<br>
                                <span style="opacity:0.7;font-size:10px;">
                                    This is an automated message. Please do not reply directly to this email.
                                    For concerns, contact the school cashier or administration office.
                                </span>
                            </p>
                        </td>
                    </tr>

                </table>
            </td>
        </tr>
    </table>
    <!--[if mso]></td></tr></table><![endif]-->

    </body>
    </html>
    HTML;
}

/**
 * Plain-text fallback for the decline email.
 */
function buildDeclineEmailText(string $studentName, string $reason, string $portalUrl): string
{
    $safeReason = $reason ?: 'No specific reason was provided by the cashier.';
    return <<<TEXT
    Payment Submission Update – Action Required
    ────────────────────────────────────────

    Dear {$studentName},

    We regret to inform you that your recent proof of payment submission
    has been reviewed by the school cashier and could not be approved.

    Reason for Decline:
    {$safeReason}

    Please log in to your student portal to resubmit a valid proof of payment:
    {$portalUrl}

    Make sure to upload a clear and complete copy of your official receipt
    or transaction confirmation.

    If you believe this is a mistake, please contact the school cashier
    or administration office directly.

    ────────────────────────────────────────
    Saint Joseph College of Novaliches, Inc.
    This is an automated message. Please do not reply.
    TEXT;
}



/**
 * Plain-text version of the email (PHPMailer AltBody).
 */
function buildPaymentEmailText(string $type, string $studentName, string $portalUrl): string
{
    $isEnrollment = $type === 'enrollment';

    $subject = getEmailSubject($type);

    if ($isEnrollment) {
        $body = <<<TEXT
        {$subject}
        ────────────────────────────────────────

        Dear {$studentName},

        Congratulations! Your enrollment has been successfully confirmed.

        Your proof of payment has been reviewed and approved by the school cashier.
        You are now officially enrolled.

        You may access your official receipt and enrollment details through your student portal:
        {$portalUrl}

        Please log in to view your enrollment status and payment receipt.
        If changes do not appear immediately, kindly wait a few minutes for system updates.
        If you continue to experience issues, please contact the school administration.

        Thank you.

        ────────────────────────────────────────
        Saint Joseph College of Novaliches, Inc.
        This is an automated message. Please do not reply.
        TEXT;
    } else {
        $body = <<<TEXT
        {$subject}
        ────────────────────────────────────────

        Dear {$studentName},

        We have successfully received and verified your tuition payment.
        Your student account has been updated accordingly.

        You may view your official receipt and current balance through your student portal:
        {$portalUrl}

        If your payment reflects an installment, your remaining balance (if any) will also
        be shown in your account dashboard.

        Please allow a few minutes for system updates. If you notice any discrepancies,
        kindly contact the school cashier or administration office.

        Thank you.

        ────────────────────────────────────────
        Saint Joseph College of Novaliches, Inc.
        This is an automated message. Please do not reply.
        TEXT;
    }

    return $body;
}

/* ============================================================
   PAYMENT DUE NOTICE — PUBLIC ENTRY POINT
   Call this inside handlePaymentDue() after INSERT.
============================================================ */

/**
 * Fetch student contact info and send a payment-due notice email.
 *
 * @param PDO    $pdo          Active PDO connection
 * @param int    $studentId    students.id of the target student
 * @param float  $amountDue    Amount the student owes
 * @param string $dueDatetime  Due date/time as 'Y-m-d H:i:s' (Asia/Manila)
 * @return bool                true on success, false on mailer failure
 */
function notifyStudentPaymentDue(PDO $pdo, int $studentId, float $amountDue, string $dueDatetime, string $noticeMessage = ''): bool
{
    // Resolve student name + email
    $stmt = $pdo->prepare("
        SELECT
            s.first_name,
            s.last_name,
            COALESCE(s.personal_email, u.personal_email, u.email) AS recipient_email
        FROM   students s
        LEFT JOIN users u ON u.id = s.user_id
        WHERE  s.id = ?
        LIMIT  1
    ");
    $stmt->execute([$studentId]);
    $student = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$student || empty($student['recipient_email'])) {
        error_log("[PaymentMailer] Cannot send payment-due email: no email found for student_id={$studentId}");
        return false;
    }

    $fullName       = trim($student['first_name'] . ' ' . $student['last_name']);
    $recipientEmail = $student['recipient_email'];

    $logoPath = __DIR__ . '/../Cashier Management/Cashier Media/school no bg.png';
    $hasLogo  = file_exists($logoPath);

    return sendPaymentDueEmail($fullName, $recipientEmail, $amountDue, $dueDatetime, $logoPath, $hasLogo, $noticeMessage);
}

/**
 * Build and send the payment-due notice email.
 */
function sendPaymentDueEmail(
    string $studentName,
    string $recipientEmail,
    float  $amountDue,
    string $dueDatetime,
    string $logoPath,
    bool   $hasLogo,
    string $noticeMessage = ''
): bool {
    $mail = new PHPMailer(true);

    try {
        $mail->isSMTP();
        $mail->Host       = MAIL_HOST;
        $mail->SMTPAuth   = true;
        $mail->Username   = MAIL_USERNAME;
        $mail->Password   = MAIL_PASSWORD;
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = MAIL_PORT;

        $mail->setFrom(MAIL_FROM_EMAIL, MAIL_FROM_NAME);
        $mail->addAddress($recipientEmail, $studentName);
        $mail->addReplyTo('admin@sjc.edu.ph', 'SJC Administration');

        $mail->CharSet  = 'UTF-8';
        $mail->Encoding = 'base64';

        $logoCid = '';
        if ($hasLogo) {
            $mail->addEmbeddedImage($logoPath, 'sjc_logo', 'school_logo.png', 'base64', 'image/png');
            $logoCid = 'cid:sjc_logo';
        }

        $mail->Subject = getEmailSubject('payment_due');
        $mail->isHTML(true);
        $mail->Body    = buildPaymentDueEmailHtml($studentName, $amountDue, $dueDatetime, PORTAL_URL, SCHOOL_YEAR, $logoCid, $noticeMessage);
        $mail->AltBody = buildPaymentDueEmailText($studentName, $amountDue, $dueDatetime, PORTAL_URL, $noticeMessage);

        $mail->send();
        error_log("[PaymentMailer] Payment-due email sent → {$recipientEmail}");
        return true;

    } catch (Exception $e) {
        error_log("[PaymentMailer] Payment-due Mailer Error → {$mail->ErrorInfo}");
        return false;
    }
}

/**
 * HTML email body for the payment-due notice.
 * Matches the exact body copy specified in the requirements.
 */
function buildPaymentDueEmailHtml(
    string $studentName,
    float  $amountDue,
    string $dueDatetime,
    string $portalUrl,
    string $year,
    string $logoCid,
    string $noticeMessage = ''
): string {
    // Format amount and due date for display
    $amountFmt  = '₱' . number_format($amountDue, 2);
    $dueDtObj   = new DateTime($dueDatetime, new DateTimeZone('Asia/Manila'));
    $dueFmt     = $dueDtObj->format('F j, Y \a\t g:i A');   // e.g. "June 30, 2025 at 5:00 PM"

    $safeStudentName = htmlspecialchars($studentName);
    $safeDueFmt      = htmlspecialchars($dueFmt);
    $safeAmountFmt   = htmlspecialchars($amountFmt);
    $safePortalUrl   = htmlspecialchars($portalUrl);
    $safeYear        = htmlspecialchars($year);

    $logoTag = $logoCid
        ? '<img src="' . htmlspecialchars($logoCid) . '" width="54" height="54"
               alt="SJC Logo"
               style="border-radius:50%;object-fit:contain;
                      border:1.5px solid rgba(201,168,76,0.35);padding:3px;">'
        : '';

    return <<<HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Payment Due Notice</title>
    </head>
    <body style="margin:0;padding:0;background-color:#f0ece6;font-family:Arial,Helvetica,sans-serif;">

    <!--[if mso]><table width="100%" cellpadding="0" cellspacing="0"><tr><td><![endif]-->
    <table width="100%" cellpadding="0" cellspacing="0" border="0"
           style="background-color:#f0ece6;padding:40px 16px;">
        <tr>
            <td align="center">

                <!-- ══ CARD ══════════════════════════════════════════════ -->
                <table width="600" cellpadding="0" cellspacing="0" border="0"
                       style="max-width:600px;width:100%;background:#ffffff;
                              border-radius:14px;overflow:hidden;
                              box-shadow:0 6px 30px rgba(0,0,0,0.15);">

                    <!-- HEADER -->
                    <tr>
                        <td style="background-color:#1a0000;padding:22px 28px;">
                            <table width="100%" cellpadding="0" cellspacing="0" border="0">
                                <tr>
                                    <td width="66" style="vertical-align:middle;padding-right:14px;">
                                        {$logoTag}
                                    </td>
                                    <td style="vertical-align:middle;">
                                        <div style="color:#c9a84c;font-size:15px;
                                                    font-weight:bold;letter-spacing:2px;
                                                    text-transform:uppercase;">
                                            Saint Joseph College
                                        </div>
                                        <div style="color:#c9a84c;font-size:10px;
                                                    opacity:0.75;letter-spacing:1px;
                                                    margin-top:3px;">
                                            OFFICIAL SCHOOL PORTAL
                                        </div>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>

                    <!-- BADGE ROW -->
                    <tr>
                        <td style="padding:14px 28px;background-color:#fffbf0;
                                   border-bottom:1px solid #f0dfa0;">
                            <span style="display:inline-block;background-color:#8b6914;
                                         color:#ffffff;padding:4px 12px;font-size:11px;
                                         font-weight:bold;letter-spacing:1px;
                                         border-radius:4px;">
                                PAYMENT DUE NOTICE
                            </span>
                        </td>
                    </tr>

                    <!-- BODY -->
                    <tr>
                        <td style="padding:34px 28px 24px;">

                            <h2 style="margin:0 0 4px;color:#1a0000;font-size:20px;">
                                Upcoming Payment Due
                            </h2>
                            <p style="margin:0 0 20px;color:#8b6914;font-size:13px;font-weight:bold;">
                                Please settle your balance on or before the due date.
                            </p>

                            <!-- Salutation using exact body copy from requirements -->
                            <p style="margin:0 0 16px;color:#3d3028;font-size:14px;line-height:1.7;">
                                Good day, <strong>{$safeStudentName}</strong>,
                            </p>

                            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                                This is to inform you that your next tuition payment is due on
                                <strong>{$safeDueFmt}</strong> with an amount of
                                <strong>{$safeAmountFmt}</strong>.
                            </p>

                            <p style="margin:0 0 14px;color:#5a4e46;line-height:1.7;font-size:14px;">
                                Kindly settle your balance on or before the due date to avoid
                                possible delays or penalties.
                            </p>

                            <!-- Due date highlight box -->
                            <table width="100%" cellpadding="0" cellspacing="0" border="0"
                                   style="margin:20px 0;">
                                <tr>
                                    <td style="background-color:#fffbf0;
                                               border:1.5px solid #f0dfa0;
                                               border-radius:8px;padding:16px 20px;
                                               text-align:center;">
                                        <p style="margin:0 0 4px;font-size:11px;font-weight:bold;
                                                  color:#8b6914;letter-spacing:0.5px;
                                                  text-transform:uppercase;">
                                            Due Date &amp; Time
                                        </p>
                                        <p style="margin:0 0 8px;font-size:18px;color:#1a0000;
                                                  font-weight:bold;">
                                            {$safeDueFmt}
                                        </p>
                                        <p style="margin:0;font-size:20px;color:#8b6914;font-weight:bold;">
                                            {$safeAmountFmt}
                                        </p>
                                    </td>
                                </tr>
                            </table>

                            <!-- Payment instructions -->
                            <p style="margin:0 0 10px;color:#3d3028;font-size:14px;font-weight:bold;">
                                You may complete your payment by:
                            </p>
                            <table width="100%" cellpadding="0" cellspacing="0" border="0"
                                   style="margin:0 0 20px;">
                                <tr>
                                    <td style="padding:4px 0 4px 16px;color:#5a4e46;font-size:14px;
                                               line-height:1.7;">
                                        &#8226;&nbsp; On-site payment at the cashier office, or
                                    </td>
                                </tr>
                                <tr>
                                    <td style="padding:4px 0 4px 16px;color:#5a4e46;font-size:14px;
                                               line-height:1.7;">
                                        &#8226;&nbsp; Uploading your proof of payment through the school portal.
                                    </td>
                                </tr>
                            </table>

                            <!-- CTA BOX -->
                            <table width="100%" cellpadding="0" cellspacing="0" border="0"
                                   style="margin:20px 0 0;">
                                <tr>
                                    <td style="background-color:#fdf9f2;
                                               border:1px solid #e8dfc8;
                                               border-radius:8px;padding:18px 20px;">
                                        <p style="margin:0 0 12px;font-size:13px;color:#5a4e46;">
                                            Access the student portal to upload your proof of payment:
                                        </p>
                                        <a href="{$safePortalUrl}"
                                           style="display:inline-block;background-color:#1a0000;
                                                  color:#c9a84c;padding:11px 20px;
                                                  text-decoration:none;border-radius:6px;
                                                  font-size:13px;font-weight:bold;
                                                  letter-spacing:0.5px;">
                                            Open Student Portal
                                        </a>
                                        <p style="margin:12px 0 0;font-size:11px;color:#8a7a72;">
                                            {$safePortalUrl}
                                        </p>
                                    </td>
                                </tr>
                            </table>

                            <p style="margin:24px 0 0;font-size:13px;color:#5a4e46;line-height:1.6;">
                                Thank you.
                            </p>

                        </td>
                    </tr>

                    <!-- FOOTER -->
                    <tr>
                        <td style="background-color:#1a0000;padding:18px 28px;">
                            <p style="margin:0;color:#c9a84c;font-size:11px;line-height:1.6;">
                                &copy; {$safeYear} Saint Joseph College of Novaliches, Inc.
                                &mdash; All rights reserved.<br>
                                <span style="opacity:0.7;font-size:10px;">
                                    This is an automated message. Please do not reply directly to this email.
                                    For concerns, contact the school cashier or administration office.
                                </span>
                            </p>
                        </td>
                    </tr>

                </table>
                <!-- ══ END CARD ══════════════════════════════════════════ -->

            </td>
        </tr>
    </table>
    <!--[if mso]></td></tr></table><![endif]-->

    </body>
    </html>
    HTML;
}

/**
 * Plain-text fallback for the payment-due email.
 * Uses the exact body copy specified in the requirements.
 */
function buildPaymentDueEmailText(
    string $studentName,
    float  $amountDue,
    string $dueDatetime,
    string $portalUrl,
    string $noticeMessage = ''
): string {
    $amountFmt = '₱' . number_format($amountDue, 2);
    $dueDtObj  = new DateTime($dueDatetime, new DateTimeZone('Asia/Manila'));
    $dueFmt    = $dueDtObj->format('F j, Y \a\t g:i A');
    $extraNote = $noticeMessage ? "\n\nNote: {$noticeMessage}" : '';

    return <<<TEXT
Payment Deadline Notice – Saint Joseph College
────────────────────────────────────────

Good day, {$studentName},

This is to inform you that your payment deadline is on {$dueFmt} with an amount of {$amountFmt}.

Kindly settle your balance on or before the deadline to avoid possible delays or penalties.{$extraNote}

You may complete your payment through:
  • GCash — upload your proof of payment via the student portal
  • Bank Transfer — upload your proof of payment via the student portal
  • On-site payment at the cashier office

All payments must be completed through the student portal before the deadline.

Access the student portal here:
{$portalUrl}

Thank you.

────────────────────────────────────────
Saint Joseph College of Novaliches, Inc.
This is an automated message. Please do not reply.
TEXT;
}