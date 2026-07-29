<?php
/**
 * CashierManagement.php
 *
 * Handles the Cashier Portal for proof-of-payment review.
 *
 * Responsibilities:
 *   - Page render: list all payment_submissions with student details
 *   - Mark submission as "under_review" when cashier opens it (viewed)
 *   - API: approve  → updates payment status + conditionally updates enrollment to 'enrolled'
 *   - API: decline  → updates payment status to 'rejected', stores reason
 *   - API: onsite   → records a cash payment, enrolls student directly
 *   - API: lookup   → find student by ID or LRN for on-site form
 *   - Page render:  Transaction History tab
 *
 * Session requirement: $_SESSION['cashier_id']  (integer FK → cashiers.id)
 *                      $_SESSION['user_id']      (integer FK → users.id)
 */

session_start();

// ── Show errors in development so a blank page becomes a real error message ──
if (defined('APP_ENV') && APP_ENV === 'development') {
    ini_set('display_errors', 1);
    ini_set('display_startup_errors', 1);
    error_reporting(E_ALL);
}

require_once __DIR__ . '/config/db.php';   // provides $pdo (PDO instance)
require_once __DIR__ . '/PaymentMailer.php';             // email notifications

/* ============================================================
   AUTH GUARD
============================================================ */
if (empty($_SESSION['cashier_id'])) {
    if (isAjax()) {
        jsonError('Unauthenticated.', 401);
    }
    header('Location: login.html');
    exit;
}

$cashierId = (int) $_SESSION['cashier_id'];

/* ============================================================
   ROUTER — dispatch JSON API calls before any HTML output
============================================================ */
$requestUri    = strtok($_SERVER['REQUEST_URI'], '?');
$requestMethod = $_SERVER['REQUEST_METHOD'];

// Accept ?action=approve style URLs (Fix 1) or fall back to URL path routing
$action = trim($_GET['action'] ?? '') ?: basename($requestUri);

if (isAjax() || in_array($action, ['approve', 'decline', 'onsite', 'payment-due', 'lookup', 'suggest', 'logout', 'mark-viewed', 'topup', 'wallet-lookup'])) {
    header('Content-Type: application/json');

    switch ($action) {
        case 'approve':       handleApprove($pdo, $cashierId);      break;
        case 'decline':       handleDecline($pdo, $cashierId);      break;
        case 'onsite':        handleOnsite($pdo, $cashierId);       break;
        case 'payment-due':   handlePaymentDue($pdo, $cashierId);   break;
        case 'lookup':        handleLookup($pdo);                  break;
        case 'suggest':       handleSuggest($pdo);                 break;
        case 'mark-viewed':   handleMarkViewed($pdo, $cashierId);   break;
        case 'wallet-lookup': handleWalletLookup($pdo);             break;
        case 'topup':         handleTopup($pdo, $cashierId);        break;
        case 'logout':        handleLogout();                      break;
        default:              jsonError('Unknown endpoint.', 404);
    }
    exit;
}

/* ============================================================
   PAGE DATA — fetch for HTML render
============================================================ */
$cashierInfo  = getCashierInfo($pdo, $cashierId);
$submissions  = getPendingSubmissions($pdo);
$history      = getTransactionHistory($pdo);
$stats        = computeStats($submissions);
$topupHistory = getTopupHistory($pdo);

/* ============================================================
   HTML PAGE
============================================================ */
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cashier Portal | Payment Management</title>
    <link rel="stylesheet" href="../src/css/cashier.css">
</head>
<body>

