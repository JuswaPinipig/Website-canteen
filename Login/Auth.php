<?php
/**
 * SJC Portal — auth.php
 * ─────────────────────────────────────────────────────────
 * Location: C:\xampp\htdocs\Login\auth.php
 *
 * PURPOSE:
 *   Every protected page (student dashboard, admin panel, etc.)
 *   must include this file at the very top — before any HTML output.
 *
 * WHAT IT DOES:
 *   1. Starts the session
 *   2. If the user already has a valid session → let them through
 *   3. If no session but a "Remember Me" cookie exists → auto-login
 *   4. If neither → redirect to the login page
 *   5. On every request, it also verifies that the session_token
 *      in $_SESSION matches the one stored in the database.
 *      If they don't match (e.g. user logged in elsewhere), it
 *      destroys this session and redirects to login.
 *
 * HOW TO USE ON A PROTECTED PAGE:
 *
 *   <?php
 *   require_once '/path/to/auth.php';     // ← must be first line
 *   // After this line, these variables are guaranteed to exist:
 *   // $authUser['id'], $authUser['role'], $authUser['email']
 *   ?>
 *   <html>... your protected page ...</html>
 */

// ── Step 0: Start session ─────────────────────────────────
// session_start() must be called before any use of $_SESSION.
// We only call it if a session isn't already active.
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

require_once __DIR__ . '/logindb.php'; // gives us $conn (PDO)

// Where to send the user if they are not authenticated
// Adjust this path if your login page is in a different folder.
define('LOGIN_URL', '/Login/Maininterface.html');

// ── Step 1: Check for an active PHP session ───────────────
if (!empty($_SESSION['logged_in']) && !empty($_SESSION['session_token'])) {

    // The user has a session. Now verify the token is still
    // valid in the database (catches "logged in elsewhere").
    $valid = validateSessionToken(
        (int)$_SESSION['user_id'],
        $_SESSION['session_token'],
        $conn
    );

    if ($valid) {
        // ✅ Session is valid. Set $authUser and let them through.
        $authUser = [
            'id'    => (int)$_SESSION['user_id'],
            'role'  => $_SESSION['user_role'] ?? '',
            'email' => $_SESSION['user_email'] ?? '',
        ];
        // Nothing else to do — the rest of the protected page loads.
        return;
    }

    // ❌ Token mismatch — someone logged in from another device.
    // Destroy this session silently and fall through to the cookie check.
    destroyCurrentSession();
}

// ── Step 2: No valid session — check "Remember Me" cookie ─
// The cookie holds a raw token. We hash it and look it up in the DB.
if (!empty($_COOKIE['remember_token'])) {

    $result = validateRememberToken($_COOKIE['remember_token'], $conn);

    if ($result) {
        // ✅ Valid remember-me token found. Restore the full session.
        restoreSessionFromRememberToken($result, $conn);

        $authUser = [
            'id'    => (int)$_SESSION['user_id'],
            'role'  => $_SESSION['user_role'] ?? '',
            'email' => $_SESSION['user_email'] ?? '',
        ];
        return; // Let them through
    }

    // ❌ Cookie exists but token is expired or invalid.
    // Clear the bad cookie so it doesn't keep firing.
    clearRememberCookie();
}

// ── Step 3: No valid session, no valid cookie → redirect ──
// Save the page they were trying to reach so we can send them
// back after login (optional — remove if you don't need this).
$_SESSION['intended_url'] = $_SERVER['REQUEST_URI'];

header('Location: ' . LOGIN_URL);
exit;


// ═════════════════════════════════════════════════════════
//  HELPER FUNCTIONS
// ═════════════════════════════════════════════════════════

/**
 * Check whether the session_token in $_SESSION still matches
 * what is stored in the database for this user.
 *
 * Why? If the user logs in from another device, loginverify.php
 * writes a NEW session_token to the DB. This old session's token
 * no longer matches → we reject it here → auto-logout.
 *
 * @param int    $userId
 * @param string $sessionToken
 * @param PDO    $conn
 * @return bool  true = still valid, false = invalidated
 */
