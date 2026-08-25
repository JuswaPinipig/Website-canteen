@echo off
title NovaLunch Python Student Kiosk GUI Launcher
cd /d "%~dp0"

echo ==================================================================
echo   🍱 NOVALUNCH STUDENT KIOSK HARDWARE GUI (SJC NOVALICHES)
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

:: Free port 8085 if occupied by stale process
for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| findstr ":8085" ^| findstr "LISTENING"') do (
    echo   [INFO] Freeing occupied Kiosk Port 8085 (PID %%a)...
    taskkill /F /PID %%a >nul 2>&1
)

echo.
echo   [1/1] Launching Student Kiosk GUI (Port 8085)...
echo   (No extra web browser windows will be opened)
echo.

if exist "src\hardware\student_kiosk_gui.py" (
    %PYTHON_CMD% src\hardware\student_kiosk_gui.py
) else if exist "..\src\hardware\student_kiosk_gui.py" (
    %PYTHON_CMD% ..\src\hardware\student_kiosk_gui.py
) else (
    echo [ERROR] student_kiosk_gui.py not found!
    pause
)

echo.
echo Kiosk process finished.
pause

