@echo off
REM DualClock for Windows v2.2 - builds DualClock.exe (with its "Two Hands" icon) using the
REM C# compiler built into Windows (.NET Framework 4.x). Keep this .bat next to DualClock.cs and double-click it.

setlocal
cd /d "%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
  echo Could not find csc.exe. .NET Framework 4.x is required ^(standard on Windows 10/11^).
  pause
  exit /b 1
)

REM Close a running copy so the exe can be replaced
taskkill /im DualClock.exe /f >nul 2>&1

set "OPTS=/nologo /target:winexe /optimize+ /r:System.Windows.Forms.dll /r:System.Drawing.dll"

REM Pass 1: plain build, used only to draw the icon
"%CSC%" %OPTS% /out:DualClock.exe DualClock.cs
if errorlevel 1 goto fail
DualClock.exe --make-icon DualClock.ico
if errorlevel 1 goto fail

REM Pass 2: final build with the icon embedded
"%CSC%" %OPTS% /win32icon:DualClock.ico /out:DualClock.exe DualClock.cs
if errorlevel 1 goto fail

echo.
echo Built DualClock.exe

REM v2.2 is one app with a 12h ^| 12/24 ^| 24h switch: replace the old per-mode shortcuts with one
del /q "DualClock 12h.lnk" "DualClock 24h.lnk" >nul 2>&1
powershell -NoProfile -Command "$w=New-Object -ComObject WScript.Shell; $s=$w.CreateShortcut((Join-Path '%~dp0' 'DualClock.lnk')); $s.TargetPath=(Join-Path '%~dp0' 'DualClock.exe'); $s.WorkingDirectory='%~dp0'; $s.IconLocation=(Join-Path '%~dp0' 'DualClock.exe')+',0'; $s.Save()"
echo Created shortcut: "DualClock"

start "" "DualClock.exe"
endlocal
exit /b 0

:fail
echo.
echo Build failed.
pause
exit /b 1
