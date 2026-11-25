@rem cspell:ignore errorlevel
@echo off
powershell.exe -NoProfile -File "%~dp0Install-AI-Edition.ps1"
if errorlevel 1 pause
