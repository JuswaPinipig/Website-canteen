<?php
// ============================================================
//  studentgradesdata.php
//  Fetches all grade data for the logged-in student.
//  Database: school_system
//  Included by studentgrades.php
//
//  APPROVAL CHAIN (current DB):
//    encoded → submitted → approved_by_principal → approved_by_head
//
//  The final status that makes grades visible to students is
//  'approved_by_principal' OR 'approved_by_head' — both mean
//  the grade has cleared the principal step and is released.
//  The old code only checked 'approved_by_head', which no longer
//  exists in live data — grades top out at 'approved_by_principal'
//  after the coordinator approves.
//
//  SESSION / AUTH (current DB):
//    Students log in via users.id → $_SESSION['user_id'] with role='student'.
//    students.user_id is the FK that links a login account to a student row.
//    The old code looked for $_SESSION['student_id'] which is never set
//    by the login system — so student_id was always 0 and grades never showed.
// ============================================================
if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

// ─── DB CONNECTION ───────────────────────────────────────────────────────────
$db = new mysqli('localhost', 'root', '', 'school_system');
if ($db->connect_error) {
    die('Database error: ' . $db->connect_error);
}

// ─── DEBUG MODE — set to false before going live ─────────────────────────────
$debug = false;

// ─── RESOLVE STUDENT ID ──────────────────────────────────────────────────────
// The login system stores users.id in $_SESSION['user_id'] with role='student'.
// We resolve students.id by joining through students.user_id.
$student_id = 0;

if (!empty($_SESSION['user_id']) && (($_SESSION['role'] ?? '') === 'student')) {
    // Normal login path: look up students.id via the users.id FK
    $uid  = (int)$_SESSION['user_id'];
    $uStmt = $db->prepare("SELECT id FROM students WHERE user_id = ? LIMIT 1");
    $uStmt->bind_param('i', $uid);
    $uStmt->execute();
    $uRow = $uStmt->get_result()->fetch_assoc();
    $uStmt->close();
    if ($uRow) {
        $student_id = (int)$uRow['id'];
    }
} elseif (!empty($_SESSION['student_id'])) {
    // Legacy / direct session path (kept for backward compatibility)
    $student_id = (int)$_SESSION['student_id'];
} elseif (!empty($_GET['student_id']) && $debug) {
    $student_id = (int)$_GET['student_id'];
}

// ─── DEBUG PANEL ─────────────────────────────────────────────────────────────
if ($debug) {
    echo '<div style="font-family:monospace;font-size:0.85rem;background:#fffbe6;border:2px solid #f0c040;padding:1rem 1.5rem;margin:1rem;border-radius:8px;position:relative;z-index:9999;">';
    echo '<strong style="font-size:1rem;">DEBUG — studentgradesdata.php</strong><br><br>';

    echo 'SESSION user_id: ';
    echo !empty($_SESSION['user_id'])
        ? '<span style="color:green">' . $_SESSION['user_id'] . '</span>'
        : '<span style="color:red">not set</span>';
    echo '<br>';

    echo 'SESSION role: ';
    echo !empty($_SESSION['role'])
        ? '<span style="color:green">' . $_SESSION['role'] . '</span>'
        : '<span style="color:red">not set</span>';
    echo '<br>';

    echo 'SESSION student_id (legacy): ';
    echo !empty($_SESSION['student_id'])
        ? '<span style="color:green">' . $_SESSION['student_id'] . '</span>'
        : '<span style="color:red">not set</span>';
    echo '<br>';

    echo 'Resolved student_id: <span style="color:blue;font-weight:bold;">' . $student_id . '</span><br><br>';

    $all = $db->query("SELECT id, lrn, first_name, last_name, grade_level_id, registration_status FROM students ORDER BY id LIMIT 50");
    if ($all) {
        echo '<strong>Students in school_system.students (first 50):</strong><br>';
        echo '<table border="1" cellpadding="5" style="border-collapse:collapse;margin-top:6px;">';
        echo '<tr style="background:#eee"><th>id</th><th>lrn</th><th>first_name</th><th>last_name</th><th>grade_level_id</th><th>status</th></tr>';
        while ($row = $all->fetch_assoc()) {
            $hl = ((int)$row['id'] === $student_id) ? 'background:#d4f5d4;font-weight:bold;' : '';
            echo "<tr style=\"{$hl}\"><td>{$row['id']}</td><td>{$row['lrn']}</td><td>{$row['first_name']}</td><td>{$row['last_name']}</td><td>{$row['grade_level_id']}</td><td>{$row['registration_status']}</td></tr>";
        }
        echo '</table><br>';
    }

    $allGrades = $db->query("SELECT id, student_id, subject_id, status FROM student_grades ORDER BY id LIMIT 50");
    if ($allGrades) {
        echo '<br><strong>Grades in school_system.student_grades (first 50):</strong><br>';
        echo '<table border="1" cellpadding="5" style="border-collapse:collapse;margin-top:6px;">';
        echo '<tr style="background:#eee"><th>id</th><th>student_id</th><th>subject_id</th><th>status</th></tr>';
        while ($gr = $allGrades->fetch_assoc()) {
            $hl = ((int)$gr['student_id'] === $student_id) ? 'background:#d4f5d4;font-weight:bold;' : '';
            echo "<tr style=\"{$hl}\"><td>{$gr['id']}</td><td>{$gr['student_id']}</td><td>{$gr['subject_id']}</td><td>{$gr['status']}</td></tr>";
        }
        echo '</table><br>';
        echo 'Visible statuses to student: <code>approved_by_principal</code>, <code>approved_by_head</code><br>';
    }

    echo '</div>';
}

