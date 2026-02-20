@echo off
REM Build script for RISE Client on Windows

echo === Building RISE Client ===

REM Set JavaFX path
set JAVAFX_PATH=%~dp0openjfx-25.0.2_windows-x64_bin-sdk\javafx-sdk-25.0.2\lib

REM Clean and compile
echo Compiling...
call mvn clean package -DskipTests

if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    exit /b 1
)

REM Create executable with jpackage
echo Creating executable...
call jpackage --input target --main-jar rise-client-1.0.0.jar --name RISE --type exe --app-version 1.0.0 --module-path "%JAVAFX_PATH%" --add-modules javafx.controls,javafx.fxml,javafx.graphics,javafx.base

echo === Done! ===
echo RISE.exe is ready in the current folder
