<?php
/**
 * GET /api/receipt_image.php?id={submission_id}
 *
 * Returns the image URL for a payment submission receipt.
 * Students can only view their own receipts.
 *
 * Response:
 *   { success: true, image_url: "...", reference_number: "..." }
 *   { success: false, message: "..." }
 */

require_once __DIR__ . '/config.php';
sendJsonHeaders();

$auth = requireStudentAuth();
$studentId = $auth['student_id'];

$submissionId = isset($_GET['id']) ? (int) $_GET['id'] : 0;
if ($submissionId <= 0) {
    jsonError('Invalid submission ID.');
}

try {
    $db = getDB();

    $stmt = $db->prepare("
        SELECT proof_image_path, reference_number
        FROM payment_submissions
        WHERE id = :id AND student_id = :student_id
        LIMIT 1
    ");
    $stmt->execute([':id' => $submissionId, ':student_id' => $studentId]);
    $row = $stmt->fetch();

    if (!$row) {
        jsonError('Receipt not found or access denied.', 404);
    }

    // Build a URL the browser can load.
    // Adjust the base URL to match your server setup.
    $scheme   = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http';
    $host     = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $basePath = rtrim(dirname(dirname($_SERVER['SCRIPT_NAME'])), '/');

    // proof_image_path is stored as "uploads/payment_proofs/student_N/pay_xxx.jpg"
    // We serve it relative to the project root
    $imageUrl = "{$scheme}://{$host}{$basePath}/{$row['proof_image_path']}";

    jsonSuccess([
        'image_url'        => $imageUrl,
        'reference_number' => $row['reference_number'],
    ]);

} catch (Throwable $e) {
    error_log('[receipt_image.php] ' . $e->getMessage());
    jsonError('Failed to retrieve receipt image.', 500);
}
