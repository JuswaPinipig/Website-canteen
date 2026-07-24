<?php
if (!is_array($student) || !is_array($schedules)) {
    http_response_code(403);
    die("Access denied. Please access this page through the student portal.");
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>My Schedule | Student Portal</title>
    <link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@400;700;900&family=DM+Sans:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="schedule.css">
</head>
<body>

<!-- HEADER -->
<header class="header">
    <div class="header-inner">
        <div class="header-brand">
            <img src="../student media/school no bg.png" alt="School Logo" onerror="this.style.display='none'">
            <div class="header-brand-text">
                <span class="brand-title">Student Portal</span>
                <span class="brand-sub">Class Schedule</span>
            </div>
        </div>
        <a href="../student.html" class="back-btn">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M19 12H5M5 12l7 7M5 12l7-7"/></svg>
            Back to Portal
        </a>
    </div>
</header>

<!-- MAIN -->
<main class="main">

    <!-- STUDENT HERO -->
    <div class="student-hero">
        <div class="student-info">
            <div class="student-greeting">Academic Schedule · AY 2026–2027</div>
            <div class="student-name"><?= htmlspecialchars($student['first_name'] . ' ' . $student['last_name']) ?></div>
            <div class="student-badges">
                <span class="badge badge-grade">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M22 10v6M2 10l10-5 10 5-10 5z"/><path d="M6 12v5c3 3 9 3 12 0v-5"/></svg>
                    Grade <?= htmlspecialchars($student['grade_level']) ?>
                </span>
                <?php if (!empty($student['section_name'])): ?>
                <span class="badge badge-grade">§ <?= htmlspecialchars($student['section_name']) ?></span>
                <?php endif; ?>
                <?php if (!empty($student['lrn'])): ?>
                <span class="badge badge-lrn">LRN <?= htmlspecialchars($student['lrn']) ?></span>
                <?php endif; ?>
                <span class="badge badge-count">
                    <?= count($schedules) ?> <?= count($schedules) === 1 ? 'Class' : 'Classes' ?>
                </span>
            </div>
        </div>
        <div class="hero-actions">
            <div class="view-toggle">
                <button class="view-btn active" id="btn-table" onclick="setView('table')">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 9h18M3 15h18M9 3v18M15 3v18"/></svg>
                    Column
                </button>
                <button class="view-btn" id="btn-calendar" onclick="setView('calendar')">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>
                    Calendar
                </button>
            </div>
        </div>
    </div>

    <?php if (empty($schedules)): ?>
    <!-- EMPTY STATE -->
    <div class="empty-state">
        <div class="empty-icon">📋</div>
        <div class="empty-title">No classes assigned yet.</div>
        <p class="empty-sub">Your schedule will appear here once classes are assigned by the registrar. Please check back later or contact the registrar's office.</p>
    </div>

    <?php else: ?>

    <!-- SECTION LABEL -->
    <div class="section-label">
        <span class="section-label-text">Enrolled Classes</span>
        <div class="section-label-line"></div>
    </div>

    <!-- TABLE VIEW (default) -->
    <div id="tableView"></div>

    <!-- CALENDAR VIEW -->
    <div id="calendarView"></div>

    <?php endif; ?>

</main>

<!-- DETAIL MODAL -->
<div class="modal-overlay" id="modalOverlay" onclick="closeModalOutside(event)">
    <div class="modal-card" id="modalCard">
        <div class="modal-header">
            <button class="modal-close" onclick="closeModal()">✕</button>
            <div class="modal-tag" id="m-tag">Class Details</div>
            <div class="modal-subject-name" id="m-subject">—</div>
            <span class="modal-section-badge" id="m-section">—</span>
        </div>
        <div class="modal-body">
            <div class="modal-grid">
                <div class="modal-info-item">
                    <span class="modal-info-label">Grade Level</span>
                    <span class="modal-info-value" id="m-grade">—</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">Room</span>
                    <span class="modal-info-value" id="m-room">—</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">Schedule</span>
                    <span class="modal-info-value" id="m-schedule">—</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">Class Capacity</span>
                    <span class="modal-info-value" id="m-capacity">—</span>
                </div>
                <div class="modal-info-item">
                    <span class="modal-info-label">Students Enrolled</span>
                    <span class="modal-info-value" id="m-enrolled">—</span>
                </div>
            </div>

            <div class="modal-divider"></div>

            <div class="modal-teacher-block">
                <div class="teacher-avatar" id="m-teacher-initials">—</div>
                <div>
                    <div class="teacher-info-name" id="m-teacher-name">—</div>
                    <div class="teacher-info-sub" id="m-teacher-subject">Subject Teacher</div>
                </div>
            </div>

            <div class="capacity-bar-wrap">
                <div class="capacity-bar-label">
                    <span>Class Fill Rate</span>
                    <span id="m-pct">—</span>
                </div>
                <div class="capacity-bar">
                    <div class="capacity-fill" id="m-bar" style="width:0%"></div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- SCRIPTS -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.5.25/jspdf.plugin.autotable.min.js"></script>

<script>
    const scheduleData   = <?= json_encode($schedules) ?>;
    const studentName    = <?= json_encode(trim($student['first_name'] . ' ' . $student['last_name'])) ?>;
    const studentGrade   = <?= json_encode('Grade ' . $student['grade_level']) ?>;
    const studentLRN     = <?= json_encode($student['lrn'] ?? '') ?>;
    const studentSection = <?= json_encode($student['section_name'] ?? '') ?>;
</script>

<script src="schedule.js"></script>

</body>
</html>