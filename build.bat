@echo off
rem Assembles every example in the course.
rem Requires fasm.exe on PATH and INCLUDE pointing at FASM's INCLUDE folder.
rem See docs\00-setup.md.

setlocal enabledelayedexpansion

where fasm >nul 2>nul
if errorlevel 1 (
    echo fasm.exe not found on PATH. See docs\00-setup.md
    exit /b 1
)

if "%INCLUDE%"=="" (
    echo INCLUDE is not set. Example: set INCLUDE=C:\fasm\INCLUDE
    exit /b 1
)

set FAILED=0
for /r "%~dp0examples" %%f in (*.asm) do (
    pushd "%%~dpf"
    echo === %%~nxf
    fasm "%%~nxf"
    if errorlevel 1 set FAILED=1
    popd
)

if "%FAILED%"=="1" (
    echo.
    echo One or more files failed to assemble.
    exit /b 1
)
echo.
echo All examples built.
