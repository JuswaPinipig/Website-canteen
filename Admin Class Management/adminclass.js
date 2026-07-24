/* ════════════════════════════════════════════════════════════
   ADMIN PORTAL — adminclass.js
   All modules: Dashboard, School Years, Class Mgmt,
   Subjects, Curriculum, Deadlines, Users, Audit Logs
════════════════════════════════════════════════════════════ */

'use strict';

/* ─── SCHOOL YEAR STATE (declared here to avoid TDZ errors) ── */
let _syPending        = null;
let _syCountdownTimer = null;

/* ─── API HELPERS ─────────────────────────────────────────── */
const API_BASE = 'adminclass.php';

async function api(action, data = {}) {
  const fd = new FormData();
  fd.append('action', action);
  for (const [k, v] of Object.entries(data)) fd.append(k, v);
  try {
    const res = await fetch(API_BASE, { method: 'POST', body: fd });
    return await res.json();
  } catch (e) {
    return { success: false, message: 'Network error' };
  }
}

/* ─── TOAST ───────────────────────────────────────────────── */
function toast(msg, type = 'info') {
  const icons = { success: 'fa-circle-check', error: 'fa-circle-xmark', info: 'fa-circle-info', warn: 'fa-triangle-exclamation' };
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.innerHTML = `<i class="fa-solid ${icons[type]} toast-icon"></i><span class="toast-msg">${msg}</span>`;
  document.getElementById('toastContainer').appendChild(el);
  setTimeout(() => { el.style.opacity = '0'; el.style.transition = 'opacity 0.3s'; setTimeout(() => el.remove(), 300); }, 3000);
}

/* ─── MODAL ───────────────────────────────────────────────── */
function openModal(title, bodyHTML, footerHTML = '', large = false, extraClass = '') {
  document.getElementById('modalTitle').textContent = title;
  document.getElementById('modalBody').innerHTML = bodyHTML;
  document.getElementById('modalFooter').innerHTML = footerHTML;
  const box = document.getElementById('modalBox');
  // Clear any previously applied extra classes, then apply new ones
  box.classList.remove('modal-lg', 'modal-deadline', 'modal-audit-detail');
  if (large) box.classList.add('modal-lg');
  if (extraClass) box.classList.add(extraClass);
  document.getElementById('modalOverlay').style.display = 'flex';
}

function closeModal() {
  document.getElementById('modalOverlay').style.display = 'none';
}

// Only call this when truly cancelling a SY flow (X button, backdrop click, or cancel btn)
function closeModalAndClearSY() {
  if (_syCountdownTimer) { clearInterval(_syCountdownTimer); _syCountdownTimer = null; }
  if (_dlCountdownTimer) { clearInterval(_dlCountdownTimer); _dlCountdownTimer = null; }
  _syPending = null;
  closeModal();
}

document.getElementById('modalClose').addEventListener('click', closeModalAndClearSY);
document.getElementById('modalOverlay').addEventListener('click', e => {
  if (e.target === document.getElementById('modalOverlay')) closeModalAndClearSY();
});

/* ─── THEME TOGGLE ────────────────────────────────────────── */
(function initTheme() {
  const saved = localStorage.getItem('adminTheme') || 'dark';
  document.documentElement.setAttribute('data-theme', saved);
})();

let _themeSwitching = false;

function toggleTheme() {
  if (_themeSwitching) return;               // anti-spam lock
  _themeSwitching = true;

  const btn     = document.getElementById('themeToggleBtn');
  const current = document.documentElement.getAttribute('data-theme') || 'dark';
  const next    = current === 'dark' ? 'light' : 'dark';

  // Step 1 — animate icons out
  btn.classList.add('theme-switching');
  btn.disabled = true;

  setTimeout(() => {
    // Step 2 — switch theme while icons are invisible
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('adminTheme', next);
    updateThemeLabel(next);

    // Step 3 — animate icons back in
    btn.classList.remove('theme-switching');

    setTimeout(() => {
      btn.disabled    = false;
      _themeSwitching = false;
    }, 420); // matches CSS cubic-bezier duration
  }, 260); // icons fully faded after 250ms
}

function updateThemeLabel(theme) {
  const lbl = document.getElementById('themeLabel');
  if (lbl) lbl.textContent = theme === 'light' ? 'Light' : 'Dark';
}




/* ─── GREETING TIME ───────────────────────────────────────── */
function getTimeOfDay() {
  const h = new Date().getHours();
  if (h < 12) return 'Morning';
  if (h < 17) return 'Afternoon';
  return 'Evening';
}

/* ════════════════════════════════════════════════════════════
   LOADING SEQUENCE
════════════════════════════════════════════════════════════ */
const LOAD_STEPS = [
  { pct: 15, msg: 'Connecting to database...' },
  { pct: 35, msg: 'Loading system configuration...' },
  { pct: 55, msg: 'Fetching academic data...' },
  { pct: 75, msg: 'Preparing user session...' },
  { pct: 92, msg: 'Finalizing portal...' },
  { pct: 100, msg: 'Ready.' },
];

async function runLoadingSequence() {
  const bar    = document.getElementById('loadingBar');
  const status = document.getElementById('loadingStatus');

  // Fetch current admin name during loading
  const sessionRes = await api('get_session');
  const adminName  = sessionRes.success ? sessionRes.data.name : 'Administrator';

  for (const step of LOAD_STEPS) {
    bar.style.width = step.pct + '%';
    status.textContent = step.msg;
    await delay(320 + Math.random() * 180);
  }

  await delay(300);

  // Hide loading screen
  const loadingScreen = document.getElementById('loadingScreen');
  loadingScreen.style.transition = 'opacity 0.4s ease';
  loadingScreen.style.opacity    = '0';
  await delay(400);
  loadingScreen.style.display = 'none';

  // Show greeting
  const greetingOverlay = document.getElementById('greetingOverlay');
  document.getElementById('greetingTime').textContent = getTimeOfDay();
  document.getElementById('greetingName').textContent = adminName;
  document.getElementById('sidebarUserName').textContent = adminName;
  document.getElementById('sidebarAvatar').textContent  = adminName.charAt(0).toUpperCase();
  document.getElementById('greetingName').textContent   = adminName;
  greetingOverlay.style.display = 'flex';

  await delay(2700); // Show greeting for ~2.7s (progress bar duration matches)

  greetingOverlay.style.transition = 'opacity 0.4s ease';
  greetingOverlay.style.opacity    = '0';
  await delay(400);
  greetingOverlay.style.display = 'none';

  // Show app
  const app = document.getElementById('app');
  app.style.display = 'flex';

  // Load default module
  activateModule('dashboard');
}

function delay(ms) { return new Promise(r => setTimeout(r, ms)); }

/* ════════════════════════════════════════════════════════════
   NAVIGATION
════════════════════════════════════════════════════════════ */
const MODULE_LABELS = {
  dashboard:        'Dashboard',
  'school-years':   'School Year',
  'class-management': 'Section Management',
  subjects:         'Subjects',
  deadlines:        'Academic Deadlines',
  users:            'Faculty Accounts',
  'student-accounts': 'Student Accounts',
  rooms:            'Room Management',
  audit:            'Audit Logs',
  'cafeteria-wallet':    'Cafeteria · Student Wallet',
  'cafeteria-menu':      'Cafeteria · Food Menu',
  'cafeteria-inventory': 'Cafeteria · Inventory',
};

function activateModule(module) {
  document.querySelectorAll('.nav-item').forEach(el => {
    el.classList.toggle('active', el.dataset.module === module);
  });
  document.getElementById('topbarModule').textContent = MODULE_LABELS[module] || module;

  // Auto-expand the Cafeteria dropdown group when one of its modules is active
  const cafGroup = document.getElementById('navGroupCafeteria');
  if (cafGroup) {
    cafGroup.classList.toggle('open', (module || '').startsWith('cafeteria-'));
  }

  const ca = document.getElementById('contentArea');
  ca.style.animation = 'none';
  ca.offsetHeight; // reflow
  ca.style.animation = '';

  renderModule(module);
}

document.querySelectorAll('.nav-item').forEach(el => {
  el.addEventListener('click', e => {
    e.preventDefault();

    // Dropdown group toggles (e.g. "Cafeteria") only expand/collapse the submenu
    if (el.classList.contains('nav-group-toggle')) {
      const group = el.closest('.nav-group');
      if (group) group.classList.toggle('open');
      return;
    }

    // Reset subject state when the user explicitly clicks the Subjects nav link
    if (el.dataset.module === 'subjects') {
      _subjFilterMode  = 'active';
      _subjGradeFilter = '';
      _subjSearch      = '';
      _subjPage        = 1;
      _subjTab         = 'list';
    }
    activateModule(el.dataset.module);
  });
});

// Sidebar toggle
document.getElementById('sidebarToggle').addEventListener('click', () => {
  const sidebar   = document.getElementById('sidebar');
  const mainWrap  = document.querySelector('.main-wrap');
  if (window.innerWidth <= 900) {
    sidebar.classList.toggle('mobile-open');
  } else {
    sidebar.classList.toggle('collapsed');
    mainWrap.classList.toggle('expanded');
  }
});

// Logout
document.getElementById('logoutBtn').addEventListener('click', () => {
  openModal('Confirm Logout', '<p style="color:var(--text-secondary)">Are you sure you want to log out of the Admin Portal?</p>',
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-danger" onclick="doLogout()"><i class="fa-solid fa-right-from-bracket"></i> Logout</button>`);
});

function doLogout() {
  api('logout').then(() => { window.location.href = '../Login/Maininterface.html'; });
}

/* ════════════════════════════════════════════════════════════
   MODULE ROUTER
════════════════════════════════════════════════════════════ */
async function renderModule(module) {
  const ca = document.getElementById('contentArea');
  ca.innerHTML = `<div class="flex-center" style="height:200px"><div class="spinner"></div></div>`;

  switch (module) {
    case 'dashboard':        return renderDashboard(ca);
    case 'school-years':     return renderSchoolYears(ca);
    case 'class-management': return renderClassManagement(ca);
    case 'subjects':         return renderSubjects(ca, 'active');
    case 'deadlines':        return renderDeadlines(ca);
    case 'users':            return renderUsers(ca);
    case 'student-accounts': return renderStudentAccounts(ca);
    case 'rooms':            return renderRooms(ca);
    case 'audit':            return renderAudit(ca);
    case 'cafeteria-wallet':    return renderCafeteriaWallet(ca);
    case 'cafeteria-menu':      return renderCafeteriaMenu(ca);
    case 'cafeteria-inventory': return renderCafeteriaInventory(ca);
  }
}

/* ════════════════════════════════════════════════════════════
   DASHBOARD
════════════════════════════════════════════════════════════ */
async function renderDashboard(ca) {
  const res = await api('get_dashboard_stats');
  const d   = res.success ? res.data : {};

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Dashboard</h1>
      <p>System overview · Admin Portal</p>
    </div>
  </div>

  <div class="stats-grid">
    <div class="stat-card">
      <div class="stat-icon"><i class="fa-solid fa-calendar-days"></i></div>
      <div class="stat-value">${d.school_years ?? '—'}</div>
      <div class="stat-label">School Years</div>
      <div class="stat-sub">Active: ${d.active_sy_label ?? 'None'}</div>
    </div>
    <div class="stat-card">
      <div class="stat-icon"><i class="fa-solid fa-door-open"></i></div>
      <div class="stat-value">${d.total_sections ?? '—'}</div>
      <div class="stat-label">Total Sections</div>
      <div class="stat-sub">Active: ${d.active_sections ?? 0}</div>
    </div>
    <div class="stat-card">
      <div class="stat-icon"><i class="fa-solid fa-book-open"></i></div>
      <div class="stat-value">${d.subjects ?? '—'}</div>
      <div class="stat-label">Subjects</div>
      <div class="stat-sub">Active in system</div>
    </div>
    <div class="stat-card">
      <div class="stat-icon"><i class="fa-solid fa-users-gear"></i></div>
      <div class="stat-value">${d.admin_users ?? '—'}</div>
      <div class="stat-label">Faculty Accounts</div>
      <div class="stat-sub">Registered accounts</div>
    </div>
  </div>

  <div style="display:grid;grid-template-columns:1fr 1fr;gap:20px;flex-wrap:wrap">
    <div class="panel">
      <div class="panel-header">
        <span class="panel-title"><i class="fa-solid fa-clock"></i> Upcoming Deadlines</span>
      </div>
      <div class="panel-body">
        ${renderDeadlinesMini(d.upcoming_deadlines)}
      </div>
    </div>
    <div class="panel">
      <div class="panel-header">
        <span class="panel-title"><i class="fa-solid fa-scroll"></i> Recent Audit Activity</span>
      </div>
      <div class="panel-body">
        ${renderAuditMini(d.recent_audit)}
      </div>
    </div>
  </div>`;
}

function renderDeadlinesMini(list) {
  if (!list || !list.length) return `<div class="empty-state"><i class="fa-solid fa-clock"></i><p>No upcoming deadlines</p></div>`;
  return list.map(d => {
    const startVal = d.start_datetime || d.start_date || '';
    const endVal   = d.end_datetime   || d.end_date   || '';
    return `
    <div class="deadline-row">
      <div class="deadline-type-badge">${(d.type_label || d.type).replace(/_/g,' ').toUpperCase()}</div>
      <div class="deadline-dates">${formatDT(startVal)} → ${formatDT(endVal)}</div>
      <div class="deadline-status"><span class="badge badge-active badge-dot">${d.status}</span></div>
    </div>`;
  }).join('');
}

function renderAuditMini(list) {
  if (!list || !list.length) return `<div class="empty-state"><i class="fa-solid fa-scroll"></i><p>No recent activity</p></div>`;
  return list.map(a => `
    <div style="display:flex;align-items:center;gap:10px;padding:9px 0;border-bottom:1px solid var(--border)">
      <span class="audit-action-badge audit-${a.action}">${a.action}</span>
      <span style="font-size:12px;color:var(--text-secondary);flex:1">${a.table_name} #${a.record_id}</span>
      <span style="font-size:11px;font-family:var(--font-mono);color:var(--text-muted)">${a.created_at}</span>
    </div>`).join('');
}

/* ════════════════════════════════════════════════════════════
   SCHOOL YEARS
════════════════════════════════════════════════════════════ */
async function renderSchoolYears(ca) {
  const res = await api('get_school_years');
  const rows = res.success ? res.data : [];

  const today = new Date().toISOString().slice(0, 10);
  // Detect an active SY — blocks activation of any other SY
  const activeSY = rows.find(r => r.is_active == 1 && r.is_finalized == 0);
  const hasActiveSY = !!activeSY;

  // Find the next queued SY (earliest start after activeSY's end, not finalized, not active)
  const nextSY = hasActiveSY
    ? rows
        .filter(r => r.id != activeSY.id && r.is_finalized != 1 && r.is_active != 1 && r.start_date > activeSY.end_date)
        .sort((a, b) => a.start_date.localeCompare(b.start_date))[0] || null
    : null;

  // Active SY policy banner shown at the top when a SY is currently active
  const activeBanner = hasActiveSY ? `
  <div class="sy-active-policy-banner">
    <div class="sy-active-policy-icon"><i class="fa-solid fa-shield-halved"></i></div>
    <div class="sy-active-policy-body">
      <div class="sy-active-policy-title">
        Active School Year Found — <strong>S.Y. ${escHTML(activeSY.label)}</strong>
      </div>
      <div class="sy-active-policy-text">
        <strong>S.Y. ${escHTML(activeSY.label)}</strong> is currently active and
        <strong>cannot be manually deactivated</strong>. It will only deactivate automatically
        once it reaches its set end date of <strong>${activeSY.end_date}</strong> and
        auto-advances to the next school year.
        ${nextSY
          ? `<span class="sy-active-policy-next"><i class="fa-solid fa-forward-step"></i>
             <strong>S.Y. ${escHTML(nextSY.label)}</strong> is queued and will be activated
             automatically when S.Y. ${escHTML(activeSY.label)} ends.</span>`
          : `<span class="sy-active-policy-next sy-active-policy-next--warn">
             <i class="fa-solid fa-triangle-exclamation"></i>
             No next school year is queued. Create one before <strong>${activeSY.end_date}</strong>
             to enable automatic transition.</span>`
        }
      </div>
      <div class="sy-active-policy-rule">
        <i class="fa-solid fa-lock"></i>
        No other school year can be activated while S.Y. ${escHTML(activeSY.label)} is active.
        Activation buttons are disabled until this school year completes.
      </div>
    </div>
  </div>` : '';

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>School Year</h1>
      <p>Define and manage the academic year period</p>
    </div>
    <button class="btn btn-primary" onclick="openAddSchoolYear()">
      <i class="fa-solid fa-plus"></i> New School Year
    </button>
  </div>

  ${activeBanner}

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-calendar-days"></i> School Year Records</span>
      <span class="text-muted text-mono">${rows.length} record${rows.length !== 1 ? 's' : ''}</span>
    </div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Label</th>
            <th>Start Date</th>
            <th>End Date</th>
            <th>Status</th>
            <th>Created</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          ${rows.length ? rows.map(r => {
            const isFinalized  = r.is_finalized == 1;
            const isActive     = r.is_active == 1;
            const isConfirmed  = r.is_confirmed == 1;
            const isPast       = today >= r.end_date;
            const isFuture     = today < r.start_date;

            // status column from DB — fall back to deriving from flags
            const dbStatus = r.status || (
              isFinalized  ? 'completed' :
              isActive     ? 'active'    :
              isPast       ? 'completed' : 'upcoming'
            );

            const isLocked    = isConfirmed && !isPast;
            const canFinalize = !isFinalized && isPast && isActive;
            const canEdit     = !isFinalized && !isLocked && !isActive;
            // Can only activate if: not finalized, not already active, upcoming status,
            // AND no other SY is currently active
            const canActivate = !isFinalized && !isActive && dbStatus === 'upcoming' && !hasActiveSY;

            // Status badge
            let statusBadge = '';
            if (isFinalized || dbStatus === 'completed') {
              statusBadge = '<span class="badge badge-archived"><i class="fa-solid fa-lock" style="margin-right:4px"></i>Completed</span>';
            } else if (isActive || dbStatus === 'active') {
              statusBadge = '<span class="badge badge-active badge-dot"><i class="fa-solid fa-circle-check" style="margin-right:4px;font-size:10px"></i>Active</span>';
            } else {
              const upcomingLabel = isFuture ? 'Upcoming' : 'Upcoming (Ready)';
              statusBadge = '<span class="badge badge-upcoming"><i class="fa-solid fa-calendar-check" style="margin-right:4px;font-size:10px"></i>' + upcomingLabel + '</span>';
            }

            const confirmedLockChip = isLocked && !isActive
              ? '<span class="sy-lock-chip" title="Dates locked until end date"><i class="fa-solid fa-lock"></i> Dates locked</span>'
              : '';

            const editBtn = canEdit
              ? '<button class="btn-icon sy-edit-btn" data-syid="'+r.id+'" title="Edit dates"><i class="fa-solid fa-pen"></i></button>'
              : '';

            // Activate button: grayed out (disabled) when another SY is already active
            let switchBtn = '';
            if (isActive) {
              switchBtn = '<span style="font-size:11px;color:var(--success,#22c55e);font-family:var(--font-mono);padding:4px 6px"><i class="fa-solid fa-toggle-on"></i> Active</span>';
            } else if (!isFinalized && dbStatus === 'upcoming') {
              if (hasActiveSY) {
                // Grayed-out disabled button with tooltip explaining why
                switchBtn = '<button class="btn-icon sy-switch-btn sy-switch-btn--blocked" data-syid="'+r.id+'" disabled title="Cannot activate — S.Y. '+escHTML(activeSY.label)+' is currently active. It must complete first."><i class="fa-solid fa-toggle-off"></i></button>';
              } else {
                switchBtn = '<button class="btn-icon sy-switch-btn sy-switch-btn--upcoming" data-syid="'+r.id+'" title="Activate this school year"><i class="fa-solid fa-toggle-off"></i></button>';
              }
            }

            const finalBtn = canFinalize
              ? '<button class="btn-icon btn-icon-warn sy-final-btn" data-syid="'+r.id+'" data-sylabel="'+r.label+'" title="Complete &amp; Lock"><i class="fa-solid fa-flag-checkered"></i></button>'
              : '';
            const lockedTag = isFinalized
              ? '<span style="font-size:10px;font-family:var(--font-mono);color:var(--text-muted);padding:4px 6px"><i class="fa-solid fa-lock"></i> Locked</span>'
              : '';

            return '<tr data-syid="'+r.id+'" data-sylabel="'+r.label+'" data-systart="'+r.start_date+'" data-syend="'+r.end_date+'" data-syactive="'+r.is_active+'" data-systatus="'+(dbStatus)+'">' +
              '<td class="td-primary td-mono">'+r.label+'</td>' +
              '<td class="td-mono">'+r.start_date+'</td>' +
              '<td class="td-mono">'+r.end_date+'</td>' +
              '<td>'+statusBadge+'</td>' +
              '<td class="td-mono">'+r.created_at+'</td>' +
              '<td><div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center">'+confirmedLockChip+editBtn+switchBtn+finalBtn+lockedTag+'</div></td>' +
              '</tr>';
          }).join('') : '<tr><td colspan="6"><div class="empty-state"><i class="fa-solid fa-calendar-days"></i><p>No school years yet. Create one to get started.</p></div></td></tr>'}
        </tbody>
      </table>
    </div>
  </div>`;

  // ── Event delegation for SY table action buttons ──────────
  function _syCaClickHandler(e) {
    const editBtn  = e.target.closest('.sy-edit-btn');
    const swBtn    = e.target.closest('.sy-switch-btn');
    const finBtn   = e.target.closest('.sy-final-btn');
    if (editBtn) {
      const tr = editBtn.closest('tr[data-syid]');
      openEditSchoolYear(
        parseInt(tr.dataset.syid),
        tr.dataset.sylabel,
        tr.dataset.systart,
        tr.dataset.syend,
        parseInt(tr.dataset.syactive)
      );
    } else if (swBtn) {
      setSYActive(parseInt(swBtn.dataset.syid));
    } else if (finBtn) {
      confirmFinalizeSY(parseInt(finBtn.dataset.syid), finBtn.dataset.sylabel);
    }
  }
  // Remove any previously stacked listener before adding a fresh one
  ca.removeEventListener('click', ca._syCaClickHandler);
  ca._syCaClickHandler = _syCaClickHandler;
  ca.addEventListener('click', _syCaClickHandler);
}

function openAddSchoolYear() {
  const today = new Date();
  const currentYear = today.getFullYear();
  const minStart = `${currentYear}-01-01`;
  const maxEnd   = `${currentYear + 3}-12-31`;

  openModal('New School Year',
    `<div class="sy-label-preview-wrap">
       <div class="sy-label-preview-tag" id="syLabelPreview">
         <i class="fa-solid fa-calendar-days"></i>
         <span id="syLabelText">Set dates below to generate label</span>
       </div>
       <div class="sy-label-hint">School year label is automatically generated from your selected dates</div>
     </div>
     <input type="hidden" id="syLabel"/>
     <div class="form-grid">
       <div class="form-group">
         <label>Start Date</label>
         <input type="date" id="syStart" min="${minStart}" max="${maxEnd}" oninput="syncSYLabel()"/>
       </div>
       <div class="form-group">
         <label>End Date</label>
         <input type="date" id="syEnd" min="${minStart}" max="${maxEnd}" oninput="syncSYLabel()"/>
       </div>
     </div>
     <div class="sy-disclaimer-box">
       <i class="fa-solid fa-triangle-exclamation"></i>
       <div>
         <strong>Important:</strong> This school year will be saved as <strong>inactive</strong>. It will <strong>not</strong> be automatically activated — you must activate it manually when you are ready. Once confirmed, dates and label will be <strong>permanently locked</strong> until the end date passes. You will have <strong>5 seconds</strong> to review before confirming.
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-success" onclick="submitAddSchoolYear()"><i class="fa-solid fa-plus"></i> Create &amp; Review</button>`);
}

function syncSYLabel() {
  const startVal = document.getElementById('syStart')?.value;
  const endVal   = document.getElementById('syEnd')?.value;
  const previewTag  = document.getElementById('syLabelPreview');
  const previewText = document.getElementById('syLabelText');
  if (startVal && endVal) {
    const sy = startVal.slice(0, 4);
    const ey = endVal.slice(0, 4);
    if (sy && ey) {
      const label = `${sy}-${ey}`;
      const hiddenLabel = document.getElementById('syLabel');
      if (hiddenLabel) hiddenLabel.value = label;
      if (previewText) previewText.textContent = `S.Y. ${label}`;
      if (previewTag)  previewTag.classList.add('sy-label-preview-tag--set');
    }
  } else {
    if (previewText) previewText.textContent = 'Set dates below to generate label';
    if (previewTag)  previewTag.classList.remove('sy-label-preview-tag--set');
  }
}

function validateSYDates(label, start, end) {
  const currentYear = new Date().getFullYear();

  if (!label || !start || !end) return 'Please fill in all fields.';
  if (!/^\d{4}-\d{4}$/.test(label))
    return `Label must follow the format YYYY-YYYY (e.g. ${currentYear}-${currentYear + 1}).`;

  const [ls, le] = label.split('-').map(Number);
  if (le !== ls + 1)
    return `Label must span exactly one year (e.g. ${currentYear}-${currentYear + 1}).`;
  if (ls < currentYear || ls > currentYear + 2)
    return `Start year must be between ${currentYear} and ${currentYear + 2}.`;

  const sy = parseInt(start.slice(0,4), 10);
  const ey = parseInt(end.slice(0,4), 10);
  if (ls !== sy || le !== ey)
    return `Label "${label}" does not match the start/end years (${sy}–${ey}).`;
  if (new Date(end) <= new Date(start)) return 'End date must be after start date.';
  const diffMonths = (ey - sy) * 12 + (parseInt(end.slice(5,7),10) - parseInt(start.slice(5,7),10));
  if (diffMonths > 14) return 'A school year cannot span more than 14 months.';
  return null; // valid
}

async function submitAddSchoolYear() {
  const label  = document.getElementById('syLabel').value.trim();
  const start  = document.getElementById('syStart').value;
  const end    = document.getElementById('syEnd').value;
  const err = validateSYDates(label, start, end);
  if (err) return toast(err, 'warn');

  // Front-end duplicate label check — fetch existing SYs and compare
  const existingRes = await api('get_school_years');
  if (existingRes.success && existingRes.data) {
    const duplicate = existingRes.data.find(r => r.label === label);
    if (duplicate) {
      toast(`School year ${label} already exists. Duplicate school years are not allowed.`, 'error');
      return;
    }
  }

  // New SYs are always created inactive — admin must activate manually
  openSYCountdownConfirm(label, start, end, 0);
}

/* ─── 5-SECOND COUNTDOWN CONFIRMATION FOR SCHOOL YEAR ─── */
function _startSYCountdown() {
  const TOTAL = 5;
  const CIRC  = 213.6;
  let remaining = TOTAL;

  if (_syCountdownTimer) { clearInterval(_syCountdownTimer); _syCountdownTimer = null; }

  // Ensure button starts disabled (set after modal has rendered)
  setTimeout(() => {
    const btn = document.getElementById('syConfirmBtn');
    if (btn) btn.disabled = true;
  }, 0);

  _syCountdownTimer = setInterval(() => {
    remaining--;
    // Re-query elements each tick — guarantees we have live DOM references
    const circleEl  = document.getElementById('syCountdownCircle');
    const numEl     = document.getElementById('syCountdownNum');
    const confirmBtn = document.getElementById('syConfirmBtn');
    const lblEl     = document.getElementById('syCountdownLabelText');

    if (numEl)    numEl.textContent = remaining;
    if (circleEl) circleEl.style.strokeDashoffset = CIRC * (1 - remaining / TOTAL);

    if (remaining <= 0) {
      clearInterval(_syCountdownTimer); _syCountdownTimer = null;
      if (confirmBtn) {
        confirmBtn.disabled = false;
        confirmBtn.removeAttribute('disabled');
        confirmBtn.classList.add('btn-pulse');
      }
      if (numEl)  numEl.textContent = '✓';
      if (lblEl)  lblEl.textContent = 'Review complete — you may now confirm';
    }
  }, 1000);
}

function openSYCountdownConfirm(label, start, end, active) {
  if (_syCountdownTimer) { clearInterval(_syCountdownTimer); _syCountdownTimer = null; }
  _syPending = { label, start, end, active, mode: 'create' };

  const TOTAL = 5;

  openModal('Confirm School Year — Review Period',
    '<div class="sy-confirm-header">' +
    '<div class="sy-confirm-icon"><i class="fa-solid fa-calendar-check"></i></div>' +
    '<div class="sy-confirm-label">S.Y. ' + escHTML(label) + '</div>' +
    '<div class="sy-confirm-dates">' + start + ' &nbsp;→&nbsp; ' + end + '</div>' +
    '<div class="sy-confirm-active-tag" style="background:var(--bg-overlay);color:var(--text-muted);border:1px solid var(--border)"><i class="fa-solid fa-toggle-off"></i> Will be saved as Inactive — activate manually when ready</div>' +
    '</div>' +
    '<div class="sy-countdown-disclaimer">' +
    '<i class="fa-solid fa-shield-halved" style="color:var(--warn);font-size:18px;flex-shrink:0"></i>' +
    '<div><strong style="display:block;margin-bottom:4px;color:var(--text-primary)">This school year will NOT be activated automatically</strong>' +
    'It will be stored as <strong>inactive</strong> and must be activated manually from the School Year list when you are ready to use it. Once confirmed, the label, start date, and end date will be <strong>permanently locked</strong> until <strong>' + end + '</strong> has passed.' +
    '<br/><br/>This 5-second window is your last chance to cancel and make changes.</div></div>' +
    '<div class="sy-countdown-ring-wrap">' +
    '<svg class="sy-countdown-svg" viewBox="0 0 80 80" xmlns="http://www.w3.org/2000/svg">' +
    '<circle class="sy-countdown-track" cx="40" cy="40" r="34"/>' +
    '<circle class="sy-countdown-fill" id="syCountdownCircle" cx="40" cy="40" r="34" stroke-dasharray="213.6" stroke-dashoffset="0"/>' +
    '</svg>' +
    '<div class="sy-countdown-number" id="syCountdownNum">' + TOTAL + '</div></div>' +
    '<div class="sy-countdown-label-text" id="syCountdownLabelText">seconds remaining to review</div>',

    '<button class="btn btn-ghost" onclick="cancelSYCountdown()">' +
    '<i class="fa-solid fa-xmark"></i> Cancel &amp; Go Back</button> ' +
    '<button class="btn btn-success" id="syConfirmBtn" disabled onclick="doConfirmSY()">' +
    '<i class="fa-solid fa-lock"></i> Confirm &amp; Lock School Year</button>'
  );

  _startSYCountdown();
}

function cancelSYCountdown() {
  if (_syCountdownTimer) { clearInterval(_syCountdownTimer); _syCountdownTimer = null; }
  const pending = _syPending;   // capture before clearing
  _syPending = null;
  closeModal();
  if (pending && pending.mode === 'edit') {
    // Reopen edit form with original values
    openEditSchoolYear(pending.id, pending.label, pending.start, pending.end, pending.active);
  } else {
    openAddSchoolYear();
  }
}

async function doConfirmSY() {
  if (_syCountdownTimer) { clearInterval(_syCountdownTimer); _syCountdownTimer = null; }
  const p = _syPending;
  if (!p) return;
  _syPending = null;

  if (p.mode === 'edit') {
    const res = await api('update_school_year', { id: p.id, label: p.label, start_date: p.start, end_date: p.end, is_confirmed: 1 });
    if (res.success) {
      toast('S.Y. ' + p.label + ' saved and locked until ' + p.end + '.', 'success');
      closeModal(); activateModule('school-years');
    } else toast(res.message, 'error');
  } else {
    const res = await api('create_school_year', { label: p.label, start_date: p.start, end_date: p.end, is_active: p.active, is_confirmed: 1 });
    if (res.success) {
      toast('S.Y. ' + p.label + ' created and locked until ' + p.end + '.', 'success');
      closeModal(); activateModule('school-years');
    } else toast(res.message, 'error');
  }
}

function openEditSchoolYear(id, label, start, end, active) {
  const currentYear = new Date().getFullYear();
  const minStart = `${currentYear}-01-01`;
  const maxEnd   = `${currentYear + 2}-12-31`;

  openModal('Edit School Year',
    `<div class="sy-label-preview-wrap">
       <div class="sy-label-preview-tag sy-label-preview-tag--set" id="syLabelPreview">
         <i class="fa-solid fa-calendar-days"></i>
         <span id="syLabelText">S.Y. ${label}</span>
       </div>
       <div class="sy-label-hint">Label is automatically generated from selected dates</div>
     </div>
     <input type="hidden" id="syLabel" value="${label}"/>
     <div class="form-grid">
       <div class="form-group">
         <label>Start Date</label>
         <input type="date" id="syStart" value="${start}" min="${minStart}" max="${maxEnd}" oninput="syncSYLabel()"/>
       </div>
       <div class="form-group">
         <label>End Date</label>
         <input type="date" id="syEnd" value="${end}" min="${minStart}" max="${maxEnd}" oninput="syncSYLabel()"/>
       </div>
     </div>
     <div class="sy-disclaimer-box">
       <i class="fa-solid fa-triangle-exclamation"></i>
       <div>
         <strong>Warning:</strong> Saving will trigger a <strong>5-second review countdown</strong>. After confirming, the label and dates will be <strong>permanently locked</strong> until the end date passes. The school year's activation status is <strong>not affected</strong> by editing — it must still be activated manually.
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-primary" onclick="submitEditSchoolYear(${id},${active})"><i class="fa-solid fa-floppy-disk"></i> Save &amp; Review</button>`);
}

async function submitEditSchoolYear(id, active) {
  const label = document.getElementById('syLabel').value.trim();
  const start = document.getElementById('syStart').value;
  const end   = document.getElementById('syEnd').value;
  const err = validateSYDates(label, start, end);
  if (err) return toast(err, 'warn');
  openSYEditCountdownConfirm(id, label, start, end, active || 0);
}

function openSYEditCountdownConfirm(id, label, start, end, active) {
  if (_syCountdownTimer) { clearInterval(_syCountdownTimer); _syCountdownTimer = null; }
  _syPending = { id, label, start, end, active, mode: 'edit' };

  const TOTAL = 5;

  openModal('Confirm School Year Changes — Review Period',
    '<div class="sy-confirm-header">' +
    '<div class="sy-confirm-icon"><i class="fa-solid fa-calendar-check"></i></div>' +
    '<div class="sy-confirm-label">S.Y. ' + escHTML(label) + '</div>' +
    '<div class="sy-confirm-dates">' + start + ' &nbsp;→&nbsp; ' + end + '</div></div>' +
    '<div class="sy-countdown-disclaimer">' +
    '<i class="fa-solid fa-shield-halved" style="color:var(--warn);font-size:18px;flex-shrink:0"></i>' +
    '<div><strong style="display:block;margin-bottom:4px;color:var(--text-primary)">Last chance to cancel</strong>' +
    'Once saved, the label and dates will be <strong>permanently locked</strong> until <strong>' + end + '</strong> has passed. The activation status of this school year is <strong>not changed</strong> — it must still be activated manually from the School Year list.</div></div>' +
    '<div class="sy-countdown-ring-wrap">' +
    '<svg class="sy-countdown-svg" viewBox="0 0 80 80" xmlns="http://www.w3.org/2000/svg">' +
    '<circle class="sy-countdown-track" cx="40" cy="40" r="34"/>' +
    '<circle class="sy-countdown-fill" id="syCountdownCircle" cx="40" cy="40" r="34" stroke-dasharray="213.6" stroke-dashoffset="0"/>' +
    '</svg>' +
    '<div class="sy-countdown-number" id="syCountdownNum">' + TOTAL + '</div></div>' +
    '<div class="sy-countdown-label-text" id="syCountdownLabelText">seconds remaining to review</div>',

    '<button class="btn btn-ghost" onclick="cancelSYCountdown()">' +
    '<i class="fa-solid fa-xmark"></i> Cancel &amp; Go Back</button> ' +
    '<button class="btn btn-primary" id="syConfirmBtn" disabled onclick="doConfirmSY()">' +
    '<i class="fa-solid fa-lock"></i> Save &amp; Lock School Year</button>'
  );

  _startSYCountdown();
}

async function setSYActive(id) {
  // Fetch all SYs fresh from server
  const allRes = await api('get_school_years');
  const allSYs = allRes.success ? allRes.data : [];
  const target = allSYs.find(r => r.id == id);
  if (!target) return toast('School year not found.', 'error');

  // ── Hard block: another SY is already active ──────────────
  const currentActive = allSYs.find(r => r.id != id && r.is_active == 1 && r.is_finalized != 1);
  if (currentActive) {
    // Find what's queued after the active SY
    const queuedAfterActive = allSYs
      .filter(r => r.id != currentActive.id && r.is_finalized != 1 && r.is_active != 1 && r.start_date > currentActive.end_date)
      .sort((a, b) => a.start_date.localeCompare(b.start_date))[0] || null;

    const queuedNote = queuedAfterActive
      ? `<div class="sy-active-blocked-next sy-active-blocked-next--set">
           <i class="fa-solid fa-forward-step"></i>
           <div><strong>S.Y. ${escHTML(queuedAfterActive.label)}</strong> is already queued and will
           be activated automatically when S.Y. ${escHTML(currentActive.label)} ends on
           <strong>${currentActive.end_date}</strong>.</div>
         </div>`
      : `<div class="sy-active-blocked-next sy-active-blocked-next--warn">
           <i class="fa-solid fa-triangle-exclamation"></i>
           <div>No next school year is currently queued. Once S.Y. ${escHTML(currentActive.label)}
           ends on <strong>${currentActive.end_date}</strong>, it will need a school year to
           auto-advance to. You can create one now — it will activate automatically.</div>
         </div>`;

    openModal('Cannot Activate — Active School Year Exists',
      `<div class="sy-blocked-modal">
         <div class="sy-blocked-icon"><i class="fa-solid fa-shield-halved"></i></div>

         <div class="sy-blocked-title">An Active School Year Has Been Found</div>

         <div class="sy-blocked-active-card">
           <div class="sy-blocked-active-label">
             <i class="fa-solid fa-toggle-on"></i>
             <strong>S.Y. ${escHTML(currentActive.label)}</strong>
             <span class="badge badge-active badge-dot" style="font-size:11px">Active</span>
           </div>
           <div class="sy-blocked-active-dates">${currentActive.start_date} &nbsp;→&nbsp; ${currentActive.end_date}</div>
         </div>

         <div class="sy-blocked-policy">
           <p>
             <strong>S.Y. ${escHTML(currentActive.label)}</strong> has been activated and
             <strong>cannot be manually deactivated</strong>. It will only deactivate once
             it has reached its set end date of <strong>${currentActive.end_date}</strong>
             and auto-advances to the next school year.
           </p>
           <p>
             No other school year can be activated while
             <strong>S.Y. ${escHTML(currentActive.label)}</strong> is running.
           </p>
         </div>

         ${queuedNote}

         <div class="sy-blocked-rule">
           <i class="fa-solid fa-lock"></i>
           Strict one-active-school-year policy is enforced. You may create upcoming school years
           at any time — they will queue and activate automatically when the current one ends.
         </div>
       </div>`,
      `<button class="btn btn-primary" onclick="closeModal()"><i class="fa-solid fa-circle-check"></i> Understood</button>`
    );
    return;
  }

  // ── No other active SY — proceed with normal activation confirmation ──
  // Next SY = earliest start_date after THIS target's end_date
  const nextSY = allSYs
    .filter(r => r.id != id && r.is_finalized != 1 && r.is_active != 1 && r.start_date > target.end_date)
    .sort((a, b) => a.start_date.localeCompare(b.start_date))[0] || null;

  const nextNote = nextSY
    ? `<div class="sy-activate-next-note sy-activate-next-note--set">
         <i class="fa-solid fa-forward-step"></i>
         <div><strong>Auto-advance queued:</strong> When S.Y. ${escHTML(target.label)} ends on
         <strong>${target.end_date}</strong>, the system will automatically activate
         <strong>S.Y. ${escHTML(nextSY.label)}</strong>.</div>
       </div>`
    : `<div class="sy-activate-next-note sy-activate-next-note--warn">
         <i class="fa-solid fa-triangle-exclamation"></i>
         <div><strong>No next school year queued.</strong> After S.Y. ${escHTML(target.label)} ends
         on <strong>${target.end_date}</strong>, there will be no school year to auto-advance to.
         You can create one at any time — it will queue automatically.</div>
       </div>`;

  openModal('Activate School Year — Final Confirmation',
    `<div class="sy-activate-disclaimer">
       <div class="sy-activate-header">
         <div class="sy-activate-icon"><i class="fa-solid fa-shield-halved"></i></div>
         <div class="sy-activate-label">S.Y. ${escHTML(target.label)}</div>
         <div class="sy-activate-dates">${target.start_date} &nbsp;→&nbsp; ${target.end_date}</div>
       </div>

       <div class="sy-activate-warning-block">
         <i class="fa-solid fa-lock" style="font-size:20px;color:var(--danger,#ef4444);flex-shrink:0;margin-top:2px"></i>
         <div>
           <strong style="display:block;margin-bottom:6px;color:var(--text-primary);font-size:14px">
             This action is permanent and cannot be undone.
           </strong>
           <ul class="sy-activate-rules">
             <li>Once activated, <strong>this school year cannot be deactivated manually</strong>.</li>
             <li>Only <strong>one school year</strong> can be active at a time.</li>
             <li>The school year status will change to <strong>Completed</strong> automatically
                 when its end date passes and the next one activates.</li>
             <li>If no next school year exists when the end date passes, the system will
                 stay on this one until you create one.</li>
           </ul>
         </div>
       </div>

       ${nextNote}

       <div class="sy-activate-confirm-row">
         <label class="sy-activate-checkbox-label">
           <input type="checkbox" id="syActivateAck"
             onchange="document.getElementById('syActivateBtn').disabled = !this.checked;"/>
           <span>I understand this is permanent and cannot be undone.</span>
         </label>
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-danger" id="syActivateBtn" disabled onclick="doActivateSY(${id})">
       <i class="fa-solid fa-toggle-on"></i> Activate School Year
     </button>`
  );
}

async function doActivateSY(id) {
  const res = await api('set_active_school_year', { id });
  if (res.success) {
    toast('School year activated. This cannot be undone.', 'success');
    closeModal();
    activateModule('school-years');
  } else {
    toast(res.message, 'error');
  }
}

function confirmFinalizeSY(id, label) {
  openModal('Finalize School Year',
    `<div style="color:var(--text-secondary);line-height:1.7">
       <div style="display:flex;align-items:center;gap:10px;margin-bottom:14px">
         <i class="fa-solid fa-triangle-exclamation" style="font-size:22px;color:var(--warn)"></i>
         <strong style="color:var(--text-primary)">This action is permanent and irreversible.</strong>
       </div>
       <p>You are about to finalize <strong>${escHTML(label)}</strong>.</p>
       <ul style="margin:10px 0 0 18px;line-height:2">
         <li>The school year will be <strong>permanently locked</strong>.</li>
         <li>No records (sections, subjects, curriculum) can be edited.</li>
         <li>The school year will be deactivated.</li>
         <li>A new school year may be created after finalization.</li>
       </ul>
       <div style="margin-top:16px;padding:10px 14px;background:var(--danger-bg,#fff0f0);border-radius:8px;font-size:12px;color:var(--danger)">
         <i class="fa-solid fa-lock" style="margin-right:6px"></i>
         Finalizing will permanently lock all records. This cannot be undone.
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-danger" onclick="doFinalizeSY(${id})"><i class="fa-solid fa-lock"></i> Finalize &amp; Lock</button>`);
}

async function doFinalizeSY(id) {
  const res = await api('finalize_school_year', { id });
  if (res.success) {
    toast('School year finalized and permanently locked.', 'success');
    closeModal();
    activateModule('school-years');
  } else {
    toast(res.message, 'error');
  }
}

/* ════════════════════════════════════════════════════════════
   SECTION MANAGEMENT
════════════════════════════════════════════════════════════ */
async function renderClassManagement(ca) {
  const [syRes, secRes] = await Promise.all([api('get_active_school_year'), api('get_sections_by_grade')]);
  const activeSY = syRes.success ? syRes.data : null;
  const grades   = secRes.success ? secRes.data : {};

  // Split sections into active and archived per grade
  const activeGrades   = {};
  const archivedAll    = []; // flat list of archived sections across all grades
  Object.entries(grades).forEach(([gradeId, g]) => {
    const activeSecs   = (g.sections || []).filter(s => s.status !== 'archived');
    const archivedSecs = (g.sections || []).filter(s => s.status === 'archived');
    activeGrades[gradeId] = { ...g, sections: activeSecs };
    archivedSecs.forEach(s => archivedAll.push({ ...s, grade_display: g.display_name, grade_level: g.level }));
  });

  // Update nav badge (active only)
  const totalActive = Object.values(activeGrades).reduce((s, g) => s + g.sections.length, 0);
  const badge = document.getElementById('badgeSections');
  if (badge) badge.textContent = totalActive || '0';

  const syBanner = activeSY
    ? `<div class="badge badge-active badge-dot" style="font-size:11px">Active: ${activeSY.label}</div>`
    : `<div class="badge badge-inactive">No Active School Year</div>`;

  const gradeBlocks = Object.entries(activeGrades).map(([gradeId, g]) => buildGradeCabinet(gradeId, g, activeSY)).join('');

  // Build archived sections panel
  const archivedPanel = buildArchivedSectionsPanel(archivedAll);

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Section Management</h1>
      <p>Create sections, assign advisers, and manage student rosters</p>
    </div>
    <div style="display:flex;align-items:center;gap:10px">
      ${syBanner}
      <button class="btn btn-primary" onclick="openAddSection()" ${!activeSY ? 'disabled title="No active school year"' : ''}>
        <i class="fa-solid fa-plus"></i> New Section
      </button>
    </div>
  </div>
  ${gradeBlocks || '<div class="panel"><div class="panel-body"><div class="empty-state"><i class="fa-solid fa-door-open"></i><p>No active sections found. Create a section to get started.</p></div></div></div>'}
  ${archivedPanel}`;

  // Attach cabinet toggles
  document.querySelectorAll('.cabinet-header').forEach(h => {
    h.addEventListener('click', () => {
      const body    = h.nextElementSibling;
      const chevron = h.querySelector('.cabinet-chevron');
      const open    = body.style.display !== 'none';
      body.style.display = open ? 'none' : 'block';
      chevron.classList.toggle('open', !open);
    });
  });
}

function buildGradeCabinet(gradeId, g, activeSY) {
  const sections = g.sections || [];
  const sectionCards = sections.map(s => {
    const pct  = s.capacity > 0 ? (s.enrolled_count / s.capacity) * 100 : 0;
    const cls  = pct >= 100 ? 'full' : pct >= 80 ? 'warn' : '';
    return `
    <div class="section-card" onclick="openSectionPanel(${s.id})">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px">
        <div class="section-card-name">${escHTML(s.name)}</div>
        <span class="badge badge-${s.status === 'active' ? 'open' : 'archived'}">${s.status}</span>
      </div>
      <div class="section-capacity-bar">
        <div class="section-capacity-fill ${cls}" style="width:${Math.min(pct,100)}%"></div>
      </div>
      <div class="section-stats">
        <span><span class="section-stat-val">${s.enrolled_count}</span>/${s.capacity} enrolled</span>
        <span class="ml-auto"><span class="section-stat-val">${s.capacity - s.enrolled_count}</span> slots</span>
      </div>
      <div style="margin-top:10px;font-size:11px;font-family:var(--font-mono);color:var(--text-muted)">
        <i class="fa-solid fa-user" style="margin-right:4px"></i><span class="section-card-adviser">${escHTML(s.adviser_name || 'No adviser')}</span>
      </div>
    </div>`;
  }).join('');

  const addCard = activeSY ? `<div class="add-section-card" onclick="openAddSection(${gradeId})"><i class="fa-solid fa-plus"></i> Add Section</div>` : '';

  return `
  <div class="grade-cabinet">
    <div class="cabinet-header">
      <span class="cabinet-grade-tag">GRADE ${g.level}</span>
      <span class="cabinet-title">${escHTML(g.display_name)}</span>
      <span class="cabinet-count">${sections.length} section${sections.length !== 1 ? 's' : ''}</span>
      <i class="fa-solid fa-chevron-right cabinet-chevron open"></i>
    </div>
    <div class="cabinet-body">
      <div class="sections-grid">
        ${sectionCards}
        ${addCard}
      </div>
    </div>
  </div>`;
}

/* ── Archived Sections Panel ───────────────────────────────── */
function buildArchivedSectionsPanel(archivedSections) {
  if (!archivedSections.length) return '';

  const rows = archivedSections.map(s => {
    const pct = s.capacity > 0 ? Math.round((s.enrolled_count / s.capacity) * 100) : 0;
    return `
    <tr>
      <td class="td-primary">${escHTML(s.name)}</td>
      <td><span style="font-size:12px;font-weight:600;color:var(--text-muted)">Grade ${escHTML(String(s.grade_level))}</span></td>
      <td class="td-mono">${s.enrolled_count}/${s.capacity}</td>
      <td><span class="badge badge-archived">Archived</span></td>
      <td>
        <div style="display:flex;gap:6px;align-items:center">
          <button class="btn-icon btn-icon-success" title="Restore section" onclick="confirmUnarchiveSection(${s.id},'${escHTML(s.name)}')"><i class="fa-solid fa-rotate-left"></i> Restore</button>
          <button class="btn-icon btn-icon-danger" title="Permanently delete section" onclick="confirmDeleteSection(${s.id},'${escHTML(s.name)}')"><i class="fa-solid fa-trash"></i> Delete</button>
        </div>
      </td>
    </tr>`;
  }).join('');

  return `
  <div class="grade-cabinet" style="margin-top:8px;border:1.5px dashed var(--border);opacity:0.92">
    <div class="cabinet-header" id="archivedCabinetHdr" style="background:var(--surface-alt)">
      <span class="cabinet-grade-tag" style="background:var(--text-muted);color:#fff">ARCHIVED</span>
      <span class="cabinet-title" style="color:var(--text-muted)">Archived Sections</span>
      <span class="cabinet-count">${archivedSections.length} section${archivedSections.length !== 1 ? 's' : ''}</span>
      <i class="fa-solid fa-chevron-right cabinet-chevron"></i>
    </div>
    <div class="cabinet-body" style="display:none">
      <div class="table-wrap" style="margin:0">
        <table>
          <thead><tr><th>Section Name</th><th>Grade</th><th>Students / Cap</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
      </div>
    </div>
  </div>`;
}

function confirmUnarchiveSection(id, name) {
  openModal('Restore Section',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-success"><i class="fa-solid fa-rotate-left"></i></div>
       <p>Restore <strong>${escHTML(name)}</strong> to active?</p>
       <p class="confirm-sub">The section will become active again. Students will need to be re-assigned.</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-success" onclick="doUnarchiveSection(${id})"><i class="fa-solid fa-rotate-left"></i> Restore Section</button>`
  );
}

