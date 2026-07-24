<?php
/**
 * GET /api/dashboard.php
 *
 * Returns the logged-in student's profile + current enrollment status.
 *
 * Response:
 * {
 *   success: true,
 *   student_name: "Juan Dela Cruz",
 *   lrn: "100000000001",
 *   grade_level: "Grade 8",
 *   section: "Sampaguita",
 *   academic_year: "2026-2027",
 *   status: "enrolled" | "pending" | "pending_payment" | "payment_review"
 * }
 */

require_once __DIR__ . '/config.php';
sendJsonHeaders();

$auth = requireStudentAuth();
$studentId = $auth['student_id'];

try {
    $db = getDB();

    // ── 1. Get student basic info ──────────────────────────────
    $stmt = $db->prepare("
        SELECT
            s.id,
            s.lrn,
            CONCAT(s.first_name, ' ', COALESCE(s.middle_name, ''), ' ', s.last_name) AS full_name,
            s.first_name,
            s.last_name,
            s.registration_status,
            gl.display_name AS grade_level_display,
            s.grade_level_id
        FROM students s
        LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
        WHERE s.id = :student_id
        LIMIT 1
    ");
    $stmt->execute([':student_id' => $studentId]);
    $student = $stmt->fetch();

    if (!$student) {
        jsonError('Student record not found.', 404);
    }

    // ── 2. Get active school year enrollment ───────────────────
    $stmt = $db->prepare("
        SELECT
            e.id        AS enrollment_id,
            e.status    AS enrollment_status,
            e.grade_level_id,
            gl.display_name AS grade_level,
            sy.label    AS academic_year,
            sec.name    AS section_name
        FROM enrollments e
        JOIN school_years sy ON sy.id = e.school_year_id AND sy.is_active = 1
        LEFT JOIN grade_levels gl ON gl.id = e.grade_level_id
        LEFT JOIN section_school_years ssy ON ssy.id = e.section_sy_id
        LEFT JOIN sections sec ON sec.id = ssy.section_id
        WHERE e.student_id = :student_id
        ORDER BY e.created_at DESC
        LIMIT 1
    ");
    $stmt->execute([':student_id' => $studentId]);
    $enrollment = $stmt->fetch();

    // ── 3. Check if there's a pending payment submission ──────
    $stmt = $db->prepare("
        SELECT status
        FROM payment_submissions
        WHERE student_id = :student_id
          AND status NOT IN ('verified','reflected_to_enrollment','rejected')
        ORDER BY submitted_at DESC
        LIMIT 1
    ");
    $stmt->execute([':student_id' => $studentId]);
    $pendingPayment = $stmt->fetch();

    // ── 4. Determine displayed status ─────────────────────────
    $displayStatus = 'pending'; // fallback: fresh/unnapproved registration
    if ($enrollment) {
        $es = $enrollment['enrollment_status'];
        if ($es === 'enrolled') {
            $displayStatus = 'enrolled';
        } elseif ($pendingPayment) {
            $ps = $pendingPayment['status'];
            $displayStatus = in_array($ps, ['uploaded','under_review']) ? 'payment_review' : 'pending_payment';
        } else {
            $displayStatus = 'pending_payment';
        }
    } elseif ($student['registration_status'] === 'enrolled') {
        $displayStatus = 'enrolled';
    } elseif ($student['registration_status'] === 'registered') {
        // Registrar has approved registration but no enrollment record yet
        $displayStatus = 'registered';
    }
    // Any other registration_status (e.g. 'pending') stays as 'pending'

    // ── 5. Fallback academic year (active one) ─────────────────
    if (!$enrollment) {
        $stmt = $db->prepare("SELECT label FROM school_years WHERE is_active = 1 LIMIT 1");
        $stmt->execute();
        $activeYear = $stmt->fetchColumn();
    }

    jsonSuccess([
        'student_name'  => trim($student['full_name']),
        'lrn'           => $student['lrn'] ?? '—',
        'grade_level'   => $enrollment['grade_level']   ?? $student['grade_level_display'] ?? '—',
        'section'       => $enrollment['section_name']  ?? '—',
        'academic_year' => $enrollment['academic_year'] ?? ($activeYear ?? '—'),
        'status'        => $displayStatus,
    ]);

} catch (Throwable $e) {
    error_log('[dashboard.php] ' . $e->getMessage());
    jsonError('Server error. Please try again later.', 500);
}