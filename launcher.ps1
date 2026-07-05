$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$reportDir = Join-Path $scriptDir 'reports'
$reportFile = Join-Path $reportDir 'report.txt'
$toolsFile = Join-Path $scriptDir 'tools.json'

if (!(Test-Path $reportDir))
{
    New-Item -ItemType Directory -Path $reportDir | Out-Null
}

$tools = @{}

if (Test-Path $toolsFile)
{
    $json = Get-Content $toolsFile -Raw | ConvertFrom-Json

    foreach ($prop in $json.PSObject.Properties)
    {
        $tools[$prop.Name] = $prop.Value
    }
}

function Show-ToolList
{
    param([hashtable]$tools)

    if ($tools.Count -eq 0)
    {
        Write-Host "Инструменты не найдены."
        return
    }

    $index = 1
    foreach ($tool in $tools.Keys)
    {
        Write-Host ("{0,2} - {1}" -f $index, $tool)
        $index++
    }
}

function Get-ToolNameByIndex
{
    param(
        [hashtable]$tools,
        [int]$index
    )

    if ($index -lt 1 -or $index -gt $tools.Count)
    {
        return $null
    }

    $keys = @($tools.Keys)
    return $keys[$index - 1]
}

function Parse-Indexes
{
    param(
        [string]$inputText,
        [int]$max
    )

    $indexes = @()

    foreach ($part in ($inputText -split '[,;\s]+' ))
    {
        if ($part -match '^[0-9]+$')
        {
            $value = [int]$part
            if ($value -ge 1 -and $value -le $max)
            {
                $indexes += $value
            }
        }
    }

    return ,($indexes | Select-Object -Unique)
}

function Run-Tool
{
    param(
        [string]$name,
        [string]$path
    )

    if (-not (Test-Path $path))
    {
        return "FAIL: путь '$path' не найден"
    }

    try
    {
        Start-Process -FilePath $path -ErrorAction Stop
        return "SUCCESS"
    }
    catch
    {
        return "FAIL: $($_.Exception.Message)"
    }
}

function Write-RunReport
{
    param(
        [string]$name,
        [string]$status
    )

    Add-Content $reportFile "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $name | $status"
}

function Create-BulkRunReport
{
    param([array]$entries)

    $fileName = Join-Path $reportDir "bulk-report-$((Get-Date).ToString('yyyyMMdd-HHmmss')).txt"
    $lines = @()
    $lines += "Массовый запуск: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
    $lines += ""
    $lines += "Выбранные инструменты:"

    foreach ($entry in $entries)
    {
        $lines += "$($entry.Name) | $($entry.Path) | $($entry.Status)"
    }

    $lines | Set-Content $fileName
    Write-Host "Отчет создан: $fileName"
    notepad $fileName
}

function Create-SummaryReport
{
    $fileName = "reports\summary-report-$((Get-Date).ToString('yyyyMMdd-HHmmss')).txt"
    $lines = @()

    $lines += "Отчет об инструментах"
    $lines += "Дата: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
    $lines += ""
    $lines += "Список инструментов:"

    if ($tools.Count -eq 0)
    {
        $lines += "  (инструменты не найдены)"
    }
    else
    {
        foreach ($tool in $tools.Keys)
        {
            $lines += "  - $tool : $($tools[$tool])"
        }
    }

    $lines += ""
    $lines += "История запусков:"

    if (Test-Path $reportFile)
    {
        $lines += Get-Content $reportFile
    }
    else
    {
        $lines += "  (история запусков отсутствует)"
    }

    $lines | Set-Content $fileName
    Write-Host "Создан отчет: $fileName"
    notepad $fileName
}

do
{
    Clear-Host

    Write-Host "===== МЕНЮ ====="
    Write-Host "1 - Запуск инструмента"
    Write-Host "2 - Массовый запуск"
    Write-Host "3 - Создать отчет"
    Write-Host "4 - Добавить программу"
    Write-Host "5 - Выход"

    $choice = Read-Host "Выберите пункт"

    switch ($choice)
    {
        "1"
        {
            if ($tools.Count -eq 0)
            {
                Write-Host "Нет доступных инструментов. Сначала добавьте программу."
                Pause
                break
            }

            Write-Host ""
            Write-Host "Доступные инструменты:"
            Show-ToolList -tools $tools

            $userInput = Read-Host "Введите номер инструмента"
            $indexes = Parse-Indexes -inputText $userInput -max $tools.Count

            if (($indexes | Measure-Object).Count -ne 1)
            {
                Write-Host "Неверный выбор. Введите один номер."
                Pause
                break
            }

            $name = Get-ToolNameByIndex -tools $tools -index $indexes[0]

            if (-not $name)
            {
                Write-Host "Инструмент не найден."
                Pause
                break
            }

            $status = Run-Tool -name $name -path $tools[$name]
            Write-RunReport -name $name -status $status

            Write-Host "Результат: $status"
            Pause
        }

        "2"
        {
            if ($tools.Count -eq 0)
            {
                Write-Host "Нет доступных инструментов. Сначала добавьте программу."
                Pause
                break
            }

            Write-Host ""
            Write-Host "Доступные инструменты:"
            Show-ToolList -tools $tools

            $userInput = Read-Host "Введите номера инструментов через запятую или пробел"
            $indexes = Parse-Indexes -inputText $userInput -max $tools.Count

            if (($indexes | Measure-Object).Count -eq 0)
            {
                Write-Host "Неверный выбор. Укажите номера через запятую или пробел."
                Pause
                break
            }

            $entries = @()

            foreach ($index in $indexes)
            {
                $name = Get-ToolNameByIndex -tools $tools -index $index
                if ($name)
                {
                    $status = Run-Tool -name $name -path $tools[$name]
                    Write-RunReport -name $name -status $status

                    $entries += [pscustomobject]@{
                        Name = $name
                        Path = $tools[$name]
                        Status = $status
                    }
                }
            }

            if ($entries.Count -eq 0)
            {
                Write-Host "Не удалось выбрать инструменты для запуска."
                Pause
                break
            }

            Create-BulkRunReport -entries $entries
            Write-Host "Выбрано и запущено: $($entries.Count) инструмент(ов)."
            Pause
        }

        "3"
        {
            Create-SummaryReport
            Pause
        }

        "4"
        {
            $name = Read-Host "Название программы"
            $path = Read-Host "Путь к exe"

            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($path))
            {
                Write-Host "Название и путь не могут быть пустыми."
                Pause
                break
            }

            $tools[$name] = $path
            $tools | ConvertTo-Json | Set-Content $toolsFile

            Write-Host "Программа добавлена"
            Pause
        }

        "5"
        {
            break 2
        }

        default
        {
            Write-Host "Неверный выбор"
            Pause
        }
    }
}
while ($true)