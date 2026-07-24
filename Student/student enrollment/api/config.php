<?php
/**
 * config.php — Shared database connection + session auth helper
 * Place this file in:  /your-project/student enrollment/api/config.php
 *
 * All API endpoints require() this file.
 */

// ── Database credentials ────────────────────────────────────────
define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'school_system');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_PORT', 3306);

// ── Upload directory (absolute path on disk) ────────────────────
// Must be writable by the web server process.
// Adjust to your actual server path.
define('UPLOAD_DIR', dirname(__DIR__) . '/uploads/payment_proofs/');
define('UPLOAD_URL_BASE', '../uploads/payment_proofs/'); // relative URL for serving images

// ── PDO connection factory ──────────────────────────────────────
function getDB(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
            DB_HOST, DB_PORT, DB_NAME);
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    }
    return $pdo;
}

// ── CORS / JSON headers ─────────────────────────────────────────
function sendJsonHeaders(): void {
    header('Content-Type: application/json; charset=utf-8');
    // Allow credentials for session cookie
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    header("Access-Control-Allow-Origin: {$origin}");
    header('Access-Control-Allow-Credentials: true');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');
    if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(204); exit; }
}

// ── Session auth ────────────────────────────────────────────────
/**
 * Starts session and returns the authenticated student row,
 * or sends 401 JSON and exits.
 *
 * Expects session to have:
 *   $_SESSION['user_id']   — users.id
 *   $_SESSION['role']      — must equal 'student'
 *   $_SESSION['student_id'] — students.id (set at login)
 */
function requireStudentAuth(): array {
    if (session_status() === PHP_SESSION_NONE) {
        session_start();
    }

    if (
        empty($_SESSION['user_id']) ||
        empty($_SESSION['role'])    ||
        $_SESSION['role'] !== 'student' ||
        empty($_SESSION['student_id'])
    ) {
        http_response_code(401);
        echo json_encode(['success' => false, 'message' => 'Unauthorized. Please log in.']);
        exit;
    }

    return [
        'user_id'    => (int) $_SESSION['user_id'],
        'student_id' => (int) $_SESSION['student_id'],
    ];
}

// ── Helpers ─────────────────────────────────────────────────────
function jsonSuccess(array $data = []): void {
    echo json_encode(array_merge(['success' => true], $data));
    exit;
}

function jsonError(string $message, int $code = 400): void {
    http_response_code($code);
    echo json_encode(['success' => false, 'message' => $message]);
    exit;
}

function formatCurrency(float|null $amount): string {
    if ($amount === null) return '—';
    return '₱' . number_format($amount, 2);
}

function formatDatetime(string|null $dt): string {
    if (!$dt) return '';
    try {
        return (new DateTime($dt, new DateTimeZone('Asia/Manila')))->format('M d, Y h:i A');
    } catch (Exception) {
        return $dt;
    }
}
