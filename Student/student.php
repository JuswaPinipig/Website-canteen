<?php
// ═══════════════════════════════════════════════
//  SJC STUDENT PORTAL — student.php
//  Backend API: returns logged-in student data as JSON
//  Called by student.js on page load via fetch()
// ═══════════════════════════════════════════════

session_start();
header('Content-Type: application/json');

// ── Auth guard ───────────────────────────────────
if (
    !isset($_SESSION['user_id']) ||
    !isset($_SESSION['role'])    ||
    $_SESSION['role'] !== 'student'
) {
    http_response_code(401);
    echo json_encode(['error' => 'unauthorized']);
    exit;
}

// ── DB connection ────────────────────────────────
$host   = 'localhost';
$dbname = 'school_system';
$dbuser = 'root';
$dbpass = '';

try {
    $pdo = new PDO(
        "mysql:host=$host;dbname=$dbname;charset=utf8mb4",
        $dbuser,
        $dbpass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => 'db_connection_failed']);
    exit;
}

// ── Fetch student record ─────────────────────────
$userId = (int) $_SESSION['user_id'];

$stmt = $pdo->prepare("
    SELECT
        s.id            AS student_id,
        s.first_name,
        s.last_name,
        s.lrn,
        s.registration_status,
        s.enrollment_type,
        gl.display_name AS grade_label
    FROM   students s
    JOIN   grade_levels gl ON gl.id = s.grade_level_id
    WHERE  s.user_id = ?
    LIMIT  1
");
$stmt->execute([$userId]);
$student = $stmt->fetch();

if (!$student) {
    http_response_code(404);
    echo json_encode(['error' => 'student_not_found']);
    exit;
}

// ── Fetch active school year ─────────────────────
$syStmt  = $pdo->query("SELECT id, label FROM school_years WHERE is_active = 1 LIMIT 1");
$syRow   = $syStmt->fetch();
$activeYear   = $syRow['label']  ?? '2025-2026';
$activeYearId = $syRow['id']     ?? null;

// ── Check: is student fully enrolled? ────────────
// registration_status values: pending | registered | verified | enrolled | archived
// Only 'enrolled' means the registrar has confirmed them — all others are restricted.
$isEnrolled = ($student['registration_status'] === 'enrolled');

// ── Check: outstanding payment balance? ──────────
// A pending payment_due_notice for the current school year = unpaid balance.
$hasBalance = false;
if ($activeYearId && $student['student_id']) {
    $payStmt = $pdo->prepare("
        SELECT COUNT(*) FROM payment_due_notices
        WHERE  student_id    = ?
          AND  school_year_id = ?
          AND  status        = 'pending'
        LIMIT 1
    ");
    $payStmt->execute([$student['student_id'], $activeYearId]);
    $hasBalance = (bool) $payStmt->fetchColumn();
}

// ── Fetch active payment deadline ────────────────
// Reads the 'payments' row from system_deadlines for the active school year.
// Only surfaces the end date — we never handle real transactions, only proof upload.
$paymentDeadline = null;
if ($activeYearId) {
    $dlStmt = $pdo->prepare("
        SELECT end_datetime, end_date
        FROM   system_deadlines
        WHERE  school_year_id = ?
          AND  type           = 'payments'
        LIMIT  1
    ");
    $dlStmt->execute([$activeYearId]);
    $dlRow = $dlStmt->fetch();
    if ($dlRow) {
        // Prefer the datetime column; fall back to date-only
        $raw = $dlRow['end_datetime'] ?: $dlRow['end_date'];
        if ($raw && $raw !== '0000-00-00' && $raw !== '0000-00-00 00:00:00') {
            $paymentDeadline = $raw;
        }
    }
}

// ── Derive access flags ───────────────────────────
// registration_status flow:
//   pending    → submitted docs, awaiting registrar review  ← POPUP shown
//   registered → docs approved by registrar; student must now pay ← NO popup
//   verified   → registrar approved; student must now pay enrollment fee
//   enrolled   → fully enrolled (paid), full portal access
//   archived   → inactive
//
// locked_registration : true  → status is ONLY 'pending' (docs under review, not yet approved)
// locked_verified     : true  → status is registered or verified (approved, must pay)
// locked_balance      : true  → enrolled but has an unpaid due notice
// locked_hold         : true  → status is 'rejected' (on hold, awaiting student resubmission)
$regStatus = $student['registration_status'];

$lockedRegistration = ($regStatus === 'pending');
$lockedVerified     = in_array($regStatus, ['registered', 'verified']);
$lockedBalance      = $isEnrolled && $hasBalance;
$lockedHold         = ($regStatus === 'rejected');

// ── Return JSON ──────────────────────────────────
echo json_encode([
    'first_name'          => $student['first_name'],
    'last_name'           => $student['last_name'],
    'lrn'                 => $student['lrn'] ?? '',
    'grade_label'         => $student['grade_label'],
    'status'              => $regStatus,
    'enrollment_type'     => $student['enrollment_type'],
    'school_year'         => $activeYear,
    'locked_registration' => $lockedRegistration,
    'locked_verified'     => $lockedVerified,
    'locked_balance'      => $lockedBalance,
    'locked_hold'         => $lockedHold,
    'payment_deadline'    => $paymentDeadline,  // null or "YYYY-MM-DD HH:MM:SS" / "YYYY-MM-DD"
]);