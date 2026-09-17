@echo off
REM Headless test run. Set GODOT to your Godot 4.7 executable if it is not on PATH.
REM   set GODOT=C:\Godot\Godot_v4.7-stable_win64.exe

if "%GODOT%"=="" set GODOT=godot

pushd "%~dp0.."
"%GODOT%" --headless --path . --script tests/run_tests.gd
set RESULT=%ERRORLEVEL%
popd

if %RESULT% NEQ 0 (
  echo.
  echo TESTS FAILED
) else (
  echo.
  echo All tests passed.
)
exit /b %RESULT%
