#!/usr/bin/env bash
set -euo pipefail

# ĐƯỜNG DẪN TỚI FILE .icns CỦA BẠN
ICON_PATH="BrightnessMenuApp/AppIcon.icns"  # sửa nếu file .icns ở chỗ khác

# THƯ MỤC TARGET CHÍNH (thường trùng tên app). Sửa nếu cần.
TARGET_DIR="BrightnessMenuApp"
if [[ ! -d "$TARGET_DIR" ]]; then
  # Nếu không có thư mục BrightnessMenuApp, dùng thư mục hiện tại làm fallback
  TARGET_DIR="."
fi

if [[ ! -f "$ICON_PATH" ]]; then
  echo "Không tìm thấy file icns tại: $ICON_PATH"
  echo "Hãy sửa biến ICON_PATH trong script trỏ đúng tới AppIcon.icns rồi chạy lại."
  exit 1
fi

ASSETS_DIR="$TARGET_DIR/Assets.xcassets"
APPICON_SET_DIR="$ASSETS_DIR/AppIcon.appiconset"

echo "Tạo/cập nhật Asset Catalog tại: $ASSETS_DIR"
mkdir -p "$APPICON_SET_DIR"

# Contents.json cho gốc Assets.xcassets (an toàn nếu đã tồn tại)
cat > "$ASSETS_DIR/Contents.json" << 'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

# Copy .icns vào appiconset, đặt tên chuẩn AppIcon.icns
cp "$ICON_PATH" "$APPICON_SET_DIR/AppIcon.icns"

# Contents.json cho AppIcon.appiconset tham chiếu file .icns
cat > "$APPICON_SET_DIR/Contents.json" << 'JSON'
{
  "images" : [
    {
      "filename" : "AppIcon.icns",
      "idiom" : "mac"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Đã tạo AppIcon.appiconset và thêm AppIcon.icns."

# Thử gỡ CFBundleIconFile trong Info.plist (nếu bạn từng dùng Cách 1)
# Đoán đường dẫn Info.plist phổ biến; bạn có thể sửa nếu project bạn khác bố cục
INFO_PLIST_CANDIDATE="$TARGET_DIR/Info.plist"
if [[ -f "$INFO_PLIST_CANDIDATE" ]]; then
  if /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$INFO_PLIST_CANDIDATE" >/dev/null 2>&1; then
    echo "Phát hiện CFBundleIconFile trong $INFO_PLIST_CANDIDATE, đang xóa để tránh xung đột với Asset Catalog..."
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$INFO_PLIST_CANDIDATE" || true
  fi
fi

echo "Xong. Mở Xcode, vào Target > General > App Icon và chọn “AppIcon”."
echo "Nếu Assets.xcassets chưa thuộc Target Membership, tick nó trong File Inspector."
