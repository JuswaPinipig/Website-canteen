<?php
/**
 * GET /api/payment_history.php
 *
 * Returns the student's full payment submission history
 * and their past enrollment records.
 *
 * Response:
 * {
 *   success: true,
 *   payments: [ ...PaymentRow ],
 *   enrollment_history: [ ...EnrollmentRow ]
 * }
 *
 * PaymentRow fields (matches what studentenroll.js renderPaymentRows() expects):
 *   id, reference_number, submitted_date, payment_type, payment_type_label,
 *   amount_formatted, cashier_name, status, rejection_reason,
 *   confirmed_at, receipt_pdf_path
 *
 * EnrollmentRow fields (matches renderEnrollmentTimeline()):
 *   academic_year, grade_level, status, reference_number (submission ref),
 *   date, payment_type, cashier_name, amount_formatted,
 *   submission_id, rejection_reason, confirmed_at, receipt_pdf_path
 */

require_once __DIR__ . '/config.php';
sendJsonHeaders();

$auth = requireStudentAuth();
$studentId = $auth['student_id'];

try {
    $db = getDB();

    // ── 1. Payment submissions history ────────────────────────
    $stmt = $db->prepare("
        SELECT
            ps.id,
            ps.reference_number,
            DATE_FORMAT(ps.submitted_at, '%b %d, %Y')          AS submitted_date,
            ps.payment_type,
            CASE ps.payment_type
                WHEN 'full'    THEN 'Full Payment'
                WHEN 'partial' THEN 'Partial Payment'
                ELSE ps.payment_type
            END                                                 AS payment_type_label,
            ps.amount,
            ps.confirmed_amount,
            ps.status,
            ps.rejection_reason,
            ps.receipt_pdf_path,
            DATE_FORMAT(ps.confirmed_at, '%b %d, %Y %h:%i %p') AS confirmed_at,
            COALESCE(c.full_name, '—')                          AS cashier_name
        FROM payment_submissions ps
        LEFT JOIN cashiers c ON c.id = ps.cashier_id
        WHERE ps.student_id = :student_id
        ORDER BY ps.submitted_at DESC
    ");
    $stmt->execute([':student_id' => $studentId]);
    $rawPayments = $stmt->fetchAll();

    $payments = array_map(function (array $row): array {
        // Use confirmed_amount if cashier filled it, otherwise student-entered amount
        $displayAmount = $row['confirmed_amount'] ?? $row['amount'] ?? null;
        return [
            'id'               => (int) $row['id'],
            'reference_number' => $row['reference_number'],
            'submitted_date'   => $row['submitted_date'],
            'payment_type'     => $row['payment_type'],
            'payment_type_label' => $row['payment_type_label'],
            'amount_formatted' => formatCurrency($displayAmount !== null ? (float)$displayAmount : null),
            'cashier_name'     => $row['cashier_name'],
            'status'           => $row['status'],
            'rejection_reason' => $row['rejection_reason'],
            'confirmed_at'     => $row['confirmed_at'],
            'receipt_pdf_path' => $row['receipt_pdf_path'],
        ];
    }, $rawPayments);

    // ── 2. Enrollment history (all years) ─────────────────────
    $stmt = $db->prepare("
        SELECT
            e.id            AS enrollment_id,
            sy.label        AS academic_year,
            gl.display_name AS grade_level,
            e.status        AS enrollment_status,
            e.created_at,
            -- attach latest verified payment submission for that enrollment year
            ps.id           AS submission_id,
            ps.reference_number,
            ps.payment_type,
            ps.status       AS payment_status,
            ps.rejection_reason,
            ps.receipt_pdf_path,
            COALESCE(c.full_name, '—')                          AS cashier_name,
            COALESCE(ps.confirmed_amount, ps.amount)            AS amount,
            DATE_FORMAT(ps.confirmed_at, '%b %d, %Y %h:%i %p') AS confirmed_at,
            DATE_FORMAT(e.created_at, '%b %d, %Y')              AS date
        FROM enrollments e
        JOIN school_years sy ON sy.id = e.school_year_id
        JOIN grade_levels gl ON gl.id = e.grade_level_id
        LEFT JOIN payment_submissions ps
               ON ps.student_id = e.student_id
              AND ps.school_year_id = e.school_year_id
              AND ps.status IN ('verified','reflected_to_enrollment')
              AND ps.id = (
                SELECT id FROM payment_submissions p2
                WHERE p2.student_id = e.student_id
                  AND p2.school_year_id = e.school_year_id
                  AND p2.status IN ('verified','reflected_to_enrollment')
                ORDER BY p2.confirmed_at DESC
                LIMIT 1
              )
        LEFT JOIN cashiers c ON c.id = ps.cashier_id
        WHERE e.student_id = :student_id
        ORDER BY e.created_at DESC
    ");
    $stmt->execute([':student_id' => $studentId]);
    $rawHistory = $stmt->fetchAll();

    $history = array_map(function (array $row): array {
        return [
            'academic_year'    => $row['academic_year'],
            'grade_level'      => $row['grade_level'],
            'status'           => $row['enrollment_status'],
            'reference_number' => $row['reference_number'] ?? '—',
            'date'             => $row['date'],
            'payment_type'     => $row['payment_type'] ?? '',
            'cashier_name'     => $row['cashier_name'],
            'amount_formatted' => formatCurrency($row['amount'] !== null ? (float)$row['amount'] : null),
            'submission_id'    => $row['submission_id'] ? (int)$row['submission_id'] : 0,
            'rejection_reason' => $row['rejection_reason'],
            'confirmed_at'     => $row['confirmed_at'],
            'receipt_pdf_path' => $row['receipt_pdf_path'],
        ];
    }, $rawHistory);

    jsonSuccess([
        'payments'           => $payments,
        'enrollment_history' => $history,
    ]);

} catch (Throwable $e) {
    error_log('[payment_history.php] ' . $e->getMessage());
    jsonError('Failed to load payment history.', 500);
}