function confirmDeleteSection(id, name) {
  openModal('Delete Section',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-danger"><i class="fa-solid fa-trash"></i></div>
       <p>Delete <strong>${escHTML(name)}</strong>?</p>
       <p class="confirm-sub">This action cannot be undone. The section and all its records will be permanently removed.</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-danger" id="confirmDeleteSectionBtn" onclick="doDeleteSection(${id})"><i class="fa-solid fa-trash"></i> Delete</button>`
  );
}

async function doDeleteSection(id) {
  const btn = document.getElementById('confirmDeleteSectionBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Deleting…'; }
  const res = await api('delete_section', { id });
  if (res.success) {
    toast(res.message || 'Section permanently deleted.', 'success');
    closeModal();
    activateModule('class-management');
  } else {
    toast(res.message || 'Failed to delete section.', 'error');
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-trash"></i> Delete'; }
  }
}

/* ── Create Section Modal ──────────────────────────────────── */
async function openAddSection(preGradeId = null) {
  const [glRes, syRes, advRes] = await Promise.all([
    api('get_grade_levels'), api('get_active_school_year'), api('get_available_teachers', { current_section_id: 0 })
  ]);
  const grades    = glRes.success ? glRes.data : [];
  const activeSY  = syRes.success ? syRes.data : null;
  const advisers  = advRes.success ? (advRes.data.teachers || []) : [];

  if (!activeSY) return toast('No active school year. Please set one first.', 'warn');

  const gradeOpts = grades.map(g =>
    `<option value="${g.id}" ${g.id == preGradeId ? 'selected' : ''}>${g.display_name}</option>`).join('');
  const advOpts = `<option value="">— Assign Later —</option>` +
    advisers.map(a => `<option value="${a.id}">${escHTML(a.full_name)}</option>`).join('');

  openModal('New Section',
    `<div class="sm-step-indicator">
       <span class="sm-step active"><i class="fa-solid fa-circle-1"></i> Details</span>
       <span class="sm-step-divider"></span>
       <span class="sm-step"><i class="fa-solid fa-circle-2"></i> Adviser</span>
       <span class="sm-step-divider"></span>
       <span class="sm-step"><i class="fa-solid fa-circle-3"></i> Students</span>
     </div>
     <div class="form-group"><label>Grade Level</label><select id="secGrade">${gradeOpts}</select></div>
     <div class="form-group">
       <label>Section Name</label>
       <input type="text" id="secName" placeholder="e.g. Apollo Sampaguita Narra" oninput="sanitizePlainText(this)" autocomplete="off"/>
     </div>
     <div class="form-group">
       <label>Section Capacity</label>
       <div class="sm-capacity-wrap">
         <input type="number" id="secCap" value="25" min="25" max="40" oninput="updateCapacityPreview()"/>
         <span class="sm-capacity-hint" id="capHint">25 students (min 25 · max 40)</span>
       </div>
     </div>
     <div class="form-group">
       <label>Adviser <span style="color:var(--text-muted);font-weight:400">(optional — can assign later)</span></label>
       <select id="secAdviser">${advOpts}</select>
     </div>
`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-success" id="createSectionBtn" onclick="submitAddSection(${activeSY.id})"><i class="fa-solid fa-plus"></i> Create Section</button>`,
    false
  );
}

function updateCapacityPreview() {
  const val  = parseInt(document.getElementById('secCap')?.value) || 0;
  const hint = document.getElementById('capHint');
  if (!hint) return;
  if (val < 25)      hint.textContent = `Minimum is 25 students`;
  else if (val > 40) hint.textContent = `Maximum is 40 students`;
  else               hint.textContent = `${val} student${val !== 1 ? 's' : ''} (min 25 · max 40)`;
}

let _creatingSection = false;

async function submitAddSection(syId) {
  if (_creatingSection) return; // prevent double-submit
  const grade_level_id = document.getElementById('secGrade').value;
  const name           = document.getElementById('secName').value.trim();
  const capacity       = document.getElementById('secCap').value;
  const adviser_id     = document.getElementById('secAdviser').value;
  if (!name)     return toast('Section name is required.', 'warn');
  const capNum = parseInt(capacity);
  if (!capacity || capNum < 25) return toast('Section capacity must be at least 25 students.', 'warn');
  if (capNum > 40)              return toast('Section capacity cannot exceed 40 students.', 'warn');

  // Disable button immediately to block double-clicks
  _creatingSection = true;
  const btn = document.getElementById('createSectionBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Creating…'; }

  const res = await api('create_section', { grade_level_id, name, capacity, adviser_id, school_year_id: syId });
  _creatingSection = false;
  if (res.success) {
    toast(`Section "${name}" created successfully.`, 'success');
    closeModal();
    activateModule('class-management');
  } else {
    toast(res.message, 'error');
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-plus"></i> Create Section'; }
  }
}

/* ── Section Detail Panel (full modal with tabs) ──────────── */
async function openSectionPanel(id) {
  // Load all data in parallel; get_available_teachers excludes advisers assigned elsewhere
  const [sdRes, advRes, studRes] = await Promise.all([
    api('get_section_detail', { id }),
    api('get_available_teachers', { current_section_id: id }),
    api('get_section_students', { section_id: id }),
  ]);
  const sd       = sdRes.success ? sdRes.data : {};
  const advisers = advRes.success ? (advRes.data.teachers || []) : [];
  const students = studRes.success ? studRes.data : [];

  const name     = sd.name || '—';
  const status   = sd.status || 'active';
  const capacity = sd.capacity || 40;
  // Use actual fetched student roster as source of truth — keeps bar & counts in sync
  const enrolled = students.length > 0 ? students.length : (sd.enrolled_count || 0);
  const pct      = capacity > 0 ? Math.round((enrolled / capacity) * 100) : 0;
  const barCls   = pct >= 100 ? 'full' : pct >= 80 ? 'warn' : '';

  const advOpts = `<option value="">— None —</option>` +
    advisers.map(a => `<option value="${a.id}" ${a.id == sd.adviser_id ? 'selected' : ''}>${escHTML(a.full_name)}</option>`).join('');

  const studentRows = students.length
    ? students.map(s => `
      <tr class="sm-enrolled-row" data-sid="${s.student_id}" data-name="${escHTML((s.last_name + ' ' + s.first_name).toLowerCase())}">
        <td style="width:32px">
          <input type="checkbox" class="sm-rem-check" value="${s.student_id}" onchange="updateRemoveCount()"/>
        </td>
        <td class="td-primary">${escHTML(s.last_name)}, ${escHTML(s.first_name)} ${s.middle_name ? escHTML(s.middle_name[0]) + '.' : ''}</td>
        <td class="td-mono">${escHTML(s.lrn || '—')}</td>
        <td><span class="badge badge-active badge-dot">Enrolled</span></td>
      </tr>`).join('')
    : `<tr><td colspan="4"><div class="empty-state" style="padding:24px"><i class="fa-solid fa-users"></i><p>No students assigned to this section yet.</p></div></td></tr>`;

  openModal(`Section: ${escHTML(name)}`,
    `<div class="sm-panel-hero">
       <div class="sm-panel-name">${escHTML(name)}</div>
       <span class="badge badge-${status === 'active' ? 'open' : 'archived'} sm-status-badge">${status}</span>
     </div>
     <div class="sm-capacity-overview">
       <div class="sm-cap-stat"><span class="sm-cap-num">${enrolled}</span><span class="sm-cap-lbl">Enrolled</span></div>
       <div class="sm-cap-divider"></div>
       <div class="sm-cap-stat"><span class="sm-cap-num">${capacity}</span><span class="sm-cap-lbl">Capacity</span></div>
       <div class="sm-cap-divider"></div>
       <div class="sm-cap-stat"><span class="sm-cap-num ${capacity - enrolled <= 3 ? 'sm-cap-warn' : ''}">${capacity - enrolled}</span><span class="sm-cap-lbl">Slots Left</span></div>
       <div class="sm-cap-divider"></div>
       <div class="sm-cap-stat"><span class="sm-cap-num">${pct}%</span><span class="sm-cap-lbl">Full</span></div>
     </div>
     <div class="section-capacity-bar" style="margin-bottom:16px;height:6px">
       <div class="section-capacity-fill ${barCls}" style="width:${Math.min(pct,100)}%"></div>
     </div>

     <!-- TABS -->
     <div class="sm-tabs">
       <button class="sm-tab active" onclick="switchSMTab(this,'sm-tab-details')"><i class="fa-solid fa-circle-info"></i> Details</button>
       <button class="sm-tab" onclick="switchSMTab(this,'sm-tab-adviser')"><i class="fa-solid fa-chalkboard-teacher"></i> Adviser</button>
       <button class="sm-tab" onclick="switchSMTab(this,'sm-tab-students')"><i class="fa-solid fa-users"></i> Students <span class="sm-tab-count">${enrolled}</span></button>
     </div>

     <!-- TAB: DETAILS -->
     <div id="sm-tab-details" class="sm-tab-panel">
       <div class="form-group"><label>Section Name</label><input type="text" id="eSName" value="${escHTML(name)}"/></div>
       <div class="form-group">
         <label>Capacity</label>
         <input type="number" id="eSCap" value="${capacity}" min="${enrolled}" max="100"
           title="Cannot be set below current enrolled count (${enrolled})"/>
         ${enrolled > 0 ? `<div style="font-size:10px;color:var(--text-muted);margin-top:4px"><i class="fa-solid fa-info-circle"></i> Min capacity is ${enrolled} (currently enrolled)</div>` : ''}
       </div>

       <!-- DANGER ZONE -->
       <div class="sm-danger-zone">
         <div class="sm-danger-zone-header" onclick="toggleDangerZone(this)">
           <span><i class="fa-solid fa-triangle-exclamation"></i> Archive Section</span>
           <i class="fa-solid fa-chevron-down sm-danger-chevron"></i>
         </div>
         <div class="sm-danger-zone-body" style="display:none">
           <div class="sm-danger-desc">
             <strong>Archive this section</strong>
             <span>Archiving will hide this section from active lists. Students and advisers will be unlinked. This can be reversed.</span>
           </div>
           <button class="btn btn-danger btn-sm sm-danger-archive-btn"
             onclick="confirmArchiveSectionWithStudents(${id},'${escHTML(name)}',${enrolled},'${escHTML(sd.room || '')}','${escHTML((sd.adviser_name || '').trim())}')">
             <i class="fa-solid fa-box-archive"></i> Archive Section
           </button>
         </div>
       </div>
     </div>

     <!-- TAB: ADVISER -->
     <div id="sm-tab-adviser" class="sm-tab-panel" style="display:none">
       <div class="sm-adviser-info">
         <i class="fa-solid fa-chalkboard-teacher sm-adviser-icon"></i>
         <div>
           <div style="font-size:13px;font-weight:600;color:var(--text-primary)">Section Adviser</div>
           <div style="font-size:11px;color:var(--text-muted);margin-top:2px">The adviser is the homeroom teacher responsible for this section</div>
         </div>
       </div>
       <div class="form-group" style="margin-top:14px">
         <label>Assign Adviser</label>
         <select id="eSAdv">${advOpts}</select>
       </div>
     </div>

     <!-- TAB: STUDENTS -->
     <div id="sm-tab-students" class="sm-tab-panel" style="display:none">
       <div class="sm-students-toolbar">
         <div class="search-wrap" style="flex:1">
           <i class="fa-solid fa-search"></i>
           <input type="text" placeholder="Search students in this section…" oninput="filterSMStudents(this.value)"/>
         </div>
         <button class="btn btn-primary btn-sm" onclick="openAddStudentsToSection(${id},${capacity},${enrolled})">
           <i class="fa-solid fa-user-plus"></i> Add Students
         </button>
       </div>
       ${students.length ? `
       <div class="sm-select-all-bar" style="margin-top:10px">
         <label style="display:flex;align-items:center;gap:8px;cursor:pointer;font-size:12px">
           <input type="checkbox" id="smRemSelectAll" onchange="toggleAllRemove(this.checked)"/> Select all visible
         </label>
         <div style="display:flex;align-items:center;gap:8px">
           <span class="sm-selected-count" id="smRemoveCount">0 selected</span>
           <button class="btn btn-sm sm-batch-remove-btn" id="smBatchRemoveBtn" onclick="submitBatchRemoveStudents(${id})" disabled>
             <i class="fa-solid fa-user-minus"></i> Remove Selected
           </button>
         </div>
       </div>` : ''}
       <div class="table-wrap" style="margin-top:8px">
         <table id="smStudentsTable">
           <thead><tr><th style="width:32px"></th><th>Name</th><th>LRN</th><th>Status</th></tr></thead>
           <tbody id="smStudentsTbody">${studentRows}</tbody>
         </table>
       </div>
     </div>`,

    `<button class="btn btn-ghost" onclick="closeModal()">Close</button>
     <button class="btn btn-primary" id="smFooterSaveDetails" onclick="submitEditSection(${id})"><i class="fa-solid fa-floppy-disk"></i> Save Details</button>
     <button class="btn btn-primary" id="smFooterSaveAdviser" style="display:none" onclick="submitAdviserOnly(${id})"><i class="fa-solid fa-floppy-disk"></i> Save Adviser</button>`,
    true
  );

  // No individual remove buttons — batch remove handled via checkboxes
  setTimeout(() => {
    // keep smStudentsTbody click handler only for row-level checkbox toggling
    document.getElementById('smStudentsTbody')?.addEventListener('click', e => {
      const row = e.target.closest('.sm-enrolled-row');
      if (!row || e.target.type === 'checkbox') return;
      const cb = row.querySelector('.sm-rem-check');
      if (cb) { cb.checked = !cb.checked; updateRemoveCount(); }
    });
  }, 50);
}

function switchSMTab(btn, tabId) {
  document.querySelectorAll('.sm-tab').forEach(t => t.classList.remove('active'));
  btn.classList.add('active');
  document.querySelectorAll('.sm-tab-panel').forEach(p => p.style.display = 'none');
  const panel = document.getElementById(tabId);
  if (panel) panel.style.display = 'block';

  // Swap footer save buttons based on active tab
  const saveDetails = document.getElementById('smFooterSaveDetails');
  const saveAdviser = document.getElementById('smFooterSaveAdviser');
  if (saveDetails) saveDetails.style.display = tabId === 'sm-tab-details'  ? '' : 'none';
  if (saveAdviser) saveAdviser.style.display  = tabId === 'sm-tab-adviser' ? '' : 'none';
}

function toggleDangerZone(header) {
  const body    = header.nextElementSibling;
  const chevron = header.querySelector('.sm-danger-chevron');
  const open    = body.style.display !== 'none';
  body.style.display = open ? 'none' : 'flex';
  if (chevron) chevron.style.transform = open ? '' : 'rotate(180deg)';
}

function filterSMStudents(q) {
  const lower = q.toLowerCase();
  document.querySelectorAll('#smStudentsTbody .sm-enrolled-row').forEach(r => {
    const match = !q || r.dataset.name.includes(lower) || r.textContent.toLowerCase().includes(lower);
    r.style.display = match ? '' : 'none';
  });
  updateRemoveCount();
}

function toggleAllRemove(checked) {
  document.querySelectorAll('#smStudentsTbody .sm-enrolled-row:not([style*="display: none"]) .sm-rem-check')
    .forEach(cb => { cb.checked = checked; });
  updateRemoveCount();
}

function updateRemoveCount() {
  const checked = document.querySelectorAll('#smStudentsTbody .sm-rem-check:checked').length;
  const countEl = document.getElementById('smRemoveCount');
  const btn     = document.getElementById('smBatchRemoveBtn');
  if (countEl) countEl.textContent = `${checked} selected`;
  if (btn) {
    btn.disabled = checked === 0;
    btn.classList.toggle('btn-danger',  checked > 0);
    btn.classList.toggle('btn-ghost',   checked === 0);
  }
  // Sync select-all checkbox state
  const all     = document.querySelectorAll('#smStudentsTbody .sm-enrolled-row:not([style*="display: none"]) .sm-rem-check').length;
  const selAll  = document.getElementById('smRemSelectAll');
  if (selAll) selAll.indeterminate = checked > 0 && checked < all;
  if (selAll) selAll.checked = all > 0 && checked === all;
}

