@echo off
REM Builds DualClock.exe using the C# compiler built into Windows (.NET Framework 4.x).
REM Keep this .bat in the same folder as DualClock.cs and double-click it.

setlocal
cd /d "%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
  echo Could not find csc.exe. .NET Framework 4.x is required ^(standard on Windows 10/11^).
  pause
  exit /b 1
)

"%CSC%" /nologo /target:winexe /optimize+ /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:DualClock.exe "DualClock.cs"
if errorlevel 1 (
  echo.
  echo Build failed.
  pause
  exit /b 1
)

echo.
echo Built DualClock.exe

REM Create two shortcuts in this folder: a dedicated 12-hour clock and a dedicated 24-hour clock.
powershell -NoProfile -Command "$w=New-Object -ComObject WScript.Shell; foreach($m in '12','24'){ $s=$w.CreateShortcut((Join-Path '%~dp0' ('DualClock '+$m+'h.lnk'))); $s.TargetPath=(Join-Path '%~dp0' 'DualClock.exe'); $s.Arguments='/'+$m; $s.WorkingDirectory='%~dp0'; $s.Save() }"
echo Created shortcuts: "DualClock 12h" and "DualClock 24h"

start "" "DualClock.exe" /12
start "" "DualClock.exe" /24
endlocal
