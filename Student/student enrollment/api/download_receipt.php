<?php
/**
 * GET /api/download_receipt.php?id={submission_id}
 *
 * Generates and streams an Official Payment Receipt PDF
 * for the currently logged-in student.
 *
 * Requirements:
 *   - Student must be authenticated (session)
 *   - Submission must belong to this student
 *   - Submission status must be 'verified' or 'reflected_to_enrollment'
 *   - Uses mPDF: composer require mpdf/mpdf
 */

require_once __DIR__ . '/config.php';

// ── Auth ───────────────────────────────────────────────────────
if (session_status() === PHP_SESSION_NONE) session_start();

if (
    empty($_SESSION['user_id']) ||
    empty($_SESSION['role'])    ||
    $_SESSION['role'] !== 'student' ||
    empty($_SESSION['student_id'])
) {
    http_response_code(401);
    exit('Unauthorized. Please log in.');
}

$studentId    = (int) $_SESSION['student_id'];
$submissionId = isset($_GET['id']) ? (int) $_GET['id'] : 0;

if ($submissionId <= 0) {
    http_response_code(400);
    exit('Invalid request.');
}

try {
    $db = getDB();

    $stmt = $db->prepare("
        SELECT
            ps.id                                                           AS submission_id,
            ps.reference_number,
            ps.payment_type,
            ps.payment_channel,
            ps.bank_name,
            COALESCE(ps.confirmed_amount, ps.amount)                        AS amount,
            ps.status,
            DATE_FORMAT(ps.confirmed_at,  '%M %d, %Y')                     AS date_paid,
            DATE_FORMAT(ps.confirmed_at,  '%h:%i %p')                      AS time_paid,
            DATE_FORMAT(ps.submitted_at,  '%M %d, %Y')                     AS date_submitted,
            s.lrn,
            TRIM(CONCAT(
                s.first_name, ' ',
                COALESCE(CONCAT(s.middle_name, ' '), ''),
                s.last_name
            ))                                                              AS student_name,
            gl.display_name                                                 AS grade_level,
            sec.name                                                        AS section_name,
            sy.label                                                        AS school_year,
            COALESCE(c.full_name, '—')                                      AS cashier_name,
            e.id                                                            AS enrollment_id
        FROM payment_submissions ps
        JOIN students s      ON s.id  = ps.student_id
        JOIN school_years sy ON sy.id = ps.school_year_id
        LEFT JOIN grade_levels gl    ON gl.id  = s.grade_level_id
        LEFT JOIN cashiers c         ON c.id   = ps.cashier_id
        LEFT JOIN enrollments e
               ON e.student_id    = ps.student_id
              AND e.school_year_id = ps.school_year_id
              AND e.status         = 'enrolled'
        LEFT JOIN section_school_years ssy ON ssy.id = e.section_sy_id
        LEFT JOIN sections sec             ON sec.id  = ssy.section_id
        WHERE ps.id         = :id
          AND ps.student_id = :student_id
          AND ps.status IN ('verified', 'reflected_to_enrollment')
        LIMIT 1
    ");
    $stmt->execute([':id' => $submissionId, ':student_id' => $studentId]);
    $rec = $stmt->fetch();

    if (!$rec) {
        http_response_code(404);
        exit('Receipt not found or payment not yet verified.');
    }

    // ── Derived display values ─────────────────────────────────
    $amountFormatted = $rec['amount'] !== null
        ? '₱ ' . number_format((float) $rec['amount'], 2)
        : '—';

    $payTypeLabel = $rec['payment_type'] === 'full' ? 'Full Payment' : 'Partial Payment';

    $channelLabel = match($rec['payment_channel'] ?? '') {
        'gcash'         => 'GCash',
        'bank_transfer' => 'Bank Transfer' . ($rec['bank_name'] ? ' — ' . $rec['bank_name'] : ''),
        default         => 'Online Payment',
    };

    $receiptNo = 'OR-' . date('Y') . '-' . str_pad($rec['submission_id'], 5, '0', STR_PAD_LEFT);

} catch (Throwable $e) {
    error_log('[download_receipt.php] ' . $e->getMessage());
    http_response_code(500);
    exit('Server error. Please try again later.');
}

// ── Logo base64 ────────────────────────────────────────────────
$logoPaths = [
    dirname(__DIR__) . '/student enrollment media/school no bg.png',
    dirname(__DIR__) . '/media/school no bg.png',
    dirname(__DIR__) . '/Cashier/Cashier Management/Cashier Media/school no bg.png',
    __DIR__ . '/../student enrollment media/school no bg.png',
];
$logoSrc = '';
foreach ($logoPaths as $lp) {
    if (file_exists($lp)) {
        $logoSrc = 'data:image/png;base64,' . base64_encode(file_get_contents($lp));
        break;
    }
}
$logoImgTag = $logoSrc
    ? '<img src="' . $logoSrc . '" alt="Logo" style="width:52px;height:52px;object-fit:contain;">'
    : '';

$now          = new DateTime('now', new DateTimeZone('Asia/Manila'));
$generatedAt  = $now->format('F d, Y h:i A');

// ── Safe HTML variables (all escaped here, used directly below) ──
$v_receiptNo     = htmlspecialchars($receiptNo);
$v_datePaid      = htmlspecialchars($rec['date_paid']      ?? '—');
$v_timePaid      = htmlspecialchars($rec['time_paid']      ?? '—');
$v_schoolYear    = htmlspecialchars($rec['school_year']    ?? '—');
$v_studentName   = htmlspecialchars(strtoupper($rec['student_name'] ?? '—'));
$v_lrn           = htmlspecialchars($rec['lrn']            ?? '—');
$v_gradeLevel    = htmlspecialchars($rec['grade_level']    ?? '—');
$v_sectionName   = htmlspecialchars($rec['section_name']   ?? '—');
$v_payType       = htmlspecialchars($payTypeLabel);
$v_dateSubmitted = htmlspecialchars($rec['date_submitted'] ?? '—');
$v_referenceNo   = htmlspecialchars($rec['reference_number'] ?? '—');
$v_channel       = htmlspecialchars($channelLabel);
$v_cashierName   = htmlspecialchars($rec['cashier_name']   ?? '—');
$v_amount        = htmlspecialchars($amountFormatted);
$v_generatedAt   = htmlspecialchars($generatedAt);

// ── HTML ───────────────────────────────────────────────────────
$html = '<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family: Arial, sans-serif; font-size: 9pt; color: #1a1a1a; }

    /* HEADER */
    .header { text-align:center; padding:14px 0 10px; border-bottom:3px solid #6B0D23; }
    .header img { display:block; margin:0 auto 6px; width:58px; height:58px; object-fit:contain; }
    .school-name { font-size:12pt; font-weight:bold; color:#6B0D23; text-transform:uppercase; letter-spacing:0.4px; }
    .school-sub  { font-size:8pt; color:#555; margin-top:2px; }
    .school-addr { font-size:7.5pt; color:#777; margin-top:1px; }
    .doc-title-wrap { margin-top:8px; }
    .doc-title {
        display:inline-block;
        font-size:10.5pt; font-weight:bold; color:#6B0D23;
        letter-spacing:2px; text-transform:uppercase;
        border-top:1.5px solid #6B0D23;
        border-bottom:1.5px solid #6B0D23;
        padding:3px 20px;
    }

    /* META BAR */
    .meta-bar {
        display:table; width:100%;
        padding:6px 0; margin-top:8px;
        border-bottom:1px solid #e0c0c5;
    }
    .meta-left  { display:table-cell; vertical-align:middle; }
    .meta-right { display:table-cell; vertical-align:middle; text-align:right; }
    .or-num     { font-size:8.5pt; font-weight:bold; color:#6B0D23; }
    .or-date    { font-size:7.5pt; color:#666; margin-top:2px; }
    .badge {
        display:inline-block; font-size:7.5pt; font-weight:bold;
        padding:4px 12px; border-radius:3px; letter-spacing:0.3px;
        background:#EAF5ED; color:#1A6B35; border:1px solid #1A6B35;
    }

    /* SECTION HEADER */
    .sec-hdr {
        background:#6B0D23; color:#fff;
        font-size:7.5pt; font-weight:bold;
        padding:4px 9px; text-transform:uppercase;
        letter-spacing:0.8px; margin-top:8px;
    }

    /* INFO TABLE */
    .info-tbl { width:100%; border-collapse:collapse; }
    .info-tbl td {
        border:0.75px solid #ddd;
        padding:4px 8px; font-size:8pt;
        height:18px; vertical-align:middle;
    }
    .lbl { background:#F5EEF0; color:#6B0D23; font-weight:bold; white-space:nowrap; width:16%; }
    .val { background:#fff; color:#1a1a1a; width:34%; }

    /* AMOUNT BOX */
    .amount-box {
        background:#6B0D23; border-radius:4px;
        padding:14px 18px; margin:12px 0;
        display:table; width:100%;
    }
    .amount-label {
        display:table-cell; vertical-align:middle;
        color:#e8c0c8; font-size:9pt; font-weight:bold;
        text-transform:uppercase; letter-spacing:0.5px;
    }
    .amount-value {
        display:table-cell; vertical-align:middle;
        text-align:right; font-size:20pt;
        font-weight:bold; color:#fff;
    }

    /* NOTE */
    .note {
        margin-top:10px; padding:6px 9px;
        border-left:3px solid #6B0D23;
        background:#fdf8f9; font-size:7.5pt; color:#444; line-height:1.5;
    }

    /* SIGNATURES */
    .sig-wrap { display:table; width:100%; margin-top:24px; }
    .sig-cell { display:table-cell; width:50%; text-align:center; padding:0 24px; vertical-align:bottom; }
    .sig-space { height:28px; }
    .sig-line  { border-top:1px solid #6B0D23; }
    .sig-name  { font-size:8pt; font-weight:bold; color:#1a1a1a; margin-top:3px; }
    .sig-role  { font-size:7.5pt; color:#666; margin-top:1px; }

    /* FOOTER */
    .footer {
        border-top:1px solid #e0c0c5; margin-top:14px;
        padding-top:5px; text-align:center;
        font-size:7pt; color:#aaa;
    }
</style>
</head>
<body>

<!-- HEADER -->
<div class="header">
    ' . $logoImgTag . '
    <div class="school-name">St. Joseph College of Novaliches, Inc.</div>
    <div class="school-sub">Accounting / Cashier\'s Office</div>
    <div class="school-addr">Novaliches, Quezon City, Metro Manila</div>
    <div class="doc-title-wrap">
        <span class="doc-title">Official Payment Receipt</span>
    </div>
</div>

<!-- META BAR -->
<div class="meta-bar">
    <div class="meta-left">
        <div class="or-num">Receipt No.: ' . $v_receiptNo . '</div>
        <div class="or-date">Date &amp; Time: ' . $v_datePaid . ' &nbsp;&bull;&nbsp; ' . $v_timePaid . ' &nbsp;&bull;&nbsp; SY ' . $v_schoolYear . '</div>
    </div>
    <div class="meta-right">
        <span class="badge">&#10003;&nbsp; PAYMENT VERIFIED</span>
    </div>
</div>

<!-- STUDENT INFORMATION -->
<div class="sec-hdr">Student Information</div>
<table class="info-tbl">
    <tr>
        <td class="lbl">Student Name</td>
        <td class="val" colspan="3"><strong>' . $v_studentName . '</strong></td>
    </tr>
    <tr>
        <td class="lbl">LRN</td>
        <td class="val">' . $v_lrn . '</td>
        <td class="lbl">Grade Level</td>
        <td class="val">' . $v_gradeLevel . '</td>
    </tr>
    <tr>
        <td class="lbl">Section</td>
        <td class="val">' . $v_sectionName . '</td>
        <td class="lbl">School Year</td>
        <td class="val">' . $v_schoolYear . '</td>
    </tr>
</table>

<!-- PAYMENT DETAILS -->
<div class="sec-hdr">Payment Details</div>
<table class="info-tbl">
    <tr>
        <td class="lbl">Reference No.</td>
        <td class="val"><strong>' . $v_referenceNo . '</strong></td>
        <td class="lbl">Payment Channel</td>
        <td class="val">' . $v_channel . '</td>
    </tr>
    <tr>
        <td class="lbl">Payment Type</td>
        <td class="val">' . $v_payType . '</td>
        <td class="lbl">Date Submitted</td>
        <td class="val">' . $v_dateSubmitted . '</td>
    </tr>
    <tr>
        <td class="lbl">Cashier</td>
        <td class="val">' . $v_cashierName . '</td>
        <td class="lbl">Date Confirmed</td>
        <td class="val">' . $v_datePaid . ' &nbsp; ' . $v_timePaid . '</td>
    </tr>
</table>

<!-- AMOUNT BOX -->
<div class="amount-box">
    <div class="amount-label">Amount Paid</div>
    <div class="amount-value">' . $v_amount . '</div>
</div>

<!-- NOTE -->
<div class="note">
    This receipt confirms that the payment listed above has been verified by the cashier for School Year <strong>' . $v_schoolYear . '</strong>.
    Please keep this document as proof of your payment. Any alterations or erasures render this receipt void.
    For concerns, contact the Accounting Office.
</div>

<!-- SIGNATURES -->
<div class="sig-wrap">
    <div class="sig-cell">
        <div class="sig-space"></div>
        <div class="sig-line"></div>
        <div class="sig-name">Student / Parent / Guardian</div>
        <div class="sig-role">Signature over Printed Name &nbsp;&bull;&nbsp; Date: ___________</div>
    </div>
    <div class="sig-cell">
        <div class="sig-space"></div>
        <div class="sig-line"></div>
        <div class="sig-name">' . $v_cashierName . '</div>
        <div class="sig-role">Authorized Cashier &nbsp;&bull;&nbsp; ' . $v_datePaid . '</div>
    </div>
</div>

<!-- FOOTER -->
<div class="footer">
    ' . $v_receiptNo . ' &nbsp;&bull;&nbsp; Generated: ' . $v_generatedAt . ' &nbsp;&bull;&nbsp; This is a system-generated document.
</div>

</body>
</html>';

// ── Generate PDF ───────────────────────────────────────────────
require_once dirname(__DIR__) . '/vendor/autoload.php';

$mpdf = new \Mpdf\Mpdf([
    'mode'          => 'utf-8',
    'format'        => 'A4',
    'margin_top'    => 10,
    'margin_bottom' => 10,
    'margin_left'   => 14,
    'margin_right'  => 14,
]);

$mpdf->SetTitle('Official Receipt — ' . $rec['reference_number']);
$mpdf->SetAuthor("Cashier's Office");
$mpdf->WriteHTML($html);

$safeRef  = preg_replace('/[^A-Za-z0-9_-]/', '_', $rec['reference_number']);
$filename = 'Receipt_' . $safeRef . '.pdf';
$mpdf->Output($filename, 'D');