// Holds student IDs selected for batch removal — captured before confirm modal wipes DOM
let _pendingRemoveIds = [];

async function submitBatchRemoveStudents(sectionId) {
  const checked = [...document.querySelectorAll('#smStudentsTbody .sm-rem-check:checked')];
  if (!checked.length) return;

  // Capture IDs NOW — openModal() will destroy #smStudentsTbody
  _pendingRemoveIds = checked.map(cb => cb.value);

  const count  = _pendingRemoveIds.length;
  const plural = count !== 1 ? 's' : '';

  openModal('Remove Students',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-user-minus"></i></div>
       <p>Remove <strong>${count} student${plural}</strong> from this section?</p>
       <p class="confirm-sub">Their section assignment will be cleared and they can be re-assigned to another section.</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal();openSectionPanel(${sectionId})">Cancel</button>
     <button class="btn btn-danger" onclick="confirmBatchRemove(${sectionId})">
       <i class="fa-solid fa-user-minus"></i> Remove ${count} Student${plural}
     </button>`,
    true
  );
}

async function confirmBatchRemove(sectionId) {
  // Use the IDs captured before the confirm modal opened
  if (!_pendingRemoveIds.length) {
    toast('No students selected.', 'warn');
    return;
  }
  const studentIds = _pendingRemoveIds.join(',');
  const count      = _pendingRemoveIds.length;
  _pendingRemoveIds = []; // clear immediately to prevent double-submit

  const res = await api('batch_remove_students_from_section', { section_id: sectionId, student_ids: studentIds });
  if (res.success) {
    toast(`${count} student${count !== 1 ? 's' : ''} removed from section.`, 'success');
    closeModal();
    await refreshSectionCard(sectionId);
    openSectionPanel(sectionId);
  } else toast(res.message, 'error');
}

/* ── Edit section details (from panel Details tab) ─────────── */
async function submitEditSection(id) {
  const name       = document.getElementById('eSName').value.trim();
  const capacity   = document.getElementById('eSCap').value;
  const adviser_id = document.getElementById('eSAdv')?.value || '';
  if (!name) return toast('Section name is required.', 'warn');
  const res = await api('update_section', { id, name, capacity, adviser_id });
  if (res.success) { toast('Section updated.', 'success'); closeModal(); activateModule('class-management'); }
  else toast(res.message, 'error');
}

/* ── Save adviser only (from Adviser tab) ─────────────────── */
async function submitAdviserOnly(id) {
  const name       = document.getElementById('eSName')?.value.trim() || '';
  const capacity   = document.getElementById('eSCap')?.value || '40';
  const adviser_id = document.getElementById('eSAdv').value;
  const res = await api('update_section', { id, name, capacity, adviser_id });
  if (res.success) {
    toast('Adviser updated.', 'success');
    // Refresh the background grid card so the adviser name updates immediately
    await refreshSectionCard(id);
    closeModal();
    openSectionPanel(id);
  } else toast(res.message, 'error');
}

/* ── Add students to section ──────────────────────────────── */
async function openAddStudentsToSection(sectionId, capacity, enrolled) {
  const slotsLeft = capacity - enrolled;
  if (slotsLeft <= 0) return toast('This section is at full capacity.', 'warn');

  // Get students who are registered (enrolled/docs_submitted) but NOT yet in this section
  const res = await api('get_available_students_for_section', { section_id: sectionId });
  const available = res.success ? res.data : [];

  const rows = available.length
    ? available.map(s => `
      <tr class="sm-student-row" data-sid="${s.id}">
        <td><input type="checkbox" class="sm-stu-check" value="${s.id}" onchange="updateAddStudentCount()"/></td>
        <td class="td-primary">${escHTML(s.last_name)}, ${escHTML(s.first_name)} ${s.middle_name ? escHTML(s.middle_name[0]) + '.' : ''}</td>
        <td class="td-mono" style="font-size:11px">${escHTML(s.lrn || '—')}</td>
        <td><span class="badge badge-active badge-dot" style="font-size:10px">Enrolled</span></td>
      </tr>`).join('')
    : `<tr><td colspan="4"><div class="empty-state" style="padding:24px"><i class="fa-solid fa-user-check"></i><p>No enrolled students available to assign for this grade level.</p><p style="font-size:10px;margin-top:4px">Only fully enrolled students can be added to a section. Students with pending or registered status must be approved by the registrar first.</p></div></td></tr>`;

  openModal('Add Students to Section',
    `<div class="sm-add-students-header">
       <div class="sm-slots-badge"><i class="fa-solid fa-door-open"></i> ${slotsLeft} slot${slotsLeft !== 1 ? 's' : ''} available</div>
       <div style="font-size:12px;color:var(--text-muted)">Select students matching this section's grade level to assign.</div>
     </div>
     <div class="search-wrap" style="margin-bottom:10px">
       <i class="fa-solid fa-search"></i>
       <input type="text" placeholder="Search students…" oninput="filterAddStudentTable(this.value)"/>
     </div>
     <div class="sm-select-all-bar">
       <label style="display:flex;align-items:center;gap:8px;cursor:pointer;font-size:12px">
         <input type="checkbox" id="smSelectAll" onchange="toggleAllStudents(this.checked, ${slotsLeft})"/> Select ${slotsLeft} student${slotsLeft !== 1 ? 's' : ''}
       </label>
       <span class="sm-selected-count" id="smSelectedCount">0 selected</span>
     </div>
     <div class="table-wrap" style="max-height:280px;overflow-y:auto">
       <table id="smAddTable">
         <thead><tr><th style="width:30px"></th><th>Name</th><th>LRN</th><th>Status</th></tr></thead>
         <tbody id="smAddTbody">${rows}</tbody>
       </table>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal();openSectionPanel(${sectionId})">Cancel</button>
     <button class="btn btn-success" onclick="submitAddStudentsToSection(${sectionId},${slotsLeft})"><i class="fa-solid fa-user-plus"></i> Add Selected Students</button>`,
    true
  );
}

function filterAddStudentTable(q) {
  document.querySelectorAll('#smAddTbody tr.sm-student-row').forEach(r => {
    r.style.display = r.textContent.toLowerCase().includes(q.toLowerCase()) ? '' : 'none';
  });
  updateAddStudentCount();
}

function toggleAllStudents(checked, slotsLeft) {
  const visible = [...document.querySelectorAll('#smAddTbody tr.sm-student-row:not([style*="display: none"]) .sm-stu-check')];
  if (!checked) {
    visible.forEach(cb => cb.checked = false);
  } else {
    // Only check up to slotsLeft checkboxes
    visible.forEach((cb, i) => { cb.checked = i < slotsLeft; });
    if (visible.length > slotsLeft) {
      toast(`Only ${slotsLeft} slot${slotsLeft !== 1 ? 's' : ''} available — first ${slotsLeft} student${slotsLeft !== 1 ? 's' : ''} selected.`, 'warn');
    }
  }
  updateAddStudentCount();
}

function updateAddStudentCount() {
  const count = document.querySelectorAll('#smAddTbody .sm-stu-check:checked').length;
  const el = document.getElementById('smSelectedCount');
  if (el) el.textContent = `${count} selected`;
}

/* ── Refresh a single section card in the background without full re-render ── */
async function refreshSectionCard(sectionId) {
  const [sdRes, studRes] = await Promise.all([
    api('get_section_detail', { id: sectionId }),
    api('get_section_students', { section_id: sectionId }),
  ]);
  if (!sdRes.success) return;
  const sd       = sdRes.data;
  const students = studRes.success ? studRes.data : [];
  const capacity = sd.capacity || 40;
  const enrolled = students.length > 0 ? students.length : (sd.enrolled_count || 0);
  const pct      = capacity > 0 ? Math.round((enrolled / capacity) * 100) : 0;
  const barCls   = pct >= 100 ? 'full' : pct >= 80 ? 'warn' : '';

  // Find the card in the background DOM by its onclick attribute
  const card = document.querySelector(`.section-card[onclick="openSectionPanel(${sectionId})"]`);
  if (!card) return;

  // Update progress bar
  const fill = card.querySelector('.section-capacity-fill');
  if (fill) {
    fill.style.width = Math.min(pct, 100) + '%';
    fill.className = 'section-capacity-fill' + (barCls ? ' ' + barCls : '');
  }

  // Update enrolled / slots text
  const statVals = card.querySelectorAll('.section-stat-val');
  if (statVals[0]) statVals[0].textContent = enrolled;
  if (statVals[1]) statVals[1].textContent = capacity - enrolled;

  // Update adviser name displayed at the bottom of the card
  const adviserEl = card.querySelector('.section-card-adviser');
  if (adviserEl) adviserEl.textContent = sd.adviser_name || 'No adviser';
}

async function submitAddStudentsToSection(sectionId, slotsLeft) {
  const checked = [...document.querySelectorAll('#smAddTbody .sm-stu-check:checked')];
  if (!checked.length) return toast('Please select at least one student.', 'warn');
  if (checked.length > slotsLeft) return toast(`Only ${slotsLeft} slot${slotsLeft !== 1 ? 's' : ''} available. Please deselect some students.`, 'warn');
  const studentIds = checked.map(cb => cb.value).join(',');
  const res = await api('assign_students_to_section', { section_id: sectionId, student_ids: studentIds });
  if (res.success) {
    toast(`${checked.length} student${checked.length !== 1 ? 's' : ''} added to section.`, 'success');
    closeModal();
    await refreshSectionCard(sectionId);
    openSectionPanel(sectionId);
  } else toast(res.message, 'error');
}

/* ── Legacy openSectionDetail (kept for backward compat) ─────── */
function openSectionDetail(id, name, status, capacity, enrolled, adviser, room) {
  openSectionPanel(id);
}

/* ── Archive Section (smart: room-aware + student/adviser-aware modals) ── */
function confirmArchiveSectionWithStudents(id, name, enrolled, room, adviserName) {
  const hasRoom    = !!(room && room.trim());
  const hasAdviser = !!(adviserName && adviserName.trim());
  const hasStudents = enrolled > 0;

  // ── CASE 1: Has room AND (students or adviser) ──────────────────────────
  // Full "everything will be affected" warning
  if (hasRoom && (hasStudents || hasAdviser)) {
    const detailLines = [];
    if (hasStudents) detailLines.push(`<li><i class="fa-solid fa-users" style="width:14px;color:var(--warn,#f59e0b)"></i> <strong>${enrolled}</strong> assigned student${enrolled !== 1 ? 's' : ''}</li>`);
    if (hasAdviser)  detailLines.push(`<li><i class="fa-solid fa-chalkboard-teacher" style="width:14px;color:var(--warn,#f59e0b)"></i> Advisory teacher: <strong>${escHTML(adviserName)}</strong></li>`);
    if (hasRoom)     detailLines.push(`<li><i class="fa-solid fa-building" style="width:14px;color:var(--warn,#f59e0b)"></i> Assigned to <strong>Room ${escHTML(room)}</strong></li>`);

    openModal('Archive Section',
      `<div class="confirm-body">
         <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
         <p>Archive <strong>${escHTML(name)}</strong>?</p>
         <div style="margin-top:14px;padding:14px 16px;background:var(--warn-bg,#fff8e1);border:1px solid var(--warn,#f59e0b);border-radius:10px;font-size:13px;color:var(--warn-text,#92400e);line-height:1.9">
           <div style="font-weight:600;margin-bottom:8px"><i class="fa-solid fa-triangle-exclamation" style="margin-right:6px;color:var(--warn,#f59e0b)"></i>This section currently has:</div>
           <ul style="margin:0;padding:0 0 0 4px;list-style:none;display:flex;flex-direction:column;gap:5px">
             ${detailLines.join('')}
           </ul>
           <div style="margin-top:12px;border-top:1px solid rgba(245,158,11,0.25);padding-top:10px;font-size:12px">
             Archiving will <strong>remove this section from Room ${escHTML(room)}</strong> and it will <strong>no longer appear</strong> for students and teachers. Continue?
           </div>
         </div>
         <p class="confirm-sub" style="margin-top:10px;font-size:11px">The section can be unarchived at any time from the Archived Sections panel.</p>
       </div>`,
      `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
       <button class="btn btn-warning" onclick="doArchiveSectionConfirmed(${id})"><i class="fa-solid fa-box-archive"></i> Yes, Archive Section</button>`
    );
    return;
  }

  // ── CASE 2: Has room only (no students, no adviser) ─────────────────────
  // Simpler room-removal notice
  if (hasRoom) {
    openModal('Archive Section',
      `<div class="confirm-body">
         <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
         <p>Archive <strong>${escHTML(name)}</strong>?</p>
         <div style="margin-top:14px;padding:14px 16px;background:var(--warn-bg,#fff8e1);border:1px solid var(--warn,#f59e0b);border-radius:10px;font-size:13px;color:var(--warn-text,#92400e);line-height:1.7">
           <i class="fa-solid fa-building" style="margin-right:6px;color:var(--warn,#f59e0b)"></i>
           <strong>${escHTML(name)}</strong> is currently assigned to <strong>Room ${escHTML(room)}</strong>. Archiving this section will remove it from the assigned room.
         </div>
         <p class="confirm-sub" style="margin-top:10px;font-size:11px">The section can be unarchived at any time from the Archived Sections panel.</p>
       </div>`,
      `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
       <button class="btn btn-warning" onclick="doArchiveSectionConfirmed(${id})"><i class="fa-solid fa-box-archive"></i> Yes, Archive Section</button>`
    );
    return;
  }

  // ── CASE 3: No room — original behaviour ────────────────────────────────
  if (hasStudents) {
    openModal('Archive Section',
      `<div class="confirm-body">
         <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
         <p>Archive <strong>${escHTML(name)}</strong>?</p>
         <div style="margin-top:14px;padding:14px 16px;background:var(--warn-bg,#fff8e1);border:1px solid var(--warn,#f59e0b);border-radius:10px;font-size:13px;color:var(--warn-text,#92400e);line-height:1.7">
           <i class="fa-solid fa-triangle-exclamation" style="margin-right:6px;color:var(--warn,#f59e0b)"></i>
           Archiving this section will remove the <strong>${enrolled} student${enrolled !== 1 ? 's' : ''}</strong> assigned to it. Do you wish to continue?
         </div>
         <p class="confirm-sub" style="margin-top:10px;font-size:11px">The section can be unarchived at any time from the Archived Sections panel.</p>
       </div>`,
      `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
       <button class="btn btn-warning" onclick="doArchiveSectionConfirmed(${id})"><i class="fa-solid fa-box-archive"></i> Yes, Archive Section</button>`
    );
    return;
  }

  // No room, no students, no adviser — archive silently
  doArchiveSectionConfirmed(id);
}

async function doArchiveSectionConfirmed(id) {
  const res = await api('archive_section', { id });
  if (res.success) {
    toast('Section archived.', 'success');
    closeModal();
    activateModule('class-management');
  } else toast(res.message, 'error');
}

async function doUnarchiveSection(id) {
  const res = await api('activate_section', { id });
  if (res.success) {
    toast('Section restored to active.', 'success');
    activateModule('class-management');
  } else toast(res.message, 'error');
}

/* ════════════════════════════════════════════════════════════
   SUBJECTS  —  persistent filter + pagination state
════════════════════════════════════════════════════════════ */

/* Module-level state — survives re-renders (create/edit/archive) */
let _subjFilterMode  = 'active'; // 'active' | 'archived' | 'all'
let _subjGradeFilter = '';       // '' | 'Grade 7' | 'Grade 8' | 'Grade 9' | 'Grade 10'
let _subjSearch      = '';       // free-text search string
let _subjPage        = 1;        // current pagination page
const SUBJ_PER_PAGE  = 10;
let _subjTab         = 'list';   // 'list' | 'curriculum'

/* All rows fetched from the server (unfiltered master copy) */
let _subjAllRows     = [];
let _subjIsLocked    = false;

async function renderSubjects(ca, filterMode = null) {
  // Only override state when explicitly navigating (first load or filter dropdown change)
  if (filterMode !== null) {
    _subjFilterMode = filterMode;
    _subjPage       = 1; // reset page when switching filter mode
  }

  // If curriculum tab is active, delegate to the curriculum renderer
  if (_subjTab === 'curriculum') {
    return renderSubjectsWithCurriculumTab(ca);
  }

  const includeArchived = (_subjFilterMode === 'all' || _subjFilterMode === 'archived') ? '1' : '0';
  const [subRes, syRes] = await Promise.all([
    api('get_subjects', { include_archived: includeArchived }),
    api('get_active_school_year'),
  ]);

  _subjAllRows = subRes.success ? subRes.data : [];
  const activeSY  = syRes.success ? syRes.data : null;
  _subjIsLocked   = !!(activeSY && activeSY.is_finalized == 1);

  // Apply status filter
  if (_subjFilterMode === 'active')   _subjAllRows = _subjAllRows.filter(r => r.is_archived == 0);
  if (_subjFilterMode === 'archived') _subjAllRows = _subjAllRows.filter(r => r.is_archived == 1);

  // Grade counts from full unfiltered (status-filtered) set
  const gradeCounts = { 7: 0, 8: 0, 9: 0, 10: 0 };
  _subjAllRows.forEach(r => { if (gradeCounts[r.grade_level_id] !== undefined) gradeCounts[r.grade_level_id]++; });

  const lockBanner = _subjIsLocked
    ? `<div class="lock-banner"><i class="fa-solid fa-lock"></i> School year <strong>${escHTML(activeSY.label)}</strong> is finalized — subjects are read-only.</div>`
    : '';

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Subjects</h1>
      <p>DepEd MATATAG JHS subject master list — subjects are grade-specific</p>
    </div>
    <button class="btn btn-primary" onclick="openAddSubject()" ${_subjIsLocked ? 'disabled title="School year is locked"' : ''}>
      <i class="fa-solid fa-plus"></i> New Subject
    </button>
  </div>
  ${lockBanner}

  <!-- Module tabs -->
  <div class="subj-tabs">
    <button class="subj-tab-btn active" onclick="switchSubjTab('list',this)">
      <i class="fa-solid fa-book-open"></i> Subject List
    </button>
    <button class="subj-tab-btn" onclick="switchSubjTab('curriculum',this)">
      <i class="fa-solid fa-sitemap"></i> Curriculum Matrix
    </button>
  </div>

  <!-- Grade filter chips (clickable) -->
  <div class="subj-grade-chips" id="subjGradeChips">
    <button class="subj-grade-chip ${_subjGradeFilter === '' ? 'active' : ''}" onclick="setSubjGradeFilter('')">
      <i class="fa-solid fa-layer-group"></i> All Grades
      <span class="subj-grade-chip-count">${_subjAllRows.length}</span>
    </button>
    ${[7,8,9,10].map(g => `
    <button class="subj-grade-chip ${_subjGradeFilter === 'Grade '+g ? 'active' : ''}" onclick="setSubjGradeFilter('Grade ${g}')">
      Grade ${g}
      <span class="subj-grade-chip-count">${gradeCounts[g]}</span>
    </button>`).join('')}
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-book-open"></i> Subject List</span>
      <div class="filter-bar">
        <div class="search-wrap">
          <i class="fa-solid fa-search"></i>
          <input type="text" id="subjSearch" placeholder="Search subjects…" value="${escHTML(_subjSearch)}"
            oninput="_subjSearch=this.value;_subjPage=1;renderSubjPage()"/>
        </div>
        <select id="subjFilter" onchange="renderSubjects(document.getElementById('contentArea'), this.value)">
          <option value="active"   ${_subjFilterMode==='active'   ? 'selected':''}>Active</option>
          <option value="archived" ${_subjFilterMode==='archived' ? 'selected':''}>Archived</option>
          <option value="all"      ${_subjFilterMode==='all'      ? 'selected':''}>All</option>
        </select>
      </div>
    </div>

    <div class="table-wrap">
      <table id="subjectsTable">
        <thead>
          <tr>
            <th>Code</th>
            <th>Subject Name</th>
            <th>Grade Level</th>
            <th>Hrs/Week</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="subjTbody"></tbody>
      </table>
    </div>

    <!-- Pagination lives inside the panel, below the table -->
    <div class="users-pagination" id="subjPagination"></div>
  </div>`;

  // Render the first (or remembered) page
  renderSubjPage();
}

/* ── Filter helpers ── */
function setSubjGradeFilter(grade) {
  _subjGradeFilter = grade;
  _subjPage        = 1;
  // Update chip active states without full re-render
  document.querySelectorAll('.subj-grade-chip').forEach(c => {
    const chipGrade = c.textContent.trim().replace(/\d+$/, '').trim(); // strip count
    c.classList.toggle('active',
      grade === ''
        ? c.textContent.includes('All Grades')
        : c.textContent.includes(grade)
    );
  });
  renderSubjPage();
}

function _getFilteredSubjRows() {
  const q = _subjSearch.toLowerCase();
  return _subjAllRows.filter(r => {
    const gradeMatch = !_subjGradeFilter || (r.grade_display || '') === _subjGradeFilter;
    const textMatch  = !q
      || (r.name  || '').toLowerCase().includes(q)
      || (r.code  || '').toLowerCase().includes(q)
      || (r.grade_display || '').toLowerCase().includes(q);
    return gradeMatch && textMatch;
  });
}

/* ── Page renderer — called after any filter / page change ── */
function renderSubjPage() {
  const tbody      = document.getElementById('subjTbody');
  const pagingEl   = document.getElementById('subjPagination');
  if (!tbody) return;

  const filtered   = _getFilteredSubjRows();
  const totalPages = Math.max(1, Math.ceil(filtered.length / SUBJ_PER_PAGE));
  if (_subjPage > totalPages) _subjPage = totalPages;

  const start = (_subjPage - 1) * SUBJ_PER_PAGE;
  const slice = filtered.slice(start, start + SUBJ_PER_PAGE);

  if (slice.length === 0) {
    tbody.innerHTML = `<tr><td colspan="6"><div class="empty-state"><i class="fa-solid fa-book-open"></i><p>No subjects found</p></div></td></tr>`;
  } else {
    tbody.innerHTML = slice.map(r => `
    <tr data-id="${r.id}" data-grade="${escHTML(r.grade_display || '')}">
      <td><span class="subject-code-badge">${escHTML(r.code)}</span></td>
      <td class="td-primary">${escHTML(r.name)}</td>
      <td><span style="font-size:12px;font-weight:600;color:var(--primary)">${escHTML(r.grade_display || '—')}</span></td>
      <td class="td-mono">${r.hours_per_week}</td>
      <td>${r.is_archived == 1
            ? '<span class="badge badge-archived">Archived</span>'
            : r.is_active == 1
              ? '<span class="badge badge-active badge-dot">Active</span>'
              : '<span class="badge badge-inactive">Inactive</span>'}</td>
      <td>
        <div style="display:flex;gap:6px;align-items:center">
          ${r.is_archived == 0 && !_subjIsLocked ? `
            <button class="btn-icon" onclick="openEditSubject(${r.id},'${escHTML(r.name)}','${escHTML(r.code)}',${r.grade_level_id},${r.hours_per_week},${r.is_active})" title="Edit"><i class="fa-solid fa-pen"></i></button>
          ` : r.is_archived == 1 && !_subjIsLocked ? `
            <button class="btn-icon" onclick="restoreSubject(${r.id})" title="Restore" style="color:var(--green)"><i class="fa-solid fa-rotate-left"></i></button>
          ` : `<span style="font-size:10px;color:var(--text-muted);font-family:var(--font-mono)"><i class="fa-solid fa-lock"></i></span>`}
        </div>
      </td>
    </tr>`).join('');
  }

  // Render pagination
  if (pagingEl) renderSubjPagination(totalPages, filtered.length);
}

function renderSubjPagination(totalPages, totalItems) {
  const container = document.getElementById('subjPagination');
  if (!container) return;
  if (totalPages <= 1) { container.innerHTML = ''; return; }

  const curr = _subjPage;

  // Build page list with ellipsis — always show first, last, and window around current
  let pages = [];
  if (totalPages <= 7) {
    for (let i = 1; i <= totalPages; i++) pages.push(i);
  } else {
    pages = [1];
    if (curr > 3) pages.push('…');
    for (let i = Math.max(2, curr - 1); i <= Math.min(totalPages - 1, curr + 1); i++) pages.push(i);
    if (curr < totalPages - 2) pages.push('…');
    pages.push(totalPages);
  }

  const btnClass = p => p === curr ? 'page-btn page-btn-active' : 'page-btn';
  const btns = pages.map(p =>
    p === '…'
      ? `<span class="page-ellipsis">…</span>`
      : `<button class="${btnClass(p)}" onclick="goSubjPage(${p})">${p}</button>`
  ).join('');

  const showing = Math.min(totalItems, (_subjPage - 1) * SUBJ_PER_PAGE + SUBJ_PER_PAGE);
  const from    = (_subjPage - 1) * SUBJ_PER_PAGE + 1;

  container.innerHTML = `
    <div class="pagination-wrap">
      <button class="page-btn page-btn-nav" onclick="goSubjPage(${curr - 1})" ${curr === 1 ? 'disabled' : ''}>
        <i class="fa-solid fa-chevron-left"></i>
      </button>
      ${btns}
      <button class="page-btn page-btn-nav" onclick="goSubjPage(${curr + 1})" ${curr === totalPages ? 'disabled' : ''}>
        <i class="fa-solid fa-chevron-right"></i>
      </button>
      <span class="page-info">${from}–${showing} of ${totalItems} · Page ${curr} of ${totalPages}</span>
    </div>`;
}

function goSubjPage(p) {
  const total = Math.max(1, Math.ceil(_getFilteredSubjRows().length / SUBJ_PER_PAGE));
  if (p < 1 || p > total) return;
  _subjPage = p;
  renderSubjPage();
}

/* ── Soft refresh: re-fetch data but keep all filter/page state ── */
async function _refreshSubjects() {
  const includeArchived = (_subjFilterMode === 'all' || _subjFilterMode === 'archived') ? '1' : '0';
  const subRes = await api('get_subjects', { include_archived: includeArchived });
  let rows = subRes.success ? subRes.data : [];
  if (_subjFilterMode === 'active')   rows = rows.filter(r => r.is_archived == 0);
  if (_subjFilterMode === 'archived') rows = rows.filter(r => r.is_archived == 1);
  _subjAllRows = rows;
  // Update grade chip counts
  const gradeCounts = { 7: 0, 8: 0, 9: 0, 10: 0 };
  rows.forEach(r => { if (gradeCounts[r.grade_level_id] !== undefined) gradeCounts[r.grade_level_id]++; });
  document.querySelectorAll('.subj-grade-chip').forEach(c => {
    const countEl = c.querySelector('.subj-grade-chip-count');
    if (!countEl) return;
    if (c.textContent.includes('All Grades')) { countEl.textContent = rows.length; return; }
    const m = c.textContent.match(/Grade (\d+)/);
    if (m) countEl.textContent = gradeCounts[parseInt(m[1])] ?? 0;
  });
  renderSubjPage();
}

/* ── Add Subject ── */
function openAddSubject() {
  // Pre-select grade in modal if a grade is currently filtered
  const preGrade = _subjGradeFilter.replace('Grade ', ''); // '7','8','9','10' or ''
  openModal('New Subject',
    `<div class="form-group">
       <label>Grade Level <span style="color:var(--danger)">*</span></label>
       <select id="sGrade">
         <option value="" ${!preGrade ? 'selected' : ''}>— Select Grade Level —</option>
         <option value="7"  ${preGrade==='7'  ? 'selected':''}>Grade 7</option>
         <option value="8"  ${preGrade==='8'  ? 'selected':''}>Grade 8</option>
         <option value="9"  ${preGrade==='9'  ? 'selected':''}>Grade 9</option>
         <option value="10" ${preGrade==='10' ? 'selected':''}>Grade 10</option>
       </select>
       <div class="form-note" style="font-size:11px;color:var(--text-muted);margin-top:4px">
         <i class="fa-solid fa-circle-info"></i>&nbsp;
         Grade level determines the <strong>-G</strong> suffix of the subject code (7, 8, 9, 10).
       </div>
     </div>
     <div class="form-group">
       <label>Subject Name <span style="color:var(--danger)">*</span></label>
       <input type="text" id="sName" placeholder="e.g. Filipino Mathematics TLE" oninput="sanitizePlainText(this)" autocomplete="off"/>
     </div>
     <div class="form-group">
       <label>Subject Code <span style="color:var(--danger)">*</span></label>
       <input type="text" id="sCode" placeholder="e.g. MATH-8, FIL-7, TLE-10" style="font-family:var(--font-mono)" oninput="sanitizeCodeText(this)" autocomplete="off"/>
       <div class="form-note" style="font-size:11px;color:var(--text-muted);margin-top:4px">
         <i class="fa-solid fa-circle-info"></i>&nbsp;
         Format: <strong>ABBREV-G</strong>&nbsp;(e.g. <strong>FIL-7</strong>, <strong>MATH-8</strong>, <strong>TLE-10</strong>). Letters, numbers, and hyphens only. Used by the Registrar to assign subjects to class schedules.
       </div>
     </div>
     <div class="form-group">
       <label>Hours / Week</label>
       <input type="number" id="sHours" value="1" min="1" max="40"/>
     </div>
     <div class="subj-disabled-notice">
       <i class="fa-solid fa-circle-info"></i>
       <span>New subjects are <strong>disabled by default</strong>. Enable them from the <strong>Curriculum Matrix</strong> tab when ready.</span>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-success" onclick="submitAddSubject()"><i class="fa-solid fa-plus"></i> Create Subject</button>`);
}

// Note: inform user that subjects are disabled by default — enable via Curriculum Matrix

async function submitAddSubject() {
  const name  = document.getElementById('sName').value.trim();
  const code  = document.getElementById('sCode').value.trim().toUpperCase();
  const grade = document.getElementById('sGrade').value;
  const hours = document.getElementById('sHours').value;

  if (!grade) return toast('Please select a grade level.', 'warn');
  if (!name)  return toast('Subject name is required.', 'warn');
  if (!code)  return toast('Subject code is required.', 'warn');

  const res = await api('create_subject', { name, code, grade_level_id: grade, hours_per_week: hours, is_active: 0 });
  if (res.success) {
    toast('Subject created successfully.', 'success');
    closeModal();
    // Keep current grade filter — if none is set, snap to the just-created subject's grade
    if (!_subjGradeFilter) _subjGradeFilter = 'Grade ' + grade;
    await _refreshSubjects();
  } else {
    toast(res.message, 'error');
  }
}

function openEditSubject(id, name, code, gradeId, hours, active) {
  openModal('Edit Subject',
    `<div class="form-group">
       <label>Grade Level <span style="color:var(--danger)">*</span></label>
       <select id="sGrade">
         <option value="7"  ${gradeId==7  ? 'selected':''}>Grade 7</option>
         <option value="8"  ${gradeId==8  ? 'selected':''}>Grade 8</option>
         <option value="9"  ${gradeId==9  ? 'selected':''}>Grade 9</option>
         <option value="10" ${gradeId==10 ? 'selected':''}>Grade 10</option>
       </select>
     </div>
     <div class="form-group">
       <label>Subject Name <span style="color:var(--danger)">*</span></label>
       <input type="text" id="sName" value="${escHTML(name)}" oninput="sanitizePlainText(this)" autocomplete="off"/>
     </div>
     <div class="form-group">
       <label>Subject Code <span style="color:var(--danger)">*</span></label>
       <input type="text" id="sCode" value="${escHTML(code)}" style="font-family:var(--font-mono)" oninput="sanitizeCodeText(this)" autocomplete="off"/>
       <div class="form-note" style="font-size:11px;color:var(--text-muted);margin-top:4px">
         <i class="fa-solid fa-circle-info"></i>&nbsp;Format: <strong>ABBREV-G</strong> (e.g. FIL-7). Letters, numbers, and hyphens only. Used as a filter key by the Registrar.
       </div>
     </div>
     <div class="form-group">
       <label>Hours / Week</label>
       <input type="number" id="sHours" value="${hours}" min="1" max="40"/>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-primary" onclick="submitEditSubject(${id})"><i class="fa-solid fa-floppy-disk"></i> Save Changes</button>`);
}

async function submitEditSubject(id) {
  const name  = document.getElementById('sName').value.trim();
  const code  = document.getElementById('sCode').value.trim().toUpperCase();
  const grade = document.getElementById('sGrade').value;
  const hours = document.getElementById('sHours').value;

  if (!grade) return toast('Please select a grade level.', 'warn');
  if (!name)  return toast('Subject name is required.', 'warn');
  if (!code)  return toast('Subject code is required.', 'warn');

  const res = await api('update_subject', { id, name, code, grade_level_id: grade, hours_per_week: hours });
  if (res.success) {
    toast('Subject updated successfully.', 'success');
    closeModal();
    await _refreshSubjects(); // stay on same page/filter
  } else {
    toast(res.message, 'error');
  }
}

async function toggleSubjectStatus(id, current) {
  const res = await api('toggle_subject', { id, is_active: current == 1 ? 0 : 1 });
  if (res.success) {
    toast(`Subject ${current == 1 ? 'deactivated' : 'activated'}.`, 'success');
    await _refreshSubjects();
  } else toast(res.message, 'error');
}

function archiveSubject(id, name) {
  openModal(
    'Disable and archive this subject?',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
       <p>Archive <strong>${escHTML(name || 'this subject')}</strong>?</p>
       <p class="confirm-sub">The subject will be immediately archived and will no longer appear in active subject lists.</p>
       <label class="subj-archive-hide-check">
         <input type="checkbox" id="hideFromSessionChk"/>
         <span>Hide from current session</span>
       </label>
       <p class="confirm-sub" style="margin-top:6px;font-size:11px;color:var(--text-muted)">
         If checked, this subject will be hidden for your current login session only. After logging out and back in, it will reappear in its archived state.
       </p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-warning" id="confirmArchiveSubjBtn" onclick="doArchiveSubject(${id})">
       <i class="fa-solid fa-box-archive"></i> Confirm
     </button>`
  );
}

async function doArchiveSubject(id) {
  const btn = document.getElementById('confirmArchiveSubjBtn');
  const hideChecked = document.getElementById('hideFromSessionChk')?.checked || false;
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Archiving…'; }

  const res = await api('archive_subject', { id });
  if (res.success) {
    // If "hide from session" is checked, store the ID in sessionStorage so the list renderer can filter it out
    if (hideChecked) {
      const hidden = JSON.parse(sessionStorage.getItem('subj_hidden_ids') || '[]');
      if (!hidden.includes(id)) hidden.push(id);
      sessionStorage.setItem('subj_hidden_ids', JSON.stringify(hidden));
    }
    toast('Subject archived.', 'success');
    closeModal();
    await _refreshSubjects();
  } else {
    toast(res.message || 'Failed to archive subject.', 'error');
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-box-archive"></i> Confirm'; }
  }
}

async function restoreSubject(id) {
  const res = await api('restore_subject', { id });
  if (res.success) { toast('Subject restored and active.', 'success'); await _refreshSubjects(); }
  else toast(res.message, 'error');
}

/* ── Tab switcher ── */
function switchSubjTab(tab, btnEl) {
  _subjTab = tab;
  const ca = document.getElementById('contentArea');
  if (tab === 'curriculum') {
    renderSubjectsWithCurriculumTab(ca);
  } else {
    renderSubjects(ca, null);
  }
}

/* ── Curriculum tab embedded inside Subjects ── */
async function renderSubjectsWithCurriculumTab(ca) {
  // Show spinner while fetching
  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Subjects</h1>
      <p>DepEd MATATAG JHS subject master list — subjects are grade-specific</p>
    </div>
  </div>
  <div class="subj-tabs">
    <button class="subj-tab-btn" onclick="switchSubjTab('list',this)">
      <i class="fa-solid fa-book-open"></i> Subject List
    </button>
    <button class="subj-tab-btn active" onclick="switchSubjTab('curriculum',this)">
      <i class="fa-solid fa-sitemap"></i> Curriculum Matrix
    </button>
  </div>
  <div class="flex-center" style="height:200px"><div class="spinner"></div></div>`;

  const [syRes, currRes, glRes, subRes] = await Promise.all([
    api('get_school_years'), api('get_curriculum'), api('get_grade_levels'), api('get_subjects', { include_archived: '0' })
  ]);

  const sysAll   = syRes.success  ? syRes.data  : [];
  const grades   = glRes.success  ? glRes.data  : [];
  // Show ALL non-archived subjects regardless of is_active — activation managed here
  const subjects = subRes.success ? subRes.data.filter(s => s.is_archived != 1) : [];
  const curriculum = currRes.success ? currRes.data : [];

  const activeSY   = sysAll.find(s => s.is_active) || sysAll[0];
  const activeSYId = activeSY ? activeSY.id : null;
  const currSet    = new Set(curriculum.map(c => `${c.school_year_id}-${c.grade_level_id}-${c.subject_id}`));

  const syOpts     = sysAll.map(s => `<option value="${s.id}" ${s.is_active ? 'selected' : ''}>${s.label}</option>`).join('');
  const headerCols = grades.map(g => `<th>${g.display_name}</th>`).join('');

  const rows = subjects.map(sub => {
    const isEnabled = sub.is_active == 1;
    const cells = grades.map(g => {
      const key     = `${activeSYId}-${g.id}-${sub.id}`;
      const checked = currSet.has(key);
      if (checked) {
        return `<td><span class="curr-check checked" onclick="confirmDisableSubjectFromCell(${sub.id},'${escHTML(sub.name)}')" title="Click to disable &amp; archive this subject">
          <i class="fa-solid fa-check"></i>
        </span></td>`;
      } else {
        return `<td><span class="curr-check" onclick="toggleCurriculum(${activeSYId},${g.id},${sub.id},this,${sub.grade_level_id},'${escHTML(sub.code)}','${escHTML(g.display_name)}')" title="Add to curriculum">
          <i class="fa-solid fa-plus"></i>
        </span></td>`;
      }
    }).join('');

    const enabledDot = isEnabled
      ? ''
      : '<span class="badge badge-inactive" style="font-size:9px;padding:2px 6px;margin-left:4px">Disabled</span>';

    return `<tr data-subj-id="${sub.id}" class="${isEnabled ? '' : 'curr-row-disabled'}">
      <td>
        <div style="display:flex;align-items:center;gap:6px">
          <span>${escHTML(sub.name)} <span class="td-mono">(${escHTML(sub.code)})</span></span>
          ${enabledDot}
        </div>
      </td>${cells}
    </tr>`;
  }).join('');

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Subjects</h1>
      <p>DepEd MATATAG JHS subject master list — subjects are grade-specific</p>
    </div>
    <div class="filter-bar">
      <select id="currSYPicker" onchange="renderSubjectsWithCurriculumTab(document.getElementById('contentArea'))" style="max-width:160px">${syOpts}</select>
    </div>
  </div>

  <div class="subj-tabs">
    <button class="subj-tab-btn" onclick="switchSubjTab('list',this)">
      <i class="fa-solid fa-book-open"></i> Subject List
    </button>
    <button class="subj-tab-btn active" onclick="switchSubjTab('curriculum',this)">
      <i class="fa-solid fa-sitemap"></i> Curriculum Matrix
    </button>
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-sitemap"></i> Subject × Grade Matrix</span>
      <span class="text-muted text-mono" style="font-size:11px">Click <strong>+</strong> to add a subject to a grade · Click <strong>✓</strong> to disable &amp; archive the subject.</span>
    </div>
    <div class="table-wrap">
      <table class="curriculum-matrix">
        <thead><tr><th>Subject</th>${headerCols}</tr></thead>
        <tbody>${rows || `<tr><td colspan="${grades.length + 1}"><div class="empty-state"><i class="fa-solid fa-sitemap"></i><p>No subjects found.</p></div></td></tr>`}</tbody>
      </table>
    </div>
  </div>`;
}

/* ════════════════════════════════════════════════════════════
   CURRICULUM
════════════════════════════════════════════════════════════ */
async function renderCurriculum(ca) {
  const [syRes, currRes, glRes, subRes] = await Promise.all([
    api('get_school_years'), api('get_curriculum'), api('get_grade_levels'), api('get_subjects')
  ]);

  const sysAll = syRes.success ? syRes.data : [];
  const grades = glRes.success ? glRes.data : [];
  const subjects = subRes.success ? subRes.data.filter(s => s.is_active == 1) : [];
  const curriculum = currRes.success ? currRes.data : [];

  const syOpts = sysAll.map(s => `<option value="${s.id}" ${s.is_active ? 'selected' : ''}>${s.label}</option>`).join('');
  const currSet = new Set(curriculum.map(c => `${c.school_year_id}-${c.grade_level_id}-${c.subject_id}`));

  const activeSY = sysAll.find(s => s.is_active) || sysAll[0];
  const activeSYId = activeSY ? activeSY.id : null;

  const headerCols = grades.map(g => `<th>${g.display_name}</th>`).join('');
  const rows = subjects.map(sub => {
    const cells = grades.map(g => {
      const key     = `${activeSYId}-${g.id}-${sub.id}`;
      const checked = currSet.has(key);
      if (checked) {
        return `<td><span class="curr-check checked" onclick="confirmDisableSubjectFromCell(${sub.id},'${escHTML(sub.name)}')" title="Click to disable &amp; archive this subject">
          <i class="fa-solid fa-check"></i>
        </span></td>`;
      } else {
        return `<td><span class="curr-check" onclick="toggleCurriculum(${activeSYId},${g.id},${sub.id},this,${sub.grade_level_id},'${escHTML(sub.code)}','${escHTML(g.display_name)}')" title="Add to curriculum">
          <i class="fa-solid fa-plus"></i>
        </span></td>`;
      }
    }).join('');
    return `<tr><td>${escHTML(sub.name)} <span class="td-mono">(${sub.code})</span></td>${cells}</tr>`;
  }).join('');

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Curriculum</h1>
      <p>Map subjects to grade levels per school year</p>
    </div>
    <div class="filter-bar">
      <select id="currSYPicker" onchange="activateModule('curriculum')" style="max-width:160px">${syOpts}</select>
    </div>
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-sitemap"></i> Subject × Grade Matrix</span>
      <span class="text-muted text-mono" style="font-size:11px">Click cells to toggle. Changes save immediately.</span>
    </div>
    <div class="table-wrap">
      <table class="curriculum-matrix">
        <thead><tr><th>Subject</th>${headerCols}</tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>
  </div>`;
}

async function toggleCurriculum(syId, gradeId, subjectId, el, subjectGradeLevelId, subjectCode, gradeDisplayName) {
  const isChecked = el.classList.contains('checked');

  // \u2500\u2500 Grade-lock guard: only allow enabling in the subject's designated grade \u2500\u2500
  if (!isChecked && subjectGradeLevelId !== undefined && gradeId !== subjectGradeLevelId) {
    const codeMatch = subjectCode ? subjectCode.match(/[-_]?(\d{2})$/) : null;
    const assignedGradeLabel = codeMatch ? `Grade ${parseInt(codeMatch[1], 10)}` : 'its assigned grade';
    toast(
      `Currently cannot assign <strong>${subjectCode}</strong> as <strong>${subjectCode}</strong> is only assigned for <strong>${assignedGradeLabel}</strong>`,
      'warn'
    );
    return;
  }

  const action = isChecked ? 'remove_curriculum' : 'add_curriculum';
  const res = await api(action, { school_year_id: syId, grade_level_id: gradeId, subject_id: subjectId });
  if (res.success) {
    el.classList.toggle('checked', !isChecked);
    el.innerHTML = !isChecked ? '<i class="fa-solid fa-check"></i>' : '<i class="fa-solid fa-plus"></i>';
    toast(isChecked ? 'Removed from curriculum.' : 'Added to curriculum.', 'success');
  } else toast(res.message, 'error');
}

/* ── Enable a subject from the Curriculum Matrix ── */
/* ── Checkbox handler: enable directly, disable via modal ── */
function handleCurrSubjectToggle(checkbox, id, name, wasEnabled) {
  if (wasEnabled) {
    // User unchecked (wants to disable) — revert checkbox immediately, then show modal
    checkbox.checked = true; // revert optimistically; modal will archive if confirmed
    confirmDisableSubject(id, name);
  } else {
    // User checked (wants to enable) — proceed directly
    checkbox.checked = false; // revert while we wait for server
    enableSubjectFromMatrix(id);
  }
}

async function enableSubjectFromMatrix(id) {
  const res = await api('toggle_subject', { id, is_active: 1 });
  if (res.success) {
    toast('Subject enabled.', 'success');
    renderSubjectsWithCurriculumTab(document.getElementById('contentArea'));
  } else toast(res.message || 'Failed to enable subject.', 'error');
}

/* ── Triggered when user clicks a ✓ cell in the matrix ── */
function confirmDisableSubjectFromCell(id, name) {
  openModal(
    'Disable &amp; Archive Subject?',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
       <p>Disable and archive <strong>${escHTML(name)}</strong>?</p>
       <p class="confirm-sub">This subject will be archived and removed from all active subject lists. It can be restored later from the Subject List tab.</p>
       <label class="subj-archive-hide-check">
         <input type="checkbox" id="hideFromSessionChk"/>
         <span>Hide from current session</span>
       </label>
       <p class="confirm-sub" style="margin-top:6px;font-size:11px;color:var(--text-muted)">
         If checked, this subject will be hidden for your current login session only. After logging out and back in, it will reappear in its archived state.
       </p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-warning" id="confirmDisableSubjBtn" onclick="doDisableSubjectFromMatrix(${id})">
       <i class="fa-solid fa-box-archive"></i> Disable &amp; Archive
     </button>`
  );
}

/* ── Confirm disable subject from Curriculum Matrix ── */
function confirmDisableSubject(id, name) {
  openModal(
    'Disable and archive this subject?',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-toggle-off"></i></div>
       <p>Disable <strong>${escHTML(name)}</strong>?</p>
       <p class="confirm-sub">The subject will be immediately archived and will no longer appear in active subject lists.</p>
       <label class="subj-archive-hide-check">
         <input type="checkbox" id="hideFromSessionChk"/>
         <span>Hide from current session</span>
       </label>
       <p class="confirm-sub" style="margin-top:6px;font-size:11px;color:var(--text-muted)">
         If checked, this subject will be hidden for your current login session only. After logging out and back in, it will reappear in its archived state.
       </p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-warning" id="confirmDisableSubjBtn" onclick="doDisableSubjectFromMatrix(${id})">
       <i class="fa-solid fa-toggle-off"></i> Confirm
     </button>`
  );
}

async function doDisableSubjectFromMatrix(id) {
  const btn = document.getElementById('confirmDisableSubjBtn');
  const hideChecked = document.getElementById('hideFromSessionChk')?.checked || false;
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Disabling…'; }

  // Disable (deactivate) then archive
  const res = await api('archive_subject', { id });
  if (res.success) {
    if (hideChecked) {
      const hidden = JSON.parse(sessionStorage.getItem('subj_hidden_ids') || '[]');
      if (!hidden.includes(id)) hidden.push(id);
      sessionStorage.setItem('subj_hidden_ids', JSON.stringify(hidden));
    }
    toast('Subject disabled and archived.', 'success');
    closeModal();
    renderSubjectsWithCurriculumTab(document.getElementById('contentArea'));
  } else {
    toast(res.message || 'Failed to disable subject.', 'error');
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-toggle-off"></i> Confirm'; }
  }
}

/* ════════════════════════════════════════════════════════════
   DEADLINES
════════════════════════════════════════════════════════════ */
const DEADLINE_TYPES = [
  { value: 'enrollment',            label: 'Enrollment' },
  { value: 'grade_encoding_term1',  label: 'Grade Encoding (1st Term)' },
  { value: 'grade_encoding_term2',  label: 'Grade Encoding (2nd Term)' },
  { value: 'grade_encoding_term3',  label: 'Grade Encoding (3rd Term)' },
  { value: 'payments',              label: 'Payments' },
];

/* ─── DEADLINE DATETIME HELPERS ───────────────────────────── */
function formatDT(dtStr) {
  if (!dtStr) return '—';
  const d = new Date(dtStr.replace(' ', 'T'));
  if (isNaN(d)) return dtStr;
  const date = d.toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' });
  const time = d.toLocaleTimeString('en-PH', { hour: '2-digit', minute: '2-digit', hour12: true });
  return `${date} ${time}`;
}

/** Convert "YYYY-MM-DD HH:MM:SS" or "YYYY-MM-DD HH:MM" → datetime-local value "YYYY-MM-DDTHH:MM" */
function toDTLocal(dtStr) {
  if (!dtStr) return '';
  return dtStr.replace(' ', 'T').slice(0, 16);
}

/** Combine separate date + time inputs into a datetime-local-style string */
function combineDT(dateVal, timeVal) {
  if (!dateVal) return '';
  return dateVal + 'T' + (timeVal || '00:00');
}

/** Format "YYYY-MM-DD" → "Month D, YYYY" for display in hints */
function formatDateOnly(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr + 'T00:00');
  if (isNaN(d)) return dateStr;
  return d.toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' });
}

async function renderDeadlines(ca) {
  const [syRes, dlRes] = await Promise.all([api('get_school_years'), api('get_deadlines')]);
  const sysAll    = syRes.success ? syRes.data : [];
  const deadlines = dlRes.success ? dlRes.data : [];

  const activeSY = sysAll.find(s => s.is_active) || sysAll[0];

  // Collect already-used deadline types for the active SY (for duplicate check)
  const usedTypes = deadlines
    .filter(d => activeSY && String(d.school_year_id) === String(activeSY.id))
    .map(d => d.type);
  _dlUsedTypes = usedTypes;  // store for use in onclick attributes

  const rows = deadlines.map(d => {
    const now   = new Date();
    const start = d.start_datetime ? new Date(d.start_datetime.replace(' ', 'T')) : new Date(d.start_date);
    const end   = d.end_datetime   ? new Date(d.end_datetime.replace(' ', 'T'))   : new Date(d.end_date);
    let statusBadge;
    if (now < start)    statusBadge = `<span class="badge badge-closed">Upcoming</span>`;
    else if (now > end) statusBadge = `<span class="badge badge-archived">Closed</span>`;
    else                statusBadge = `<span class="badge badge-active badge-dot">Open</span>`;

    const startVal = d.start_datetime || d.start_date || '';
    const endVal   = d.end_datetime   || d.end_date   || '';

    return `
    <tr>
      <td class="td-mono">${DEADLINE_TYPES.find(t => t.value === d.type)?.label || d.type_label || d.type}</td>
      <td class="td-mono">${formatDT(startVal)}</td>
      <td class="td-mono">${formatDT(endVal)}</td>
      <td>${statusBadge}</td>
      <td><button class="btn-icon" onclick="openEditDeadline(${d.id},'${d.type}','${escHTML(startVal)}','${escHTML(endVal)}','${escHTML(activeSY?.start_date||'')}','${escHTML(activeSY?.end_date||'')}')"><i class="fa-solid fa-pen"></i></button></td>
    </tr>`;
  }).join('');

  const syLabel    = activeSY ? activeSY.label : 'No active school year';
  const syEndDate  = activeSY?.end_date  || '';
  const syStartDate = activeSY?.start_date || '';

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Academic Deadlines</h1>
      <p>Set enrollment and grade encoding windows</p>
    </div>
    <button class="btn btn-primary" onclick="openAddDeadline(${activeSY ? activeSY.id : 'null'},'${escHTML(syStartDate)}','${escHTML(syEndDate)}',_dlUsedTypes)">
      <i class="fa-solid fa-plus"></i> Set Deadline
    </button>
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-clock"></i> Deadline Windows</span>
      <span class="dl-sy-badge"><i class="fa-solid fa-calendar-days"></i> ${escHTML(syLabel)}</span>
    </div>
    <div class="table-wrap">
      <table>
        <thead><tr><th>Type</th><th>Start</th><th>End</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody>
          ${rows || `<tr><td colspan="5"><div class="empty-state"><i class="fa-solid fa-clock"></i><p>No deadlines set yet</p></div></td></tr>`}
        </tbody>
      </table>
    </div>
  </div>`;
}

let _dlCountdownTimer = null;
let _dlUsedTypes      = [];   // avoids JSON.stringify inside onclick attributes

function openAddDeadline(syId, syStart, syEnd, usedTypes = []) {
  _dlUsedTypes = usedTypes;
  if (!syId) return toast('No active school year found.', 'warn');

  const typeOpts = DEADLINE_TYPES.map(t => {
    const used = usedTypes.includes(t.value);
    return `<option value="${t.value}" ${used ? 'disabled' : ''}>${t.label}${used ? ' ✓ already set' : ''}</option>`;
  }).join('');

  const firstAvail = DEADLINE_TYPES.find(t => !usedTypes.includes(t.value));
  const minDT = syStart ? syStart + 'T00:00' : '';
  const maxDT = syEnd   ? syEnd   + 'T23:59' : '';

  const syHint = syEnd
    ? `<div class="dl-sy-hint-bar">
         <div class="dl-sy-hint-icon"><i class="fa-solid fa-circle-info"></i></div>
         <div class="dl-sy-hint-text">
           <span class="dl-sy-hint-label">School Year Boundary</span>
           <span class="dl-sy-hint-desc">Dates must fall within the active school year. End date cannot exceed <strong>${formatDateOnly(syEnd)}</strong>.</span>
         </div>
       </div>`
    : '';

  openModal('Set Academic Deadline',
    `${syHint}
     <div class="dl-form-section">
       <div class="dl-section-label"><i class="fa-solid fa-tag"></i> Deadline Type</div>
       <select id="dlType" class="dl-select"${firstAvail ? '' : ' disabled'}>${typeOpts}</select>
       ${!firstAvail ? '<div class="dl-error-note"><i class="fa-solid fa-circle-xmark"></i> All deadline types have already been set for this school year.</div>' : ''}
     </div>
     <div class="dl-date-row">
       <div class="dl-date-card dl-date-start">
         <div class="dl-date-card-header">
           <i class="fa-solid fa-play-circle"></i>
           <span>Opens</span>
         </div>
         <div class="dt-split-wrap">
           <div class="dt-split-field">
             <label class="dt-split-label"><i class="fa-solid fa-calendar-day"></i> Date</label>
             <input type="date" id="dlStartDate" class="dt-input dt-split-input"
               ${minDT ? `min="${minDT.slice(0,10)}"` : ''} ${maxDT ? `max="${maxDT.slice(0,10)}"` : ''}/>
           </div>
           <div class="dt-split-field">
             <label class="dt-split-label"><i class="fa-solid fa-clock"></i> Time</label>
             <input type="time" id="dlStartTime" class="dt-input dt-split-input"/>
           </div>
         </div>
         <div class="dl-date-hint">Registration opens at this date &amp; time</div>
       </div>
       <div class="dl-date-arrow"><i class="fa-solid fa-arrow-right-long"></i></div>
       <div class="dl-date-card dl-date-end">
         <div class="dl-date-card-header">
           <i class="fa-solid fa-stop-circle"></i>
           <span>Closes</span>
         </div>
         <div class="dt-split-wrap">
           <div class="dt-split-field">
             <label class="dt-split-label"><i class="fa-solid fa-calendar-check"></i> Date</label>
             <input type="date" id="dlEndDate" class="dt-input dt-split-input dt-split-input-end"
               ${minDT ? `min="${minDT.slice(0,10)}"` : ''} ${maxDT ? `max="${maxDT.slice(0,10)}"` : ''}/>
           </div>
           <div class="dt-split-field">
             <label class="dt-split-label"><i class="fa-solid fa-clock"></i> Time</label>
             <input type="time" id="dlEndTime" class="dt-input dt-split-input dt-split-input-end"/>
           </div>
         </div>
         <div class="dl-date-hint">Registration closes at this date &amp; time</div>
       </div>
     </div>
     <div id="dlConfirmBanner" class="dl-confirm-banner" style="display:none">
       <i class="fa-solid fa-triangle-exclamation"></i>
       <span>Deadline will be set. Confirming in <strong id="dlCountdownNum">5</strong>s…</span>
       <button class="btn btn-xs btn-ghost" onclick="cancelDlCountdown()">Cancel</button>
     </div>`,
    `<button class="btn btn-ghost" id="dlCancelBtn" onclick="closeModal()">Cancel</button>
     <button class="btn btn-success" id="dlSetBtn" onclick="startDlCountdown(${syId},'${syStart}','${syEnd}',_dlUsedTypes)"${!firstAvail ? ' disabled' : ''}><i class="fa-solid fa-plus"></i> Set Deadline</button>`, false, 'modal-deadline');

  if (firstAvail) setTimeout(() => { const sel = document.getElementById('dlType'); if (sel) sel.value = firstAvail.value; }, 0);
}

function startDlCountdown(syId, syStart, syEnd, usedTypes = []) {
  const type      = document.getElementById('dlType').value;
  const startDate = document.getElementById('dlStartDate').value;
  const startTime = document.getElementById('dlStartTime').value;
  const endDate   = document.getElementById('dlEndDate').value;
  const endTime   = document.getElementById('dlEndTime').value;
  const start     = combineDT(startDate, startTime);
  const end       = combineDT(endDate, endTime);

  // Validation
  if (!startDate || !startTime) return toast('Opening date and time are required.', 'warn');
  if (!endDate   || !endTime)   return toast('Closing date and time are required.', 'warn');
  if (new Date(end) <= new Date(start)) return toast('End date-time must be after start date-time.', 'warn');

  // Duplicate type check (client-side guard)
  if (usedTypes.includes(type)) {
    const label = DEADLINE_TYPES.find(t => t.value === type)?.label || type;
    return toast(`"${label}" deadline already exists for this school year.`, 'error');
  }

  // School year boundary check
  if (syStart && new Date(start) < new Date(syStart + 'T00:00')) {
    return toast(`Start date cannot be before the school year start (${formatDateOnly(syStart)}).`, 'error');
  }
  if (syEnd && new Date(end) > new Date(syEnd + 'T23:59:59')) {
    return toast(`End date cannot exceed the school year end (${formatDateOnly(syEnd)}).`, 'error');
  }

  const banner    = document.getElementById('dlConfirmBanner');
  const numEl     = document.getElementById('dlCountdownNum');
  const setBtn    = document.getElementById('dlSetBtn');
  const cancelBtn = document.getElementById('dlCancelBtn');

  banner.style.display = 'flex';
  setBtn.disabled = true;
  setBtn.innerHTML = '<i class="fa-solid fa-hourglass-half fa-spin"></i> Setting…';
  cancelBtn.style.display = 'none';

  let secs = 5;
  numEl.textContent = secs;

  _dlCountdownTimer = setInterval(async () => {
    secs--;
    numEl.textContent = secs;
    if (secs <= 0) {
      clearInterval(_dlCountdownTimer);
      _dlCountdownTimer = null;
      await submitAddDeadline(syId);
    }
  }, 1000);
}

function cancelDlCountdown() {
  if (_dlCountdownTimer) { clearInterval(_dlCountdownTimer); _dlCountdownTimer = null; }
  const banner  = document.getElementById('dlConfirmBanner');
  const setBtn  = document.getElementById('dlSetBtn');
  const cancelBtn = document.getElementById('dlCancelBtn');
  if (banner)  banner.style.display = 'none';
  if (setBtn)  { setBtn.disabled = false; setBtn.innerHTML = '<i class="fa-solid fa-plus"></i> Set Deadline'; }
  if (cancelBtn) cancelBtn.style.display = '';
  toast('Countdown cancelled. You can still edit the details.', 'info');
}

async function submitAddDeadline(syId) {
  const type      = document.getElementById('dlType').value;
  const start     = combineDT(document.getElementById('dlStartDate').value, document.getElementById('dlStartTime').value);
  const end       = combineDT(document.getElementById('dlEndDate').value,   document.getElementById('dlEndTime').value);
  if (!start || !end) return toast('Start and end date-times are required.', 'warn');
  const res = await api('create_deadline', { school_year_id: syId, type, start_datetime: start, end_datetime: end });
  if (res.success) { toast('Deadline set successfully.', 'success'); closeModal(); activateModule('deadlines'); }
  else toast(res.message, 'error');
}

function openEditDeadline(id, type, start, end, syStart, syEnd) {
  const typeOpts = DEADLINE_TYPES.map(t => `<option value="${t.value}" ${t.value === type ? 'selected' : ''}>${t.label}</option>`).join('');

  const minDT = syStart ? syStart + 'T00:00' : '';
  const maxDT = syEnd   ? syEnd   + 'T23:59' : '';

  const syHint = syEnd
    ? `<div class="dl-sy-hint-bar">
         <div class="dl-sy-hint-icon"><i class="fa-solid fa-circle-info"></i></div>
         <div class="dl-sy-hint-text">
           <span class="dl-sy-hint-label">School Year Boundary</span>
           <span class="dl-sy-hint-desc">Dates must fall within the active school year. End date cannot exceed <strong>${formatDateOnly(syEnd)}</strong>.</span>
         </div>
       </div>`
    : '';

  openModal('Edit Deadline',
    `${syHint}
     <div class="dl-edit-notice">
       <i class="fa-solid fa-pen-to-square"></i>
       <span>Editing an existing deadline — changes take effect immediately on save.</span>
     </div>
     <div class="dl-form-section">
       <div class="dl-section-label"><i class="fa-solid fa-tag"></i> Deadline Type</div>
       <select id="dlType" class="dl-select">${typeOpts}</select>
     </div>
     <div class="dl-date-row">
       <div class="dl-date-card dl-date-start">
         <div class="dl-date-card-header">
           <i class="fa-solid fa-play-circle"></i>
           <span>Opens</span>
         </div>
         <div class="dt-split-wrap">
           <div class="dt-split-field">
             <label class="dt-split-label"><i class="fa-solid fa-calendar-day"></i> Date</label>
             <input type="date" id="dlStartDate" class="dt-input dt-split-input"
               value="${toDTLocal(start).slice(0,10)}"
               ${minDT ? `min="${minDT.slice(0,10)}"` : ''} ${maxDT ? `max="${maxDT.slice(0,10)}"` : ''}/>
           </div>
           <div class="dt-split-field">
             <label class="dt-split-label"><i class="fa-solid fa-clock"></i> Time</label>
             <input type="time" id="dlStartTime" class="dt-input dt-split-input"
               value="${toDTLocal(start).slice(11,16)}"/>
           </div>
         </div>
         <div class="dl-date-hint">Registration opens at this date &amp; time</div>
       </div>
       <div class="dl-date-arrow"><i class="fa-solid fa-arrow-right-long"></i></div>
       <div class="dl-date-card dl-date-end">
         <div class="dl-date-card-header">
           <i class="fa-solid fa-stop-circle"></i>
           <span>Closes</span>
         </div>
         <div class="dt-split-wrap">
           <div class="dt-split-field">
             <label class="dt-split-label"><i class="fa-solid fa-calendar-check"></i> Date</label>
             <input type="date" id="dlEndDate" class="dt-input dt-split-input dt-split-input-end"
               value="${toDTLocal(end).slice(0,10)}"
               ${minDT ? `min="${minDT.slice(0,10)}"` : ''} ${maxDT ? `max="${maxDT.slice(0,10)}"` : ''}/>
           </div>
           <div class="dt-split-field">
             <label class="dt-split-label"><i class="fa-solid fa-clock"></i> Time</label>
             <input type="time" id="dlEndTime" class="dt-input dt-split-input dt-split-input-end"
               value="${toDTLocal(end).slice(11,16)}"/>
           </div>
         </div>
         <div class="dl-date-hint">Registration closes at this date &amp; time</div>
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-primary" onclick="submitEditDeadline(${id},'${syStart}','${syEnd}')"><i class="fa-solid fa-floppy-disk"></i> Save Changes</button>`, false, 'modal-deadline');
}

async function submitEditDeadline(id, syStart, syEnd) {
  const type  = document.getElementById('dlType').value;
  const start = combineDT(document.getElementById('dlStartDate').value, document.getElementById('dlStartTime').value);
  const end   = combineDT(document.getElementById('dlEndDate').value,   document.getElementById('dlEndTime').value);

  if (!start || !end) return toast('Opening and closing date + time are both required.', 'warn');
  if (new Date(end) <= new Date(start)) return toast('End date-time must be after start date-time.', 'warn');

  // School year boundary check
  if (syStart && new Date(start) < new Date(syStart + 'T00:00')) {
    return toast(`Start date cannot be before the school year start (${formatDateOnly(syStart)}).`, 'error');
  }
  if (syEnd && new Date(end) > new Date(syEnd + 'T23:59:59')) {
    return toast(`End date cannot exceed the school year end (${formatDateOnly(syEnd)}).`, 'error');
  }

  const res = await api('update_deadline', { id, type, start_datetime: start, end_datetime: end });
  if (res.success) { toast('Deadline updated.', 'success'); closeModal(); activateModule('deadlines'); }
  else toast(res.message, 'error');
}

/* ════════════════════════════════════════════════════════════
   ADMIN USERS
════════════════════════════════════════════════════════════ */

const ROLE_META = {
  teacher:     { icon: 'fa-chalkboard-teacher', color: 'role-teacher'     },
  cashier:     { icon: 'fa-cash-register',       color: 'role-cashier'     },
  registrar:   { icon: 'fa-file-signature',      color: 'role-registrar'   },
  principal:   { icon: 'fa-user-tie',            color: 'role-principal'   },
  coordinator: { icon: 'fa-sitemap',             color: 'role-coordinator' },
  admin:       { icon: 'fa-shield-halved',       color: 'role-admin'       },
};

/* ── Pagination + filter state ── */
let _usersActiveRole   = '';
let _usersShowArchived = false;
let _usersSubjectFilter = '';   // subject name filter (teachers only)
let _usersCurrPage     = 1;
const USERS_PER_PAGE   = 10;

/** Refresh the Faculty Accounts list while keeping the current role/filter/page state. */
async function refreshUsersPreserved() {
  const ca = document.getElementById('contentArea');
  if (!ca) return;
  await renderUsers(ca, true);
}

async function renderUsers(ca, preserveFilters = false) {
  const res  = await api('get_admins');
  const rows = res.success ? res.data : [];

  // Collect unique BASE subject names from active (non-archived) teacher rows only
  const subjectSet = new Set();
  rows.forEach(r => {
    if (r.role === 'teacher' && !r.is_archived && r.assigned_subjects) {
      r.assigned_subjects.split(',').forEach(s => {
        const t = s.trim().replace(/[-–]\s*\d+$/, '').trim(); // strip "-07", "–08" etc.
        if (t) subjectSet.add(t);
      });
    }
  });
  const allSubjects = [...subjectSet].sort();

  // Count per role for chips — active (non-archived) users only
  const roleCounts = {};
  ALL_USER_ROLES.forEach(r => roleCounts[r] = 0);
  rows.forEach(r => { if (!r.is_archived && roleCounts[r.role] !== undefined) roleCounts[r.role]++; });

  const roleChips = ALL_USER_ROLES.map(r => {
    const meta = ROLE_META[r] || { icon: 'fa-user', color: 'role-teacher' };
    return `<button class="role-chip" data-role="${r}" onclick="setUsersRoleFilter('${r}',this)">
      <i class="fa-solid ${meta.icon}"></i>
      <span>${r.charAt(0).toUpperCase()+r.slice(1)}</span>
      <span class="role-chip-count">${roleCounts[r]}</span>
    </button>`;
  }).join('');

  // Subject filter dropdown (only meaningful for teachers)
  const subjectOpts = allSubjects.map(s => `<option value="${escHTML(s)}">${escHTML(s)}</option>`).join('');

  const activeCount   = rows.filter(r => !r.is_archived).length;
  const archivedCount = rows.filter(r =>  r.is_archived).length;

  // Embed all data as JSON for client-side filtering
  const safeRows = JSON.stringify(rows);

  // Detect if a principal already exists (non-archived) — used to disable the role in Add modal
  const hasPrincipal = rows.some(r => r.role === 'principal' && !r.is_archived);
  // Store on window so openAddAdmin can read it without a param
  window._hasPrincipal = hasPrincipal;

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Faculty Accounts</h1>
      <p>Manage faculty accounts</p>
    </div>
    <button class="btn btn-primary" onclick="openAddAdmin()"><i class="fa-solid fa-plus"></i> Add Account</button>
  </div>

  <!-- Role filter chips -->
  <div class="users-role-chips">
    <button class="role-chip role-chip-all active" data-role="" onclick="setUsersRoleFilter('',this)">
      <i class="fa-solid fa-users-gear"></i>
      <span>All Roles</span>
      <span class="role-chip-count">${activeCount}</span>
    </button>
    ${roleChips}
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-users-gear"></i> Faculty &amp; Staff Accounts</span>
      <div class="filter-bar">
        <div class="search-wrap" style="max-width:220px">
          <i class="fa-solid fa-search"></i>
          <input type="text" id="usersSearch" placeholder="Search by name, username, or Employee ID…" oninput="applyUsersFilter()" autocomplete="off"/>
        </div>
        <!-- Subject filter (for teachers) -->
        <select id="usersSubjectFilter" onchange="applyUsersFilter()" style="max-width:190px" title="Filter by subject">
          <option value="">All Subjects</option>
          ${subjectOpts}
        </select>
        <!-- Archived accounts modal button -->
        <button class="archived-toggle-btn" id="archivedToggleBtn" onclick="openArchivedFacultyModal()">
          <i class="fa-solid fa-box-archive"></i>
          <span>Archived Accounts</span>
          ${archivedCount > 0 ? `<span class="archived-toggle-count">${archivedCount}</span>` : ''}
        </button>
        <span class="users-result-count" id="usersResultCount">${activeCount} account${activeCount!==1?'s':''}</span>
      </div>
    </div>
    <div class="table-wrap">
      <table id="usersTable">
        <thead><tr><th>Name</th><th>Username</th><th>School Email</th><th>Role</th><th>Account Table</th><th>Created</th><th>Actions</th></tr></thead>
        <tbody id="usersTbody"></tbody>
      </table>
      <div class="users-no-match" id="usersNoMatch" style="display:none">
        <i class="fa-solid fa-user-slash"></i>
        <p>No accounts match your search or filter.</p>
      </div>
    </div>
    <!-- Pagination -->
    <div class="users-pagination" id="usersPagination"></div>
  </div>`;

  // Store the full data set
  document.getElementById('usersTable').dataset.rows = safeRows;
  // Only reset filters on a fresh load, not after an edit/archive/restore
  if (!preserveFilters) {
    _usersActiveRole    = '';
    _usersShowArchived  = false;
    _usersSubjectFilter = '';
    _usersCurrPage      = 1;
  }
  // Re-sync the role chip UI to match the current (possibly preserved) active role
  document.querySelectorAll('.role-chip').forEach(c => {
    c.classList.toggle('active', (c.dataset.role ?? '') === _usersActiveRole);
  });
  // Re-sync subject filter dropdown
  const subjSel = document.getElementById('usersSubjectFilter');
  if (subjSel && _usersSubjectFilter) subjSel.value = _usersSubjectFilter;
  applyUsersFilter(!preserveFilters);
}

/** Collect filtered rows based on current state — active accounts only for main table */
function getFilteredUserRows() {
  const tableEl = document.getElementById('usersTable');
  if (!tableEl) return [];
  const allRows = JSON.parse(tableEl.dataset.rows || '[]');
  const q = (document.getElementById('usersSearch')?.value || '').toLowerCase();

  return allRows.filter(r => {
    const isArchived = !!r.is_archived;
    // Main table always shows active accounts only
    if (isArchived) return false;
    const roleMatch  = !_usersActiveRole || r.role === _usersActiveRole;
    const nameMatch  = !q
      || (r.full_name   || '').toLowerCase().includes(q)
      || (r.username    || '').toLowerCase().includes(q)
      || (r.employee_id || '').toLowerCase().includes(q);

    // Subject filter: only applies when filtering by teacher subject
    let subjMatch = true;
    if (_usersSubjectFilter) {
      if (r.role !== 'teacher') {
        subjMatch = false;
      } else {
        // Strip grade-level code suffix before comparing (e.g. "ESP-07" → "ESP")
        const subs = (r.assigned_subjects || '').split(',').map(s => s.trim().replace(/[-–]\s*\d+$/, '').trim());
        subjMatch = subs.some(s => s.toLowerCase() === _usersSubjectFilter.toLowerCase());
      }
    }
    return roleMatch && nameMatch && subjMatch;
  });
}

function applyUsersFilter(resetPage = true) {
  _usersSubjectFilter = document.getElementById('usersSubjectFilter')?.value || '';
  if (resetPage) _usersCurrPage = 1; // reset to first page on filter change, but not on preserve-refresh
  renderUsersPage();
}

function renderUsersPage() {
  const tbody   = document.getElementById('usersTbody');
  const noMatch = document.getElementById('usersNoMatch');
  const countEl = document.getElementById('usersResultCount');
  if (!tbody) return;

  const filtered = getFilteredUserRows();
  const total    = filtered.length;
  const pages    = Math.max(1, Math.ceil(total / USERS_PER_PAGE));
  if (_usersCurrPage > pages) _usersCurrPage = pages;

  const start   = (_usersCurrPage - 1) * USERS_PER_PAGE;
  const pageRows = filtered.slice(start, start + USERS_PER_PAGE);

  tbody.innerHTML = pageRows.length
    ? pageRows.map(r => buildUserRow(r)).join('')
    : `<tr><td colspan="7"><div class="empty-state"><i class="fa-solid fa-users-gear"></i><p>No accounts found</p></div></td></tr>`;

  if (countEl) countEl.textContent = `${total} account${total !== 1 ? 's' : ''}`;
  if (noMatch) noMatch.style.display = total === 0 ? 'flex' : 'none';

  renderUsersPagination(pages);
}

function renderUsersPagination(totalPages) {
  const container = document.getElementById('usersPagination');
  if (!container) return;
  if (totalPages <= 1) { container.innerHTML = ''; return; }

  const curr = _usersCurrPage;

  // Build page numbers with ellipsis (show max 5 page buttons)
  let pages = [];
  if (totalPages <= 7) {
    for (let i = 1; i <= totalPages; i++) pages.push(i);
  } else {
    pages = [1];
    if (curr > 3) pages.push('…');
    for (let i = Math.max(2, curr - 1); i <= Math.min(totalPages - 1, curr + 1); i++) pages.push(i);
    if (curr < totalPages - 2) pages.push('…');
    pages.push(totalPages);
  }

  const btnClass = (p) => p === curr ? 'page-btn page-btn-active' : 'page-btn';
  const btns = pages.map(p =>
    p === '…'
      ? `<span class="page-ellipsis">…</span>`
      : `<button class="${btnClass(p)}" onclick="goUsersPage(${p})">${p}</button>`
  ).join('');

  container.innerHTML = `
    <div class="pagination-wrap">
      <button class="page-btn page-btn-nav" onclick="goUsersPage(${curr - 1})" ${curr === 1 ? 'disabled' : ''}>
        <i class="fa-solid fa-chevron-left"></i>
      </button>
      ${btns}
      <button class="page-btn page-btn-nav" onclick="goUsersPage(${curr + 1})" ${curr === totalPages ? 'disabled' : ''}>
        <i class="fa-solid fa-chevron-right"></i>
      </button>
      <span class="page-info">Page ${curr} of ${totalPages}</span>
    </div>`;
}

function goUsersPage(p) {
  const filtered = getFilteredUserRows();
  const total    = Math.max(1, Math.ceil(filtered.length / USERS_PER_PAGE));
  if (p < 1 || p > total) return;
  _usersCurrPage = p;
  renderUsersPage();
}

function setUsersRoleFilter(role, chipEl) {
  _usersActiveRole = role;
  document.querySelectorAll('.role-chip').forEach(c => c.classList.remove('active'));
  chipEl.classList.add('active');

  // Show/hide subject filter: only meaningful when "teacher" role or "all" is selected
  const subjectSel = document.getElementById('usersSubjectFilter');
  if (subjectSel) {
    const showSubj = role === 'teacher' || role === '';
    subjectSel.style.display = showSubj ? '' : 'none';
    if (!showSubj) { subjectSel.value = ''; _usersSubjectFilter = ''; }
  }

  applyUsersFilter();
}

function toggleArchivedUsers(btn) {
  // Legacy — now opens the dedicated modal instead
  openArchivedFacultyModal();
}

/* ── Archived Faculty Modal ──────────────────────────────── */
let _archFacultyRows  = [];  // all archived rows (master copy)
let _archFacultySearch = ''; // live search state

function openArchivedFacultyModal() {
  // Pull archived rows from the already-fetched dataset
  const tableEl = document.getElementById('usersTable');
  const allRows = tableEl ? JSON.parse(tableEl.dataset.rows || '[]') : [];
  _archFacultyRows  = allRows.filter(r => !!r.is_archived);
  _archFacultySearch = '';

  const count = _archFacultyRows.length;

  openModal(
    `Archived Faculty Accounts`,
    `<div class="arch-modal-header">
       <div class="arch-modal-meta">
         <i class="fa-solid fa-box-archive arch-modal-icon"></i>
         <div>
           <div class="arch-modal-title-text">Archived Accounts</div>
           <div class="arch-modal-subtitle">${count} archived account${count !== 1 ? 's' : ''} · accounts listed here cannot log in</div>
         </div>
       </div>
       <div class="search-wrap arch-modal-search">
         <i class="fa-solid fa-search"></i>
         <input
           type="text"
           id="archFacultySearch"
           placeholder="Search by name or Employee ID…"
           oninput="_archFacultySearch=this.value;renderArchFacultyList()"
           autocomplete="off"
           autofocus
         />
       </div>
     </div>
     <div id="archFacultyList" class="arch-faculty-list"></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()"><i class="fa-solid fa-xmark"></i> Close</button>`,
    true  // modal-lg
  );

  renderArchFacultyList();
}

