# run_collect.ps1 — LOF溢价数据采集调度脚本
# 每个检查点失败时写入 errors/ 目录，成功后清理

$ErrorActionPreference = "Stop"
$ProjectDir = "D:\Workspace\HistoryData-LofPremium"
$ErrorDir = Join-Path $ProjectDir "errors"
$TodayStr = Get-Date -Format "yyyyMMdd"

# 确保错误目录存在
if (-not (Test-Path $ErrorDir)) {
    New-Item -ItemType Directory -Path $ErrorDir -Force | Out-Null
}

function Write-CheckpointError {
    param([string]$Step, [string]$Message)
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = Join-Path $ErrorDir "${TodayStr}_ck${Step}_${ts}.txt"
    $body = @"
=== LOF采集错误检查点 ===
时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')
检查点: CK$Step
错误详情:
$Message
"@
    Set-Content -Path $file -Value $body -Encoding UTF8
    Write-Host "[CK${Step} FAIL] $Message"
    Write-Host "[CK${Step} FAIL] 错误已写入: $file"
}

function Clear-CheckpointErrors {
    $files = Get-ChildItem -Path $ErrorDir -Filter "${TodayStr}_ck*" -ErrorAction SilentlyContinue
    if ($files) {
        $files | Remove-Item -Force
        Write-Host "[OK] 已清理 $($files.Count) 个今日错误文件"
    }
}

# ===== CK1: 判断A股交易日 =====
Write-Host "`n===== CK1: 判断A股交易日 ====="
try {
    python -c "import chinese_calendar,datetime; exit(0 if chinese_calendar.is_workday(datetime.date.today()) else 1)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "今日非交易日，跳过采集"
        Clear-CheckpointErrors
        exit 0
    }
    Write-Host "今日是交易日，继续执行"
} catch {
    Write-CheckpointError -Step "1_trading_day" -Message $_.Exception.Message
    exit 1
}

# ===== CK2: 执行数据采集 =====
Write-Host "`n===== CK2: 执行数据采集 ====="
try {
    Push-Location $ProjectDir
    python save_lof_data.py 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "save_lof_data.py exit code: $LASTEXITCODE"
    }
    Pop-Location
    Write-Host "数据采集完成"
} catch {
    Write-CheckpointError -Step "2_collect" -Message $_.Exception.Message
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

# ===== CK3: Git 提交 =====
Write-Host "`n===== CK3: Git 提交 ====="
try {
    Push-Location $ProjectDir
    git add data/ *.log 2>&1

    $null = git diff --cached --quiet 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "无变更，跳过提交"
    } else {
        $dateStr = Get-Date -Format "yyyy-MM-dd"
        git commit -m "Save LOF data for $dateStr" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git commit exit code: $LASTEXITCODE"
        }
        Write-Host "提交成功: Save LOF data for $dateStr"
    }
    Pop-Location
} catch {
    Write-CheckpointError -Step "3_commit" -Message $_.Exception.Message
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

# ===== CK4: Git 推送 =====
Write-Host "`n===== CK4: Git 推送 ====="
try {
    Push-Location $ProjectDir
    git push origin main 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git push exit code: $LASTEXITCODE"
    }
    Pop-Location
    Write-Host "推送成功"
} catch {
    Write-CheckpointError -Step "4_push" -Message $_.Exception.Message
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

# ===== 全部通过 =====
Clear-CheckpointErrors
Write-Host "`n===== LOF采集全部完成 ====="
exit 0
