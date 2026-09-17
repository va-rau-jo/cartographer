@echo off
REM Headless test run.
REM
REM Set GODOT to your Godot 4.7 executable if it is not on PATH, e.g.
REM   set GODOT=C:\Godot\Godot_v4.7-stable_win64_console.exe
REM
REM Use the _console.exe build if you want to SEE the output in this window:
REM the plain win64.exe does not attach to a console, so it runs the tests
REM silently. Either way the full report is written to
REM   %APPDATA%\Godot\app_userdata\Chrono Cartographer\test_report.txt

setlocal
if "%GODOT%"=="" set GODOT=godot

pushd "%~dp0.."
"%GODOT%" --headless --path . --script tests/run_tests.gd
set RESULT=%ERRORLEVEL%
popd

set REPORT=%APPDATA%\Godot\app_userdata\Chrono Cartographer\test_report.txt
echo.
if exist "%REPORT%" (
  type "%REPORT%"
) else (
  echo No report found at:
  echo   %REPORT%
)

echo.
if %RESULT% NEQ 0 (
  echo TESTS FAILED ^(exit %RESULT%^)
) else (
  echo All tests passed.
)
endlocal & exit /b %RESULT%
