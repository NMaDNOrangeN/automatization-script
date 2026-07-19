@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul

set "CONFIG=%~dp0tools.cfg"
set "ROOTFILE=%~dp0root.cfg"
set "REPORTDIR=%~dp0reports"
set "LOGDIR=%REPORTDIR%\logs"
set "LOG=%REPORTDIR%\launch_log.csv"
set "REPORT=%REPORTDIR%\report.txt"
set "LOGLOCK=%REPORTDIR%\log.lock"
set "maxcount=0"


if not exist "%REPORTDIR%" mkdir "%REPORTDIR%"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
if not exist "%CONFIG%" type nul > "%CONFIG%"
if not exist "%ROOTFILE%" type nul > "%ROOTFILE%"
if not exist "%LOG%" echo Date;Time;Tool;Arguments;OutputLog> "%LOG%"

call :LOAD_ROOT

if /I "%~1"=="__worker__" goto WORKER_MODE

:MAIN_MENU
cls
echo ==================================================
echo               ЛАУНЧЕР СБОРКИ
echo ==================================================
if defined ROOT (
    echo  Корневой путь: !ROOT!
) else (
    echo  Корневой путь: не задан ^(будут использоваться абсолютные пути^)
)
echo ==================================================
echo  1. Запустить один инструмент
echo  2. Запустить несколько инструментов
echo  3. Сформировать отчёт о запусках
echo  4. Редактор путей к инструментам
echo  5. Выход
echo ==================================================
set /p choice="Выберите пункт меню: "

if "%choice%"=="1" goto RUN_ONE
if "%choice%"=="2" goto RUN_MANY
if "%choice%"=="3" goto REPORT
if "%choice%"=="4" goto EDIT_PATHS
if "%choice%"=="5" goto :EOF
echo Неверный выбор.
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
        echo [Ошибка] Не удалось получить доступ к лог-файлу.
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
set "padval=!padval!"
set "padded=!padval:~0,%padwidth%!"
goto :eof

:LIST_TOOLS
for /l %%i in (1,1,!maxcount!) do (
    set "name%%i="
    set "type%%i="    
    set "path%%i="
)
set count=0
for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG%") do (
    if not "%%A"=="" if not "%%B"=="" (
        set /a count+=1
        set "name!count!=%%A"
        for /f "tokens=1,* delims=|" %%X in ("%%B") do (
	    set "type!count!=%%X"
	    set "path!count!=%%Y"
	)
        call echo !count!. %%A [%%type!count!%%]
    )
)
if !count! GTR !maxcount! set "maxcount=!count!"
if "!count!"=="0" echo (список пуст)
goto :eof

:LIST_TOOLS_FULL
call :LIST_TOOLS >nul
for /l %%i in (1,1,!count!) do (
    call :RESOLVE_PATH "!path%%i!"
    echo %%i. !name%%i! [!type%%i!]
    echo      -^> !resolved!
)
if "!count!"=="0" echo   (список пуст)
goto :eof

:LAUNCH_TOOL
set "idx=%~1"
if not defined idx goto :eof

echo !idx!|findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo [Ошибка] Номер инструмента должен быть положительным числом: !idx!
    goto :eof
)
if !idx! GTR !count! (
    echo [Ошибка] Неверный номер инструмента: !idx!
    goto :eof
)

set "tname=!name%idx%!"
set "ttype=!type%idx%!"

call :RESOLVE_PATH "!path%idx%!"
set "tpath=!resolved!"
for %%F in ("!tpath!") do (
    set "tooldir=%%~dpF"
)

if not exist "!tpath!" (
    echo [Ошибка] Файл не найден: !tpath!
    set "logtime=%time%"
    set "logtime=!logtime:,=.!"
    call :LOG_APPEND "%date%;!logtime!;!tname!;FILE_NOT_FOUND;!TOOLLOG!"
    goto :eof
)

