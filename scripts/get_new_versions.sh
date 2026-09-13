#!/bin/bash

# 啟用錯誤追蹤和管道錯誤檢測
set -e
set -o pipefail

# 添加日誌函數
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

# 設置錯誤處理陷阱
trap 'handle_error $LINENO' ERR

log_info "開始檢查新版本..."

# 檢查 GITHUB_TOKEN 是否設置
if [ -z "$GITHUB_TOKEN" ]; then
  log_error "GITHUB_TOKEN 未設置。"
  exit 1
fi

UPSTREAM_REPO="git-for-windows/git"
LOCAL_REPO="$GITHUB_REPOSITORY"

log_info "從本地倉庫獲取標籤..."
# 獲取本地倉庫的所有標籤
LOCAL_TAGS=$(git ls-remote --tags "https://github.com/$LOCAL_REPO.git" | awk -F'/' '{print $NF}' | sed 's/^v//')

log_info "從上游倉庫獲取發布版本..."
# 獲取上游倉庫的所有發布版本
UPSTREAM_TAGS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$UPSTREAM_REPO/releases?per_page=100" | jq -r '.[].tag_name | select(test("^v[0-9]+[.][0-9]+[.][0-9]+"))' | sed 's/^v//')

# 檢查API調用是否成功
if [ -z "$UPSTREAM_TAGS" ]; then
  log_error "無法從上游倉庫獲取標籤。請檢查GITHUB_TOKEN和網路連接。"
  exit 1
fi

# 計算未處理的版本
log_info "計算未處理的版本..."
NEW_VERSIONS=()
for VERSION in $UPSTREAM_TAGS; do
  if ! echo "$LOCAL_TAGS" | grep -q "^$VERSION$"; then
    NEW_VERSIONS+=("$VERSION")
  fi
done

# 將新版本列表保存到文件，並設置輸出變數
if [ ${#NEW_VERSIONS[@]} -eq 0 ]; then
  log_info "沒有新版本需要處理。"
  echo "has_new_versions=false" >> "$GITHUB_OUTPUT"
else
  log_info "發現 ${#NEW_VERSIONS[@]} 個新版本需要處理：${NEW_VERSIONS[@]}"
  printf "%s\n" "${NEW_VERSIONS[@]}" > new_versions.txt
  echo "has_new_versions=true" >> "$GITHUB_OUTPUT"
fi

log_info "新版本檢查完成。"
