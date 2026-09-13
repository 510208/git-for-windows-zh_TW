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

# 刪除指定 Release（失敗回滾用，避免殘留草稿 Release）
delete_release() {
  local release_id="$1"
  if [ -z "$release_id" ] || [ "$release_id" = "null" ]; then
    return 0
  fi
  curl -s -o /dev/null -X DELETE \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/${release_id}"
}

# 設置錯誤處理陷阱
trap 'handle_error $LINENO' ERR

log_info "開始處理新版本..."

# 檢查 GITHUB_TOKEN 是否設置
if [ -z "$GITHUB_TOKEN" ]; then
  log_error "GITHUB_TOKEN 未設置。"
  exit 1
fi

# 讀取版本列表
if [ ! -f "new_versions.txt" ]; then
  log_error "new_versions.txt 文件未找到。請先運行 get_new_versions.sh。"
  exit 1
fi

# 讀取版本列表到數組
mapfile -t VERSION_ARRAY < new_versions.txt
log_info "找到 ${#VERSION_ARRAY[@]} 個需要處理的版本"

# 記錄成功和失敗的版本
successful_versions=()
failed_versions=()

# 遍歷版本列表
for VERSION in "${VERSION_ARRAY[@]}"; do
  log_info "----------------------------------------"
  log_info "處理版本：$VERSION"

  # 檢查遠程是否已存在該版本標籤（已發布的 Release 會創建標籤），防止重複處理
  if git ls-remote --tags "https://github.com/${GITHUB_REPOSITORY}.git" "refs/tags/v$VERSION" | grep -q .; then
    log_info "版本 v$VERSION 已發布，跳過。"
    continue
  fi

  # 生成語言包
  log_info "為版本 $VERSION 生成語言包..."
  chmod +x ./build.sh
  if ! ./build.sh "$VERSION"; then
    log_error "版本 $VERSION 的語言包生成失敗"
    failed_versions+=("$VERSION")
    continue
  fi

  ZIP_NAME="build-$VERSION.zip"
  if [ ! -f "$ZIP_NAME" ]; then
    log_error "語言包 $ZIP_NAME 未找到，生成可能失敗，跳過此版本。"
    failed_versions+=("$VERSION")
    continue
  fi

  # 創建 GitHub Release（草稿模式，標籤留到發布成功時由 GitHub 創建）
  log_info "為版本 $VERSION 準備 GitHub Release..."
  
  # 獲取上游版本的詳細資訊，用於豐富我們的Release描述
  UPSTREAM_RELEASE_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/git-for-windows/git/releases/tags/v$VERSION")
  
  # 提取上游版本的發布日期和URL
  UPSTREAM_RELEASE_DATE=$(echo "$UPSTREAM_RELEASE_INFO" | jq -r '.published_at' | cut -d'T' -f1)
  UPSTREAM_RELEASE_URL=$(echo "$UPSTREAM_RELEASE_INFO" | jq -r '.html_url')
  
  # 生成美化的Release描述
  RELEASE_BODY=$(cat <<EOF
### ℹ️ 資訊
- **原版發布日期**: $UPSTREAM_RELEASE_DATE
- **自動構建時間**: $(date +"%Y-%m-%d")
- **適用版本**: Git for Windows v$VERSION

### 📖 使用說明
請參考[項目README](https://github.com/$GITHUB_REPOSITORY#readme)獲取詳細的安裝和使用說明。

### 🔗 相關連結
- [原版發布頁面]($UPSTREAM_RELEASE_URL)
- [本專案 GitHub 倉庫](https://github.com/$GITHUB_REPOSITORY)

---
*此語言包由自動構建腳本生成*
EOF
)

  # 判斷是否為預發布(RC)版本，避免 RC 語言包在 Releases 頁面混入正式版
  if [[ "$VERSION" == *-rc* ]]; then
    IS_PRERELEASE=true
    log_info "版本 $VERSION 為預發布(RC)版本，標記為 prerelease"
  else
    IS_PRERELEASE=false
  fi

  # 1) 創建草稿 Release：draft=true 不會創建 Git 標籤，標籤僅在最終發布成功時
  #    才由 GitHub 創建。因此中途任何失敗都不殘留標籤，下次定時任務會重新
  #    檢測並處理該版本（自癒，避免推標籤後失敗導致版本被永久跳過）。
  RELEASE_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d @- "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases" <<EOF
{
  "tag_name": "v$VERSION",
  "name": "Git for Windows v$VERSION 繁體中文語言包",
  "body": $(echo "$RELEASE_BODY" | jq -sR .),
  "draft": true,
  "prerelease": $IS_PRERELEASE
}
EOF
  )

  RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')
  UPLOAD_URL=$(echo "$RELEASE_RESPONSE" | jq -r '.upload_url' | sed 's/{?name,label}//')

  if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "null" ] || [ -z "$UPLOAD_URL" ] || [ "$UPLOAD_URL" = "null" ]; then
    log_error "創建草稿 Release v$VERSION 失敗，跳過此版本。"
    log_error "API 響應：$RELEASE_RESPONSE"
    failed_versions+=("$VERSION")
    continue
  fi

  # 2) 上傳語言包資產到草稿 Release
  log_info "上傳語言包文件 $ZIP_NAME 到草稿 Release..."
  UPLOAD_RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/zip" \
    --data-binary @"$ZIP_NAME" \
    "$UPLOAD_URL?name=$(basename "$ZIP_NAME")")

  if ! echo "$UPLOAD_RESPONSE" | jq -e '.state == "uploaded"' &>/dev/null \
     && ! echo "$UPLOAD_RESPONSE" | jq -e '.url' &>/dev/null; then
    log_error "上傳資產到 Release v$VERSION 失敗，刪除草稿以便下次重試。"
    log_error "API 響應：$UPLOAD_RESPONSE"
    delete_release "$RELEASE_ID" || true
    failed_versions+=("$VERSION")
    continue
  fi

  # 3) 發布 Release（draft=false），此時 GitHub 才創建對應 Git 標籤
  PUBLISH_RESPONSE=$(curl -s -X PATCH -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"draft": false}' \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}")

  if ! echo "$PUBLISH_RESPONSE" | jq -e '.draft == false' &>/dev/null; then
    log_error "發布 Release v$VERSION 失敗，刪除草稿以便下次重試。"
    log_error "API 響應：$PUBLISH_RESPONSE"
    delete_release "$RELEASE_ID" || true
    failed_versions+=("$VERSION")
    continue
  fi

  log_success "Release v$VERSION 及其資產已發布。"
  successful_versions+=("$VERSION")

  # 清理生成的文件
  log_info "清理版本 $VERSION 的臨時文件..."
  rm -f "$ZIP_NAME"
  rm -rf "git-$VERSION"
  rm -f "v$VERSION.tar.gz"

  log_success "版本 v$VERSION 處理完成。"
done

log_info "----------------------------------------"
log_info "所有版本處理摘要："
log_info "成功處理的版本: ${#successful_versions[@]}"
if [ ${#successful_versions[@]} -gt 0 ]; then
  log_success "成功的版本列表: ${successful_versions[*]}"
fi

log_info "失敗處理的版本: ${#failed_versions[@]}"
if [ ${#failed_versions[@]} -gt 0 ]; then
  log_error "失敗的版本列表: ${failed_versions[*]}"
fi

log_info "所有版本處理完畢。"

# 將處理結果寫入GitHub Actions輸出
echo "successful_versions=${successful_versions[*]}" >> "$GITHUB_OUTPUT"
echo "failed_versions=${failed_versions[*]}" >> "$GITHUB_OUTPUT"
echo "total_success=${#successful_versions[@]}" >> "$GITHUB_OUTPUT"
echo "total_failed=${#failed_versions[@]}" >> "$GITHUB_OUTPUT"
