@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

rem =====================================================
rem   Лаунчер сборки программ
rem   Файлы, используемые скриптом (лежат рядом с .bat):
rem     tools.cfg      - список инструментов (Название=Путь)
rem     launch_log.csv - лог всех запусков
rem     report.txt     - формируемый отчёт
rem =====================================================

set "CONFIG=%~dp0tools.cfg"
set "LOG=%~dp0launch_log.csv"
set "REPORT=%~dp0report.txt"

if not exist "%CONFIG%" type nul > "%CONFIG%"
if not exist "%LOG%" echo Дата,Время,Инструмент,КодЗавершения> "%LOG%"

:MAIN_MENU
cls
echo ==================================================
echo            ЛАУНЧЕР СБОРКИ ПРОГРАММ
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

rem -----------------------------------------------------
rem  Подпрограмма: читает CONFIG и выводит пронумерованный
rem  список. Заполняет name1..nameN / path1..pathN и count.
rem -----------------------------------------------------
:LIST_TOOLS
set count=0
for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG%") do (
    if not "%%A"=="" (
        set /a count+=1
        set "name!count!=%%A"
        set "path!count!=%%B"
        echo !count!. %%A
    )
)
if "!count!"=="0" echo   (список пуст)
goto :eof

rem -----------------------------------------------------
rem  Подпрограмма: запуск одного инструмента по индексу %1
rem  Пишет строку в лог в любом случае (успех/ошибка).
rem -----------------------------------------------------
:LAUNCH_TOOL
set "idx=%~1"
set "tname=!name%idx%!"
set "tpath=!path%idx%!"

if not defined tname (
    echo [Ошибка] Неверный номер инструмента: %idx%
    goto :eof
)
if not exist "!tpath!" (
    echo [Ошибка] Файл не найден: !tpath!
    set "logtime=%time%"
    set "logtime=!logtime:,=.!"
    echo %date%,!logtime!,!tname!,FILE_NOT_FOUND>> "%LOG%"
    goto :eof
)

echo Запуск: !tname! ...
start "" /wait "!tpath!"
set "exitcode=!errorlevel!"
set "logtime=%time%"
set "logtime=!logtime:,=.!"
echo %date%,!logtime!,!tname!,!exitcode!>> "%LOG%"
echo   -> "!tname!" завершён с кодом !exitcode!.
goto :eof

rem -----------------------------------------------------
rem  Пункт 1: запуск одного инструмента
rem -----------------------------------------------------
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

rem -----------------------------------------------------
rem  Пункт 2: массовый запуск нескольких инструментов
rem -----------------------------------------------------
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
set "sels=!sels:,= !"
for %%s in (!sels!) do (
    if not "%%~s"=="" call :LAUNCH_TOOL %%~s
)
echo.
echo Массовый запуск завершён.
pause
goto MAIN_MENU

rem -----------------------------------------------------
rem  Пункт 3: генерация отчёта из уже накопленного лога
rem  (не запускает ничего, только читает launch_log.csv)
rem -----------------------------------------------------
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
for /f "usebackq skip=1 tokens=1-4 delims=," %%a in ("%LOG%") do (
    set /a total+=1
    if "%%d"=="0" (set /a ok+=1) else (set /a fail+=1)
)

(
    echo ОТЧЁТ О ЗАПУСКАХ ИНСТРУМЕНТОВ
    echo Сформирован: %date% %time%
    echo ==================================================
    echo Всего запусков:        !total!
    echo Успешных ^(код 0^):     !ok!
    echo Неуспешных/с ошибкой:  !fail!
    echo ==================================================
    echo.
    echo Дата;Время;Инструмент;КодЗавершения
    more +1 "%LOG%"
) > "%REPORT%"

echo Отчёт сохранён: %REPORT%
pause
goto MAIN_MENU

rem -----------------------------------------------------
rem  Пункт 4: редактор путей к инструментам
rem -----------------------------------------------------
:EDIT_PATHS
cls
echo --- Редактор путей к инструментам ---
echo  1. Показать список
echo  2. Добавить новый инструмент
echo  3. Изменить путь существующего
echo  4. Удалить инструмент
echo  5. Назад в главное меню
set /p ech="Выберите действие: "

if "%ech%"=="1" goto EDIT_SHOW
if "%ech%"=="2" goto EDIT_ADD
if "%ech%"=="3" goto EDIT_MODIFY
if "%ech%"=="4" goto EDIT_DELETE
if "%ech%"=="5" goto MAIN_MENU
goto EDIT_PATHS

:EDIT_SHOW
cls
call :LIST_TOOLS
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
set /p newpath="Полный путь к exe-файлу: "
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
set "mname=!name%midx%!"
if not defined mname (
    echo Неверный номер.
    pause
    goto EDIT_PATHS
)
set /p newpath="Новый путь для "!mname!": "
> "%CONFIG%.tmp" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG%") do (
        if not "%%A"=="" (
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
set "dname=!name%didx%!"
if not defined dname (
    echo Неверный номер.
    pause
    goto EDIT_PATHS
)
> "%CONFIG%.tmp" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG%") do (
        if not "%%A"=="" (
            if /I not "%%A"=="!dname!" echo %%A=%%B
        )
    )
)
move /y "%CONFIG%.tmp" "%CONFIG%" >nul
echo Инструмент "!dname!" удалён.
pause
goto EDIT_PATHS