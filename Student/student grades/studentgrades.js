/**
 * studentgrades.js
 * Handles term tab filtering for the grades table.
 * Quarter columns use classes: q-col, q1, q2, q3
 * Average column uses: final-col
 */

function filterTerm(event, term) {
    // Update active tab
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    event.currentTarget.classList.add('active');

    const allQCols  = document.querySelectorAll('.q-col');
    const finalCols = document.querySelectorAll('.final-col');

    if (term === 'all') {
        allQCols.forEach(col  => col.classList.remove('hide-col'));
        finalCols.forEach(col => col.classList.remove('hide-col'));
    } else {
        // Hide all quarter columns and average
        allQCols.forEach(col  => col.classList.add('hide-col'));
        finalCols.forEach(col => col.classList.add('hide-col'));

        // Show only the selected term column
        document.querySelectorAll('.' + term).forEach(col => col.classList.remove('hide-col'));
    }
}