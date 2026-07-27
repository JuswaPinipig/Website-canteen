<?php


session_start();
header('Content-Type: application/json');

// ─── PHPMailer ──────────────────────────────────────────────
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception as MailException;

require_once __DIR__ . '/../Login/PHPMailer-7.0.2/src/Exception.php';
require_once __DIR__ . '/../Login/PHPMailer-7.0.2/src/PHPMailer.php';
require_once __DIR__ . '/../Login/PHPMailer-7.0.2/src/SMTP.php';

// ─── DB CONFIG ──────────────────────────────────────────────
define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'school_system');
define('DB_USER', 'root');
define('DB_PASS', '');

function db(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        try {
            $pdo = new PDO(
                'mysql:host=' . DB_HOST . ';dbname=' . DB_NAME . ';charset=utf8mb4',
                DB_USER, DB_PASS,
                [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                 PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
            );
        } catch (PDOException $e) {
            out(false, 'Database connection failed.');
            exit;
        }
    }
    return $pdo;
}

// ─── HELPERS ────────────────────────────────────────────────
function out(bool $success, string $message = '', $data = null): void {
    echo json_encode(['success' => $success, 'message' => $message, 'data' => $data]);
    exit;
}

/** Trim and return POST value. Returns '' (not null) if missing. */
function post(string $key, $default = ''): string {
    return trim($_POST[$key] ?? $default);
}

/** Require non-empty string, call out() on failure. */
function requireField(string $value, string $label): void {
    if ($value === '') out(false, "{$label} is required.");
}

/** Validate & parse a DATETIME string (YYYY-MM-DD HH:MM:SS or YYYY-MM-DDTHH:MM). */
function parseDateTime(string $val): ?string {
    $val = trim($val);
    // Accept both HTML datetime-local format (T separator) and space separator
    $val = str_replace('T', ' ', $val);
    $d = DateTime::createFromFormat('Y-m-d H:i:s', $val)
      ?: DateTime::createFromFormat('Y-m-d H:i', $val);
    return $d ? $d->format('Y-m-d H:i:s') : null;
}

/**
 * Allowed portal roles (can log into admin portal).
 * Teachers / students / parents are NOT allowed.
 */
const PORTAL_ROLES = ['admin', 'registrar', 'principal', 'coordinator', 'cashier'];
const ALL_ROLES    = ['teacher', 'cashier', 'registrar', 'principal', 'coordinator', 'admin'];

/**
 * Allowed deadline types (new 3-term naming).
 * Maps internal key → display label.
 */
const DEADLINE_TYPES = [
    'enrollment'           => 'Enrollment',
    'grade_encoding_term1' => '1st Term',
    'grade_encoding_term2' => '2nd Term',
    'grade_encoding_term3' => '3rd Term',
    'payments'             => 'Payments',
];

/** Convert old Q1–Q4 keys to new term keys for backward compat reads. */
function normDeadlineType(string $t): string {
    $map = [
        'grade_encoding_q1' => 'grade_encoding_term1',
        'grade_encoding_q2' => 'grade_encoding_term2',
        'grade_encoding_q3' => 'grade_encoding_term3',
        'grade_encoding_q4' => 'grade_encoding_term3', // Q4 collapsed into 3rd term
    ];
    return $map[$t] ?? $t;
}

function requireAdmin(): int {
    if (empty($_SESSION['admin_id'])) {
        out(false, 'Unauthorized.');
    }
    $sessionId = (int)$_SESSION['admin_id'];

    /*
     * BUG FIX: The old code only searched the `admins` table for the session ID.
     * If the logged-in user is stored in a different role table (e.g. a super_admin
     * whose profile row was accidentally deleted from `admins`), the lookup failed
     * and the portal refused access — even though the session was valid.
     *
     * FIX: Resolve the session's admin_id to a user_id by checking ALL role tables,
     * then verify the role from the users table. Both 'admin' and 'super_admin' are
     * allowed to use this portal.
     */
    $roleTableMap = [
        'admins'       => 'admins',
        'teachers'     => 'teachers',
        'registrars'   => 'registrars',
        'cashiers'     => 'cashiers',
        'principals'   => 'principals',
        'coordinators' => 'coordinators',
    ];

    $userId = null;
    foreach ($roleTableMap as $tableName => $_) {
        try {
            $stmt = db()->prepare("SELECT user_id FROM `{$tableName}` WHERE id = ? LIMIT 1");
            $stmt->execute([$sessionId]);
            $r = $stmt->fetch();
            if ($r) { $userId = (int)$r['user_id']; break; }
        } catch (PDOException $e) { /* table might not exist yet */ }
    }

    // Fallback: session might store a users.id directly (super_admin accounts)
    if ($userId === null) {
        $stmt = db()->prepare("SELECT id, role FROM users WHERE id = ? LIMIT 1");
        $stmt->execute([$sessionId]);
        $u = $stmt->fetch();
        if ($u && in_array($u['role'], ['admin', 'super_admin'], true)) {
            return $sessionId; // already a valid user id
        }
        out(false, 'Unauthorized.');
    }

    $stmt = db()->prepare('SELECT role FROM users WHERE id = ? LIMIT 1');
    $stmt->execute([$userId]);
    $user = $stmt->fetch();

    if (!$user || !in_array($user['role'], ['admin', 'super_admin'], true)) {
        out(false, 'Access denied. Only administrators may use this portal.');
    }
    return $sessionId;
}

// ─── CAFETERIA MENU IMAGE UPLOAD HELPER ─────────────────────
/**
 * Handles an optional $_FILES['image'] upload for a menu product.
 * Returns the relative path to store in DB, or null if no file was sent.
 * Throws a RuntimeException (caught by caller) on validation failure.
 */
function handleMenuImageUpload(): ?string {
    if (empty($_FILES['image']) || $_FILES['image']['error'] === UPLOAD_ERR_NO_FILE) {
        return null;
    }
    $file = $_FILES['image'];
    if ($file['error'] !== UPLOAD_ERR_OK) {
        throw new RuntimeException('Image upload failed. Please try again.');
    }
    if ($file['size'] > 5 * 1024 * 1024) {
        throw new RuntimeException('Image must be 5MB or smaller.');
    }
    $allowed = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp', 'image/gif' => 'gif'];
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime  = finfo_file($finfo, $file['tmp_name']);
    finfo_close($finfo);
    if (!isset($allowed[$mime])) {
        throw new RuntimeException('Only JPG, PNG, WEBP, or GIF images are allowed.');
    }
    $dir = __DIR__ . '/uploads/menu';
    if (!is_dir($dir)) mkdir($dir, 0755, true);
    $filename = 'menu_' . bin2hex(random_bytes(8)) . '.' . $allowed[$mime];
    if (!move_uploaded_file($file['tmp_name'], $dir . '/' . $filename)) {
        throw new RuntimeException('Failed to save uploaded image.');
    }
    return 'uploads/menu/' . $filename;
}

function logAudit(int $adminId, string $action, string $table, int $recordId,
                  ?array $old = null, ?array $new = null): void {
    $ip        = $_SERVER['HTTP_X_FORWARDED_FOR'] ?? $_SERVER['HTTP_X_REAL_IP'] ?? $_SERVER['REMOTE_ADDR'] ?? null;
    // If X-Forwarded-For contains multiple IPs (proxy chain), take the first (client IP)
    if ($ip && strpos($ip, ',') !== false) {
        $ip = trim(explode(',', $ip)[0]);
    }
    // Normalize IPv4-mapped IPv6 (::ffff:x.x.x.x → x.x.x.x) for cleaner display
    if ($ip && preg_match('/^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/', $ip, $m)) {
        $ip = $m[1];
    }
    $userAgent = $_SERVER['HTTP_USER_AGENT'] ?? null;
    // Try to add user_agent column if it doesn't exist yet (safe ALTER)
    try {
        db()->exec("ALTER TABLE audit_logs ADD COLUMN user_agent TEXT DEFAULT NULL");
    } catch (\Exception $e) {
        // Column already exists — ignore
    }
    try {
        db()->prepare(
            'INSERT INTO audit_logs (admin_id, action, table_name, record_id, old_values, new_values, ip_address, user_agent)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        )->execute([
            $adminId, $action, $table, $recordId,
            $old ? json_encode($old) : null,
            $new  ? json_encode($new)  : null,
            $ip, $userAgent
        ]);
    } catch (\Exception $e) {
        // Fallback without user_agent if column still doesn't exist
        db()->prepare(
            'INSERT INTO audit_logs (admin_id, action, table_name, record_id, old_values, new_values, ip_address)
             VALUES (?, ?, ?, ?, ?, ?, ?)'
        )->execute([
            $adminId, $action, $table, $recordId,
            $old ? json_encode($old) : null,
            $new  ? json_encode($new)  : null,
            $ip
        ]);
    }
}

// ─── CAFETERIA INVENTORY — EXTENDED SCHEMA (self-healing) ───
/**
 * Adds restock/expiry tracking columns to cafeteria_inventory and creates
 * the restock/sales log tables the first time they're needed. Safe to call
 * on every request — each statement is wrapped so an "already exists"
 * error is silently ignored.
 */
function ensureCafeteriaInventoryExtras(): void {
    $alters = [
        "ALTER TABLE cafeteria_inventory ADD COLUMN last_restock_date DATE DEFAULT NULL",
        "ALTER TABLE cafeteria_inventory ADD COLUMN expiration_date DATE DEFAULT NULL",
        "ALTER TABLE cafeteria_inventory ADD COLUMN next_restock_date DATE DEFAULT NULL",
        "ALTER TABLE cafeteria_inventory ADD COLUMN restock_interval_days INT DEFAULT 7",
    ];
    foreach ($alters as $sql) {
        try { db()->exec($sql); } catch (\Exception $e) { /* column already exists */ }
    }

    try {
        db()->exec(
            "CREATE TABLE IF NOT EXISTS cafeteria_restock_log (
                id INT AUTO_INCREMENT PRIMARY KEY,
                product_id INT NOT NULL,
                quantity_added INT NOT NULL,
                received_date DATE NOT NULL,
                expiration_date DATE DEFAULT NULL,
                next_restock_date DATE DEFAULT NULL,
                cost_per_unit DECIMAL(10,2) DEFAULT NULL,
                notes VARCHAR(255) DEFAULT NULL,
                restocked_by INT DEFAULT NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX (product_id)
            )"
        );
    } catch (\Exception $e) { /* already exists */ }

    try {
        db()->exec(
            "CREATE TABLE IF NOT EXISTS cafeteria_sales_log (
                id INT AUTO_INCREMENT PRIMARY KEY,
                product_id INT NOT NULL,
                quantity_sold INT NOT NULL,
                unit_price DECIMAL(10,2) NOT NULL,
                total_amount DECIMAL(10,2) NOT NULL,
                reason VARCHAR(30) NOT NULL DEFAULT 'sale',
                notes VARCHAR(255) DEFAULT NULL,
                recorded_by INT DEFAULT NULL,
                sold_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX (product_id)
            )"
        );
    } catch (\Exception $e) { /* already exists */ }

    // Non-sale stock removals (spoilage, damage, expiry, miscount correction).
    // Kept separate from cafeteria_sales_log so "Sales History" only ever
    // reflects real revenue, while "Stock Adjustments" explains shrinkage.
    try {
        db()->exec(
            "CREATE TABLE IF NOT EXISTS cafeteria_stock_adjustments (
                id INT AUTO_INCREMENT PRIMARY KEY,
                product_id INT NOT NULL,
                quantity_delta INT NOT NULL COMMENT 'negative = removed, positive = corrected upward',
                reason VARCHAR(30) NOT NULL DEFAULT 'other',
                notes VARCHAR(255) DEFAULT NULL,
                adjusted_by INT DEFAULT NULL,
                adjusted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX (product_id)
            )"
        );
    } catch (\Exception $e) { /* already exists */ }
}

// ─── SCHOOL YEAR STRICT VALIDATION (Fix #1) ─────────────────
/**
 * School year MUST span exactly current year → current year+1.
 * e.g. in 2026: only 2026-2027 is valid.
 * Both start_year == currentYear and end_year == currentYear+1 are required.
 */
function validateSchoolYearStrict(string $label, string $start, string $end): void {
    $currentYear = (int)date('Y');

    if (!preg_match('/^\d{4}-\d{4}$/', $label)) {
        out(false, 'Label must follow the format YYYY-YYYY (e.g. ' . $currentYear . '-' . ($currentYear+1) . ').');
    }

    $parts    = explode('-', $label);
    $lblStart = (int)$parts[0];
    $lblEnd   = (int)$parts[1];

    // Allow start year from current year up to current+2, must span exactly 1 year
    if ($lblEnd !== $lblStart + 1 || $lblStart < $currentYear || $lblStart > $currentYear + 2) {
        out(false, 'Invalid school year range. Start year must be between ' . $currentYear . ' and ' . ($currentYear + 2) . ', spanning exactly one year.');
    }

    $startYear = (int)date('Y', strtotime($start));
    $endYear   = (int)date('Y', strtotime($end));

    if ($startYear !== $lblStart || $endYear !== $lblEnd) {
        out(false, "Label '{$label}' does not match the start/end years ({$startYear}–{$endYear}).");
    }

    if (strtotime($end) <= strtotime($start)) {
        out(false, 'End date must be after start date.');
    }

    $monthsDiff = (($endYear - $startYear) * 12)
                + ((int)date('m', strtotime($end)) - (int)date('m', strtotime($start)));
    if ($monthsDiff > 14) {
        out(false, 'A school year cannot span more than 14 months.');
    }
}

// ─── AUTO-GENERATE SCHOOL EMAIL (Fix #5) ────────────────────
function generateSchoolEmail(string $firstName, string $lastName, string $role): string {
    $fn   = strtolower(preg_replace('/\s+/', '', $firstName));
    $ln   = strtolower(preg_replace('/\s+/', '', $lastName));
    $role = strtolower($role);
    return "{$fn}{$ln}@sjc{$role}.edu.ph";
}

/**
 * Generate a unique school email that does NOT already exist in the users table.
 * If the base email is taken by a different user, appends a numeric suffix (e.g. jdelacruz2@...).
 *
 * @param string   $firstName
 * @param string   $lastName
 * @param string   $role
 * @param int|null $excludeUserId  — user_id to exclude from the duplicate check (for updates)
 */
function generateUniqueSchoolEmail(string $firstName, string $lastName, string $role, ?int $excludeUserId = null): string {
    $base  = generateSchoolEmail($firstName, $lastName, $role);
    $email = $base;
    $i     = 2;

    while (true) {
        $sql    = 'SELECT COUNT(*) FROM users WHERE (school_email = ? OR email = ?)';
        $params = [$email, $email];
        if ($excludeUserId !== null) {
            $sql    .= ' AND id != ?';
            $params[] = $excludeUserId;
        }
        $count = (int)db()->prepare($sql)->execute($params) ? db()->prepare($sql) : null;
        // Re-execute cleanly
        $stmt = db()->prepare($sql);
        $stmt->execute($params);
        $count = (int)$stmt->fetchColumn();

        if ($count === 0) break;

        // Append suffix before @
        $parts = explode('@', $base, 2);
        $email = $parts[0] . $i . '@' . $parts[1];
        $i++;
        if ($i > 999) break; // safety valve
    }

    return $email;
}

// ─── LOCK GUARD ─────────────────────────────────────────────
/**
 * Check if the active (or given) school year is finalized.
 * Calls out() and halts if locked.
 */
function lockGuard(?int $syId = null): void {
    if ($syId) {
        $row = db()->prepare('SELECT is_finalized FROM school_years WHERE id=?');
        $row->execute([$syId]);
    } else {
        $row = db()->query('SELECT is_finalized FROM school_years WHERE is_active=1 LIMIT 1');
    }
    $sy = $row->fetch();
    if ($sy && !empty($sy['is_finalized'])) {
        out(false, 'This school year is locked and cannot be modified.');
    }
}

// ─── AUTO-GENERATE SUBJECT CODE ─────────────────────────────
/**
 * Generates a subject code like Math-07, TLE-08 from a name + grade level.
 * Uses abbreviation from name (first letters of each word, max 4 chars).
 */
function generateSubjectCode(string $name, int $gradeLevel): string {
    $words = preg_split('/[\s\-\/]+/', strtoupper(trim($name)));
    $abbr = '';
    foreach ($words as $w) {
        if (strlen($abbr) >= 4) break;
        $abbr .= substr($w, 0, 1);
    }
    if (strlen($abbr) < 2 && strlen($words[0]) >= 4) {
        $abbr = substr($words[0], 0, 4);
    }
    $grade = str_pad((string)$gradeLevel, 2, '0', STR_PAD_LEFT);
    return strtoupper($abbr) . '-' . $grade;
}

// ─── CREDENTIALS EMAIL ──────────────────────────────────────
/**
 * Send account credentials (school email + system-generated password)
 * to the faculty/staff member's work/personal email after account creation.
 * Uses same brand design as the OTP email in login.php.
 */
function sendCredentialsEmail(
    string $toEmail,
    string $fullName,
    string $schoolEmail,
    string $tempPassword,
    string $role
): void {
    try {
        $mail = new PHPMailer(true);
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
        $mail->addAddress($toEmail);

        $logoSrc   = 'https://i.imgur.com/kR21xJw.png';
        $roleLabel = ucfirst($role);
        $year      = date('Y');

        $mail->CharSet  = 'UTF-8';
        $mail->isHTML(true);
        $mail->Subject  = '[SJC Portal] Your New Account Credentials';
        $mail->Body     = buildCredentialsEmailHtml($fullName, $schoolEmail, $tempPassword, $roleLabel, $year, $logoSrc);
        $mail->AltBody  = "Welcome to the SJC Portal, {$fullName}!\n\nYour account has been created.\nSchool Email: {$schoolEmail}\nTemporary Password: {$tempPassword}\n\nPlease log in and change your password immediately.\nKeep these credentials confidential.";

        $mail->send();
    } catch (\Exception $e) {
        // Non-fatal: account is already created; log the mail failure
        error_log('[adminclass] sendCredentialsEmail failed: ' . $e->getMessage());
    }
}

/**
 * Send a security notification email to the student when their account info is changed.
 */
function sendStudentAccountChangeEmail(
    string $toEmail,
    string $fullName,
    string $changedDateTime
): void {
    try {
        $mail = new PHPMailer(true);
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
        $mail->addAddress($toEmail);

        $mail->CharSet = 'UTF-8';
        $mail->isHTML(true);
        $mail->Subject  = '[SJC Portal] Student Account Information Changed';
        $mail->Body     = buildStudentChangeEmailHtml($fullName, $changedDateTime);
        $mail->AltBody  =
            "Dear {$fullName},\n\n" .
            "This is to inform you that changes were recently made to your student account information.\n\n" .
            "The following information was updated:\n" .
            "* Personal Email Address\n" .
            "Date and Time: {$changedDateTime}\n\n" .
            "If you requested or authorized this change, no further action is required.\n" .
            "If you did not request or recognize this change, please report the matter immediately to " .
            "the School Administration Office so that appropriate action can be taken.\n\n" .
            "Thank you for helping us keep your account information secure.\n\n" .
            "Regards,\nSchool Administration Office\nSaint Joseph College";

        $mail->send();
    } catch (\Exception $e) {
        error_log('[adminclass] sendStudentAccountChangeEmail failed: ' . $e->getMessage());
    }
}

/**
 * HTML email body for the student account change notification.
 */
