@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul

set "CONFIG=%~dp0tools.cfg"
set "ROOTFILE=%~dp0root.cfg"
set "LOG=%~dp0launch_log.csv"
set "REPORT=%~dp0report.txt"
set "LOGLOCK=%~dp0.log.lock"
set "maxcount=0"

if not exist "%CONFIG%" type nul > "%CONFIG%"
if not exist "%ROOTFILE%" type nul > "%ROOTFILE%"
if not exist "%LOG%" echo Date;Time;Tool;ExitCode> "%LOG%"

call :LOAD_ROOT

if /I "%~1"=="__worker__" goto WORKER_MODE

:MAIN_MENU
cls
echo ==================================================
echo            BUILD LAUNCHER
echo ==================================================
if defined ROOT (
    echo  Root PATH: !ROOT!
) else (
    echo  Root PATH: not set ^(absolute paths will be used^)
)
echo ==================================================
echo  1. Run one tool
echo  2. Run multiple tools
echo  3. Generate run report
echo  4. Tool paths editor
echo  5. Exit
echo ==================================================
set /p choice="Select menu item: "

if "%choice%"=="1" goto RUN_ONE
if "%choice%"=="2" goto RUN_MANY
if "%choice%"=="3" goto REPORT
if "%choice%"=="4" goto EDIT_PATHS
if "%choice%"=="5" goto :EOF
echo Invalid selection.
pause
goto MAIN_MENU

:LOAD_ROOT
set "ROOT="
if exist "%ROOTFILE%" (
    for /f "usebackq delims=" %%R in ("%ROOTFILE%") do (
        if not defined ROOT if not "%%R"=="" set "ROOT=%%R"
    )
)
if defined ROOT (
    if "!ROOT:~-1!"=="\" set "ROOT=!ROOT:~0,-1!"
)
goto :eof

:RESOLVE_PATH
set "rp=%~1"
if "%rp%"=="" (
    set "resolved="
    goto :eof
)
if "%rp:~1,1%"==":" (
    set "resolved=%rp%"
    goto :eof
)
if "%rp:~0,2%"=="\\" (
    set "resolved=%rp%"
    goto :eof
)
if defined ROOT (
    set "resolved=%ROOT%\%rp%"
) else (
    set "resolved=%rp%"
)
goto :eof

:LOG_APPEND
set "loglock_tries=0"

:LOG_RETRY
mkdir "%LOGLOCK%" 2>nul

if errorlevel 1 (
    set /a loglock_tries+=1

    if !loglock_tries! geq 50 (
        echo [Error] Could not access the log.
        goto :eof
    )

    timeout /t 1 >nul
    goto LOG_RETRY
)

>> "%LOG%" echo %~1

rmdir "%LOGLOCK%" 2>nul
goto :eof

:PAD
set "padval=%~1"
set "padwidth=%~2"
set "padval=!padval!                                                                "
set "padded=!padval:~0,%padwidth%!"
goto :eof

:LIST_TOOLS
for /l %%i in (1,1,!maxcount!) do (
    set "name%%i="
    set "path%%i="
)
set count=0
for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG%") do (
    if not "%%A"=="" if not "%%B"=="" (
        set /a count+=1
        set "name!count!=%%A"
        set "path!count!=%%B"
        echo !count!. %%A
    )
)
if !count! GTR !maxcount! set "maxcount=!count!"
if "!count!"=="0" echo   (list empty)
goto :eof

:LIST_TOOLS_FULL
call :LIST_TOOLS >nul
for /l %%i in (1,1,!count!) do (
    call :RESOLVE_PATH "!path%%i!"
    echo %%i. !name%%i!
    echo      -^> !resolved!
)
if "!count!"=="0" echo   (list empty)
goto :eof

:LAUNCH_TOOL
set "idx=%~1"
if not defined idx goto :eof

echo !idx!|findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo [Error] Tool number must be a positive number: !idx!
    goto :eof
)
if !idx! GTR !count! (
    echo [Error] Invalid tool number: !idx!
    goto :eof
)

set "tname=!name%idx%!"
call :RESOLVE_PATH "!path%idx%!"
set "tpath=!resolved!"

if not exist "!tpath!" (
    echo [Error] File not found: !tpath!
    set "logtime=%time%"
    set "logtime=!logtime:,=.!"
    call :LOG_APPEND "%date%;!logtime!;!tname!;FILE_NOT_FOUND"
    goto :eof
)

echo Running: !tname! (!tpath!) ...
"%tpath%"
set "exitcode=!errorlevel!"
set "logtime=%time%"
set "logtime=!logtime:,=.!"
call :LOG_APPEND "%date%;!logtime!;!tname!;!exitcode!"
echo   -^> "!tname!" finished with exit code !exitcode!.
goto :eof

:LAUNCH_MANY_ASYNC
set "aidx=%~1"
if not defined aidx goto :eof

