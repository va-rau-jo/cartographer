@echo off
REM Sets GODOT to a Godot executable, or exits 9 with instructions.
REM Called with "call tools\find_godot.bat" from the other scripts.

if not "%GODOT%"=="" exit /b 0

for %%N in (godot_console.exe godot.exe godot) do (
  where /q %%N 2>nul && ( endlocal & set "GODOT=%%N" & exit /b 0 )
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
    for /f "delims=" %%F in ('dir /b /s "%%~D\Godot*console*.exe" 2^>nul') do (
      set "GODOT=%%F" & exit /b 0
    )
    for /f "delims=" %%F in ('dir /b /s "%%~D\Godot*.exe" 2^>nul') do (
      set "GODOT=%%F" & exit /b 0
    )
  )
)

echo Could not find Godot. Set it explicitly, for example:
echo   set GODOT=C:\Godot\Godot_v4.7-stable_win64_console.exe
exit /b 9
