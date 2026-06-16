# run_collect.ps1 — LOF溢价数据采集调度脚本
# 每个检查点失败时写入 errors/ 目录，成功后清理

$ErrorActionPreference = "Stop"

# 强制绕过系统代理（东方财富API走直连更稳定）
$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
$env:http_proxy = ""
$env:https_proxy = ""
$env:NO_PROXY = "*"
$env:no_proxy = "*"

$ProjectDir = "D:\Workspace\HistoryData-LofPremium"
$ErrorDir = Join-Path $ProjectDir "errors"
$TodayStr = Get-Date -Format "yyyyMMdd"

# 确保错误目录存在
if (-not (Test-Path $ErrorDir)) {
    $null = New-Item -ItemType Directory -Path $ErrorDir -Force
}

function Write-CheckpointError($Step, $Message) {
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
Write-Host ""
Write-Host "===== CK1: 判断A股交易日 ====="
try {
    $pyCode = 'import chinese_calendar,datetime; exit(0 if chinese_calendar.is_workday(datetime.date.today()) else 1)'
    $result = & python -c $pyCode 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "今日非交易日，跳过采集"
        Clear-CheckpointErrors
        exit 0
    }
    Write-Host "今日是交易日，继续执行"
}
catch {
    Write-CheckpointError "1_trading_day" $_.Exception.Message
    exit 1
}

# ===== CK2: 执行数据采集 =====
Write-Host ""
Write-Host "===== CK2: 执行数据采集 ====="
try {
    Push-Location $ProjectDir
    & python save_lof_data.py 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location
    if ($exitCode -ne 0) {
        throw "save_lof_data.py exit code: $exitCode"
    }
    Write-Host "数据采集完成"
}
catch {
    Write-CheckpointError "2_collect" $_.Exception.Message
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

# ===== CK3: Git 提交 =====
Write-Host ""
Write-Host "===== CK3: Git 提交 ====="
try {
    Push-Location $ProjectDir
    $null = & git add data/ *.log 2>&1

    & git diff --cached --quiet 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "无变更，跳过提交"
    }
    else {
        $dateStr = Get-Date -Format "yyyy-MM-dd"
        & git commit -m "Save LOF data for $dateStr" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git commit exit code: $LASTEXITCODE"
        }
        Write-Host "提交成功: Save LOF data for $dateStr"
    }
    Pop-Location
}
catch {
    Write-CheckpointError "3_commit" $_.Exception.Message
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

# ===== CK4: Git 推送 =====
Write-Host ""
Write-Host "===== CK4: Git 推送 ====="
try {
    Push-Location $ProjectDir
    & git push origin main 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location
    if ($exitCode -ne 0) {
        throw "git push exit code: $exitCode"
    }
    Write-Host "推送成功"
}
catch {
    Write-CheckpointError "4_push" $_.Exception.Message
    Pop-Location -ErrorAction SilentlyContinue
    exit 1
}

# ===== 全部通过 =====
Clear-CheckpointErrors
Write-Host ""
Write-Host "===== LOF采集全部完成 ====="
exit 0
