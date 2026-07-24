<?php
session_start();

// ---------------------------------------------------------------
// Database — school_system (new unified database)
// ---------------------------------------------------------------
$conn = new mysqli("localhost", "root", "", "school_system");
if ($conn->connect_error) {
    die("Database connection failed: " . $conn->connect_error);
}

// ---------------------------------------------------------------
// Auth — students only
// ---------------------------------------------------------------
if (!isset($_SESSION['user_id']) || $_SESSION['role'] !== 'student') {
    header("Location: ../Login/Maininterface.html");
    exit();
}

$user_id = (int)$_SESSION['user_id'];

// ---------------------------------------------------------------
// STEP 1: Resolve student record from users.id
// ---------------------------------------------------------------
$stmt = $conn->prepare("
    SELECT
        s.id,
        s.first_name,
        s.last_name,
        s.grade_level_id,
        gl.display_name   AS grade_level,
        s.lrn,
        s.registration_status AS status
    FROM   students s
    JOIN   grade_levels gl ON gl.id = s.grade_level_id
    WHERE  s.user_id = ?
      AND  s.is_archived = 0
    LIMIT  1
");
$stmt->bind_param("i", $user_id);
$stmt->execute();
$student = $stmt->get_result()->fetch_assoc();
$stmt->close();

// Fallback — build a minimal record from users table so page never crashes
if (!$student) {
    $stmt = $conn->prepare("SELECT email FROM users WHERE id = ? LIMIT 1");
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $u = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    $local  = explode('@', $u['email'] ?? 'student@school')[0];
    $parts  = explode('.', $local);
    $student = [
        'id'           => 0,
        'first_name'   => ucfirst($parts[0] ?? 'Student'),
        'last_name'    => ucfirst($parts[1] ?? ''),
        'grade_level_id' => null,
        'grade_level'  => '—',
        'status'       => 'pending',
    ];
}

// ---------------------------------------------------------------
// STEP 2: Fetch schedules
//
// Chain (new database):
//   students
//     → student_profiles (section assignment: section_sy_id)
//     → section_school_years (capacity, enrolled_count)
//     → sections (name)
//     → grade_levels (display_name)
//     → class_schedules (days, start_time, end_time, room)
//     → subjects (name)
//     → teachers (first_name, last_name)
//
// The new system stores the student's assigned section in
// student_profiles.section_sy_id — NOT in enrollments.section_sy_id.
// We also verify the enrollment is 'enrolled' in the active school year.
// ---------------------------------------------------------------
$schedules = [];

if (!empty($student['id'])) {

    $stmt = $conn->prepare("
        SELECT
            cs.id                                           AS class_id,
            sub.name                                        AS subject,
            sec.name                                        AS section,
            gl.display_name                                 AS grade,
            cs.days,
            TIME_FORMAT(cs.start_time, '%h:%i %p')         AS time_start,
            TIME_FORMAT(cs.end_time,   '%h:%i %p')         AS time_end,
            CONCAT(
                cs.days, ' ',
                TIME_FORMAT(cs.start_time, '%h:%i %p'),
                ' – ',
                TIME_FORMAT(cs.end_time,   '%h:%i %p')
            )                                               AS schedule,
            cs.room,
            ssy.capacity,
            ssy.enrolled_count,
            t.first_name                                    AS teacher_first,
            t.last_name                                     AS teacher_last,
            sub.name                                        AS teacher_subject
        FROM   students s

        -- The section the student was placed into (by admin/registrar)
        JOIN   student_profiles sp
               ON  sp.student_id    = s.id
               AND sp.section_sy_id IS NOT NULL

        -- The section_school_years row for this assignment
        JOIN   section_school_years ssy
               ON  ssy.id = sp.section_sy_id

        -- Verify the student is enrolled in the active school year
        JOIN   enrollments e
               ON  e.student_id     = s.id
               AND e.school_year_id = ssy.school_year_id
               AND e.status         = 'enrolled'

        -- Active school year guard
        JOIN   school_years sy
               ON  sy.id        = ssy.school_year_id
               AND sy.is_active = 1

        -- Section and grade
        JOIN   sections     sec ON sec.id  = ssy.section_id
        JOIN   grade_levels gl  ON gl.id   = sec.grade_level_id

        -- Class schedules for this section
        JOIN   class_schedules cs  ON cs.ssy_id = ssy.id

        -- Subject
        JOIN   subjects sub ON sub.id = cs.subject_id

        -- Teacher (optional)
        LEFT JOIN teachers t ON t.id = cs.teacher_id

        WHERE  s.id          = ?
          AND  s.is_archived = 0

        ORDER BY
            FIELD(cs.days,
                'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'),
            cs.start_time ASC
    ");

    $stmt->bind_param("i", $student['id']);
    $stmt->execute();
    $result = $stmt->get_result();

    while ($row = $result->fetch_assoc()) {
        $schedules[] = $row;
    }

    $stmt->close();
}

$conn->close();

// ---------------------------------------------------------------
// Render view — $student and $schedules are always set
// ---------------------------------------------------------------
// Derive section name from first schedule row for display
if (!empty($schedules)) {
    $student['section_name'] = $schedules[0]['section'] ?? '';
} else {
    $student['section_name'] = '';
}

require_once __DIR__ . '/schedule_view.php';