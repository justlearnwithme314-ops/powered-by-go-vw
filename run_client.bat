@echo off
set "GODOT=C:\Users\Admin\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe"
set "PROJECT=D:\Godot stuff\powered-by-go-vw"

if not exist "%GODOT%" (
    echo Godot not found:
    echo %GODOT%
    pause
    exit /b 1
)

"%GODOT%" --path "%PROJECT%"
pause