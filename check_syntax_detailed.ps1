# PowerShell 腳本語法檢查工具
# 用於 GitHub Actions 自動化測試

$ErrorActionPreference = 'Stop'

try {
    # 設置編碼（PowerShell 5.1 需要）
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    }

    # 要檢查的腳本列表
    $scriptsToCheck = @(
        './apply_git_language_pack.ps1',
        './install.ps1'
    )

    $allPassed = $true

    foreach ($scriptPath in $scriptsToCheck) {
        Write-Host "`n" + "=" * 60
        Write-Host "檢查腳本: $scriptPath" -ForegroundColor Cyan
        Write-Host "=" * 60

        if (-not (Test-Path $scriptPath)) {
            Write-Host "腳本文件不存在: $scriptPath" -ForegroundColor Yellow
            continue
        }

        # 讀取腳本內容
        $content = Get-Content -Path $scriptPath -Raw -Encoding UTF8

        Write-Host "腳本長度: $($content.Length) 字元"

        # 使用 PSParser 檢查語法錯誤
        $errors = $null
        [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors) | Out-Null

        if ($errors.Count -gt 0) {
            Write-Host '發現語法錯誤:' -ForegroundColor Red
            $errors | ForEach-Object {
                Write-Host "  第 $($_.Token.StartLine) 行: $($_.Message)" -ForegroundColor Red
            }
            $allPassed = $false
        } else {
            Write-Host '語法檢查通過' -ForegroundColor Green
        }
    }

    Write-Host "`n" + "=" * 60
    if ($allPassed) {
        Write-Host "所有腳本語法檢查通過！" -ForegroundColor Green
        Write-Host "=" * 60
        exit 0
    } else {
        Write-Host "部分腳本存在語法錯誤" -ForegroundColor Red
        Write-Host "=" * 60
        exit 1
    }
} catch {
    Write-Host "語法檢查失敗: $_" -ForegroundColor Red
    exit 1
}
