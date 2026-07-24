<?php
/**
 * SJC Portal — example_protected_page.php
 * ─────────────────────────────────────────────────────────
 * This shows how ANY protected page in your portal should start.
 * Copy this pattern to your student dashboard, admin panel, etc.
 *
 * The ONLY thing you need to add is the require_once line below.
 * auth.php handles everything: session check, remember-me, redirect.
 */

// ① This MUST be the very first line — before any HTML or echo.
require_once __DIR__ . '/auth.php';

// ② After auth.php runs, you are guaranteed to have a valid user.
//    $authUser is set by auth.php with: id, role, email.

// ③ Optional: restrict by role. Remove this block if all roles are allowed.
if ($authUser['role'] !== 'student') {
    header('Location: /Login/Maininterface.html');
    exit;
}

// ④ From here, write your normal page HTML as usual.
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Student Dashboard — SJC Portal</title>
</head>
<body>

<h1>Welcome to your Dashboard</h1>
<p>You are logged in as: <strong><?= htmlspecialchars($authUser['email']) ?></strong></p>
<p>Your role: <strong><?= htmlspecialchars($authUser['role']) ?></strong></p>

<!--
    LOGOUT BUTTON EXAMPLE
    Point this to a logout.php file (shown below in comments).
-->
<a href="/Login/logout.php">Log Out</a>

<!--
═══════════════════════════════════════════════════════════
 LOGOUT.PHP — create this file at C:\xampp\htdocs\Login\logout.php
 Copy the code below into it.
═══════════════════════════════════════════════════════════

<?php
session_start();
require_once __DIR__ . '/logindb.php'; // $conn

// 1. Clear session_token in DB so auth.php rejects any lingering sessions
if (!empty($_SESSION['user_id'])) {
    try {
        $conn->prepare("UPDATE users SET session_token = NULL WHERE id = ?")
             ->execute([$_SESSION['user_id']]);

        // 2. Also delete remember-me tokens for this user
        $conn->prepare("DELETE FROM remember_me_tokens WHERE user_id = ?")
             ->execute([$_SESSION['user_id']]);
    } catch (PDOException $e) {
        error_log('[logout] ' . $e->getMessage());
    }
}

// 3. Destroy the PHP session
$_SESSION = [];
$p = session_get_cookie_params();
setcookie(session_name(), '', time() - 3600,
    $p['path'], $p['domain'], $p['secure'], $p['httponly']);
session_destroy();

// 4. Clear the remember-me cookie from the browser
setcookie('remember_token', '', [
    'expires'  => time() - 3600,
    'path'     => '/',
    'httponly' => true,
    'samesite' => 'Lax',
]);

// 5. Redirect to login
header('Location: /Login/Maininterface.html');
exit;
?>

-->

</body>
</html>