echo !aidx!|findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo [Error] Tool number must be a positive number: !aidx!
    goto :eof
)
if !aidx! GTR !count! (
    echo [Error] Invalid tool number: !aidx!
    goto :eof
)

set "aname=!name%aidx%!"
echo Starting in background: !aname!
start "!aname!" cmd /c call "%~f0" __worker__ "!aname!"
goto :eof

:WORKER_MODE
setlocal EnableDelayedExpansion
set "wname=%~2"
set "wpath="
for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG%") do (
    if not "%%A"=="" if not "%%B"=="" (
        if /I "%%A"=="%wname%" set "wpath=%%B"
    )
)
if not defined wpath (
    echo [Error] Tool "%wname%" not found in tools.cfg.
    timeout /t 3 >nul
    exit /b 1
)

call :RESOLVE_PATH "!wpath!"
set "tpath=!resolved!"

if not exist "!tpath!" (
    echo [Error] File not found: !tpath!
    set "logtime=%time%"
    set "logtime=!logtime:,=.!"
    call :LOG_APPEND "%date%;!logtime!;!wname!;FILE_NOT_FOUND"
    timeout /t 3 >nul
    exit /b 1
)

echo Running: !wname! ^(!tpath!^) ...
"%tpath%"
set "exitcode=!errorlevel!"
set "logtime=%time%"
set "logtime=!logtime:,=.!"
call :LOG_APPEND "%date%;!logtime!;!wname!;!exitcode!"
echo !wname! finished with exit code !exitcode!.
timeout /t 2 >nul
exit /b 0

:RUN_ONE
cls
echo --- Available tools ---
call :LIST_TOOLS
if "!count!"=="0" (
    echo Add tools through menu item 4 in the main menu.
    pause
    goto MAIN_MENU
)
echo.
set /p sel="Tool number to run: "
call :LAUNCH_TOOL !sel!
echo.
pause
goto MAIN_MENU

:RUN_MANY
cls
echo --- Available tools ---
call :LIST_TOOLS
if "!count!"=="0" (
    echo Add tools through menu item 4 in the main menu.
    pause
    goto MAIN_MENU
)
echo.
echo Enter numbers separated by commas, for example: 1,3,4
set /p sels="Numbers: "
echo.
echo Run mode:
echo   1. Sequentially ^(wait for each to finish before the next^)
echo   2. In parallel ^(all at once, each in its own window^)
set /p rmode="Select mode (1/2): "
set "sels=!sels:,= !"

if "%rmode%"=="2" (
    for %%s in (!sels!) do (
        if not "%%~s"=="" call :LAUNCH_MANY_ASYNC %%~s
    )
    echo.
    echo All selected tools have been started in parallel, each in its own window.
    echo Log entries will be added as each one finishes.
    echo Generate a report ^(menu item 3^) later once all windows are closed.
) else (
    for %%s in (!sels!) do (
        if not "%%~s"=="" call :LAUNCH_TOOL %%~s
    )
    echo.
    echo Bulk run completed.
)
pause
goto MAIN_MENU

:REPORT
cls
echo --- Generating report ---
if not exist "%LOG%" (
    echo The log is missing, so the report cannot be generated.
    pause
    goto MAIN_MENU
)

set total=0
set ok=0
set fail=0
for /f "usebackq skip=1 tokens=1-4 delims=;" %%a in ("%LOG%") do (
    set /a total+=1

    if /I "%%d"=="FILE_NOT_FOUND" (
        set /a fail+=1
    ) else (
        set /a ok+=1
    )
)

set "C1=12"
set "C2=14"
set "C3=26"
set "C4=16"
set /a TW=C1+C2+C3+C4+9
set "DASHES=----------------------------------------------------------------------------------------------"
set "DIV=!DASHES:~0,%TW%!"

call :PAD "Date" %C1%
set "H1=!padded!"
call :PAD "Time" %C2%
set "H2=!padded!"
call :PAD "Tool" %C3%
set "H3=!padded!"
call :PAD "Exit code" %C4%
set "H4=!padded!"

call :PAD "Total runs:" 24
set "L1=!padded!"
call :PAD "Successful:" 24
set "L2=!padded!"
call :PAD "Failed/not found:" 24
set "L3=!padded!"

(
    echo TOOL RUN REPORT
    echo Generated: %date% %time%
    echo !DIV!
    echo !L1!!total!
    echo !L2!!ok!
    echo !L3!!fail!
    echo !DIV!
    echo !H1! ^| !H2! ^| !H3! ^| !H4!
    echo !DIV!
) > "%REPORT%"

for /f "usebackq skip=1 tokens=1-4 delims=;" %%a in ("%LOG%") do (
    call :PAD "%%a" %C1%
    set "R1=!padded!"
    call :PAD "%%b" %C2%
    set "R2=!padded!"
    call :PAD "%%c" %C3%
    set "R3=!padded!"
    call :PAD "%%d" %C4%
    set "R4=!padded!"
    echo !R1! ^| !R2! ^| !R3! ^| !R4!>> "%REPORT%"
)

