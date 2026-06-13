@echo off
echo Starting Sales Analytics File Watcher...
cd /d "%~dp0"
python watch_folder.py
pause
