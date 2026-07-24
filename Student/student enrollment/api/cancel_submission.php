<?php
/**
 * POST /api/cancel_submission.php
 *
 * Allows a student to cancel/unsend their own payment submission,
 * but ONLY if it is still in 'uploaded' status (not yet under review).
 *
 * Body (JSON): { "submission_id": 42 }
 *
 * Response:
 *   { success: true, message: "..." }
 *   { success: false, message: "..." }
 */

require_once __DIR__ . '/config.php';
sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonError('Method not allowed.', 405);
}

$auth      = requireStudentAuth();
$studentId = $auth['student_id'];

// Accept JSON body
$body         = json_decode(file_get_contents('php://input'), true) ?? [];
$submissionId = isset($body['submission_id']) ? (int) $body['submission_id'] : 0;

if ($submissionId <= 0) {
    jsonError('Invalid submission ID.');
}

try {
    $db = getDB();

    // Fetch the submission — must belong to this student and be 'uploaded' only
    $stmt = $db->prepare("
        SELECT id, status, proof_image_path
        FROM payment_submissions
        WHERE id = :id AND student_id = :student_id
        LIMIT 1
    ");
    $stmt->execute([':id' => $submissionId, ':student_id' => $studentId]);
    $sub = $stmt->fetch();

    if (!$sub) {
        jsonError('Submission not found or access denied.', 404);
    }

    if ($sub['status'] !== 'uploaded') {
        jsonError('This submission can no longer be unsent. It is currently under review or has already been processed.', 400);
    }

    // Delete the DB record
    $stmt = $db->prepare("DELETE FROM payment_submissions WHERE id = :id");
    $stmt->execute([':id' => $submissionId]);

    // Delete the uploaded proof image from disk (best-effort)
    if (!empty($sub['proof_image_path'])) {
        $absPath = dirname(__DIR__) . '/' . ltrim($sub['proof_image_path'], '/');
        if (file_exists($absPath)) {
            @unlink($absPath);
        }
    }

    jsonSuccess(['message' => 'Your payment submission has been successfully removed.']);

} catch (Throwable $e) {
    error_log('[cancel_submission.php] ' . $e->getMessage());
    jsonError('Server error. Please try again later.', 500);
}
