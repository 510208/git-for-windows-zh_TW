# Git for Windows 中文語言包一鍵安裝腳本
# 使用方法：iwr -useb https://cdn.jsdelivr.net/gh/zkl2333/git-for-windows-zh@main/install.ps1 | iex

# 使用 & { } 包裹腳本，確保通過 iwr | iex 運行時 return 不會關閉 PowerShell 窗口
& {
    # 相容性檢查和編碼保護
    try {
        # 為Windows PowerShell (5.1及以下) 設置UTF-8編碼
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
        }
    } catch {
        Write-Warning "編碼設置失敗，繼續執行腳本..."
    }

    # 確保可以連接到 GitHub（設置 TLS 1.2）
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warning "TLS 設置失敗，繼續執行腳本..."
    }

    # 設置GitHub倉庫資訊
    $GitHubUser = "zkl2333"
    $GitHubRepo = "git-for-windows-zh"
    $InstallUrl = "https://cdn.jsdelivr.net/gh/$GitHubUser/$GitHubRepo@main/install.ps1"

    Write-Host "🚀 Git for Windows 中文語言包安裝程式" -ForegroundColor Cyan
    Write-Host ("=" * 50)

    # 檢查PowerShell版本
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Host "❌ 需要 PowerShell 版本 5.0 或更高版本" -ForegroundColor Red
        Write-Host "   當前版本：$($PSVersionTable.PSVersion)" -ForegroundColor Yellow
        return
    }

    # 檢查管理員權限
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "⚠️  檢測到未以管理員身份運行" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "請以管理員身份運行 PowerShell，然後執行：" -ForegroundColor Cyan
        Write-Host "iwr -useb $InstallUrl | iex" -ForegroundColor Green
        Write-Host ""
        $response = Read-Host "是否嘗試以管理員身份重新啟動？(Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            try {
                Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"iwr -useb $InstallUrl | iex; Read-Host '按 Enter 鍵關閉窗口'`""
                Write-Host "✅ 已啟動管理員 PowerShell 窗口，請在新窗口中繼續操作" -ForegroundColor Green
                return
            } catch {
                Write-Host "❌ 無法啟動管理員 PowerShell：$($_.Exception.Message)" -ForegroundColor Red
                return
            }
        } else {
            return
        }
    }

    Write-Host "✅ 已確認管理員權限" -ForegroundColor Green

    # 獲取git.exe的路徑
    try {
        $gitCommand = Get-Command git -ErrorAction Stop
        $gitPath = $gitCommand.Source
        Write-Host "✅ 已找到 Git：$gitPath" -ForegroundColor Green
    } catch {
        Write-Host "❌ 未找到 Git，請先安裝 Git for Windows" -ForegroundColor Red
        Write-Host "   下載網址：https://git-scm.com/download/win" -ForegroundColor Yellow
        return
    }

    # 獲取Git安裝目錄
    $gitDir = Split-Path $gitPath -Parent
    $gitInstallDir = Split-Path $gitDir -Parent

    Write-Host "📁 Git 安裝目錄：$gitInstallDir" -ForegroundColor Cyan

    # 獲取已安裝的Git版本
    $gitVersionOutput = & git --version
    if ($gitVersionOutput -match "git version (\d+\.\d+\.\d+(?:\.\w+)?(?:\.\d+)?)") {
        $gitVersion = $Matches[1]
        Write-Host "📦 已安裝的 Git 版本：$gitVersion" -ForegroundColor Cyan
    } else {
        Write-Host "❌ 無法獲取 Git 版本號" -ForegroundColor Red
        return
    }

    # 構建語言包下載URL
    $downloadUrl = "https://github.com/$GitHubUser/$GitHubRepo/releases/download/v$gitVersion/build-$gitVersion.zip"

    Write-Host "🔗 語言包下載網址：$downloadUrl" -ForegroundColor Cyan

    # 設置臨時文件和目錄
    $tempZipFile = Join-Path $env:TEMP "build-$gitVersion.zip"
    $tempExtractDir = Join-Path $env:TEMP "git-lang-pack"

    # 下載語言包
    Write-Host ""
    Write-Host "⬇️  正在下載語言包..." -ForegroundColor Yellow
    try {
        # 禁用進度條以加快下載速度（PowerShell 5.1 的進度條會嚴重拖慢下載）
        $oldProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipFile -UseBasicParsing -ErrorAction Stop
        Write-Host "✅ 語言包下載成功" -ForegroundColor Green
    } catch {
        Write-Host "❌ 下載語言包失敗" -ForegroundColor Red
        Write-Host "   請檢查該版本的語言包是否存在：v$gitVersion" -ForegroundColor Yellow
        Write-Host "   所有可用版本：https://github.com/$GitHubUser/$GitHubRepo/releases" -ForegroundColor Yellow
        Write-Host "   錯誤資訊：$($_.Exception.Message)" -ForegroundColor Red
        return
    } finally {
        $ProgressPreference = $oldProgressPreference
    }

    # 解壓語言包
    Write-Host "📦 正在解壓語言包..." -ForegroundColor Yellow
    if (Test-Path $tempExtractDir) {
        try {
            Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "無法刪除臨時目錄，嘗試使用其他方法..."
            $tempExtractDir = Join-Path $env:TEMP "git-lang-pack_$(Get-Random)"
        }
    }

    try {
        if ($PSVersionTable.PSVersion.Major -ge 5) {
            Expand-Archive -LiteralPath $tempZipFile -DestinationPath $tempExtractDir -Force -ErrorAction Stop
        } else {
            $shell = New-Object -ComObject Shell.Application
            $zip = $shell.NameSpace($tempZipFile)
            foreach($item in $zip.items()) {
                $shell.Namespace($tempExtractDir).CopyHere($item, 0x14)
            }
        }
        Write-Host "✅ 語言包解壓成功" -ForegroundColor Green
    } catch {
        Write-Host "❌ 解壓失敗：$($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # 備份原始文件（可選）
    $backupDir = Join-Path $gitInstallDir "backup_lang_$(Get-Date -Format 'yyyyMMddHHmmss')"
    Write-Host "💾 正在備份原始語言文件到：$backupDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $filesToBackup = @(
        (Join-Path $gitInstallDir "mingw64\share\locale\zh_TW\LC_MESSAGES\git.mo"),
        # (Join-Path $gitInstallDir "mingw64\share\git-gui\lib\msgs\zh_tw.msg"),
        (Join-Path $gitInstallDir "mingw64\share\gitk\lib\msgs\zh_tw.msg")
    )

    foreach ($file in $filesToBackup) {
        if (Test-Path $file) {
            $destination = $file.Replace($gitInstallDir, $backupDir)
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item -Path $file -Destination $destination -Force
        }
    }

    # 複製新的語言文件到Git安裝目錄
    Write-Host "📋 正在複製新的語言文件..." -ForegroundColor Yellow
    try {
        Copy-Item -Path (Join-Path $tempExtractDir "*") -Destination $gitInstallDir -Recurse -Force
        Write-Host "✅ 語言文件複製成功" -ForegroundColor Green
    } catch {
        Write-Host "❌ 複製文件失敗：$($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # 設置LANG環境變數
    $envName = "LANG"
    $envValue = "zh_TW.UTF-8"

    Write-Host "🔧 正在設置用戶環境變數：$envName=$envValue" -ForegroundColor Yellow
    try {
        [Environment]::SetEnvironmentVariable($envName, $envValue, [EnvironmentVariableTarget]::User)
        Write-Host "✅ 環境變數設置成功" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  環境變數設置失敗：$($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "💡 您可以手動設置環境變數或參考文件中的其他方法" -ForegroundColor Cyan
    }

    # 設置Git編碼配置
    Write-Host "🔧 正在配置 Git 編碼設置..." -ForegroundColor Yellow
    try {
        & git config --global core.quotepath false
        & git config --global gui.encoding utf-8
        & git config --global i18n.commitencoding utf-8
        & git config --global i18n.logoutputencoding utf-8
        Write-Host "✅ Git 編碼配置完成" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Git 編碼配置失敗" -ForegroundColor Yellow
        Write-Host "💡 您可以手動執行以下命令：" -ForegroundColor Cyan
        Write-Host "   git config --global core.quotepath false"
        Write-Host "   git config --global gui.encoding utf-8"
        Write-Host "   git config --global i18n.commitencoding utf-8"
        Write-Host "   git config --global i18n.logoutputencoding utf-8"
    }

    # 清理臨時文件
    Write-Host "🧹 正在清理臨時文件..." -ForegroundColor Yellow
    try {
        Remove-Item -Path $tempZipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "✅ 臨時文件清理完成" -ForegroundColor Green
    } catch {
        Write-Warning "清理臨時文件時出現錯誤，可以手動刪除：$tempZipFile 和 $tempExtractDir"
    }

    # 顯示完成資訊
    Write-Host ""
    Write-Host ("=" * 50)
    Write-Host "🎉 語言包安裝完成！" -ForegroundColor Green
    Write-Host ("=" * 50)
    Write-Host ""
    Write-Host "📋 下一步操作：" -ForegroundColor Cyan
    Write-Host "  1. 重啟 Git Bash" -ForegroundColor White
    Write-Host "  2. 運行 'git status' 驗證中文顯示" -ForegroundColor White
    Write-Host ""
    Write-Host "📖 如果仍顯示英文，請參考文件中的手動設置方法：" -ForegroundColor Cyan
    Write-Host "   https://github.com/$GitHubUser/$GitHubRepo" -ForegroundColor Blue
    Write-Host ""
}