// ─── GUARD: NO STUDENT ID ────────────────────────────────────────────────────
if (!$student_id) {
    die('<p style="font-family:sans-serif;padding:2rem;color:#c00;">
        <strong>Access denied.</strong><br><br>
        Please <a href="../login.php">log in</a> to view your grades.
    </p>');
}

// ─── FETCH STUDENT INFO ──────────────────────────────────────────────────────
$stmt = $db->prepare(
    "SELECT s.id, s.lrn, s.first_name, s.last_name, s.grade_level_id,
            gl.level AS grade_level
     FROM   students s
     LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
     WHERE  s.id = ?"
);
$stmt->bind_param('i', $student_id);
$stmt->execute();
$student = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$student) {
    die('<p style="font-family:sans-serif;padding:2rem;color:#c00;">
        <strong>Student record not found.</strong><br>
        Please contact the school registrar.
    </p>');
}

// ─── FETCH STUDENT'S SECTION (ssy_id) ───────────────────────────────────────
// Get the student's current section assignment from student_profiles
// so we can look up ALL subjects scheduled for that section.
$ssyId = 0;
$spStmt = $db->prepare(
    "SELECT sp.section_sy_id
     FROM   student_profiles sp
     JOIN   school_years sy ON sy.id = sp.school_year_id
     WHERE  sp.student_id = ?
       AND  sy.is_active  = 1
     LIMIT  1"
);
$spStmt->bind_param('i', $student_id);
$spStmt->execute();
$spRow = $spStmt->get_result()->fetch_assoc();
$spStmt->close();
if ($spRow) {
    $ssyId = (int)$spRow['section_sy_id'];
}

// ─── FETCH ALL SUBJECTS FOR THE SECTION + LEFT JOIN GRADES ───────────────────
// Shows ALL subjects scheduled for the student's section.
// Grade columns will be NULL for subjects not yet released — these show
// as dashes in the UI. Only released statuses are joined so unreleased
// grades are treated as if they don't exist yet.
$rawGrades = [];

if ($ssyId) {
    $stmt = $db->prepare(
        "SELECT
             sub.id   AS subject_id,
             sub.name AS subject_name,
             cs.ssy_id,
             cs.teacher_id,
             sg.grade_q1,
             sg.grade_q2,
             sg.grade_q3,
             sg.status
         FROM (
             SELECT DISTINCT subject_id, ssy_id, teacher_id
             FROM   class_schedules
             WHERE  ssy_id = ?
         ) cs
         JOIN subjects sub ON sub.id = cs.subject_id
         LEFT JOIN student_grades sg
               ON  sg.student_id = ?
               AND sg.subject_id = cs.subject_id
               AND sg.ssy_id     = cs.ssy_id
               AND sg.status IN ('approved_by_principal','approved_by_head','published_by_registrar')
         ORDER BY sub.name"
    );
    $stmt->bind_param('ii', $ssyId, $student_id);
    $stmt->execute();
    $rawGrades = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();
}

// ─── BUILD GRADES ARRAY ──────────────────────────────────────────────────────
$grades = [];

foreach ($rawGrades as $row) {
    // Look up teacher name
    $teacher_name = '—';
    if ($row['teacher_id']) {
        $ts = $db->prepare(
            "SELECT first_name, last_name FROM teachers WHERE id = ? LIMIT 1"
        );
        $ts->bind_param('i', $row['teacher_id']);
        $ts->execute();
        $teacher = $ts->get_result()->fetch_assoc();
        $ts->close();
        if ($teacher) {
            $teacher_name = trim($teacher['first_name'] . ' ' . $teacher['last_name']);
        }
    }

    // Only expose grades that are actually released — NULL otherwise
    $released = in_array($row['status'] ?? '', ['approved_by_principal','approved_by_head','published_by_registrar']);
    $q1 = ($released && $row['grade_q1'] !== null) ? (float)$row['grade_q1'] : null;
    $q2 = ($released && $row['grade_q2'] !== null) ? (float)$row['grade_q2'] : null;
    $q3 = ($released && $row['grade_q3'] !== null) ? (float)$row['grade_q3'] : null;

    $filled = array_filter([$q1, $q2, $q3], fn($v) => $v !== null);
    $avg    = count($filled) > 0 ? round(array_sum($filled) / count($filled), 2) : null;

    $grades[] = [
        'subject'      => $row['subject_name'],
        'teacher_name' => $teacher_name,
        'q1'           => $q1,
        'q2'           => $q2,
        'q3'           => $q3,
        'average'      => $avg,
        'passed'       => $avg !== null && $avg >= 75,
    ];
}

// ─── GWA & HONOR ─────────────────────────────────────────────────────────────
$allAvgs = array_filter(array_column($grades, 'average'), fn($v) => $v !== null);
$gwa     = count($allAvgs) > 0 ? round(array_sum($allAvgs) / count($allAvgs), 2) : null;

$honor = '';
if ($gwa !== null) {
    if      ($gwa >= 98) $honor = 'With Highest Honors';
    elseif  ($gwa >= 95) $honor = 'With High Honors';
    elseif  ($gwa >= 90) $honor = 'With Honors';
}

// ─── GRADE LEVEL LABEL ───────────────────────────────────────────────────────
$gl = (int)($student['grade_level'] ?? $student['grade_level_id']);
$gradeLabel = $gl <= 6
    ? "Grade $gl — Elementary"
    : ($gl <= 10
        ? "Grade $gl — Junior High School"
        : "Grade $gl — Senior High School");

// ─── CLOSE CONNECTION ────────────────────────────────────────────────────────
$db->close();