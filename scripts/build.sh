#!/bin/bash

set -e
set -o pipefail

log_info() {
  echo "   INFO: $1"
}

log_error() {
  echo "  ERROR: $1" >&2
}

log_success() {
  echo "SUCCESS:  $1"
}

handle_error() {
  log_error "腳本執行失敗，行號: $1"
  exit 1
}

trap 'handle_error $LINENO' ERR

if [ -z "$1" ]; then
  log_error "  USAGE：$0 <git版本>"
  exit 1
fi

gitver="$1"
tarfile="v$gitver.tar.gz"
dir="git-$gitver"
outdir="build"

log_info "開始為版本 $gitver 構建繁體中文語言包..."

if [ ! -f "$tarfile" ]; then
  log_info "下載 Git 原始碼 v$gitver..."
  if ! curl -L -o "$tarfile" "https://github.com/git-for-windows/git/archive/refs/tags/$tarfile"; then
    log_error "下載源碼失敗"
    exit 1
  fi
  log_success "源碼下載完成"
fi

log_info "解壓原始碼..."
if ! tar xf "$tarfile"; then
  log_error "解壓源碼失敗"
  exit 1
fi
log_success "源碼解壓完成"

# 1. 檢查繁體中文 (zh_TW) 翻譯檔是否存在
if [ ! -f "$dir/po/zh_TW.po" ]; then
  log_error "未找到翻譯檔案 $dir/po/zh_TW.po"
  exit 1
fi

if [ ! -f "$dir/git-gui/po/zh_tw.po" ]; then
  log_error "未找到翻譯檔案 $dir/git-gui/po/zh_tw.po"
  exit 1
fi

if [ ! -f "$dir/gitk-git/po/zh_tw.po" ]; then
  log_error "未找到翻譯檔案 $dir/gitk-git/po/zh_tw.po"
  exit 1
fi

# 2. 定義繁體中文的目標目錄 (zh_TW)
modir="$outdir/mingw64/share/locale/zh_TW/LC_MESSAGES"
guidir="$outdir/mingw64/share/git-gui/lib/msgs"
gitkdir="$outdir/mingw64/share/gitk/lib/msgs"

log_info "建立輸出目錄結構..."
mkdir -p "$modir" "$guidir" "$gitkdir"

log_info "編譯本地化檔案..."
log_info "編譯 git.mo..."
# 3. 將 zh_TW.po 編譯為 git.mo
if ! msgfmt -o "$modir/git.mo" "$dir/po/zh_TW.po"; then
  log_error "編譯 git.mo 失敗"
  exit 1
fi

log_info "編譯 git-gui 本地化檔案..."
# 4. 指定 zh_TW 語系編譯 git-gui
if ! msgfmt --tcl -l zh_TW -d "$guidir" "$dir/git-gui/po/zh_tw.po"; then
  log_error "編譯 git-gui 本地化檔案失敗"
  exit 1
fi

log_info "編譯 gitk 本地化檔案..."
# 5. 指定 zh_TW 語系編譯 gitk
if ! msgfmt --tcl -l zh_TW -d "$gitkdir" "$dir/gitk-git/po/zh_tw.po"; then
  log_error "編譯 gitk 本地化檔案失敗"
  exit 1
fi

zipname="build-$gitver.zip"

[ -f "$zipname" ] && rm -f "$zipname"

log_info "建立 zip 壓縮檔案 $zipname..."
if ! command -v zip >/dev/null 2>&1; then
  log_error "未找到 zip 命令，請安裝 zip"
  exit 1
fi

(
  cd "$outdir" || exit 1
  if ! zip -r -y "../$zipname" .; then
    log_error "使用 zip 命令建立壓縮檔失敗"
    exit 1
  fi
)

if [ ! -f "$zipname" ]; then
  log_error "未能成功建立 zip 檔案 $zipname"
  exit 1
fi

zipsize=$(du -k "$zipname" | cut -f1)
if [ "$zipsize" -lt 10 ]; then
  log_error "建立的 zip 檔案太小($zipsize KB)，可能損壞"
  exit 1
fi

log_success "成功建立 zip 壓縮檔案：$zipname (${zipsize}KB)"

log_info "清理臨時檔案..."
rm -rf "$outdir" "$dir"

log_success "語言包 $zipname 建置完成！"
exit 0
