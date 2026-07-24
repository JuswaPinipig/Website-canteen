<?php
/**
 * SJC Portal — loginverify.php
 * ─────────────────────────────────────────────────────────
 * Verifies the OTP entered by the user.
 *
 * On success:
 *   - Writes final session data (role-specific IDs, flags)
 *   - ★ NEW: Registers this browser as a trusted device for 7 days
 *       (stores SHA-256 of a random token in trusted_devices,
 *        sends the raw token in a secure HTTP-only cookie)
 *   - Returns redirect URL pulled from the logindb role_redirects table
 *
 * On failure:
 *   - Returns error message — NO session modification
 */

session_start();
header('Content-Type: application/json');

require_once 'logindb.php'; // $conn (PDO)

// ── Helper: JSON exit ─────────────────────────────────────
function respond(array $payload): void {
    echo json_encode($payload);
    exit;
}

// ── Guard: POST only ──────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(['success' => false, 'message' => 'Invalid request method.']);
}

// ── 1. Check required session keys ───────────────────────
$requiredKeys = ['otp_hash', 'otp_expiry', 'otp_user_id', 'otp_role', 'otp_email', 'otp_redirect'];
foreach ($requiredKeys as $key) {
    if (empty($_SESSION[$key])) {
        respond(['success' => false, 'message' => 'Session expired. Please log in again.']);
    }
}
$_SESSION['otp_remember_me'] = !empty($_SESSION['otp_remember_me']);

// ── 2. Check OTP expiry ───────────────────────────────────
if (time() > (int)$_SESSION['otp_expiry']) {
    clearOtpSession();
    respond(['success' => false, 'message' => 'OTP has expired. Please log in again.']);
}

// ── 3. Read and verify OTP ────────────────────────────────
$enteredOtp = trim($_POST['otp'] ?? '');

if (!preg_match('/^\d{6}$/', $enteredOtp)) {
    respond(['success' => false, 'message' => 'Please enter a valid 6-digit code.']);
}

if (!password_verify($enteredOtp, $_SESSION['otp_hash'])) {
    respond(['success' => false, 'message' => 'Incorrect code. Please try again.']);
}

// ── 4. OTP is valid — build session ───────────────────────
$role     = strtolower(trim($_SESSION['otp_role']));
$userId   = (int)$_SESSION['otp_user_id'];
$redirect = $_SESSION['otp_redirect'];

// ── 4a. Generate a secure session token ───────────────────
$sessionToken = bin2hex(random_bytes(32));

try {
    $conn->prepare(
        "UPDATE users SET session_token = ?, session_token_created_at = NOW() WHERE id = ?"
    )->execute([$sessionToken, $userId]);
} catch (PDOException $e) {
    error_log('[loginverify] session_token update: ' . $e->getMessage());
    respond(['success' => false, 'message' => 'Session error. Please try again.']);
}

// ── 4b. ★ Register trusted device for 14 days (opt-in) ───
// Only register if the user checked "Trust this device" on the OTP modal.
// The JS sends trust_device=1 in the POST body when the checkbox is checked.
// If omitted or 0 → no trusted-device cookie is set, OTP is required next time.
$trustDevice = !empty($_POST['trust_device']) && $_POST['trust_device'] === '1';
if ($trustDevice) {
    registerTrustedDevice($userId, $conn);
}

// ── 4c. Handle "Remember Me" ──────────────────────────────
$rememberMe = !empty($_SESSION['otp_remember_me']);