function buildStudentChangeEmailHtml(string $fullName, string $changedDateTime): string {
    $safeName     = htmlspecialchars($fullName);
    $safeDateTime = htmlspecialchars($changedDateTime);
    $logoSrc      = 'https://i.imgur.com/kR21xJw.png';
    $year         = date('Y');

    $logoTag = '<img src="' . htmlspecialchars($logoSrc) . '"
                     alt="SJC Logo" width="60" height="60"
                     style="display:block;width:60px;height:60px;object-fit:contain;
                            border-radius:50%;background:rgba(255,255,255,0.07);
                            border:1.5px solid rgba(201,168,76,0.35);padding:4px;">';

    return <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>SJC Portal &#8212; Account Change Notice</title>
</head>
<body style="margin:0;padding:0;background-color:#f0ece6;-webkit-text-size-adjust:100%;">

  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background-color:#f0ece6;min-width:100%;">
    <tr>
      <td align="center" style="padding:36px 16px 48px;">

        <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
               style="max-width:560px;width:100%;background:#ffffff;border-radius:14px;
                      overflow:hidden;box-shadow:0 4px 32px rgba(26,0,0,0.13);">

          <!-- HEADER -->
          <tr>
            <td style="background:linear-gradient(160deg,#1a0000 0%,#3d0808 60%,#5c1010 100%);
                       padding:28px 36px 24px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td width="64" valign="middle" style="padding-right:16px;">{$logoTag}</td>
                  <td valign="middle">
                    <p style="margin:0 0 2px;font-family:Georgia,'Times New Roman',serif;
                               font-size:17px;font-weight:normal;letter-spacing:2.5px;
                               color:#c9a84c;line-height:1.2;">SAINT JOSEPH COLLEGE</p>
                    <p style="margin:0;font-family:Georgia,'Times New Roman',serif;
                               font-size:11px;letter-spacing:1.5px;color:rgba(201,168,76,0.65);">
                      SCHOOL MANAGEMENT SYSTEM</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- ALERT BANNER -->
          <tr>
            <td style="background:#fff3cd;border-left:4px solid #c9a84c;
                       padding:14px 36px;font-family:Arial,sans-serif;
                       font-size:13px;color:#7a5a00;">
              <strong>&#9888; Security Notice:</strong> Changes were made to your student account.
            </td>
          </tr>

          <!-- BODY -->
          <tr>
            <td style="padding:32px 36px 24px;font-family:Arial,sans-serif;">
              <p style="margin:0 0 10px;font-size:15px;color:#1a0000;font-weight:600;">
                Dear {$safeName},
              </p>
              <p style="margin:0 0 20px;font-size:14px;color:#444;line-height:1.7;">
                This is to inform you that changes were recently made to your student account
                information in the <strong style="color:#1a0000;">SJC School Portal</strong>.
              </p>

              <!-- Change detail box -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#f8f4ef;border:1px solid #e2d9cf;border-radius:10px;
                            margin-bottom:24px;overflow:hidden;">
                <tr>
                  <td style="background:#1a0000;padding:10px 20px;">
                    <p style="margin:0;font-family:Georgia,serif;font-size:12px;
                               letter-spacing:1.5px;color:#c9a84c;font-weight:normal;">
                      INFORMATION UPDATED
                    </p>
                  </td>
                </tr>
                <tr>
                  <td style="padding:18px 20px;">
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td style="font-size:13px;color:#555;padding-bottom:8px;width:40%;
                                   font-family:Arial,sans-serif;">Field</td>
                        <td style="font-size:13px;color:#1a0000;padding-bottom:8px;
                                   font-family:Arial,sans-serif;font-weight:600;">
                          Personal Email Address
                        </td>
                      </tr>
                      <tr>
                        <td style="font-size:13px;color:#555;font-family:Arial,sans-serif;">
                          Date &amp; Time</td>
                        <td style="font-size:13px;color:#1a0000;font-family:'Courier New',monospace;
                                   font-weight:600;">{$safeDateTime}</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <p style="margin:0 0 14px;font-size:14px;color:#444;line-height:1.7;">
                If you <strong>requested or authorized</strong> this change, no further action is required.
              </p>

              <!-- Alert action box -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#fff0f0;border:1.5px solid #e53935;border-radius:10px;
                            margin-bottom:24px;">
                <tr>
                  <td style="padding:16px 20px;">
                    <p style="margin:0 0 6px;font-size:13px;font-weight:700;color:#b71c1c;
                               font-family:Arial,sans-serif;">
                      &#128721; Did not authorize this change?
                    </p>
                    <p style="margin:0;font-size:13px;color:#c62828;line-height:1.6;
                               font-family:Arial,sans-serif;">
                      If you did <strong>not</strong> request or recognize this change, please
                      <strong>report the matter immediately</strong> to the School Administration Office
                      so that appropriate action can be taken.
                    </p>
                  </td>
                </tr>
              </table>

              <p style="margin:0;font-size:13px;color:#888;line-height:1.6;
                         border-top:1px solid #e8e2db;padding-top:18px;">
                Thank you for helping us keep your account information secure.
              </p>
            </td>
          </tr>

          <!-- FOOTER -->
          <tr>
            <td style="background:#1a0000;padding:20px 36px;text-align:center;">
              <p style="margin:0 0 4px;font-family:Georgia,serif;font-size:12px;
                         letter-spacing:1.5px;color:#c9a84c;">SCHOOL ADMINISTRATION OFFICE</p>
              <p style="margin:0;font-size:11px;color:rgba(255,255,255,0.45);
                         font-family:Arial,sans-serif;">
                Saint Joseph College &mdash; &copy; {$year}
              </p>
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


 /* Design mirrors the OTP email (buildOtpEmailHtml in login.php):
 *  • Deep maroon (#1a0000) header with gold (#c9a84c) accents
 *  • School logo via hosted URL
 *  • Inline styles only for maximum email client compatibility
 */
function buildCredentialsEmailHtml(
    string $fullName,
    string $schoolEmail,
    string $tempPassword,
    string $roleLabel,
    string $year,
    string $logoSrc
): string {

    $logoTag = $logoSrc !== ''
        ? '<img src="' . htmlspecialchars($logoSrc) . '"
                 alt="SJC Logo"
                 width="60" height="60"
                 style="display:block;width:60px;height:60px;object-fit:contain;
                        border-radius:50%;background:rgba(255,255,255,0.07);
                        border:1.5px solid rgba(201,168,76,0.35);padding:4px;">'
        : '';

    $safeName     = htmlspecialchars($fullName);
    $safeEmail    = htmlspecialchars($schoolEmail);
    $safePassword = htmlspecialchars($tempPassword);

    return <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  <title>SJC Portal &#8212; Account Credentials</title>
</head>
<body style="margin:0;padding:0;background-color:#f0ece6;-webkit-text-size-adjust:100%;mso-line-height-rule:exactly;">

  <!-- Outer wrapper -->
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
         style="background-color:#f0ece6;min-width:100%;">
    <tr>
      <td align="center" style="padding:36px 16px 48px;">

        <!-- Email card -->
        <table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0"
               style="max-width:560px;width:100%;background:#ffffff;border-radius:14px;
                      overflow:hidden;box-shadow:0 4px 32px rgba(26,0,0,0.13);">

          <!-- ═══════════ HEADER ═══════════ -->
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
              <!-- Gold rule -->
              <div style="height:1px;background:linear-gradient(90deg,rgba(201,168,76,0.7) 0%,rgba(201,168,76,0.1) 100%);margin-top:22px;"></div>
            </td>
          </tr>

          <!-- ═══════════ SUBJECT STRIP ═══════════ -->
          <tr>
            <td style="background:#f9f5ef;padding:14px 36px;
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
                      Account Credentials
                    </span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- ═══════════ BODY ═══════════ -->
          <tr>
            <td style="padding:40px 36px 36px;">

              <!-- Greeting -->
              <p style="margin:0 0 6px;font-family:Georgia,'Times New Roman',serif;
                         font-size:22px;color:#1a0000;font-weight:normal;line-height:1.3;">
                Welcome, {$safeName}!
              </p>
              <p style="margin:0 0 28px;font-family:Arial,sans-serif;font-size:13px;
                         color:#6b5f55;line-height:1.7;">
                Your account on the <strong style="color:#1a0000;">SJC Student&nbsp;&amp;&nbsp;Faculty Portal</strong>
                has been created by the System Administrator. Below are your login credentials.
                Please <strong style="color:#1a0000;">log in and change your password immediately</strong>
                for the security of your account.
              </p>

              <!-- Thin gold divider -->
              <div style="height:1px;background:linear-gradient(90deg,transparent,#d6c99a,transparent);
                           margin:0 0 24px;"></div>

              <!-- Credentials box -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#fdf9f2;border:1px solid #e8dfc8;border-radius:8px;
                            margin-bottom:28px;">
                <tr>
                  <td style="padding:24px 28px;">
                    <p style="margin:0 0 16px;font-family:Arial,sans-serif;font-size:12px;
                               font-weight:700;color:#1a0000;letter-spacing:1px;
                               text-transform:uppercase;">
                      Your Login Credentials
                    </p>

                    <!-- School Email row -->
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                           style="margin-bottom:12px;">
                      <tr>
                        <td width="130" valign="top"
                            style="font-family:Arial,sans-serif;font-size:12px;
                                   color:#9a8a78;padding-top:2px;">
                          School Email
                        </td>
                        <td valign="top"
                            style="font-family:'Courier New','Lucida Console',monospace;
                                   font-size:13px;font-weight:700;color:#1a0000;
                                   background:#fff;border:1.5px solid #d6c99a;
                                   border-radius:6px;padding:8px 14px;word-break:break-all;">
                          {$safeEmail}
                        </td>
                      </tr>
                    </table>

                    <!-- Password row -->
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td width="130" valign="top"
                            style="font-family:Arial,sans-serif;font-size:12px;
                                   color:#9a8a78;padding-top:2px;">
                          Temporary Password
                        </td>
                        <td valign="top"
                            style="font-family:'Courier New','Lucida Console',monospace;
                                   font-size:14px;font-weight:800;color:#1a0000;
                                   background:#fff;border:1.5px solid #d6c99a;
                                   border-radius:6px;padding:8px 14px;
                                   letter-spacing:2px;word-break:break-all;">
                          {$safePassword}
                        </td>
                      </tr>
                    </table>

                  </td>
                </tr>
              </table>

              <!-- How to use steps -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#fdf9f2;border:1px solid #e8dfc8;border-radius:8px;
                            margin-bottom:28px;">
                <tr>
                  <td style="padding:20px 24px;">
                    <p style="margin:0 0 12px;font-family:Arial,sans-serif;font-size:12px;
                               font-weight:700;color:#1a0000;letter-spacing:1px;
                               text-transform:uppercase;">
                      How to log in
                    </p>
                    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td width="22" valign="top" style="padding-top:1px;">
                          <span style="display:inline-block;width:18px;height:18px;line-height:18px;
                                       text-align:center;background:#1a0000;color:#c9a84c;
                                       font-family:Arial,sans-serif;font-size:10px;font-weight:700;
                                       border-radius:50%;">1</span>
                        </td>
                        <td style="padding-left:8px;font-family:Arial,sans-serif;font-size:12px;
                                   color:#5a4e46;line-height:1.6;">
                          Go to the <strong style="color:#1a0000;">SJC Portal</strong> login page.
                        </td>
                      </tr>
                      <tr><td colspan="2" style="padding:4px 0;"></td></tr>
                      <tr>
                        <td width="22" valign="top" style="padding-top:1px;">
                          <span style="display:inline-block;width:18px;height:18px;line-height:18px;
                                       text-align:center;background:#1a0000;color:#c9a84c;
                                       font-family:Arial,sans-serif;font-size:10px;font-weight:700;
                                       border-radius:50%;">2</span>
                        </td>
                        <td style="padding-left:8px;font-family:Arial,sans-serif;font-size:12px;
                                   color:#5a4e46;line-height:1.6;">
                          Enter your <strong style="color:#1a0000;">school email</strong> and the temporary password above.
                        </td>
                      </tr>
                      <tr><td colspan="2" style="padding:4px 0;"></td></tr>
                      <tr>
                        <td width="22" valign="top" style="padding-top:1px;">
                          <span style="display:inline-block;width:18px;height:18px;line-height:18px;
                                       text-align:center;background:#1a0000;color:#c9a84c;
                                       font-family:Arial,sans-serif;font-size:10px;font-weight:700;
                                       border-radius:50%;">3</span>
                        </td>
                        <td style="padding-left:8px;font-family:Arial,sans-serif;font-size:12px;
                                   color:#5a4e46;line-height:1.6;">
                          An OTP will be sent to <em>this email address</em>. Enter it to complete login.
                        </td>
                      </tr>
                      <tr><td colspan="2" style="padding:4px 0;"></td></tr>
                      <tr>
                        <td width="22" valign="top" style="padding-top:1px;">
                          <span style="display:inline-block;width:18px;height:18px;line-height:18px;
                                       text-align:center;background:#1a0000;color:#c9a84c;
                                       font-family:Arial,sans-serif;font-size:10px;font-weight:700;
                                       border-radius:50%;">4</span>
                        </td>
                        <td style="padding-left:8px;font-family:Arial,sans-serif;font-size:12px;
                                   color:#5a4e46;line-height:1.6;">
                          Change your password immediately from your profile settings.
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Security warning -->
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"
                     style="background:#fff5f5;border:1px solid #f0d0d0;border-left:4px solid #a81c1c;
                            border-radius:6px;">
                <tr>
                  <td style="padding:16px 20px;">
                    <p style="margin:0;font-family:Arial,sans-serif;font-size:12px;
                               color:#7a2020;line-height:1.7;">
                      <strong>&#9888; Security Notice &mdash;</strong>
                      Keep these credentials strictly confidential. Never share your password
                      with anyone, including SJC staff. The school will <em>never</em> ask for
                      your password by phone, chat, or email.
                      If you did not expect this email, contact the System Administrator immediately.
                    </p>
                  </td>
                </tr>
              </table>

            </td>
          </tr>

          <!-- ═══════════ FOOTER ═══════════ -->
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
        <!-- /Email card -->

      </td>
    </tr>
  </table>

</body>
</html>
HTML;
}


$action = post('action');

switch ($action) {

    // ════════════════════════════
    // SESSION
    // ════════════════════════════
    case 'get_session':
        if (empty($_SESSION['admin_id'])) {
            out(true, '', ['name' => 'Administrator', 'id' => 0]);
            break;
        }
        $sessionId = (int)$_SESSION['admin_id'];
        /*
         * BUG FIX: The old get_session only looked in the admins table.
         * Super-admin accounts (role=super_admin or admin in users table) may not
         * have a matching row in admins, so they would always show "Administrator"
         * and all their data would appear missing.
         *
         * FIX: Search all role tables for the session ID, then fall back to
         * users directly (for super_admin accounts).
         */
        $roleTableMap = ['admins','teachers','registrars','cashiers','principals','coordinators'];
        $displayName = null;
        foreach ($roleTableMap as $tbl) {
            try {
                $stmt = db()->prepare(
                    "SELECT t.first_name, t.last_name,
                            COALESCE(t.full_name, '') AS full_name
                     FROM `{$tbl}` t WHERE t.id = ? LIMIT 1"
                );
                $stmt->execute([$sessionId]);
                $r = $stmt->fetch();
                if ($r) {
                    $displayName = !empty($r['full_name'])
                        ? $r['full_name']
                        : trim(($r['first_name'] ?? '') . ' ' . ($r['last_name'] ?? ''));
                    break;
                }
            } catch (PDOException $e) { /* table may not exist */ }
        }
        // Fallback: look up the name directly from users table
        if (!$displayName) {
            $uStmt = db()->prepare('SELECT username FROM users WHERE id = ? LIMIT 1');
            $uStmt->execute([$sessionId]);
            $uRow = $uStmt->fetch();
            $displayName = $uRow ? ($uRow['username'] ?? 'Administrator') : 'Administrator';
        }
        out(true, '', [
            'name' => $displayName ?: 'Administrator',
            'id'   => $sessionId,
        ]);
        break;

    case 'logout':
        session_destroy();
        out(true, 'Logged out.');

    // ════════════════════════════
    // DASHBOARD
    // ════════════════════════════
    case 'get_dashboard_stats':
        requireAdmin();
        $pdo = db();

        $school_years    = $pdo->query('SELECT COUNT(*) FROM school_years')->fetchColumn();
        $active_sy       = $pdo->query('SELECT label FROM school_years WHERE is_active = 1 LIMIT 1')->fetchColumn();
        $total_sections  = $pdo->query('SELECT COUNT(*) FROM sections')->fetchColumn();
        $active_sections = $pdo->query("SELECT COUNT(*) FROM sections WHERE status = 'active'")->fetchColumn();
        $subjects        = $pdo->query('SELECT COUNT(*) FROM subjects WHERE is_active = 1 AND is_archived = 0')->fetchColumn();
        $admin_users     = $pdo->query('SELECT COUNT(*) FROM admins')->fetchColumn();

        // Deadlines: use datetime columns with fallback to date columns for old rows
        $deadlines = $pdo->query(
            'SELECT d.type, d.start_datetime, d.end_datetime,
             CASE
               WHEN NOW() < d.start_datetime THEN "upcoming"
               WHEN NOW() > d.end_datetime   THEN "closed"
               ELSE "open"
             END as status
             FROM system_deadlines d
             JOIN school_years sy ON sy.id = d.school_year_id AND sy.is_active = 1
             ORDER BY d.start_datetime ASC LIMIT 5'
        )->fetchAll();

        // Map legacy type names to new labels in output
        foreach ($deadlines as &$dl) {
            $key = normDeadlineType($dl['type']);
            $dl['type']         = $key;
            $dl['type_label']   = DEADLINE_TYPES[$key] ?? $key;
        }
        unset($dl);

        $audit = $pdo->query(
            'SELECT al.action, al.table_name, al.record_id, al.created_at
             FROM audit_logs al ORDER BY al.created_at DESC LIMIT 6'
        )->fetchAll();

        out(true, '', [
            'school_years'       => (int)$school_years,
            'active_sy_label'    => $active_sy ?: 'None',
            'total_sections'     => (int)$total_sections,
            'active_sections'    => (int)$active_sections,
            'subjects'           => (int)$subjects,
            'admin_users'        => (int)$admin_users,
            'upcoming_deadlines' => $deadlines,
            'recent_audit'       => $audit,
        ]);

    // ════════════════════════════
    // SCHOOL YEARS (Fix #1)
    // ════════════════════════════
    case 'get_school_years':
        requireAdmin();
        $rows = db()->query('SELECT * FROM school_years ORDER BY start_date DESC')->fetchAll();
        $today = date('Y-m-d');
        foreach ($rows as &$row) {
            if (!isset($row['status']) || $row['status'] === null) {
                // Derive status from flags for older rows
                if ($row['is_finalized']) {
                    $row['status'] = 'completed';
                } elseif ($row['is_active']) {
                    $row['status'] = 'active';
                } else {
                    $row['status'] = 'upcoming';
                }
            }
            // Always keep is_active + status in sync for the front-end
            if ($row['is_active'] && $row['status'] !== 'active') {
                $row['status'] = 'active';
            }
        }
        unset($row);
        out(true, '', $rows);

    case 'get_active_school_year':
        requireAdmin();
        $row = db()->query('SELECT * FROM school_years WHERE is_active = 1 LIMIT 1')->fetch();
        out(true, '', $row ?: null);

    case 'create_school_year': {
        $adminId    = requireAdmin();
        $label      = post('label');
        $start      = post('start_date');
        $end        = post('end_date');
        $confirmed  = (int)post('is_confirmed', '0'); // 1 = admin confirmed & locked

        requireField($label, 'Label');
        requireField($start, 'Start date');
        requireField($end,   'End date');

        validateSchoolYearStrict($label, $start, $end);

        // Strict duplicate label check — no two school years may share the same label
        $dupCheck = db()->prepare('SELECT id FROM school_years WHERE label = ? LIMIT 1');
        $dupCheck->execute([$label]);
        if ($dupCheck->fetch()) {
            out(false, "School year {$label} already exists. Duplicate school years are not allowed.");
        }

        // New school years are ALWAYS created inactive.
        // Activation is a separate, manual step by the admin.
        $active = 0;

        try {
            $stmt = db()->prepare(
                'INSERT INTO school_years (label, start_date, end_date, is_active, is_confirmed, created_by) VALUES (?,?,?,?,?,?)'
            );
            $stmt->execute([$label, $start, $end, $active, $confirmed, $adminId]);
            $id = db()->lastInsertId();
            logAudit($adminId, 'create', 'school_years', (int)$id, null, compact('label','start','end','active','confirmed'));
            out(true, 'School year created.', ['id' => $id, 'is_confirmed' => $confirmed]);
        } catch (PDOException $e) {
            out(false, str_contains($e->getMessage(), 'Duplicate')
                ? "School year {$label} already exists. Duplicate school years are not allowed."
                : 'Failed to create school year.');
        }
    }

    case 'update_school_year': {
        $adminId   = requireAdmin();
        $id        = (int)post('id');
        $label     = post('label');
        $start     = post('start_date');
        $end       = post('end_date');
        $confirmed = (int)post('is_confirmed', '0'); // 1 = locking after review

        requireField($label, 'Label');
        requireField($start, 'Start date');
        requireField($end,   'End date');

        // Block edit if finalized
        $lockCheck = db()->prepare('SELECT is_finalized, is_confirmed, end_date FROM school_years WHERE id=?');
        $lockCheck->execute([$id]);
        $lockRow = $lockCheck->fetch();
        if ($lockRow && !empty($lockRow['is_finalized'])) {
            out(false, 'This school year is finalized and cannot be modified.');
        }
        // Block edit if confirmed-locked AND end_date hasn't passed yet
        if ($lockRow && !empty($lockRow['is_confirmed']) && date('Y-m-d') < $lockRow['end_date']) {
            out(false, 'This school year is locked until ' . $lockRow['end_date'] . ' and cannot be modified.');
        }

        validateSchoolYearStrict($label, $start, $end);

        // Duplicate label check — ensure the label isn't used by a different school year
        $dupCheck = db()->prepare('SELECT id FROM school_years WHERE label = ? AND id != ? LIMIT 1');
        $dupCheck->execute([$label, $id]);
        if ($dupCheck->fetch()) {
            out(false, "School year {$label} already exists. Duplicate school years are not allowed.");
        }

        $oldStmt = db()->prepare('SELECT * FROM school_years WHERE id=?');
        $oldStmt->execute([$id]);
        $oldRow = $oldStmt->fetch();

        db()->prepare('UPDATE school_years SET label=?, start_date=?, end_date=?, is_confirmed=? WHERE id=?')
            ->execute([$label, $start, $end, $confirmed, $id]);
        logAudit($adminId, 'update', 'school_years', $id, $oldRow, compact('label','start','end','confirmed'));
        out(true, 'Updated.');
    }

    case 'set_active_school_year': {
        $adminId = requireAdmin();
        $id      = (int)post('id');

        $target = db()->prepare('SELECT * FROM school_years WHERE id=?');
        $target->execute([$id]);
        $targetRow = $target->fetch();
        if (!$targetRow) out(false, 'School year not found.');
        if (!empty($targetRow['is_finalized'])) {
            out(false, 'Cannot activate a finalized/completed school year.');
        }
        // Block activating a SY whose end_date has already passed
        if (date('Y-m-d') > $targetRow['end_date']) {
            out(false, 'Cannot activate S.Y. ' . $targetRow['label'] . ' — its end date (' . $targetRow['end_date'] . ') has already passed. Mark it completed instead.');
        }

        // Deactivate all, activate target, update status column on all rows
        db()->prepare('UPDATE school_years SET is_active=0, status=CASE
            WHEN is_finalized=1 THEN "completed"
            WHEN end_date < CURDATE() THEN "completed"
            ELSE "upcoming"
          END')->execute();
        db()->prepare('UPDATE school_years SET is_active=1, status="active" WHERE id=?')->execute([$id]);

        logAudit($adminId, 'activate', 'school_years', $id, null, ['label' => $targetRow['label'], 'status' => 'active']);
        out(true, 'S.Y. ' . $targetRow['label'] . ' is now active.');
    }

    /**
     * Auto-advance to the next upcoming school year.
     * Intended to be called by a daily cron job or scheduled task.
     * Finds the next 'upcoming' SY with the earliest start_date after
     * the current active SY's end_date, and activates it.
     */
    case 'auto_advance_school_year': {
        $adminId = requireAdmin();

        $currentSY = db()->query(
            "SELECT * FROM school_years WHERE is_active=1 LIMIT 1"
        )->fetch();

        if (!$currentSY) out(false, 'No active school year to advance from.');

        // Only advance once the end date has passed
        if (date('Y-m-d') <= $currentSY['end_date']) {
            out(false, 'Current school year S.Y. ' . $currentSY['label'] . ' has not ended yet (ends ' . $currentSY['end_date'] . ').');
        }

        // Mark current SY as completed
        db()->prepare(
            "UPDATE school_years SET is_active=0, status='completed', is_finalized=0 WHERE id=?"
        )->execute([$currentSY['id']]);

        // Find next eligible upcoming SY
        $nextStmt = db()->prepare(
            "SELECT * FROM school_years
             WHERE is_finalized=0 AND is_active=0
               AND (status='upcoming' OR status IS NULL)
               AND start_date > ?
             ORDER BY start_date ASC LIMIT 1"
        );
        $nextStmt->execute([$currentSY['end_date']]);
        $nextSY = $nextStmt->fetch();

        if (!$nextSY) {
            error_log('[school_year] Auto-advance: no upcoming school year found after ' . $currentSY['end_date']);
            out(false, 'S.Y. ' . $currentSY['label'] . ' has been marked completed, but no upcoming school year was found to activate. Please create the next school year.');
        }

        // Activate the next SY
        db()->prepare(
            "UPDATE school_years SET is_active=1, status='active' WHERE id=?"
        )->execute([$nextSY['id']]);

        logAudit($adminId, 'activate', 'school_years', $nextSY['id'],
            ['previous_sy' => $currentSY['label']],
            ['label' => $nextSY['label'], 'auto_advance' => true]);

        out(true, 'Auto-advanced: S.Y. ' . $currentSY['label'] . ' completed → S.Y. ' . $nextSY['label'] . ' is now active.', [
            'completed' => $currentSY['label'],
            'activated' => $nextSY['label'],
        ]);
    }

    case 'finalize_school_year': {
        $adminId = requireAdmin();
        $id      = (int)post('id');

        $row = db()->prepare('SELECT * FROM school_years WHERE id=?');
        $row->execute([$id]);
        $sy = $row->fetch();
        if (!$sy) out(false, 'School year not found.');
        if (!empty($sy['is_finalized'])) {
            out(false, 'This school year is already finalized.');
        }
        // Block if current date is before end_date
        if (date('Y-m-d') < $sy['end_date']) {
            out(false, 'Cannot finalize before the school year ends. End date: ' . $sy['end_date']);
        }

        db()->prepare('UPDATE school_years SET is_finalized=1, is_active=0 WHERE id=?')->execute([$id]);
        logAudit($adminId, 'finalize', 'school_years', $id, $sy, ['is_finalized' => 1]);
        out(true, 'School year finalized and locked.');
    }

    // ════════════════════════════
    // GRADE LEVELS
    // ════════════════════════════
    case 'get_grade_levels':
        requireAdmin();
        $rows = db()->query(
            'SELECT gl.*, (SELECT COUNT(*) FROM sections s WHERE s.grade_level_id = gl.id) as section_count
             FROM grade_levels gl WHERE gl.is_active = 1 ORDER BY gl.level'
        )->fetchAll();
        out(true, '', $rows);

    // ════════════════════════════
    // SECTIONS / CLASS MANAGEMENT
    // ════════════════════════════
    case 'get_sections_by_grade': {
        requireAdmin();
        $syRow = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        $syId  = $syRow ? $syRow['id'] : null;
        $grades = db()->query('SELECT * FROM grade_levels WHERE is_active=1 ORDER BY level')->fetchAll();
        $result = [];
        foreach ($grades as $g) {
            $stmt = db()->prepare(
                'SELECT s.id, s.name, s.status, s.room,
                        COALESCE(ssy.capacity, 40)                              AS capacity,
                        COALESCE(ssy.enrolled_count, 0)                         AS enrolled_count,
                        COALESCE(ssy.adviser_id, NULL)                          AS adviser_id,
                        TRIM(CONCAT(t.first_name, " ", COALESCE(t.last_name, ""))) AS adviser_name,
                        ssy.status                                              AS sy_status
                 FROM sections s
                 LEFT JOIN section_school_years ssy ON ssy.section_id = s.id AND ssy.school_year_id = ?
                 LEFT JOIN teachers t ON t.id = ssy.adviser_id
                 WHERE s.grade_level_id = ?
                 ORDER BY s.name'
            );
            $stmt->execute([$syId, $g['id']]);
            $result[$g['id']] = [
                'level'        => $g['level'],
                'display_name' => $g['display_name'],
                'sections'     => $stmt->fetchAll(),
            ];
        }
        out(true, '', $result);
    }

    case 'get_section_detail': {
        requireAdmin();
        $id    = (int)post('id');
        $syRow = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        $syId  = $syRow ? $syRow['id'] : null;
        $stmt  = db()->prepare(
            'SELECT s.*, ssy.capacity, ssy.enrolled_count, ssy.adviser_id, ssy.status as sy_status,
                    TRIM(CONCAT(COALESCE(t.first_name,\'\'), \' \', COALESCE(t.last_name,\'\'))) AS adviser_name
             FROM sections s
             LEFT JOIN section_school_years ssy ON ssy.section_id=s.id AND ssy.school_year_id=?
             LEFT JOIN teachers t ON t.id=ssy.adviser_id
             WHERE s.id=?'
        );
        $stmt->execute([$syId, $id]);
        out(true, '', $stmt->fetch());
    }

    case 'create_section': {
        $adminId        = requireAdmin();
        $grade_level_id = (int)post('grade_level_id');
        $name           = post('name');
        $capacity       = (int)post('capacity', '40');
        $adviser_id     = post('adviser_id') ?: null;
        $school_year_id = (int)post('school_year_id');

        requireField($name, 'Section name');
        if (!$grade_level_id || !$school_year_id) out(false, 'Missing required fields.');
        lockGuard($school_year_id);

        /*
         * BUG FIX: Ensure sections.id has AUTO_INCREMENT. Without it, every INSERT
         * returns lastInsertId() = 0, causing every new section to share id = 0.
         * This means the duplicate-name check passes (different grade_level_id values
         * look unique) but all rows land on id = 0, and later archive/update
         * operations by id affect ALL sections at once.
         *
         * This ALTER is a safe no-op if AUTO_INCREMENT is already present.
         */
        try {
            db()->exec("ALTER TABLE `sections` MODIFY `id` INT(11) NOT NULL AUTO_INCREMENT");
        } catch (PDOException $e) { /* already correct — ignore */ }

        // Strict duplicate check: same section name in the same grade level is forbidden
        $dupCheck = db()->prepare(
            'SELECT s.id FROM sections s
             WHERE s.grade_level_id = ? AND LOWER(TRIM(s.name)) = LOWER(TRIM(?))
             LIMIT 1'
        );
        $dupCheck->execute([$grade_level_id, $name]);
        if ($dupCheck->fetch()) {
            out(false, "Section \"{$name}\" already exists in this grade level. Duplicate section names within the same grade are not allowed.");
        }

        try {
            db()->beginTransaction();
            $s = db()->prepare('INSERT INTO sections (grade_level_id, name) VALUES (?,?)');
            $s->execute([$grade_level_id, $name]);
            $sectionId = (int)db()->lastInsertId();

            /*
             * BUG FIX: Guard against the AUTO_INCREMENT being missing at runtime.
             * If lastInsertId() still returns 0 after the ALTER above failed silently,
             * bail out rather than inserting a corrupt id=0 row.
             */
            if ($sectionId <= 0) {
                db()->rollBack();
                out(false, 'Section could not be created: database auto-increment is not configured on the sections table. Please run the schema fix (ALTER TABLE sections MODIFY id INT NOT NULL AUTO_INCREMENT) and try again.');
            }

            $ssy = db()->prepare(
                'INSERT INTO section_school_years (section_id, school_year_id, capacity, adviser_id, status)
                 VALUES (?,?,?,?,\'open\')'
            );
            $ssy->execute([$sectionId, $school_year_id, $capacity, $adviser_id]);
            db()->commit();
            logAudit($adminId, 'create', 'sections', $sectionId, null,
                compact('grade_level_id','name','capacity','school_year_id'));
            out(true, 'Section created.', ['id' => $sectionId]);
        } catch (PDOException $e) {
            db()->rollBack();
            out(false, str_contains($e->getMessage(),'Duplicate')
                ? "Section \"{$name}\" already exists in this grade."
                : 'Failed to create section: ' . $e->getMessage());
        }
    }

    case 'delete_section': {
        $adminId = requireAdmin();
        $id      = (int)post('id');
        if (!$id) out(false, 'Missing section ID.');

        // Fetch section to confirm it exists
        $row = db()->prepare('SELECT id, name, grade_level_id FROM sections WHERE id=?');
        $row->execute([$id]);
        $section = $row->fetch();
        if (!$section) out(false, 'Section not found.');

        try {
            db()->beginTransaction();
            // Get all section_school_years IDs for this section
            $ssyStmt = db()->prepare('SELECT id FROM section_school_years WHERE section_id=?');
            $ssyStmt->execute([$id]);
            $ssyIds = $ssyStmt->fetchAll(PDO::FETCH_COLUMN);
            // Clear section assignment from enrollments (correct schema: enrollments.section_sy_id)
            if (!empty($ssyIds)) {
                $placeholders = implode(',', array_fill(0, count($ssyIds), '?'));
                db()->prepare("UPDATE enrollments SET section_sy_id=NULL WHERE section_sy_id IN ($placeholders)")
                    ->execute($ssyIds);
                // Also clear section_sy_id from student_profiles if present
                db()->prepare("UPDATE student_profiles SET section_sy_id=NULL WHERE section_sy_id IN ($placeholders)")
                    ->execute($ssyIds);
            }
            // Remove section_school_years rows
            db()->prepare('DELETE FROM section_school_years WHERE section_id=?')->execute([$id]);
            // Delete the section itself
            db()->prepare('DELETE FROM sections WHERE id=?')->execute([$id]);
            db()->commit();
            logAudit($adminId, 'delete', 'sections', $id, $section, null);
            out(true, 'Section permanently deleted.');
        } catch (PDOException $e) {
            db()->rollBack();
            out(false, 'Failed to delete section: ' . $e->getMessage());
        }
    }

    case 'update_section': {
        $adminId    = requireAdmin();
        lockGuard();
        $id         = (int)post('id');
        $name       = post('name');
        $capacity   = (int)post('capacity');
        $adviser_id = post('adviser_id') ?: null;

        requireField($name, 'Section name');

        $old = db()->prepare('SELECT * FROM sections WHERE id=?');
        $old->execute([$id]);
        $oldRow = $old->fetch();
        db()->prepare('UPDATE sections SET name=? WHERE id=?')->execute([$name, $id]); // room excluded intentionally — managed by Room Management only
        $syRow = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        if ($syRow) {
            db()->prepare('UPDATE section_school_years SET capacity=?, adviser_id=? WHERE section_id=? AND school_year_id=?')
                ->execute([$capacity, $adviser_id, $id, $syRow['id']]);
        }
        logAudit($adminId, 'update', 'sections', $id, $oldRow, compact('name','capacity','adviser_id'));
        out(true, 'Section updated.');
    }

    case 'archive_section': {
        $adminId = requireAdmin();
        lockGuard();
        $id      = (int)post('id');

        try {
            db()->beginTransaction();

            // Capture old room value for audit before clearing it
            $secRow = db()->prepare('SELECT room FROM sections WHERE id = ? LIMIT 1');
            $secRow->execute([$id]);
            $oldRoom = ($secRow->fetch() ?: [])['room'] ?? null;

            // Clear student section assignments linked to this section
            $ssyStmt = db()->prepare('SELECT id FROM section_school_years WHERE section_id=?');
            $ssyStmt->execute([$id]);
            $ssyIds = $ssyStmt->fetchAll(PDO::FETCH_COLUMN);
            if (!empty($ssyIds)) {
                $placeholders = implode(',', array_fill(0, count($ssyIds), '?'));
                db()->prepare("UPDATE enrollments SET section_sy_id=NULL WHERE section_sy_id IN ($placeholders)")
                    ->execute($ssyIds);
                db()->prepare("UPDATE student_profiles SET section_sy_id=NULL WHERE section_sy_id IN ($placeholders)")
                    ->execute($ssyIds);
            }

            // Archive the section and clear any room assignment so Room Management stays in sync
            db()->prepare("UPDATE sections SET status='archived', room=NULL WHERE id=?")->execute([$id]);

            db()->commit();
            logAudit($adminId, 'archive', 'sections', $id, ['room' => $oldRoom], ['status' => 'archived', 'room' => null]);
            out(true, 'Section archived.');
        } catch (PDOException $e) {
            db()->rollBack();
            out(false, 'Failed to archive section: ' . $e->getMessage());
        }
    }

    case 'activate_section': {
        $adminId = requireAdmin();
        lockGuard();
        $id      = (int)post('id');
        db()->prepare("UPDATE sections SET status='active' WHERE id=?")->execute([$id]);
        logAudit($adminId, 'activate', 'sections', $id);
        out(true, 'Section activated.');
    }

    // ════════════════════════════
    // SECTION STUDENTS
    // ════════════════════════════

    /**
     * Get students currently assigned to this section (via student_profiles.section_sy_id).
     */
    case 'get_section_students': {
        requireAdmin();
        $sectionId = (int)post('section_id');

        // Get active school year's section_school_years.id
        $syRow  = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        $syId   = $syRow ? $syRow['id'] : null;
        if (!$syId) out(true, '', []);

        $ssyRow = db()->prepare('SELECT id FROM section_school_years WHERE section_id=? AND school_year_id=? LIMIT 1');
        $ssyRow->execute([$sectionId, $syId]);
        $ssy    = $ssyRow->fetch();
        if (!$ssy) out(true, '', []);

        $stmt = db()->prepare(
            'SELECT s.id AS student_id, s.first_name, s.middle_name, s.last_name,
                    s.lrn, s.registration_status,
                    gl.display_name AS grade_display
             FROM   students s
             JOIN   student_profiles sp ON sp.student_id = s.id
             JOIN   grade_levels gl      ON gl.id = s.grade_level_id
             WHERE  sp.section_sy_id = ?
               AND  sp.school_year_id = ?
             ORDER BY s.last_name, s.first_name'
        );
        $stmt->execute([$ssy['id'], $syId]);
        out(true, '', $stmt->fetchAll());
    }

    /**
     * Get registered students eligible to be added to this section:
     *  - registration_status IN (enrolled, docs_submitted, verified)
     *  - Not already assigned to any section this school year
     *  - Grade level matches section's grade level
     */
    case 'get_available_students_for_section': {
        requireAdmin();
        $sectionId = (int)post('section_id');

        $syRow = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        $syId  = $syRow ? $syRow['id'] : null;
        if (!$syId) out(true, '', []);

        // Get section's grade level AND its section_school_years id
        $secRow = db()->prepare(
            'SELECT s.grade_level_id, ssy.id AS ssy_id
             FROM sections s
             LEFT JOIN section_school_years ssy ON ssy.section_id = s.id AND ssy.school_year_id = ?
             WHERE s.id = ?'
        );
        $secRow->execute([$syId, $sectionId]);
        $sec = $secRow->fetch();
        if (!$sec) out(false, 'Section not found.');

        $ssyId = $sec['ssy_id'] ?? null;

        /*
         * Admin section management: only show ENROLLED students.
         * - registration_status must be 'enrolled' (fully confirmed by registrar)
         * - pending / registered / verified students are NOT visible to admin;
         *   only the registrar portal may see those statuses.
         * - Still exclude students already assigned to a DIFFERENT section this year.
         */
        $stmt = db()->prepare(
            "SELECT s.id, s.first_name, s.middle_name, s.last_name,
                    s.lrn, s.registration_status,
                    gl.display_name AS grade_display
             FROM   students s
             JOIN   grade_levels gl ON gl.id = s.grade_level_id
             LEFT JOIN student_profiles sp
                    ON sp.student_id    = s.id
                   AND sp.school_year_id = ?
             WHERE  s.grade_level_id = ?
               AND  s.registration_status = 'enrolled'
               AND  s.is_archived = 0
               AND  (
                     sp.id IS NULL
                  OR sp.section_sy_id IS NULL
                  OR sp.section_sy_id = 0
               )
             ORDER BY s.last_name, s.first_name"
        );
        $stmt->execute([$syId, $sec['grade_level_id']]);
        out(true, '', $stmt->fetchAll());
    }

    /**
     * Assign one or more students to a section.
     * Updates BOTH student_profiles.section_sy_id AND enrollments.section_sy_id
     * so that the grading system and any query using enrollments as the
     * authoritative source stays in sync with the admin panel assignment.
     */
    case 'assign_students_to_section': {
        $adminId    = requireAdmin();
        lockGuard();
        $sectionId  = (int)post('section_id');
        $rawIds     = post('student_ids');
        $studentIds = array_filter(array_map('intval', explode(',', $rawIds)));
        if (!$sectionId || empty($studentIds)) out(false, 'Missing required fields.');

        $syRow = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        $syId  = $syRow ? $syRow['id'] : null;
        if (!$syId) out(false, 'No active school year.');

        $ssyRow = db()->prepare('SELECT id, capacity, enrolled_count FROM section_school_years WHERE section_id=? AND school_year_id=? LIMIT 1');
        $ssyRow->execute([$sectionId, $syId]);
        $ssy = $ssyRow->fetch();
        if (!$ssy) out(false, 'Section not found for the active school year.');

        $slotsLeft = (int)$ssy['capacity'] - (int)$ssy['enrolled_count'];
        if (count($studentIds) > $slotsLeft) {
            out(false, "Only {$slotsLeft} slot(s) available in this section.");
        }

        try {
            db()->beginTransaction();
            $ssyId    = (int)$ssy['id'];
            $assigned = 0;

            foreach ($studentIds as $sid) {
                // ── 1. Sync student_profiles ──────────────────────────────
                $spCheck = db()->prepare('SELECT id FROM student_profiles WHERE student_id=? AND school_year_id=? LIMIT 1');
                $spCheck->execute([$sid, $syId]);
                $sp = $spCheck->fetch();

                if ($sp) {
                    db()->prepare('UPDATE student_profiles SET section_sy_id=? WHERE id=?')
                        ->execute([$ssyId, $sp['id']]);
                } else {
                    db()->prepare('INSERT INTO student_profiles (student_id, school_year_id, section_sy_id) VALUES (?,?,?)')
                        ->execute([$sid, $syId, $ssyId]);
                }

                // ── 2. Sync enrollments (the authoritative source for grading) ──
                // Target the student's active/current enrollment for this school year.
                $enrCheck = db()->prepare(
                    'SELECT id FROM enrollments
                      WHERE student_id = ? AND school_year_id = ?
                        AND status NOT IN (\'unregistered\', \'archived\')
                      ORDER BY id DESC LIMIT 1'
                );
                $enrCheck->execute([$sid, $syId]);
                $enr = $enrCheck->fetch();

                if ($enr) {
                    db()->prepare('UPDATE enrollments SET section_sy_id=? WHERE id=?')
                        ->execute([$ssyId, $enr['id']]);
                }
                // If no active enrollment row exists yet we still update student_profiles
                // above — the enrollment row will pick up section_sy_id when it is created.

                $assigned++;
            }

            // Increment enrolled_count
            db()->prepare('UPDATE section_school_years SET enrolled_count = enrolled_count + ? WHERE id=?')
                ->execute([$assigned, $ssyId]);

            db()->commit();
            logAudit($adminId, 'update', 'sections', $sectionId, null, ['assigned_students' => count($studentIds)]);
            out(true, "{$assigned} student(s) assigned to section.");
        } catch (\PDOException $e) {
            db()->rollBack();
            out(false, 'Failed to assign students: ' . $e->getMessage());
        }
    }

    /**
     * Remove a student from a section (clears section_sy_id, decrements enrolled_count).
     */
    case 'remove_student_from_section': {
        $adminId   = requireAdmin();
        lockGuard();
        $sectionId = (int)post('section_id');
        $studentId = (int)post('student_id');
        if (!$sectionId || !$studentId) out(false, 'Missing required fields.');

        $syRow = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        $syId  = $syRow ? $syRow['id'] : null;
        if (!$syId) out(false, 'No active school year.');

        $ssyRow = db()->prepare('SELECT id FROM section_school_years WHERE section_id=? AND school_year_id=? LIMIT 1');
        $ssyRow->execute([$sectionId, $syId]);
        $ssy = $ssyRow->fetch();
        if (!$ssy) out(false, 'Section not found.');

        try {
            db()->beginTransaction();

            // ── 1. Clear section from student_profiles ────────────────────
            $upd = db()->prepare('UPDATE student_profiles SET section_sy_id=NULL WHERE student_id=? AND school_year_id=? AND section_sy_id=?');
            $upd->execute([$studentId, $syId, $ssy['id']]);
            $affected = $upd->rowCount();

            // ── 2. Clear section from enrollments (keep both tables in sync) ──
            db()->prepare(
                'UPDATE enrollments SET section_sy_id=NULL
                  WHERE student_id=? AND school_year_id=? AND section_sy_id=?'
            )->execute([$studentId, $syId, $ssy['id']]);

            if ($affected > 0) {
                db()->prepare('UPDATE section_school_years SET enrolled_count = GREATEST(0, enrolled_count - 1) WHERE id=?')
                    ->execute([$ssy['id']]);
            }
            db()->commit();
            logAudit($adminId, 'update', 'sections', $sectionId, null, ['removed_student' => $studentId]);
            out(true, 'Student removed from section.');
        } catch (\PDOException $e) {
            db()->rollBack();
            out(false, 'Failed to remove student.');
        }
    }

    case 'batch_remove_students_from_section': {
        $adminId     = requireAdmin();
        lockGuard();
        $sectionId   = (int)post('section_id');
        $rawIds      = post('student_ids', '');
        if (!$sectionId || !$rawIds) out(false, 'Missing required fields.');

        // Sanitise: only allow integers
        $studentIds = array_filter(array_map('intval', explode(',', $rawIds)));
        if (empty($studentIds)) out(false, 'No valid student IDs provided.');

        $syRow = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        $syId  = $syRow ? $syRow['id'] : null;
        if (!$syId) out(false, 'No active school year.');

        $ssyRow = db()->prepare('SELECT id FROM section_school_years WHERE section_id=? AND school_year_id=? LIMIT 1');
        $ssyRow->execute([$sectionId, $syId]);
        $ssy = $ssyRow->fetch();
        if (!$ssy) out(false, 'Section not found.');

        try {
            db()->beginTransaction();
            $removed = 0;
            $placeholders = implode(',', array_fill(0, count($studentIds), '?'));

            // ── 1. Clear section from student_profiles ────────────────────
            $upd = db()->prepare(
                "UPDATE student_profiles
                    SET section_sy_id = NULL
                  WHERE student_id IN ({$placeholders})
                    AND school_year_id = ?
                    AND section_sy_id  = ?"
            );
            $upd->execute([...$studentIds, $syId, $ssy['id']]);
            $removed = $upd->rowCount();

            // ── 2. Clear section from enrollments (keep both tables in sync) ──
            db()->prepare(
                "UPDATE enrollments
                    SET section_sy_id = NULL
                  WHERE student_id IN ({$placeholders})
                    AND school_year_id = ?
                    AND section_sy_id  = ?"
            )->execute([...$studentIds, $syId, $ssy['id']]);

            if ($removed > 0) {
                db()->prepare('UPDATE section_school_years SET enrolled_count = GREATEST(0, enrolled_count - ?) WHERE id=?')
                    ->execute([$removed, $ssy['id']]);
            }
            db()->commit();
            logAudit($adminId, 'update', 'sections', $sectionId, null, [
                'batch_removed_students' => $studentIds,
                'removed_count'          => $removed,
            ]);
            out(true, "{$removed} student(s) removed from section.", ['removed' => $removed]);
        } catch (\PDOException $e) {
            db()->rollBack();
            out(false, 'Failed to remove students: ' . $e->getMessage());
        }
    }

    // ════════════════════════════
    // SUBJECTS (Fix #6: archiving)
    // ════════════════════════════
    case 'get_subjects':
        requireAdmin();
        // Return only non-archived by default; include archived if requested
        $includeArchived = post('include_archived', '0') === '1';
        // Optional filter by grade level
        $gradeId = (int)post('grade_level_id', '0');

        $where  = $includeArchived ? '' : 'WHERE s.is_archived = 0';
        if ($gradeId > 0) {
            $where = $where === ''
                ? "WHERE s.grade_level_id = {$gradeId}"
                : "{$where} AND s.grade_level_id = {$gradeId}";
        }

        $sql = "SELECT s.*, g.display_name AS grade_display
                FROM subjects s
                LEFT JOIN grade_levels g ON g.id = s.grade_level_id
                {$where}
                ORDER BY s.grade_level_id ASC, s.name ASC";
        out(true, '', db()->query($sql)->fetchAll());

    case 'create_subject': {
        $adminId    = requireAdmin();
        lockGuard();    // Block if active SY is locked
        $name       = post('name');
        $gradeId    = (int)post('grade_level_id');
        $code       = strtoupper(post('code'));   // Full code sent from front-end e.g. FIL-07
        $hours      = (int)post('hours_per_week', '1');

        requireField($name,    'Subject name');
        requireField($code,    'Subject code');
        if ($gradeId < 7 || $gradeId > 10) out(false, 'A valid grade level (7–10) is required.');

        try {
            $stmt = db()->prepare(
                'INSERT INTO subjects (name, code, grade_level_id, hours_per_week) VALUES (?,?,?,?)'
            );
            $stmt->execute([$name, $code, $gradeId, $hours]);
            $id = (int)db()->lastInsertId();
            logAudit($adminId, 'create', 'subjects', $id, null, compact('name','code','gradeId'));
            out(true, 'Subject created.', ['id' => $id, 'code' => $code]);
        } catch (PDOException $e) {
            out(false, str_contains($e->getMessage(),'Duplicate')
                ? "Code '{$code}' already exists. Please use a unique code."
                : 'Failed to create subject.');
        }
    }

    case 'update_subject': {
        $adminId = requireAdmin();
        lockGuard();    // Block if active SY is locked
        $id      = (int)post('id');
        $name    = post('name');
        $gradeId = (int)post('grade_level_id');
        $code    = strtoupper(post('code'));
        $hours   = (int)post('hours_per_week');

        requireField($name, 'Subject name');
        requireField($code, 'Subject code');
        if ($gradeId < 7 || $gradeId > 10) out(false, 'A valid grade level (7–10) is required.');

        $old = db()->prepare('SELECT * FROM subjects WHERE id=?');
        $old->execute([$id]);
        $oldRow = $old->fetch();
        db()->prepare('UPDATE subjects SET name=?,code=?,grade_level_id=?,hours_per_week=? WHERE id=?')
            ->execute([$name, $code, $gradeId, $hours, $id]);
        logAudit($adminId, 'update', 'subjects', $id, $oldRow, compact('name','code','gradeId','hours'));
        out(true, 'Subject updated.');
    }

    case 'toggle_subject': {
        $adminId   = requireAdmin();
        lockGuard();
        $id        = (int)post('id');
        $is_active = (int)post('is_active');
        db()->prepare('UPDATE subjects SET is_active=? WHERE id=?')->execute([$is_active, $id]);
        logAudit($adminId, $is_active ? 'activate' : 'deactivate', 'subjects', $id);
        out(true, 'Subject status updated.');
    }

    // Fix #6: Archive subject (soft-delete, hidden from curriculum)
    case 'archive_subject': {
        $adminId = requireAdmin();
        lockGuard();
        $id      = (int)post('id');
        $old     = db()->prepare('SELECT * FROM subjects WHERE id=?');
        $old->execute([$id]);
        $oldRow  = $old->fetch();
        if (!$oldRow) out(false, 'Subject not found.');
        db()->prepare('UPDATE subjects SET is_archived=1, is_active=0 WHERE id=?')->execute([$id]);
        logAudit($adminId, 'archive', 'subjects', $id, $oldRow, ['is_archived' => 1]);
        out(true, 'Subject archived. It will no longer appear in active curriculum.');
    }

    // Fix #6: Restore archived subject
    case 'restore_subject': {
        $adminId = requireAdmin();
        lockGuard();
        $id      = (int)post('id');
        $old     = db()->prepare('SELECT * FROM subjects WHERE id=?');
        $old->execute([$id]);
        $oldRow  = $old->fetch();
        if (!$oldRow) out(false, 'Subject not found.');
        db()->prepare('UPDATE subjects SET is_archived=0, is_active=1 WHERE id=?')->execute([$id]);
        logAudit($adminId, 'activate', 'subjects', $id, $oldRow, ['is_archived' => 0]);
        out(true, 'Subject restored and is now active.');
    }

    // ════════════════════════════
    // CURRICULUM
    // ════════════════════════════
    case 'get_curriculum':
        requireAdmin();
        // Exclude archived subjects from curriculum view
        $rows = db()->query(
            'SELECT c.*, s.name as subject_name, s.code as subject_code
             FROM curriculum c
             JOIN subjects s ON s.id = c.subject_id AND s.is_archived = 0
             ORDER BY c.grade_level_id, c.subject_id'
        )->fetchAll();
        out(true, '', $rows);

    case 'add_curriculum': {
        $adminId        = requireAdmin();
        lockGuard();
        $school_year_id = (int)post('school_year_id');
        $grade_level_id = (int)post('grade_level_id');
        $subject_id     = (int)post('subject_id');

        // Reject archived subjects
        $subj = db()->prepare('SELECT is_archived FROM subjects WHERE id=?');
        $subj->execute([$subject_id]);
        $subjRow = $subj->fetch();
        if (!$subjRow || $subjRow['is_archived']) {
            out(false, 'Cannot add an archived subject to the curriculum.');
        }

        try {
            $stmt = db()->prepare(
                'INSERT INTO curriculum (school_year_id, grade_level_id, subject_id, created_by) VALUES (?,?,?,?)'
            );
            $stmt->execute([$school_year_id, $grade_level_id, $subject_id, $adminId]);
            $id = (int)db()->lastInsertId();
            logAudit($adminId, 'create', 'curriculum', $id, null,
                compact('school_year_id','grade_level_id','subject_id'));
            out(true, 'Added to curriculum.', ['id' => $id]);
        } catch (PDOException $e) {
            out(false, 'Already in curriculum.');
        }
    }

    case 'remove_curriculum': {
        $adminId        = requireAdmin();
        lockGuard();
        $school_year_id = (int)post('school_year_id');
        $grade_level_id = (int)post('grade_level_id');
        $subject_id     = (int)post('subject_id');
        $row = db()->prepare(
            'SELECT id FROM curriculum WHERE school_year_id=? AND grade_level_id=? AND subject_id=?'
        );
        $row->execute([$school_year_id, $grade_level_id, $subject_id]);
        $existing = $row->fetch();
        if ($existing) {
            db()->prepare('DELETE FROM curriculum WHERE id=?')->execute([$existing['id']]);
            logAudit($adminId, 'archive', 'curriculum', $existing['id']);
        }
        out(true, 'Removed from curriculum.');
    }

    // ════════════════════════════
    // DEADLINES (Fix #2, #3, #7)
    // ════════════════════════════
    case 'get_deadlines':
        requireAdmin();
        $rows = db()->query(
            'SELECT d.*, sy.label as sy_label
             FROM system_deadlines d JOIN school_years sy ON sy.id = d.school_year_id
             ORDER BY d.school_year_id DESC, d.start_datetime'
        )->fetchAll();
        // Normalize type labels in output
        foreach ($rows as &$r) {
            $r['type']       = normDeadlineType($r['type']);
            $r['type_label'] = DEADLINE_TYPES[$r['type']] ?? $r['type'];
        }
        unset($r);
        out(true, '', $rows);

    case 'get_deadline_types':
        // Returns the allowed deadline types for frontend dropdowns
        requireAdmin();
        $types = [];
        foreach (DEADLINE_TYPES as $key => $label) {
            $types[] = ['key' => $key, 'label' => $label];
        }
        out(true, '', $types);

    case 'create_deadline': {
        $adminId        = requireAdmin();
        $school_year_id = (int)post('school_year_id');
        $type           = normDeadlineType(post('type'));
        $start          = parseDateTime(post('start_datetime'));
        $end            = parseDateTime(post('end_datetime'));
        $notes          = post('notes');

        if (!array_key_exists($type, DEADLINE_TYPES)) {
            out(false, 'Invalid deadline type. Allowed: ' . implode(', ', array_keys(DEADLINE_TYPES)));
        }
        if (!$start || !$end) {
            out(false, 'Valid start and end date-times are required (format: YYYY-MM-DD HH:MM).');
        }

        // Fix #7: No past deadlines on create
        if (strtotime($start) < time()) {
            out(false, 'Start date-time cannot be in the past when creating a new deadline.');
        }
        if (strtotime($end) <= strtotime($start)) {
            out(false, 'End date-time must be after start date-time.');
        }

        // Fix #7: Deadline must fall within the school year's range
        $sy = db()->prepare('SELECT start_date, end_date FROM school_years WHERE id=?');
        $sy->execute([$school_year_id]);
        $syRow = $sy->fetch();
        if ($syRow) {
            if (strtotime($end) > strtotime($syRow['end_date'] . ' 23:59:59')) {
                out(false, 'End date-time exceeds the school year range.');
            }
        }

        // Derive plain DATE portion for the legacy start_date / end_date columns.
        // Those columns are NOT NULL and are still read by the enrollment / registration
        // open-check elsewhere in the system. Without this the columns stay 0000-00-00
        // and registration never opens even after a deadline is saved.
        $startDate = substr($start, 0, 10); // "YYYY-MM-DD"
        $endDate   = substr($end,   0, 10);

        try {
            $stmt = db()->prepare(
                'INSERT INTO system_deadlines
                    (school_year_id, type, start_date, end_date, start_datetime, end_datetime, notes, created_by)
                 VALUES (?,?,?,?,?,?,?,?)'
            );
            $stmt->execute([$school_year_id, $type, $startDate, $endDate, $start, $end, $notes, $adminId]);
            $id = (int)db()->lastInsertId();
            logAudit($adminId, 'create', 'system_deadlines', $id, null,
                compact('type','start','end'));
            out(true, 'Deadline set.', ['id' => $id]);
        } catch (PDOException $e) {
            out(false, 'A deadline for this type already exists in this school year.');
        }
    }

    case 'update_deadline': {
        $adminId = requireAdmin();
        $id      = (int)post('id');
        $type    = normDeadlineType(post('type'));
        $start   = parseDateTime(post('start_datetime'));
        $end     = parseDateTime(post('end_datetime'));
        $notes   = post('notes');

        if (!array_key_exists($type, DEADLINE_TYPES)) {
            out(false, 'Invalid deadline type.');
        }
        if (!$start || !$end) {
            out(false, 'Valid start and end date-times are required.');
        }
        if (strtotime($end) <= strtotime($start)) {
            out(false, 'End date-time must be after start date-time.');
        }

        $old = db()->prepare('SELECT * FROM system_deadlines WHERE id=?');
        $old->execute([$id]);
        $oldRow = $old->fetch();

        // Fix #7: School year range check on update too
        if ($oldRow) {
            $sy = db()->prepare('SELECT start_date, end_date FROM school_years WHERE id=?');
            $sy->execute([$oldRow['school_year_id']]);
            $syRow = $sy->fetch();
            if ($syRow && strtotime($end) > strtotime($syRow['end_date'] . ' 23:59:59')) {
                out(false, 'End date-time exceeds the school year range.');
            }
        }

        // Keep the legacy date-only columns in sync so registration checks still work.
        $startDate = substr($start, 0, 10);
        $endDate   = substr($end,   0, 10);

        db()->prepare(
            'UPDATE system_deadlines SET type=?, start_date=?, end_date=?, start_datetime=?, end_datetime=?, notes=? WHERE id=?'
        )->execute([$type, $startDate, $endDate, $start, $end, $notes, $id]);
        logAudit($adminId, 'update', 'system_deadlines', $id, $oldRow,
            compact('type','start','end'));
        out(true, 'Deadline updated.');
    }

    // ════════════════════════════
    // FACULTY ACCOUNTS — unified view across all role tables
    // ════════════════════════════
    case 'get_admins': {
        requireAdmin();

        /**
         * Query each role table individually so that a missing table
         * (e.g. teachers/cashiers not yet created) never breaks the
         * whole response — it just yields zero rows for that role.
         */
        $roleQueries = [
            'admins' => "SELECT a.id, a.user_id, a.first_name, a.middle_name, a.last_name,
                                COALESCE(NULLIF(TRIM(CONCAT(a.first_name,' ',COALESCE(a.last_name,''))), ''), a.full_name) AS full_name,
                                u.username, u.school_email, u.personal_email, u.role, u.is_active,
                                COALESCE(a.is_archived, 0) AS is_archived,
                                '' AS assigned_subjects,
                                a.created_at, 'admins' AS account_table,
                                COALESCE(u.employee_id, '') AS employee_id
                         FROM admins a JOIN users u ON u.id = a.user_id",

            'teachers' => "SELECT t.id, t.user_id, t.first_name, t.middle_name, t.last_name,
                                  TRIM(CONCAT(t.first_name,' ',COALESCE(t.last_name,''))) AS full_name,
                                  u.username, u.school_email, u.personal_email, u.role, u.is_active,
                                  COALESCE(t.is_archived, 0) AS is_archived,
                                  COALESCE(t.assigned_subjects, '') AS assigned_subjects,
                                  t.created_at, 'teachers' AS account_table,
                                  COALESCE(u.employee_id, '') AS employee_id
                           FROM teachers t JOIN users u ON u.id = t.user_id",

            'registrars' => "SELECT r.id, r.user_id, r.first_name, r.middle_name, r.last_name,
                                    TRIM(CONCAT(r.first_name,' ',COALESCE(r.last_name,''))) AS full_name,
                                    u.username, u.school_email, u.personal_email, u.role, u.is_active,
                                    COALESCE(r.is_archived, 0) AS is_archived,
                                    '' AS assigned_subjects,
                                    r.created_at, 'registrars' AS account_table,
                                    COALESCE(u.employee_id, '') AS employee_id
                              FROM registrars r JOIN users u ON u.id = r.user_id",

            'cashiers' => "SELECT c.id, c.user_id, c.first_name, c.middle_name, c.last_name,
                                  TRIM(CONCAT(c.first_name,' ',COALESCE(c.last_name,''))) AS full_name,
                                  u.username, u.school_email, u.personal_email, u.role, u.is_active,
                                  COALESCE(c.is_archived, 0) AS is_archived,
                                  '' AS assigned_subjects,
                                  c.created_at, 'cashiers' AS account_table,
                                  COALESCE(u.employee_id, '') AS employee_id
                           FROM cashiers c JOIN users u ON u.id = c.user_id",

            'principals' => "SELECT p.id, p.user_id, p.first_name, p.middle_name, p.last_name,
                                    TRIM(CONCAT(p.first_name,' ',COALESCE(p.last_name,''))) AS full_name,
                                    u.username, u.school_email, u.personal_email, u.role, u.is_active,
                                    COALESCE(p.is_archived, 0) AS is_archived,
                                    '' AS assigned_subjects,
                                    p.created_at, 'principals' AS account_table,
                                    COALESCE(u.employee_id, '') AS employee_id
                              FROM principals p JOIN users u ON u.id = p.user_id",

            'coordinators' => "SELECT co.id, co.user_id, co.first_name, co.middle_name, co.last_name,
                                      TRIM(CONCAT(co.first_name,' ',COALESCE(co.last_name,''))) AS full_name,
                                      u.username, u.school_email, u.personal_email, u.role, u.is_active,
                                      COALESCE(co.is_archived, 0) AS is_archived,
                                      '' AS assigned_subjects,
                                      co.created_at, 'coordinators' AS account_table,
                                      COALESCE(u.employee_id, '') AS employee_id
                                FROM coordinators co JOIN users u ON u.id = co.user_id",
        ];

        $rows = [];
        foreach ($roleQueries as $tableName => $sql) {
            try {
                $fetched = db()->query($sql)->fetchAll();
                $rows    = array_merge($rows, $fetched);
            } catch (PDOException $e) {
                // Table doesn't exist yet — skip silently
                error_log("[get_admins] Skipping table '{$tableName}': " . $e->getMessage());
            }
        }

        // Sort combined results: by role then full_name
        usort($rows, fn($a, $b) =>
            strcmp($a['role'] ?? '', $b['role'] ?? '') ?: strcmp($a['full_name'] ?? '', $b['full_name'] ?? '')
        );

        out(true, '', $rows);
    }

    case 'get_admin_list':
        requireAdmin();
        $rows = db()->query(
            'SELECT a.id,
                    COALESCE(
                        NULLIF(TRIM(CONCAT(a.first_name," ",COALESCE(a.last_name,""))), ""),
                        a.full_name
                    ) AS full_name
             FROM admins a ORDER BY full_name'
        )->fetchAll();
        out(true, '', $rows);

    // Teacher-only lookup for adviser dropdowns — now uses dedicated teachers table
    case 'get_teachers':
        requireAdmin();
        $rows = db()->query(
            'SELECT t.id,
                    TRIM(CONCAT(t.first_name," ",COALESCE(t.last_name,""))) AS full_name,
                    u.role
             FROM teachers t
             JOIN users u ON u.id = t.user_id
             ORDER BY full_name'
        )->fetchAll();
        out(true, '', $rows);

    /**
     * Return teachers who are NOT yet assigned as adviser in any active section,
     * PLUS the teacher currently assigned to $current_section_id (so the existing
     * adviser always appears selected in the dropdown).
     *
     * POST params:
     *   current_section_id  — the section being edited (0 or omitted for "new section")
     */
    case 'get_available_teachers': {
        requireAdmin();
        $currentSectionId = (int)post('current_section_id', '0');

        // Get the active school year
        $syRow = db()->query('SELECT id FROM school_years WHERE is_active=1 LIMIT 1')->fetch();
        $syId  = $syRow ? (int)$syRow['id'] : 0;

        // Find the adviser_id already assigned to this section (so we can always include them)
        $currentAdviserId = 0;
        if ($currentSectionId > 0 && $syId > 0) {
            $cur = db()->prepare(
                'SELECT adviser_id FROM section_school_years
                  WHERE section_id=? AND school_year_id=? LIMIT 1'
            );
            $cur->execute([$currentSectionId, $syId]);
            $curRow = $cur->fetch();
            $currentAdviserId = $curRow ? (int)($curRow['adviser_id'] ?? 0) : 0;
        }

        // Collect teacher IDs already assigned as adviser in OTHER active sections this SY
        $takenIds = [];
        if ($syId > 0) {
            $taken = db()->prepare(
                'SELECT DISTINCT ssy.adviser_id
                   FROM section_school_years ssy
                   JOIN sections s ON s.id = ssy.section_id
                  WHERE ssy.school_year_id = ?
                    AND ssy.adviser_id IS NOT NULL
                    AND s.status != \'archived\'
                    AND ssy.section_id != ?'
            );
            $taken->execute([$syId, $currentSectionId > 0 ? $currentSectionId : 0]);
            $takenIds = array_column($taken->fetchAll(), 'adviser_id');
        }

        // Build exclusion clause — also exclude archived teachers
        if (!empty($takenIds)) {
            $placeholders = implode(',', array_fill(0, count($takenIds), '?'));
            $stmt = db()->prepare(
                "SELECT t.id,
                        TRIM(CONCAT(t.first_name,' ',COALESCE(t.last_name,''))) AS full_name,
                        u.role
                   FROM teachers t
                   JOIN users u ON u.id = t.user_id
                  WHERE t.id NOT IN ({$placeholders})
                    AND COALESCE(t.is_archived, 0) = 0
                  ORDER BY full_name"
            );
            $stmt->execute($takenIds);
        } else {
            $stmt = db()->query(
                "SELECT t.id,
                        TRIM(CONCAT(t.first_name,' ',COALESCE(t.last_name,''))) AS full_name,
                        u.role
                   FROM teachers t
                   JOIN users u ON u.id = t.user_id
                  WHERE COALESCE(t.is_archived, 0) = 0
                  ORDER BY full_name"
            );
        }
        $rows = $stmt->fetchAll();

        out(true, '', ['teachers' => $rows, 'current_adviser_id' => $currentAdviserId]);
    }

    case 'get_roles':
        // Returns allowed roles for dropdown
        requireAdmin();
        out(true, '', array_map(fn($r) => ['key' => $r, 'label' => ucfirst($r)], ALL_ROLES));

    case 'create_admin': {
        $adminId        = requireAdmin();
        $first_name     = post('first_name');
        $middle_name    = post('middle_name');   // optional
        $last_name      = post('last_name');
        $username       = post('username');
        $role           = in_array(post('role'), ALL_ROLES) ? post('role') : 'teacher';
        $personal_email = post('personal_email'); // required — credentials sent here
        $assigned_subjects = $role === 'teacher' ? trim(post('assigned_subjects', '')) : '';

        requireField($first_name,     'First name');
        requireField($last_name,      'Last name');
        requireField($username,       'Username');
        requireField($personal_email, 'Work / Personal email');

        // Validate personal_email is a real email address
        if (!filter_var($personal_email, FILTER_VALIDATE_EMAIL)) {
            out(false, 'Please enter a valid work/personal email address.');
        }

        // Block school email (@sjc*.edu.ph) in the personal_email field
        if (preg_match('/@sjc.*\.edu\.ph$/i', $personal_email)) {
            out(false, 'Work/personal email must be a Gmail, Yahoo, or similar address — not a school email.');
        }

        // Enforce single-principal rule: only one non-archived principal allowed at any time
        if ($role === 'principal') {
            $existingPrincipal = db()->query(
                "SELECT id FROM principals WHERE COALESCE(is_archived, 0) = 0 LIMIT 1"
            )->fetch();
            if ($existingPrincipal) {
                out(false, 'A principal account already exists. Only one active principal is allowed. Archive the existing principal account first before creating a new one.');
            }
        }

        // Auto-generate a unique school email (appends numeric suffix if the base is taken)
        $school_email = generateUniqueSchoolEmail($first_name, $last_name, $role);

        // Build full_name for backward compat
        $full_name = trim($first_name . ($middle_name ? ' ' . $middle_name : '') . ' ' . $last_name);

        // System-generated random secure password
        $chars    = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789!@#$%';
        $temp_pass = '';
        for ($i = 0; $i < 12; $i++) {
            $temp_pass .= $chars[random_int(0, strlen($chars) - 1)];
        }

        $hash = password_hash($temp_pass, PASSWORD_BCRYPT);

        /**
         * Role → table mapping.
         * 'admin' still uses the admins table.
         * All other roles use their own dedicated table.
         */
        $roleTableMap = [
            'admin'       => 'admins',
            'teacher'     => 'teachers',
            'registrar'   => 'registrars',
            'cashier'     => 'cashiers',
            'principal'   => 'principals',
            'coordinator' => 'coordinators',
        ];
        $targetTable = $roleTableMap[$role] ?? 'teachers';

        // Generate a unique Employee ID (format: EMP-XXXXXX, e.g. EMP-4A9F2C)
        $employee_id = '';
        do {
            $candidate = 'EMP-' . strtoupper(substr(bin2hex(random_bytes(3)), 0, 6));
            $chk = db()->prepare('SELECT 1 FROM users WHERE employee_id = ? LIMIT 1');
            $chk->execute([$candidate]);
            if (!$chk->fetch()) { $employee_id = $candidate; }
        } while ($employee_id === '');

        try {
            db()->beginTransaction();

            // 1. Insert into users table (always)
            $u = db()->prepare(
                'INSERT INTO users (username, email, school_email, personal_email, password_hash, role, employee_id) VALUES (?,?,?,?,?,?,?)'
            );
            $u->execute([$username, $school_email, $school_email, $personal_email, $hash, $role, $employee_id]);
            $userId = (int)db()->lastInsertId();

            // 2. Insert into the correct role-specific profile table
            if ($targetTable === 'registrars') {
                // registrars table has is_active and employee_id columns
                $a = db()->prepare(
                    'INSERT INTO registrars (user_id, first_name, middle_name, last_name, is_active) VALUES (?,?,?,?,1)'
                );
                $a->execute([$userId, $first_name, $middle_name ?: null, $last_name]);
            } elseif ($targetTable === 'teachers') {
                // Resolve subject_id from the first assigned subject name so coordinators
                // can filter teachers by subject. assigned_subjects holds comma-separated
                // base names (e.g. "ENGLISH,MATH"); subject_id stores the FK for the first
                // (primary) subject matched in the subjects table.
                $resolvedSubjectId = null;
                if ($assigned_subjects !== '') {
                    $firstSubjectName = trim(explode(',', $assigned_subjects)[0]);
                    // Match by name — case-insensitive, also matches grade-suffixed variants
                    // e.g. admin saves "Science", but subjects table has "Science-07", "Science-08"
                    // We grab the lowest active id so all grade-level variants share the same root
                    $baseUpper = strtoupper(preg_replace('/[-–]\s*\d+$/', '', $firstSubjectName));
                    $subjStmt = db()->prepare(
                        "SELECT id FROM subjects
                          WHERE UPPER(TRIM(name)) = ?
                             OR UPPER(TRIM(REGEXP_REPLACE(name, '[[:space:]]*[-–][[:space:]]*[0-9]+$', ''))) = ?
                          ORDER BY is_archived ASC, id ASC
                          LIMIT 1"
                    );
                    $subjStmt->execute([$baseUpper, $baseUpper]);
                    $subjRow = $subjStmt->fetch();
                    if (!$subjRow) {
                        // Fallback: LIKE match for partial names (e.g. "Science" matches "Science-07")
                        $likeStmt = db()->prepare(
                            "SELECT id FROM subjects
                              WHERE UPPER(TRIM(name)) LIKE ?
                              ORDER BY is_archived ASC, id ASC
                              LIMIT 1"
                        );
                        $likeStmt->execute([$baseUpper . '%']);
                        $subjRow = $likeStmt->fetch();
                    }
                    if ($subjRow) {
                        $resolvedSubjectId = (int)$subjRow['id'];
                    }
                }

                $a = db()->prepare(
                    'INSERT INTO teachers (user_id, first_name, middle_name, last_name, full_name, assigned_subjects, subject_id) VALUES (?,?,?,?,?,?,?)'
                );
                $a->execute([$userId, $first_name, $middle_name ?: null, $last_name, $full_name, $assigned_subjects ?: null, $resolvedSubjectId]);
            } else {
                // admins, teachers, cashiers, principals, coordinators all share same structure
                $a = db()->prepare(
                    "INSERT INTO {$targetTable} (user_id, first_name, middle_name, last_name, full_name) VALUES (?,?,?,?,?)"
                );
                $a->execute([$userId, $first_name, $middle_name ?: null, $last_name, $full_name]);
            }
            $newProfileId = (int)db()->lastInsertId();
            db()->commit();

            // Send credentials email to personal/work email
            sendCredentialsEmail($personal_email, $full_name, $school_email, $temp_pass, $role);

            logAudit($adminId, 'create', $targetTable, $newProfileId, null,
                compact('full_name','username','role','school_email'));
            out(true, 'Account created. Credentials sent to ' . $personal_email, [
                'id'           => $newProfileId,
                'school_email' => $school_email,
                'table'        => $targetTable,
            ]);
        } catch (PDOException $e) {
            db()->rollBack();
            out(false, str_contains($e->getMessage(),'Duplicate')
                ? 'Username or school email already taken.'
                : 'Failed to create account: ' . $e->getMessage());
        }
    }

    case 'update_admin': {
        $adminId     = requireAdmin();
        $id          = (int)post('id');
        $first_name  = post('first_name');
        $middle_name = post('middle_name');
        $last_name   = post('last_name');
        $role        = in_array(post('role'), ALL_ROLES) ? post('role') : null;
        $personal_email = post('personal_email');
        $assigned_subjects = (post('role') === 'teacher') ? trim(post('assigned_subjects', '')) : null;

        // account_table is passed from the JS buildUserRow — use it to know EXACTLY which
        // table this account lives in, avoiding the dangerous cross-table UNION lookup.
        $account_table = post('account_table'); // e.g. 'teachers', 'admins', etc.

        // Support legacy full_name-only edits
        $full_name_legacy = post('full_name');
        if (!$first_name && !$last_name && $full_name_legacy) {
            $first_name = $full_name_legacy;
        }

        requireField($first_name,     'First name');
        requireField($personal_email, 'Work / Personal email');

        if (!filter_var($personal_email, FILTER_VALIDATE_EMAIL)) {
            out(false, 'Please enter a valid work/personal email address.');
        }
        if (preg_match('/@sjc.*\.edu\.ph$/i', $personal_email)) {
            out(false, 'Work/personal email must be a Gmail, Yahoo, or similar address — not a school email.');
        }

        $full_name = $last_name
            ? trim($first_name . ($middle_name ? ' ' . $middle_name : '') . ' ' . $last_name)
            : $first_name;

        $roleTableMap = [
            'admin'       => 'admins',
            'teacher'     => 'teachers',
            'registrar'   => 'registrars',
            'cashier'     => 'cashiers',
            'principal'   => 'principals',
            'coordinator' => 'coordinators',
        ];

        $allowed = array_values($roleTableMap);

        /*
         * BUG FIX — CRITICAL: The old code used a UNION subquery:
         *   SELECT user_id FROM admins WHERE id=? UNION
         *   SELECT user_id FROM teachers WHERE id=? UNION ...
         * The problem: IDs are independent auto-increments per table, so
         * if a teacher has id=2 AND an admin also has id=2, the UNION finds
         * BOTH user_id rows. The first match wins — which could be the WRONG
         * table. Editing teacher id=2 could look up and update admin id=2's
         * users row instead, regenerating the admin's school_email and
         * effectively breaking or "deleting" the admin account's login.
         *
         * FIX: Use the account_table field that the JS already knows and sends
         * (from buildUserRow → r.account_table). This uniquely identifies
         * EXACTLY which table the account row lives in, so there is zero ambiguity.
         *
         * If account_table wasn't sent (legacy call), fall back to the role's
         * expected table based on the posted role value.
         */
        if (!$account_table || !in_array($account_table, $allowed, true)) {
            // Fallback: derive from the role being set (best-effort for old calls)
            $account_table = $role ? ($roleTableMap[$role] ?? null) : null;
            if (!$account_table) {
                out(false, 'Cannot determine which account table to update. Please reload the page and try again.');
            }
        }

        // Now look up the user_id from the CORRECT table only — no cross-table confusion
        $stmt = db()->prepare("SELECT user_id FROM `{$account_table}` WHERE id = ? LIMIT 1");
        $stmt->execute([$id]);
        $oldRow = $stmt->fetch();

        if (!$oldRow) out(false, 'Account not found.');
        $userId = (int)$oldRow['user_id'];

        // Fetch current user role for the email-regeneration logic below
        $userStmt = db()->prepare('SELECT role, school_email, personal_email FROM users WHERE id = ? LIMIT 1');
        $userStmt->execute([$userId]);
        $userRecord = $userStmt->fetch();
        $currentRole = $userRecord['role'] ?? '';

        $targetTable = $roleTableMap[$role ?? $currentRole] ?? $account_table;

        // Update the profile in the correct role table
        if ($targetTable === 'registrars') {
            db()->prepare('UPDATE registrars SET first_name=?, middle_name=?, last_name=? WHERE id=?')
                ->execute([$first_name, $middle_name ?: null, $last_name ?: null, $id]);
        } elseif ($targetTable === 'teachers') {
            // Resolve subject_id from the first assigned subject name (same logic as create_admin)
            $resolvedSubjectId = null;
            if ($assigned_subjects !== null && $assigned_subjects !== '') {
                $firstSubjectName = trim(explode(',', $assigned_subjects)[0]);
                $baseUpper = strtoupper(preg_replace('/[-–]\s*\d+$/', '', $firstSubjectName));
                $subjStmt = db()->prepare(
                    "SELECT id FROM subjects
                      WHERE UPPER(TRIM(name)) = ?
                         OR UPPER(TRIM(REGEXP_REPLACE(name, '[[:space:]]*[-–][[:space:]]*[0-9]+$', ''))) = ?
                      ORDER BY is_archived ASC, id ASC LIMIT 1"
                );
                $subjStmt->execute([$baseUpper, $baseUpper]);
                $subjRow = $subjStmt->fetch();
                if (!$subjRow) {
                    $likeStmt = db()->prepare(
                        "SELECT id FROM subjects
                          WHERE UPPER(TRIM(name)) LIKE ?
                          ORDER BY is_archived ASC, id ASC LIMIT 1"
                    );
                    $likeStmt->execute([$baseUpper . '%']);
                    $subjRow = $likeStmt->fetch();
                }
                if ($subjRow) {
                    $resolvedSubjectId = (int)$subjRow['id'];
                }
            }
            db()->prepare("UPDATE teachers SET first_name=?, middle_name=?, last_name=?, full_name=?, assigned_subjects=?, subject_id=? WHERE id=?")
                ->execute([$first_name, $middle_name ?: null, $last_name ?: null, $full_name, $assigned_subjects, $resolvedSubjectId, $id]);
        } else {
            db()->prepare("UPDATE {$targetTable} SET first_name=?, middle_name=?, last_name=?, full_name=? WHERE id=?")
                ->execute([$first_name, $middle_name ?: null, $last_name ?: null, $full_name, $id]);
        }

        if ($role) {
            $newEmail = generateUniqueSchoolEmail($first_name, $last_name ?: $first_name, $role, $userId);
            db()->prepare('UPDATE users SET email=?, school_email=?, personal_email=?, role=? WHERE id=?')
                ->execute([$newEmail, $newEmail, $personal_email, $role, $userId]);
        } else {
            db()->prepare('UPDATE users SET personal_email=? WHERE id=?')
                ->execute([$personal_email, $userId]);
        }

        logAudit($adminId, 'update', $targetTable, $id, $userRecord,
            compact('full_name','role','personal_email'));
        out(true, 'Account updated.');
    }

    case 'get_archive_context': {
        /*
         * Returns context needed for the archive warning prompt.
         * For teachers  → their assigned_subjects string.
         * For coordinators → their active curriculum subject names.
         * For others    → empty subjects (generic warning shown).
         *
         * Request: { id, table }
         * Response: { subjects: "English, Math" }   (empty string = no active assignment)
         */
        requireAdmin();
        $id    = (int)post('id');
        $table = post('table');

        $allowed = ['admins','teachers','registrars','cashiers','principals','coordinators'];
        if (!in_array($table, $allowed, true)) out(false, 'Invalid account table.');

        $subjects = '';

        if ($table === 'teachers') {
            $stmt = db()->prepare('SELECT assigned_subjects FROM teachers WHERE id = ? LIMIT 1');
            $stmt->execute([$id]);
            $row = $stmt->fetch();
            if ($row && !empty($row['assigned_subjects'])) {
                // Normalize: strip grade-level suffixes (e.g. "ESP-07" → "ESP") and deduplicate
                $parts = array_map('trim', explode(',', $row['assigned_subjects']));
                $parts = array_map(fn($s) => preg_replace('/[-–]\s*\d+$/', '', $s), $parts);
                $parts = array_values(array_unique(array_filter($parts)));
                $subjects = implode(', ', $parts);
            }
        } elseif ($table === 'coordinators') {
            // Pull from curriculum — the subjects assigned to this coordinator by the principal
            $stmt = db()->prepare("
                SELECT DISTINCT TRIM(s.name) AS sname
                FROM   curriculum  cur
                JOIN   subjects    s  ON s.id  = cur.subject_id
                JOIN   school_years sy ON sy.id = cur.school_year_id
                WHERE  cur.coordinator_id = ?
                  AND  cur.is_active      = 1
                  AND  sy.is_active       = 1
                ORDER  BY sname
            ");
            $stmt->execute([$id]);
            $names = $stmt->fetchAll(PDO::FETCH_COLUMN);
            $subjects = implode(', ', $names);
        }

        out(true, '', ['subjects' => $subjects]);
    }

    case 'archive_admin': {
        $adminId = requireAdmin();
        $id      = (int)post('id');
        $archive = post('archive', '1') === '1';
        $table   = post('table');

        $allowed = ['admins','teachers','registrars','cashiers','principals','coordinators'];
        if (!in_array($table, $allowed, true)) out(false, 'Invalid account table.');

        // Add is_archived column if it doesn't exist yet (safe migration)
        try {
            db()->exec("ALTER TABLE `{$table}` ADD COLUMN `is_archived` TINYINT(1) NOT NULL DEFAULT 0");
        } catch (PDOException $e) { /* column already exists — ignore */ }

        $row = db()->prepare("SELECT user_id FROM `{$table}` WHERE id=?");
        $row->execute([$id]);
        $r = $row->fetch();
        if (!$r) out(false, 'Account not found.');

        db()->prepare("UPDATE `{$table}` SET is_archived=? WHERE id=?")->execute([$archive ? 1 : 0, $id]);
        // Also deactivate/activate the user account accordingly
        db()->prepare('UPDATE users SET is_active=? WHERE id=?')->execute([$archive ? 0 : 1, $r['user_id']]);

        logAudit($adminId, $archive ? 'archive' : 'restore', $table, $id);
        out(true, $archive ? 'Account archived.' : 'Account restored.');
    }

    case 'toggle_admin_active': {
        $adminId   = requireAdmin();
        $id        = (int)post('id');
        $is_active = (int)post('is_active');
        $table     = post('table'); // account_table sent from JS

        $allowed = ['admins','teachers','registrars','cashiers','principals','coordinators'];
        if (!in_array($table, $allowed, true)) $table = 'admins';

        $row = db()->prepare("SELECT user_id FROM {$table} WHERE id=?");
        $row->execute([$id]);
        $r = $row->fetch();
        if (!$r) out(false, 'Account not found.');
        db()->prepare('UPDATE users SET is_active=? WHERE id=?')->execute([$is_active, $r['user_id']]);
        logAudit($adminId, $is_active ? 'activate' : 'deactivate', $table, $id);
        out(true, $is_active ? 'Account activated.' : 'Account deactivated.');
    }

    // ════════════════════════════
    // STUDENT ACCOUNTS
    // ════════════════════════════

    /**
     * List all students with grade level info.
     * Supports optional grade_level filter (7-10) and optional archived filter.
     */
    case 'get_student_accounts': {
        requireAdmin();
        $gradeId         = (int)post('grade_level_id', '0');
        $includeArchived = post('include_archived', '0') === '1';

        // Safe migration: add is_archived column if it does not exist yet
        try {
            db()->exec("ALTER TABLE `students` ADD COLUMN `is_archived` TINYINT(1) NOT NULL DEFAULT 0");
        } catch (PDOException $e) { /* column already exists — ignore */ }

        $whereClauses = [];
        if (!$includeArchived) $whereClauses[] = "s.is_archived = 0";
        if ($gradeId >= 7 && $gradeId <= 10) $whereClauses[] = "gl.level = {$gradeId}";
        $where = $whereClauses ? 'WHERE ' . implode(' AND ', $whereClauses) : '';

        $sql = "SELECT s.id, s.first_name, s.middle_name, s.last_name,
                       TRIM(CONCAT(s.first_name, ' ', COALESCE(s.middle_name,''), ' ', s.last_name)) AS full_name,
                       s.lrn, s.registration_status,
                       COALESCE(s.is_archived, 0) AS is_archived,
                       s.personal_email,
                       gl.display_name AS grade_display,
                       gl.level        AS grade_level,
                       s.created_at
                FROM students s
                LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
                {$where}
                ORDER BY gl.level ASC, s.last_name ASC, s.first_name ASC";

        out(true, '', db()->query($sql)->fetchAll());
    }

    /**
     * Verify the currently-logged-in admin's password (for re-authentication gates).
     */
    case 'verify_admin_password': {
        $adminId  = requireAdmin();
        $password = post('password');

        if ($password === '') out(false, 'Password is required.');

        $stmt = db()->prepare('SELECT password_hash FROM users WHERE id = ? LIMIT 1');
        $stmt->execute([$adminId]);
        $row = $stmt->fetch();

        if (!$row || !password_verify($password, $row['password_hash'])) {
            out(false, 'Incorrect password. Please try again.');
        }

        out(true, 'Verified.');
    }

    /**
     * Combined: update student email + LRN, write audit log, send notification email.
     * This is the secure single-action replacement for the separate email/LRN calls.
     */
    case 'update_student_info': {
        $adminId       = requireAdmin();
        $id            = (int)post('id');
        $personalEmail = post('personal_email');
        $lrn           = post('lrn', '');

        if (!$id) out(false, 'Missing student ID.');
        requireField($personalEmail, 'Personal email');

        if (!filter_var($personalEmail, FILTER_VALIDATE_EMAIL)) {
            out(false, 'Please enter a valid email address.');
        }

        if ($lrn !== '' && !preg_match('/^\d{12}$/', $lrn)) {
            out(false, 'LRN must be exactly 12 digits.');
        }

        // Check LRN uniqueness
        if ($lrn !== '') {
            $dup = db()->prepare('SELECT id FROM students WHERE lrn = ? AND id != ?');
            $dup->execute([$lrn, $id]);
            if ($dup->fetch()) out(false, 'This LRN is already assigned to another student.');
        }

        // Fetch existing record
        $oldStmt = db()->prepare('SELECT id, personal_email, lrn, first_name, last_name FROM students WHERE id = ?');
        $oldStmt->execute([$id]);
        $oldRow = $oldStmt->fetch();
        if (!$oldRow) out(false, 'Student not found.');

        $oldEmail = $oldRow['personal_email'] ?? '';
        $oldLrn   = $oldRow['lrn'] ?? '';
        $emailChanged = ($personalEmail !== $oldEmail);
        $lrnChanged   = ($lrn !== $oldLrn && !($lrn === '' && $oldLrn === null));

        // Perform updates
        db()->prepare('UPDATE students SET personal_email=? WHERE id=?')
            ->execute([$personalEmail, $id]);

        db()->prepare('UPDATE students SET lrn=? WHERE id=?')
            ->execute([$lrn !== '' ? $lrn : null, $id]);

        // Build audit old/new arrays only for changed fields
        $auditOld = [];
        $auditNew = [];
        if ($emailChanged) {
            $auditOld['personal_email'] = $oldEmail;
            $auditNew['personal_email'] = $personalEmail;
        }
        if ($lrnChanged) {
            $auditOld['lrn'] = $oldLrn;
            $auditNew['lrn'] = $lrn ?: null;
        }

        if (!empty($auditNew)) {
            // Include student identity context in old_values (prefixed _ so UI can distinguish)
            $auditOld['_student_name'] = trim(($oldRow['first_name'] ?? '') . ' ' . ($oldRow['last_name'] ?? ''));
            $auditOld['_student_lrn']  = $oldRow['lrn'] ?? null;
            logAudit($adminId, 'update', 'students', $id, $auditOld, $auditNew);
        }

        // Send email notification only if personal email changed
        if ($emailChanged && $personalEmail !== '') {
            $fullName = trim(($oldRow['first_name'] ?? '') . ' ' . ($oldRow['last_name'] ?? ''));
            $changedDateTime = date('F j, Y \a\t h:i A');
            sendStudentAccountChangeEmail($personalEmail, $fullName, $changedDateTime);
        }

        out(true, 'Student account updated successfully.');
    }

    /**
     * Update a student's personal email only.
     */
    case 'update_student_email': {
        $adminId       = requireAdmin();
        $id            = (int)post('id');
        $personalEmail = post('personal_email');

        if (!$id) out(false, 'Missing student ID.');
        requireField($personalEmail, 'Personal email');

        if (!filter_var($personalEmail, FILTER_VALIDATE_EMAIL)) {
            out(false, 'Please enter a valid email address.');
        }

        $old = db()->prepare('SELECT id, personal_email, first_name, last_name FROM students WHERE id=?');
        $old->execute([$id]);
        $oldRow = $old->fetch();
        if (!$oldRow) out(false, 'Student not found.');

        db()->prepare('UPDATE students SET personal_email=? WHERE id=?')
            ->execute([$personalEmail, $id]);

        logAudit($adminId, 'update', 'students', $id,
            ['personal_email'  => $oldRow['personal_email'],
             '_student_name'   => trim(($oldRow['first_name'] ?? '') . ' ' . ($oldRow['last_name'] ?? '')),
             '_student_lrn'    => $oldRow['lrn'] ?? null],
            ['personal_email'  => $personalEmail]);
        out(true, 'Email updated.');
    }

    /**
     * Update a student's LRN (12-digit, admin only).
     */
    case 'update_student_lrn': {
        $adminId = requireAdmin();
        $id      = (int)post('id');
        $lrn     = trim(post('lrn', ''));

        if (!$id) out(false, 'Missing student ID.');

        // LRN must be exactly 12 digits or empty (to clear it)
        if ($lrn !== '' && !preg_match('/^\d{12}$/', $lrn)) {
            out(false, 'LRN must be exactly 12 digits.');
        }

        // Check uniqueness (if non-empty)
        if ($lrn !== '') {
            $dup = db()->prepare('SELECT id FROM students WHERE lrn = ? AND id != ?');
            $dup->execute([$lrn, $id]);
            if ($dup->fetch()) out(false, 'This LRN is already assigned to another student.');
        }

        $old = db()->prepare('SELECT id, lrn, first_name, last_name FROM students WHERE id=?');
        $old->execute([$id]);
        $oldRow = $old->fetch();
        if (!$oldRow) out(false, 'Student not found.');

        db()->prepare('UPDATE students SET lrn=? WHERE id=?')
            ->execute([$lrn !== '' ? $lrn : null, $id]);

        logAudit($adminId, 'update', 'students', $id,
            ['lrn'            => $oldRow['lrn'],
             '_student_name'  => trim(($oldRow['first_name'] ?? '') . ' ' . ($oldRow['last_name'] ?? '')),
             '_student_lrn'   => $oldRow['lrn'] ?? null],
            ['lrn'            => $lrn ?: null]);
        out(true, 'LRN updated successfully.');
    }

    /**
     * Archive or restore a student account.
     * Adds is_archived column if it doesn't exist yet (safe migration).
     */
    case 'archive_student': {
        $adminId = requireAdmin();
        $id      = (int)post('id');
        $archive = post('archive', '1') === '1';

        if (!$id) out(false, 'Missing student ID.');

        // Safe migration: add column if absent
        try {
            db()->exec("ALTER TABLE `students` ADD COLUMN `is_archived` TINYINT(1) NOT NULL DEFAULT 0");
        } catch (PDOException $e) { /* already exists */ }

        $row = db()->prepare('SELECT id, first_name, last_name FROM students WHERE id=?');
        $row->execute([$id]);
        $student = $row->fetch();
        if (!$student) out(false, 'Student not found.');

        db()->prepare('UPDATE students SET is_archived=? WHERE id=?')
            ->execute([$archive ? 1 : 0, $id]);

        logAudit($adminId, $archive ? 'archive' : 'restore', 'students', $id);
        out(true, $archive ? 'Student account archived.' : 'Student account restored.');
    }

    // ════════════════════════════
    // AUDIT LOGS
    // ════════════════════════════
    case 'get_audit_logs': {
        requireAdmin();
        $limit = min((int)post('limit', '50'), 5000);
        $rows  = db()->query(
            "SELECT al.*,
                    COALESCE(
                        NULLIF(TRIM(CONCAT(a.first_name,' ',COALESCE(a.last_name,''))), ''),
                        a.full_name
                    ) AS admin_name
             FROM audit_logs al
             LEFT JOIN admins a ON a.id = al.admin_id
             ORDER BY al.created_at DESC
             LIMIT {$limit}"
        )->fetchAll();
        out(true, '', $rows);
    }

    // ════════════════════════════
    // ROOM MANAGEMENT
    // ════════════════════════════

    case 'get_rooms': {
        requireAdmin();
        $rows = db()->query(
            'SELECT id, number, capacity, status, created_at
             FROM rooms
             ORDER BY CAST(number AS UNSIGNED), number'
        )->fetchAll();
        out(true, '', $rows);
        break;
    }

    case 'add_room': {
        requireAdmin();
        $number   = preg_replace('/[^0-9]/', '', post('number'));
        // Capacity is optional — defaults to 0 and is automatically reflected
        // from the assigned section's max capacity once a section is assigned.
        $capacity = max(0, (int) post('capacity', '0'));

        if ($number === '')  { out(false, 'Room number is required.');          break; }

        // Duplicate check (active rooms only)
        $dup = db()->prepare(
            "SELECT id FROM rooms WHERE number = ? AND status = 'active' LIMIT 1"
        );
        $dup->execute([$number]);
        if ($dup->fetch()) { out(false, "Room {$number} already exists."); break; }

        $stmt = db()->prepare(
            'INSERT INTO rooms (number, capacity, status, created_by) VALUES (?, ?, \'active\', ?)'
        );
        $stmt->execute([$number, $capacity, $_SESSION['admin_id'] ?? null]);
        $newId = (int) db()->lastInsertId();

        logAudit(
            $_SESSION['admin_id'] ?? 0,
            'create', 'rooms', $newId,
            null,
            ['number' => $number, 'capacity' => $capacity]
        );

        $room = db()->prepare('SELECT id, number, capacity, status, created_at FROM rooms WHERE id = ?');
        $room->execute([$newId]);
        out(true, "Room {$number} created successfully.", $room->fetch());
        break;
    }

    case 'archive_room': {
        requireAdmin();
        $id = (int) post('id');
        if (!$id) { out(false, 'Room ID is required.'); break; }

        $row = db()->prepare('SELECT * FROM rooms WHERE id = ? LIMIT 1');
        $row->execute([$id]);
        $room = $row->fetch();
        if (!$room) { out(false, 'Room not found.'); break; }
        if ($room['status'] === 'archived') { out(false, 'Room is already archived.'); break; }

        db()->prepare("UPDATE rooms SET status = 'archived' WHERE id = ?")->execute([$id]);

        logAudit(
            $_SESSION['admin_id'] ?? 0,
            'archive', 'rooms', $id,
            $room,
            ['status' => 'archived']
        );

        out(true, "Room {$room['number']} archived.");
        break;
    }

    case 'restore_room': {
        requireAdmin();
        $id = (int) post('id');
        if (!$id) { out(false, 'Room ID is required.'); break; }

        $row = db()->prepare('SELECT * FROM rooms WHERE id = ? LIMIT 1');
        $row->execute([$id]);
        $room = $row->fetch();
        if (!$room) { out(false, 'Room not found.'); break; }

        // Prevent restoring if the same number already exists as active
        $dup = db()->prepare(
            "SELECT id FROM rooms WHERE number = ? AND status = 'active' AND id != ? LIMIT 1"
        );
        $dup->execute([$room['number'], $id]);
        if ($dup->fetch()) {
            out(false, "Cannot restore — an active Room {$room['number']} already exists.");
            break;
        }

        db()->prepare("UPDATE rooms SET status = 'active' WHERE id = ?")->execute([$id]);

        logAudit(
            $_SESSION['admin_id'] ?? 0,
            'restore', 'rooms', $id,
            $room,
            ['status' => 'active']
        );

        out(true, "Room {$room['number']} restored.");
        break;
    }

    case 'delete_room': {
        requireAdmin();
        $id = (int) post('id');
        if (!$id) { out(false, 'Room ID is required.'); break; }

        $row = db()->prepare('SELECT * FROM rooms WHERE id = ? LIMIT 1');
        $row->execute([$id]);
        $room = $row->fetch();
        if (!$room) { out(false, 'Room not found.'); break; }
        if ($room['status'] !== 'archived') { out(false, 'Only archived rooms can be deleted.'); break; }

        try {
            db()->beginTransaction();
            db()->prepare('DELETE FROM rooms WHERE id = ?')->execute([$id]);
            db()->commit();
            logAudit(
                $_SESSION['admin_id'] ?? 0,
                'delete', 'rooms', $id,
                $room,
                null
            );
            out(true, "Room {$room['number']} permanently deleted.");
        } catch (PDOException $e) {
            db()->rollBack();
            out(false, 'Failed to delete room: ' . $e->getMessage());
        }
        break;
    }

    case 'unassign_room': {
        requireAdmin();
        $sectionId = (int) post('section_id');
        if (!$sectionId) { out(false, 'Section ID is required.'); break; }

        // Fetch section to confirm it exists and capture old room for audit
        $row = db()->prepare('SELECT id, name, room FROM sections WHERE id = ? LIMIT 1');
        $row->execute([$sectionId]);
        $section = $row->fetch();
        if (!$section) { out(false, 'Section not found.'); break; }
        if (empty($section['room'])) { out(false, 'This section has no room assigned.'); break; }

        $oldRoom = $section['room'];

        // Clear the room field — schedules are untouched
        db()->prepare("UPDATE sections SET room = NULL WHERE id = ?")->execute([$sectionId]);

        logAudit(
            $_SESSION['admin_id'] ?? 0,
            'unassign_room', 'sections', $sectionId,
            ['room' => $oldRoom],
            ['room' => null]
        );

        out(true, "Room {$oldRoom} unassigned from {$section['name']}.");
        break;
    }

    /* ═══════════════════════════════════════════════════════
       CAFETERIA · FOOD MENU
    ═══════════════════════════════════════════════════════ */
    case 'get_cafeteria_products': {
        requireAdmin();
        $includeArchived = post('include_archived', '0') === '1';
        $where = $includeArchived ? '' : "WHERE status = 'active'";
        $rows = db()->query(
            "SELECT id, name, image_path, category, price, nutritional_info, status, is_visible, created_at, updated_at
             FROM cafeteria_products
             {$where}
             ORDER BY category, name"
        )->fetchAll();
        out(true, '', $rows);
        break;
    }

    case 'add_cafeteria_product': {
        requireAdmin();
        $name     = post('name');
        $category = post('category', 'other');
        $price    = (float) post('price', '0');
        $nutrition = post('nutritional_info', '');

        requireField($name, 'Product name');
        if (!in_array($category, ['meal', 'snack', 'drink', 'other'], true)) $category = 'other';
        if ($price < 0) { out(false, 'Price cannot be negative.'); break; }

        $dup = db()->prepare("SELECT id FROM cafeteria_products WHERE name = ? AND status = 'active' LIMIT 1");
        $dup->execute([$name]);
        if ($dup->fetch()) { out(false, "\"{$name}\" already exists in the menu."); break; }

        try {
            $imagePath = handleMenuImageUpload();
        } catch (RuntimeException $e) {
            out(false, $e->getMessage()); break;
        }

        $stmt = db()->prepare(
            "INSERT INTO cafeteria_products (name, image_path, category, price, nutritional_info, status, is_visible, created_by)
             VALUES (?, ?, ?, ?, ?, 'active', 1, ?)"
        );
        $stmt->execute([$name, $imagePath, $category, $price, $nutrition !== '' ? $nutrition : null, $_SESSION['admin_id'] ?? null]);
        $newId = (int) db()->lastInsertId();

        // Auto-create an inventory row at 0 stock so it immediately shows in Inventory
        db()->prepare(
            "INSERT INTO cafeteria_inventory (product_id, quantity, low_stock_threshold, updated_by) VALUES (?, 0, 10, ?)"
        )->execute([$newId, $_SESSION['admin_id'] ?? null]);

        logAudit(
            $_SESSION['admin_id'] ?? 0, 'create', 'cafeteria_products', $newId,
            null, ['name' => $name, 'category' => $category, 'price' => $price]
        );

        $row = db()->prepare('SELECT id, name, image_path, category, price, nutritional_info, status, is_visible, created_at FROM cafeteria_products WHERE id = ?');
        $row->execute([$newId]);
        out(true, "{$name} added to the food menu.", $row->fetch());
        break;
    }

    case 'update_cafeteria_product': {
        requireAdmin();
        $id       = (int) post('id');
        $name     = post('name');
        $category = post('category', 'other');
        $price    = (float) post('price', '0');
        $nutrition = post('nutritional_info', '');

        if (!$id) { out(false, 'Product ID is required.'); break; }
        requireField($name, 'Product name');
        if (!in_array($category, ['meal', 'snack', 'drink', 'other'], true)) $category = 'other';
        if ($price < 0) { out(false, 'Price cannot be negative.'); break; }

        $row = db()->prepare('SELECT * FROM cafeteria_products WHERE id = ? LIMIT 1');
        $row->execute([$id]);
        $old = $row->fetch();
        if (!$old) { out(false, 'Product not found.'); break; }

        try {
            $imagePath = handleMenuImageUpload();
        } catch (RuntimeException $e) {
            out(false, $e->getMessage()); break;
        }

        if ($imagePath !== null) {
            db()->prepare('UPDATE cafeteria_products SET name = ?, image_path = ?, category = ?, price = ?, nutritional_info = ? WHERE id = ?')
                ->execute([$name, $imagePath, $category, $price, $nutrition !== '' ? $nutrition : null, $id]);
            // Clean up the old image file if it's being replaced
            if (!empty($old['image_path']) && file_exists(__DIR__ . '/' . $old['image_path'])) {
                @unlink(__DIR__ . '/' . $old['image_path']);
            }
        } else {
            db()->prepare('UPDATE cafeteria_products SET name = ?, category = ?, price = ?, nutritional_info = ? WHERE id = ?')
                ->execute([$name, $category, $price, $nutrition !== '' ? $nutrition : null, $id]);
        }

        logAudit(
            $_SESSION['admin_id'] ?? 0, 'update', 'cafeteria_products', $id,
            $old, ['name' => $name, 'category' => $category, 'price' => $price]
        );

        out(true, "{$name} updated.");
        break;
    }

    case 'toggle_cafeteria_product_visibility': {
        requireAdmin();
        $id = (int) post('id');
        $isVisible = post('is_visible', '1') === '1' ? 1 : 0;
        if (!$id) { out(false, 'Product ID is required.'); break; }

        $row = db()->prepare('SELECT * FROM cafeteria_products WHERE id = ? LIMIT 1');
        $row->execute([$id]);
        $product = $row->fetch();
        if (!$product) { out(false, 'Product not found.'); break; }

        db()->prepare('UPDATE cafeteria_products SET is_visible = ? WHERE id = ?')->execute([$isVisible, $id]);

        logAudit(
            $_SESSION['admin_id'] ?? 0, 'update', 'cafeteria_products', $id,
            ['is_visible' => (int) $product['is_visible']], ['is_visible' => $isVisible]
        );

        out(true, $isVisible ? "{$product['name']} is now available in the menu." : "{$product['name']} is now hidden from the menu.");
        break;
    }

    case 'archive_cafeteria_product': {
        requireAdmin();
        $id = (int) post('id');
        if (!$id) { out(false, 'Product ID is required.'); break; }

        $row = db()->prepare('SELECT * FROM cafeteria_products WHERE id = ? LIMIT 1');
        $row->execute([$id]);
        $product = $row->fetch();
        if (!$product) { out(false, 'Product not found.'); break; }
        if ($product['status'] === 'archived') { out(false, 'Product is already archived.'); break; }

        db()->prepare("UPDATE cafeteria_products SET status = 'archived' WHERE id = ?")->execute([$id]);

        logAudit($_SESSION['admin_id'] ?? 0, 'archive', 'cafeteria_products', $id, $product, ['status' => 'archived']);

        out(true, "{$product['name']} archived.");
        break;
    }

    case 'restore_cafeteria_product': {
        requireAdmin();
        $id = (int) post('id');
        if (!$id) { out(false, 'Product ID is required.'); break; }

        $row = db()->prepare('SELECT * FROM cafeteria_products WHERE id = ? LIMIT 1');
        $row->execute([$id]);
        $product = $row->fetch();
        if (!$product) { out(false, 'Product not found.'); break; }

        db()->prepare("UPDATE cafeteria_products SET status = 'active' WHERE id = ?")->execute([$id]);

        logAudit($_SESSION['admin_id'] ?? 0, 'restore', 'cafeteria_products', $id, $product, ['status' => 'active']);

        out(true, "{$product['name']} restored.");
        break;
    }

    case 'delete_cafeteria_product': {
        requireAdmin();
        $id = (int) post('id');
        if (!$id) { out(false, 'Product ID is required.'); break; }

        $row = db()->prepare('SELECT * FROM cafeteria_products WHERE id = ? LIMIT 1');
        $row->execute([$id]);
        $product = $row->fetch();
        if (!$product) { out(false, 'Product not found.'); break; }
        if ($product['status'] !== 'archived') { out(false, 'Only archived items can be deleted.'); break; }

        try {
            db()->beginTransaction();
            db()->prepare('DELETE FROM cafeteria_products WHERE id = ?')->execute([$id]); // cascades to inventory
            db()->commit();
            if (!empty($product['image_path']) && file_exists(__DIR__ . '/' . $product['image_path'])) {
                @unlink(__DIR__ . '/' . $product['image_path']);
            }
            logAudit($_SESSION['admin_id'] ?? 0, 'delete', 'cafeteria_products', $id, $product, null);
            out(true, "{$product['name']} permanently deleted.");
        } catch (PDOException $e) {
            db()->rollBack();
            out(false, 'Failed to delete product: ' . $e->getMessage());
        }
        break;
    }

    /* ═══════════════════════════════════════════════════════
       CAFETERIA · INVENTORY (stock quantity per product)
    ═══════════════════════════════════════════════════════ */
    case 'get_cafeteria_inventory': {
        requireAdmin();
        ensureCafeteriaInventoryExtras();
        $rows = db()->query(
            "SELECT p.id AS product_id, p.name, p.category, p.price, p.status,
                    COALESCE(i.quantity, 0)             AS quantity,
                    COALESCE(i.low_stock_threshold, 10)  AS low_stock_threshold,
                    i.last_restock_date, i.expiration_date, i.next_restock_date,
                    COALESCE(i.restock_interval_days, 7) AS restock_interval_days,
                    i.updated_at,
                    (SELECT r.quantity_added FROM cafeteria_restock_log r
                       WHERE r.product_id = p.id
                       ORDER BY r.created_at DESC, r.id DESC LIMIT 1) AS last_restock_qty
             FROM cafeteria_products p
             LEFT JOIN cafeteria_inventory i ON i.product_id = p.id
             WHERE p.status = 'active'
             ORDER BY p.category, p.name"
        )->fetchAll();

        $today = date('Y-m-d');
        foreach ($rows as &$r) {
            $qty       = (int) $r['quantity'];
            $threshold = (int) $r['low_stock_threshold'];
            $exp       = $r['expiration_date'];

            if ($qty <= 0) {
                $r['stock_state'] = 'out';
            } elseif ($qty <= $threshold) {
                $r['stock_state'] = 'low';
            } else {
                $r['stock_state'] = 'ok';
            }

            if ($exp && $exp < $today) {
                $r['expiry_state'] = 'expired';
            } elseif ($exp && $exp <= date('Y-m-d', strtotime('+3 days'))) {
                $r['expiry_state'] = 'expiring_soon';
            } else {
                $r['expiry_state'] = 'ok';
            }
        }
        unset($r);

        out(true, '', $rows);
        break;
    }

    case 'update_cafeteria_inventory': {
        // NOTE: Current stock is intentionally NOT editable here. It is only ever
        // changed by record_cafeteria_restock (+), record_cafeteria_sale (-), or
        // record_cafeteria_adjustment (+/- with a reason). This endpoint only
        // touches admin-configurable settings: the low-stock alert threshold and,
        // optionally, a manual override of the next-restock date.
        requireAdmin();
        ensureCafeteriaInventoryExtras();
        $productId          = (int) post('product_id');
        $threshold          = (int) post('low_stock_threshold', '10');
        $nextRestockOverride = post('next_restock_date', '');

        if (!$productId) { out(false, 'Product ID is required.'); break; }
        if ($threshold < 0) $threshold = 0;

        $prod = db()->prepare('SELECT name FROM cafeteria_products WHERE id = ? LIMIT 1');
        $prod->execute([$productId]);
        $p = $prod->fetch();
        if (!$p) { out(false, 'Product not found.'); break; }

        $existing = db()->prepare('SELECT * FROM cafeteria_inventory WHERE product_id = ? LIMIT 1');
        $existing->execute([$productId]);
        $old = $existing->fetch();
        $nextRestock = $nextRestockOverride !== '' ? $nextRestockOverride : ($old['next_restock_date'] ?? null);

        if ($old) {
            db()->prepare('UPDATE cafeteria_inventory SET low_stock_threshold = ?, next_restock_date = ?, updated_by = ? WHERE product_id = ?')
                ->execute([$threshold, $nextRestock, $_SESSION['admin_id'] ?? null, $productId]);
        } else {
            db()->prepare('INSERT INTO cafeteria_inventory (product_id, quantity, low_stock_threshold, next_restock_date, updated_by) VALUES (?, 0, ?, ?, ?)')
                ->execute([$productId, $threshold, $nextRestock, $_SESSION['admin_id'] ?? null]);
        }

        logAudit(
            $_SESSION['admin_id'] ?? 0, 'update', 'cafeteria_inventory', $productId,
            $old ?: null, ['low_stock_threshold' => $threshold, 'next_restock_date' => $nextRestock]
        );

        out(true, "Settings for {$p['name']} updated.");
        break;
    }

    /* ═══════════════════════════════════════════════════════
       CAFETERIA · INVENTORY — STOCK ADJUSTMENT (spoilage,
       damage, expiry, miscount correction — NOT a sale)
    ═══════════════════════════════════════════════════════ */
    case 'record_cafeteria_adjustment': {
        requireAdmin();
        ensureCafeteriaInventoryExtras();

        $productId    = (int) post('product_id');
        $qtyRemoved   = (int) post('quantity_removed', '0');
        $reason       = post('reason', 'other');
        $notes        = post('notes', '');
        $validReasons = ['spoilage', 'damage', 'expired', 'correction', 'other'];

        if (!$productId) { out(false, 'Product ID is required.'); break; }
        if ($qtyRemoved <= 0) { out(false, 'Enter a valid quantity to remove.'); break; }
        if (!in_array($reason, $validReasons, true)) $reason = 'other';

        $prod = db()->prepare('SELECT name FROM cafeteria_products WHERE id = ? LIMIT 1');
        $prod->execute([$productId]);
        $p = $prod->fetch();
        if (!$p) { out(false, 'Product not found.'); break; }

        $existing = db()->prepare('SELECT * FROM cafeteria_inventory WHERE product_id = ? LIMIT 1');
        $existing->execute([$productId]);
        $old = $existing->fetch();
        $currentQty = $old ? (int) $old['quantity'] : 0;

        if ($qtyRemoved > $currentQty) { out(false, "Only {$currentQty} unit(s) of {$p['name']} in stock."); break; }

        $newQty = $currentQty - $qtyRemoved;

        if ($old) {
            db()->prepare('UPDATE cafeteria_inventory SET quantity = ?, updated_by = ? WHERE product_id = ?')
                ->execute([$newQty, $_SESSION['admin_id'] ?? null, $productId]);
        } else {
            db()->prepare('INSERT INTO cafeteria_inventory (product_id, quantity, low_stock_threshold, updated_by) VALUES (?, ?, 10, ?)')
                ->execute([$productId, $newQty, $_SESSION['admin_id'] ?? null]);
        }

        db()->prepare(
            'INSERT INTO cafeteria_stock_adjustments (product_id, quantity_delta, reason, notes, adjusted_by)
             VALUES (?, ?, ?, ?, ?)'
        )->execute([$productId, -$qtyRemoved, $reason, $notes !== '' ? $notes : null, $_SESSION['admin_id'] ?? null]);

        logAudit(
            $_SESSION['admin_id'] ?? 0, 'adjust', 'cafeteria_inventory', $productId,
            $old ?: null, ['quantity_removed' => $qtyRemoved, 'reason' => $reason, 'new_quantity' => $newQty]
        );

        out(true, "Removed {$qtyRemoved} unit(s) of {$p['name']} ({$reason}). Now {$newQty} in stock.");
        break;
    }

    /* ═══════════════════════════════════════════════════════
       CAFETERIA · INVENTORY — RESTOCK (receive new stock)
    ═══════════════════════════════════════════════════════ */
    case 'record_cafeteria_restock': {
        requireAdmin();
        ensureCafeteriaInventoryExtras();

        $productId    = (int) post('product_id');
        $qtyAdded     = (int) post('quantity_added', '0');
        $receivedDate = post('received_date', date('Y-m-d'));
        $expDate      = post('expiration_date', '');
        $interval     = (int) post('restock_interval_days', '7');
        $costPerUnit  = post('cost_per_unit', '');
        $notes        = post('notes', '');

        if (!$productId) { out(false, 'Product ID is required.'); break; }
        if ($qtyAdded <= 0) { out(false, 'Quantity received must be greater than zero.'); break; }
        if ($interval <= 0) $interval = 7;
        if ($receivedDate > date('Y-m-d')) { out(false, 'Date received cannot be in the future.'); break; }

        $prod = db()->prepare('SELECT name FROM cafeteria_products WHERE id = ? LIMIT 1');
        $prod->execute([$productId]);
        $p = $prod->fetch();
        if (!$p) { out(false, 'Product not found.'); break; }

        $nextRestock = date('Y-m-d', strtotime($receivedDate . " +{$interval} days"));

        $existing = db()->prepare('SELECT * FROM cafeteria_inventory WHERE product_id = ? LIMIT 1');
        $existing->execute([$productId]);
        $old = $existing->fetch();
        $newQty = ($old ? (int) $old['quantity'] : 0) + $qtyAdded;

        if ($old) {
            db()->prepare(
                'UPDATE cafeteria_inventory
                 SET quantity = ?, last_restock_date = ?, expiration_date = ?, next_restock_date = ?,
                     restock_interval_days = ?, updated_by = ?
                 WHERE product_id = ?'
            )->execute([$newQty, $receivedDate, $expDate !== '' ? $expDate : null, $nextRestock, $interval, $_SESSION['admin_id'] ?? null, $productId]);
        } else {
            db()->prepare(
                'INSERT INTO cafeteria_inventory
                    (product_id, quantity, low_stock_threshold, last_restock_date, expiration_date, next_restock_date, restock_interval_days, updated_by)
                 VALUES (?, ?, 10, ?, ?, ?, ?, ?)'
            )->execute([$productId, $newQty, $receivedDate, $expDate !== '' ? $expDate : null, $nextRestock, $interval, $_SESSION['admin_id'] ?? null]);
        }

        db()->prepare(
            'INSERT INTO cafeteria_restock_log
                (product_id, quantity_added, received_date, expiration_date, next_restock_date, cost_per_unit, notes, restocked_by)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        )->execute([
            $productId, $qtyAdded, $receivedDate, $expDate !== '' ? $expDate : null, $nextRestock,
            $costPerUnit !== '' ? (float) $costPerUnit : null, $notes !== '' ? $notes : null, $_SESSION['admin_id'] ?? null
        ]);

        logAudit(
            $_SESSION['admin_id'] ?? 0, 'restock', 'cafeteria_inventory', $productId,
            $old ?: null, ['quantity_added' => $qtyAdded, 'new_quantity' => $newQty, 'received_date' => $receivedDate, 'expiration_date' => $expDate]
        );

        out(true, "Restocked {$p['name']}: +{$qtyAdded} units (now {$newQty}).");
        break;
    }

    /* ═══════════════════════════════════════════════════════
       CAFETERIA · INVENTORY — RECORD SALE / DEDUCTION
    ═══════════════════════════════════════════════════════ */
    case 'record_cafeteria_sale': {
        requireAdmin();
        ensureCafeteriaInventoryExtras();

        $productId = (int) post('product_id');
        $qtySold   = (int) post('quantity_sold', '0');
        $unitPrice = post('unit_price', '');
        $reason    = post('reason', 'sale');
        $notes     = post('notes', '');

        if (!$productId) { out(false, 'Product ID is required.'); break; }
        if ($qtySold <= 0) { out(false, 'Quantity must be greater than zero.'); break; }
        if (!in_array($reason, ['sale', 'spoilage', 'waste', 'correction'], true)) $reason = 'sale';

        $prod = db()->prepare('SELECT name, price FROM cafeteria_products WHERE id = ? LIMIT 1');
        $prod->execute([$productId]);
        $p = $prod->fetch();
        if (!$p) { out(false, 'Product not found.'); break; }

        $price = $unitPrice !== '' ? (float) $unitPrice : (float) $p['price'];
        if ($price < 0) { out(false, 'Unit price cannot be negative.'); break; }

        $existing = db()->prepare('SELECT * FROM cafeteria_inventory WHERE product_id = ? LIMIT 1');
        $existing->execute([$productId]);
        $old = $existing->fetch();
        $currentQty = $old ? (int) $old['quantity'] : 0;

        if ($qtySold > $currentQty) { out(false, "Only {$currentQty} unit(s) of {$p['name']} left in stock."); break; }

        $newQty = $currentQty - $qtySold;
        $total  = round($price * $qtySold, 2);

        if ($old) {
            db()->prepare('UPDATE cafeteria_inventory SET quantity = ?, updated_by = ? WHERE product_id = ?')
                ->execute([$newQty, $_SESSION['admin_id'] ?? null, $productId]);
        } else {
            db()->prepare('INSERT INTO cafeteria_inventory (product_id, quantity, low_stock_threshold, updated_by) VALUES (?, ?, 10, ?)')
                ->execute([$productId, $newQty, $_SESSION['admin_id'] ?? null]);
        }

        db()->prepare(
            'INSERT INTO cafeteria_sales_log (product_id, quantity_sold, unit_price, total_amount, reason, notes, recorded_by)
             VALUES (?, ?, ?, ?, ?, ?, ?)'
        )->execute([$productId, $qtySold, $price, $total, $reason, $notes !== '' ? $notes : null, $_SESSION['admin_id'] ?? null]);

        logAudit(
            $_SESSION['admin_id'] ?? 0, 'deduct', 'cafeteria_inventory', $productId,
            $old ?: null, ['quantity_sold' => $qtySold, 'reason' => $reason, 'new_quantity' => $newQty]
        );

        out(true, "Recorded {$qtySold} unit(s) of {$p['name']} (₱" . number_format($total, 2) . ").");
        break;
    }

    /* ═══════════════════════════════════════════════════════
       CAFETERIA · INVENTORY — DETAILED VIEW (history + stats)
    ═══════════════════════════════════════════════════════ */
    case 'get_cafeteria_inventory_detail': {
        requireAdmin();
        ensureCafeteriaInventoryExtras();

        $productId = (int) post('product_id');
        if (!$productId) { out(false, 'Product ID is required.'); break; }

        $prod = db()->prepare(
            "SELECT p.id AS product_id, p.name, p.category, p.price,
                    COALESCE(i.quantity, 0) AS quantity,
                    COALESCE(i.low_stock_threshold, 10) AS low_stock_threshold,
                    i.last_restock_date, i.expiration_date, i.next_restock_date,
                    COALESCE(i.restock_interval_days, 7) AS restock_interval_days
             FROM cafeteria_products p
             LEFT JOIN cafeteria_inventory i ON i.product_id = p.id
             WHERE p.id = ? LIMIT 1"
        );
        $prod->execute([$productId]);
        $product = $prod->fetch();
        if (!$product) { out(false, 'Product not found.'); break; }

        $restockStmt = db()->prepare(
            'SELECT r.*, a.full_name AS restocked_by_name
             FROM cafeteria_restock_log r
             LEFT JOIN admins a ON a.id = r.restocked_by
             WHERE r.product_id = ? ORDER BY r.created_at DESC LIMIT 25'
        );
        $restockStmt->execute([$productId]);
        $restockRows = $restockStmt->fetchAll();

        $salesStmt = db()->prepare(
            'SELECT s.*, a.full_name AS recorded_by_name
             FROM cafeteria_sales_log s
             LEFT JOIN admins a ON a.id = s.recorded_by
             WHERE s.product_id = ? AND s.reason = \'sale\' ORDER BY s.sold_at DESC LIMIT 25'
        );
        $salesStmt->execute([$productId]);
        $salesRows = $salesStmt->fetchAll();

        $adjStmt = db()->prepare(
            'SELECT j.*, a.full_name AS adjusted_by_name
             FROM cafeteria_stock_adjustments j
             LEFT JOIN admins a ON a.id = j.adjusted_by
             WHERE j.product_id = ? ORDER BY j.adjusted_at DESC LIMIT 25'
        );
        $adjStmt->execute([$productId]);
        $adjRows = $adjStmt->fetchAll();

        // Aggregate stats — real sales only (reason = 'sale')
        $statsStmt = db()->prepare(
            "SELECT COUNT(*) AS sale_count, COALESCE(SUM(quantity_sold),0) AS total_units,
                    COALESCE(SUM(total_amount),0) AS total_revenue,
                    MIN(sold_at) AS first_sale, MAX(sold_at) AS last_sale
             FROM cafeteria_sales_log WHERE product_id = ? AND reason = 'sale'"
        );
        $statsStmt->execute([$productId]);
        $stats = $statsStmt->fetch() ?: ['sale_count' => 0, 'total_units' => 0, 'total_revenue' => 0, 'first_sale' => null, 'last_sale' => null];

        $restockAggStmt = db()->prepare('SELECT COUNT(*) AS c, COALESCE(SUM(quantity_added),0) AS total_received FROM cafeteria_restock_log WHERE product_id = ?');
        $restockAggStmt->execute([$productId]);
        $restockAgg = $restockAggStmt->fetch() ?: ['c' => 0, 'total_received' => 0];

        $adjAggStmt = db()->prepare(
            "SELECT COALESCE(SUM(CASE WHEN quantity_delta < 0 THEN -quantity_delta ELSE 0 END),0) AS total_removed
             FROM cafeteria_stock_adjustments WHERE product_id = ?"
        );
        $adjAggStmt->execute([$productId]);
        $adjAgg = $adjAggStmt->fetch() ?: ['total_removed' => 0];

        // Average units sold per day since the first recorded sale
        $avgDaily = 0.0;
        if (!empty($stats['first_sale']) && (int) $stats['total_units'] > 0) {
            $days = max(1, (int) ((strtotime('now') - strtotime($stats['first_sale'])) / 86400));
            $avgDaily = round((int) $stats['total_units'] / $days, 2);
        }

        $daysOfStockLeft = $avgDaily > 0 ? floor(((int) $product['quantity']) / $avgDaily) : null;

        out(true, '', [
            'product'            => $product,
            'restock_history'    => $restockRows,
            'sales_history'      => $salesRows,
            'adjustment_history' => $adjRows,
            'stats' => [
                'sale_count'           => (int) $stats['sale_count'],
                'total_units_sold'     => (int) $stats['total_units'],
                'total_revenue'        => (float) $stats['total_revenue'],
                'restock_count'        => (int) $restockAgg['c'],
                'total_units_received' => (int) $restockAgg['total_received'],
                'total_units_removed'  => (int) $adjAgg['total_removed'],
                'avg_daily_deduction'  => $avgDaily,
                'days_of_stock_left'   => $daysOfStockLeft,
                'last_sale_at'         => $stats['last_sale'],
            ],
        ]);
        break;
    }

    /* ═══════════════════════════════════════════════════════
       CAFETERIA · STUDENT WALLET
    ═══════════════════════════════════════════════════════ */
    case 'get_student_wallets': {
        requireAdmin();
        $gradeId   = (int) post('grade_level_id', '0');
        $sectionId = (int) post('section_id', '0');
        $search    = post('search', '');

        $where  = ['s.is_archived = 0'];
        $params = [];
        if ($gradeId >= 7 && $gradeId <= 10) { $where[] = 'gl.level = ?'; $params[] = $gradeId; }
        if ($sectionId > 0) { $where[] = 'sec.id = ?'; $params[] = $sectionId; }
        if ($search !== '') {
            $where[] = '(s.first_name LIKE ? OR s.last_name LIKE ?)';
            $like = "%{$search}%";
            array_push($params, $like, $like);
        }
        $whereSql = 'WHERE ' . implode(' AND ', $where);

        // Section comes from the student's profile assignment for the ACTIVE school year:
        // student_profiles.section_sy_id -> section_school_years.section_id -> sections
        $sql = "SELECT s.id AS student_id, s.lrn AS lrn,
                       TRIM(CONCAT(s.first_name,' ',COALESCE(s.middle_name,''),' ',s.last_name)) AS full_name,
                       gl.display_name AS grade_display, gl.level AS grade_level,
                       sec.id AS section_id, sec.name AS section_name,
                       COALESCE(w.balance, 0.00) AS balance,
                       w.updated_at AS wallet_updated_at
                FROM students s
                LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
                LEFT JOIN student_profiles sp ON sp.student_id = s.id
                LEFT JOIN section_school_years ssy ON ssy.id = sp.section_sy_id
                LEFT JOIN sections sec ON sec.id = ssy.section_id
                LEFT JOIN student_wallets w ON w.student_id = s.id
                {$whereSql}
                ORDER BY gl.level ASC, sec.name ASC, s.last_name ASC, s.first_name ASC";

        $stmt = db()->prepare($sql);
        $stmt->execute($params);
        out(true, '', $stmt->fetchAll());
        break;
    }

    /* ═══════════════════════════════════════════════════════
       CAFETERIA · WALLET SETTINGS (max top-up per transaction)
    ═══════════════════════════════════════════════════════ */
    case 'get_cafeteria_settings': {
        requireAdmin();
        $row = db()->query('SELECT max_topup_amount FROM cafeteria_settings WHERE id = 1 LIMIT 1')->fetch();
        out(true, '', ['max_topup_amount' => $row ? (float) $row['max_topup_amount'] : 0.00]);
        break;
    }

    case 'update_cafeteria_settings': {
        $adminId = requireAdmin();
        $maxTopup = (float) post('max_topup_amount', '0');
        if ($maxTopup < 0) { out(false, 'Limit cannot be negative.'); break; }

        $old = db()->query('SELECT max_topup_amount FROM cafeteria_settings WHERE id = 1 LIMIT 1')->fetch();

        if ($old) {
            db()->prepare('UPDATE cafeteria_settings SET max_topup_amount = ?, updated_by = ? WHERE id = 1')
                ->execute([$maxTopup, $adminId]);
        } else {
            db()->prepare('INSERT INTO cafeteria_settings (id, max_topup_amount, updated_by) VALUES (1, ?, ?)')
                ->execute([$maxTopup, $adminId]);
        }

        logAudit(
            $adminId, 'update', 'cafeteria_settings', 1,
            $old ?: null, ['max_topup_amount' => $maxTopup]
        );

        $msg = $maxTopup > 0
            ? 'Maximum top-up per transaction set to ₱' . number_format($maxTopup, 2) . '.'
            : 'Top-up limit removed — admins can add any amount.';
        out(true, $msg, ['max_topup_amount' => $maxTopup]);
        break;
    }

    case 'adjust_student_wallet': {
        $adminId   = requireAdmin();
        $studentId = (int) post('student_id');
        $type      = post('type');
        $amount    = (float) post('amount', '0');
        $note      = post('note', '');

        if (!$studentId) { out(false, 'Student is required.'); break; }
        if (!in_array($type, ['credit', 'debit'], true)) { out(false, 'Invalid transaction type.'); break; }
        if ($amount <= 0) { out(false, 'Amount must be greater than zero.'); break; }

        if ($type === 'credit') {
            $limitRow = db()->query('SELECT max_topup_amount FROM cafeteria_settings WHERE id = 1 LIMIT 1')->fetch();
            $maxTopup = $limitRow ? (float) $limitRow['max_topup_amount'] : 0.00;
            if ($maxTopup > 0 && $amount > $maxTopup) {
                out(false, 'Amount exceeds the maximum top-up limit of ₱' . number_format($maxTopup, 2) . ' per transaction.');
                break;
            }
        }

        $stu = db()->prepare('SELECT id, first_name, last_name FROM students WHERE id = ? AND is_archived = 0 LIMIT 1');
        $stu->execute([$studentId]);
        $student = $stu->fetch();
        if (!$student) { out(false, 'Student not found.'); break; }

        try {
            db()->beginTransaction();

            $w = db()->prepare('SELECT * FROM student_wallets WHERE student_id = ? LIMIT 1 FOR UPDATE');
            $w->execute([$studentId]);
            $wallet = $w->fetch();

            $currentBalance = $wallet ? (float) $wallet['balance'] : 0.00;

            if ($type === 'debit' && $amount > $currentBalance) {
                db()->rollBack();
                out(false, 'Insufficient wallet balance for this deduction.');
                break;
            }

            $newBalance = $type === 'credit' ? $currentBalance + $amount : $currentBalance - $amount;

            if ($wallet) {
                db()->prepare('UPDATE student_wallets SET balance = ? WHERE student_id = ?')->execute([$newBalance, $studentId]);
            } else {
                db()->prepare('INSERT INTO student_wallets (student_id, balance) VALUES (?, ?)')->execute([$studentId, $newBalance]);
            }

            db()->prepare(
                'INSERT INTO wallet_transactions (student_id, admin_id, type, amount, balance_after, note) VALUES (?, ?, ?, ?, ?, ?)'
            )->execute([$studentId, $adminId, $type, $amount, $newBalance, $note !== '' ? $note : null]);

            db()->commit();

            logAudit(
                $adminId, $type === 'credit' ? 'added' : 'deducted', 'student_wallets', $studentId,
                ['balance' => $currentBalance, '_student_name' => trim($student['first_name'] . ' ' . $student['last_name'])],
                ['balance' => $newBalance, 'note' => $note]
            );

            $fullName = trim($student['first_name'] . ' ' . $student['last_name']);
            $verb     = $type === 'credit' ? 'added to' : 'deducted from';
            out(true, '₱' . number_format($amount, 2) . " {$verb} {$fullName}'s wallet.", ['balance' => $newBalance]);
        } catch (PDOException $e) {
            db()->rollBack();
            out(false, 'Failed to update wallet: ' . $e->getMessage());
        }
        break;
    }

    case 'bulk_credit_student_wallets': {
        $adminId    = requireAdmin();
        $studentIds = post('student_ids', '');
        $amount     = (float) post('amount', '0');
        $note       = post('note', '');

        $ids = array_values(array_unique(array_filter(array_map('intval', explode(',', (string) $studentIds)))));

        if (empty($ids)) { out(false, 'Select at least one student.'); break; }
        if ($amount <= 0) { out(false, 'Amount must be greater than zero.'); break; }

        $limitRow = db()->query('SELECT max_topup_amount FROM cafeteria_settings WHERE id = 1 LIMIT 1')->fetch();
        $maxTopup = $limitRow ? (float) $limitRow['max_topup_amount'] : 0.00;
        if ($maxTopup > 0 && $amount > $maxTopup) {
            out(false, 'Amount exceeds the maximum top-up limit of ₱' . number_format($maxTopup, 2) . ' per transaction.');
            break;
        }

        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $stu = db()->prepare("SELECT id, first_name, last_name FROM students WHERE id IN ($placeholders) AND is_archived = 0");
        $stu->execute($ids);
        $students = $stu->fetchAll();
        if (empty($students)) { out(false, 'No valid students found.'); break; }

        $successCount = 0;

        try {
            foreach ($students as $student) {
                $studentId = (int) $student['id'];

                db()->beginTransaction();

                $w = db()->prepare('SELECT * FROM student_wallets WHERE student_id = ? LIMIT 1 FOR UPDATE');
                $w->execute([$studentId]);
                $wallet = $w->fetch();

                $currentBalance = $wallet ? (float) $wallet['balance'] : 0.00;
                $newBalance     = $currentBalance + $amount;

                if ($wallet) {
                    db()->prepare('UPDATE student_wallets SET balance = ? WHERE student_id = ?')->execute([$newBalance, $studentId]);
                } else {
                    db()->prepare('INSERT INTO student_wallets (student_id, balance) VALUES (?, ?)')->execute([$studentId, $newBalance]);
                }

                db()->prepare(
                    'INSERT INTO wallet_transactions (student_id, admin_id, type, amount, balance_after, note) VALUES (?, ?, "credit", ?, ?, ?)'
                )->execute([$studentId, $adminId, $amount, $newBalance, $note !== '' ? $note : null]);

                db()->commit();

                logAudit(
                    $adminId, 'added', 'student_wallets', $studentId,
                    ['balance' => $currentBalance, '_student_name' => trim($student['first_name'] . ' ' . $student['last_name'])],
                    ['balance' => $newBalance, 'note' => $note]
                );

                $successCount++;
            }

            out(true, '₱' . number_format($amount, 2) . " added to {$successCount} student wallet" . ($successCount === 1 ? '' : 's') . '.', ['count' => $successCount]);
        } catch (PDOException $e) {
            if (db()->inTransaction()) db()->rollBack();
            out(false, 'Failed to update wallets: ' . $e->getMessage());
        }
        break;
    }

    case 'get_wallet_transactions': {
        requireAdmin();
        $studentId = (int) post('student_id');
        if (!$studentId) { out(false, 'Student ID is required.'); break; }

        $stmt = db()->prepare(
            "SELECT t.id, t.type, t.amount, t.balance_after, t.note, t.created_at,
                    TRIM(CONCAT(a.first_name,' ',a.last_name)) AS admin_name
             FROM wallet_transactions t
             LEFT JOIN admins a ON a.id = t.admin_id
             WHERE t.student_id = ?
             ORDER BY t.created_at DESC
             LIMIT 100"
        );
        $stmt->execute([$studentId]);
        out(true, '', $stmt->fetchAll());
        break;
    }

    default:
        out(false, 'Unknown action: ' . htmlspecialchars($action));
}