function renderArchFacultyList() {
  const container = document.getElementById('archFacultyList');
  if (!container) return;

  const q = (_archFacultySearch || '').toLowerCase().trim();
  const filtered = _archFacultyRows.filter(r => {
    if (!q) return true;
    return (r.full_name    || '').toLowerCase().includes(q)
        || (r.employee_id  || '').toLowerCase().includes(q)
        || (r.username     || '').toLowerCase().includes(q);
  });

  if (!filtered.length) {
    container.innerHTML = `
      <div class="arch-empty-state">
        <i class="fa-solid fa-box-archive"></i>
        <p>${q ? 'No archived accounts match your search.' : 'No archived accounts found.'}</p>
      </div>`;
    return;
  }

  container.innerHTML = filtered.map(r => {
    const meta    = ROLE_META[r.role] || { icon: 'fa-user', color: 'role-teacher' };
    const initial = (r.full_name || '?').charAt(0).toUpperCase();
    const subjHtml = (r.role === 'teacher' && r.assigned_subjects)
      ? r.assigned_subjects.split(',').map(s => `<span class="subj-chip arch-subj-chip">${escHTML(s.trim())}</span>`).join('')
      : '';

    return `
    <div class="arch-faculty-card" id="arch-card-${r.id}">
      <div class="arch-card-left">
        <div class="arch-card-avatar ${meta.color}">${initial}</div>
      </div>
      <div class="arch-card-body">
        <div class="arch-card-name">${escHTML(r.full_name || '—')}</div>
        <div class="arch-card-meta">
          <span class="role-badge ${meta.color}" style="font-size:10px;padding:2px 8px">
            <i class="fa-solid ${meta.icon}"></i> ${r.role.charAt(0).toUpperCase()+r.role.slice(1)}
          </span>
          ${r.employee_id ? `<span class="arch-card-empid"><i class="fa-solid fa-id-badge"></i> ${escHTML(r.employee_id)}</span>` : ''}
          ${r.username    ? `<span class="arch-card-username"><i class="fa-solid fa-at"></i> ${escHTML(r.username)}</span>`       : ''}
        </div>
        ${subjHtml ? `<div class="subj-chips-wrap" style="margin-top:5px">${subjHtml}</div>` : ''}
        <div class="arch-card-date"><i class="fa-solid fa-clock"></i> Archived · joined ${r.created_at}</div>
      </div>
      <div class="arch-card-actions">
        <button class="btn btn-sm btn-success arch-restore-btn"
          onclick="confirmRestoreAdmin(${r.id},'${escHTML(r.full_name||'')}','${escHTML(r.account_table||'')}')">
          <i class="fa-solid fa-rotate-left"></i> Unarchive
        </button>
      </div>
    </div>`;
  }).join('');
}

