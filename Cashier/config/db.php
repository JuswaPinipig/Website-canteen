<?php
/**
 * config/db.php
 *
 * Provides a single shared PDO instance ($pdo) for the entire application.
 *
 * Usage (in any PHP file that needs DB access):
 *   require_once __DIR__ . '/../config/db.php';
 *   // $pdo is now available
 *
 * This file must be required AFTER session_start() if session-based
 * error display is needed, but it has no session dependency itself.
 */

/* ============================================================
   LOAD ENVIRONMENT CONFIGURATION
   Pulls constants defined in config.php (host, dbname, user, pass).
============================================================ */
require_once __DIR__ . '/../../Cashier/Config/config.php';

/* ============================================================
   PDO OPTIONS
============================================================ */
$dsn = sprintf(
    'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
    DB_HOST,
    DB_PORT,
    DB_NAME
);

$options = [
    // Throw PDOException on every error — never silently fail.
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,

    // Return rows as associative arrays by default.
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,

    // Disable emulated prepares — use real server-side prepared statements.
    // This is important for security (prevents second-order injection via
    // emulation quirks) and for correct data-type handling.
    PDO::ATTR_EMULATE_PREPARES   => false,

    // Persistent connections — reuse the same connection across requests
    // on the same PHP-FPM worker. Set to false if you see stale state bugs.
    PDO::ATTR_PERSISTENT         => false,

    // Ensure the connection uses the Philippine timezone so NOW(), CURDATE(),
    // and CONVERT_TZ() all agree with Asia/Manila wall-clock time.
    PDO::MYSQL_ATTR_INIT_COMMAND => "SET time_zone = '+08:00'",
];

/* ============================================================
   CREATE CONNECTION
============================================================ */
try {
    $pdo = new PDO($dsn, DB_USER, DB_PASS, $options);
} catch (PDOException $e) {
    /*
     * Never expose raw PDO error messages to the browser in production —
     * they can leak host names, usernames, or schema details.
     *
     * The full message is written to the PHP error log for diagnostics.
     * The browser (or API caller) only ever sees a generic message.
     */
    error_log('[db.php] Connection failed: ' . $e->getMessage());

    if (defined('APP_ENV') && APP_ENV === 'development') {
        // In development it is safe (and useful) to show the real error.
        http_response_code(500);
        die('<pre>Database connection failed: ' . htmlspecialchars($e->getMessage()) . '</pre>');
    }

    // Production — generic error response.
    http_response_code(500);
    die(json_encode([
        'success' => false,
        'error'   => 'A database error occurred. Please try again later.',
    ]));
}