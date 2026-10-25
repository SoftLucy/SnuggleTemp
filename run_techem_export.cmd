@echo off
setlocal
cd /d "%~dp0"
py -3 export_techem_heating.py >> techem_export.log 2>&1
exit /b %errorlevel%
