<#
    build_elfs.ps1 -- собирает обе прошивки MicroBlaze за один запуск.

        app_component/build/app_component.elf        TIME_SCALE = 1     -> плата
        ../../vivado/LED_AXI_GPIO_MB/sim_elf/
                     app_component_sim.elf           TIME_SCALE = N     -> симуляция

    Порядок намеренный: симуляционная сборка делается первой, боевая --
    последней. Поэтому в build/ всегда остаётся вариант для платы, даже
    если скрипт прервать. UserConfig.cmake восстанавливается через finally.

    Запуск:
        .\build_elfs.ps1              # масштаб 1000 (шаг 250 мс -> 250 мкс)
        .\build_elfs.ps1 -Scale 500   # другой масштаб

    ВНИМАНИЕ: файл должен быть сохранён в UTF-8 С BOM.
    Windows PowerShell 5.1 без BOM читает скрипт как ANSI, кириллица
    превращается в мусор и разбор файла ломается.
#>

[CmdletBinding()]
param(
    [ValidateRange(2, 100000)]
    [int]$Scale = 1000
)

$ErrorActionPreference = 'Stop'

# ---- Пути ----
$ws     = $PSScriptRoot
$src    = Join-Path $ws 'app_component\src'
$build  = Join-Path $ws 'app_component\build'
$cfg    = Join-Path $src 'UserConfig.cmake'
$simDir = Join-Path $ws '..\..\vivado\LED_AXI_GPIO_MB\sim_elf'

foreach ($p in @($src, $build, $cfg)) {
    if (-not (Test-Path $p)) { throw "Не найден: $p" }
}
if (-not (Test-Path $simDir)) { New-Item -ItemType Directory -Path $simDir -Force | Out-Null }
$simDir = (Resolve-Path $simDir).Path

$vitisBin = 'C:\AMDDesignTools\2025.2\Vitis\bin'
$mbBin    = 'C:\AMDDesignTools\2025.2\Vitis\gnu\microblaze\nt\bin'
foreach ($p in @($vitisBin, $mbBin)) {
    if (-not (Test-Path $p)) { throw "Не найден инструментарий: $p" }
}
$env:PATH = "$mbBin;$vitisBin;$env:PATH"

# ---- Правка USER_COMPILE_DEFINITIONS ----
# Блок выглядит так:
#     set(USER_COMPILE_DEFINITIONS
#     ""
#     )
$pattern = 'set\(USER_COMPILE_DEFINITIONS\s*\r?\n\s*"[^"]*"\s*\r?\n\)'

function Set-Define([string]$value) {
    $text = Get-Content $cfg -Raw
    $hits = [regex]::Matches($text, $pattern).Count
    if ($hits -ne 1) {
        throw "В UserConfig.cmake блоков USER_COMPILE_DEFINITIONS: $hits, ожидался 1. Формат изменился, правьте вручную."
    }
    $replacement = "set(USER_COMPILE_DEFINITIONS`r`n`"$value`"`r`n)"
    $text = [regex]::Replace($text, $pattern, $replacement)
    Set-Content -Path $cfg -Value $text -Encoding utf8 -NoNewline
}

function Invoke-Build([string]$label) {
    Write-Host "  сборка: $label" -ForegroundColor DarkGray

    # Без 2>&1: в PS 5.1 перенаправление stderr нативной программы
    # оборачивает каждую строку в ErrorRecord, и при ErrorActionPreference=Stop
    # скрипт падает даже при успешной сборке. stderr идёт прямо в консоль.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out  = & cmd.exe /C "empyro.bat build_app -s `"$src`" -b `"$build`""
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev

    if ($code -ne 0) {
        $out | Select-Object -Last 15 | ForEach-Object { Write-Host $_ }
        throw "Сборка '$label' завершилась с ошибкой, код $code."
    }

    $sizeFile = Join-Path $build 'app_component.elf.size'
    $size = Get-Content $sizeFile | Where-Object { $_ -match '^\s*\d' } | Select-Object -First 1
    return $size.Trim()
}

# ---- Работа ----
$simSize   = $null
$boardSize = $null

try {
    Write-Host ""
    Write-Host "[1/2] Вариант для СИМУЛЯЦИИ (TIME_SCALE=$Scale)" -ForegroundColor Cyan
    Set-Define "TIME_SCALE=$Scale"
    $simSize = Invoke-Build "sim"

    Copy-Item (Join-Path $build 'app_component.elf')      (Join-Path $simDir 'app_component_sim.elf')      -Force
    Copy-Item (Join-Path $build 'app_component.elf.size') (Join-Path $simDir 'app_component_sim.elf.size') -Force
    Write-Host "  скопировано -> $simDir\app_component_sim.elf" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "[2/2] Вариант для ПЛАТЫ (реальное время)" -ForegroundColor Cyan
    Set-Define ""
    $boardSize = Invoke-Build "board"
}
finally {
    # Что бы ни случилось, файл настроек остаётся в боевом состоянии
    try { Set-Define "" } catch { Write-Warning "Не удалось восстановить UserConfig.cmake: $_" }
}

# ---- Итог ----
Write-Host ""
Write-Host "Готово." -ForegroundColor Green
Write-Host "  плата     : app_component\build\app_component.elf"
Write-Host "              $boardSize"
Write-Host "  симуляция : sim_elf\app_component_sim.elf   (TIME_SCALE=$Scale)"
Write-Host "              $simSize"
Write-Host ""
Write-Host "Напоминание: в Vivado привязать app_component_sim.elf" -ForegroundColor Yellow
Write-Host "через Tools -> Associate ELF Files -> Simulation Sources." -ForegroundColor Yellow
