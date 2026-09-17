@echo off
REM Headless test run.
REM
REM Finds Godot automatically in the usual places. If your install is somewhere
REM unusual, set GODOT first:
REM   set GODOT=D:\Tools\Godot\Godot_v4.7-stable_win64_console.exe
REM
REM Prefers the _console.exe build when it can find one: the plain win64.exe
REM does not attach to a console on Windows, so a --headless run prints
REM nothing. The full report is written to a file either way.

setlocal EnableDelayedExpansion

if not "%GODOT%"=="" goto :found

REM --- 1. anything on PATH ---
for %%N in (godot_console.exe godot.exe godot) do (
  where /q %%N 2>nul && ( set "GODOT=%%N" & goto :found )
)

REM --- 2. the usual install locations, console build first ---
for %%D in (
  "%LOCALAPPDATA%\Programs\Godot"
  "%LOCALAPPDATA%\Godot"
  "%ProgramFiles%\Godot"
  "%ProgramFiles(x86)%\Godot"
  "%USERPROFILE%\Godot"
  "%USERPROFILE%\Downloads"
  "%USERPROFILE%\Desktop"
  "C:\Godot"
  "D:\Godot"
) do (
  if exist %%D (
    for /f "delims=" %%F in ('dir /b /s "%%~D\Godot*console*.exe" 2^>nul') do (
      set "GODOT=%%F" & goto :found
    )
  )
)
for %%D in (
  "%LOCALAPPDATA%\Programs\Godot"
  "%LOCALAPPDATA%\Godot"
  "%ProgramFiles%\Godot"
  "%ProgramFiles(x86)%\Godot"
  "%USERPROFILE%\Godot"
  "%USERPROFILE%\Downloads"
  "%USERPROFILE%\Desktop"
  "C:\Godot"
  "D:\Godot"
) do (
  if exist %%D (
    for /f "delims=" %%F in ('dir /b /s "%%~D\Godot*.exe" 2^>nul') do (
      set "GODOT=%%F" & goto :found
    )
  )
)

REM --- 3. Steam ---
for %%D in (
  "%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine"
  "%ProgramFiles%\Steam\steamapps\common\Godot Engine"
) do (
  if exist %%D (
    for /f "delims=" %%F in ('dir /b /s "%%~D\Godot*.exe" 2^>nul') do (
      set "GODOT=%%F" & goto :found
    )
  )
)

echo.
echo Could not find Godot.
echo.
echo Set GODOT to your executable and run this again, for example:
echo.
echo   set GODOT=C:\Godot\Godot_v4.7-stable_win64_console.exe
echo   tools\run_tests.bat
echo.
echo Searched PATH and: %%LOCALAPPDATA%%\Programs\Godot, %%ProgramFiles%%\Godot,
echo %%USERPROFILE%%\Godot, %%USERPROFILE%%\Downloads, %%USERPROFILE%%\Desktop,
echo C:\Godot, D:\Godot, and the Steam library.
echo.
exit /b 9

:found
echo Using Godot: %GODOT%
if not exist "%GODOT%" (
  where /q "%GODOT%" 2>nul || (
    echo.
    echo That path does not exist. Check the GODOT variable.
    exit /b 9
  )
)
echo.

pushd "%~dp0.."

REM Refresh the import cache before running anything. A --script run reads
REM .godot\global_script_class_cache.cfg exactly as it finds it and never
REM rescans the project, so any class_name added since the editor last ran is
REM simply absent -- and every suite that names it fails to compile with
REM "Could not find type ... in the current scope". --import rebuilds the
REM cache. It is a few seconds once and near-instant afterwards.
"%GODOT%" --headless --path . --import >nul 2>&1
if errorlevel 1 (
  echo WARNING: --import failed. If suites report "did not compile", the
  echo script class cache is stale -- open the project in the Godot editor once,
  echo or point GODOT at an editor build rather than an export template.
  echo.
)

"%GODOT%" --headless --path . --script tests/run_tests.gd
set RESULT=%ERRORLEVEL%
popd

set "REPORT=%APPDATA%\Godot\app_userdata\Chrono Cartographer\test_report.txt"
echo.
if exist "%REPORT%" (
  type "%REPORT%"
) else (
  echo No report was written. Expected it at:
  echo   %REPORT%
  echo.
  echo If Godot printed nothing at all, the run never started -- check the
  echo path above. Exit code was %RESULT%.
)

echo.
if %RESULT% NEQ 0 (
  echo TESTS FAILED ^(exit %RESULT%^)
) else (
  echo All tests passed.
)
endlocal & exit /b %RESULT%
