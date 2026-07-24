<?php
/**
 * GET /api/payment_tracker.php
 *
 * Returns the student's most recent ACTIVE payment submission
 * (status: uploaded | under_review | rejected).
 * If all submissions are finalized (verified / reflected / rejected-old),
 * returns has_active: false.
 *
 * Response (has_active = true):
 * {
 *   success: true,
 *   has_active: true,
 *   submission: {
 *     id, reference_number, status,
 *     submitted_at_formatted,
 *     review_started_at_formatted,
 *     confirmed_at_formatted,
 *     reflected_to_enrollment_at_formatted
 *   }
 * }
 *
 * Response (has_active = false):
 * { success: true, has_active: false }
 */

require_once __DIR__ . '/config.php';
sendJsonHeaders();

$auth = requireStudentAuth();
$studentId = $auth['student_id'];

try {
    $db = getDB();

    // The tracker shows the MOST RECENT submission that is still "in flight"
    // OR recently completed (verified / reflected) so the student can see
    // the outcome and dismiss it themselves rather than it vanishing instantly.
    // Once the student clicks "Got it, Dismiss", the JS stores a localStorage key
    // and stops showing that submission — the backend never needs to hide it early.
    $stmt = $db->prepare("
        SELECT
            ps.id,
            ps.reference_number,
            ps.status,
            ps.payment_type,
            ps.amount,
            ps.confirmed_amount,
            ps.rejection_reason,
            ps.submitted_at,
            ps.review_started_at,
            ps.confirmed_at,
            ps.reflected_to_enrollment_at
        FROM payment_submissions ps
        WHERE ps.student_id = :student_id
          AND ps.status IN ('uploaded', 'under_review', 'rejected', 'verified', 'reflected_to_enrollment')
        ORDER BY ps.submitted_at DESC
        LIMIT 1
    ");
    $stmt->execute([':student_id' => $studentId]);
    $sub = $stmt->fetch();

    if (!$sub) {
        jsonSuccess(['has_active' => false]);
    }

    jsonSuccess([
        'has_active'  => true,
        'submission'  => [
            'id'                                    => (int) $sub['id'],
            'reference_number'                      => $sub['reference_number'],
            'status'                                => $sub['status'],
            'payment_type'                          => $sub['payment_type'],
            'payment_type_label'                    => $sub['payment_type'] === 'full' ? 'Full Payment' : 'Partial Payment',
            'amount_formatted'                      => formatCurrency($sub['confirmed_amount'] ?? $sub['amount'] ?? null),
            'rejection_reason'                      => $sub['rejection_reason'],
            'submitted_at_formatted'                => formatDatetime($sub['submitted_at']),
            'review_started_at_formatted'           => formatDatetime($sub['review_started_at']),
            'confirmed_at_formatted'                => formatDatetime($sub['confirmed_at']),
            'reflected_to_enrollment_at_formatted'  => formatDatetime($sub['reflected_to_enrollment_at']),
        ],
    ]);

} catch (Throwable $e) {
    error_log('[payment_tracker.php] ' . $e->getMessage());
    jsonError('Failed to load tracker data.', 500);
}