echo Запуск: !tname! (!tpath!) ...
if /I "!ttype!"=="console" (

    echo.
    echo Обнаружен консольный инструмент:
    echo 1. Интерактивный режим
    echo 2. Запуск с параметрами и сохранением лога
    set /p cmode="Выберите режим (1/2): "

    if "!cmode!"=="1" (

        start "!tname!" cmd /k "cd /d ""!tooldir!"" && ""!tpath!"""
        goto :eof

    ) else (

        echo.
        set /p USERARGS="Параметры: "

        set "stamp=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
        set "stamp=!stamp: =0!"
        set "TOOLLOG=%LOGDIR%\!tname!_!stamp!.log"

        pushd "!tooldir!"

        "!tpath!" !USERARGS! > "!TOOLLOG!" 2>&1

        set "exitcode=!errorlevel!"

        popd

        set "logtime=%time%"
        set "logtime=!logtime:,=.!"

        call :LOG_APPEND "%date%;!logtime!;!tname!;!exitcode!;!TOOLLOG!"

        echo.
        echo Лог сохранён:
        echo !TOOLLOG!

        goto :eof
    )

) else (
    set "stamp=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%"
    set "stamp=!stamp: =0!"
    set "TOOLLOG=%LOGDIR%\!tname!_!stamp!.log"
    "%tpath%" > "!TOOLLOG!" 2>&1
    set "exitcode=!errorlevel!"
)
set "exitcode=!errorlevel!"
set "logtime=%time%"
set "logtime=!logtime:,=.!"
for %%F in ("!TOOLLOG!") do set "LOGSIZE=%%~zF"
if "!LOGSIZE!"=="0" (
    del "!TOOLLOG!" >nul 2>&1
    call :LOG_APPEND "%date%;!logtime!;!tname!;!exitcode!;"
) else (
    call :LOG_APPEND "%date%;!logtime!;!tname!;!exitcode!;!TOOLLOG!"
)
echo   -^> "!tname!" завершён с кодом возврата !exitcode!.
goto :eof

:LAUNCH_MANY_ASYNC
set "aidx=%~1"
if not defined aidx goto :eof

echo !aidx!|findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo [Ошибка] Номер инструмента должен быть положительным числом: !aidx!
    goto :eof
)
if !aidx! GTR !count! (
    echo [Ошибка] Неверный номер инструмента: !aidx!
    goto :eof
)

set "aname=!name%aidx%!"
echo Запуск в фоне: !aname!

set "worker_file=%REPORTDIR%\warg_%random%_%random%.tmp"
> "!worker_file!" echo !aname!

echo CreateObject("WScript.Shell").Run """%~f0"" __worker__ ""!worker_file!""", 0, False > "%REPORTDIR%\runw.vbs"
wscript.exe //B "%REPORTDIR%\runw.vbs"

goto :eof

:WORKER_MODE
chcp 65001 >nul
cd /d "%~dp0"
setlocal EnableDelayedExpansion

set "CONFIG=%~dp0tools.cfg"
set "ROOTFILE=%~dp0root.cfg"
set "REPORTDIR=%~dp0reports"
set "LOGDIR=%REPORTDIR%\logs"
set "LOG=%REPORTDIR%\launch_log.csv"

set "worker_file=%~2"
if not defined worker_file exit /b 1

set "wname="
if exist "%worker_file%" (
    set /p wname=<"%worker_file%"
    del "%worker_file%" 2>nul
)

if not defined wname exit /b 1

set "wpath="
set "wtype=gui"
for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG%") do (
    if /I "%%A"=="%wname%" (
        for /f "tokens=1,* delims=|" %%X in ("%%B") do (
            set "wtype=%%X"
            set "wpath=%%Y"
        )
    )
)

if not defined wpath (
    call :LOG_APPEND "%date%;%time%;%wname%;NOT_FOUND;"
    exit /b 1
)

call :RESOLVE_PATH "!wpath!"
set "tpath=!resolved!"
for %%F in ("!tpath!") do set "tooldir=%%~dpF"

if not exist "!tpath!" (
    call :LOG_APPEND "%date%;%time%;%wname%;FILE_NOT_FOUND;"
    exit /b 1
)

set "stamp=%date:~-4%%date:~3,2%%date:~0,2%_%time:~0,2%%time:~3,2%%time:~6,2%_%random%"
set "stamp=!stamp: =0!"
set "TOOLLOG=%LOGDIR%\!wname!_!stamp!.log"

if /I "!wtype!"=="console" (
    start "Tool_!wname!" cmd /k "cd /d "!tooldir!" && "!tpath!""
    set "logtime=%time%"
    set "logtime=!logtime:,=.!"
    call :LOG_APPEND "%date%;!logtime!;!wname!;0;Запущено (интерактивно)"
) else (
    "!tpath!" > "!TOOLLOG!" 2>&1
    set "exitcode=!errorlevel!"
    set "logtime=%time%"
    set "logtime=!logtime:,=.!"
    for %%F in ("!TOOLLOG!") do set "LOGSIZE=%%~zF"
    if "!LOGSIZE!"=="0" (
        del "!TOOLLOG!" >nul 2>&1
        call :LOG_APPEND "%date%;!logtime!;!wname!;!exitcode!;"
    ) else (
        call :LOG_APPEND "%date%;!logtime!;!wname!;!exitcode!;!TOOLLOG!"
    )
)

exit /b 0

:RUN_ONE
cls
echo --- Доступные инструменты ---
call :LIST_TOOLS
if "!count!"=="0" (
    echo Добавьте инструменты через пункт меню 4 в главном меню.
    pause
    goto MAIN_MENU
)
echo.
set /p sel="Номер инструмента для запуска: "
call :LAUNCH_TOOL !sel!
echo.
pause
goto MAIN_MENU

