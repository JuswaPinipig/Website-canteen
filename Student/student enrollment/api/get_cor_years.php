<?php
/**
 * GET /api/get_cor_years.php
 *
 * Returns all school years in which the student has an 'enrolled' OR 'registered'
 * enrollment, so both enrolled and registered students can access their COR.
 *
 * Response:
 * {
 *   success: true,
 *   years: [
 *     { school_year_id: 3, label: "2026-2027", is_active: true },
 *     { school_year_id: 2, label: "2025-2026", is_active: false }
 *   ]
 * }
 */

require_once __DIR__ . '/config.php';
sendJsonHeaders();

$auth      = requireStudentAuth();
$studentId = $auth['student_id'];

try {
    $db = getDB();

    // Include both enrolled and registered students
    $stmt = $db->prepare("
        SELECT
            sy.id          AS school_year_id,
            sy.label,
            sy.is_active
        FROM enrollments e
        JOIN school_years sy ON sy.id = e.school_year_id
        WHERE e.student_id = :student_id
          AND e.status IN ('enrolled', 'registered')
        GROUP BY sy.id
        ORDER BY sy.id DESC
    ");
    $stmt->execute([':student_id' => $studentId]);
    $rows = $stmt->fetchAll();

    // Fallback: if no enrollment row exists but the student is 'registered' in
    // the students table, return the active school year.
    if (empty($rows)) {
        $stmt2 = $db->prepare("
            SELECT registration_status FROM students WHERE id = :student_id LIMIT 1
        ");
        $stmt2->execute([':student_id' => $studentId]);
        $regStatus = $stmt2->fetchColumn();

        if (in_array($regStatus, ['registered', 'enrolled'])) {
            $stmt3 = $db->prepare("
                SELECT id AS school_year_id, label, is_active
                FROM school_years WHERE is_active = 1 LIMIT 1
            ");
            $stmt3->execute();
            $rows = $stmt3->fetchAll();
        }
    }

    $years = array_map(fn($r) => [
        'school_year_id' => (int) $r['school_year_id'],
        'label'          => $r['label'],
        'is_active'      => (bool) $r['is_active'],
    ], $rows);

    jsonSuccess(['years' => $years]);

} catch (Throwable $e) {
    error_log('[get_cor_years.php] ' . $e->getMessage());
    jsonError('Failed to load school years.', 500);
}