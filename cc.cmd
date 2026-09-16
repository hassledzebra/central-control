@echo off
rem central-control entry point -- see cc.ps1 for the commands.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0cc.ps1" %*