:RUN_MANY
cls
echo --- Доступные инструменты ---
call :LIST_TOOLS
if "!count!"=="0" (
    echo Добавьте инструменты через пункт меню 4 в главном меню.
    pause
    goto MAIN_MENU
)

echo.
echo Введите номера через запятую, например: 1,3,4
set /p sels="Номера: "

echo.
echo Режим запуска:
echo   1. Последовательно ^(ждать завершения каждого перед следующим^)
echo   2. Параллельно ^(все сразу, каждый в своём процессе^)
set /p rmode="Выберите режим (1/2): "

set "sels=!sels:,= !"

if "%rmode%"=="2" (
    for %%s in (!sels!) do (
        if not "%%~s"=="" call :LAUNCH_MANY_ASYNC %%~s
    )

    echo.
    echo Все выбранные инструменты запущены параллельно.
    echo Логи и коды возврата будут сохранены автоматически.
    timeout /t 3 >nul
    goto MAIN_MENU
)

for %%s in (!sels!) do (
    if not "%%~s"=="" call :LAUNCH_TOOL %%~s
)

echo.
echo Групповой запуск завершён.
pause
goto MAIN_MENU

:REPORT
cls
echo --- Формирование отчёта ---
if not exist "%LOG%" (
    echo Лог-файл отсутствует, отчёт не может быть сформирован.
    pause
    goto MAIN_MENU
)