<div class="app-shell">

    <!-- ============================
         SIDEBAR
    ============================ -->
    <aside class="sidebar">
        <div class="sidebar-logo">
            <div class="logo-img-wrap">
                <img src="../assets/images/branding/school no bg.png" alt="School Logo" id="school-logo">
            </div>
            <div class="logo-text">
                <span class="school-name" id="sidebar-school-name"><?= htmlspecialchars($cashierInfo['school_name'] ?? 'Saint Joseph') ?></span>
                <span class="portal-label">Cashier Portal</span>
            </div>
        </div>

        <div class="nav-section">
            <span class="nav-label">Navigation</span>
            <a href="cashier-pos.html" class="nav-link">
                <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/>
                    <path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/>
                </svg>
                Point of Sale Register
            </a>
            <a href="#" class="nav-link active" data-view="payments">
                <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <rect x="2" y="5" width="20" height="14" rx="2"/>
                    <path d="M2 10h20"/>
                </svg>
                Manage Payments
            </a>
            <a href="#" class="nav-link" data-view="history">
                <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <path d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                Transaction History
            </a>
            <a href="#" class="nav-link" data-view="topup">
                <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <circle cx="12" cy="12" r="9"/>
                    <path d="M12 7v10M9 9.5c0-1.1 1.3-2 3-2s3 .9 3 2-1.3 1.5-3 2-3 .9-3 2 1.3 2 3 2 3-.9 3-2"/>
                </svg>
                Student Top-Up
            </a>
        </div>

        <div class="sidebar-footer">
            <div class="cashier-info">
                <div class="cashier-avatar" id="cashier-initials"><?= htmlspecialchars(getInitials($cashierInfo['full_name'] ?? '')) ?></div>
                <div class="cashier-meta">
                    <div class="name" id="cashier-name"><?= htmlspecialchars($cashierInfo['full_name'] ?? 'Cashier') ?></div>
                    <div class="role" id="cashier-role">Cashier Desk</div>
                </div>
            </div>
            <button class="btn-logout" onclick="openLogoutModal()">
                <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                    <path d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"/>
                </svg>
                Sign Out
            </button>
        </div>
    </aside>

    <!-- ============================
         MAIN AREA
    ============================ -->
    <div class="main-area">

        <!-- Top Bar -->
        <header class="topbar">
            <div class="topbar-left">
                <h1>Proof of Payment Review</h1>
                <p id="today-date"></p>
            </div>

            <div class="topbar-right">
                <div class="search-wrap">
                    <span class="search-icon">
                        <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                            <circle cx="11" cy="11" r="8"/>
                            <path d="m21 21-4.35-4.35"/>
                        </svg>
                    </span>
                    <input
                        type="text"
                        id="live-search"
                        placeholder="Search by name or reference…"
                        oninput="liveSearch(this.value)"
                        autocomplete="off"
                    >
                </div>

                <span class="search-count" id="search-count"></span>
            </div>
        </header>

        <!-- Stats Row -->
        <div class="stats-row">
            <div class="stat-card">
                <div class="stat-icon maroon">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
                    </svg>
                </div>
                <div class="stat-info">
                    <div class="num" id="stat-pending"><?= $stats['pending'] ?></div>
                    <div class="lbl">Pending Review</div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon green">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                    </svg>
                </div>
                <div class="stat-info">
                    <div class="num" id="stat-enrolled"><?= $stats['enrolled_today'] ?></div>
                    <div class="lbl">Enrolled Today</div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon gold">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <rect x="2" y="5" width="20" height="14" rx="2"/>
                        <path d="M2 10h20"/>
                    </svg>
                </div>
                <div class="stat-info">
                    <div class="num" id="stat-total"><?= $stats['total'] ?></div>
                    <div class="lbl">Total Submissions</div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon blue">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2z"/>
                    </svg>
                </div>
                <div class="stat-info">
                    <div class="num" id="stat-onsite"><?= $stats['onsite'] ?></div>
                    <div class="lbl">On-Site Payments</div>
                </div>
            </div>
        </div>

        <!-- ============================
             MANAGE PAYMENTS VIEW
        ============================ -->
        <div id="view-payments" class="view-panel active">
            <div class="table-panel">
                <div class="table-panel-header">
                    <h2>Payment Submissions</h2>
                    <div class="legend">
                        <span class="legend-dot pending">Pending</span>
                        <span class="legend-dot onsite">On-Site</span>
                    </div>
                    <span class="history-count-label" id="payments-count-label"></span>
                </div>
                <div class="table-scroll">
                    <table>
                        <thead>
                            <tr>
                                <th>Student</th>
                                <th>Reference No.</th>
                                <th>Amount</th>
                                <th>Submitted</th>
                                <th>Type</th>
                                <th>Status</th>
                                <th>Action</th>
                            </tr>
                        </thead>
                        <tbody id="payment-tbody">
                            <?php if (empty($submissions)): ?>
                            <tr id="empty-state">
                                <td colspan="7">
                                    <div class="empty-state visible">
                                        <svg width="40" height="40" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                                            <path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"/>
                                        </svg>
                                        <p>No payment submissions yet.</p>
                                    </div>
                                </td>
                            </tr>
                            <?php else: ?>
                            <?php foreach ($submissions as $row):
                                $isEnrolled   = ($row['enrollment_status'] === 'enrolled');
                                $isRejected   = false; // rejected rows excluded from this view
                                $isVerified   = in_array($row['status'], ['verified', 'reflected_to_enrollment']);
                                $isReviewed   = $isEnrolled || $isVerified;
                                $isOnsite     = ($row['payment_channel'] === 'onsite');

                                // Display status badge
                                if ($isEnrolled || $isVerified) {
                                    $badgeClass = 'enrolled'; $badgeLabel = 'Enrolled';
                                } elseif ($row['status'] === 'under_review') {
                                    $badgeClass = 'pending'; $badgeLabel = 'Under Review';
                                } else {
                                    $badgeClass = 'pending'; $badgeLabel = 'Pending';
                                }

                                $channel   = $row['payment_channel'] ?? 'gcash';
                                $bankName  = $row['bank_name'] ?? '';
                                if ($isOnsite) {
                                    $typeClass = 'onsite'; $typeLabel = 'On-Site';
                                } elseif ($channel === 'bank_transfer') {
                                    $typeClass = 'bank-transfer';
                                    $typeLabel = 'Bank Transfer' . ($bankName ? ' – ' . htmlspecialchars($bankName) : '');
                                } else {
                                    $typeClass = 'gcash'; $typeLabel = 'GCash';
                                }

                                $displayName = htmlspecialchars(trim($row['first_name'] . ' ' . $row['last_name']));
                                $initials    = strtoupper(substr($row['first_name'], 0, 1) . substr($row['last_name'], 0, 1));
                                $amount      = $row['amount'] ? '₱' . number_format($row['amount'], 2) : '—';
                                $gradeLevel  = htmlspecialchars($row['grade_level'] ?? '');
                                $section     = htmlspecialchars($row['section_name'] ?? '');
                                $gradeSec    = trim($gradeLevel . ($section ? ' – ' . $section : ''));
                            ?>
                            <tr class="payment-row<?= $isReviewed ? ' reviewed-row' : '' ?>"
                                data-id="<?= (int) $row['id'] ?>"
                                data-student="<?= $displayName ?>"
                                data-ref="<?= htmlspecialchars($row['reference_number'] ?? '') ?>"
                                data-date="<?= htmlspecialchars($row['submitted_at'] ?? '') ?>"
                                data-img="<?= htmlspecialchars($row['proof_image_path'] ?? '') ?>"
                                data-status="<?= htmlspecialchars($isEnrolled ? 'enrolled' : $row['status']) ?>"
                                data-type="<?= htmlspecialchars($isOnsite ? 'onsite' : ($channel === 'bank_transfer' ? 'bank_transfer' : 'gcash')) ?>"
                                data-bank-name="<?= htmlspecialchars($bankName) ?>"
                                data-enrollment-status="<?= htmlspecialchars($row['enrollment_status'] ?? '') ?>"
                                data-amount="<?= htmlspecialchars($row['amount'] ?? '') ?>"
                                data-confirmed-amount="<?= htmlspecialchars($row['confirmed_amount'] ?? '') ?>"
                                data-payment-type="<?= htmlspecialchars($row['payment_type'] ?? '') ?>"
                                data-grade-section="<?= htmlspecialchars($gradeSec) ?>"
                                data-student-id="<?= (int) $row['student_id'] ?>"
                                data-lrn="<?= htmlspecialchars($row['lrn'] ?? '') ?>"
                                data-enrollment-id="<?= (int) ($row['enrollment_id'] ?? 0) ?>"
                            >
                                <td>
                                    <div class="student-cell">
                                        <div class="student-avatar"><?= $initials ?></div>
                                        <div class="student-info">
                                            <span class="student-name"><?= $displayName ?></span>
                                            <?php if ($gradeSec): ?>
                                            <span class="student-grade"><?= $gradeSec ?></span>
                                            <?php endif; ?>
                                        </div>
                                    </div>
                                </td>
                                <td><span class="ref-badge"><?= htmlspecialchars($row['reference_number'] ?? '—') ?></span></td>
                                <td class="amount-cell"><?= $amount ?></td>
                                <td class="date-cell"><?= htmlspecialchars(formatDatePH($row['submitted_at'])) ?></td>
                                <td><span class="type-badge <?= $typeClass ?>"><?= $typeLabel ?></span></td>
                                <td><span class="status-badge <?= $badgeClass ?>"><?= $badgeLabel ?></span></td>
                                <td>
                                    <?php if ($isVerified || ($isEnrolled && !$isOnsite && $row['status'] !== 'uploaded' && $row['status'] !== 'under_review')): ?>
                                        <button class="btn-review reviewed" disabled>Approved</button>
                                    <?php else: ?>
                                        <button class="btn-review" onclick="openReviewModal(this)">Review</button>
                                    <?php endif; ?>
                                </td>
                            </tr>
                            <?php endforeach; ?>
                            <?php endif; ?>
                        </tbody>
                    </table>
                    <div class="no-results" id="no-results">
                        <svg width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                            <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
                        </svg>
                        No records match your search.
                    </div>
                </div>
                <!-- Pagination for manage payments -->
                <div class="history-pagination" id="payments-pagination"></div>
            </div>
        </div><!-- /view-payments -->

        <!-- ============================
             TRANSACTION HISTORY VIEW
        ============================ -->
        <div id="view-history" class="view-panel">
            <div class="table-panel">
                <div class="table-panel-header">
                    <h2>Transaction History</h2>
                    <div class="history-header-right">
                        <!-- Status filter buttons -->
                        <div class="history-filter-group" id="history-filter-group">
                            <button class="hfilt-btn active" data-filter="all" onclick="historyFilter('all', this)">All</button>
                            <button class="hfilt-btn" data-filter="pending" onclick="historyFilter('pending', this)">Pending</button>
                            <button class="hfilt-btn approved" data-filter="approved" onclick="historyFilter('approved', this)">Approved</button>
                            <button class="hfilt-btn rejected" data-filter="rejected" onclick="historyFilter('rejected', this)">Rejected</button>
                        </div>
                        <!-- Reference number live search -->
                        <div class="search-wrap">
                            <span class="search-icon">
                                <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                                    <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
                                </svg>
                            </span>
                            <input type="text" id="history-search" placeholder="Search by name or reference no…" oninput="historySearchRef(this.value)" autocomplete="off">
                            <button class="history-search-clear" id="history-search-clear" onclick="clearHistorySearch()" title="Clear search" style="display:none;">
                                <svg width="12" height="12" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path d="M18 6L6 18M6 6l12 12"/></svg>
                            </button>
                        </div>
                        <span class="history-count-label" id="history-count-label"></span>
                    </div>
                </div>

                <!-- Accordion list — one card per approved student transaction -->
                <div id="history-accordion" class="history-accordion">
                    <?php if (empty($history)): ?>
                    <div class="history-empty">
                        <svg width="40" height="40" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                            <path d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                        </svg>
                        <p>No approved transactions yet.</p>
                    </div>
                    <?php else: ?>
                    <?php foreach ($history as $row):
                        $isOnsite    = ($row['payment_channel'] === 'onsite');
                        $isRejected  = ($row['status'] === 'rejected');
                        $badgeClass  = $isRejected ? 'declined' : 'enrolled';
                        $badgeLabel  = $isRejected ? 'Rejected' : 'Approved';
                        $hChannel  = $row['payment_channel'] ?? 'gcash';
                        $hBankName = $row['bank_name'] ?? '';
                        if ($isOnsite) {
                            $typeClass = 'onsite'; $typeLabel = 'On-Site Cash';
                        } elseif ($hChannel === 'bank_transfer') {
                            $typeClass = 'bank-transfer';
                            $typeLabel = 'Bank Transfer' . ($hBankName ? ' – ' . htmlspecialchars($hBankName) : '');
                        } else {
                            $typeClass = 'gcash'; $typeLabel = 'GCash';
                        }
                        $displayName = htmlspecialchars(trim($row['first_name'] . ' ' . $row['last_name']));
                        $initials    = strtoupper(substr($row['first_name'], 0, 1) . substr($row['last_name'], 0, 1));
                        $amount      = $row['confirmed_amount'] ?? $row['amount'];
                        $amountFmt   = $amount ? '₱' . number_format($amount, 2) : '—';
                        $gradeLevel  = htmlspecialchars($row['grade_level'] ?? '');
                        $section     = htmlspecialchars($row['section_name'] ?? '');
                        $gradeSec    = trim($gradeLevel . ($section ? ' – ' . $section : ''));
                        $lrn         = htmlspecialchars($row['lrn'] ?? '—');
                    ?>
                    <div class="hacc-item"
                        data-student="<?= $displayName ?>"
                        data-lrn="<?= htmlspecialchars($row['lrn'] ?? '') ?>"
                        data-ref="<?= htmlspecialchars($row['reference_number'] ?? '') ?>"
                        data-status="<?= htmlspecialchars($row['status']) ?>"
                    >
                        <!-- Accordion Header (always visible) -->
                        <div class="hacc-header" onclick="toggleAccordion(this)">
                            <div class="hacc-avatar"><?= $initials ?></div>
                            <div class="hacc-identity">
                                <span class="hacc-name"><?= $displayName ?></span>
                                <span class="hacc-meta">
                                    <span class="hacc-lrn">LRN: <?= $lrn ?></span>
                                    <?php if ($gradeSec): ?>
                                    <span class="hacc-sep">·</span>
                                    <span class="hacc-grade"><?= $gradeSec ?></span>
                                    <?php endif; ?>
                                </span>
                            </div>
                            <span class="status-badge <?= $badgeClass ?> hacc-badge"><?= $badgeLabel ?></span>
                            <span class="hacc-chevron">
                                <svg width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24">
                                    <path d="M6 9l6 6 6-6"/>
                                </svg>
                            </span>
                        </div>

                        <!-- Accordion Body (collapsed by default) -->
                        <div class="hacc-body">
                            <div class="hacc-details">
                                <div class="hacc-detail-col">
                                    <div class="hacc-field">
                                        <span class="hacc-field-label">Reference No.</span>
                                        <span class="hacc-field-val ref-badge"><?= htmlspecialchars($row['reference_number'] ?? '—') ?></span>
                                    </div>
                                    <div class="hacc-field">
                                        <span class="hacc-field-label">Amount</span>
                                        <span class="hacc-field-val hacc-amount"><?= $amountFmt ?></span>
                                    </div>
                                    <div class="hacc-field">
                                        <span class="hacc-field-label">Payment Type</span>
                                        <span class="hacc-field-val"><span class="type-badge <?= $typeClass ?>"><?= $typeLabel ?></span></span>
                                    </div>
                                </div>
                                <div class="hacc-detail-col">
                                    <div class="hacc-field">
                                        <span class="hacc-field-label">Submitted On</span>
                                        <span class="hacc-field-val"><?= htmlspecialchars(formatDatePH($row['submitted_at'])) ?></span>
                                    </div>
                                    <div class="hacc-field">
                                        <span class="hacc-field-label">Reviewed At</span>
                                        <span class="hacc-field-val"><?= htmlspecialchars(formatDatePH($row['reviewed_at'])) ?></span>
                                    </div>
                                    <?php if ($isRejected && !empty($row['rejection_reason'])): ?>
                                    <div class="hacc-field">
                                        <span class="hacc-field-label">Decline Reason</span>
                                        <span class="hacc-field-val hacc-reason"><?= htmlspecialchars($row['rejection_reason']) ?></span>
                                    </div>
                                    <?php endif; ?>
                                </div>
                            </div>
                            <div class="hacc-actions">
                                <button class="btn-review btn-view-history" onclick="openHistoryModalFromAccordion(this)"
                                    data-id="<?= (int) $row['id'] ?>"
                                    data-student="<?= $displayName ?>"
                                    data-lrn="<?= $lrn ?>"
                                    data-ref="<?= htmlspecialchars($row['reference_number'] ?? '') ?>"
                                    data-date="<?= htmlspecialchars($row['submitted_at'] ?? '') ?>"
                                    data-img="<?= htmlspecialchars($row['proof_image_path'] ?? '') ?>"
                                    data-status="<?= htmlspecialchars($row['status']) ?>"
                                    data-amount="<?= htmlspecialchars($row['amount'] ?? '') ?>"
                                    data-confirmed-amount="<?= htmlspecialchars($row['confirmed_amount'] ?? '') ?>"
                                    data-payment-type="<?= htmlspecialchars($row['payment_type'] ?? '') ?>"
                                    data-rejection-reason="<?= htmlspecialchars($row['rejection_reason'] ?? '') ?>"
                                    data-grade-section="<?= htmlspecialchars($gradeSec) ?>"
                                >
                                    <svg width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                                        <path d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
                                        <path d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>
                                    </svg>
                                    View Proof of Payment
                                </button>
                            </div>
                        </div>
                    </div>
                    <?php endforeach; ?>
                    <?php endif; ?>
                </div><!-- /history-accordion -->

                <!-- Pagination -->
                <div class="history-pagination" id="history-pagination"></div>

            </div>
        </div><!-- /view-history -->

        <!-- ============================
             STUDENT TOP-UP HISTORY VIEW
        ============================ -->
        <div id="view-topup" class="view-panel">
            <div class="table-panel">
                <div class="table-panel-header">
                    <h2>Student Top-Up History</h2>
                    <span class="history-count-label" id="topup-count-label"></span>
                    <div class="topup-header-actions">
                        <div class="search-wrap topup-search-wrap">
                            <span class="search-icon">
                                <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                                    <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
                                </svg>
                            </span>
                            <input type="text" id="topup-search" placeholder="Search by cashier, student, or LRN…" oninput="topupLiveSearch(this.value)" autocomplete="off">
                        </div>
                        <button class="btn-topup" onclick="openTopupModal()">
                            <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                                <path d="M12 5v14M5 12h14"/>
                            </svg>
                            New Top-Up
                        </button>
                    </div>
                </div>
                <div class="table-scroll">
                    <table>
                        <thead>
                            <tr>
                                <th>Cashier</th>
                                <th>Student</th>
                                <th>LRN</th>
                                <th>Amount</th>
                                <th>Mode of Payment</th>
                                <th>Date &amp; Time</th>
                            </tr>
                        </thead>
                        <tbody id="topup-tbody">
                            <?php if (empty($topupHistory)): ?>
                            <tr id="topup-empty-state">
                                <td colspan="6">
                                    <div class="empty-state visible">
                                        <svg width="40" height="40" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                                            <circle cx="12" cy="12" r="9"/>
                                            <path d="M12 7v10M9 9.5c0-1.1 1.3-2 3-2s3 .9 3 2-1.3 1.5-3 2-3 .9-3 2 1.3 2 3 2 3-.9 3-2"/>
                                        </svg>
                                        <p>No top-ups recorded yet.</p>
                                    </div>
                                </td>
                            </tr>
                            <?php else: ?>
                            <?php foreach ($topupHistory as $row):
                                $modeMap   = ['cash' => ['cash', 'Cash'], 'gcash' => ['gcash', 'GCash'], 'bank_transfer' => ['bank-transfer', 'Bank Transfer']];
                                [$modeClass, $modeLabel] = $modeMap[$row['payment_mode']] ?? ['gcash', ucfirst($row['payment_mode'] ?? '—')];
                                $studentName = htmlspecialchars(trim($row['student_first_name'] . ' ' . $row['student_last_name']));
                                $cashierName = htmlspecialchars($row['cashier_name'] ?? '—');
                                $lrn         = htmlspecialchars($row['lrn'] ?? '—');
                                $amountFmt   = '+₱' . number_format($row['amount'], 2);
                            ?>
                            <tr class="topup-row"
                                data-cashier="<?= $cashierName ?>"
                                data-student="<?= $studentName ?>"
                                data-lrn="<?= $lrn ?>"
                            >
                                <td><?= $cashierName ?></td>
                                <td>
                                    <div class="student-cell">
                                        <div class="student-avatar"><?= strtoupper(substr($row['student_first_name'], 0, 1) . substr($row['student_last_name'], 0, 1)) ?></div>
                                        <span class="student-name"><?= $studentName ?></span>
                                    </div>
                                </td>
                                <td><span class="ref-badge"><?= $lrn ?></span></td>
                                <td class="amount-cell is-topup-credit"><?= $amountFmt ?></td>
                                <td><span class="type-badge <?= $modeClass ?>"><?= $modeLabel ?></span></td>
                                <td class="date-cell"><?= htmlspecialchars(formatDatePH($row['created_at'])) ?></td>
                            </tr>
                            <?php endforeach; ?>
                            <?php endif; ?>
                        </tbody>
                    </table>
                    <div class="no-results" id="topup-no-results">
                        <svg width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                            <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
                        </svg>
                        No records match your search.
                    </div>
                </div>
                <div class="history-pagination" id="topup-pagination"></div>
            </div>
        </div><!-- /view-topup -->

    </div><!-- /main-area -->
