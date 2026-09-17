@echo off
REM Writes a playable ten-photo album to the project's user:// directory.
if "%GODOT%"=="" set GODOT=godot
pushd "%~dp0.."
"%GODOT%" --headless --path . --script tools/make_test_album.gd
popd
