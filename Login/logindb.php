<?php
date_default_timezone_set('Asia/Manila');

$dbHost   = getenv('MYSQL_HOST')    ?: 'localhost';
$dbName   = getenv('MYSQL_LOGINDB') ?: 'school_system';
$dbUser   = getenv('MYSQL_USER')    ?: 'root';
$dbPass   = getenv('MYSQL_PASS')    ?: '';

try {
    $conn = new PDO(
        "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
        $dbUser,
        $dbPass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]
    );
    $conn->exec("SET time_zone = '+08:00'"); // Align MySQL to Philippine Standard Time
} catch (PDOException $e) {
    // Log internally — never expose DB details to the browser
    error_log('[logindb] Connection failed: ' . $e->getMessage());
    header('Content-Type: application/json');
    echo json_encode(['success' => false, 'message' => 'Database connection failed. Please try again later.']);
    exit;
}
?>