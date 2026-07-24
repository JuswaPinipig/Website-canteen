<?php
/**
 * SJC Portal — do_reset_password.php
 * ─────────────────────────────────────────────────────────
 * AJAX endpoint called by reset_password.php after the user
 * fills in their new password.
 *
 * Security model:
 *   • Token was already validated by reset_password.php on page load
 *     and stored in $_SESSION['reset_token_hash'] + ['reset_user_id']
 *   • This endpoint re-validates the session keys and verifies the
 *     token is still live in the DB before writing the new password
 *   • Token is deleted immediately after use (single-use)
 */

session_start();
header('Content-Type: application/json');

require_once 'logindb.php'; // $conn (PDO)

function respond(array $payload): void {
    echo json_encode($payload);
    exit;
}

// ── Guard: POST only ──────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(['success' => false, 'message' => 'Invalid request method.']);
}

// ── Guard: session must have reset context ─────────────────
if (
    empty($_SESSION['reset_token_hash']) ||
    empty($_SESSION['reset_user_id'])
) {
    respond(['success' => false, 'message' => 'Session expired. Please request a new reset link.']);
}

$tokenHash = $_SESSION['reset_token_hash'];
$userId    = (int)$_SESSION['reset_user_id'];

// ── 1. Re-validate token in DB (still live, not expired) ──
try {
    $stmt = $conn->prepare(
        "SELECT user_id FROM password_reset_tokens
         WHERE  token_hash = ? AND expires_at > NOW()
         LIMIT  1"
    );
    $stmt->execute([$tokenHash]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
} catch (PDOException $e) {
    error_log('[do_reset_password] Token re-check failed: ' . $e->getMessage());
    respond(['success' => false, 'message' => 'Database error. Please try again.']);
}

if (!$row || (int)$row['user_id'] !== $userId) {
    respond(['success' => false, 'message' => 'Reset link is invalid or has expired. Please request a new one.']);
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
    error_log('[do_reset_password] Password update failed: ' . $e->getMessage());
    respond(['success' => false, 'message' => 'Database error. Please try again.']);
}

// ── 4. Delete the used token (single-use) ─────────────────
try {
    $del = $conn->prepare("DELETE FROM password_reset_tokens WHERE token_hash = ?");
    $del->execute([$tokenHash]);
} catch (PDOException $e) {
    error_log('[do_reset_password] Token delete failed: ' . $e->getMessage());
    // Non-fatal — token will expire naturally
}

// ── 5. Clear reset session keys ───────────────────────────
unset($_SESSION['reset_token_hash'], $_SESSION['reset_user_id']);

respond(['success' => true, 'message' => 'Password reset successfully.']);
?>
