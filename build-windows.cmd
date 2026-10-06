@echo off
setlocal

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1"
if errorlevel 1 (
    echo.
    echo Build failed. See the error above.
    pause
    exit /b 1
)

echo.
echo The Windows executable is available in the dist folder.
pause