</div><!-- /app-shell -->                        <label>Reference Number</label>
                        <div class="val ref" id="cal-view-ref-number">—</div>
                    </div>
                    <div class="detail-row">
                        <label>Amount Declared</label>
                        <div class="val" id="cal-view-amount">—</div>
                    </div>
                    <div class="detail-row">
                        <label>Payment Type</label>
                        <div class="val" id="cal-view-payment-type">—</div>
                    </div>
                    <div class="detail-row">
                        <label>Submitted On</label>
                        <div class="val" id="cal-view-date-time">—</div>
                    </div>
                </div>

            </div><!-- /details-pane -->

        </div><!-- /modal-body -->
    </div><!-- /modal-card -->
</div>


<!-- ============================
     REVIEW MODAL
============================ -->
<div id="reviewModal" class="modal-overlay">
    <div class="modal-card review-modal-card">
        <div class="modal-topbar">
            <h2>Review Proof of Payment</h2>
            <button class="btn-close-modal" onclick="closeModal()">&#x2715;</button>
        </div>
        <div class="modal-body review-modal-body">

            <!-- LEFT: Proof image + view button -->
            <div class="proof-column">
                <div class="proof-area" id="proof-area">
                    <div class="proof-placeholder">
                        <svg width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                            <path d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                        </svg>
                        <p>Proof of Payment</p>
                    </div>
                </div>
                <!-- View Full Image button (shown only when image exists) -->
                <a id="proof-open-btn" href="#" target="_blank" class="btn-view-proof hidden">
                    <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
                        <path d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>
                    </svg>
                    View Full Image
                </a>
            </div>

            <!-- RIGHT: Details + actions -->
            <div class="details-pane">

                <!-- Student Info Block -->
                <div class="detail-section">
                    <div class="detail-section-title">Student Information</div>
                    <div class="detail-row">
                        <label>Student Name</label>
                        <div class="val" id="modal-student-name">—</div>
                    </div>
                    <div class="detail-row">
                        <label>Grade &amp; Section</label>
                        <div class="val" id="modal-grade-section">—</div>
                    </div>
                    <div class="detail-row">
                        <label>Enrollment Status</label>
                        <div class="val" id="modal-enrollment-status">—</div>
                    </div>
                </div>

                <div class="modal-divider"></div>

                <!-- Payment Info Block -->
                <div class="detail-section">
                    <div class="detail-section-title">Payment Details</div>
                    <div class="detail-row">
                        <label>Reference Number</label>
                        <div class="val ref" id="modal-ref-number">—</div>
                    </div>
                    <div class="detail-row">
                        <label>Amount Declared</label>
                        <div class="val" id="modal-amount">—</div>
                    </div>
                    <div class="detail-row">
                        <label>Payment Type</label>
                        <div class="val" id="modal-payment-type">—</div>
                    </div>
                    <div class="detail-row">
                        <label>Submitted On</label>
                        <div class="val" id="modal-date-time">—</div>
                    </div>
                </div>

                <div class="modal-divider"></div>

                <!-- Decline reason textarea (hidden by default) -->
                <div class="decline-reason-wrap" id="decline-reason-wrap">
                    <label>Reason for Decline</label>
                    <textarea id="decline-reason" placeholder="e.g. Blurry image, incorrect amount, unreadable reference…" rows="3"></textarea>
                </div>

                <!-- Approve / Decline -->
                <div class="action-row" id="action-row">
                    <button class="btn-decline-modal" onclick="initiateDecline()">Decline Payment</button>
                    <button class="btn-approve-modal" onclick="initiateApproval()">Approve Payment</button>
                </div>

                <!-- Decline confirm row -->
                <div class="action-row decline-confirm-row" id="decline-confirm-row">
                    <button class="btn-cancel-decline" onclick="cancelDecline()">Cancel</button>
                    <button class="btn-confirm-decline" onclick="finalizeDecline()">Confirm Decline</button>
                </div>

                <!-- Countdown confirmation -->
                <div class="countdown-box" id="countdown-box">
                    <div class="headline">Auto-confirming in <span id="timer-display">10</span>s</div>
                    <div class="progress-track">
                        <div class="progress-fill" id="progress-fill"></div>
                    </div>
                    <div class="countdown-btns">
                        <button class="btn-cancel-cd" onclick="cancelApproval()">Cancel</button>
                        <button class="btn-confirm-now" onclick="forceApprove()">Confirm Now</button>
                    </div>
                </div>

            </div><!-- /details-pane -->

        </div><!-- /modal-body -->
    </div><!-- /modal-card -->
