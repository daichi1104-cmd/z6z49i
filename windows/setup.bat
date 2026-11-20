@echo off
rem band2score: first-time setup (Python, ffmpeg, libraries, AI model)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
