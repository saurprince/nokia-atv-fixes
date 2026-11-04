@echo off
rem Double-click helper for Windows: asks for the TV's address, then runs scripts\debloat.ps1.
rem Needs adb (Android platform-tools) on the PATH. Nothing is uninstalled; "undo" puts everything back.
setlocal
echo.
echo  Nokia ATV helper
echo  Make sure the TV is on and "USB debugging" is switched on (see README.md).
echo.
set /p TV=TV IP address (Settings ^> Network, for example 192.168.1.20):
echo.
echo   1 = show the state of each app in the list (safe, changes nothing)
echo   2 = back up, then disable the apps in the list
echo   3 = undo (switch the apps back on)
echo.
set /p CHOICE=Choose 1, 2 or 3:
set ACTION=
if "%CHOICE%"=="1" set ACTION=status
if "%CHOICE%"=="2" set ACTION=apply
if "%CHOICE%"=="3" set ACTION=restore
if not defined ACTION (
  echo Not a valid choice.
  pause
  exit /b 1
)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\debloat.ps1" %TV% %ACTION%
echo.
pause
