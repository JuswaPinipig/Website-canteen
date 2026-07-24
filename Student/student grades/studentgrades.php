<?php require_once __DIR__ . '/studentgradesdata.php'; ?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Academic Grades — <?= htmlspecialchars($student['first_name'] . ' ' . $student['last_name']) ?></title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@400;500;600;700&family=DM+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="studentgrades.css">
</head>
<body>

<!-- ═══════════════════════════════════════════════════════════ HEADER ══ -->
<header class="portal-header">
    <div class="header-content">
        <div class="logo-section">
            <img src="../student media/school no bg.png" alt="School Logo" class="school-logo-img">
            <h1 class="portal-title">Academic Records</h1>
        </div>
        <a href="../student.html" class="back-btn">← Portal</a>
    </div>
</header>

<!-- ═══════════════════════════════════════════════════ MAIN CONTAINER ══ -->
<div class="container fade-in">

    <!-- ── STUDENT IDENTITY CARD ──────────────────────────────────────── -->
    <section class="identity-card">
        <div class="identity-left">
            <div class="identity-badge">S.Y. 2025–2026</div>
            <h2 class="student-name">
                <?= htmlspecialchars($student['last_name'] . ', ' . $student['first_name']) ?>
            </h2>
            <p class="student-meta">
                <?= htmlspecialchars($gradeLabel) ?>
                &nbsp;·&nbsp; LRN: <?= htmlspecialchars($student['lrn']) ?>
            </p>
        </div>

        <?php if ($gwa !== null): ?>
        <div class="identity-right">
            <span class="gwa-label">General Average</span>
            <div class="gwa-value"><?= number_format($gwa, 2) ?></div>
        </div>
        <?php endif; ?>
    </section>

    <!-- ── TERM FILTER TABS ───────────────────────────────────────────── -->
    <div class="term-tabs">
        <button class="tab-btn active" onclick="filterTerm(event, 'all')">All Terms</button>
        <button class="tab-btn"        onclick="filterTerm(event, 'q1')">1st Term</button>
        <button class="tab-btn"        onclick="filterTerm(event, 'q2')">2nd Term</button>
        <button class="tab-btn"        onclick="filterTerm(event, 'q3')">3rd Term</button>
    </div>

    <!-- ── GRADES CONTENT ─────────────────────────────────────────────── -->
    <?php if (empty($grades)): ?>

        <!-- Empty state: no approved grades yet -->
        <div class="empty-state">
            <div class="empty-icon">📋</div>
            <h3>No Released Grades Yet</h3>
            <p>Your grades will appear here once they have been reviewed and approved by the school registrar.</p>
        </div>

    <?php else: ?>

        <!-- Grades table card -->
        <div class="grades-card">
            <div class="card-header">
                <div>
                    <h3>Subject Performance</h3>
                    <div class="header-line"></div>
                </div>
                <span class="released-badge">✓ Official Release</span>
            </div>

            <div class="table-wrap">
                <table class="grades-table" id="gradesTable">
                    <thead>
                        <tr>
                            <th class="th-subject">Learning Area</th>
                            <th class="th-term q-col q1">1st Term</th>
                            <th class="th-term q-col q2">2nd Term</th>
                            <th class="th-term q-col q3">3rd Term</th>
                            <th class="th-avg final-col">Average</th>
                            <th class="th-rem">Remarks</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($grades as $g): ?>
                        <tr class="grade-row">

                            <!-- Subject + teacher tooltip -->
                            <td class="subject-cell">
                                <span class="subject-text">
                                    <?= htmlspecialchars($g['subject']) ?>
                                    <span class="teacher-tooltip">
                                        <span class="tooltip-label">Teacher</span>
                                        <?= htmlspecialchars($g['teacher_name']) ?>
                                    </span>
                                </span>
                            </td>

                            <!-- 1st Term -->
                            <td class="q-col q1 score-cell <?= ($g['q1'] !== null && $g['q1'] < 75) ? 'score-low' : '' ?>">
                                <?= $g['q1'] !== null
                                    ? number_format($g['q1'], 0)
                                    : '<span class="no-grade">—</span>' ?>
                            </td>

                            <!-- 2nd Term -->
                            <td class="q-col q2 score-cell <?= ($g['q2'] !== null && $g['q2'] < 75) ? 'score-low' : '' ?>">
                                <?= $g['q2'] !== null
                                    ? number_format($g['q2'], 0)
                                    : '<span class="no-grade">—</span>' ?>
                            </td>

                            <!-- 3rd Term -->
                            <td class="q-col q3 score-cell <?= ($g['q3'] !== null && $g['q3'] < 75) ? 'score-low' : '' ?>">
                                <?= $g['q3'] !== null
                                    ? number_format($g['q3'], 0)
                                    : '<span class="no-grade">—</span>' ?>
                            </td>

                            <!-- Average -->
                            <td class="final-col avg-cell <?= ($g['average'] !== null && $g['average'] < 75) ? 'score-low' : '' ?>">
                                <?= $g['average'] !== null ? number_format($g['average'], 2) : '—' ?>
                            </td>

                            <!-- Remarks -->
                            <td class="remarks-cell">
                                <?php if ($g['average'] === null): ?>
                                    <span class="rem-pending">Pending</span>
                                <?php elseif ($g['passed']): ?>
                                    <span class="rem-pass">Passed</span>
                                <?php else: ?>
                                    <span class="rem-fail">Failed</span>
                                <?php endif; ?>
                            </td>

                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>

    <?php endif; ?>

</div><!-- /container -->

<script src="studentgrades.js"></script>
</body>
</html>