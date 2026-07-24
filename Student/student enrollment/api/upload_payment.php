<?php
/**
 * POST /api/upload_payment.php
 *
 * Accepts multipart form data:
 *   proof_image       file     (required) JPG/PNG/WEBP ≤ 5 MB
 *   reference_number  string   (required)
 *   payment_type      string   full | partial  (default: partial)
 *   amount            float    (optional)
 *
 * Response:
 *   { success: true, submission_id: 42, message: "..." }
 *   { success: false, message: "..." }
 */

require_once __DIR__ . '/config.php';
sendJsonHeaders();

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonError('Method not allowed.', 405);
}

$auth = requireStudentAuth();
$studentId = $auth['student_id'];

// ── Validate text inputs ───────────────────────────────────────
$refNumber      = trim($_POST['reference_number'] ?? '');
$paymentType    = in_array($_POST['payment_type'] ?? '', ['full','partial'])
                  ? $_POST['payment_type']
                  : 'partial';
$paymentChannel = in_array($_POST['payment_channel'] ?? '', ['gcash','bank_transfer'])
                  ? $_POST['payment_channel']
                  : 'gcash';
$bankName       = $paymentChannel === 'bank_transfer'
                  ? trim(substr($_POST['bank_name'] ?? '', 0, 100))
                  : null;
$amount         = isset($_POST['amount']) && is_numeric($_POST['amount'])
                  ? round((float)$_POST['amount'], 2)
                  : null;

if ($refNumber === '') {
    jsonError('Reference number is required.');
}

// GCash: must be exactly 13 digits. Bank: 6–30 chars alphanumeric.
if ($paymentChannel === 'gcash') {
    if (!preg_match('/^\d{13}$/', $refNumber)) {
        jsonError('GCash reference number must be exactly 13 digits (numbers only).');
    }
} else {
    if (!preg_match('/^\d{16,20}$/', $refNumber)) {
        jsonError('Bank reference number must be 16–20 digits (numbers only).');
    }
    if (!$bankName) {
        jsonError('Bank name is required for bank transfer submissions.');
    }
}

// ── Validate uploaded file ─────────────────────────────────────
if (empty($_FILES['proof_image']) || $_FILES['proof_image']['error'] !== UPLOAD_ERR_OK) {
    $uploadErrors = [
        UPLOAD_ERR_INI_SIZE   => 'File exceeds server upload limit.',
        UPLOAD_ERR_FORM_SIZE  => 'File exceeds form size limit.',
        UPLOAD_ERR_PARTIAL    => 'File was only partially uploaded.',
        UPLOAD_ERR_NO_FILE    => 'No receipt image was uploaded.',
        UPLOAD_ERR_NO_TMP_DIR => 'Server temporary folder is missing.',
        UPLOAD_ERR_CANT_WRITE => 'Failed to write file to disk.',
        UPLOAD_ERR_EXTENSION  => 'File upload blocked by extension.',
    ];
    $errCode = $_FILES['proof_image']['error'] ?? UPLOAD_ERR_NO_FILE;
    jsonError($uploadErrors[$errCode] ?? 'File upload failed.');
}

$file      = $_FILES['proof_image'];
$tmpPath   = $file['tmp_name'];
$origName  = basename($file['name']);
$fileSize  = $file['size'];

// Size check: 5 MB
if ($fileSize > 5 * 1024 * 1024) {
    jsonError('Receipt image must be smaller than 5 MB.');
}

// MIME type check (use finfo — don't trust $_FILES['type'])
$finfo    = new finfo(FILEINFO_MIME_TYPE);
$mimeType = $finfo->file($tmpPath);
$allowedMimes = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
if (!in_array($mimeType, $allowedMimes, true)) {
    jsonError('Only JPG, PNG, and WEBP images are accepted.');
}
$extMap = ['image/jpeg'=>'jpg','image/jpg'=>'jpg','image/png'=>'png','image/webp'=>'webp'];
$ext = $extMap[$mimeType];

// ── Get active school year ─────────────────────────────────────
try {
    $db = getDB();

    $stmt = $db->prepare("SELECT id FROM school_years WHERE is_active = 1 LIMIT 1");
    $stmt->execute();
    $schoolYearId = $stmt->fetchColumn();
    if (!$schoolYearId) {
        jsonError('No active school year found. Please contact the registrar.', 500);
    }

    // ── Duplicate reference number check (same student, same year) ──
    $stmt = $db->prepare("
        SELECT id FROM payment_submissions
        WHERE student_id = :sid
          AND school_year_id = :syid
          AND reference_number = :ref
        LIMIT 1
    ");
    $stmt->execute([':sid'=>$studentId, ':syid'=>$schoolYearId, ':ref'=>$refNumber]);
    if ($stmt->fetchColumn()) {
        jsonError('You already submitted a payment with this reference number for the current school year.');
    }

    // ── Save file to disk ──────────────────────────────────────
    $uploadDir = UPLOAD_DIR . "student_{$studentId}/";
    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0755, true);
    }

    $uniqueName = 'pay_' . uniqid('', true) . '.' . $ext;
    $destPath   = $uploadDir . $uniqueName;

    if (!move_uploaded_file($tmpPath, $destPath)) {
        error_log("[upload_payment] move_uploaded_file failed for student {$studentId}");
        jsonError('Failed to save receipt image. Please try again.', 500);
    }

    // Relative path for DB storage
    $relativePath = "uploads/payment_proofs/student_{$studentId}/{$uniqueName}";

    // ── Insert submission record ───────────────────────────────
    $stmt = $db->prepare("
        INSERT INTO payment_submissions
            (student_id, school_year_id, reference_number, payment_type, payment_channel, bank_name, amount,
             proof_image_path, proof_image_name, proof_image_mime, proof_image_size_kb,
             status, submitted_at, ip_address)
        VALUES
            (:sid, :syid, :ref, :type, :channel, :bank, :amount,
             :path, :name, :mime, :size,
             'uploaded', NOW(), :ip)
    ");
    $stmt->execute([
        ':sid'     => $studentId,
        ':syid'    => $schoolYearId,
        ':ref'     => $refNumber,
        ':type'    => $paymentType,
        ':channel' => $paymentChannel,
        ':bank'    => $bankName,
        ':amount'  => $amount,
        ':path'    => $relativePath,
        ':name'    => $origName,
        ':mime'    => $mimeType,
        ':size'    => (int) round($fileSize / 1024),
        ':ip'      => $_SERVER['REMOTE_ADDR'] ?? null,
    ]);

    $submissionId = (int) $db->lastInsertId();

    jsonSuccess([
        'submission_id' => $submissionId,
        'message' => 'Payment proof submitted successfully. Our cashier will review it within 1–2 business days.',
    ]);

} catch (Throwable $e) {
    // Clean up file if DB insert failed
    if (isset($destPath) && file_exists($destPath)) {
        unlink($destPath);
    }
    error_log('[upload_payment.php] ' . $e->getMessage());
    jsonError('Server error. Please try again later.', 500);
}