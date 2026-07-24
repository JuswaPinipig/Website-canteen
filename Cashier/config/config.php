<?php
/**
 * config/config.php
 *
 * Central environment configuration.
 * Required by db.php to establish the PDO connection.
 *
 * ⚠️  EDIT the values below to match your local setup.
 *     For XAMPP the defaults below are usually correct —
 *     just set DB_PASS to '' (empty) unless you added a root password.
 */

// ── Database ────────────────────────────────────────────────
define('DB_HOST', '127.0.0.1');   // or 'localhost'
define('DB_PORT', 3306);
define('DB_NAME', 'school_system'); // ← your database name in phpMyAdmin
define('DB_USER', 'root');          // ← your MySQL username
define('DB_PASS', '');              // ← your MySQL password (blank for XAMPP default)

// ── Environment ─────────────────────────────────────────────
// Set to 'production' on live server to hide raw error messages.
define('APP_ENV', 'development');