</div>


<!-- ============================
     HISTORY VIEW MODAL (read-only)
============================ -->
<div id="historyModal" class="modal-overlay">
    <div class="modal-card review-modal-card">
        <div class="modal-topbar">
            <h2>Transaction Detail</h2>
            <button class="btn-close-modal" onclick="closeHistoryModal()">&#x2715;</button>
        </div>
        <div class="modal-body review-modal-body">
            <div class="proof-column">
                <div class="proof-area" id="history-proof-area">
                    <div class="proof-placeholder">
                        <svg width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                            <path d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                        </svg>
                        <p>No image available</p>
                    </div>
                </div>
                <a id="history-proof-open-btn" href="#" target="_blank" class="btn-view-proof hidden">
                    <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
                        <path d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>
                    </svg>
                    View Full Image
                </a>
            </div>
            <div class="details-pane">
                <div class="detail-section">
                    <div class="detail-section-title">Student Information</div>
                    <div class="detail-row"><label>Student Name</label><div class="val" id="hist-student-name">—</div></div>
                    <div class="detail-row"><label>Grade &amp; Section</label><div class="val" id="hist-grade-section">—</div></div>
                    <div class="detail-row"><label>LRN</label><div class="val" id="hist-lrn">—</div></div>
                </div>
                <div class="modal-divider"></div>
                <div class="detail-section">
                    <div class="detail-section-title">Payment Details</div>
                    <div class="detail-row"><label>Reference Number</label><div class="val ref" id="hist-ref-number">—</div></div>
                    <div class="detail-row"><label>Amount</label><div class="val" id="hist-amount">—</div></div>
                    <div class="detail-row"><label>Payment Type</label><div class="val" id="hist-payment-type">—</div></div>
                    <div class="detail-row"><label>Submitted On</label><div class="val" id="hist-date-time">—</div></div>
                </div>
                <div class="modal-divider"></div>
                <div class="detail-section">
                    <div class="detail-section-title">Review Outcome</div>
                    <div class="detail-row"><label>Result</label><div class="val" id="hist-result">—</div></div>
                    <div class="detail-row" id="hist-reason-row" style="display:none"><label>Decline Reason</label><div class="val" id="hist-reason">—</div></div>
                </div>
            </div>
        </div>
    </div>
</div>


<!-- ============================
     ON-SITE PAYMENT MODAL (internal legacy use)
============================ -->
<div id="onsiteModal" class="modal-overlay">
    <div class="modal-card onsite-card">
        <div class="modal-topbar">
            <h2>Record On-Site Payment</h2>
            <button class="btn-close-modal" onclick="closeOnsiteModal()">&#x2715;</button>
        </div>
        <div class="onsite-body">
            <div class="onsite-grid">
                <div class="form-group full">
                    <label for="os-student-id">Student ID / LRN</label>
                    <div class="input-with-btn">
                        <input type="text" id="os-student-id" placeholder="Enter student ID or LRN…" autocomplete="off">
                        <button class="btn-lookup" onclick="lookupStudent()">
                            <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                                <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
                            </svg>
                            Look Up
                        </button>
                    </div>
                </div>
                <div class="form-group">
                    <label for="os-student-name">Student Name</label>
                    <input type="text" id="os-student-name" placeholder="Auto-filled or type name…" autocomplete="off">
                </div>
                <div class="form-group">
                    <label for="os-grade-section">Grade &amp; Section</label>
                    <input type="text" id="os-grade-section" placeholder="Auto-filled after lookup…" autocomplete="off">
                </div>
                <div class="form-group">
                    <label for="os-amount">Amount Paid</label>
                    <div class="peso-input-wrap">
                        <span class="peso-symbol">₱</span>
                        <input type="text" id="os-amount" placeholder="0.00" autocomplete="off" inputmode="decimal">
                    </div>
                </div>
                <div class="form-group">
                    <label for="os-fee-type">Fee Type</label>
                    <select id="os-fee-type">
                        <option value="">— Select —</option>
                        <option value="enrollment">Enrollment Fee</option>
                        <option value="tuition">Tuition</option>
                        <option value="misc">Miscellaneous</option>
                    </select>
                </div>
            </div>
            <div class="onsite-actions">
                <button class="btn-onsite-cancel" onclick="closeOnsiteModal()">Cancel</button>
                <button class="btn-onsite-submit" onclick="submitOnsitePayment()">
                    <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24">
                        <path d="M5 13l4 4L19 7"/>
                    </svg>
                    Record &amp; Enroll
                </button>
            </div>
        </div>
    </div>
</div>


<!-- ============================
     STUDENT TOP-UP MODAL
     Cashier-side wallet/token credit. Cashiers can only ADD credit —
     there is no deduct control here. The amount per transaction is
     capped by the admin-set limit (cafeteria_settings.max_topup_amount).
============================ -->
<div id="topupModal" class="modal-overlay">
    <div class="modal-card onsite-card">
        <div class="modal-topbar">
            <h2>Student ID Top-Up</h2>
            <button class="btn-close-modal" onclick="closeTopupModal()">&#x2715;</button>
        </div>
        <div class="onsite-body">

            <div class="pd-announcement-banner topup-banner">
                <div class="pd-announcement-icon">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <circle cx="12" cy="12" r="9"/>
                        <path d="M12 7v10M9 9.5c0-1.1 1.3-2 3-2s3 .9 3 2-1.3 1.5-3 2-3 .9-3 2 1.3 2 3 2 3-.9 3-2"/>
                    </svg>
                </div>
                <div class="pd-announcement-text">
                    <strong>Add credit only</strong>
                    <span id="topup-limit-note">Cashiers can only load funds onto a student's ID. Deductions are admin-only.</span>
                </div>
            </div>

            <div class="onsite-grid">
                <div class="form-group full">
                    <label for="tu-student-id">Student ID / LRN / Name / Section</label>
                    <div class="typeahead-wrap">
                        <div class="input-with-btn">
                            <input type="text" id="tu-student-id" placeholder="Type a name, LRN, ID, or section…" autocomplete="off"
                                   oninput="onTopupSearchInput(this.value)"
                                   onkeydown="onTopupSearchKeydown(event)"
                                   onfocus="onTopupSearchInput(this.value)">
                            <button class="btn-lookup" onclick="lookupTopupStudent()">
                                <svg width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                                    <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
                                </svg>
                                Look Up
                            </button>
                        </div>
                        <div id="tu-suggest-list" class="typeahead-list" hidden></div>
                    </div>
                </div>
                <div class="form-group">
                    <label for="tu-student-name">Student Name</label>
                    <input type="text" id="tu-student-name" placeholder="Auto-filled after lookup…" readonly>
                </div>
                <div class="form-group">
                    <label for="tu-grade-section">Grade &amp; Section</label>
                    <input type="text" id="tu-grade-section" placeholder="Auto-filled after lookup…" readonly>
                </div>
                <div class="form-group">
                    <label>Current Balance</label>
                    <div class="val topup-current-balance" id="tu-current-balance">—</div>
                </div>
                <div class="form-group">
                    <label for="tu-amount">Amount to Add</label>
                    <div class="peso-input-wrap">
                        <span class="peso-symbol">₱</span>
                        <input type="text" id="tu-amount" placeholder="0.00" autocomplete="off" inputmode="decimal" disabled>
                    </div>
                    <span class="topup-hint" id="tu-limit-hint"></span>
                </div>
                <div class="form-group">
                    <label for="tu-payment-mode">Mode of Payment</label>
                    <select id="tu-payment-mode">
                        <option value="">— Select —</option>
                        <option value="cash">Cash</option>
                        <option value="gcash">GCash</option>
                        <option value="bank_transfer">Bank Transfer</option>
                    </select>
                </div>
            </div>
            <div class="onsite-actions">
                <button class="btn-onsite-cancel" onclick="closeTopupModal()">Cancel</button>
                <button class="btn-onsite-submit btn-topup-submit" onclick="submitTopup()" disabled>
                    <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24">
                        <path d="M5 13l4 4L19 7"/>
                    </svg>
                    Add Credit
                </button>
            </div>
        </div>
    </div>
</div>


<!-- ============================
     SET PAYMENT DUE MODAL — ANNOUNCEMENT BROADCAST
     Sends a payment deadline notice to ALL currently enrolled students.
     Registered (new) students paying enrollment fees are excluded.