function confirmRestoreAdmin(id, name, table) {
  openModal('Unarchive Account',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-success"><i class="fa-solid fa-rotate-left"></i></div>
       <p>Unarchive <strong>${escHTML(name)}</strong>?</p>
       <div class="arch-restore-info-box">
         <i class="fa-solid fa-circle-info"></i>
         <div>
           When you unarchive this user, their account will be <strong>enabled</strong> and they will be able to <strong>log in again</strong>.
         </div>
       </div>
       <p class="confirm-sub">Do you want to proceed?</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="openArchivedFacultyModal()"><i class="fa-solid fa-arrow-left"></i> Back</button>
     <button class="btn btn-success" onclick="doArchiveAdmin(${id},'${escHTML(table)}',false)">
       <i class="fa-solid fa-rotate-left"></i> Yes, Unarchive
     </button>`
  );
}

/* Legacy alias — kept in case anything calls the old name */
function filterUsersTable(q) {
  if (document.getElementById('usersSearch')) document.getElementById('usersSearch').value = q;
  applyUsersFilter();
}

function _staleFilterUsersTable_REMOVED() {
  // replaced by applyUsersFilter + renderUsersPage
}

function buildUserRow(r) {
  const meta     = ROLE_META[r.role] || { icon: 'fa-user', color: 'role-teacher' };
  const archived = !!r.is_archived;
  const subjHtml = (r.role === 'teacher' && r.assigned_subjects)
    ? r.assigned_subjects.split(',').map(s => `<span class="subj-chip">${escHTML(s.trim())}</span>`).join('')
    : '';

  return `<tr class="users-row ${archived ? 'users-row-archived' : ''}" data-role="${r.role}" data-name="${escHTML((r.full_name||'').toLowerCase())}" data-archived="${archived?'1':'0'}">
    <td>
      <div style="display:flex;align-items:center;gap:10px">
        <div class="user-avatar-chip ${meta.color} ${archived?'archived-avatar':''}">${(r.full_name||'?').charAt(0).toUpperCase()}</div>
        <div>
          <div style="display:flex;align-items:center;gap:6px">
            <span class="td-primary ${archived?'archived-name':''}">${escHTML(r.full_name || '')}</span>
            ${archived ? '<span class="archived-badge"><i class="fa-solid fa-box-archive"></i> Archived</span>' : ''}
          </div>
          ${subjHtml ? `<div class="subj-chips-wrap">${subjHtml}</div>` : ''}
        </div>
      </div>
    </td>
    <td class="td-mono">
      <div>${escHTML(r.username)}</div>
      ${r.employee_id ? `<div style="font-size:10px;margin-top:3px;color:var(--text-muted);letter-spacing:0.05em"><i class="fa-solid fa-id-badge" style="margin-right:3px;opacity:0.55"></i>${escHTML(r.employee_id)}</div>` : ''}
    </td>
    <td class="td-mono">${escHTML(r.school_email || r.email || '')}</td>
    <td><span class="role-badge ${meta.color}"><i class="fa-solid ${meta.icon}"></i> ${r.role.charAt(0).toUpperCase()+r.role.slice(1)}</span></td>
    <td class="td-mono" style="font-size:11px;color:var(--text-muted)">${escHTML(r.account_table || '')}</td>
    <td class="td-mono">${r.created_at}</td>
    <td>
      <div style="display:flex;gap:6px">
        ${!archived
          ? `<button class="btn-icon" title="Edit" onclick="openEditAdmin(${r.id},'${escHTML(r.first_name||'')}','${escHTML(r.middle_name||'')}','${escHTML(r.last_name||'')}','${escHTML(r.personal_email||'')}','${r.role}','${escHTML(r.assigned_subjects||'')}','${escHTML(r.account_table||'')}')"><i class="fa-solid fa-pen"></i></button>
             <button class="btn-icon btn-icon-danger" title="Archive account" onclick="confirmArchiveAdmin(${r.id},'${escHTML(r.full_name||'')}','${escHTML(r.account_table||'')}','${r.role}','${escHTML(r.assigned_subjects||'')}')"><i class="fa-solid fa-box-archive"></i></button>`
          : `<button class="btn-icon btn-icon-success" title="Restore account" onclick="confirmRestoreAdmin(${r.id},'${escHTML(r.full_name||'')}','${escHTML(r.account_table||'')}')"><i class="fa-solid fa-rotate-left"></i></button>`
        }
      </div>
    </td>
  </tr>`;
}

const ALL_USER_ROLES = ['teacher','cashier','registrar','principal','coordinator','admin'];

function buildRoleOpts(selected = 'teacher', disabledRoles = []) {
  return ALL_USER_ROLES.map(r => {
    const isDisabled = disabledRoles.includes(r);
    const label = r.charAt(0).toUpperCase() + r.slice(1) + (isDisabled ? ' (limit reached)' : '');
    return `<option value="${r}" ${r === selected ? 'selected' : ''} ${isDisabled ? 'disabled' : ''}>${label}</option>`;
  }).join('');
}

/** Auto-generate school email preview: firstname+lastname@sjc{role}.edu.ph */
function updateEmailPreview() {
  const fn   = (document.getElementById('aFirstName')?.value || '').trim().toLowerCase().replace(/\s+/g,'');
  const ln   = (document.getElementById('aLastName')?.value  || '').trim().toLowerCase().replace(/\s+/g,'');
  const role = (document.getElementById('aRole')?.value      || 'teacher').toLowerCase();
  const preview = document.getElementById('aSchoolEmailPreview');
  if (preview) preview.value = fn && ln ? `${fn}${ln}@sjc${role}.edu.ph` : '';
}

function buildSubjectSelect(selectedSubjects = '') {
  // Unique subject names — strip any grade-level codes (e.g. "Mathematics-07" → "Mathematics")
  // We fetch live from get_subjects; fallback list used until API resolves
  const sel = selectedSubjects ? selectedSubjects.split(',').map(s => s.trim()) : [];
  return `<div class="form-group teacher-subject-group" id="teacherSubjectGroup">
    <label>Assigned Subjects <span style="color:var(--text-muted);font-weight:400">(select all that apply)</span></label>
    <div class="subject-multiselect" id="subjectMultiselect">
      <div class="subject-loading"><i class="fa-solid fa-spinner fa-spin"></i> Loading subjects…</div>
    </div>
    <input type="hidden" id="aAssignedSubjects"/>
  </div>`;
}

async function loadSubjectOptions(selectedList = []) {
  const wrap = document.getElementById('subjectMultiselect');
  if (!wrap) return;
  const res = await api('get_subjects');
  if (!res.success) { wrap.innerHTML = '<span style="color:var(--danger);font-size:12px">Failed to load subjects.</span>'; return; }

  // Deduplicate by base name (strip grade-level suffix like "-07")
  const seen = new Set();
  const unique = [];
  res.data.forEach(s => {
    const baseName = s.name.replace(/[-–]\s*\d+$/, '').trim();
    if (!seen.has(baseName)) { seen.add(baseName); unique.push({ ...s, baseName }); }
  });

  wrap.innerHTML = unique.map(s => {
    const checked = selectedList.includes(s.baseName);
    return `<label class="subj-checkbox-item ${checked?'checked':''}">
      <input type="checkbox" value="${escHTML(s.baseName)}" ${checked?'checked':''} onchange="syncSubjectHidden()"/>
      <span class="subj-check-icon"><i class="fa-solid fa-check"></i></span>
      <span class="subj-label">${escHTML(s.baseName)}</span>
    </label>`;
  }).join('');
  syncSubjectHidden();
}

function syncSubjectHidden() {
  const boxes  = document.querySelectorAll('#subjectMultiselect input[type=checkbox]');
  const hidden = document.getElementById('aAssignedSubjects');
  if (!hidden) return;
  const vals = [...boxes].filter(b => b.checked).map(b => b.value);
  hidden.value = vals.join(',');
  // Update checked styling
  boxes.forEach(b => b.closest('.subj-checkbox-item')?.classList.toggle('checked', b.checked));
}

function onRoleChange() {
  updateEmailPreview();
  const role  = document.getElementById('aRole')?.value;
  const grp   = document.getElementById('teacherSubjectGroup');
  if (!grp) return;
  if (role === 'teacher') {
    grp.style.display = '';
    grp.classList.add('subject-group-visible');
  } else {
    grp.style.display = 'none';
    grp.classList.remove('subject-group-visible');
  }
}

function openAddAdmin() {
  const disabledRoles = window._hasPrincipal ? ['principal'] : [];
  openModal('Add Faculty / Staff Account',
    `<div class="form-grid">
       <div class="form-group"><label>First Name</label><input type="text" id="aFirstName" placeholder="Juan" oninput="sanitizePlainText(this);updateEmailPreview()" autocomplete="off"/></div>
       <div class="form-group"><label>Last Name</label><input type="text" id="aLastName" placeholder="DelaCreuz" oninput="sanitizePlainText(this);updateEmailPreview()" autocomplete="off"/></div>
     </div>
     <div class="form-group"><label>Middle Name <span style="color:var(--text-muted);font-weight:400">(optional)</span></label><input type="text" id="aMiddleName" placeholder="Santos" oninput="sanitizePlainText(this)" autocomplete="off"/></div>
     <div class="form-grid">
       <div class="form-group"><label>Username</label><input type="text" id="aUser" placeholder="jdelacruz" oninput="sanitizePlainText(this)" autocomplete="off"/></div>
       <div class="form-group"><label>Role</label><select id="aRole" onchange="onRoleChange()">${buildRoleOpts('teacher', disabledRoles)}</select>
         ${disabledRoles.includes('principal') ? '<div style="font-size:10px;color:var(--warn,#f59e0b);margin-top:4px"><i class="fa-solid fa-triangle-exclamation"></i> Principal role is unavailable — an active principal account already exists. Archive it first to create a new one.</div>' : ''}
       </div>
     </div>
     ${buildSubjectSelect()}
     <div class="form-group"><label>School Email <span style="color:var(--text-muted);font-weight:400">(auto-generated)</span></label><input type="text" id="aSchoolEmailPreview" readonly placeholder="juandelacruz@sjcteacher.edu.ph" style="opacity:0.7;cursor:default"/></div>
     <div class="form-group">
       <label>Work / Personal Email <span style="color:var(--danger);font-weight:600">*</span> <span style="color:var(--text-muted);font-weight:400">(Gmail or Yahoo — OTP &amp; credentials sent here)</span></label>
       <input type="text" id="aPersonalEmail" placeholder="juan@gmail.com or juan@yahoo.com" oninput="sanitizeEmailText(this)" autocomplete="off"/>
     </div>
     <div class="form-note" style="font-size:11px;color:var(--text-muted);margin-top:2px;padding:8px 12px;background:var(--bg-overlay);border-radius:6px;border:1px solid var(--border)">
       <i class="fa-solid fa-circle-info" style="margin-right:5px;color:var(--primary)"></i>
       A <strong>system-generated password</strong> and login credentials will be automatically sent to the work/personal email above. <strong>No temp-mail or disposable addresses allowed.</strong>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-success" onclick="submitAddAdmin()"><i class="fa-solid fa-plus"></i> Create Account</button>`);
  // Default role is teacher — load subjects immediately
  loadSubjectOptions([]);
}


async function submitAddAdmin() {
  const first_name        = document.getElementById('aFirstName').value.trim();
  const middle_name       = document.getElementById('aMiddleName').value.trim();
  const last_name         = document.getElementById('aLastName').value.trim();
  const username          = document.getElementById('aUser').value.trim();
  const role              = document.getElementById('aRole').value;
  const personal_email    = document.getElementById('aPersonalEmail').value.trim();
  const assigned_subjects = role === 'teacher' ? (document.getElementById('aAssignedSubjects')?.value || '') : '';
  if (!first_name || !last_name) return toast('First name and last name are required.', 'warn');
  if (!username)                 return toast('Username is required.', 'warn');
  if (!personal_email)           return toast('Work / Personal email is required. Credentials will be sent there.', 'warn');
  const emailErr = validateAdminEmail(personal_email);
  if (emailErr) return toast(emailErr, 'warn');
  const res = await api('create_admin', { first_name, middle_name, last_name, username, role, personal_email, assigned_subjects });
  if (res.success) {
    toast(`Account created! Credentials sent to ${personal_email}`, 'success');
    closeModal();
    activateModule('users');
  } else toast(res.message, 'error');
}

function openEditAdmin(id, firstName, middleName, lastName, personalEmail, role, assignedSubjects, accountTable) {
  assignedSubjects = assignedSubjects || '';
  accountTable = accountTable || '';
  openModal('Edit Account',
    `<input type="hidden" id="aAccountTable" value="${escHTML(accountTable)}"/>
     <div class="form-grid">
       <div class="form-group"><label>First Name</label><input type="text" id="aFirstName" value="${escHTML(firstName)}" oninput="sanitizePlainText(this);updateEmailPreview()" autocomplete="off"/></div>
       <div class="form-group"><label>Last Name</label><input type="text" id="aLastName" value="${escHTML(lastName)}" oninput="sanitizePlainText(this);updateEmailPreview()" autocomplete="off"/></div>
     </div>
     <div class="form-group"><label>Middle Name <span style="color:var(--text-muted);font-weight:400">(optional)</span></label><input type="text" id="aMiddleName" value="${escHTML(middleName)}" oninput="sanitizePlainText(this)" autocomplete="off"/></div>
     <div class="form-group"><label>Role</label><select id="aRole" onchange="onRoleChange()">${buildRoleOpts(role)}</select></div>
     ${buildSubjectSelect(assignedSubjects)}
     <div class="form-group"><label>School Email <span style="color:var(--text-muted);font-weight:400">(auto-generated preview)</span></label><input type="text" id="aSchoolEmailPreview" readonly style="opacity:0.7;cursor:default"/></div>
     <div class="form-group">
       <label>Work / Personal Email <span style="color:var(--danger);font-weight:600">*</span> <span style="color:var(--text-muted);font-weight:400">(Gmail or Yahoo — OTP sent here)</span></label>
       <input type="text" id="aPersonalEmail" value="${escHTML(personalEmail)}" placeholder="juan@gmail.com or juan@yahoo.com" oninput="sanitizeEmailText(this)" autocomplete="off"/>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-primary" onclick="submitEditAdmin(${id})"><i class="fa-solid fa-floppy-disk"></i> Save</button>`);
  setTimeout(() => {
    updateEmailPreview();
    // Show/hide subject picker based on current role
    const grp = document.getElementById('teacherSubjectGroup');
    if (grp) grp.style.display = role === 'teacher' ? '' : 'none';
    if (role === 'teacher') {
      const sel = assignedSubjects ? assignedSubjects.split(',').map(s => s.trim()) : [];
      loadSubjectOptions(sel);
    }
  }, 0);
}

/* ── Step 1: validate fields then open re-auth modal ── */
function submitEditAdmin(id) {
  const first_name        = document.getElementById('aFirstName').value.trim();
  const middle_name       = document.getElementById('aMiddleName').value.trim();
  const last_name         = document.getElementById('aLastName').value.trim();
  const role              = document.getElementById('aRole').value;
  const personal_email    = document.getElementById('aPersonalEmail').value.trim();
  const assigned_subjects = role === 'teacher' ? (document.getElementById('aAssignedSubjects')?.value || '') : '';
  const account_table     = document.getElementById('aAccountTable')?.value || '';
  if (!first_name) return toast('First name is required.', 'warn');
  if (!last_name)  return toast('Last name is required.', 'warn');
  if (!personal_email) return toast('Work / Personal email is required.', 'warn');
  const emailErr = validateAdminEmail(personal_email);
  if (emailErr) return toast(emailErr, 'warn');

  // All fields valid — stash payload and open re-auth
  const fullName = [first_name, middle_name, last_name].filter(Boolean).join(' ');
  window._adminEditPending = { id, first_name, middle_name, last_name, role, personal_email, assigned_subjects, account_table, fullName };
  openAdminReauthModal(fullName);
}

/* ── Step 2: re-auth modal ── */
function openAdminReauthModal(fullName) {
  openModal('Confirm Your Identity',
    `<div style="display:flex;flex-direction:column;align-items:center;gap:10px;padding:8px 0 16px">
       <div style="width:54px;height:54px;border-radius:50%;background:var(--surface-alt);border:2px solid var(--primary);
                   display:flex;align-items:center;justify-content:center;font-size:22px;color:var(--primary)">
         <i class="fa-solid fa-lock"></i>
       </div>
       <p style="margin:0;font-size:14px;font-weight:600;color:var(--text-primary);text-align:center">
         Re-authentication Required
       </p>
       <p style="margin:0;font-size:12px;color:var(--text-secondary);text-align:center;max-width:320px;line-height:1.6">
         Please confirm your password before saving changes to
         <strong style="color:var(--text-primary)">${escHTML(fullName)}</strong>'s account.
       </p>
     </div>

     <div class="form-group">
       <label style="display:flex;align-items:center;gap:6px">
         <i class="fa-solid fa-key" style="color:var(--primary);font-size:12px"></i>
         Your Admin Password
       </label>
       <div style="position:relative">
         <input type="password" id="faAdminPassword" placeholder="Enter your password"
           autocomplete="current-password"
           style="padding-right:44px;box-sizing:border-box;width:100%"
           onkeydown="if(event.key==='Enter')confirmAdminEditWithPassword()"/>
         <button type="button" id="faPasswordToggle"
           title="Show / hide password"
           style="position:absolute;right:0;top:0;bottom:0;width:40px;
                  display:flex;align-items:center;justify-content:center;
                  background:none;border:none;cursor:pointer;
                  color:var(--text-muted);font-size:13px;padding:0;
                  border-radius:0 var(--radius) var(--radius) 0;
                  transition:color 0.15s">
           <i class="fa-solid fa-eye" id="faPasswordToggleIcon"></i>
         </button>
       </div>
       <div id="faReauthError" style="display:none;align-items:center;gap:6px;
                font-size:11px;color:var(--danger);margin-top:6px">
         <i class="fa-solid fa-circle-xmark"></i>
         <span id="faReauthErrMsg">Incorrect password.</span>
       </div>
     </div>

     <div style="background:var(--surface-alt);border:1px solid var(--border);border-radius:8px;
                 padding:10px 14px;font-size:11px;color:var(--text-muted);line-height:1.6;margin-top:4px">
       <i class="fa-solid fa-circle-info" style="color:var(--primary);margin-right:4px"></i>
       This action will be recorded in the audit log. A security notification may be sent
       if the account's email address was changed.
     </div>`,
    `<button class="btn btn-ghost" id="faReauthBackBtn">Back</button>
     <button class="btn btn-primary" id="faConfirmSaveBtn" onclick="confirmAdminEditWithPassword()">
       <i class="fa-solid fa-floppy-disk"></i> Save Changes
     </button>`
  );

  setTimeout(() => {
    document.getElementById('faAdminPassword')?.focus();

    // Show/hide toggle
    const toggleBtn  = document.getElementById('faPasswordToggle');
    const toggleIcon = document.getElementById('faPasswordToggleIcon');
    const pwInput    = document.getElementById('faAdminPassword');
    if (toggleBtn && pwInput) {
      toggleBtn.addEventListener('click', () => {
        const isHidden = pwInput.type === 'password';
        pwInput.type = isHidden ? 'text' : 'password';
        toggleIcon.classList.toggle('fa-eye',       !isHidden);
        toggleIcon.classList.toggle('fa-eye-slash',  isHidden);
        toggleBtn.style.color = isHidden ? 'var(--primary)' : 'var(--text-muted)';
        pwInput.focus();
      });
    }

    // Back button reopens the edit modal with the original values
    const backBtn = document.getElementById('faReauthBackBtn');
    if (backBtn) {
      backBtn.addEventListener('click', () => {
        const p = window._adminEditPending;
        if (p) openEditAdmin(p.id, p.first_name, p.middle_name, p.last_name, p.personal_email, p.role, p.assigned_subjects, p.account_table);
        else   closeModal();
      });
    }
  }, 80);
}

/* ── Step 3: verify password then save ── */
async function confirmAdminEditWithPassword() {
  const password = document.getElementById('faAdminPassword')?.value;
  const errEl    = document.getElementById('faReauthError');
  const errMsg   = document.getElementById('faReauthErrMsg');
  const btn      = document.getElementById('faConfirmSaveBtn');

  if (!password) {
    if (errEl) { errEl.style.display = 'flex'; }
    if (errMsg) errMsg.textContent = 'Password is required.';
    return;
  }

  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Verifying…'; }
  if (errEl) errEl.style.display = 'none';

  const verifyRes = await api('verify_admin_password', { password });
  if (!verifyRes.success) {
    if (errEl) { errEl.style.display = 'flex'; errEl.style.alignItems = 'center'; errEl.style.gap = '6px'; }
    if (errMsg) errMsg.textContent = verifyRes.message || 'Incorrect password.';
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-floppy-disk"></i> Save Changes'; }
    document.getElementById('faAdminPassword').value = '';
    document.getElementById('faAdminPassword').focus();
    return;
  }

  // Password OK — execute the update
  if (btn) btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Saving…';

  const { id, first_name, middle_name, last_name, role, personal_email, assigned_subjects, account_table } = window._adminEditPending;
  const res = await api('update_admin', { id, first_name, middle_name, last_name, role, personal_email, assigned_subjects, account_table });
  if (res.success) {
    toast('Account updated.', 'success');
    window._adminEditPending = null;
    closeModal();
    refreshUsersPreserved();
  } else {
    toast(res.message || 'Failed to update account.', 'error');
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-floppy-disk"></i> Save Changes'; }
  }
}

/* ── Archive / Restore helpers ── */
async function confirmArchiveAdmin(id, name, table, role = '', assignedSubjects = '') {
  // Fetch live subject context from server for teachers and coordinators
  let subjects = '';
  if (role === 'teacher' || role === 'coordinator') {
    const ctx = await api('get_archive_context', { id, table });
    if (ctx.success) subjects = ctx.data?.subjects || '';
  }

  // Build the role-specific warning line
  let warningLine = '';
  if ((role === 'teacher' || role === 'coordinator') && subjects) {
    warningLine = `<p class="confirm-sub confirm-sub-warn"><i class="fa-solid fa-triangle-exclamation" style="color:var(--warning);margin-right:5px"></i><strong>${escHTML(name)}</strong> is currently assigned to <strong>${escHTML(subjects)}</strong>. Archiving this user will disable their account completely.</p>`;
  } else {
    warningLine = `<p class="confirm-sub confirm-sub-warn"><i class="fa-solid fa-triangle-exclamation" style="color:var(--warning);margin-right:5px"></i>Disabling <strong>${escHTML(name)}</strong> will disable their account completely.</p>`;
  }

  openModal('Archive Account',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
       <p>Archive <strong>${escHTML(name)}</strong>?</p>
       ${warningLine}
       <p class="confirm-sub">Do you wish to proceed?</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-warning" onclick="doArchiveAdmin(${id},'${escHTML(table)}',true)"><i class="fa-solid fa-box-archive"></i> Archive</button>`);
}

async function doArchiveAdmin(id, table, archive) {
  const res = await api('archive_admin', { id, table, archive: archive ? '1' : '0' });
  if (res.success) {
    toast(archive ? 'Account archived.' : 'Account unarchived and re-enabled.', 'success');
    closeModal();
    await refreshUsersPreserved();
    // Re-open the archived modal after a restore so the user can continue managing archived accounts
    if (!archive) openArchivedFacultyModal();
  } else toast(res.message, 'error');
}


/* ════════════════════════════════════════════════════════════
   STUDENT ACCOUNTS MODULE
════════════════════════════════════════════════════════════ */

let _saGradeFilter  = 0;   // 0 = All grades
let _saPage         = 1;
let _saSearch       = '';
const SA_PER_PAGE   = 10;
let _saAllRows      = [];  // master copy (active only — archived stored separately)

const GRADE_FILTER_LABELS = {
  0:  { label: 'All Grades', icon: 'fa-users' },
  7:  { label: 'Grade 7',    icon: 'fa-7' },
  8:  { label: 'Grade 8',    icon: 'fa-8' },
  9:  { label: 'Grade 9',    icon: 'fa-9' },
  10: { label: 'Grade 10',   icon: 'fa-1' },
};

const STATUS_META = {
  enrolled:       { cls: 'badge-active badge-dot', label: 'Enrolled' },
  verified:       { cls: 'badge-open',             label: 'Verified' },
  docs_submitted: { cls: 'badge-closed',           label: 'Docs Submitted' },
  pending:        { cls: 'badge-inactive',         label: 'Pending' },
  registered:     { cls: 'badge-inactive',         label: 'Registered' },
};

async function renderStudentAccounts(ca) {
  // Fetch active only for main table
  const res  = await api('get_student_accounts', { include_archived: '0' });
  _saAllRows = res.success ? res.data : [];

  // Count per grade (active only)
  const gradeCounts = { 0: _saAllRows.length, 7: 0, 8: 0, 9: 0, 10: 0 };
  _saAllRows.forEach(r => {
    const lv = parseInt(r.grade_level);
    if (gradeCounts[lv] !== undefined) gradeCounts[lv]++;
  });

  const gradeChips = [0, 7, 8, 9, 10].map(g => {
    const meta  = GRADE_FILTER_LABELS[g];
    const isAll = g === 0;
    return `<button class="role-chip ${isAll ? 'role-chip-all active' : ''}" data-grade="${g}" onclick="setSAGradeFilter(${g},this)">
      <i class="fa-solid ${meta.icon}"></i>
      <span>${meta.label}</span>
      <span class="role-chip-count">${gradeCounts[g] ?? 0}</span>
    </button>`;
  }).join('');

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Student Accounts</h1>
      <p>Manage student accounts — update email, LRN, and archive accounts</p>
    </div>
    <button class="btn btn-warning" onclick="openArchivedStudentsModal()">
      <i class="fa-solid fa-box-archive"></i> View Archived Accounts
    </button>
  </div>

  <!-- Grade filter chips -->
  <div class="users-role-chips">
    ${gradeChips}
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-user-graduate"></i> Student Accounts</span>
      <div class="filter-bar">
        <div class="search-wrap" style="max-width:300px">
          <i class="fa-solid fa-search"></i>
          <input type="text" id="saSearch" placeholder="Search by name or LRN…"
            oninput="_saSearch=this.value;_saPage=1;renderSAPage()" autocomplete="off"/>
        </div>
        <span class="users-result-count" id="saResultCount">—</span>
      </div>
    </div>
    <div class="table-wrap">
      <table id="saTable">
        <thead>
          <tr>
            <th>Student</th>
            <th>LRN</th>
            <th>Grade</th>
            <th>Status</th>
            <th>Personal Email</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody id="saTbody"></tbody>
      </table>
      <div class="users-no-match" id="saNoMatch" style="display:none">
        <i class="fa-solid fa-user-slash"></i>
        <p>No students match your search or filter.</p>
      </div>
    </div>
    <div class="users-pagination" id="saPagination"></div>
  </div>`;

  _saGradeFilter = 0;
  _saSearch      = '';
  _saPage        = 1;
  renderSAPage();
}

/* ── Filter + pagination helpers ── */
function _getSAFiltered() {
  const q = _saSearch.toLowerCase();
  return _saAllRows.filter(r => {
    const gradeMatch = !_saGradeFilter || parseInt(r.grade_level) === _saGradeFilter;
    const queryMatch = !q
      || ((r.last_name  || '') + ' ' + (r.first_name || '')).toLowerCase().includes(q)
      || (r.lrn || '').includes(q);
    return gradeMatch && queryMatch;
  });
}

function renderSAPage() {
  const tbody   = document.getElementById('saTbody');
  const noMatch = document.getElementById('saNoMatch');
  const countEl = document.getElementById('saResultCount');
  const pagEl   = document.getElementById('saPagination');
  if (!tbody) return;

  const filtered   = _getSAFiltered();
  const total      = filtered.length;
  const totalPages = Math.max(1, Math.ceil(total / SA_PER_PAGE));
  if (_saPage > totalPages) _saPage = totalPages;

  const start = (_saPage - 1) * SA_PER_PAGE;
  const slice = filtered.slice(start, start + SA_PER_PAGE);

  tbody.innerHTML = slice.length
    ? slice.map(r => buildSARow(r)).join('')
    : `<tr><td colspan="6"><div class="empty-state"><i class="fa-solid fa-user-graduate"></i><p>No students found.</p></div></td></tr>`;

  if (countEl) countEl.textContent = `${total} student${total !== 1 ? 's' : ''}`;
  if (noMatch) noMatch.style.display = total === 0 ? 'flex' : 'none';
  if (pagEl)   renderSAPagination(totalPages, total);
}

function renderSAPagination(totalPages, total) {
  const container = document.getElementById('saPagination');
  if (!container) return;
  if (totalPages <= 1) { container.innerHTML = ''; return; }

  const curr = _saPage;
  let pages = [];
  if (totalPages <= 7) {
    for (let i = 1; i <= totalPages; i++) pages.push(i);
  } else {
    pages = [1];
    if (curr > 3) pages.push('…');
    for (let i = Math.max(2, curr - 1); i <= Math.min(totalPages - 1, curr + 1); i++) pages.push(i);
    if (curr < totalPages - 2) pages.push('…');
    pages.push(totalPages);
  }

  const btnClass = p => p === curr ? 'page-btn page-btn-active' : 'page-btn';
  const btns = pages.map(p =>
    p === '…'
      ? `<span class="page-ellipsis">…</span>`
      : `<button class="${btnClass(p)}" onclick="goSAPage(${p})">${p}</button>`
  ).join('');

  const from    = (_saPage - 1) * SA_PER_PAGE + 1;
  const showing = Math.min(total, _saPage * SA_PER_PAGE);

  container.innerHTML = `
    <div class="pagination-wrap">
      <button class="page-btn page-btn-nav" onclick="goSAPage(${curr - 1})" ${curr === 1 ? 'disabled' : ''}>
        <i class="fa-solid fa-chevron-left"></i>
      </button>
      ${btns}
      <button class="page-btn page-btn-nav" onclick="goSAPage(${curr + 1})" ${curr === totalPages ? 'disabled' : ''}>
        <i class="fa-solid fa-chevron-right"></i>
      </button>
      <span class="page-info">${from}–${showing} of ${total} · Page ${curr} of ${totalPages}</span>
    </div>`;
}

function goSAPage(p) {
  const total = Math.max(1, Math.ceil(_getSAFiltered().length / SA_PER_PAGE));
  if (p < 1 || p > total) return;
  _saPage = p;
  renderSAPage();
}

function setSAGradeFilter(grade, chipEl) {
  _saGradeFilter = grade;
  _saPage        = 1;
  document.querySelectorAll('.role-chip').forEach(c => c.classList.remove('active'));
  chipEl.classList.add('active');
  renderSAPage();
}

function buildSARow(r) {
  const statusMeta = STATUS_META[r.registration_status] || { cls: 'badge-inactive', label: r.registration_status || 'Registered' };
  const initials   = ((r.first_name || '?').charAt(0) + (r.last_name || '').charAt(0)).toUpperCase();
  const fullName   = escHTML(((r.last_name || '') + ', ' + (r.first_name || '') + (r.middle_name ? ' ' + r.middle_name.charAt(0) + '.' : '')).trim());
  const lrn        = escHTML(r.lrn || '—');
  const grade      = escHTML(r.grade_display || '—');
  const email      = escHTML(r.personal_email || '—');

  return `<tr class="users-row"
              data-grade="${r.grade_level || 0}"
              data-name="${escHTML(((r.last_name||'') + ' ' + (r.first_name||'')).toLowerCase())}"
              data-lrn="${(r.lrn || '').toLowerCase()}">
    <td>
      <div style="display:flex;align-items:center;gap:10px">
        <div class="user-avatar-chip role-teacher">${initials}</div>
        <span class="td-primary">${fullName}</span>
      </div>
    </td>
    <td class="td-mono">${lrn}</td>
    <td><span class="sa-grade-chip">${grade}</span></td>
    <td><span class="badge ${statusMeta.cls}">${statusMeta.label}</span></td>
    <td class="td-mono" style="font-size:12px">${email}</td>
    <td>
      <div style="display:flex;gap:6px">
        <button class="btn-icon" title="Edit student account"
          onclick="openEditStudent(${r.id},'${escHTML(r.personal_email||'')}','${escHTML(r.lrn||'')}','${escHTML((r.first_name||'')+' '+(r.last_name||''))}')">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button class="btn-icon btn-icon-danger" title="Archive account"
          onclick="confirmArchiveStudent(${r.id},'${escHTML((r.first_name||'')+' '+(r.last_name||''))}')">
          <i class="fa-solid fa-box-archive"></i>
        </button>
      </div>
    </td>
  </tr>`;
}

/* ── Edit student modal (email + LRN) ── */
function openEditStudent(id, currentEmail, currentLrn, fullName) {
  openModal(`Edit Student — ${escHTML(fullName)}`,
    `<div class="sa-email-edit-info">
       <i class="fa-solid fa-circle-info"></i>
       You can update the student's personal email (used for OTP &amp; notifications) and their LRN. LRN must be exactly 12 digits.
     </div>

     <div class="form-group" style="margin-top:16px">
       <label>Personal Email</label>
       <input type="text" id="saEmailInput" value="${escHTML(currentEmail)}"
         placeholder="student@gmail.com" autocomplete="off" oninput="sanitizeEmailText(this)"/>
     </div>

     <div class="form-group">
       <label>Learner Reference Number (LRN)
         <span style="color:var(--text-muted);font-weight:400;font-size:11px"> — 12 digits, strictly</span>
       </label>
       <div style="position:relative">
         <input type="text" id="saLrnInput" value="${escHTML(currentLrn)}"
           placeholder="e.g. 123456789012" maxlength="12"
           style="font-family:var(--font-mono);letter-spacing:1px"
           oninput="validateLrnInput(this)"/>
         <span id="saLrnCounter" style="position:absolute;right:12px;top:50%;transform:translateY(-50%);font-size:10px;font-family:var(--font-mono);color:var(--text-muted)">
           ${currentLrn.length}/12
         </span>
       </div>
       <div id="saLrnError" style="font-size:11px;color:var(--danger);margin-top:4px;display:none">
         <i class="fa-solid fa-circle-xmark"></i> LRN must be exactly 12 numeric digits.
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-primary" id="saReviewBtn" onclick="openStudentReauthModal(${id},'${escHTML(fullName).replace(/'/g,"\\'")}')">
       <i class="fa-solid fa-shield-halved"></i> Review &amp; Save
     </button>`
  );
  setTimeout(() => {
    document.getElementById('saEmailInput')?.focus();
    validateLrnInput(document.getElementById('saLrnInput'));
  }, 80);
}

/* ── Step 2: validate fields, then open re-auth confirmation ── */
function openStudentReauthModal(id, fullName) {
  // Validate before opening re-auth
  const email = document.getElementById('saEmailInput')?.value.trim();
  const lrn   = document.getElementById('saLrnInput')?.value.trim();

  if (!email) return toast('Email is required.', 'warn');
  const emailErr = validateAdminEmail(email);
  if (emailErr) return toast(emailErr, 'warn');
  if (lrn && !/^\d{12}$/.test(lrn)) return toast('LRN must be exactly 12 numeric digits.', 'warn');

  // Store pending values on window so re-auth modal can read them
  window._saEditPending = { id, fullName, email, lrn };

  openModal('Confirm Your Identity',
    `<div style="display:flex;flex-direction:column;align-items:center;gap:10px;padding:8px 0 16px">
       <div style="width:54px;height:54px;border-radius:50%;background:var(--surface-alt);border:2px solid var(--primary);
                   display:flex;align-items:center;justify-content:center;font-size:22px;color:var(--primary)">
         <i class="fa-solid fa-lock"></i>
       </div>
       <p style="margin:0;font-size:14px;font-weight:600;color:var(--text-primary);text-align:center">
         Re-authentication Required
       </p>
       <p style="margin:0;font-size:12px;color:var(--text-secondary);text-align:center;max-width:320px;line-height:1.6">
         Please confirm your password before saving changes to
         <strong style="color:var(--text-primary)">${escHTML(fullName)}</strong>'s account.
       </p>
     </div>

     <div class="form-group">
       <label style="display:flex;align-items:center;gap:6px">
         <i class="fa-solid fa-key" style="color:var(--primary);font-size:12px"></i>
         Your Admin Password
       </label>
       <div style="position:relative">
         <input type="password" id="saAdminPassword" placeholder="Enter your password"
           autocomplete="current-password"
           style="padding-right:44px;box-sizing:border-box;width:100%"
           onkeydown="if(event.key==='Enter')confirmStudentEditWithPassword()"/>
         <button type="button" id="saPasswordToggle"
           title="Show / hide password"
           style="position:absolute;right:0;top:0;bottom:0;width:40px;
                  display:flex;align-items:center;justify-content:center;
                  background:none;border:none;cursor:pointer;
                  color:var(--text-muted);font-size:13px;padding:0;
                  border-radius:0 var(--radius) var(--radius) 0;
                  transition:color 0.15s">
           <i class="fa-solid fa-eye" id="saPasswordToggleIcon"></i>
         </button>
       </div>
       <div id="saReauthError" style="display:none;align-items:center;gap:6px;
                font-size:11px;color:var(--danger);margin-top:6px">
         <i class="fa-solid fa-circle-xmark"></i>
         <span id="saReauthErrMsg">Incorrect password.</span>
       </div>
     </div>

     <div style="background:var(--surface-alt);border:1px solid var(--border);border-radius:8px;
                 padding:10px 14px;font-size:11px;color:var(--text-muted);line-height:1.6;margin-top:4px">
       <i class="fa-solid fa-circle-info" style="color:var(--primary);margin-right:4px"></i>
       This action will be recorded in the audit log. If the student's email is changed,
       a security notification will be sent to their new address.
     </div>`,
    `<button class="btn btn-ghost" id="saReauthBackBtn">Back</button>
     <button class="btn btn-primary" id="saConfirmSaveBtn" onclick="confirmStudentEditWithPassword()">
       <i class="fa-solid fa-floppy-disk"></i> Save Changes
     </button>`
  );

  setTimeout(() => {
    // Focus password field
    document.getElementById('saAdminPassword')?.focus();

    // Wire password show/hide toggle with icon swap
    const toggleBtn  = document.getElementById('saPasswordToggle');
    const toggleIcon = document.getElementById('saPasswordToggleIcon');
    const pwInput    = document.getElementById('saAdminPassword');
    if (toggleBtn && pwInput) {
      toggleBtn.addEventListener('click', () => {
        const isHidden = pwInput.type === 'password';
        pwInput.type = isHidden ? 'text' : 'password';
        toggleIcon.classList.toggle('fa-eye',       !isHidden);
        toggleIcon.classList.toggle('fa-eye-slash',  isHidden);
        toggleBtn.style.color = isHidden ? 'var(--primary)' : 'var(--text-muted)';
        pwInput.focus();
      });
    }

    // Wire Back button safely (avoids inline-onclick string injection issues)
    const backBtn = document.getElementById('saReauthBackBtn');
    if (backBtn) {
      backBtn.addEventListener('click', () => {
        const p = window._saEditPending;
        if (p) openEditStudent(p.id, p.email, p.lrn, p.fullName);
        else    closeModal();
      });
    }
  }, 80);
}

/* ── Step 3: verify password server-side, then save ── */
async function confirmStudentEditWithPassword() {
  const password = document.getElementById('saAdminPassword')?.value;
  const errEl    = document.getElementById('saReauthError');
  const errMsg   = document.getElementById('saReauthErrMsg');
  const btn      = document.getElementById('saConfirmSaveBtn');

  if (!password) {
    if (errEl) { errEl.style.display = 'flex'; }
    if (errMsg) errMsg.textContent = 'Password is required.';
    return;
  }

  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Verifying…'; }
  if (errEl) errEl.style.display = 'none';

  // Step 1: verify password
  const verifyRes = await api('verify_admin_password', { password });
  if (!verifyRes.success) {
    if (errEl) { errEl.style.display = 'flex'; errEl.style.alignItems = 'center'; errEl.style.gap = '6px'; }
    if (errMsg) errMsg.textContent = verifyRes.message || 'Incorrect password.';
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-floppy-disk"></i> Save Changes'; }
    document.getElementById('saAdminPassword').value = '';
    document.getElementById('saAdminPassword').focus();
    return;
  }

  // Step 2: password OK — save changes
  if (btn) btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Saving…';

  const { id, email, lrn } = window._saEditPending;
  await submitEditStudent(id, email, lrn);
}

function validateLrnInput(input) {
  if (!input) return;
  // Strip non-digits
  input.value = input.value.replace(/\D/g, '').slice(0, 12);
  const len     = input.value.length;
  const counter = document.getElementById('saLrnCounter');
  const errEl   = document.getElementById('saLrnError');
  if (counter) {
    counter.textContent = `${len}/12`;
    counter.style.color = len === 12 ? 'var(--success,#22c55e)' : len > 0 ? 'var(--warn,#f59e0b)' : 'var(--text-muted)';
  }
  if (errEl) errEl.style.display = (len > 0 && len < 12) ? 'block' : 'none';
}

async function submitEditStudent(id, email, lrn) {
  // Use passed values (already validated before re-auth step)
  if (!email) return toast('Email is required.', 'warn');

  // Single combined action — handles email update, LRN update, audit log, and notification email
  const res = await api('update_student_info', {
    id,
    personal_email: email,
    lrn: lrn || ''
  });

  if (!res.success) {
    toast(res.message || 'Failed to update student account.', 'error');
    // Re-enable the save button in re-auth modal if still open
    const btn = document.getElementById('saConfirmSaveBtn');
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-floppy-disk"></i> Save Changes'; }
    return;
  }

  toast(res.message || 'Student account updated successfully.', 'success');
  window._saEditPending = null;
  closeModal();
  activateModule('student-accounts');
}

/* ── Archived students modal ── */
async function openArchivedStudentsModal() {
  openModal('Archived Student Accounts',
    `<div class="flex-center" style="padding:40px"><div class="spinner"></div></div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Close</button>`,
    true
  );

  const res      = await api('get_student_accounts', { include_archived: '1' });
  const allRows  = res.success ? res.data : [];
  const archived = allRows.filter(r => parseInt(r.is_archived) === 1);

  // Build the modal body with search + grade filter controls
  document.getElementById('modalBody').innerHTML = `
    <div class="arch-stu-toolbar">
      <div class="arch-stu-search-wrap">
        <i class="fa-solid fa-magnifying-glass arch-stu-search-icon"></i>
        <input
          type="text"
          id="archStuSearchInput"
          class="arch-stu-search-input"
          placeholder="Search name or LRN…"
          autocomplete="off"
        />
      </div>
      <div class="arch-stu-grade-filters" id="archStuGradeFilters">
        <button class="arch-stu-grade-btn active" data-grade="all">All</button>
        <button class="arch-stu-grade-btn" data-grade="7">Grade 7</button>
        <button class="arch-stu-grade-btn" data-grade="8">Grade 8</button>
        <button class="arch-stu-grade-btn" data-grade="9">Grade 9</button>
        <button class="arch-stu-grade-btn" data-grade="10">Grade 10</button>
      </div>
    </div>
    <div style="margin-bottom:10px;font-size:12px;color:var(--text-muted)">
      <i class="fa-solid fa-circle-info"></i>
      <span id="archStuCount">${archived.length}</span> archived account${archived.length !== 1 ? 's' : ''}.
      Restored accounts will become active immediately.
    </div>
    <div class="table-wrap" style="max-height:360px;overflow-y:auto">
      <table>
        <thead><tr><th>Student</th><th>LRN</th><th>Grade</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody id="archStuTbody"></tbody>
      </table>
    </div>`;

  // ── Render helper ──────────────────────────────────────────────
  function renderArchivedRows(query, gradeFilter) {
    const q = (query || '').toLowerCase().trim();

    const filtered = archived.filter(r => {
      const fullName = ((r.last_name||'') + ' ' + (r.first_name||'') + ' ' + (r.middle_name||'')).toLowerCase();
      const lrn      = (r.lrn || '').toLowerCase();
      const matchSearch = !q || fullName.includes(q) || lrn.includes(q);

      // grade_display is like "Grade 7" — extract the number for comparison
      const gradeNum = (r.grade_display || '').replace(/\D/g, '');
      const matchGrade = gradeFilter === 'all' || gradeNum === gradeFilter;

      return matchSearch && matchGrade;
    });

    const tbody = document.getElementById('archStuTbody');
    const countEl = document.getElementById('archStuCount');
    if (countEl) countEl.textContent = filtered.length;

    if (!filtered.length) {
      tbody.innerHTML = `<tr><td colspan="5"><div class="empty-state" style="padding:28px">
        <i class="fa-solid fa-box-archive"></i>
        <p>${q || gradeFilter !== 'all' ? 'No results match your search.' : 'No archived student accounts found.'}</p>
      </div></td></tr>`;
      return;
    }

    tbody.innerHTML = filtered.map(r => {
      const fullName   = escHTML(((r.last_name||'') + ', ' + (r.first_name||'') + (r.middle_name ? ' ' + r.middle_name.charAt(0) + '.' : '')).trim());
      const grade      = escHTML(r.grade_display || '—');
      const lrn        = escHTML(r.lrn || '—');
      const statusMeta = STATUS_META[r.registration_status] || { cls: 'badge-inactive', label: r.registration_status || 'Registered' };
      return `<tr>
        <td class="td-primary">${fullName}</td>
        <td class="td-mono">${lrn}</td>
        <td><span class="sa-grade-chip">${grade}</span></td>
        <td><span class="badge ${statusMeta.cls}">${statusMeta.label}</span></td>
        <td>
          <button class="btn-icon btn-icon-success" title="Restore account"
            onclick="doRestoreStudentFromModal(${r.id},'${escHTML((r.first_name||'')+' '+(r.last_name||''))}')">
            <i class="fa-solid fa-rotate-left"></i> Restore
          </button>
        </td>
      </tr>`;
    }).join('');
  }

  // Initial render — show all
  renderArchivedRows('', 'all');

  // ── Wire up search input ───────────────────────────────────────
  let _archStuGrade = 'all';
  let _archStuSearchTimer;

  document.getElementById('archStuSearchInput').addEventListener('input', function () {
    clearTimeout(_archStuSearchTimer);
    _archStuSearchTimer = setTimeout(() => {
      renderArchivedRows(this.value, _archStuGrade);
    }, 200);
  });

  // ── Wire up grade filter buttons ──────────────────────────────
  document.getElementById('archStuGradeFilters').addEventListener('click', function (e) {
    const btn = e.target.closest('.arch-stu-grade-btn');
    if (!btn) return;
    _archStuGrade = btn.dataset.grade;
    this.querySelectorAll('.arch-stu-grade-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const query = document.getElementById('archStuSearchInput').value;
    renderArchivedRows(query, _archStuGrade);
  });
}

async function doRestoreStudentFromModal(id, name) {
  const res = await api('archive_student', { id, archive: '0' });
  if (res.success) {
    toast(`${name} restored successfully.`, 'success');
    // Refresh the modal content
    openArchivedStudentsModal();
    // Also refresh background list
    const listRes  = await api('get_student_accounts', { include_archived: '0' });
    _saAllRows = listRes.success ? listRes.data : _saAllRows;
    renderSAPage();
  } else toast(res.message, 'error');
}

/* ── Archive student ── */
function confirmArchiveStudent(id, name) {
  openModal('Archive Student Account',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
       <p>Archive <strong>${escHTML(name)}</strong>?</p>
       <p class="confirm-sub">The account will be hidden from active lists and the student won't be able to log in. You can restore it at any time via "View Archived Accounts".</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-warning" onclick="doArchiveStudent(${id},true)"><i class="fa-solid fa-box-archive"></i> Archive</button>`
  );
}

