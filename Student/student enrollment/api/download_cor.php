<?php
/**
 * GET /api/download_cor.php?year_id={id}
 *
 * Generates and streams a Certificate of Registration (COR) PDF.
 * Available to BOTH 'enrolled' AND 'registered' students.
 *
 * Uses mPDF: composer require mpdf/mpdf
 * Logo expected at:  /student enrollment/student enrollment media/school no bg.png
 */

require_once __DIR__ . '/config.php';

// ── Auth (no JSON headers — we stream a PDF) ───────────────────
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
$schoolYearId = isset($_GET['year_id']) && ctype_digit((string)$_GET['year_id'])
               ? (int) $_GET['year_id']
               : null;

try {
    $db = getDB();

    // ── 1. Build year condition ─────────────────────────────────
    if ($schoolYearId) {
        $yearCondition = 'sy.id = :year_id';
        $yearParam     = [':student_id' => $studentId, ':year_id' => $schoolYearId];
    } else {
        $yearCondition = 'sy.is_active = 1';
        $yearParam     = [':student_id' => $studentId];
    }

    // ── 2. Student + enrollment info ───────────────────────────
    $stmt = $db->prepare("
        SELECT
            s.id                                                        AS student_id,
            s.lrn,
            TRIM(CONCAT(
                s.last_name, ', ',
                s.first_name,
                COALESCE(CONCAT(' ', s.middle_name), '')
            ))                                                          AS full_name_formal,
            TRIM(CONCAT(
                s.first_name, ' ',
                COALESCE(CONCAT(s.middle_name, ' '), ''),
                s.last_name
            ))                                                          AS full_name,
            CONCAT(s.address, ', ', s.city, ', ', s.province, ' ', s.zip_code) AS full_address,
            s.nationality,
            s.sex,
            e.id                                                        AS enrollment_id,
            e.status                                                    AS enrollment_status,
            e.section_sy_id,
            e.enrollment_type,
            gl.display_name                                             AS grade_level,
            sy.id                                                       AS school_year_id,
            sy.label                                                    AS school_year,
            sec.name                                                    AS section_name,
            COALESCE(CONCAT(t.first_name, ' ', t.last_name), '—')      AS adviser_name,
            DATE_FORMAT(e.updated_at, '%B %d, %Y')                     AS date_enrolled
        FROM students s
        JOIN enrollments e
            ON e.student_id = s.id
        JOIN school_years sy
            ON sy.id = e.school_year_id AND {$yearCondition}
        JOIN grade_levels gl
            ON gl.id = e.grade_level_id
        LEFT JOIN section_school_years ssy
            ON ssy.id = e.section_sy_id
        LEFT JOIN sections sec
            ON sec.id = ssy.section_id
        LEFT JOIN teachers t
            ON t.id = ssy.adviser_id
        WHERE s.id = :student_id
          AND e.status IN ('enrolled', 'registered')
        ORDER BY e.updated_at DESC
        LIMIT 1
    ");
    $stmt->execute($yearParam);
    $student = $stmt->fetch();

    // Fallback: no enrollment row but registered in students table
    if (!$student) {
        $stmt = $db->prepare("
            SELECT
                s.id            AS student_id,
                s.lrn,
                TRIM(CONCAT(s.last_name, ', ', s.first_name,
                    COALESCE(CONCAT(' ', s.middle_name), ''))) AS full_name_formal,
                TRIM(CONCAT(s.first_name, ' ',
                    COALESCE(CONCAT(s.middle_name, ' '), ''),
                    s.last_name)) AS full_name,
                CONCAT(s.address, ', ', s.city, ', ', s.province, ' ', s.zip_code) AS full_address,
                s.nationality,
                s.sex,
                NULL            AS enrollment_id,
                'registered'    AS enrollment_status,
                NULL            AS section_sy_id,
                s.enrollment_type,
                gl.display_name AS grade_level,
                sy.id           AS school_year_id,
                sy.label        AS school_year,
                NULL            AS section_name,
                '—'             AS adviser_name,
                DATE_FORMAT(NOW(), '%B %d, %Y') AS date_enrolled
            FROM students s
            LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
            JOIN school_years sy ON sy.is_active = 1
            WHERE s.id = :student_id
              AND s.registration_status IN ('registered', 'enrolled', 'verified')
            LIMIT 1
        ");
        $stmt->execute([':student_id' => $studentId]);
        $student = $stmt->fetch();
    }

    if (!$student) {
        http_response_code(403);
        exit('COR is only available for registered or enrolled students.');
    }

    // ── 3. Subjects + class schedules ──────────────────────────
    $subjects = [];
    if (!empty($student['section_sy_id'])) {
        $stmt = $db->prepare("
            SELECT
                sub.code                                                AS subject_code,
                sub.name                                                AS subject_name,
                sec.name                                                AS section,
                GROUP_CONCAT(DISTINCT cs.days
                    ORDER BY FIELD(cs.days,
                        'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')
                    SEPARATOR '/')                                      AS days,
                TIME_FORMAT(MIN(cs.start_time), '%h:%i %p')            AS start_time,
                TIME_FORMAT(MIN(cs.end_time),   '%h:%i %p')            AS end_time,
                COALESCE(MAX(cs.room), '—')                            AS room,
                sub.units                                               AS units,
                COALESCE(CONCAT(t.first_name, ' ', t.last_name), '—')  AS teacher
            FROM class_schedules cs
            JOIN subjects sub   ON sub.id = cs.subject_id
            JOIN section_school_years ssy ON ssy.id = cs.ssy_id
            JOIN sections sec   ON sec.id = ssy.section_id
            LEFT JOIN teachers t ON t.id = cs.teacher_id
            WHERE cs.ssy_id = :ssy_id
            GROUP BY sub.id, cs.teacher_id
            ORDER BY MIN(cs.start_time) ASC
        ");
        $stmt->execute([':ssy_id' => $student['section_sy_id']]);
        $subjects = $stmt->fetchAll();
    }

    if (empty($subjects)) {
        $stmt = $db->prepare("
            SELECT
                sub.code    AS subject_code,
                sub.name    AS subject_name,
                :section    AS section,
                '—'         AS days,
                '—'         AS start_time,
                '—'         AS end_time,
                '—'         AS room,
                sub.units   AS units,
                '—'         AS teacher
            FROM subjects sub
            WHERE sub.grade_level_id = :grade_level_id
              AND sub.is_active = 1
              AND sub.is_archived = 0
            ORDER BY sub.name ASC
        ");
        $stmt->execute([
            ':grade_level_id' => $student['grade_level_id'] ?? (
                $db->query("SELECT grade_level_id FROM enrollments WHERE student_id = {$student['student_id']} ORDER BY updated_at DESC LIMIT 1")->fetchColumn()
                ?? 7
            ),
            ':section' => $student['section_name'] ?? '—',
        ]);
        $subjects = $stmt->fetchAll();
    }

    // ── 4. COR reference + totals ──────────────────────────────
    $enrollId   = $student['enrollment_id'] ?? $studentId;
    $corNo      = 'COR-' . date('Y') . '-' . str_pad($enrollId, 6, '0', STR_PAD_LEFT);
    $totalUnits = 0;
    foreach ($subjects as $sub) {
        $totalUnits += (float)($sub['units'] ?? 1);
    }

    // ── 5. Status label ────────────────────────────────────────
    $isEnrolled   = ($student['enrollment_status'] === 'enrolled');
    $statusLabel  = $isEnrolled ? 'OFFICIALLY ENROLLED' : 'OFFICIALLY REGISTERED';
    $statusColor  = $isEnrolled ? '#1A6B35' : '#8A4800';
    $statusBg     = $isEnrolled ? '#EAF5ED'  : '#FEF3E2';
    $statusBorder = $isEnrolled ? '#1A6B35'  : '#B8600A';
    $stampWord    = $isEnrolled ? 'ENROLLED'  : 'REGISTERED';

    // ── 6. Sex label ──────────────────────────────────────────
    $sexLabel = match(strtolower($student['sex'] ?? '')) {
        'male', 'm'   => 'MALE',
        'female', 'f' => 'FEMALE',
        default       => strtoupper($student['sex'] ?? '—'),
    };

} catch (Throwable $e) {
    error_log('[download_cor.php] ' . $e->getMessage());
    http_response_code(500);
    exit('Server error. Please try again later.');
}

// ── 7. Logo as base64 ─────────────────────────────────────────
$logoPaths = [
    dirname(__DIR__) . '/student enrollment media/school no bg.png',
    dirname(__DIR__) . '/media/school no bg.png',
    dirname(__DIR__) . '/Cashier/Cashier Management/Cashier Media/school no bg.png',
    __DIR__ . '/../student enrollment media/school no bg.png',
];
$logoBase64 = '';
foreach ($logoPaths as $path) {
    if (file_exists($path)) {
        $logoBase64 = 'data:image/png;base64,' . base64_encode(file_get_contents($path));
        break;
    }
}
$logoImgTag   = $logoBase64 ? "<img src=\"{$logoBase64}\" alt=\"School Logo\" style=\"width:64px;height:64px;object-fit:contain;\">" : '';
// Watermark is set via mPDF native API below — not via CSS (mPDF ignores position:fixed correctly only via SetWatermarkImage)
$watermarkRawPath = '';
foreach ($logoPaths as $path) {
    if (file_exists($path)) { $watermarkRawPath = $path; break; }
}

// ── 8. Subject rows HTML ──────────────────────────────────────
$subjectRowsHtml = '';
foreach ($subjects as $i => $sub) {
    $rowBg = ($i % 2 === 0) ? '#ffffff' : '#fdf8f8';
    $subjectRowsHtml .= sprintf(
        '<tr style="background:%s;">
            <td class="cell-center cell-code">%s</td>
            <td class="cell-desc">%s</td>
            <td class="cell-center">%s</td>
            <td class="cell-center">%s</td>
            <td class="cell-center">%s &ndash; %s</td>
            <td class="cell-center">%s</td>
            <td class="cell-center cell-units">%s</td>
         </tr>',
        $rowBg,
        htmlspecialchars($sub['subject_code']),
        htmlspecialchars($sub['subject_name']),
        htmlspecialchars($sub['section'] ?? ($student['section_name'] ?? '—')),
        htmlspecialchars($sub['days']),
        htmlspecialchars($sub['start_time']),
        htmlspecialchars($sub['end_time']),
        htmlspecialchars($sub['room']),
        number_format((float)($sub['units'] ?? 1), 1)
    );
}
if (empty($subjects)) {
    $subjectRowsHtml = '<tr><td colspan="7" style="text-align:center;color:#999;padding:12px 5px;font-style:italic;font-size:8pt;">
        No subjects assigned yet. Please contact the Registrar\'s Office.
    </td></tr>';
}

// ── 9. Build HTML ─────────────────────────────────────────────
$now        = new DateTime('now', new DateTimeZone('Asia/Manila'));
$dateIssued = $now->format('F d, Y');
$timeIssued = $now->format('h:i A');

// Safe HTML values
$fullName    = htmlspecialchars(strtoupper($student['full_name_formal']));
$lrn         = htmlspecialchars($student['lrn'] ?? '—');
$gradeLevel  = htmlspecialchars($student['grade_level'] ?? '—');
$schoolYear  = htmlspecialchars($student['school_year'] ?? '—');
$sectionName = htmlspecialchars($student['section_name'] ?? '—');
$adviser     = htmlspecialchars($student['adviser_name'] ?? '—');
$dateEnroll  = htmlspecialchars($student['date_enrolled'] ?? '—');
$fullAddress = htmlspecialchars($student['full_address'] ?? '—');
$nationality = htmlspecialchars(strtoupper($student['nationality'] ?? 'FILIPINO'));
$totalUnitsF = number_format($totalUnits, 1);
$studentId0  = str_pad($student['student_id'], 12, '0', STR_PAD_LEFT);

$html = <<<HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body {
        font-family: Arial, sans-serif;
        font-size: 8.5pt;
        color: #1a1a1a;
        background: #fff;
    }

    /* ── HEADER ── */
    .header {
        text-align: center;
        padding: 14px 0 10px;
        border-bottom: 3px solid #6B0D23;
    }
    .header img {
        display: block;
        margin: 0 auto 6px;
        width: 62px;
        height: 62px;
        object-fit: contain;
    }
    .school-name {
        font-size: 12pt;
        font-weight: bold;
        color: #6B0D23;
        letter-spacing: 0.5px;
        text-transform: uppercase;
    }
    .school-sub {
        font-size: 8pt;
        color: #555;
        margin-top: 2px;
    }
    .school-addr {
        font-size: 7.5pt;
        color: #777;
        margin-top: 1px;
    }
    .doc-title-wrap {
        margin-top: 8px;
    }
    .doc-title {
        display: inline-block;
        font-size: 10.5pt;
        font-weight: bold;
        color: #6B0D23;
        letter-spacing: 2.5px;
        text-transform: uppercase;
        border-top: 1.5px solid #6B0D23;
        border-bottom: 1.5px solid #6B0D23;
        padding: 3px 20px;
    }

    /* ── META BAR ── */
    .meta-bar {
        display: table;
        width: 100%;
        padding: 6px 0;
        margin-top: 8px;
        border-bottom: 1px solid #e0c0c5;
    }
    .meta-left  { display: table-cell; vertical-align: middle; }
    .meta-right { display: table-cell; vertical-align: middle; text-align: right; }
    .cor-num    { font-size: 8.5pt; font-weight: bold; color: #6B0D23; }
    .cor-dates  { font-size: 7.5pt; color: #666; margin-top: 2px; }


    /* ── SECTION HEADER ── */
    .sec-hdr {
        background: #6B0D23;
        color: #fff;
        font-size: 7.5pt;
        font-weight: bold;
        padding: 4px 9px;
        text-transform: uppercase;
        letter-spacing: 0.8px;
        margin-top: 8px;
    }

    /* ── INFO TABLE ── */
    .info-tbl {
        width: 100%;
        border-collapse: collapse;
    }
    .info-tbl td {
        border: 0.75px solid #ddd;
        padding: 4px 8px;
        font-size: 8pt;
        height: 18px;
        vertical-align: middle;
    }
    .lbl {
        background: #F5EEF0;
        color: #6B0D23;
        font-weight: bold;
        white-space: nowrap;
        width: 16%;
    }
    .val {
        background: #fff;
        color: #1a1a1a;
        width: 34%;
    }

    /* ── SUBJECTS TABLE ── */
    .subj-tbl {
        width: 100%;
        border-collapse: collapse;
        margin-top: 0;
    }
    .subj-tbl th {
        background: #F5EEF0;
        color: #6B0D23;
        font-size: 7.5pt;
        font-weight: bold;
        padding: 5px 4px;
        border: 0.75px solid #ddd;
        text-align: center;
        text-transform: uppercase;
        letter-spacing: 0.3px;
    }
    .subj-tbl td {
        border: 0.75px solid #e8e8e8;
        padding: 4px 5px;
        font-size: 8pt;
        vertical-align: middle;
    }
    .cell-center { text-align: center; }
    .cell-desc   { padding-left: 7px; }
    .cell-code   { font-weight: bold; color: #6B0D23; }
    .cell-units  { font-weight: bold; }

    .totals-row td {
        background: #F5EEF0;
        font-weight: bold;
        color: #6B0D23;
        border: 0.75px solid #ddd;
        padding: 4px 5px;
        font-size: 8pt;
    }

    /* ── NOTE ── */
    .note {
        margin-top: 10px;
        padding: 6px 9px;
        border-left: 3px solid #6B0D23;
        background: #fdf8f9;
        font-size: 7.5pt;
        color: #444;
        line-height: 1.5;
    }



    /* ── FOOTER ── */
    .footer {
        border-top: 1px solid #e0c0c5;
        margin-top: 14px;
        padding-top: 5px;
        text-align: center;
        font-size: 7pt;
        color: #aaa;
    }
</style>
</head>
<body>

<!-- HEADER -->
<div class="header">
    {$logoImgTag}
    <div class="school-name">St. Joseph College of Novaliches, Inc.</div>
    <div class="school-sub">Registrar's Office</div>
    <div class="school-addr">Novaliches, Quezon City, Metro Manila</div>
    <div class="doc-title-wrap">
        <span class="doc-title">Certificate of Registration</span>
    </div>
</div>

<!-- META BAR -->
<div class="meta-bar">
    <div class="meta-left">
        <div class="cor-num">COR No.: {$corNo}</div>
        <div class="cor-dates">Issued: {$dateIssued} &nbsp;&bull;&nbsp; Enrollment Date: {$dateEnroll}</div>
    </div>
    <div class="meta-right"></div>
</div>

<!-- STUDENT INFORMATION -->
<div class="sec-hdr">Student Information</div>
<table class="info-tbl">
    <tr>
        <td class="lbl">LRN</td>
        <td class="val">{$lrn}</td>
        <td class="lbl">School Year</td>
        <td class="val">{$schoolYear}</td>
    </tr>
    <tr>
        <td class="lbl">Full Name</td>
        <td class="val" colspan="3"><strong>{$fullName}</strong></td>
    </tr>
    <tr>
        <td class="lbl">Citizenship</td>
        <td class="val">{$nationality}</td>
        <td class="lbl">Gender</td>
        <td class="val">{$sexLabel}</td>
    </tr>
    <tr>
        <td class="lbl">Address</td>
        <td class="val" colspan="3">{$fullAddress}</td>
    </tr>
    <tr>
        <td class="lbl">Grade Level</td>
        <td class="val">{$gradeLevel}</td>
        <td class="lbl">Section</td>
        <td class="val">{$sectionName}</td>
    </tr>
    <tr>
        <td class="lbl">Adviser</td>
        <td class="val" colspan="3">{$adviser}</td>
    </tr>
</table>

<!-- ENROLLED SUBJECTS -->
<div class="sec-hdr">Enrolled Subjects &amp; Class Schedule</div>
<table class="subj-tbl">
    <thead>
        <tr>
            <th style="width:11%;">Subject Code</th>
            <th style="width:28%;text-align:left;padding-left:7px;">Description</th>
            <th style="width:11%;">Section</th>
            <th style="width:9%;">Day</th>
            <th style="width:19%;">Schedule</th>
            <th style="width:9%;">Room</th>
            <th style="width:7%;">Units</th>
        </tr>
    </thead>
    <tbody>
        {$subjectRowsHtml}
    </tbody>
    <tfoot>
        <tr class="totals-row">
            <td colspan="6" style="text-align:right;padding-right:8px;">Total Units</td>
            <td class="cell-center">{$totalUnitsF}</td>
        </tr>
    </tfoot>
</table>

<!-- NOTE -->
<div class="note">
    This Certificate of Registration is issued for School Year <strong>{$schoolYear}</strong>.
    Any alterations or erasures render this document void. For concerns, contact the Registrar's Office.
</div>

<!-- REGISTRAR + STAMP -->
<div style="display:table;width:100%;margin-top:20px;">
    <div style="display:table-cell;width:60%;vertical-align:bottom;padding-right:20px;">
    </div>
    <div style="display:table-cell;width:40%;vertical-align:bottom;text-align:center;position:relative;">
        <!-- Stamp SVG -->
        <div style="position:relative;display:inline-block;margin-bottom:6px;">
            <svg width="140" height="140" viewBox="0 0 140 140" xmlns="http://www.w3.org/2000/svg" style="opacity:0.22;">
                <!-- Outer double ring -->
                <circle cx="70" cy="70" r="67" fill="none" stroke="#555555" stroke-width="3.5"/>
                <circle cx="70" cy="70" r="60" fill="none" stroke="#555555" stroke-width="1.2"/>
                <!-- Inner fill -->
                <circle cx="70" cy="70" r="56" fill="#aaaaaa" opacity="0.15"/>
                <!-- Top arc text: OFFICE OF THE REGISTRAR -->
                <path id="topArc" d="M 20,70 A 50,50 0 0,1 120,70" fill="none"/>
                <text font-family="Arial" font-size="8" font-weight="bold" fill="#333333" letter-spacing="1.5">
                    <textPath href="#topArc" startOffset="8%">OFFICE OF THE REGISTRAR</textPath>
                </text>
                <!-- Bottom arc text: ST. JOSEPH COLLEGE OF NOVALICHES -->
                <path id="botArc" d="M 18,72 A 52,52 0 0,0 122,72" fill="none"/>
                <text font-family="Arial" font-size="7" font-weight="bold" fill="#333333" letter-spacing="1">
                    <textPath href="#botArc" startOffset="3%">ST. JOSEPH COLLEGE OF NOVALICHES</textPath>
                </text>
                <!-- Horizontal divider lines -->
                <line x1="28" y1="60" x2="112" y2="60" stroke="#555555" stroke-width="0.8"/>
                <line x1="28" y1="82" x2="112" y2="82" stroke="#555555" stroke-width="0.8"/>
                <!-- Center status text -->
                <text x="70" y="68" text-anchor="middle" font-family="Arial" font-size="9" font-weight="bold" fill="#333333" letter-spacing="0.5">OFFICIALLY</text>
                <text x="70" y="79" text-anchor="middle" font-family="Arial" font-size="9" font-weight="bold" fill="#333333" letter-spacing="0.5">{$stampWord}</text>
                <!-- OR No label -->
                <text x="70" y="95" text-anchor="middle" font-family="Arial" font-size="6.5" fill="#333333">OR No.: ________________</text>
            </svg>
        </div>
        <div style="border-top:1px solid #6B0D23;margin:0 10px;"></div>
        <div style="font-size:8pt;font-weight:bold;color:#1a1a1a;margin-top:3px;">Registrar</div>
        <div style="font-size:7.5pt;color:#666;margin-top:1px;">Issued: {$dateIssued}</div>
    </div>
</div>

<!-- FOOTER -->
<div class="footer">
    Issue Date: {$dateIssued} {$timeIssued} &nbsp;&bull;&nbsp; {$corNo}
</div>

</body>
</html>
HTML;

// ── 10. Generate PDF with mPDF ────────────────────────────────
require_once dirname(__DIR__) . '/vendor/autoload.php';

$mpdf = new \Mpdf\Mpdf([
    'mode'          => 'utf-8',
    'format'        => 'A4',
    'margin_top'    => 10,
    'margin_bottom' => 10,
    'margin_left'   => 14,
    'margin_right'  => 14,
]);

$mpdf->SetTitle('Certificate of Registration — ' . $student['full_name']);
$mpdf->SetAuthor("Registrar's Office");

// ── Native mPDF watermark: centered, behind all content, every page ──
if ($watermarkRawPath) {
    $mpdf->SetWatermarkImage(
        $watermarkRawPath,
        0.07,          // alpha (opacity) — 0=transparent, 1=opaque
        [150, 150],    // [width, height] in mm — large enough to dominate the page center
        'P'            // position: 'P' = center of page
    );
    $mpdf->showWatermarkImage = true;
}

$mpdf->WriteHTML($html);

$cleanName = preg_replace('/[^A-Za-z0-9_]/', '_', $student['full_name']);
$filename  = "CertificateOfRegistration-{$cleanName}-{$student['school_year']}.pdf";
$mpdf->Output($filename, 'D');