============================ -->
<div id="paymentDueModal" class="modal-overlay">
    <div class="modal-card onsite-card">
        <div class="modal-topbar">
            <h2>Set Payment Deadline</h2>
            <button class="btn-close-modal" onclick="closePaymentDueModal()">&#x2715;</button>
        </div>
        <div class="onsite-body">

            <!-- Announcement callout banner -->
            <div class="pd-announcement-banner">
                <div class="pd-announcement-icon">
                    <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                        <path d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
                    </svg>
                </div>
                <div class="pd-announcement-text">
                    <strong>Broadcast to Enrolled Students Only</strong>
                    <span>This notice will be sent to all students who are currently enrolled. Registered (new) students paying enrollment fees are not included.</span>
                </div>
            </div>

            <div class="onsite-grid">
                <!-- Amount Due -->
                <div class="form-group">
                    <label for="pd-amount-due">Amount Due <span style="color:#c0392b">*</span></label>
                    <div class="peso-input-wrap">
                        <span class="peso-symbol">₱</span>
                        <input type="text" id="pd-amount-due" placeholder="0.00" autocomplete="off" inputmode="decimal">
                    </div>
                </div>
                <!-- Deadline Date and Time -->
                <div class="form-group">
                    <label for="pd-due-datetime">Payment Deadline <span style="color:#c0392b">*</span></label>
                    <input type="datetime-local" id="pd-due-datetime" autocomplete="off">
                </div>
                <!-- Optional additional message -->
                <div class="form-group full">
                    <label for="pd-notice-message">Additional Message <span style="color:#8a7570;font-weight:400;">(optional)</span></label>
                    <textarea id="pd-notice-message" rows="3" placeholder="e.g. All payments must be completed through the student portal before the deadline…" style="width:100%;padding:10px 12px;border:1.5px solid var(--maroon-border);border-radius:var(--radius-sm);font-family:inherit;font-size:.875rem;color:var(--text-body);resize:vertical;background:#fff;"></textarea>
                </div>
            </div>

            <div class="onsite-actions">
                <button class="btn-onsite-cancel" onclick="closePaymentDueModal()">Cancel</button>
                <button class="btn-onsite-submit btn-payment-due-submit" onclick="submitPaymentDue()">
                    <svg width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" viewBox="0 0 24 24">
                        <path d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
                    </svg>
                    Send Notice to All Students
                </button>
            </div>
        </div>
    </div>
</div>


<!-- ============================
     LOGOUT MODAL
============================ -->
<div id="logoutModal" class="logout-overlay">
    <div class="logout-card">
        <div class="logout-icon">
            <svg width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                <path d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"/>
            </svg>
        </div>
        <h3>Sign Out</h3>
        <p>Are you sure you want to sign out of the Cashier Portal?</p>
        <div class="logout-btns">
            <button class="btn-logout-cancel" onclick="closeLogoutModal()">Stay Signed In</button>
            <button class="btn-logout-confirm" onclick="confirmLogout()">Yes, Sign Out</button>
        </div>
    </div>
</div>


<!-- Toast Container -->
<div id="toast-stack" class="toast-stack"></div>

<script>
// Inject PHP config for JS to use
window.APP_CONFIG = {
    schoolName:   <?= json_encode($cashierInfo['school_name'] ?? 'Saint Joseph') ?>,
    cashierName:  <?= json_encode($cashierInfo['full_name']   ?? '') ?>,
    cashierRole:  'Cashier Desk',
    cashierId:    <?= (int) $cashierId ?>,
    loginUrl:     'login.html',
    proofBaseUrl: '../assets/proofs/',
    approveUrl:   'cashier-manage.php?action=approve',
    declineUrl:   'cashier-manage.php?action=decline',
    onsiteUrl:    'cashier-manage.php?action=onsite',
    paymentDueUrl:'cashier-manage.php?action=payment-due',
    lookupUrl:    'cashier-manage.php?action=lookup',
    suggestUrl:   'cashier-manage.php?action=suggest',
    walletLookupUrl: 'cashier-manage.php?action=wallet-lookup',
    topupUrl:     'cashier-manage.php?action=topup',
    markViewedUrl:'cashier-manage.php?action=mark-viewed',
    logoutUrl:    'cashier-manage.php?action=logout',
    countdownSec: 10,
};
</script>
<script src="../src/js/cashier.js"></script>

</body>
</html>

<?php
/* ============================================================
   DATA FETCH FUNCTIONS
============================================================ */

/**
 * Returns all payment submissions that are not yet finalized
 * (uploaded, under_review) PLUS recently finalized ones (last 7 days)
 * so the cashier can see the full working list.
 */
function getPendingSubmissions(PDO $pdo): array
{
    $sql = "
        SELECT
            ps.id,
            ps.student_id,
            ps.reference_number,
            ps.payment_type,
            ps.amount,
            ps.confirmed_amount,
            ps.proof_image_path,
            ps.proof_image_name,
            ps.proof_image_mime,
            ps.proof_image_size_kb,
            ps.status,
            ps.rejection_reason,
            ps.submitted_at,
            ps.reviewed_at,
            ps.review_started_at,
            ps.confirmed_at,
            CASE WHEN ps.proof_image_mime = 'onsite/cash'
                 THEN 'onsite'
                 ELSE COALESCE(ps.payment_channel, 'gcash')
            END                            AS payment_channel,
            ps.bank_name,
            s.first_name,
            s.last_name,
            s.lrn,
            gl.display_name                AS grade_level,
            sec.name                       AS section_name,
            e.id                           AS enrollment_id,
            e.status                       AS enrollment_status
        FROM   payment_submissions ps
        JOIN   students   s   ON s.id  = ps.student_id
        LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
        LEFT JOIN enrollments  e  ON e.student_id = ps.student_id
                                 AND e.school_year_id = ps.school_year_id
        LEFT JOIN section_school_years ssy ON ssy.id = e.section_sy_id
        LEFT JOIN sections sec ON sec.id = ssy.section_id
        WHERE  ps.status IN ('uploaded', 'under_review', 'pending', 'submitted', 'paid')
           OR  ps.status IS NULL
        ORDER  BY ps.submitted_at DESC
    ";
    return $pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC);
}

/**
 * Returns all approved / rejected transactions for the history tab.
 */
function getTransactionHistory(PDO $pdo): array
{
    $sql = "
        SELECT
            ps.id,
            ps.student_id,
            ps.reference_number,
            ps.payment_type,
            ps.amount,
            ps.confirmed_amount,
            ps.proof_image_path,
            ps.status,
            ps.rejection_reason,
            ps.submitted_at,
            ps.reviewed_at,
            CASE WHEN ps.proof_image_mime = 'onsite/cash' THEN 'onsite' ELSE 'online' END AS payment_channel,
            s.first_name,
            s.last_name,
            s.lrn,
            gl.display_name  AS grade_level,
            sec.name         AS section_name
        FROM   payment_submissions ps
        JOIN   students s ON s.id = ps.student_id
        LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
        LEFT JOIN enrollments  e  ON e.student_id = ps.student_id
                                 AND e.school_year_id = ps.school_year_id
        LEFT JOIN section_school_years ssy ON ssy.id = e.section_sy_id
        LEFT JOIN sections sec ON sec.id = ssy.section_id
        WHERE  ps.status IN ('verified', 'rejected', 'reflected_to_enrollment')
        ORDER  BY COALESCE(ps.reviewed_at, ps.updated_at) DESC
        LIMIT  200
    ";
    return $pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC);
}

function getCashierInfo(PDO $pdo, int $cashierId): array
{
    $stmt = $pdo->prepare("SELECT full_name FROM cashiers WHERE id = ?");
    $stmt->execute([$cashierId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];
    $row['school_name'] = 'Saint Joseph College';
    return $row;
}

/**
 * All cashier-performed Student ID Top-Ups, most recent first.
 * Only rows attributed to a cashier (cashier_id IS NOT NULL) are shown here —
 * admin-side "Add Funds" adjustments have their own history on the admin side.
 */
function getTopupHistory(PDO $pdo): array
{
    $sql = "
        SELECT
            wt.id,
            wt.amount,
            wt.payment_mode,
            wt.balance_after,
            wt.created_at,
            c.full_name  AS cashier_name,
            s.first_name AS student_first_name,
            s.last_name  AS student_last_name,
            s.lrn
        FROM   wallet_transactions wt
        JOIN   students s  ON s.id = wt.student_id
        LEFT JOIN cashiers c ON c.id = wt.cashier_id
        WHERE  wt.type = 'credit'
          AND  wt.cashier_id IS NOT NULL
        ORDER  BY wt.created_at DESC
        LIMIT  300
    ";
    return $pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC);
}

function computeStats(array $rows): array
{
    $pending = $enrolledToday = $onsite = 0;
    $today = date('Y-m-d');

    foreach ($rows as $r) {
        if (in_array($r['status'], ['uploaded', 'under_review'])) $pending++;
        if ($r['enrollment_status'] === 'enrolled' && substr($r['submitted_at'] ?? '', 0, 10) === $today) $enrolledToday++;
        if (($r['payment_channel'] ?? '') === 'onsite') $onsite++;
    }

    return [
        'pending'       => $pending,
        'enrolled_today'=> $enrolledToday,
        'total'         => count($rows),
        'onsite'        => $onsite,
    ];
}

/* ============================================================
   API HANDLERS
============================================================ */

/**
 * POST /cashier/approve
 * Body: { id: int, cashier_id: int }
 *
 * Logic:
 *  1. Load the payment_submission + student's enrollment
 *  2. If enrollment.status = 'pending'  → update to 'enrolled'
 *  3. If enrollment.status = 'enrolled' → no change (just store)
 *  4. Mark payment as 'verified' / 'reflected_to_enrollment'
 *  5. Notify student (placeholder — implement email/notification as needed)
 */
