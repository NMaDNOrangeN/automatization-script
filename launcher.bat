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
echo            ЛАУНЧЕР СБОРКИ ПРОГРАММ
echo ==================================================
if defined ROOT (
    echo  Корневой PATH: !ROOT!
) else (
    echo  Корневой PATH: не задан ^(используются абсолютные пути^)
)
echo ==================================================
echo  1. Запустить один инструмент
echo  2. Массовый запуск инструментов
echo  3. Сгенерировать отчёт о запусках
echo  4. Редактор путей к инструментам
echo  5. Выход
echo ==================================================
set /p choice="Выберите пункт меню: "

if "%choice%"=="1" goto RUN_ONE
if "%choice%"=="2" goto RUN_MANY
if "%choice%"=="3" goto REPORT
if "%choice%"=="4" goto EDIT_PATHS
if "%choice%"=="5" goto :EOF
echo Некорректный выбор.
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
        echo [Ошибка] Не удалось получить доступ к логу.
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
if "!count!"=="0" echo   (список пуст)
goto :eof

:LIST_TOOLS_FULL
call :LIST_TOOLS >nul
for /l %%i in (1,1,!count!) do (
    call :RESOLVE_PATH "!path%%i!"
    echo %%i. !name%%i!
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
call :RESOLVE_PATH "!path%idx%!"
set "tpath=!resolved!"

if not exist "!tpath!" (
    echo [Ошибка] Файл не найден: !tpath!
    set "logtime=%time%"
    set "logtime=!logtime:,=.!"
    call :LOG_APPEND "%date%;!logtime!;!tname!;FILE_NOT_FOUND"
    goto :eof
)

echo Запуск: !tname! (!tpath!) ...
"%tpath%"
set "exitcode=!errorlevel!"
set "logtime=%time%"
set "logtime=!logtime:,=.!"
call :LOG_APPEND "%date%;!logtime!;!tname!;!exitcode!"
echo   -^> "!tname!" завершён с кодом !exitcode!.
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
    echo [Ошибка] Инструмент "%wname%" не найден в tools.cfg.
    timeout /t 3 >nul
    exit /b 1
)

call :RESOLVE_PATH "!wpath!"
set "tpath=!resolved!"

if not exist "!tpath!" (
    echo [Ошибка] Файл не найден: !tpath!
    set "logtime=%time%"
    set "logtime=!logtime:,=.!"
    call :LOG_APPEND "%date%;!logtime!;!wname!;FILE_NOT_FOUND"
    timeout /t 3 >nul
    exit /b 1
)

echo Запуск: !wname! ^(!tpath!^) ...
"%tpath%"
set "exitcode=!errorlevel!"
set "logtime=%time%"
set "logtime=!logtime:,=.!"
call :LOG_APPEND "%date%;!logtime!;!wname!;!exitcode!"
echo !wname! завершён с кодом !exitcode!.
timeout /t 2 >nul
exit /b 0

:RUN_ONE
cls
echo --- Доступные инструменты ---
call :LIST_TOOLS
if "!count!"=="0" (
    echo Добавьте инструменты через пункт 4 главного меню.
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
    echo Добавьте инструменты через пункт 4 главного меню.
    pause
    goto MAIN_MENU
)
echo.
echo Введите номера через запятую, например: 1,3,4
set /p sels="Номера: "
echo.
echo Режим запуска:
echo   1. Последовательно ^(ждать завершения каждого перед следующим^)
echo   2. Параллельно ^(все сразу, каждый в своём окне^)
set /p rmode="Выберите режим (1/2): "
set "sels=!sels:,= !"

if "%rmode%"=="2" (
    for %%s in (!sels!) do (
        if not "%%~s"=="" call :LAUNCH_MANY_ASYNC %%~s
    )
    echo.
    echo Все выбранные инструменты запущены параллельно, каждый в своём окне.
    echo Строки в лог будут добавляться по мере завершения каждого из них.
    echo Сформируйте отчёт ^(пункт 3^) позже, когда все окна закроются.
) else (
    for %%s in (!sels!) do (
        if not "%%~s"=="" call :LAUNCH_TOOL %%~s
    )
    echo.
    echo Массовый запуск завершён.
)
pause
goto MAIN_MENU

:REPORT
cls
echo --- Генерация отчёта ---
if not exist "%LOG%" (
    echo Лог отсутствует, отчёт сформировать нельзя.
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

call :PAD "Дата" %C1%
set "H1=!padded!"
call :PAD "Время" %C2%
set "H2=!padded!"
call :PAD "Инструмент" %C3%
set "H3=!padded!"
call :PAD "Код завершения" %C4%
set "H4=!padded!"

call :PAD "Всего запусков:" 24
set "L1=!padded!"
call :PAD "Успешных:" 24
set "L2=!padded!"
call :PAD "С ошибкой/не найден:" 24
set "L3=!padded!"

(
    echo ОТЧЁТ О ЗАПУСКАХ ИНСТРУМЕНТОВ
    echo Сформирован: %date% %time%
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

echo Отчёт сохранён: %REPORT%
pause
goto MAIN_MENU

:EDIT_PATHS
cls
echo --- Редактор путей к инструментам ---
if defined ROOT (
    echo  Текущий корневой PATH: !ROOT!
) else (
    echo  Корневой PATH не задан.
)
echo.
echo  1. Показать список ^(с разрешёнными путями^)
echo  2. Добавить новый инструмент
echo  3. Изменить путь существующего
echo  4. Удалить инструмент
echo  5. Задать/изменить корневой PATH
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
echo --- Корневой PATH ---
if defined ROOT (
    echo Текущее значение: !ROOT!
) else (
    echo Сейчас не задан - все пути в tools.cfg считаются абсолютными.
)
echo.
echo Введите новую папку ^(например D:\Инструменты\Программы^).
echo Оставьте строку пустой и нажмите Enter, чтобы отключить PATH.
set /p newroot="Новый корневой PATH: "
if "!newroot:~-1!"=="\" set "newroot=!newroot:~0,-1!"
> "%ROOTFILE%" (
    if not "%newroot%"=="" echo %newroot%
)
call :LOAD_ROOT
if defined ROOT (
    echo Корневой PATH установлен: !ROOT!
) else (
    echo Корневой PATH отключён, пути в tools.cfg должны быть абсолютными.
)
pause
goto EDIT_PATHS

:EDIT_ADD
cls
set /p newname="Название инструмента: "
if "%newname%"=="" (
    echo Название не может быть пустым.
    pause
    goto EDIT_PATHS
)

call :LIST_TOOLS >nul
set "dup="
for /l %%i in (1,1,!count!) do (
    if /I "!name%%i!"=="!newname!" set "dup=1"
)
if defined dup (
    echo Инструмент с названием "!newname!" уже существует.
    pause
    goto EDIT_PATHS
)

if defined ROOT (
    echo Корневой PATH задан ^(!ROOT!^) - можно ввести
    echo относительный путь ^(например Tool\Tool.exe^)
    echo либо полный абсолютный путь ^(C:\...^).
) else (
    echo Корневой PATH не задан - вводите полный путь к exe-файлу.
)
set /p newpath="Путь к exe-файлу: "
if "%newpath%"=="" (
    echo Путь не может быть пустым.
    pause
    goto EDIT_PATHS
)
echo !newname!=!newpath!>> "%CONFIG%"
echo Инструмент "!newname!" добавлен.
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
set /p newpath="Новый путь для "!mname!" (абсолютный или относительный к PATH): "
if "%newpath%"=="" (
    echo Путь не может быть пустым.
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
echo Путь для "!mname!" обновлён.
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