echo !DIV!>> "%REPORT%"

echo Report saved: %REPORT%
pause
goto MAIN_MENU

:EDIT_PATHS
cls
echo --- Tool paths editor ---
if defined ROOT (
    echo  Current root PATH: !ROOT!
) else (
    echo  Root PATH is not set.
)
echo.
echo  1. Show list ^(with resolved paths^)
echo  2. Add a new tool
echo  3. Change an existing path
echo  4. Delete a tool
echo  5. Set/change the root PATH
echo  6. Back to main menu
set /p ech="Select action: "

if "%ech%"=="1" goto EDIT_SHOW
if "%ech%"=="2" goto EDIT_ADD
if "%ech%"=="3" goto EDIT_MODIFY
if "%ech%"=="4" goto EDIT_DELETE
if "%ech%"=="5" goto EDIT_ROOT
if "%ech%"=="6" goto MAIN_MENU
goto EDIT_PATHS

:EDIT_SHOW
cls
call :LIST_TOOLS_FULL
pause
goto EDIT_PATHS

:EDIT_ROOT
cls
echo --- Root PATH ---
if defined ROOT (
    echo Current value: !ROOT!
) else (
    echo Currently not set - all paths in tools.cfg are treated as absolute.
)
echo.
echo Enter a new folder ^(for example D:\Tools\Programs^).
echo Leave the line empty and press Enter to disable PATH.
set /p newroot="New root PATH: "
if "!newroot:~-1!"=="\" set "newroot=!newroot:~0,-1!"
> "%ROOTFILE%" (
    if not "%newroot%"=="" echo %newroot%
)
call :LOAD_ROOT
if defined ROOT (
    echo Root PATH set: !ROOT!
) else (
    echo Root PATH disabled; paths in tools.cfg must be absolute.
)
pause
goto EDIT_PATHS

:EDIT_ADD
cls
set /p newname="Tool name: "
if "%newname%"=="" (
    echo Name cannot be empty.
    pause
    goto EDIT_PATHS
)

call :LIST_TOOLS >nul
set "dup="
for /l %%i in (1,1,!count!) do (
    if /I "!name%%i!"=="!newname!" set "dup=1"
)
if defined dup (
    echo A tool named "!newname!" already exists.
    pause
    goto EDIT_PATHS
)

if defined ROOT (
    echo Root PATH is set ^(!ROOT!^) - you can enter
    echo a relative path ^(for example Tool\Tool.exe^)
    echo or a full absolute path ^(C:\...^).
) else (
    echo Root PATH is not set - enter the full path to the exe file.
)
set /p newpath="Path to the exe file: "
if "%newpath%"=="" (
    echo Path cannot be empty.
    pause
    goto EDIT_PATHS
)
echo !newname!=!newpath!>> "%CONFIG%"
echo Tool "!newname!" added.
pause
goto EDIT_PATHS

:EDIT_MODIFY
cls
call :LIST_TOOLS
if "!count!"=="0" (
    pause
    goto EDIT_PATHS
)
set /p midx="Tool number to change: "
echo !midx!|findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo Invalid number.
    pause
    goto EDIT_PATHS
)
if !midx! GTR !count! (
    echo Invalid number.
    pause
    goto EDIT_PATHS
)
set "mname=!name%midx%!"
set /p newpath="New path for "!mname!" (absolute or relative to PATH): "
if "%newpath%"=="" (
    echo Path cannot be empty.
    pause
    goto EDIT_PATHS
)
> "%CONFIG%.tmp" (
    for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG%") do (
        if not "%%A"=="" if not "%%B"=="" (
            if /I "%%A"=="!mname!" (
                echo %%A=!newpath!
            ) else (
                echo %%A=%%B
            )
        )
    )
)
move /y "%CONFIG%.tmp" "%CONFIG%" >nul
echo Path for "!mname!" updated.
pause
goto EDIT_PATHS

:EDIT_DELETE
cls
call :LIST_TOOLS
if "!count!"=="0" (
    pause
    goto EDIT_PATHS
)
set /p didx="Tool number to delete: "
echo !didx!|findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo Invalid number.
    pause
    goto EDIT_PATHS
)
if !didx! GTR !count! (
    echo Invalid number.
    pause
    goto EDIT_PATHS
)
set "dname=!name%didx%!"
> "%CONFIG%.tmp" (
    for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG%") do (
        if not "%%A"=="" if not "%%B"=="" (
            if /I not "%%A"=="!dname!" echo %%A=%%B
        )
    )
)
move /y "%CONFIG%.tmp" "%CONFIG%" >nul
echo Tool "!dname!" deleted.
pause
goto EDIT_PATHS