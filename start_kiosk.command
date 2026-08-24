#!/bin/bash
# ==============================================================================
# NovaLunch Enterprise Platform — All-in-One Auto Launcher
# Saint Joseph College of Novaliches (SJC)
# Double-click this script in Finder or run in Terminal to start the full system.
# ==============================================================================

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=================================================================="
echo "  🍱 STARTING NOVALUNCH CANTEEN PLATFORM (SJC NOVALICHES)"
echo "=================================================================="

# 1. Determine Python 3 executable
PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif [ -f "/usr/bin/python3" ]; then
    PYTHON_CMD="/usr/bin/python3"
elif [ -f "/opt/homebrew/bin/python3" ]; then
    PYTHON_CMD="/opt/homebrew/bin/python3"
elif [ -f "/usr/local/bin/python3" ]; then
    PYTHON_CMD="/usr/local/bin/python3"
else
    echo "❌ Error: Python 3 not found on system. Please install Python 3."
    read -p "Press Enter to exit..."
    exit 1
fi

echo "  🐍 Using Python: $($PYTHON_CMD --version)"

# 2. Check & start NovaLunch Unified Web & Bridge Server (Port 8080)
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null ; then
    echo "  🌐 Web Server is already running on http://localhost:8080"
else
    echo "  🚀 Starting NovaLunch Web & Bridge Server on port 8080..."
    $PYTHON_CMD "$DIR/server.py" > "$DIR/novalunch_server.log" 2>&1 &
    SERVER_PID=$!
    sleep 1
    if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null ; then
        echo "  ✅ Web Server started successfully (PID: $SERVER_PID)"
    else
        echo "  ⚠️ Web Server starting in background..."
    fi
fi

# 3. Automatically open browser to NovaLunch Portal
echo "  💻 Opening NovaLunch Web Portal in default browser..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    open "http://localhost:8080"
elif command -v xdg-open &> /dev/null; then
    xdg-open "http://localhost:8080"
fi

# 4. Check & start Student Kiosk & Camera Vision GUI (Port 8085)
echo "------------------------------------------------------------------"
if lsof -Pi :8085 -sTCP:LISTEN -t >/dev/null ; then
    echo "  🖥️  Python Student Kiosk GUI is already active on port 8085."
    echo "  Press Ctrl+C in this terminal to close this launcher window."
    wait
else
    echo "  🚀 Launching NovaLunch Student Kiosk & AI Scanner GUI..."
    echo "  (Live Cashier POS Bridge Active on http://127.0.0.1:8085)"
    echo "=================================================================="
    $PYTHON_CMD "$DIR/src/hardware/student_kiosk_gui.py"
fi
