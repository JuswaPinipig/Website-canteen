// scheduleData, studentName, studentGrade, studentLRN, studentSection
// are declared inline by schedule_view.php

// =============================================
// VIEW TOGGLE
// =============================================
function setView(v) {
    const isCalendar = v === 'calendar';
    document.getElementById('calendarView').style.display = isCalendar ? 'block' : 'none';
    document.getElementById('tableView').style.display   = isCalendar ? 'none' : 'block';
    document.getElementById('btn-calendar').classList.toggle('active',  isCalendar);
    document.getElementById('btn-table').classList.toggle('active', !isCalendar);

    if (isCalendar) buildCalendar();
}

// =============================================
// CALENDAR BUILDER
// =============================================
const DAYS_ORDER = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
const CAL_START  = 6;   // 6am
const CAL_END    = 21;  // 9pm
const SLOT_H     = 52;  // px per hour

function timeToMinutes(t) {
    if (!t) return 0;
    const clean = t.trim().toUpperCase();
    const m     = clean.match(/(\d+):(\d+)\s*(AM|PM)/);
    if (!m) return 0;
    let h = parseInt(m[1]);
    const min = parseInt(m[2]);
    if (m[3] === 'PM' && h !== 12) h += 12;
    if (m[3] === 'AM' && h === 12) h = 0;
    return h * 60 + min;
}

function buildCalendar() {
    const cal = document.getElementById('calendarView');
    if (!scheduleData || scheduleData.length === 0) { cal.innerHTML = ''; return; }

    // Parse events per day
    const byDay = {};
    DAYS_ORDER.forEach(d => byDay[d] = []);

    scheduleData.forEach(s => {
        const days = (s.days || '').split(/[,\/]/).map(d => d.trim());
        days.forEach(d => {
            if (byDay[d] !== undefined) {
                byDay[d].push(s);
            }
        });
    });

    const hours = [];
    for (let h = CAL_START; h <= CAL_END; h++) hours.push(h);

    const today = DAYS_ORDER[new Date().getDay()];

    let html = `<div class="calendar-wrapper">
    <div class="cal-header">
        <div class="cal-header-time"></div>`;

    DAYS_ORDER.forEach(d => {
        const isToday = d === today;
        html += `<div class="cal-header-day${isToday ? ' cal-day-today' : ''}">
            <div class="cal-day-name">${d.substring(0,3).toUpperCase()}</div>
        </div>`;
    });

    html += `</div><div class="cal-body">`;

    // Time column
    html += `<div class="cal-time-col">`;
    hours.forEach(h => {
        const label = h === 12 ? '12pm' : h > 12 ? (h-12)+'pm' : h+'am';
        html += `<div class="cal-time-slot"><span class="cal-time-label">${label}</span></div>`;
    });
    html += `</div>`;

    // Day columns
    DAYS_ORDER.forEach(d => {
        const isToday = d === today;
        html += `<div class="cal-day-col${isToday ? ' today-col' : ''}">`;

        // Empty cells for grid lines
        hours.forEach(() => { html += `<div class="cal-cell"></div>`; });

        // Events
        byDay[d].forEach(s => {
            const startMin  = timeToMinutes(s.time_start);
            const endMin    = timeToMinutes(s.time_end);
            const calStartM = CAL_START * 60;

            if (endMin <= calStartMin || startMin >= CAL_END * 60) return; // out of range

            const topPx    = ((startMin - calStartM) / 60) * SLOT_H;
            const heightPx = Math.max(((endMin - startMin) / 60) * SLOT_H - 2, 28);
            const teacher  = ((s.teacher_first||'') + ' ' + (s.teacher_last||'')).trim();

            html += `<div class="cal-event"
                style="top:${topPx}px;height:${heightPx}px;"
                onclick="openModal(${escapeJson(s)})">
                <div class="cal-event-subject">${esc(s.subject)}</div>
                <div class="cal-event-time">${esc(s.time_start)} – ${esc(s.time_end)}</div>
                <div class="cal-event-section">§ ${esc(s.section)}</div>
                ${teacher ? `<div class="cal-event-teacher">${esc(teacher)}</div>` : ''}
            </div>`;
        });

        html += `</div>`;
    });

    html += `</div></div>`;
    cal.innerHTML = html;
}

