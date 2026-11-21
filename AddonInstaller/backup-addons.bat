@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-addons.ps1" backup
pause
