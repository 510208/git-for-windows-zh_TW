# apply_git_language_pack.ps1

# 相容性檢查和編碼保護
try {
    # 為Windows PowerShell (5.1及以下) 設置UTF-8編碼
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    }
} catch {
    Write-Warning "編碼設置失敗，繼續執行腳本..."
}

# 設置您的GitHub使用者名稱和倉庫名
$GitHubUser = "510208"      # 替換為您的GitHub使用者名稱
$GitHubRepo = "git-for-windows-zh_TW"    # 替換為您的GitHub倉庫名

# 檢查 PowerShell 版本
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "需要 PowerShell 版本 5.0 或更高版本。目前版本：$($PSVersionTable.PSVersion)"
    exit 1
}

# 獲取git.exe的路徑
try {
    $gitCommand = Get-Command git -ErrorAction Stop
    $gitPath = $gitCommand.Source
} catch {
    Write-Host "錯誤：未找到Git，請確保已安裝Git並將其添加到系統PATH環境變數中。" -ForegroundColor Red
    Write-Host "下載網址：https://git-scm.com/download/win" -ForegroundColor Yellow
    Read-Host "按任意鍵退出..."
    exit 1
}

# 獲取Git安裝目錄
$gitDir = Split-Path $gitPath -Parent
$gitInstallDir = Split-Path $gitDir -Parent

Write-Host "Git安裝目錄：$gitInstallDir"

# 獲取已安裝的Git版本
$gitVersionOutput = git --version
if ($gitVersionOutput -match "git version (\d+\.\d+\.\d+(?:\.\w+)?(?:\.\d+)?)") {
    $gitVersion = $Matches[1]
    Write-Host "已安裝的Git版本：$gitVersion"
} else {
    Write-Host "無法獲取Git版本號。"
    exit 1
}

# 構建語言包下載URL
$downloadUrl = "https://github.com/$GitHubUser/$GitHubRepo/releases/download/v$gitVersion/build-$gitVersion.zip"

Write-Host "語言包下載URL：$downloadUrl"

# 設置臨時文件和目錄
$tempZipFile = "$env:TEMP\build-$gitVersion.zip"
$tempExtractDir = "$env:TEMP\git-lang-pack"

# 下載語言包
Write-Host "正在下載語言包..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZipFile -ErrorAction Stop
} catch {
    Write-Host "下載語言包失敗。請檢查該版本的語言包是否存在。"
    exit 1
}

Write-Host "語言包已下載到：$tempZipFile"

# 解壓語言包
Write-Host "正在解壓語言包..."
if (Test-Path $tempExtractDir) {
    try {
        Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warning "無法刪除臨時目錄，嘗試使用其他方法..."
        $tempExtractDir = "$env:TEMP\git-lang-pack_$(Get-Random)"
    }
}

try {
    # 相容不同版本的PowerShell
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Expand-Archive -LiteralPath $tempZipFile -DestinationPath $tempExtractDir -Force -ErrorAction Stop
    } else {
        # 對於舊版本，使用Shell.Application對象
        $shell = New-Object -ComObject Shell.Application
        $zip = $shell.NameSpace($tempZipFile)
        foreach($item in $zip.items()) {
            $shell.Namespace($tempExtractDir).CopyHere($item, 0x14)
        }
    }
} catch {
    Write-Host "錯誤：解壓失敗。$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "語言包已解壓到：$tempExtractDir"

# 備份原始文件（可選）
$backupDir = "$gitInstallDir\backup_lang_$(Get-Date -Format 'yyyyMMddHHmmss')"
Write-Host "正在備份原始語言文件到：$backupDir"
New-Item -ItemType Directory -Path $backupDir | Out-Null

$filesToBackup = @(
    "$gitInstallDir\mingw64\share\locale\zh_TW\LC_MESSAGES\git.mo",
    "$gitInstallDir\mingw64\share\git-gui\lib\msgs\zh_tw.msg",
    "$gitInstallDir\mingw64\share\gitk\lib\msgs\zh_tw.msg"
)

foreach ($file in $filesToBackup) {
    if (Test-Path $file) {
        $destination = $file.Replace($gitInstallDir, $backupDir)
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -Path $file -Destination $destination -Force
    }
}

# 複製新的語言文件到Git安裝目錄
Write-Host "正在複製新的語言文件..."
Copy-Item -Path "$tempExtractDir\*" -Destination $gitInstallDir -Recurse -Force

# 設置LANG環境變數
$envName = "LANG"
$envValue = "zh_CN.UTF-8"

Write-Host "正在設置用戶環境變數：$envName=$envValue"
try {
    [Environment]::SetEnvironmentVariable($envName, $envValue, [EnvironmentVariableTarget]::User)
    Write-Host "✓ 環境變數設置成功"
    Write-Host "⚠ 請重啟 Git Bash 使環境變數生效"
} catch {
    Write-Host "⚠ 環境變數設置失敗：$($_.Exception.Message)"
    Write-Host "💡 您可以手動設置環境變數或參考文件中的其他方法"
}

# 設置Git編碼配置
Write-Host "正在配置Git編碼設置..."
try {
    & git config --global core.quotepath false
    & git config --global gui.encoding utf-8
    & git config --global i18n.commitencoding utf-8
    & git config --global i18n.logoutputencoding utf-8
    Write-Host "✓ Git編碼配置完成"
} catch {
    Write-Warning "Git編碼配置失敗，您可以手動執行以下命令："
    Write-Host "git config --global core.quotepath false"
    Write-Host "git config --global gui.encoding utf-8"
    Write-Host "git config --global i18n.commitencoding utf-8"
    Write-Host "git config --global i18n.logoutputencoding utf-8"
}

Write-Host ""
Write-Host "🎉 語言包安裝完成！"
Write-Host ""
Write-Host "📋 下一步操作："
Write-Host "1. 重啟 Git Bash"
Write-Host "2. 運行 'git status' 驗證中文顯示"
Write-Host ""
Write-Host "📖 如果仍顯示英文，請參考文件中的手動設置方法："
Write-Host "   - bash profile 配置"
Write-Host "   - 系統環境變數設置"

# 清理臨時文件
Write-Host "正在清理臨時文件..."
Remove-Item -Path $tempZipFile -Force
Remove-Item -Path $tempExtractDir -Recurse -Force
