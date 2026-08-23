#!/bin/bash
# ==============================================================================
# NovaLunch Student Kiosk Launcher Script
# Saint Joseph College of Novaliches (SJC)
# Double-click this script in Finder or run from terminal to launch GUI.
# ==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=========================================================="
echo "  🚀 LAUNCHING NOVALUNCH STUDENT KIOSK & AI SCANNER GUI..."
echo "  Live Cashier POS Bridge Active on http://127.0.0.1:8085"
echo "=========================================================="

if [ -f "/usr/bin/python3" ]; then
    /usr/bin/python3 "$DIR/src/hardware/student_kiosk_gui.py"
elif command -v python3 &> /dev/null; then
    python3 "$DIR/src/hardware/student_kiosk_gui.py"
else
    echo "❌ Error: Python 3 not found on system."
    read -p "Press enter to exit..."
fi