async function doArchiveStudent(id, archive) {
  const res = await api('archive_student', { id, archive: archive ? '1' : '0' });
  if (res.success) {
    toast(archive ? 'Student archived.' : 'Student restored.', 'success');
    closeModal();
    activateModule('student-accounts');
  } else toast(res.message, 'error');
}


/* ════════════════════════════════════════════════════════════
   AUDIT LOGS
════════════════════════════════════════════════════════════ */

/* Module-level pagination + filter state for Audit Logs */
let _auditAllRows   = [];
let _auditPage      = 1;
let _auditSearch    = '';
let _auditAction    = '';
const AUDIT_PER_PAGE = 20;

async function renderAudit(ca) {
  // Fetch a generous cap from server; client-side pagination handles display
  const res  = await api('get_audit_logs', { limit: 2000 });
  _auditAllRows = res.success ? res.data : [];
  _auditPage    = 1;
  _auditSearch  = '';
  _auditAction  = '';

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Audit Logs</h1>
      <p>Track all admin actions in the system</p>
    </div>
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-scroll"></i> Activity Log</span>
      <div class="filter-bar">
        <div class="search-wrap">
          <i class="fa-solid fa-search"></i>
          <input type="text" id="auditSearch" placeholder="Search logs…"
            oninput="_auditSearch=this.value;_auditPage=1;renderAuditPage()" autocomplete="off"/>
        </div>
        <select id="auditActionFilter" onchange="_auditAction=this.value;_auditPage=1;renderAuditPage()">
          <option value="">All Actions</option>
          <option value="create">Create</option>
          <option value="update">Update</option>
          <option value="archive">Archive</option>
          <option value="restore">Restore</option>
          <option value="delete">Delete</option>
          <option value="activate">Activate</option>
          <option value="deactivate">Deactivate</option>
          <option value="finalize">Finalize</option>
        </select>
        <span class="users-result-count" id="auditResultCount">—</span>
        <button class="audit-export-btn" id="auditExportBtn" onclick="exportAuditXLSX()" title="Export filtered results as .xlsx">
          <i class="fa-solid fa-file-arrow-down"></i> Export .xlsx
        </button>
      </div>
    </div>
    <div class="audit-click-hint"><i class="fa-solid fa-arrow-pointer"></i> Click any row to view full details</div>
    <div class="table-wrap">
      <table id="auditTable">
        <thead>
          <tr><th>Time</th><th>Admin</th><th>Action</th><th>Table</th><th>Record</th><th>IP</th><th></th></tr>
        </thead>
        <tbody id="auditTbody"></tbody>
      </table>
    </div>
    <div class="users-pagination" id="auditPagination"></div>
  </div>`;

  renderAuditPage();
}

function _getAuditFiltered() {
  const q = _auditSearch.toLowerCase();
  return _auditAllRows.filter(r => {
    const matchAction = !_auditAction || r.action === _auditAction;
    const matchQ = !q || [
      r.admin_name || '', r.action, r.table_name, String(r.record_id), r.ip_address || '', r.created_at
    ].join(' ').toLowerCase().includes(q);
    return matchAction && matchQ;
  });
}

function renderAuditPage() {
  const tbody   = document.getElementById('auditTbody');
  const countEl = document.getElementById('auditResultCount');
  const pagEl   = document.getElementById('auditPagination');
  if (!tbody) return;

  const filtered   = _getAuditFiltered();
  const total      = filtered.length;
  const totalPages = Math.max(1, Math.ceil(total / AUDIT_PER_PAGE));
  if (_auditPage > totalPages) _auditPage = totalPages;

  const start = (_auditPage - 1) * AUDIT_PER_PAGE;
  const slice = filtered.slice(start, start + AUDIT_PER_PAGE);

  tbody.innerHTML = slice.length
    ? slice.map((r, i) => `
      <tr class="audit-row-clickable" data-idx="${start + i}" onclick="openAuditDetail(${start + i})" title="Click to view full details">
        <td class="td-mono" style="white-space:nowrap">${r.created_at}</td>
        <td class="td-primary">${escHTML(r.admin_name || 'System')}</td>
        <td><span class="audit-action-badge audit-${r.action}">${r.action}</span></td>
        <td class="td-mono">${r.table_name}</td>
        <td class="td-mono">#${r.record_id}</td>
        <td class="td-mono">${formatIPDisplay(r.ip_address)}</td>
        <td><i class="fa-solid fa-chevron-right audit-row-arrow"></i></td>
      </tr>`).join('')
    : `<tr><td colspan="7"><div class="empty-state"><i class="fa-solid fa-scroll"></i><p>No audit logs match your search.</p></div></td></tr>`;

  if (countEl) countEl.textContent = `${total} log${total !== 1 ? 's' : ''}`;
  if (pagEl)   renderAuditPagination(totalPages, total);
}

/* ── Audit Detail Modal ─────────────────────────────────────── */
function openAuditDetail(idx) {
  const filtered = _getAuditFiltered();
  const r = filtered[idx];
  if (!r) return;

  /* ── Parse device from user_agent ── */
  const ua = r.user_agent || '';
  const device = parseUserAgent(ua);

  /* ── Extract student identity (only for student edits) ── */
  let studentName = '';
  let studentLrn  = '';
  const isStudentEdit = (r.table_name === 'students');

  /* ── Format old/new values ── */
  let oldHTML = '';
  let newHTML = '';
  let oldObj  = null;
  let newObj  = null;

  try {
    oldObj = r.old_values ? (typeof r.old_values === 'string' ? JSON.parse(r.old_values) : r.old_values) : null;
    newObj = r.new_values ? (typeof r.new_values === 'string' ? JSON.parse(r.new_values) : r.new_values) : null;

    // Pull student identity meta fields before building diff tables
    if (isStudentEdit && oldObj) {
      studentName = oldObj['_student_name'] || '';
      studentLrn  = oldObj['_student_lrn']  || '';
    }

    // Strip _-prefixed meta keys so they don't appear in the diff table
    const stripMeta = obj => {
      if (!obj || typeof obj !== 'object') return obj;
      return Object.fromEntries(Object.entries(obj).filter(([k]) => !k.startsWith('_')));
    };
    const cleanOld = stripMeta(oldObj);
    const cleanNew = stripMeta(newObj);

    if (cleanOld && Object.keys(cleanOld).length) oldHTML = buildJsonDiffTable(cleanOld, cleanNew, 'before');
    if (cleanNew && Object.keys(cleanNew).length) newHTML = buildJsonDiffTable(cleanNew, cleanOld, 'after');
  } catch (e) {
    oldHTML = `<code class="ald-raw-json">${escHTML(String(r.old_values || ''))}</code>`;
    newHTML = `<code class="ald-raw-json">${escHTML(String(r.new_values || ''))}</code>`;
  }

  const hasDiff = !!(r.old_values || r.new_values);

  // Build optional student identity chip (only for student table edits)
  const studentChip = (isStudentEdit && studentName)
    ? `<span class="ald-student-chip">
         <span class="ald-student-name">${escHTML(studentName)}</span>
         <span class="ald-student-lrn">${escHTML(studentLrn || '—')}</span>
       </span>`
    : '';

  const body = `
  <div class="ald-wrap">

    <!-- Identity strip -->
    <div class="ald-strip">
      <span class="ald-action-tag ald-tag-${r.action}">${r.action.toUpperCase()}</span>
      <span class="ald-table-name">${escHTML(r.table_name)}</span>
      <span class="ald-record-id">#${r.record_id}</span>
      ${studentChip}
    </div>

    <!-- Meta grid -->
    <div class="ald-meta-grid">
      <div class="ald-meta-cell">
        <div class="ald-meta-label">Date &amp; Time</div>
        <div class="ald-meta-value ald-mono">${escHTML(r.created_at)}</div>
      </div>
      <div class="ald-meta-cell">
        <div class="ald-meta-label">Administrator</div>
        <div class="ald-meta-value">${escHTML(r.admin_name || 'System')}</div>
      </div>
      <div class="ald-meta-cell">
        <div class="ald-meta-label">Device</div>
        <div class="ald-meta-value">${escHTML(device.deviceModel || device.deviceType || 'Desktop')}</div>
        <div class="ald-meta-sub">${escHTML([device.os, device.browser].filter(Boolean).join(' · '))}</div>
      </div>
      <div class="ald-meta-cell">
        <div class="ald-meta-label">IP Address</div>
        <div class="ald-meta-value ald-mono">${escHTML(formatIPDisplay(r.ip_address))}</div>
        <div class="ald-meta-sub">${escHTML(getIPNote(r.ip_address))}</div>
      </div>
    </div>

    <!-- Action row -->
    <div class="ald-action-row">
      <div>
        <div class="ald-meta-label">Action Performed</div>
        <div class="ald-meta-value">${escHTML(r.action.charAt(0).toUpperCase() + r.action.slice(1))} on <strong>${escHTML(r.table_name)}</strong></div>
        <div class="ald-meta-sub">Record ID #${r.record_id}</div>
      </div>
      <span class="ald-action-tag ald-tag-${r.action}">${r.action.toUpperCase()}</span>
    </div>

    <!-- Before / After diff -->
    <div class="ald-diff-section">
      <div class="ald-diff-label">Before &amp; After</div>
      ${hasDiff ? `
      <div class="ald-diff-grid">
        <div class="ald-diff-col ald-diff-before">
          <div class="ald-diff-col-header"><span class="ald-diff-dot"></span> Before</div>
          <div class="ald-diff-col-body">
            ${oldHTML || '<div class="ald-diff-empty">No data recorded</div>'}
          </div>
        </div>
        <div class="ald-diff-col ald-diff-after">
          <div class="ald-diff-col-header"><span class="ald-diff-dot"></span> After</div>
          <div class="ald-diff-col-body">
            ${newHTML || '<div class="ald-diff-empty">No data recorded</div>'}
          </div>
        </div>
      </div>` : `<div class="ald-no-diff">No data snapshot recorded for this action</div>`}
    </div>

    ${ua ? `
    <div class="ald-ua-row">
      <div class="ald-meta-label">User Agent</div>
      <div class="ald-ua-val">${escHTML(ua.substring(0, 200))}${ua.length > 200 ? '…' : ''}</div>
    </div>` : ''}

  </div>`;

  openModal(`Audit Log Detail — #${r.id || ''}`, body,
    `<button class="btn btn-ghost" onclick="closeModal()"><i class="fa-solid fa-xmark"></i> Close</button>
     <button class="btn audit-detail-export-btn" onclick="exportSingleAuditXLSX(${JSON.stringify(r.id)})">
       <i class="fa-solid fa-file-arrow-down"></i> Export Log
     </button>`,
    true, 'modal-audit-detail'
  );
}

