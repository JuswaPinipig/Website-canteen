@echo off
title NovaLunch Kiosk & Web Server Launcher
cd /d "%~dp0"

echo ==================================================================
echo   🍱 NOVALUNCH CANTEEN PLATFORM (SJC NOVALICHES)
echo ==================================================================

:: Check if Python is available
where py >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set PYTHON_CMD=py -3
    goto :PYTHON_FOUND
)

where python >nul 2>&1
if %ERRORLEVEL% equ 0 (
    set PYTHON_CMD=python
    goto :PYTHON_FOUND
)

echo [ERROR] Python not found on PATH. Please install Python 3.10+ from python.org.
pause
exit /b 1

:PYTHON_FOUND
echo   [OK] Python detected:
%PYTHON_CMD% --version

echo.
echo   [1/3] Starting NovaLunch Web & Bridge Server (Port 8080)...
start "NovaLunch Web Server" /min %PYTHON_CMD% server.py

timeout /t 2 /nobreak >nul

echo   [2/3] Opening NovaLunch Web Portal in default browser...
start http://localhost:8080

echo   [3/3] Starting Student Kiosk GUI (Port 8085)...
start "NovaLunch Student Kiosk GUI" %PYTHON_CMD% src\hardware\student_kiosk_gui.py

echo.
echo ==================================================================
echo   ✅ NovaLunch Platform is now ACTIVE!
echo   🌐 Web Portal: http://localhost:8080
echo   🖥️  Kiosk GUI:  Port 8085 (Pygame Window)
echo ==================================================================
echo.
pause
