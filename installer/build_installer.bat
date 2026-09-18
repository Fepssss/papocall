@echo off
title Gerar Instalador PapoCall
cd /d "%~dp0\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "installer\build_installer.ps1"
pause