set total=0
set ok=0
set fail=0
for /f "usebackq skip=1 tokens=1-5 delims=;" %%a in ("%LOG%") do (
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
set "C5=100"
set /a TW=C1+C2+C3+C4+C5+4
set "DASHES=----------------------------------------------------------------------------------------------"
set "DIV=!DASHES:~0,%TW%!"

call :PAD "Дата" %C1%
set "H1=!padded!"
call :PAD "Время" %C2%
set "H2=!padded!"
call :PAD "Инструмент" %C3%
set "H3=!padded!"
call :PAD "Код возврата" %C4%
set "H4=!padded!"
call :PAD "Лог инструмента" %C5%
set "H5=!padded!"

call :PAD "Всего запусков:" 24
set "L1=!padded!"
call :PAD "Успешных:" 24
set "L2=!padded!"
call :PAD "Ошибок/не найдено:" 24
set "L3=!padded!"

(
    echo ОТЧЁТ О ЗАПУСКАХ ИНСТРУМЕНТОВ
    echo Сформирован: %date% %time%
    echo !DIV!
    echo !L1!!total!
    echo !L2!!ok!
    echo !L3!!fail!
    echo !DIV!
    echo !H1! ^| !H2! ^| !H3! ^| !H4! ^| !H5!
    echo !DIV!
) > "%REPORT%"

for /f "usebackq skip=1 tokens=1-5 delims=;" %%a in ("%LOG%") do (
    call :PAD "%%a" %C1%
    set "R1=!padded!"
    call :PAD "%%b" %C2%
    set "R2=!padded!"
    call :PAD "%%c" %C3%
    set "R3=!padded!"
    call :PAD "%%d" %C4%
    set "R4=!padded!"
    call :PAD "%%e" %C5%
    set "R5=!padded!"
    echo !R1! ^| !R2! ^| !R3! ^| !R4! ^| !R5!>> "%REPORT%"
)

echo !DIV!>> "%REPORT%"

echo.>> "%REPORT%"
echo =====================================================>> "%REPORT%"
echo ЛОГИ ВЫВОДА ИНСТРУМЕНТОВ>> "%REPORT%"
echo =====================================================>> "%REPORT%"

for /f "usebackq skip=1 tokens=1-5 delims=;" %%a in ("%LOG%") do (
    echo.>> "%REPORT%"
    echo Инструмент: %%c>> "%REPORT%"
    echo Код возврата: %%d>> "%REPORT%"
    echo Файл лога: %%e>> "%REPORT%"
    echo -------------------------------------------------->> "%REPORT%"

    if exist "%%e" (
        type "%%e" >> "%REPORT%"
    ) else (
        echo [Нет вывода в консоль или файл лога не найден]>> "%REPORT%"
    )

    echo.>> "%REPORT%"
    echo -------------------------------------------------->> "%REPORT%"
)

echo Отчёт сохранён: %REPORT%
pause
goto MAIN_MENU

:EDIT_PATHS
cls
echo --- Редактор путей к инструментам ---
if defined ROOT (
    echo  Текущий корневой путь: !ROOT!
) else (
    echo  Корневой путь не задан.
)
echo.
echo  1. Показать список ^(с разрешёнными путями^)
echo  2. Добавить новый инструмент
echo  3. Изменить существующий путь
echo  4. Удалить инструмент
echo  5. Задать/изменить корневой путь
echo  6. Назад в главное меню
set /p ech="Выберите действие: "

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
echo --- Корневой путь ---
if defined ROOT (
    echo Текущее значение: !ROOT!
) else (
    echo Сейчас не задан - все пути в tools.cfg считаются абсолютными.
)
echo.
echo Введите новую папку ^(например D:\Tools\Programs^).
echo Оставьте строку пустой и нажмите Enter, чтобы отключить корневой путь.
set /p newroot="Новый корневой путь: "
if "!newroot:~-1!"=="\" set "newroot=!newroot:~0,-1!"
> "%ROOTFILE%" (
    if not "%newroot%"=="" echo %newroot%
)
call :LOAD_ROOT
if defined ROOT (
    echo Корневой путь задан: !ROOT!
) else (
    echo Корневой путь отключён; пути в tools.cfg должны быть абсолютными.
)
pause
goto EDIT_PATHS

:EDIT_ADD
cls
set /p newname="Имя инструмента: "
if "%newname%"=="" (
    echo Имя не может быть пустым.
    pause
    goto EDIT_PATHS
)

call :LIST_TOOLS >nul
set "dup="
for /l %%i in (1,1,!count!) do (
    if /I "!name%%i!"=="!newname!" set "dup=1"
)
if defined dup (
    echo Инструмент с именем "!newname!" уже существует.
    pause
    goto EDIT_PATHS
)

echo.
echo Тип инструмента:
echo   1. GUI ^(по умолчанию^)
echo   2. Консольный
set /p ttype="Выберите тип (1/2, Enter=1): "
if not defined ttype set "ttype=1"
if "%ttype%"=="1" (
    set "tooltype=gui"
) else if "%ttype%"=="2" (
    set "tooltype=console"
) else (
    echo Неверный тип, будет использован GUI по умолчанию.
    set "tooltype=gui"
)

if defined ROOT (
    echo Корневой путь задан ^(!ROOT!^) - вы можете ввести
    echo относительный путь ^(например Tool\Tool.exe^)
    echo или полный абсолютный путь ^(C:\...^).
) else (
    echo Корневой путь не задан - введите полный путь к exe-файлу.
)
set /p newpath="Путь к exe-файлу: "
if "%newpath%"=="" (
    echo Путь не может быть пустым.
    pause
    goto EDIT_PATHS
)

>> "%CONFIG%" echo.
>> "%CONFIG%" echo(!newname!=!tooltype!^|!newpath!
echo Инструмент "!newname!" ^(!tooltype!^) добавлен.
pause
goto EDIT_PATHS

:EDIT_MODIFY
cls
call :LIST_TOOLS
if "!count!"=="0" (
    pause
    goto EDIT_PATHS
)
set /p midx="Номер инструмента для изменения: "
echo !midx!|findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo Неверный номер.
    pause
    goto EDIT_PATHS
)
if !midx! GTR !count! (
    echo Неверный номер.
    pause
    goto EDIT_PATHS
)
set "mname=!name%midx%!"
set "mtype=!type%midx%!"
echo Текущий инструмент: !mname! [!mtype!]
echo.
set /p newpath="Новый путь (оставьте пустым, чтобы сохранить текущий): "
if "%newpath%"=="" set "newpath=!path%midx%!"
echo.
echo Текущий тип: !mtype!
echo Изменить тип? (1=GUI, 2=Консольный, Enter=оставить текущий)
set /p newtype="Выбор (1/2/Enter): "
if not defined newtype (
    set "newtype=!mtype!"
) else if "%newtype%"=="1" (
    set "newtype=gui"
) else if "%newtype%"=="2" (
    set "newtype=console"
) else (
    set "newtype=!mtype!"
)

> "%CONFIG%.tmp" (
    for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG%") do (
        if not "%%A"=="" if not "%%B"=="" (
            if /I "%%A"=="!mname!" (
                echo(%%A=!newtype!^|!newpath!
            ) else (
                echo %%A=%%B
            )
        )
    )
)
move /y "%CONFIG%.tmp" "%CONFIG%" >nul
echo Инструмент "!mname!" обновлён: !newtype! ^| !newpath!
pause
goto EDIT_PATHS

:EDIT_DELETE
cls
call :LIST_TOOLS
if "!count!"=="0" (
    pause
    goto EDIT_PATHS
)
set /p didx="Номер инструмента для удаления: "
echo !didx!|findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo Неверный номер.
    pause
    goto EDIT_PATHS
)
if !didx! GTR !count! (
    echo Неверный номер.
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
echo Инструмент "!dname!" удалён.
pause
goto EDIT_PATHS