/* ── Render a JSON object as a readable key/value table, highlighting changed fields ── */
function buildJsonDiffTable(obj, otherObj, side) {
  if (!obj || typeof obj !== 'object') return `<code class="ald-raw-json">${escHTML(String(obj))}</code>`;
  const rows = Object.entries(obj).map(([k, v]) => {
    const otherVal = otherObj ? otherObj[k] : undefined;
    const changed  = otherObj !== null && otherObj !== undefined && JSON.stringify(v) !== JSON.stringify(otherVal);
    const valStr   = v === null ? '<em style="color:var(--text-muted)">null</em>' : escHTML(String(v));
    return `<tr class="${changed ? 'ald-diff-row-changed' : ''}">
      <td class="ald-diff-key">${escHTML(k)}</td>
      <td class="ald-diff-val">${valStr}</td>
    </tr>`;
  }).join('');
  return `<table class="ald-diff-table"><tbody>${rows}</tbody></table>`;
}

/* ── Format IP address for human-readable display ── */
function formatIPDisplay(ip) {
  if (!ip) return '—';
  if (ip === '::1' || ip === '127.0.0.1') return '127.0.0.1';
  // Normalize IPv4-mapped IPv6 (e.g. "::ffff:192.168.1.1" → "192.168.1.1")
  const mapped = ip.match(/^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
  if (mapped) return mapped[1];
  return ip;
}

function getIPNote(ip) {
  if (!ip) return '';
  if (ip === '::1' || ip === '127.0.0.1') return 'Localhost — same machine as server';
  const mapped = ip.match(/^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
  if (mapped) {
    const v4 = mapped[1];
    if (v4.startsWith('192.168.') || v4.startsWith('10.') || v4.startsWith('172.')) return 'Local / Private Network';
    return 'IPv4-mapped address';
  }
  if (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.')) return 'Local / Private Network';
  if (ip === '0:0:0:0:0:0:0:1') return 'Localhost — same machine as server';
  return '';
}

/* ── Parse User-Agent string into readable device info ── */
function parseUserAgent(ua) {
  if (!ua) return { icon: 'circle-question', label: 'Unknown Device', os: '', browser: 'Unknown Browser', deviceType: 'Desktop' };

  let os = '';
  let browser = '';
  let icon = 'desktop';
  let deviceType = 'Desktop';
  let deviceModel = '';

  // ── Detect OS + Device Type ──────────────────────────────
  if (/iPhone/.test(ua)) {
    // Extract iOS version
    const iosM = ua.match(/iPhone OS ([0-9_]+)/);
    const iosVer = iosM ? iosM[1].replace(/_/g, '.') : '';
    os = 'iOS' + (iosVer ? ' ' + iosVer : '') + ' — iPhone';
    icon = 'mobile-screen';
    deviceType = 'Mobile';
    deviceModel = 'iPhone';
  } else if (/iPad/.test(ua)) {
    const iosM = ua.match(/CPU OS ([0-9_]+)/);
    const iosVer = iosM ? iosM[1].replace(/_/g, '.') : '';
    os = 'iPadOS' + (iosVer ? ' ' + iosVer : '') + ' — iPad';
    icon = 'tablet-screen-button';
    deviceType = 'Tablet';
    deviceModel = 'iPad';
  } else if (/Android/.test(ua)) {
    const andM  = ua.match(/Android ([0-9.]+)/);
    const andVer = andM ? andM[1] : '';
    // Try to extract device model from end of UA (e.g. "Pixel 6", "SM-G991B")
    const modelM = ua.match(/;\s*([^;)]+)\s*Build\//);
    const model  = modelM ? modelM[1].trim() : '';
    os = 'Android' + (andVer ? ' ' + andVer : '');
    if (model) os += ' — ' + model;
    if (/Mobile/.test(ua)) {
      icon = 'mobile-screen';
      deviceType = 'Mobile';
      deviceModel = model || 'Android Phone';
    } else {
      icon = 'tablet-screen-button';
      deviceType = 'Tablet';
      deviceModel = model || 'Android Tablet';
    }
  } else if (/CrOS/.test(ua)) {
    os = 'Chrome OS';
    icon = 'laptop';
    deviceType = 'Chromebook';
    deviceModel = 'Chromebook';
  } else if (/Macintosh|Mac OS X/.test(ua)) {
    // Detect macOS version
    const macM = ua.match(/Mac OS X ([0-9_]+)/);
    const macVer = macM ? macM[1].replace(/_/g, '.') : '';
    os = 'macOS' + (macVer ? ' ' + macVer : '');
    icon = 'laptop';
    deviceType = 'Mac';
    deviceModel = 'Mac';
  } else if (/Windows NT 10/.test(ua)) {
    // Windows 10 or 11 — can't distinguish without JS hints
    os = 'Windows 10 / 11';
    deviceModel = 'Windows PC';
  } else if (/Windows NT 6\.3/.test(ua)) {
    os = 'Windows 8.1';
    deviceModel = 'Windows PC';
  } else if (/Windows NT 6\.1/.test(ua)) {
    os = 'Windows 7';
    deviceModel = 'Windows PC';
  } else if (/Windows/.test(ua)) {
    os = 'Windows';
    deviceModel = 'Windows PC';
  } else if (/Linux/.test(ua)) {
    os = 'Linux';
    deviceModel = 'Linux PC';
  } else {
    os = 'Unknown OS';
    deviceModel = 'Unknown Device';
  }

  // ── Detect Browser ──────────────────────────────────────
  let browserVer = '';
  if (/Edg\/([0-9.]+)/.test(ua)) {
    browser = 'Microsoft Edge';
    browserVer = ua.match(/Edg\/([0-9.]+)/)?.[1]?.split('.')[0] || '';
  } else if (/OPR\/([0-9.]+)|Opera/.test(ua)) {
    browser = 'Opera';
    browserVer = ua.match(/OPR\/([0-9.]+)/)?.[1]?.split('.')[0] || '';
  } else if (/Brave/.test(ua)) {
    browser = 'Brave';
  } else if (/Firefox\/([0-9.]+)/.test(ua)) {
    browser = 'Firefox';
    browserVer = ua.match(/Firefox\/([0-9.]+)/)?.[1]?.split('.')[0] || '';
  } else if (/Chrome\/([0-9.]+)/.test(ua)) {
    browser = 'Chrome';
    browserVer = ua.match(/Chrome\/([0-9.]+)/)?.[1]?.split('.')[0] || '';
  } else if (/Safari\//.test(ua)) {
    browser = 'Safari';
    const safM = ua.match(/Version\/([0-9.]+)/);
    browserVer = safM ? safM[1].split('.')[0] : '';
  } else {
    browser = 'Unknown Browser';
  }

  const browserLabel = browser + (browserVer ? ' ' + browserVer : '');

  // ── Build the primary label shown in "Device Used" card ─
  // Format: "<Device/OS> via <Browser>"
  const primaryLabel = (deviceModel || os) + ' via ' + browserLabel;

  return {
    icon,
    label: primaryLabel,          // e.g. "Windows PC via Chrome 124"
    os,                           // e.g. "Windows 10 / 11"
    browser: browserLabel,        // e.g. "Chrome 124"
    deviceType,                   // e.g. "Desktop"
    deviceModel,                  // e.g. "Windows PC"
  };
}

function renderAuditPagination(totalPages, total) {
  const container = document.getElementById('auditPagination');
  if (!container) return;
  if (totalPages <= 1) { container.innerHTML = ''; return; }

  const curr = _auditPage;
  let pages = [];
  if (totalPages <= 7) {
    for (let i = 1; i <= totalPages; i++) pages.push(i);
  } else {
    pages = [1];
    if (curr > 3) pages.push('…');
    for (let i = Math.max(2, curr - 1); i <= Math.min(totalPages - 1, curr + 1); i++) pages.push(i);
    if (curr < totalPages - 2) pages.push('…');
    pages.push(totalPages);
  }

  const btnClass = p => p === curr ? 'page-btn page-btn-active' : 'page-btn';
  const btns = pages.map(p =>
    p === '…'
      ? `<span class="page-ellipsis">…</span>`
      : `<button class="${btnClass(p)}" onclick="goAuditPage(${p})">${p}</button>`
  ).join('');

  const from    = (_auditPage - 1) * AUDIT_PER_PAGE + 1;
  const showing = Math.min(total, _auditPage * AUDIT_PER_PAGE);

  container.innerHTML = `
    <div class="pagination-wrap">
      <button class="page-btn page-btn-nav" onclick="goAuditPage(${curr - 1})" ${curr === 1 ? 'disabled' : ''}>
        <i class="fa-solid fa-chevron-left"></i>
      </button>
      ${btns}
      <button class="page-btn page-btn-nav" onclick="goAuditPage(${curr + 1})" ${curr === totalPages ? 'disabled' : ''}>
        <i class="fa-solid fa-chevron-right"></i>
      </button>
      <span class="page-info">${from}–${showing} of ${total} · Page ${curr} of ${totalPages}</span>
    </div>`;
}

function goAuditPage(p) {
  const total = Math.max(1, Math.ceil(_getAuditFiltered().length / AUDIT_PER_PAGE));
  if (p < 1 || p > total) return;
  _auditPage = p;
  renderAuditPage();
}

/* Legacy DOM-filter (no longer used but kept for safety) */
function filterAuditTable(q) {
  _auditSearch = q;
  _auditPage   = 1;
  renderAuditPage();
}

/* ─── UTILS ──────────────────────────────────────────────── */
function escHTML(str) {
  return String(str)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

/* ════════════════════════════════════════════════════════════
   INPUT SANITIZATION SYSTEM
   Rules:
   • Plain text fields  → letters + numbers ONLY
     (no spaces, hyphens, symbols, emojis, special chars, or ")
   • Subject code field → letters + numbers + hyphen ONLY
     (the one exception to support format like MATH-8)
   • Email fields       → letters + numbers + @ and . and + ONLY
     (hyphens, spaces, emojis, quotes, and all other symbols are blocked;
      temp-mail domains blocked on submit)
════════════════════════════════════════════════════════════ */

/** Strip everything except letters and digits (no spaces, no hyphens). */
function sanitizePlainText(input) {
  // Remove anything that is not a letter (any script) or a digit.
  // Also explicitly strip the straight double-quote character.
  input.value = input.value
    .replace(/[^a-zA-Z0-9\u00C0-\u024F\u1E00-\u1EFF]/g, '');
}

/** Strip everything except letters, digits, and a single hyphen (for subject codes). */
function sanitizeCodeText(input) {
  input.value = input.value
    .replace(/[^a-zA-Z0-9\-]/g, '')
    // Collapse multiple consecutive hyphens into one
    .replace(/-{2,}/g, '-');
}

/** Strip everything except letters, digits, @, dot, and + (for email addresses). */
function sanitizeEmailText(input) {
  input.value = input.value
    .replace(/[^a-zA-Z0-9@.+]/g, '')
    // Prevent more than one @
    .replace(/(@.*?)@/g, '$1');
}

/** Blocked temporary / disposable email domains. */
const TEMP_MAIL_DOMAINS = [
  'mailinator.com','guerrillamail.com','guerrillamailblock.com','guerrillamail.info',
  'guerrillamail.biz','guerrillamail.de','guerrillamail.net','guerrillamail.org',
  'tempmail.com','temp-mail.org','throwam.com','throwam.net','dispostable.com',
  'yopmail.com','yopmail.fr','cool.fr.nf','jetable.fr.nf','nospam.ze.tc',
  'nomail.xl.cx','mega.zik.dj','speed.1s.fr','courriel.fr.nf','moncourrier.fr.nf',
  'monemail.fr.nf','monmail.fr.nf','trashmail.at','trashmail.com','trashmail.io',
  'trashmail.me','trashmail.net','trashmail.org','trashmail.xyz','sharklasers.com',
  'guerrillamail.info','grr.la','guerrillamailblock.com','spam4.me','spamgourmet.com',
  'spamgourmet.net','spamgourmet.org','spamgourmet.com','spamgourmet.net','mailnull.com',
  'maildrop.cc','inboxkitten.com','fakeinbox.com','mailnesia.com','mailnull.com',
  '10minutemail.com','10minutemail.net','10minutemail.org','10minutemail.co.uk',
  '20minutemail.com','minutemailbox.com','getairmail.com','filzmail.com',
  'owlpic.com','spamhereplease.com','kasmail.com','spamspot.com',
  'discard.email','discardmail.com','discardmail.de','throwam.com',
  'crap.handcrafted.jp','imgof.com','spamevader.net','sharklasers.com',
  'tempinbox.com','tempr.email','tempsky.com','tempomail.fr','temporarily.de',
  'throam.com','throwam.com','throwam.net','jnxjn.com','trbvm.com',
  'spamgourmet.com','spam.la','bccto.me','chacuo.net','discard.email',
  'fakemailgenerator.com','maildrop.cc','mailnull.com','spamgourmet.com',
  'mt2014.com','mt2015.com','qq.com.ru','sharklasers.com','sogetthis.com',
  'spamgourmet.com','spamhereplease.com','spamspot.com','trashtom.com',
  'wegwerfemail.de','wegwerfmail.de','wegwerfmail.net','wegwerfmail.org',
  'wegwerfadresse.de','yahoo.com.ph.com','zetmail.com','zoemail.org',
  'dispostable.com','tempm.com','tmails.net','trashdevil.com','trashdevil.de',
  'trashmail.at','trashmail.com','trashmail.io','trashmail.me','trashmail.net',
  'trashmail.org','trashmail.xyz','mailtemp.net','mohmal.com','tempail.com',
  'spamfree24.org','spamfree24.de','spamfree24.info','spamfree24.biz',
  'spamfree24.net','spamfree24.com','spamfree.eu','spamfree24.eu',
  'mailexpire.com','mail.mezimages.net','meltmail.com','ero-tube.org',
  'hot-mail.ru','hot-mail.tk','ieatspam.eu','ieatspam.info','instant-mail.de',
  'jetable.com','jetable.fr.nf','jetable.net','jetable.org','courriel.fr.nf',
  'jetable.pp.ua','kasmail.com','klassmaster.com','klzlk.com','kurzepost.de',
  'lol.ovpn.to','lookugly.com','lopl.co.cc','lortemail.dk','lr78.com',
  'lukop.dk','meinspamschutz.de','mailscrap.com','mailslite.com',
  'mailtemporaire.com','mailtemporaire.fr','mega.zik.dj','mfsa.ru',
  'mhzayt.online','mintemail.com','misterpinball.de','moncourrier.fr.nf',
  'monemail.fr.nf','monmail.fr.nf','mozcom.com','muelmail.com',
  'mymail-in.net','mymailoasis.com','mynetstore.de','mytempmail.com',
  'nwldx.com','nobulk.com','noclickemail.com','nus.edu.sg.9q.ro',
  'nwldx.com','oneoffmail.com','onewaymail.com','online.ms',
  'ooemail.com','ordinaryamerican.net','owlpic.com',
];

/**
 * Validate an email address for use in faculty/student forms.
 * Allowed in local part (before @): letters, digits, dots, + sign
 * NOT allowed: hyphens, spaces, emojis, quotes (single or double), or any other symbol
 * Returns null if valid, or an error string if invalid.
 */
function validateAdminEmail(email) {
  if (!email) return 'Email is required.';
  // Local part: letters, digits, dots, + only
  // Domain part: letters, digits, dots only, with a valid TLD
  if (!/^[a-zA-Z0-9][a-zA-Z0-9.+]*@[a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)*\.[a-zA-Z]{2,}$/.test(email)) {
    return 'Invalid email format. Only letters, numbers, dots (.) and plus (+) are allowed before the @. No hyphens, spaces, quotes, or special characters.';
  }
  // Reject if local part starts or ends with a dot or +
  const local = email.split('@')[0];
  if (/^[.+]|[.+]$/.test(local)) {
    return 'Email cannot start or end with a dot (.) or plus (+).';
  }
  // Reject consecutive dots in local part
  if (/\.{2,}/.test(local)) {
    return 'Email cannot contain consecutive dots.';
  }
  const domain = email.split('@')[1].toLowerCase();
  if (TEMP_MAIL_DOMAINS.includes(domain)) {
    return 'Temporary or disposable email addresses are not allowed. Please use a real Gmail or Yahoo address.';
  }
  return null;
}

/* ════════════════════════════════════════════════════════════
   ROOM MANAGEMENT
════════════════════════════════════════════════════════════ */

/* ── Sanitise: strip everything that isn't a digit ── */
function _sanitiseNumber(str) {
  return str.replace(/[^0-9]/g, '');
}

/* ── Update nav badge from DB count ── */
async function _updateRoomBadge() {
  const badge = document.getElementById('badgeRooms');
  if (!badge) return;
  try {
    const res = await api('get_rooms');
    if (res.success) {
      const active = (res.data || []).filter(r => r.status !== 'archived').length;
      badge.textContent = active || '0';
    }
  } catch (_) {}
}

/* ═══ MAIN RENDER ════════════════════════════════════════════ */
async function renderRooms(ca) {

  // Show loading state while we fetch
  ca.innerHTML = `<div class="loading-placeholder" style="padding:40px;text-align:center;color:var(--text-muted)">
    <i class="fa-solid fa-circle-notch fa-spin" style="font-size:24px"></i>
    <p style="margin-top:12px">Loading rooms…</p>
  </div>`;

  // Fetch rooms and section assignments in parallel
  const [roomsRes, sectionsRes] = await Promise.all([
    api('get_rooms'),
    api('get_sections_by_grade'),
  ]);

  if (!roomsRes.success) {
    ca.innerHTML = `<div class="empty-state"><p>Failed to load rooms: ${escHTML(roomsRes.message || 'Unknown error')}</p></div>`;
    return;
  }

  const allRooms = roomsRes.data || [];

  // Build sectionMap: roomNumber → { sectionName, gradeName, enrolledCount, capacity }
  // Sections store room as a plain varchar (room number string), not a foreign key yet
  let sectionMap = {};
  if (sectionsRes.success) {
    Object.values(sectionsRes.data).forEach(g => {
      (g.sections || []).forEach(s => {
        const roomNum = (s.room || '').trim();
        if (roomNum) {
          sectionMap[roomNum] = {
            sectionId:     s.id,
            sectionName:   s.name,
            gradeName:     g.display_name,
            enrolledCount: parseInt(s.enrolled_count) || 0,
            capacity:      parseInt(s.capacity)       || 0,
          };
        }
      });
    });
  }

  // Update badge
  const badge = document.getElementById('badgeRooms');
  if (badge) {
    const active = allRooms.filter(r => r.status !== 'archived').length;
    badge.textContent = active || '0';
  }

  const activeRooms   = allRooms.filter(r => r.status !== 'archived');
  const archivedRooms = allRooms.filter(r => r.status === 'archived');

  // Match by room number string (sections.room stores the number as text)
  const roomCards = activeRooms.map(r => buildRoomCard(r, sectionMap[String(r.number)] || null)).join('');

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Room Management</h1>
      <p>Create and manage classrooms · track section assignments</p>
    </div>
    <button class="btn btn-primary" onclick="openAddRoom()">
      <i class="fa-solid fa-plus"></i> Add Room
    </button>
  </div>

  <!-- Stats strip -->
  <div class="room-stats-strip">
    <div class="room-stat-pill">
      <i class="fa-solid fa-building"></i>
      <span><strong id="rStatTotal">${activeRooms.length}</strong> Rooms</span>
    </div>
    <div class="room-stat-pill room-stat-vacant">
      <i class="fa-solid fa-door-open"></i>
      <span><strong id="rStatVacant">${activeRooms.filter(r => !sectionMap[r.id]).length}</strong> Vacant</span>
    </div>
    <div class="room-stat-pill room-stat-occupied">
      <i class="fa-solid fa-door-closed"></i>
      <span><strong id="rStatOccupied">${activeRooms.filter(r => !!sectionMap[r.id]).length}</strong> Occupied</span>
    </div>
  </div>

  <!-- Active rooms grid -->
  <div class="room-grid" id="roomGrid">
    ${roomCards || `<div class="room-empty-state">
      <i class="fa-solid fa-building"></i>
      <p>No rooms yet. Click <strong>Add Room</strong> to create your first classroom.</p>
    </div>`}
  </div>

  <!-- Archived rooms panel -->
  ${archivedRooms.length ? buildArchivedRoomsPanel(archivedRooms) : ''}`;

  // Wire cabinet toggles (archived rooms panel)
  document.querySelectorAll('.cabinet-header').forEach(h => {
    h.addEventListener('click', () => {
      const body    = h.nextElementSibling;
      const chevron = h.querySelector('.cabinet-chevron');
      if (!body) return;
      const open = body.style.display !== 'none';
      body.style.display = open ? 'none' : 'block';
      chevron.classList.toggle('open', !open);
    });
  });
}

/* ═══ ROOM CARD ══════════════════════════════════════════════ */
function buildRoomCard(room, assignment) {
  const isOccupied = !!assignment;

  // Effective capacity: use the assigned section's capacity (set by admin in Section Mgmt).
  // When vacant, room has no capacity yet — it's determined at assignment time.
  const effectiveCap = isOccupied ? (assignment.capacity || 0) : 0;

  const pct = isOccupied && effectiveCap > 0
    ? Math.round((assignment.enrolledCount / effectiveCap) * 100)
    : 0;
  const barCls = pct >= 100 ? 'full' : pct >= 80 ? 'warn' : '';

  const statusBadge = isOccupied
    ? `<span class="badge badge-closed room-status-badge room-occupied-badge"><i class="fa-solid fa-door-closed"></i> Occupied</span>`
    : `<span class="badge badge-open room-status-badge room-vacant-badge"><i class="fa-solid fa-door-open"></i> Vacant</span>`;

  const assignmentInfo = isOccupied ? `
    <div class="room-assignment-info">
      <div class="room-assign-row">
        <i class="fa-solid fa-chalkboard"></i>
        <span class="room-assign-section">${escHTML(assignment.sectionName)}</span>
        <span class="room-assign-grade">${escHTML(assignment.gradeName)}</span>
      </div>
      <div class="room-capacity-bar" style="margin-top:8px">
        <div class="room-cap-fill ${barCls}" style="width:${Math.min(pct,100)}%"></div>
      </div>
      <div class="room-cap-legend">
        <span>${assignment.enrolledCount} enrolled</span>
        <span>${pct}% of section capacity</span>
      </div>
    </div>` : `
    <div class="room-vacant-placeholder">
      <i class="fa-solid fa-hourglass"></i>
      <span>Awaiting assignment by Registrar</span>
    </div>`;

  // Capacity meta line — shows section capacity when occupied, or a pending note when vacant
  const capMetaHTML = isOccupied
    ? `<div class="room-cap-meta">
         <i class="fa-solid fa-users"></i>
         <span>Max Capacity: <strong>${effectiveCap}</strong></span>
         <span class="room-cap-source-tag"><i class="fa-solid fa-link" style="font-size:9px"></i> from section</span>
       </div>`
    : `<div class="room-cap-meta room-cap-meta--pending">
         <i class="fa-solid fa-users" style="color:var(--text-muted)"></i>
         <span style="color:var(--text-muted)">Capacity: <em>set by section assignment</em></span>
       </div>`;

  // Fill bar against effective capacity
  const roomBarCls = pct >= 100 ? 'full' : pct >= 80 ? 'warn' : '';

  return `
  <div class="room-card" id="roomCard-${room.id}">
    <div class="room-card-header">
      <div class="room-number-display">
        <i class="fa-solid fa-building room-card-icon"></i>
        <span class="room-number-text">Room ${escHTML(String(room.number))}</span>
      </div>
      ${statusBadge}
    </div>

    ${capMetaHTML}

    <!-- Room fill progress (against section capacity) -->
    <div class="room-fill-track" title="${pct}% of section capacity used">
      <div class="room-fill-bar ${roomBarCls}" style="width:${Math.min(pct,100)}%"></div>
    </div>
    <div class="room-fill-legend">
      <span>${isOccupied ? assignment.enrolledCount + ' students' : '0 students'}</span>
      <span>${pct}% full</span>
    </div>

    ${assignmentInfo}

    <div class="room-card-footer">
      ${isOccupied ? `
      <button class="btn btn-xs btn-ghost room-unassign-btn"
        title="Unassign section from this room"
        onclick="confirmUnassignRoom(${assignment.sectionId},'${escHTML(assignment.sectionName)}','${escHTML(String(room.number))}')">
        <i class="fa-solid fa-link-slash"></i> Clear
      </button>` : ''}
      <button class="btn btn-xs btn-ghost room-archive-btn"
        onclick="confirmArchiveRoom(${room.id},'${escHTML(String(room.number))}', ${isOccupied})"
        ${isOccupied ? 'disabled title="Cannot archive — room is occupied"' : 'title="Archive this room"'}>
        <i class="fa-solid fa-box-archive"></i> Archive
      </button>
    </div>
  </div>`;
}

/* ═══ ARCHIVED ROOMS PANEL ═══════════════════════════════════ */
function buildArchivedRoomsPanel(archivedRooms) {
  const rows = archivedRooms.map(r => `
    <tr>
      <td class="td-primary">Room ${escHTML(String(r.number))}</td>
      <td class="td-mono">${r.capacity}</td>
      <td><span class="badge badge-archived">Archived</span></td>
      <td>
        <div style="display:flex;gap:6px;align-items:center">
          <button class="btn-icon btn-icon-success" title="Restore room"
            onclick="restoreRoom(${r.id})">
            <i class="fa-solid fa-rotate-left"></i> Restore
          </button>
          <button class="btn-icon btn-icon-danger" title="Permanently delete room"
            onclick="confirmDeleteRoom(${r.id},'${escHTML(String(r.number))}')">
            <i class="fa-solid fa-trash"></i> Delete
          </button>
        </div>
      </td>
    </tr>`).join('');

  return `
  <div class="grade-cabinet" style="margin-top:24px;border:1.5px dashed var(--border);opacity:0.9">
    <div class="cabinet-header" style="background:var(--surface-alt)">
      <span class="cabinet-grade-tag" style="background:var(--text-muted);color:#fff">ARCHIVED</span>
      <span class="cabinet-title" style="color:var(--text-muted)">Archived Rooms</span>
      <span class="cabinet-count">${archivedRooms.length} room${archivedRooms.length !== 1 ? 's' : ''}</span>
      <i class="fa-solid fa-chevron-right cabinet-chevron"></i>
    </div>
    <div class="cabinet-body" style="display:none">
      <div class="table-wrap" style="margin:0">
        <table>
          <thead><tr><th>Room</th><th>Capacity</th><th>Status</th><th>Actions</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
      </div>
    </div>
  </div>`;
}

/* ═══ ADD ROOM MODAL ═════════════════════════════════════════ */
function openAddRoom() {
  openModal('Add New Room',
    `<div class="room-form-intro">
       <i class="fa-solid fa-building"></i>
       <span>Enter the room number. Capacity will be automatically set from the assigned section's max capacity once a section is assigned by the Registrar.</span>
     </div>

     <div style="margin-top:16px">
       <div class="form-group">
         <label>Room Number <span style="color:var(--danger)">*</span></label>
         <div class="room-input-wrap">
           <i class="fa-solid fa-building room-input-icon"></i>
           <input type="text" id="roomNumber" placeholder="e.g. 101"
             inputmode="numeric"
             maxlength="6"
             oninput="this.value=this.value.replace(/[^0-9]/g,'').slice(0,6);updateRoomCapPreview()"
             autocomplete="off"/>
         </div>
         <div class="room-input-hint">Numbers only · no letters, spaces, or symbols</div>
       </div>
     </div>

     <div class="room-cap-auto-notice" style="display:flex;align-items:flex-start;gap:10px;padding:12px 14px;background:var(--surface-alt);border:1px solid var(--border);border-radius:8px;margin-top:12px;font-size:12px;color:var(--text-secondary)">
       <i class="fa-solid fa-circle-info" style="color:var(--primary);margin-top:2px;flex-shrink:0"></i>
       <span>Room capacity is <strong>not set manually</strong>. Once a section is assigned to this room, the room will automatically reflect that section's max student capacity.</span>
     </div>

     <div class="room-preview-card" id="roomPreviewCard" style="display:none">
       <div class="room-preview-label">Preview</div>
       <div class="room-preview-body">
         <div class="room-preview-number" id="previewRoomNum">Room —</div>
         <div class="room-preview-cap" id="previewRoomCap"><i class="fa-solid fa-users"></i> Capacity from section</div>
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-success" id="confirmRoomBtn" onclick="submitAddRoom()">
       <i class="fa-solid fa-plus"></i> Create Room
     </button>`
  );

  // Live preview on typing
  setTimeout(() => {
    document.getElementById('roomNumber')?.addEventListener('input', updateRoomCapPreview);
  }, 50);
}

function updateRoomCapPreview() {
  const num  = (document.getElementById('roomNumber')?.value || '').trim();
  const card = document.getElementById('roomPreviewCard');
  const numEl = document.getElementById('previewRoomNum');
  if (!card) return;
  if (num) {
    card.style.display = 'flex';
    if (numEl) numEl.textContent = `Room ${num}`;
  } else {
    card.style.display = 'none';
  }
}

async function submitAddRoom() {
  const numRaw = (document.getElementById('roomNumber')?.value || '').replace(/[^0-9]/g, '');

  if (!numRaw) return toast('Room number is required.', 'warn');

  const btn = document.getElementById('confirmRoomBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Saving…'; }

  // Capacity is 0 — it will be auto-set from the assigned section's capacity
  const res = await api('add_room', { number: numRaw, capacity: 0 });

  if (!res.success) {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-plus"></i> Create Room'; }
    return toast(res.message || 'Failed to create room.', 'error');
  }

  toast(res.message || `Room ${numRaw} created successfully.`, 'success');
  closeModal();
  activateModule('rooms');
}

/* ═══ ARCHIVE / RESTORE ══════════════════════════════════════ */
function confirmArchiveRoom(id, number, isOccupied) {
  if (isOccupied) {
    return toast('Cannot archive — this room is currently occupied by a section.', 'error');
  }
  openModal('Archive Room',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
       <p>Archive <strong>Room ${escHTML(number)}</strong>?</p>
       <p class="confirm-sub">The room will be hidden from active lists. You can restore it at any time.</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-warning" onclick="doArchiveRoom(${id})">
       <i class="fa-solid fa-box-archive"></i> Archive Room
     </button>`
  );
}

async function doArchiveRoom(id) {
  const res = await api('archive_room', { id });
  if (!res.success) return toast(res.message || 'Failed to archive room.', 'error');
  toast(res.message || 'Room archived.', 'success');
  closeModal();
  activateModule('rooms');
}

async function restoreRoom(id) {
  const res = await api('restore_room', { id });
  if (!res.success) return toast(res.message || 'Failed to restore room.', 'error');
  toast(res.message || 'Room restored.', 'success');
  activateModule('rooms');
}

function confirmDeleteRoom(id, number) {
  openModal('Delete Room',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-danger"><i class="fa-solid fa-trash"></i></div>
       <p>Delete <strong>Room ${escHTML(String(number))}</strong>?</p>
       <p class="confirm-sub">This action cannot be undone.</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-danger" id="confirmDeleteRoomBtn" onclick="doDeleteRoom(${id})">
       <i class="fa-solid fa-trash"></i> Delete
     </button>`
  );
}

async function doDeleteRoom(id) {
  const btn = document.getElementById('confirmDeleteRoomBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Deleting…'; }
  const res = await api('delete_room', { id });
  if (res.success) {
    toast(res.message || 'Room permanently deleted.', 'success');
    closeModal();
    activateModule('rooms');
  } else {
    toast(res.message || 'Failed to delete room.', 'error');
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-trash"></i> Delete'; }
  }
}

/* ═══ UNASSIGN ROOM ══════════════════════════════════════════ */
function confirmUnassignRoom(sectionId, sectionName, roomNumber) {
  openModal('Clear Room Assignment',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-link-slash"></i></div>
       <p>Unassign <strong>${escHTML(sectionName)}</strong> from this room?</p>
       <p class="confirm-sub">Unassigning this room will remove the section from this room. Only do this if there are situations where there are bugs in the room assignment or Registrar has requested for room changing.</p>
       <div class="unassign-notice">
         <i class="fa-solid fa-circle-info"></i>
         <span>This will <strong>Clear</strong> any schedule. A room will be be selected on the registrar's end.</span>
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-warning" id="confirmUnassignBtn" onclick="doUnassignRoom(${sectionId},'${escHTML(sectionName)}')">
       <i class="fa-solid fa-link-slash"></i> Unassign Room
     </button>`
  );
}

async function doUnassignRoom(sectionId, sectionName) {
  const btn = document.getElementById('confirmUnassignBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Unassigning…'; }

  const res = await api('unassign_room', { section_id: sectionId });

  if (!res.success) {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-link-slash"></i> Unassign Room'; }
    return toast(res.message || 'Failed to unassign room.', 'error');
  }

  toast(res.message || `Room unassigned from ${sectionName}.`, 'success');
  closeModal();
  activateModule('rooms');
}

/* ════════════════════════════════════════════════════════════
   AUDIT XLSX EXPORT
════════════════════════════════════════════════════════════ */

/* Inject SheetJS if not already loaded, then run callback */
function _ensureXLSX(cb) {
  if (window.XLSX) { cb(); return; }
  const s = document.createElement('script');
  s.src = 'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js';
  s.onload = cb;
  document.head.appendChild(s);
}

/* Export currently filtered audit rows */
function exportAuditXLSX() {
  _ensureXLSX(() => {
    const rows = _getAuditFiltered();
    if (!rows.length) return toast('No logs to export.', 'warn');

    const headers = ['Log ID', 'Date & Time', 'Administrator', 'Action', 'Table', 'Record ID', 'IP Address', 'Device', 'OS', 'Browser'];
    const data = rows.map(r => {
      const dev = parseUserAgent(r.user_agent || '');
      return [
        r.id,
        r.created_at,
        r.admin_name || 'System',
        r.action,
        r.table_name,
        r.record_id,
        formatIPDisplay(r.ip_address),
        dev.deviceModel || dev.deviceType || 'Desktop',
        dev.os || '—',
        dev.browser || '—',
      ];
    });

    const wb = window.XLSX.utils.book_new();
    const ws = window.XLSX.utils.aoa_to_sheet([headers, ...data]);
    ws['!cols'] = [6, 20, 20, 10, 16, 10, 16, 16, 20, 18].map(w => ({ wch: w }));
    window.XLSX.utils.book_append_sheet(wb, ws, 'Audit Logs');

    const search = _auditSearch ? `_q=${_auditSearch.replace(/\s+/g,'_')}` : '';
    const action = _auditAction ? `_${_auditAction}` : '';
    const ts     = new Date().toISOString().slice(0,10);
    window.XLSX.writeFile(wb, `audit_logs${action}${search}_${ts}.xlsx`);
    toast(`Exported ${rows.length} log${rows.length !== 1 ? 's' : ''} to .xlsx`, 'success');
  });
}

/* Export a single log entry from the detail modal */
function exportSingleAuditXLSX(logId) {
  _ensureXLSX(() => {
    const r = _auditAllRows.find(x => x.id == logId);
    if (!r) return toast('Log not found.', 'error');
    const dev = parseUserAgent(r.user_agent || '');

    const wb = window.XLSX.utils.book_new();

    // Sheet 1 — Summary
    const ws1 = window.XLSX.utils.aoa_to_sheet([
      ['Audit Log Detail'],
      [],
      ['Log ID',        `#${r.id}`],
      ['Date & Time',   r.created_at],
      ['Administrator', r.admin_name || 'System'],
      ['Action',        r.action],
      ['Table',         r.table_name],
      ['Record ID',     `#${r.record_id}`],
      ['IP Address',    formatIPDisplay(r.ip_address)],
      ['IP Note',       getIPNote(r.ip_address)],
      ['Device',        dev.deviceModel || dev.deviceType || 'Desktop'],
      ['OS',            dev.os || '—'],
      ['Browser',       dev.browser || '—'],
    ]);
    ws1['!cols'] = [{ wch: 18 }, { wch: 44 }];
    window.XLSX.utils.book_append_sheet(wb, ws1, 'Summary');

    // Sheet 2 — Changes (if any)
    try {
      const oldObj = r.old_values ? (typeof r.old_values === 'string' ? JSON.parse(r.old_values) : r.old_values) : null;
      const newObj = r.new_values ? (typeof r.new_values === 'string' ? JSON.parse(r.new_values) : r.new_values) : null;
      if (oldObj || newObj) {
        const allKeys = [...new Set([...Object.keys(oldObj || {}), ...Object.keys(newObj || {})])];
        const rows2   = [['Field', 'Before', 'After'], ...allKeys.map(k => [k, oldObj?.[k] ?? '', newObj?.[k] ?? ''])];
        const ws2     = window.XLSX.utils.aoa_to_sheet(rows2);
        ws2['!cols']  = [{ wch: 22 }, { wch: 36 }, { wch: 36 }];
        window.XLSX.utils.book_append_sheet(wb, ws2, 'Changes');
      }
    } catch (_) {}

    window.XLSX.writeFile(wb, `audit_log_${r.id}.xlsx`);
    toast(`Exported audit_log_${r.id}.xlsx`, 'success');
  });
}

/* ════════════════════════════════════════════════════════════
   CAFETERIA · STUDENT WALLET
════════════════════════════════════════════════════════════ */
let _cwSearch        = '';
let _cwGradeFilter    = 0;   // 0 = All Grades
let _cwSectionFilter  = 0;   // 0 = All Sections
let _cwRows           = [];
let _cwSectionsData   = null; // cached result of get_sections_by_grade
let _cwMaxTopup       = 0;    // cached max top-up per transaction (0 = no limit)

async function renderCafeteriaWallet(ca) {
  ca.innerHTML = `<div class="flex-center" style="height:200px"><div class="spinner"></div></div>`;

  const [walletRes, settingsRes] = await Promise.all([
    api('get_student_wallets', { grade_level_id: _cwGradeFilter, section_id: _cwSectionFilter, search: _cwSearch }),
    api('get_cafeteria_settings', {}),
  ]);

  _cwRows = walletRes.success ? walletRes.data : [];
  _cwMaxTopup = settingsRes.success ? parseFloat(settingsRes.data.max_topup_amount || 0) : 0;

  if (!_cwSectionsData) {
    const secRes = await api('get_sections_by_grade', {});
    _cwSectionsData = secRes.success ? secRes.data : {};
  }

  const totalBalance = _cwRows.reduce((sum, r) => sum + parseFloat(r.balance || 0), 0);
  const activeFilterCount = (_cwGradeFilter ? 1 : 0) + (_cwSectionFilter ? 1 : 0);

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Cafeteria · Student Wallet</h1>
      <p>Edit and top up student cafeteria balances</p>
    </div>
    <button class="btn btn-ghost" onclick="openWalletLimitModal()">
      <i class="fa-solid fa-gauge-high"></i> ${_cwMaxTopup > 0 ? `Limit: ₱${_cwMaxTopup.toFixed(2)}` : 'Set Top-up Limit'}
    </button>
  </div>

  <div class="room-stats-strip">
    <div class="room-stat-pill">
      <i class="fa-solid fa-user-graduate"></i>
      <span><strong>${_cwRows.length}</strong> Students</span>
    </div>
    <div class="room-stat-pill">
      <i class="fa-solid fa-sack-dollar"></i>
      <span><strong>₱${totalBalance.toFixed(2)}</strong> Total Balance</span>
    </div>
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-wallet"></i> Student Wallets</span>
      <div class="filter-bar">
        <div class="search-wrap">
          <i class="fa-solid fa-search"></i>
          <input type="text" id="cwSearch" placeholder="Search by student name…" value="${escHTML(_cwSearch)}"
            oninput="_cwSearch=this.value" onkeydown="if(event.key==='Enter')renderCafeteriaWallet(document.getElementById('contentArea'))"/>
        </div>
        <button class="btn btn-ghost btn-xs" onclick="openWalletFilters()" title="Advanced filters">
          <i class="fa-solid fa-sliders"></i> Filters ${activeFilterCount ? `<span class="nav-badge">${activeFilterCount}</span>` : ''}
        </button>
      </div>
    </div>

    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Student</th>
            <th>Section</th>
            <th>Grade Level</th>
            <th>Balance</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          ${_cwRows.length === 0
            ? `<tr><td colspan="5"><div class="empty-state"><i class="fa-solid fa-wallet"></i><p>No students found</p></div></td></tr>`
            : _cwRows.map(r => `
            <tr>
              <td class="td-primary">${escHTML(r.full_name)}</td>
              <td>${r.section_name ? escHTML(r.section_name) : '<span class="text-muted">Unassigned</span>'}</td>
              <td>${escHTML(r.grade_display || '—')}</td>
              <td><span class="wallet-balance ${parseFloat(r.balance) <= 0 ? 'wallet-balance-zero' : ''}">₱${parseFloat(r.balance || 0).toFixed(2)}</span></td>
              <td>
                <div style="display:flex;gap:6px;align-items:center">
                  <button class="btn-icon btn-icon-success" title="Add funds" onclick="openWalletAdjust(${r.student_id},'${escHTML(r.full_name)}','credit')">
                    <i class="fa-solid fa-plus"></i>
                  </button>
                  <button class="btn-icon btn-icon-danger" title="Deduct funds" onclick="openWalletAdjust(${r.student_id},'${escHTML(r.full_name)}','debit')">
                    <i class="fa-solid fa-minus"></i>
                  </button>
                  <button class="btn-icon" title="Transaction history" onclick="openWalletHistory(${r.student_id},'${escHTML(r.full_name)}')">
                    <i class="fa-solid fa-clock-rotate-left"></i>
                  </button>
                </div>
              </td>
            </tr>`).join('')}
        </tbody>
      </table>
    </div>
  </div>`;
}

/* ─── Advanced Filters: radio buttons for Grade + Section ─── */
function openWalletFilters() {
  const grades = Object.values(_cwSectionsData || {}).sort((a, b) => a.level - b.level);

  openModal('Filter Student Wallets',
    `<div class="form-group">
       <label>Grade Level</label>
       <div class="radio-group" id="cwFilterGradeGroup">
         <label class="radio-pill">
           <input type="radio" name="cwFilterGrade" value="0" ${_cwGradeFilter === 0 ? 'checked' : ''} onchange="_onWalletFilterGradeChange()"/>
           <span>All Grades</span>
         </label>
         ${grades.map(g => `
         <label class="radio-pill">
           <input type="radio" name="cwFilterGrade" value="${g.level}" ${_cwGradeFilter === g.level ? 'checked' : ''} onchange="_onWalletFilterGradeChange()"/>
           <span>${escHTML(g.display_name)}</span>
         </label>`).join('')}
       </div>
     </div>
     <div class="form-group">
       <label>Section</label>
       <div class="radio-group" id="cwFilterSectionGroup">
         ${_buildWalletSectionRadios(_cwGradeFilter)}
       </div>
     </div>`,
    `<button class="btn btn-ghost" onclick="clearWalletFilters()">Clear Filters</button>
     <button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-primary" onclick="applyWalletFilters()">
       <i class="fa-solid fa-filter"></i> Apply Filters
     </button>`
  );
}

function _buildWalletSectionRadios(gradeLevel) {
  const grades = Object.values(_cwSectionsData || {});
  let sections = [];
  if (gradeLevel) {
    const match = grades.find(g => g.level === gradeLevel);
    sections = match ? match.sections : [];
  } else {
    sections = grades.flatMap(g => g.sections.map(s => ({ ...s, _gradeLabel: g.display_name })));
  }

  const allOption = `
    <label class="radio-pill">
      <input type="radio" name="cwFilterSection" value="0" ${_cwSectionFilter === 0 ? 'checked' : ''}/>
      <span>All Sections</span>
    </label>`;

  if (sections.length === 0) {
    return allOption + `<p class="confirm-sub" style="margin:6px 0 0">No sections available${gradeLevel ? ' for this grade' : ''}.</p>`;
  }

  return allOption + sections.map(s => `
    <label class="radio-pill">
      <input type="radio" name="cwFilterSection" value="${s.id}" ${_cwSectionFilter === s.id ? 'checked' : ''}/>
      <span>${escHTML(s.name)}${s._gradeLabel ? ` <small>(${escHTML(s._gradeLabel)})</small>` : ''}</span>
    </label>`).join('');
}

function _onWalletFilterGradeChange() {
  const selected = document.querySelector('input[name="cwFilterGrade"]:checked');
  const gradeLevel = selected ? parseInt(selected.value) : 0;
  document.getElementById('cwFilterSectionGroup').innerHTML = _buildWalletSectionRadios(gradeLevel);
}

function applyWalletFilters() {
  const gradeEl   = document.querySelector('input[name="cwFilterGrade"]:checked');
  const sectionEl = document.querySelector('input[name="cwFilterSection"]:checked');
  _cwGradeFilter   = gradeEl ? parseInt(gradeEl.value) : 0;
  _cwSectionFilter = sectionEl ? parseInt(sectionEl.value) : 0;
  closeModal();
  renderCafeteriaWallet(document.getElementById('contentArea'));
}

function clearWalletFilters() {
  _cwGradeFilter = 0;
  _cwSectionFilter = 0;
  closeModal();
  renderCafeteriaWallet(document.getElementById('contentArea'));
}

/* ─── Max top-up per transaction (admin-configurable limit) ─── */
function openWalletLimitModal() {
  openModal('Set Top-up Limit',
    `<div class="form-group">
       <label>Maximum amount (₱) admins can add per transaction</label>
       <input type="number" id="cwLimitInput" min="0" step="0.01" value="${_cwMaxTopup > 0 ? _cwMaxTopup : ''}" placeholder="0.00 = no limit" autocomplete="off"/>
       <p class="confirm-sub" style="margin-top:6px">Leave at 0 to allow any amount. This only limits "Add Funds" — deductions are unaffected.</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-primary" id="cwLimitSaveBtn" onclick="saveWalletLimit()">
       <i class="fa-solid fa-check"></i> Save Limit
     </button>`
  );
}

async function saveWalletLimit() {
  const val = parseFloat(document.getElementById('cwLimitInput')?.value || '0');
  if (isNaN(val) || val < 0) return toast('Enter a valid limit.', 'warn');

  const btn = document.getElementById('cwLimitSaveBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Saving…'; }

  const res = await api('update_cafeteria_settings', { max_topup_amount: val });

  if (!res.success) {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-check"></i> Save Limit'; }
    return toast(res.message || 'Failed to save limit.', 'error');
  }

  _cwMaxTopup = val;
  toast(res.message || 'Limit updated.', 'success');
  closeModal();
  renderCafeteriaWallet(document.getElementById('contentArea'));
}

function openWalletAdjust(studentId, name, type) {
  const isCredit = type === 'credit';
  const limitHint = isCredit && _cwMaxTopup > 0
    ? `<p class="confirm-sub" style="margin-top:-6px">Maximum ₱${_cwMaxTopup.toFixed(2)} per transaction.</p>` : '';

  openModal(isCredit ? 'Add Funds' : 'Deduct Funds',
    `<div class="form-group">
       <label>Student</label>
       <input type="text" value="${escHTML(name)}" disabled/>
     </div>
     <div class="form-group">
       <label>Amount (₱) <span style="color:var(--danger)">*</span></label>
       <input type="number" id="cwAmount" min="0.01" ${isCredit && _cwMaxTopup > 0 ? `max="${_cwMaxTopup}"` : ''} step="0.01" placeholder="0.00" autocomplete="off"/>
       ${limitHint}
     </div>
     <div class="form-group">
       <label>Note (optional)</label>
       <input type="text" id="cwNote" placeholder="e.g. Weekly allowance top-up" maxlength="255" autocomplete="off"/>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn ${isCredit ? 'btn-success' : 'btn-danger'}" id="cwSubmitBtn" onclick="submitWalletAdjust(${studentId},'${type}')">
       <i class="fa-solid ${isCredit ? 'fa-plus' : 'fa-minus'}"></i> ${isCredit ? 'Add Funds' : 'Deduct Funds'}
     </button>`
  );
}

async function submitWalletAdjust(studentId, type) {
  const amount = parseFloat(document.getElementById('cwAmount')?.value || '0');
  const note   = document.getElementById('cwNote')?.value || '';

  if (!amount || amount <= 0) return toast('Enter a valid amount.', 'warn');
  if (type === 'credit' && _cwMaxTopup > 0 && amount > _cwMaxTopup) {
    return toast(`Amount exceeds the ₱${_cwMaxTopup.toFixed(2)} top-up limit.`, 'warn');
  }

  const btn = document.getElementById('cwSubmitBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Saving…'; }

  const res = await api('adjust_student_wallet', { student_id: studentId, type, amount, note });

  if (!res.success) {
    if (btn) { btn.disabled = false; btn.innerHTML = type === 'credit' ? '<i class="fa-solid fa-plus"></i> Add Funds' : '<i class="fa-solid fa-minus"></i> Deduct Funds'; }
    return toast(res.message || 'Failed to update wallet.', 'error');
  }

  toast(res.message || 'Wallet updated.', 'success');
  closeModal();
  renderCafeteriaWallet(document.getElementById('contentArea'));
}

async function openWalletHistory(studentId, name) {
  openModal(`Transaction History — ${name}`,
    `<div class="flex-center" style="height:120px"><div class="spinner"></div></div>`, '', true);

  const res = await api('get_wallet_transactions', { student_id: studentId });
  const rows = res.success ? res.data : [];

  const body = rows.length === 0
    ? `<div class="empty-state"><i class="fa-solid fa-clock-rotate-left"></i><p>No transactions yet</p></div>`
    : `<div class="table-wrap" style="margin:0">
         <table>
           <thead><tr><th>Date</th><th>Type</th><th>Amount</th><th>Balance After</th><th>Note</th><th>By</th></tr></thead>
           <tbody>
             ${rows.map(t => `
             <tr>
               <td class="td-mono" style="white-space:nowrap">${escHTML(t.created_at)}</td>
               <td>${t.type === 'credit'
                    ? '<span class="badge badge-active badge-dot">Credit</span>'
                    : '<span class="badge badge-inactive">Debit</span>'}</td>
               <td class="wallet-balance">${t.type === 'credit' ? '+' : '-'}₱${parseFloat(t.amount).toFixed(2)}</td>
               <td class="td-mono">₱${parseFloat(t.balance_after).toFixed(2)}</td>
               <td>${escHTML(t.note || '—')}</td>
               <td>${escHTML(t.admin_name || 'System')}</td>
             </tr>`).join('')}
           </tbody>
         </table>
       </div>`;

  document.getElementById('modalBody').innerHTML = body;
  document.getElementById('modalFooter').innerHTML = `<button class="btn btn-ghost" onclick="closeModal()">Close</button>`;
}

/* ════════════════════════════════════════════════════════════
   CAFETERIA · FOOD MENU
════════════════════════════════════════════════════════════ */
let _cmFilterMode = 'active';
let _cmRows = [];

async function renderCafeteriaMenu(ca, filterMode = null) {
  if (filterMode !== null) _cmFilterMode = filterMode;

  ca.innerHTML = `<div class="flex-center" style="height:200px"><div class="spinner"></div></div>`;

  const includeArchived = (_cmFilterMode === 'all' || _cmFilterMode === 'archived') ? '1' : '0';
  const res = await api('get_cafeteria_products', { include_archived: includeArchived });
  let rows = res.success ? res.data : [];

  if (_cmFilterMode === 'active')   rows = rows.filter(r => r.status === 'active');
  if (_cmFilterMode === 'archived') rows = rows.filter(r => r.status === 'archived');
  _cmRows = rows;

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Cafeteria · Food Menu</h1>
      <p>Add new products and set their prices</p>
    </div>
    <button class="btn btn-primary" onclick="openAddFoodItem()">
      <i class="fa-solid fa-plus"></i> Add Product
    </button>
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-bowl-food"></i> Menu Items</span>
      <div class="filter-bar">
        <select id="cmFilter" onchange="renderCafeteriaMenu(document.getElementById('contentArea'), this.value)">
          <option value="active"   ${_cmFilterMode==='active'  ?'selected':''}>Active</option>
          <option value="archived" ${_cmFilterMode==='archived'?'selected':''}>Archived</option>
          <option value="all"      ${_cmFilterMode==='all'     ?'selected':''}>All</option>
        </select>
      </div>
    </div>

    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Product</th>
            <th>Category</th>
            <th>Price</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          ${rows.length === 0
            ? `<tr><td colspan="5"><div class="empty-state"><i class="fa-solid fa-bowl-food"></i><p>No menu items found</p></div></td></tr>`
            : rows.map(r => `
            <tr>
              <td class="td-primary">${escHTML(r.name)}</td>
              <td><span class="cat-tag cat-tag-${escHTML(r.category)}">${escHTML(r.category)}</span></td>
              <td class="td-mono">₱${parseFloat(r.price).toFixed(2)}</td>
              <td>${r.status === 'archived'
                    ? '<span class="badge badge-archived">Archived</span>'
                    : '<span class="badge badge-active badge-dot">Active</span>'}</td>
              <td>
                <div style="display:flex;gap:6px;align-items:center">
                  ${r.status === 'active' ? `
                    <button class="btn-icon" title="Edit" onclick='openEditFoodItem(${r.id},${JSON.stringify(r.name)},${JSON.stringify(r.category)},${r.price})'>
                      <i class="fa-solid fa-pen"></i>
                    </button>
                    <button class="btn-icon btn-icon-danger" title="Archive" onclick="confirmArchiveFoodItem(${r.id},'${escHTML(r.name)}')">
                      <i class="fa-solid fa-box-archive"></i>
                    </button>` : `
                    <button class="btn-icon btn-icon-success" title="Restore" onclick="restoreFoodItem(${r.id})">
                      <i class="fa-solid fa-rotate-left"></i>
                    </button>
                    <button class="btn-icon btn-icon-danger" title="Delete permanently" onclick="confirmDeleteFoodItem(${r.id},'${escHTML(r.name)}')">
                      <i class="fa-solid fa-trash"></i>
                    </button>`}
                </div>
              </td>
            </tr>`).join('')}
        </tbody>
      </table>
    </div>
  </div>`;
}

function _foodFormHTML(name = '', category = 'meal', price = '') {
  return `
    <div class="form-group">
      <label>Product Name <span style="color:var(--danger)">*</span></label>
      <input type="text" id="cmName" value="${escHTML(name)}" placeholder="e.g. Chicken Adobo Rice Meal" maxlength="150" autocomplete="off"/>
    </div>
    <div class="form-group">
      <label>Category</label>
      <select id="cmCategory">
        <option value="meal"  ${category==='meal' ?'selected':''}>Meal</option>
        <option value="snack" ${category==='snack'?'selected':''}>Snack</option>
        <option value="drink" ${category==='drink'?'selected':''}>Drink</option>
        <option value="other" ${category==='other'?'selected':''}>Other</option>
      </select>
    </div>
    <div class="form-group">
      <label>Price (₱) <span style="color:var(--danger)">*</span></label>
      <input type="number" id="cmPrice" min="0" step="0.01" value="${price}" placeholder="0.00" autocomplete="off"/>
    </div>`;
}

function openAddFoodItem() {
  openModal('Add Menu Product', _foodFormHTML(),
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-success" id="cmSubmitBtn" onclick="submitAddFoodItem()">
       <i class="fa-solid fa-plus"></i> Add Product
     </button>`
  );
}

async function submitAddFoodItem() {
  const name     = document.getElementById('cmName')?.value.trim() || '';
  const category = document.getElementById('cmCategory')?.value || 'other';
  const price    = document.getElementById('cmPrice')?.value || '0';

  if (!name) return toast('Product name is required.', 'warn');
  if (parseFloat(price) < 0) return toast('Price cannot be negative.', 'warn');

  const btn = document.getElementById('cmSubmitBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Saving…'; }

  const res = await api('add_cafeteria_product', { name, category, price });

  if (!res.success) {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-plus"></i> Add Product'; }
    return toast(res.message || 'Failed to add product.', 'error');
  }

  toast(res.message || 'Product added.', 'success');
  closeModal();
  renderCafeteriaMenu(document.getElementById('contentArea'));
}

function openEditFoodItem(id, name, category, price) {
  openModal('Edit Menu Product', _foodFormHTML(name, category, price),
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-primary" id="cmSubmitBtn" onclick="submitEditFoodItem(${id})">
       <i class="fa-solid fa-check"></i> Save Changes
     </button>`
  );
}

async function submitEditFoodItem(id) {
  const name     = document.getElementById('cmName')?.value.trim() || '';
  const category = document.getElementById('cmCategory')?.value || 'other';
  const price    = document.getElementById('cmPrice')?.value || '0';

  if (!name) return toast('Product name is required.', 'warn');
  if (parseFloat(price) < 0) return toast('Price cannot be negative.', 'warn');

  const btn = document.getElementById('cmSubmitBtn');
  if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i> Saving…'; }

  const res = await api('update_cafeteria_product', { id, name, category, price });

  if (!res.success) {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-check"></i> Save Changes'; }
    return toast(res.message || 'Failed to update product.', 'error');
  }

  toast(res.message || 'Product updated.', 'success');
  closeModal();
  renderCafeteriaMenu(document.getElementById('contentArea'));
}

function confirmArchiveFoodItem(id, name) {
  openModal('Archive Product',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-warn"><i class="fa-solid fa-box-archive"></i></div>
       <p>Archive <strong>${escHTML(name)}</strong>?</p>
       <p class="confirm-sub">It will be hidden from the active menu. You can restore it later.</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-warning" onclick="doArchiveFoodItem(${id})">
       <i class="fa-solid fa-box-archive"></i> Archive
     </button>`
  );
}

async function doArchiveFoodItem(id) {
  const res = await api('archive_cafeteria_product', { id });
  if (!res.success) return toast(res.message || 'Failed to archive product.', 'error');
  toast(res.message || 'Product archived.', 'success');
  closeModal();
  renderCafeteriaMenu(document.getElementById('contentArea'));
}

async function restoreFoodItem(id) {
  const res = await api('restore_cafeteria_product', { id });
  if (!res.success) return toast(res.message || 'Failed to restore product.', 'error');
  toast(res.message || 'Product restored.', 'success');
  renderCafeteriaMenu(document.getElementById('contentArea'));
}

function confirmDeleteFoodItem(id, name) {
  openModal('Delete Product',
    `<div class="confirm-body">
       <div class="confirm-icon confirm-icon-danger"><i class="fa-solid fa-trash"></i></div>
       <p>Permanently delete <strong>${escHTML(name)}</strong>?</p>
       <p class="confirm-sub">This action cannot be undone.</p>
     </div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Cancel</button>
     <button class="btn btn-danger" onclick="doDeleteFoodItem(${id})">
       <i class="fa-solid fa-trash"></i> Delete
     </button>`
  );
}

async function doDeleteFoodItem(id) {
  const res = await api('delete_cafeteria_product', { id });
  if (!res.success) return toast(res.message || 'Failed to delete product.', 'error');
  toast(res.message || 'Product deleted.', 'success');
  closeModal();
  renderCafeteriaMenu(document.getElementById('contentArea'));
}

/* ════════════════════════════════════════════════════════════
   CAFETERIA · INVENTORY
════════════════════════════════════════════════════════════ */
async function renderCafeteriaInventory(ca) {
  ca.innerHTML = `<div class="flex-center" style="height:200px"><div class="spinner"></div></div>`;

  const res = await api('get_cafeteria_inventory');
  const rows = res.success ? res.data : [];
  const lowStockCount = rows.filter(r => parseInt(r.quantity) <= parseInt(r.low_stock_threshold)).length;

  ca.innerHTML = `
  <div class="page-header">
    <div class="page-title-wrap">
      <h1>Cafeteria · Inventory</h1>
      <p>Set stock quantities for menu products (not raw ingredients)</p>
    </div>
  </div>

  <div class="room-stats-strip">
    <div class="room-stat-pill">
      <i class="fa-solid fa-boxes-stacked"></i>
      <span><strong>${rows.length}</strong> Products</span>
    </div>
    <div class="room-stat-pill room-stat-vacant">
      <i class="fa-solid fa-triangle-exclamation"></i>
      <span><strong>${lowStockCount}</strong> Low Stock</span>
    </div>
  </div>

  <div class="panel">
    <div class="panel-header">
      <span class="panel-title"><i class="fa-solid fa-boxes-stacked"></i> Stock Levels</span>
    </div>

    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Product</th>
            <th>Category</th>
            <th>Quantity</th>
            <th>Low Stock Alert At</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          ${rows.length === 0
            ? `<tr><td colspan="6"><div class="empty-state"><i class="fa-solid fa-boxes-stacked"></i><p>No products in the menu yet</p></div></td></tr>`
            : rows.map(r => `
            <tr data-product="${r.product_id}">
              <td class="td-primary">${escHTML(r.name)}</td>
              <td><span class="cat-tag cat-tag-${escHTML(r.category)}">${escHTML(r.category)}</span></td>
              <td><input type="number" min="0" class="stock-input" id="invQty-${r.product_id}" value="${r.quantity}"/></td>
              <td><input type="number" min="0" class="stock-input" id="invThresh-${r.product_id}" value="${r.low_stock_threshold}"/></td>
              <td>${parseInt(r.quantity) <= parseInt(r.low_stock_threshold)
                    ? '<span class="low-stock-tag"><i class="fa-solid fa-triangle-exclamation"></i> Low Stock</span>'
                    : '<span class="badge badge-active badge-dot">In Stock</span>'}</td>
              <td>
                <button class="btn btn-xs btn-primary" onclick="saveInventoryRow(${r.product_id},'${escHTML(r.name)}')">
                  <i class="fa-solid fa-check"></i> Save
                </button>
              </td>
            </tr>`).join('')}
        </tbody>
      </table>
    </div>
  </div>`;
}

async function saveInventoryRow(productId, name) {
  const qtyEl    = document.getElementById(`invQty-${productId}`);
  const threshEl = document.getElementById(`invThresh-${productId}`);
  const quantity  = parseInt(qtyEl?.value ?? '0');
  const threshold = parseInt(threshEl?.value ?? '10');

  if (isNaN(quantity) || quantity < 0) return toast('Enter a valid quantity.', 'warn');

  const res = await api('update_cafeteria_inventory', { product_id: productId, quantity, low_stock_threshold: isNaN(threshold) ? 10 : threshold });
  if (!res.success) return toast(res.message || 'Failed to update stock.', 'error');

  toast(res.message || `${name} stock updated.`, 'success');
  renderCafeteriaInventory(document.getElementById('contentArea'));
}

/* ════════════════════════════════════════════════════════════
   BOOT
════════════════════════════════════════════════════════════ */
window.addEventListener('DOMContentLoaded', () => {
  // Wire theme toggle button
  const themeBtn = document.getElementById('themeToggleBtn');
  if (themeBtn) themeBtn.addEventListener('click', toggleTheme);
  // Set initial label to match saved theme
  updateThemeLabel(document.documentElement.getAttribute('data-theme') || 'dark');

  runLoadingSequence();
});