// Fix typo in buildCalendar
const calStartMin = CAL_START * 60;

function esc(s){ return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
function escapeJson(obj){ return JSON.stringify(obj).replace(/'/g,"&#39;"); }

// =============================================
// TABLE VIEW — build grouped by day
// =============================================
function buildTable() {
    const container = document.getElementById('tableView');
    if (!scheduleData || scheduleData.length === 0) return;

    const DAY_ORDER_MAP = {};
    DAYS_ORDER.forEach((d,i) => DAY_ORDER_MAP[d] = i);

    // Group by day
    const grouped = {};
    scheduleData.forEach(s => {
        const days = (s.days || '').split(/[,\/]/).map(d => d.trim());
        days.forEach(d => {
            if (!grouped[d]) grouped[d] = [];
            grouped[d].push(s);
        });
    });

    // Sort days
    const sortedDays = Object.keys(grouped).sort((a,b) =>
        (DAY_ORDER_MAP[a]??99) - (DAY_ORDER_MAP[b]??99)
    );

    let html = `<div class="pdf-section">
        <button class="pdf-btn" onclick="generatePDF()">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
            Download PDF
        </button>
    </div>`;

    sortedDays.forEach((day, idx) => {
        const rows = grouped[day];
        const groupId = 'day-group-' + day.toLowerCase();
        html += `<div class="day-group" id="${groupId}">
            <div class="day-group-header day-group-toggle" onclick="toggleDayGroup('${groupId}')" role="button" aria-expanded="false">
                <div class="day-group-dot"></div>
                <div class="day-group-name">${esc(day)}</div>
                <div class="day-group-count">${rows.length} ${rows.length===1?'class':'classes'}</div>
                <div class="day-group-line"></div>
                <div class="day-group-chevron">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M6 9l6 6 6-6"/></svg>
                </div>
            </div>
            <div class="day-group-body">
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Subject</th>
                            <th>Section</th>
                            <th>Schedule</th>
                            <th>Room</th>
                            <th>Instructor</th>
                        </tr>
                    </thead>
                    <tbody>`;

        rows.sort((a,b) => timeToMinutes(a.time_start) - timeToMinutes(b.time_start));

        rows.forEach(s => {
            const teacher = esc(((s.teacher_first||'') + ' ' + (s.teacher_last||'')).trim());
            html += `<tr onclick="openModal(${escapeJson(s).replace(/"/g,'&quot;')})">
                <td>
                    <div class="td-subject">${esc(s.subject)}</div>
                </td>
                <td><div class="td-section">${esc(s.section)}</div></td>
                <td>${esc(s.time_start)} – ${esc(s.time_end)}</td>
                <td>${esc(s.room||'—')}</td>
                <td><div class="td-teacher"><div class="td-teacher-dot"></div>${teacher||'—'}</div></td>
            </tr>`;
        });

        html += `</tbody></table></div></div></div>`;
    });

    container.innerHTML = html;
}

// =============================================
// MODAL
// =============================================
function openModal(data) {
    if (typeof data === 'string') {
        try { data = JSON.parse(data); } catch(e){ return; }
    }
    const teacherFirst = data.teacher_first || '';
    const teacherLast  = data.teacher_last  || '';
    const teacherName  = (teacherFirst + ' ' + teacherLast).trim();
    const initials     = (teacherFirst[0]||'') + (teacherLast[0]||'');
    const pct          = data.capacity > 0 ? Math.round((data.enrolled_count / data.capacity) * 100) : 0;

    document.getElementById('m-tag').textContent     = 'Grade ' + (data.grade||'—') + ' · Section ' + (data.section||'—');
    document.getElementById('m-subject').textContent  = data.subject || '—';
    document.getElementById('m-section').textContent  = 'Section ' + (data.section||'—');
    document.getElementById('m-grade').textContent    = 'Grade ' + (data.grade||'—');
    document.getElementById('m-schedule').textContent = data.schedule || '—';
    document.getElementById('m-room').textContent     = data.room || '—';
    document.getElementById('m-capacity').textContent = (data.capacity||0) + ' seats';
    document.getElementById('m-enrolled').textContent = (data.enrolled_count||0) + ' students';
    document.getElementById('m-teacher-initials').textContent = initials.toUpperCase() || '?';
    document.getElementById('m-teacher-name').textContent     = teacherName || '—';
    document.getElementById('m-teacher-subject').textContent  = (data.teacher_subject||'Subject') + ' Teacher';
    document.getElementById('m-pct').textContent = pct + '%';

    document.getElementById('modalOverlay').classList.add('open');
    setTimeout(() => { document.getElementById('m-bar').style.width = pct + '%'; }, 150);
}

function closeModal() {
    document.getElementById('modalOverlay').classList.remove('open');
    document.getElementById('m-bar').style.width = '0%';
}

function closeModalOutside(e) {
    if (e.target === document.getElementById('modalOverlay')) closeModal();
}

document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });

// =============================================
// PDF EXPORT — Premium layout
// =============================================
function generatePDF() {
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF({ unit: 'mm', format: 'a4' });
    const W = 210, margin = 18;

    // ── Maroon header band ──
    doc.setFillColor(40, 0, 0);
    doc.rect(0, 0, W, 50, 'F');

    // Gold accent line
    doc.setDrawColor(212, 175, 55);
    doc.setLineWidth(0.6);
    doc.line(0, 50, W, 50);

    // Logo — try to load from same server path
    try {
        const logoPath = '../student media/school no bg.png';
        doc.addImage(logoPath, 'PNG', margin, 8, 22, 22);
    } catch(e) { /* logo not available in PDF context */ }

    // School name / title block
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(14);
    doc.setTextColor(255, 255, 255);
    doc.text('OFFICIAL CLASS SCHEDULE', W/2, 18, { align: 'center' });

    doc.setFontSize(8);
    doc.setTextColor(212, 175, 55);
    doc.text('Academic Year 2026 – 2027', W/2, 26, { align: 'center' });

    doc.setFontSize(7);
    doc.setTextColor(180, 180, 180);
    doc.text('This is an official computer-generated document. No signature required.', W/2, 33, { align: 'center' });

    // ── Student Info Band ──
    doc.setFillColor(250, 248, 242);
    doc.rect(0, 50, W, 28, 'F');

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8.5);
    doc.setTextColor(60, 60, 60);

    const lrnDisplay = (typeof studentLRN !== 'undefined' && studentLRN) ? studentLRN : '—';
    const secDisplay = (typeof studentSection !== 'undefined' && studentSection) ? studentSection : '—';

    doc.setFont('helvetica', 'bold');
    doc.setTextColor(40, 0, 0);
    doc.setFontSize(9);
    doc.text('STUDENT INFORMATION', margin, 60);

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8.5);
    doc.setTextColor(60, 60, 60);
    doc.text('Name:', margin, 68);
    doc.setFont('helvetica', 'bold');
    doc.text(studentName, margin + 16, 68);

    doc.setFont('helvetica', 'normal');
    doc.text('LRN:', margin + 90, 68);
    doc.setFont('helvetica', 'bold');
    doc.text(lrnDisplay, margin + 102, 68);

    doc.setFont('helvetica', 'normal');
    doc.text('Section:', margin, 74.5);
    doc.setFont('helvetica', 'bold');
    doc.text(secDisplay, margin + 18, 74.5);

    doc.setFont('helvetica', 'normal');
    doc.text('Grade:', margin + 90, 74.5);
    doc.setFont('helvetica', 'bold');
    doc.text(studentGrade, margin + 104, 74.5);

    doc.setFont('helvetica', 'normal');
    doc.setFontSize(7.5);
    doc.setTextColor(120);
    doc.text('Date Issued: ' + new Date().toLocaleDateString('en-PH',{year:'numeric',month:'long',day:'numeric'}), W - margin, 74.5, { align: 'right' });

    // Gold divider
    doc.setDrawColor(212, 175, 55);
    doc.setLineWidth(0.4);
    doc.line(margin, 79, W - margin, 79);

    // ── Schedule Table ──
    // Group and sort by day
    const dayOrder = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    const grouped = {};
    scheduleData.forEach(s => {
        const days = (s.days||'').split(/[,\/]/).map(d => d.trim());
        days.forEach(d => {
            if (!grouped[d]) grouped[d] = [];
            grouped[d].push(s);
        });
    });

    const sortedDays = Object.keys(grouped).sort((a,b) =>
        (dayOrder.indexOf(a)===-1?99:dayOrder.indexOf(a)) - (dayOrder.indexOf(b)===-1?99:dayOrder.indexOf(b))
    );

    let rows = [];
    sortedDays.forEach(day => {
        const dayRows = grouped[day].sort((a,b) => {
            const ta = (a.time_start||'').replace(/[AP]M/,'');
            const tb = (b.time_start||'').replace(/[AP]M/,'');
            return ta.localeCompare(tb);
        });
        dayRows.forEach((s,i) => {
            rows.push([
                i===0 ? day : '',
                s.subject || '—',
                s.section || '—',
                (s.time_start||'') + ' – ' + (s.time_end||''),
                s.room || '—',
                ((s.teacher_first||'') + ' ' + (s.teacher_last||'')).trim() || '—'
            ]);
        });
    });

    doc.autoTable({
        head: [['Day', 'Subject', 'Section', 'Time', 'Room', 'Instructor']],
        body: rows,
        startY: 83,
        theme: 'grid',
        headStyles: {
            fillColor: [40, 0, 0],
            textColor: [212, 175, 55],
            fontSize: 7.5,
            halign: 'center',
            fontStyle: 'bold',
            cellPadding: 3,
        },
        bodyStyles: { textColor: [50, 10, 10], fontSize: 7.5, cellPadding: 2.8 },
        columnStyles: {
            0: { fontStyle: 'bold', cellWidth: 20, fillColor: [250, 245, 235] },
            1: { fontStyle: 'bold', cellWidth: 52 },
            2: { cellWidth: 28 },
            3: { cellWidth: 34, halign: 'center' },
            4: { cellWidth: 14, halign: 'center' },
        },
        alternateRowStyles: { fillColor: [253, 251, 245] },
        margin: { left: margin, right: margin },
    });

    // ── Footer ──
    const finalY = doc.lastAutoTable.finalY + 10;

    doc.setFillColor(40, 0, 0);
    doc.rect(0, finalY, W, 18, 'F');

    doc.setFont('helvetica', 'italic');
    doc.setFontSize(7.5);
    doc.setTextColor(212, 175, 55);
    doc.text('Issued by the Office of the School Registrar', W/2, finalY + 7, { align: 'center' });
    doc.setTextColor(180, 180, 180);
    doc.text('This document is valid without signature. For inquiries, contact the Registrar\'s Office.', W/2, finalY + 13, { align: 'center' });

    doc.save(studentName.replace(/ /g,'_') + '_Schedule.pdf');
}

// =============================================
// COLLAPSIBLE DAY GROUPS
// =============================================
function toggleDayGroup(groupId) {
    const group = document.getElementById(groupId);
    if (!group) return;
    const isCollapsed = group.classList.contains('collapsed');
    if (isCollapsed) {
        group.classList.remove('collapsed');
        group.querySelector('.day-group-toggle').setAttribute('aria-expanded', 'true');
    } else {
        group.classList.add('collapsed');
        group.querySelector('.day-group-toggle').setAttribute('aria-expanded', 'false');
    }
}

// =============================================
// INIT
// =============================================
document.addEventListener('DOMContentLoaded', () => {
    buildTable();
    // Collapse all day groups by default after building
    document.querySelectorAll('.day-group').forEach(g => {
        g.classList.add('collapsed');
    });
});