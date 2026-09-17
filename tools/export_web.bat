@echo off
REM Local web export, for testing before pushing.
REM
REM Needs the export templates installed. If "Manage Export Templates" failed
REM to download them, see the README: the archive is 1.3 GB and the reliable
REM route is to download the .tpz by hand and use "Install from File".
REM
REM The result cannot be opened with file:// — browsers block the WebAssembly
REM fetch from a file URL. Serve it instead:
REM   cd build\web && python -m http.server 8080
REM then open http://localhost:8080

setlocal
if "%GODOT%"=="" set GODOT=godot

pushd "%~dp0.."
if not exist "build\web" mkdir "build\web"
"%GODOT%" --headless --path . --export-release "Web" "%CD%\build\web\index.html"
set RESULT=%ERRORLEVEL%
popd

echo.
if %RESULT% NEQ 0 (
  echo EXPORT FAILED ^(exit %RESULT%^)
) else (
  echo Exported to build\web
  echo Serve it:  cd build\web ^&^& python -m http.server 8080
)
endlocal & exit /b %RESULT%