function validateSessionToken(int $userId, string $sessionToken, PDO $conn): bool
{
    try {
        $stmt = $conn->prepare(
            "SELECT session_token FROM users
             WHERE id = ? AND is_active = 1
             LIMIT 1"
        );
        $stmt->execute([$userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$row) {
            return false; // User deactivated or deleted
        }

        // hash_equals() is timing-safe (prevents timing attacks)
        return hash_equals($row['session_token'] ?? '', $sessionToken);

    } catch (PDOException $e) {
        error_log('[auth] validateSessionToken: ' . $e->getMessage());
        return false;
    }
}

/**
 * Look up a remember-me cookie token in the database.
 * Returns the matching user row if found and not expired,
 * or null if invalid/expired.
 *
 * @param string $rawToken  The raw token value from the cookie
 * @param PDO    $conn
 * @return array|null       Full user row, or null
 */
function validateRememberToken(string $rawToken, PDO $conn): ?array
{
    // We only store the SHA-256 hash in the DB, never the raw token.
    $tokenHash = hash('sha256', $rawToken);

    try {
        $stmt = $conn->prepare(
            "SELECT u.id, u.email, u.role, u.personal_email,
                    u.session_token, r.redirect_url, rmt.token_hash
             FROM   remember_me_tokens rmt
             JOIN   users u ON u.id = rmt.user_id AND u.is_active = 1
             LEFT   JOIN role_redirects r ON r.role = u.role
             WHERE  rmt.token_hash = ?
               AND  rmt.expires_at > NOW()
             LIMIT  1"
        );
        $stmt->execute([$tokenHash]);
        return $stmt->fetch(PDO::FETCH_ASSOC) ?: null;

    } catch (PDOException $e) {
        error_log('[auth] validateRememberToken: ' . $e->getMessage());
        return null;
    }
}

/**
 * After a valid remember-me token is found, rebuild the PHP session
 * exactly as loginverify.php would, and issue a fresh session_token.
 *
 * This means: even on auto-login, a new session_token is written to
 * the DB, and a fresh cookie is set. The old token is deleted.
 *
 * @param array $userRow  Row returned by validateRememberToken()
 * @param PDO   $conn
 */
function restoreSessionFromRememberToken(array $userRow, PDO $conn): void
{
    // Generate a new session token (this also logs out the old session
    // on any other device that had a PHP session open)
    $newSessionToken = bin2hex(random_bytes(32));

    try {
        $conn->prepare(
            "UPDATE users
             SET    session_token = ?, session_token_created_at = NOW()
             WHERE  id = ?"
        )->execute([$newSessionToken, $userRow['id']]);
    } catch (PDOException $e) {
        error_log('[auth] restoreSession update: ' . $e->getMessage());
    }

    // Rebuild session — mirrors what loginverify.php sets
    $_SESSION['user_id']       = (int)$userRow['id'];
    $_SESSION['user_email']    = $userRow['email'];
    $_SESSION['user_role']     = strtolower(trim($userRow['role']));
    $_SESSION['role']          = strtolower(trim($userRow['role']));
    $_SESSION['logged_in']     = true;
    $_SESSION['session_token'] = $newSessionToken;

    // Rotate the remember-me token too (delete old, set new cookie)
    // This is called "token rotation" — good security practice.
    $oldHash = $userRow['token_hash'];
    $newRaw  = bin2hex(random_bytes(32));
    $newHash = hash('sha256', $newRaw);
    $expiry  = time() + (30 * 24 * 3600); // 30 days

    try {
        // Replace old token with new one
        $conn->prepare(
            "UPDATE remember_me_tokens
             SET    token_hash = ?, expires_at = ?
             WHERE  token_hash = ?"
        )->execute([$newHash, date('Y-m-d H:i:s', $expiry), $oldHash]);
    } catch (PDOException $e) {
        error_log('[auth] token rotation: ' . $e->getMessage());
    }

    // Set the new cookie
    setRememberCookie($newRaw, $expiry);
}

/**
 * Set the "remember_token" cookie securely.
 *
 * Flags used:
 *  · HttpOnly   — JS cannot read it (prevents XSS theft)
 *  · Secure     — only sent over HTTPS (set to false for localhost dev)
 *  · SameSite   — "Lax" prevents CSRF in most cases
 *
 * @param string $rawToken
 * @param int    $expiry    Unix timestamp
 */
function setRememberCookie(string $rawToken, int $expiry): void
{
    // Change 'secure' to true once your site is on HTTPS!
    $isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');

    setcookie('remember_token', $rawToken, [
        'expires'  => $expiry,
        'path'     => '/',
        'domain'   => '',          // empty = current domain only
        'secure'   => $isHttps,    // true in production
        'httponly' => true,        // not accessible via JS
        'samesite' => 'Lax',       // CSRF protection
    ]);
}

/**
 * Delete the remember_token cookie from the browser.
 */
function clearRememberCookie(): void
{
    setcookie('remember_token', '', [
        'expires'  => time() - 3600,
        'path'     => '/',
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
}

/**
 * Destroy the current PHP session cleanly.
 * Does NOT redirect — caller is responsible for that.
 */
function destroyCurrentSession(): void
{
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(session_name(), '', time() - 3600,
            $p['path'], $p['domain'], $p['secure'], $p['httponly']
        );
    }
    session_destroy();
}
?>