function handleApprove(PDO $pdo, int $cashierId): void
{
    $body = getJsonBody();
    $id   = (int) ($body['id'] ?? 0);

    if (!$id) { jsonError('Missing payment ID.'); }

    // Load submission + enrollment
    $stmt = $pdo->prepare("
        SELECT ps.*, e.id AS enrollment_id, e.status AS enrollment_status, e.student_id AS enroll_student_id
        FROM   payment_submissions ps
        LEFT JOIN enrollments e ON e.student_id = ps.student_id
                               AND e.school_year_id = ps.school_year_id
        WHERE  ps.id = ?
        LIMIT  1
    ");
    $stmt->execute([$id]);
    $sub = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$sub) { jsonError('Payment submission not found.', 404); }
    if (in_array($sub['status'], ['verified', 'reflected_to_enrollment'])) {
        jsonError('This payment has already been approved.', 409);
    }

    $pdo->beginTransaction();
    try {
        $enrollmentChanged = false;
        $newPaymentStatus  = 'verified';

        // enrollments.status uses enum('pending','enrolled','unregistered','archived')
        // A newly registered student has enrollments.status = 'pending'
        // students.registration_status = 'registered' is a separate column on the students table
        $needsEnrollment = $sub['enrollment_id']
            && in_array($sub['enrollment_status'], ['pending', 'registered']);

        if ($needsEnrollment) {
            // enrollment_logs.old_status enum only accepts: pending, enrolled, unregistered, archived
            // 'registered' lives on students table, not enrollments — always log as 'pending' here
            $logOldStatus = $sub['enrollment_status'];

            $pdo->prepare("
                UPDATE enrollments
                SET    status       = 'enrolled',
                       processed_by = NULL,
                       processed_at = NOW(),
                       updated_at   = NOW()
                WHERE  id = ?
            ")->execute([$sub['enrollment_id']]);

            // Sync students.registration_status
            $pdo->prepare("
                UPDATE students
                SET    registration_status = 'enrolled',
                       updated_at          = NOW()
                WHERE  id = ?
            ")->execute([$sub['student_id']]);

            // Sync users.account_status
            $pdo->prepare("
                UPDATE users u
                JOIN   students s ON s.user_id = u.id
                SET    u.account_status = 'enrolled',
                       u.updated_at     = NOW()
                WHERE  s.id = ?
            ")->execute([$sub['student_id']]);

            // Enrollment log — old_status must be a valid enum value for that column
            $pdo->prepare("
                INSERT INTO enrollment_logs
                    (enrollment_id, student_id, changed_by, old_status, new_status, notes, ip_address)
                VALUES (?, ?, ?, ?, 'enrolled', 'Enrollment confirmed via payment approval by cashier.', ?)
            ")->execute([
                $sub['enrollment_id'],
                $sub['student_id'],
                $cashierId,
                $logOldStatus,
                $_SERVER['REMOTE_ADDR'] ?? null,
            ]);

            $enrollmentChanged = true;
            $newPaymentStatus  = 'reflected_to_enrollment';
        } // end if ($needsEnrollment)

        // Update payment submission
        $pdo->prepare("
            UPDATE payment_submissions
            SET    status       = ?,
                   cashier_id   = ?,
                   reviewed_at  = NOW(),
                   confirmed_at = NOW(),
                   updated_at   = NOW()
            WHERE  id = ?
        ")->execute([$newPaymentStatus, $cashierId, $id]);

        // TODO: Send notification to student (email / in-app)
        // notifyStudent($sub['student_id'], $enrollmentChanged ? 'approved_enrolled' : 'approved');

        $pdo->commit();

    } catch (\Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        error_log('Approve error: ' . $e->getMessage());
        jsonError('Database error during approval. Please try again.');
    }

    // Send approval email AFTER the transaction has been committed and closed.
    // Wrapped in its own try/catch so a PHPMailer crash is logged but never
    // outputs HTML that would corrupt the JSON response back to the browser.
    try {
        notifyStudentPayment($pdo, $sub['student_id'], $enrollmentChanged);
    } catch (\Throwable $mailErr) {
        error_log('[PaymentMailer] Approval email failed: ' . $mailErr->getMessage());
    }

    echo json_encode([
        'success'           => true,
        'enrollment_changed'=> $enrollmentChanged,
        'new_enrollment_status' => $enrollmentChanged ? 'enrolled' : $sub['enrollment_status'],
        'message'           => $enrollmentChanged
            ? 'Payment approved. Student enrollment status updated to Enrolled.'
            : 'Payment approved. Student was already enrolled — transaction stored in history.',
    ]);
}

/**
 * POST /cashier/decline
 * Body: { id: int, cashier_id: int, reason: string }
 */
function handleDecline(PDO $pdo, int $cashierId): void
{
    $body   = getJsonBody();
    $id     = (int) ($body['id']     ?? 0);
    $reason = trim($body['reason']   ?? '');

    if (!$id) { jsonError('Missing payment ID.'); }

    $stmt = $pdo->prepare("SELECT id, status, student_id FROM payment_submissions WHERE id = ?");
    $stmt->execute([$id]);
    $sub = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$sub) { jsonError('Payment submission not found.', 404); }
    if (in_array($sub['status'], ['verified', 'reflected_to_enrollment'])) {
        jsonError('This payment has already been approved and cannot be declined.', 409);
    }

    $pdo->prepare("
        UPDATE payment_submissions
        SET    status           = 'rejected',
               cashier_id       = ?,
               rejection_reason = ?,
               reviewed_at      = NOW(),
               updated_at       = NOW()
        WHERE  id = ?
    ")->execute([$cashierId, $reason ?: null, $id]);

    // Send decline email — wrapped in try/catch so a PHPMailer crash is logged
    // but never outputs HTML that would corrupt the JSON response to the browser.
    try {
        notifyStudentDecline($pdo, (int) $sub['student_id'], $reason);
    } catch (\Throwable $mailErr) {
        error_log('[PaymentMailer] Decline email failed: ' . $mailErr->getMessage());
    }

    echo json_encode(['success' => true, 'message' => 'Payment declined. Student will be notified.']);
}

/**
 * POST /cashier/mark-viewed
 * Body: { id: int }
 * Called when the cashier opens a submission — sets status to 'under_review'
 * and stamps review_started_at if not already set.
 * This is reflected back to the student's portal as "Viewed by Cashier".
 */
function handleMarkViewed(PDO $pdo, int $cashierId): void
{
    $body = getJsonBody();
    $id   = (int) ($body['id'] ?? 0);

    if (!$id) { jsonError('Missing ID.'); }

    $pdo->prepare("
        UPDATE payment_submissions
        SET    status             = IF(status = 'uploaded', 'under_review', status),
               review_started_at = IF(review_started_at IS NULL, NOW(), review_started_at),
               cashier_id        = COALESCE(cashier_id, ?),
               updated_at        = NOW()
        WHERE  id = ?
          AND  status IN ('uploaded', 'under_review')
    ")->execute([$cashierId, $id]);

    echo json_encode(['success' => true]);
}

/**
 * POST /cashier/onsite
 * Records a walk-in cash payment and immediately enrolls the student.
 */
function handleOnsite(PDO $pdo, int $cashierId): void
{
    $body         = getJsonBody();
    $studentId    = isset($body['student_id']) ? (int) $body['student_id'] : null;
    $studentName  = trim($body['student_name']  ?? '');
    $gradeSection = trim($body['grade_section'] ?? '');
    $amount       = isset($body['amount'])   ? (float)  $body['amount']   : null;
    $feeType      = trim($body['fee_type']   ?? '');

    if (!$studentName)           { jsonError('Student name is required.'); }
    if (!$amount || $amount <= 0){ jsonError('A valid amount is required.'); }
    if (!$feeType)               { jsonError('Fee type is required.'); }

    // If we have a student_id, try to enroll them
    if ($studentId) {
        $stmt = $pdo->prepare("
            SELECT e.id AS enrollment_id, e.status
            FROM   enrollments e
            JOIN   school_years sy ON sy.id = e.school_year_id AND sy.is_active = 1
            WHERE  e.student_id = ?
            LIMIT  1
        ");
        $stmt->execute([$studentId]);
        $enrollment = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($enrollment && in_array($enrollment['status'], ['registered', 'pending'])) {
            $pdo->prepare("
                UPDATE enrollments SET status='enrolled', processed_at=NOW(), updated_at=NOW() WHERE id=?
            ")->execute([$enrollment['enrollment_id']]);

            $pdo->prepare("
                UPDATE students SET registration_status='enrolled', updated_at=NOW() WHERE id=?
            ")->execute([$studentId]);
        }
    }

    // Store a payment_submission record for the on-site payment
    // We use reference_number = 'ONSITE-' + timestamp as a synthetic ref
    $ref = 'ONSITE-' . strtoupper(substr(uniqid(), -6));

    // Fetch active school_year_id
    $syStmt = $pdo->query("SELECT id FROM school_years WHERE is_active = 1 LIMIT 1");
    $syId   = (int) ($syStmt->fetchColumn() ?: 1);

    if ($studentId) {
        $pdo->prepare("
            INSERT INTO payment_submissions
                (student_id, school_year_id, reference_number, payment_type, amount,
                 proof_image_path, proof_image_name, proof_image_mime,
                 status, cashier_id, reviewed_at, confirmed_at, confirmed_amount,
                 reflected_to_enrollment_at, submitted_at, ip_address)
            VALUES
                (?, ?, ?, 'full', ?,
                 '', ?, 'onsite/cash',
                 'reflected_to_enrollment', ?, NOW(), NOW(), ?,
                 NOW(), NOW(), ?)
        ")->execute([
            $studentId, $syId, $ref, $amount,
            "On-Site Cash – {$feeType}",
            $cashierId, $amount,
            $_SERVER['REMOTE_ADDR'] ?? null,
        ]);
        $newId = (int) $pdo->lastInsertId();
    } else {
        $newId = null;
    }

    echo json_encode([
        'success' => true,
        'message' => "On-site payment recorded for {$studentName}.",
        'record'  => [
            'id'               => $newId,
            'student_name'     => $studentName,
            'reference_number' => $ref,
            'amount'           => $amount,
            'submitted_at'     => date('Y-m-d H:i:s'),
            'status'           => 'reflected_to_enrollment',
            'payment_type'     => 'onsite',
        ],
    ]);
}

/**
 * POST /cashier/payment-due  (BROADCAST)
 * Body: { amount_due: float, due_datetime: string, notice_message: string,
 *          cashier_id: int, broadcast: true }
 *
 * Sends a payment deadline notice to ALL currently enrolled students.
 * Registered (new) students paying enrollment fees are intentionally excluded.
 * Creates one payment_due_notices record per enrolled student and emails each.
 */
function handlePaymentDue(PDO $pdo, int $cashierId): void
{
    $body          = getJsonBody();
    $amountDue     = isset($body['amount_due'])     ? (float)  $body['amount_due']     : null;
    $dueDatetime   = trim($body['due_datetime']     ?? '');
    $noticeMessage = trim($body['notice_message']   ?? '');

    if (!$amountDue || $amountDue <= 0) { jsonError('A valid amount due is required.'); }
    if (!$dueDatetime)                  { jsonError('Due date and time is required.'); }

    try {
        $dueDt = new DateTime($dueDatetime, new DateTimeZone('Asia/Manila'));
    } catch (\Exception $e) {
        jsonError('Invalid due date/time format.');
    }

    // Fetch active school year
    $syStmt = $pdo->query("SELECT id FROM school_years WHERE is_active = 1 LIMIT 1");
    $syId   = (int) ($syStmt->fetchColumn() ?: 1);

    // Fetch all ENROLLED students (exclude registered/pending — they are paying enrollment fees separately)
    $enrolledStmt = $pdo->prepare("
        SELECT
            s.id AS student_id,
            CONCAT(s.first_name, ' ', s.last_name) AS full_name,
            COALESCE(s.personal_email, u.personal_email, u.email) AS email
        FROM   students s
        JOIN   enrollments e   ON e.student_id = s.id
                               AND e.school_year_id = ?
                               AND e.status = 'enrolled'
        LEFT JOIN users u ON u.id = s.user_id
        WHERE  s.registration_status = 'enrolled'
    ");
    $enrolledStmt->execute([$syId]);
    $enrolled = $enrolledStmt->fetchAll(PDO::FETCH_ASSOC);

    if (empty($enrolled)) {
        echo json_encode([
            'success'        => true,
            'notified_count' => 0,
            'message'        => 'No enrolled students found to notify.',
        ]);
        return;
    }

    $dueDateStr    = $dueDt->format('Y-m-d H:i:s');
    $notifiedCount = 0;
    $failedEmails  = [];

    // NOTE: If notice_message column doesn't exist yet, run this migration first:
    //   ALTER TABLE payment_due_notices ADD COLUMN notice_message text NULL AFTER due_datetime;
    $insertStmt = $pdo->prepare("
        INSERT INTO payment_due_notices
            (student_id, school_year_id, amount_due, due_datetime,
             notice_message, status, assigned_by, created_at, updated_at)
        VALUES
            (?, ?, ?, ?,
             ?, 'pending', ?, NOW(), NOW())
    ");

    foreach ($enrolled as $student) {
        // Insert notice record for each enrolled student
        $insertStmt->execute([
            $student['student_id'],
            $syId,
            $amountDue,
            $dueDateStr,
            $noticeMessage ?: null,
            $cashierId,
        ]);

        // Send individual email notification
        if (!empty($student['email'])) {
            try {
                notifyStudentPaymentDue(
                    $pdo,
                    (int) $student['student_id'],
                    $amountDue,
                    $dueDateStr,
                    $noticeMessage
                );
                $notifiedCount++;
            } catch (\Throwable $mailErr) {
                error_log('[PaymentMailer] Due notice email failed for student_id='
                    . $student['student_id'] . ': ' . $mailErr->getMessage());
                $failedEmails[] = $student['student_id'];
                $notifiedCount++; // still count as noticed (record saved)
            }
        } else {
            $notifiedCount++; // record saved even if no email on file
        }
    }

    echo json_encode([
        'success'        => true,
        'notified_count' => $notifiedCount,
        'failed_emails'  => count($failedEmails),
        'message'        => "Payment deadline notice sent to {$notifiedCount} enrolled student(s).",
    ]);
}

/**
 * GET /cashier/lookup?q=<student_id_or_lrn_or_name>
 *
 * Searches by:
 *   1. Student ID (numeric exact match)
 *   2. LRN (exact match)
 *   3. Full name partial match (first_name, last_name, or combined)
 *
 * When a name query matches multiple students, returns up to 10 results
 * so the front-end can display a disambiguation list.
 */
function handleLookup(PDO $pdo): void
{
    $q = trim($_GET['q'] ?? '');
    if (!$q) { echo json_encode(['found' => false, 'results' => []]); return; }

    $baseSelect = "
        SELECT
            s.id,
            CONCAT(s.first_name,
                   IF(s.middle_name IS NOT NULL AND s.middle_name <> '', CONCAT(' ', s.middle_name), ''),
                   ' ', s.last_name) AS name,
            CONCAT(gl.display_name,
                   IF(sec.name IS NOT NULL, CONCAT(' – ', sec.name), '')) AS grade_section,
            e.status AS enrollment_status,
            s.personal_email AS email
        FROM  students s
        LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
        LEFT JOIN enrollments  e  ON e.student_id = s.id
        LEFT JOIN section_school_years ssy ON ssy.id = e.section_sy_id
        LEFT JOIN sections sec ON sec.id = ssy.section_id
    ";

    // --- Try exact ID / LRN match first ---
    $isNumeric = ctype_digit($q);
    if ($isNumeric) {
        $stmt = $pdo->prepare($baseSelect . "WHERE (s.id = ? OR s.lrn = ?) LIMIT 1");
        $stmt->execute([$q, $q]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            echo json_encode([
                'found'             => true,
                'multiple'          => false,
                'student_id'        => $row['id'],
                'name'              => $row['name'],
                'grade_section'     => $row['grade_section'],
                'enrollment_status' => $row['enrollment_status'],
                'email'             => $row['email'],
            ]);
            return;
        }
    }

    // --- Fall back to name search (partial, case-insensitive) ---
    $like = '%' . $q . '%';
    $stmt = $pdo->prepare($baseSelect . "
        WHERE (
            s.first_name  LIKE ?
            OR s.last_name  LIKE ?
            OR s.middle_name LIKE ?
            OR CONCAT(s.first_name, ' ', s.last_name) LIKE ?
            OR CONCAT(s.last_name,  ' ', s.first_name) LIKE ?
        )
        ORDER BY s.last_name, s.first_name
        LIMIT 10
    ");
    $stmt->execute([$like, $like, $like, $like, $like]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    if (!$rows) {
        echo json_encode(['found' => false, 'results' => []]);
        return;
    }

    if (count($rows) === 1) {
        $row = $rows[0];
        echo json_encode([
            'found'             => true,
            'multiple'          => false,
            'student_id'        => $row['id'],
            'name'              => $row['name'],
            'grade_section'     => $row['grade_section'],
            'enrollment_status' => $row['enrollment_status'],
            'email'             => $row['email'],
        ]);
        return;
    }

    // Multiple matches — let the front-end show a picker
    $results = array_map(fn($r) => [
        'student_id'        => $r['id'],
        'name'              => $r['name'],
        'grade_section'     => $r['grade_section'],
        'enrollment_status' => $r['enrollment_status'],
        'email'             => $r['email'],
    ], $rows);

    echo json_encode(['found' => true, 'multiple' => true, 'results' => $results]);
}

/**
 * GET /cashier/wallet-lookup?q=<student_id_or_lrn>
 *
 * Finds a student and returns their current cafeteria/ID wallet balance
 * plus the admin-set per-transaction top-up limit, so the Student Top-Up
 * modal can display and pre-validate before the cashier submits.
 *
 * Response: { found, student_id, name, grade_section, enrollment_status,
 *             balance, max_topup_amount }
 *   max_topup_amount = 0 means the admin has not set a per-transaction cap.
 */
function handleWalletLookup(PDO $pdo): void
{
    $q = trim($_GET['q'] ?? '');

    $limitStmt = $pdo->query("SELECT max_topup_amount FROM cafeteria_settings ORDER BY id LIMIT 1");
    $maxTopup  = (float) ($limitStmt->fetchColumn() ?: 0);

    if ($q === '') {
        echo json_encode(['found' => false, 'max_topup_amount' => $maxTopup]);
        return;
    }

    $sql = "
        SELECT
            s.id,
            CONCAT(s.first_name,
                   IF(s.middle_name IS NOT NULL AND s.middle_name <> '', CONCAT(' ', s.middle_name), ''),
                   ' ', s.last_name) AS name,
            CONCAT(gl.display_name,
                   IF(sec.name IS NOT NULL, CONCAT(' – ', sec.name), '')) AS grade_section,
            e.status AS enrollment_status,
            COALESCE(w.balance, 0) AS balance
        FROM  students s
        LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
        LEFT JOIN enrollments  e  ON e.student_id = s.id
        LEFT JOIN section_school_years ssy ON ssy.id = e.section_sy_id
        LEFT JOIN sections sec ON sec.id = ssy.section_id
        LEFT JOIN student_wallets w ON w.student_id = s.id
    ";

    $isNumeric = ctype_digit($q);
    if ($isNumeric) {
        $stmt = $pdo->prepare($sql . " WHERE (s.id = ? OR s.lrn = ?) LIMIT 1");
        $stmt->execute([$q, $q]);
    } else {
        $stmt = $pdo->prepare($sql . " WHERE s.lrn = ? LIMIT 1");
        $stmt->execute([$q]);
    }
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        echo json_encode(['found' => false, 'max_topup_amount' => $maxTopup]);
        return;
    }

    echo json_encode([
        'found'             => true,
        'student_id'        => (int) $row['id'],
        'name'              => $row['name'],
        'grade_section'     => $row['grade_section'],
        'enrollment_status' => $row['enrollment_status'],
        'balance'           => (float) $row['balance'],
        'max_topup_amount'  => $maxTopup,
    ]);
}

/**
 * POST /cashier/topup
 * Body: { student_id: int, amount: float, cashier_id: int }
 *
 * Cashier-side Student ID Top-Up. Credits a student's cafeteria/token
 * wallet (student_wallets.balance) and logs the movement in
 * wallet_transactions.
 *
 * Admin restrictions enforced here (never trust the client):
 *   - Cashiers can only ADD credit. There is no deduct branch reachable
 *     from this endpoint — deducting a student's balance is an admin-only
 *     capability handled elsewhere in the system.
 *   - A single top-up cannot exceed cafeteria_settings.max_topup_amount,
 *     the same admin-controlled ceiling used for "Add Funds" transactions
 *     (0 = admin has not set a limit).
 */
function handleTopup(PDO $pdo, int $cashierId): void
{
    $body        = getJsonBody();
    $studentId   = (int) ($body['student_id'] ?? 0);
    $amount      = isset($body['amount']) ? round((float) $body['amount'], 2) : 0;
    $paymentMode = trim($body['payment_mode'] ?? '');

    $allowedModes = ['cash', 'gcash', 'bank_transfer'];

    if (!$studentId)                       { jsonError('Select a valid student first.'); }
    if (!$amount || $amount <= 0)          { jsonError('Enter a valid top-up amount.'); }
    if (!in_array($paymentMode, $allowedModes, true)) { jsonError('Select the mode of payment.'); }

    try {
        $pdo->beginTransaction();

        // Confirm the student exists (lock row to avoid concurrent edits)
        $stmt = $pdo->prepare("SELECT id, first_name, last_name, lrn FROM students WHERE id = ? LIMIT 1 FOR UPDATE");
        $stmt->execute([$studentId]);
        $student = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$student) { $pdo->rollBack(); jsonError('Student not found.', 404); }

        // Admin-set per-transaction ceiling — authoritative check, not just UI hinting
        $limitStmt = $pdo->query("SELECT max_topup_amount FROM cafeteria_settings ORDER BY id LIMIT 1");
        $maxTopup  = (float) ($limitStmt->fetchColumn() ?: 0);

        if ($maxTopup > 0 && $amount > $maxTopup) {
            $pdo->rollBack();
            jsonError('Amount exceeds the admin-set top-up limit of ₱' . number_format($maxTopup, 2) . ' per transaction.');
        }

        // Lock (or create) the wallet row, then credit it
        $wStmt = $pdo->prepare("SELECT id, balance FROM student_wallets WHERE student_id = ? FOR UPDATE");
        $wStmt->execute([$studentId]);
        $wallet = $wStmt->fetch(PDO::FETCH_ASSOC);

        if ($wallet) {
            $newBalance = round((float) $wallet['balance'] + $amount, 2);
            $pdo->prepare("UPDATE student_wallets SET balance = ?, updated_at = NOW() WHERE id = ?")
                ->execute([$newBalance, $wallet['id']]);
        } else {
            $newBalance = $amount;
            $pdo->prepare("INSERT INTO student_wallets (student_id, balance, updated_at) VALUES (?, ?, NOW())")
                ->execute([$studentId, $newBalance]);
        }

        // Ledger entry — admin_id stays NULL for cashier-initiated top-ups;
        // cashier_id records who actually performed it (see wallet_topup_migration.sql)
        $cashierName = getCashierInfo($pdo, $cashierId)['full_name'] ?? 'Cashier';
        $note = "Top-up by cashier: {$cashierName}";
        $pdo->prepare("
            INSERT INTO wallet_transactions
                (student_id, admin_id, cashier_id, type, payment_mode, amount, balance_after, note, created_at)
            VALUES
                (?, NULL, ?, 'credit', ?, ?, ?, ?, NOW())
        ")->execute([$studentId, $cashierId, $paymentMode, $amount, $newBalance, $note]);

        $pdo->commit();

        echo json_encode([
            'success'      => true,
            'message'      => 'Top-up successful.',
            'student_id'   => $studentId,
            'student_name' => trim($student['first_name'] . ' ' . $student['last_name']),
            'lrn'          => $student['lrn'],
            'cashier_name' => $cashierName,
            'amount_added' => $amount,
            'new_balance'  => $newBalance,
            'payment_mode' => $paymentMode,
            'created_at'   => date('Y-m-d H:i:s'),
        ]);
    } catch (\Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        error_log('[handleTopup] ' . $e->getMessage());
        jsonError('Failed to process top-up. Please try again.', 500);
    }
}

/**
 * GET /cashier/suggest?q=<partial_query>
 *
 * Typeahead / live-search endpoint.
 * Returns up to 8 lightweight student records matching:
 *   - Partial student ID (numeric prefix)
 *   - Partial LRN (numeric prefix or substring)
 *   - Partial first name, last name, middle name, or combined name
 *
 * Response: { suggestions: [ { student_id, name, lrn, grade_section, email }, … ] }
 */
function handleSuggest(PDO $pdo): void
{
    $q = trim($_GET['q'] ?? '');

    // Need at least 2 chars to avoid returning the entire table
    if (strlen($q) < 2) {
        echo json_encode(['suggestions' => []]);
        return;
    }

    $like      = '%' . $q . '%';
    $isNumeric = ctype_digit($q);

    if ($isNumeric) {
        // For numeric queries match ID prefix, LRN prefix, or LRN substring
        $stmt = $pdo->prepare("
            SELECT
                s.id,
                s.lrn,
                CONCAT(s.first_name,
                       IF(s.middle_name IS NOT NULL AND s.middle_name <> '',
                          CONCAT(' ', s.middle_name), ''),
                       ' ', s.last_name) AS name,
                CONCAT(gl.display_name,
                       IF(sec.name IS NOT NULL, CONCAT(' – ', sec.name), '')) AS grade_section,
                s.personal_email AS email
            FROM  students s
            LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
            LEFT JOIN enrollments  e  ON e.student_id = s.id
            LEFT JOIN section_school_years ssy ON ssy.id = e.section_sy_id
            LEFT JOIN sections sec ON sec.id = ssy.section_id
            WHERE (
                CAST(s.id AS CHAR) LIKE ?
                OR s.lrn LIKE ?
            )
            ORDER BY
                CASE WHEN s.lrn = ? THEN 0 WHEN CAST(s.id AS CHAR) = ? THEN 1 ELSE 2 END,
                s.last_name, s.first_name
            LIMIT 8
        ");
        $stmt->execute([$like, $like, $q, $q]);
    } else {
        $stmt = $pdo->prepare("
            SELECT
                s.id,
                s.lrn,
                CONCAT(s.first_name,
                       IF(s.middle_name IS NOT NULL AND s.middle_name <> '',
                          CONCAT(' ', s.middle_name), ''),
                       ' ', s.last_name) AS name,
                CONCAT(gl.display_name,
                       IF(sec.name IS NOT NULL, CONCAT(' – ', sec.name), '')) AS grade_section,
                s.personal_email AS email
            FROM  students s
            LEFT JOIN grade_levels gl ON gl.id = s.grade_level_id
            LEFT JOIN enrollments  e  ON e.student_id = s.id
            LEFT JOIN section_school_years ssy ON ssy.id = e.section_sy_id
            LEFT JOIN sections sec ON sec.id = ssy.section_id
            WHERE (
                s.first_name  LIKE ?
                OR s.last_name  LIKE ?
                OR s.middle_name LIKE ?
                OR CONCAT(s.first_name, ' ', s.last_name)  LIKE ?
                OR CONCAT(s.last_name,  ' ', s.first_name) LIKE ?
                OR sec.name LIKE ?
            )
            ORDER BY
                CASE
                    WHEN s.first_name LIKE ? THEN 0
                    WHEN s.last_name  LIKE ? THEN 1
                    WHEN sec.name     LIKE ? THEN 2
                    ELSE 3
                END,
                s.last_name, s.first_name
            LIMIT 8
        ");
        $startLike = $q . '%';
        $stmt->execute([$like, $like, $like, $like, $like, $like, $startLike, $startLike, $startLike]);
    }

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $suggestions = array_map(fn($r) => [
        'student_id'    => (int) $r['id'],
        'lrn'           => $r['lrn'] ?? '',
        'name'          => $r['name'],
        'grade_section' => $r['grade_section'],
        'email'         => $r['email'],
    ], $rows);

    echo json_encode(['suggestions' => $suggestions]);
}

function handleLogout(): void
{
    session_destroy();
    echo json_encode(['success' => true]);
}

/* ============================================================
   HELPERS
============================================================ */
function getJsonBody(): array
{
    $raw = file_get_contents('php://input');
    return $raw ? (json_decode($raw, true) ?? []) : [];
}

function jsonError(string $message, int $code = 400): void
{
    http_response_code($code);
    echo json_encode(['success' => false, 'error' => $message]);
    exit;
}

function isAjax(): bool
{
    return !empty($_SERVER['HTTP_X_REQUESTED_WITH'])
        && strtolower($_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest';
}

function getInitials(string $name): string
{
    $parts = preg_split('/\s+/', trim($name));
    $init  = strtoupper(substr($parts[0] ?? '', 0, 1));
    if (isset($parts[1])) $init .= strtoupper(substr($parts[1], 0, 1));
    return $init ?: '?';
}

function formatDatePH(?string $dateStr): string
{
    if (!$dateStr) return '—';
    try {
        $dt = new DateTime($dateStr, new DateTimeZone('Asia/Manila'));
        return $dt->format('M j, Y  g:i A');
    } catch (\Exception $e) {
        return $dateStr;
    }
}