if ($rememberMe) {
    $rememberRaw    = bin2hex(random_bytes(32));
    $rememberHash   = hash('sha256', $rememberRaw);
    $rememberExpiry = time() + (30 * 24 * 3600); // 30 days

    try {
        $conn->prepare("DELETE FROM remember_me_tokens WHERE user_id = ?")->execute([$userId]);
        $conn->prepare(
            "INSERT INTO remember_me_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)"
        )->execute([$userId, $rememberHash, date('Y-m-d H:i:s', $rememberExpiry)]);

        $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
        setcookie('remember_token', $rememberRaw, [
            'expires'  => $rememberExpiry,
            'path'     => '/',
            'secure'   => $isHttps,
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
    } catch (PDOException $e) {
        error_log('[loginverify] remember_me insert: ' . $e->getMessage());
    }
}

// ── 4d. Build PHP session ────────────────────────────────
$_SESSION['user_id']       = $userId;
$_SESSION['user_email']    = $_SESSION['otp_email'];
$_SESSION['user_role']     = $role;
$_SESSION['role']          = $role;
$_SESSION['logged_in']     = true;
$_SESSION['session_token'] = $sessionToken;

// ── 4e. Role-specific session enrichment ─────────────────

if ($role === 'student') {
    $result = resolveStudentId($userId);

    if (!$result['success']) {
        clearOtpSession();
        respond([
            'success' => false,
            'message' => 'Your enrollment is still being processed. '
                       . 'Please wait for the Registrar\'s Office to complete your registration before logging in.'
        ]);
    }

    $_SESSION['student_id']          = $result['student_id'];
    $_SESSION['lrn']                 = $result['lrn'];
    $_SESSION['enrollment_status']   = $result['enrollment_status'];
    $_SESSION['registration_status'] = $result['registration_status'];
}

if ($role === 'admin') {
    try {
        $schoolConn = new PDO("mysql:host=localhost;dbname=school_system;charset=utf8mb4","root","");
        $schoolConn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

        $userStmt = $conn->prepare("SELECT school_email, personal_email FROM users WHERE id = ? LIMIT 1");
        $userStmt->execute([$userId]);
        $userDetails = $userStmt->fetch(PDO::FETCH_ASSOC);

        $schoolConn->prepare("
            INSERT INTO admins (user_id, school_email, personal_email, role)
            VALUES (?, ?, ?, 'admin')
            ON DUPLICATE KEY UPDATE school_email=VALUES(school_email),personal_email=VALUES(personal_email),role='admin'
        ")->execute([$userId, $userDetails['school_email'] ?? null, $userDetails['personal_email'] ?? null]);

        $stmt = $schoolConn->prepare("SELECT id FROM admins WHERE user_id = ? LIMIT 1");
        $stmt->execute([$userId]);
        $adminRow = $stmt->fetch(PDO::FETCH_ASSOC);
        $_SESSION['admin_id'] = (int)$adminRow['id'];

    } catch (PDOException $e) {
        error_log('[loginverify] resolveAdminId failed: ' . $e->getMessage());
        clearOtpSession();
        respond(['success' => false, 'message' => 'Session error. Please try again.']);
    }
}

if ($role === 'teacher') {
    $_SESSION['teacher_id'] = resolveTeacherId($userId);
}

if ($role === 'coordinator') {
    try {
        $schoolConn = new PDO("mysql:host=localhost;dbname=school_system;charset=utf8mb4","root","");
        $schoolConn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $stmt = $schoolConn->prepare("SELECT id FROM coordinators WHERE user_id = ? AND is_active = 1 LIMIT 1");
        $stmt->execute([$userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) $_SESSION['coordinator_id'] = (int)$row['id'];
    } catch (PDOException $e) {
        error_log('[loginverify] resolveCoordinatorId failed: ' . $e->getMessage());
    }
}

if ($role === 'cashier') {
    try {
        $schoolConn = new PDO("mysql:host=localhost;dbname=school_system;charset=utf8mb4","root","");
        $schoolConn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $stmt = $schoolConn->prepare("SELECT id FROM cashiers WHERE user_id = ? LIMIT 1");
        $stmt->execute([$userId]);
        $cashierRow = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($cashierRow) $_SESSION['cashier_id'] = (int)$cashierRow['id'];
    } catch (PDOException $e) {
        error_log('[loginverify] resolveCashier: ' . $e->getMessage());
    }
}

// ── 5. Clean up OTP session ───────────────────────────────
clearOtpSession();

// ── 6. Respond with redirect URL ─────────────────────────
respond([
    'success'               => true,
    'message'               => 'Login successful.',
    'redirect'              => $redirect,
    'trust_device_registered' => $trustDevice,
]);


// ═════════════════════════════════════════════════════════
//  ★ NEW HELPER — Register Trusted Device
// ═════════════════════════════════════════════════════════

/**
 * Called once after a successful OTP verification.
 *
 * - Generates a cryptographically random 32-byte raw token
 * - Stores SHA-256(rawToken) in trusted_devices (7-day expiry)
 * - Sends the raw token in an HTTP-only cookie named `trusted_device`
 *
 * On the NEXT login, login.php:
 *   1. Reads the cookie
 *   2. SHA-256 hashes it
 *   3. Looks it up in trusted_devices WHERE user_id=? AND expires_at > NOW()
 *   4. If found → skips OTP → logs in directly
 *
 * Device label is built from the User-Agent for human readability
 * (e.g. in a future "manage devices" admin page).
 *
 * @param int $userId
 * @param PDO $conn
 */
function registerTrustedDevice(int $userId, PDO $conn): void
{
    try {
        // ── Generate token ────────────────────────────────
        $rawToken  = bin2hex(random_bytes(32)); // 64 hex chars — goes in cookie
        $tokenHash = hash('sha256', $rawToken); // only this goes in DB

        // ── 14-day expiry ─────────────────────────────────
        $expiryTs  = time() + (14 * 24 * 3600);
        $expiryDt  = date('Y-m-d H:i:s', $expiryTs);

        // ── Build a human-readable device label ──────────
        // Stored for future "active devices" management pages.
        $ua          = $_SERVER['HTTP_USER_AGENT'] ?? 'Unknown browser';
        $deviceLabel = buildDeviceLabel($ua);

        // ── IP for audit trail ────────────────────────────
        $ip = $_SERVER['HTTP_X_FORWARDED_FOR']
            ?? $_SERVER['REMOTE_ADDR']
            ?? null;
        if ($ip) {
            // If behind a proxy, take the first IP in the list
            $ip = trim(explode(',', $ip)[0]);
        }

        // ── Delete any existing trusted device tokens ─────
        // We keep ONE trusted device per user by default.
        // If you want to support multiple devices simultaneously,
        // comment out the DELETE below and just INSERT.
        // (The UNIQUE constraint on token_hash prevents duplicates.)
        $conn->prepare(
            "DELETE FROM trusted_devices WHERE user_id = ?"
        )->execute([$userId]);

        // ── Insert new trusted device record ──────────────
        $conn->prepare(
            "INSERT INTO trusted_devices
                (user_id, token_hash, device_label, expires_at, confirmed_ip)
             VALUES (?, ?, ?, ?, ?)"
        )->execute([$userId, $tokenHash, $deviceLabel, $expiryDt, $ip]);

        // ── Send cookie to browser ────────────────────────
        // HttpOnly  = JS cannot read it (XSS protection)
        // Secure    = HTTPS only (change to true in production)
        // SameSite  = Lax prevents CSRF
        // Expires   = matches the DB expiry (7 days)
        $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');

        setcookie('trusted_device', $rawToken, [
            'expires'  => $expiryTs,
            'path'     => '/',
            'secure'   => $isHttps,   // ← set true in production (HTTPS)
            'httponly' => true,
            'samesite' => 'Lax',
        ]);

    } catch (PDOException $e) {
        // Non-fatal — user still logs in normally, just won't be trusted next time
        error_log('[loginverify] registerTrustedDevice: ' . $e->getMessage());
    }
}

/**
 * Build a short human-readable label from a User-Agent string.
 * Examples:
 *   "Chrome on Windows"
 *   "Firefox on Mac"
 *   "Safari on iPhone"
 *   "Edge on Windows"
 *
 * @param string $ua
 * @return string
 */
function buildDeviceLabel(string $ua): string
{
    // Browser detection (order matters — Edge/Chrome share keywords)
    $browser = 'Unknown Browser';
    if (str_contains($ua, 'Edg/'))          $browser = 'Edge';
    elseif (str_contains($ua, 'OPR/'))      $browser = 'Opera';
    elseif (str_contains($ua, 'Chrome/'))   $browser = 'Chrome';
    elseif (str_contains($ua, 'Firefox/'))  $browser = 'Firefox';
    elseif (str_contains($ua, 'Safari/'))   $browser = 'Safari';

    // OS detection
    $os = 'Unknown OS';
    if (str_contains($ua, 'iPhone'))        $os = 'iPhone';
    elseif (str_contains($ua, 'iPad'))      $os = 'iPad';
    elseif (str_contains($ua, 'Android'))   $os = 'Android';
    elseif (str_contains($ua, 'Windows'))   $os = 'Windows';
    elseif (str_contains($ua, 'Macintosh')) $os = 'Mac';
    elseif (str_contains($ua, 'Linux'))     $os = 'Linux';

    return "{$browser} on {$os}";
}


// ═════════════════════════════════════════════════════════
//  EXISTING HELPERS (unchanged)
// ═════════════════════════════════════════════════════════

function clearOtpSession(): void {
    foreach (['otp_hash','otp_expiry','otp_user_id','otp_role','otp_email','otp_redirect','otp_remember_me','otp_trust_device'] as $k) {
        unset($_SESSION[$k]);
    }
}

function resolveStudentId(int $userId): array {
    try {
        $conn = new PDO("mysql:host=localhost;dbname=school_system;charset=utf8mb4", "root", "");
        $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

        $stmt = $conn->prepare(
            "SELECT id, lrn, enrollment_type, registration_status FROM students WHERE user_id = ? LIMIT 1"
        );
        $stmt->execute([$userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$row) {
            return ['success'=>false,'student_id'=>0,'lrn'=>null,'enrollment_status'=>'','registration_status'=>''];
        }
        return [
            'success'             => true,
            'student_id'          => (int)$row['id'],
            'lrn'                 => $row['lrn'] ?: null,
            'enrollment_status'   => $row['enrollment_type'],
            'registration_status' => $row['registration_status'],
        ];
    } catch (PDOException $e) {
        error_log('[loginverify] resolveStudentId failed: ' . $e->getMessage());
        return ['success'=>false,'student_id'=>0,'lrn'=>null,'enrollment_status'=>'','registration_status'=>''];
    }
}

function resolveTeacherId(int $loginUserId): int {
    try {
        $conn = new PDO("mysql:host=localhost;dbname=school_registrar;charset=utf8mb4", "root", "");
        $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $stmt = $conn->prepare("SELECT id FROM teachers WHERE logindb_user_id = ? LIMIT 1");
        $stmt->execute([$loginUserId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        return $row ? (int)$row['id'] : $loginUserId;
    } catch (PDOException $e) {
        return $loginUserId;
    }
}
?>