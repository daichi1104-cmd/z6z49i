@echo off
rem band2score: check that every library loads on this PC
cd /d "%~dp0.."
".venv\Scripts\python.exe" -m band2score.check
pause
