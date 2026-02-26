#!/bin/bash
SRC="/Users/kpudan/.cursor/projects/Users-kpudan-dev-xcode-Steps4/assets/ChatGPT_Image_Feb_23__2026_at_10_52_06_PM-14b32381-ba27-48ac-a074-c40c5f52f5b1.png"
DEST="/Users/kpudan/dev/xcode/Steps4/StepsTrader/Assets.xcassets/AppIcon.appiconset"

f() { cp "$SRC" "$DEST/$1" && sips -z $3 $2 "$DEST/$1" > /dev/null 2>&1 && echo "✓ $1 (${2}x${3})"; }

f "Icon-iOS-Default-1024x1024@1x.png" 1024 1024
f "Icon-iOS-Default-512x512@1x.png" 512 512
f "Icon-iOS-Default-256x256@2x.png" 512 512
f "Icon-iOS-Default-256x256@1x.png" 256 256
f "Icon-iOS-Default-128x128@2x.png" 256 256
f "Icon-iOS-Default-128x128@1x.png" 128 128
f "Icon-iOS-Default-83.5x83.5@2x.png" 167 167
f "Icon-iOS-Default-76x76@2x.png" 152 152
f "Icon-iOS-Default-60x60@3x.png" 180 180
f "Icon-iOS-Default-60x60@2x.png" 120 120
f "Icon-iOS-Default-40x40@3x.png" 120 120
f "Icon-iOS-Default-40x40@2x.png" 80 80
f "Icon-iOS-Default-40x40@2x 1.png" 80 80
f "Icon-iOS-Default-38x38@2x.png" 76 76
f "Icon-iOS-Default-32x32@2x.png" 64 64
f "Icon-iOS-Default-32x32@1x.png" 32 32
f "Icon-iOS-Default-29x29@3x.png" 87 87
f "Icon-iOS-Default-29x29@2x.png" 58 58
f "Icon-iOS-Default-29x29@2x 1.png" 58 58
f "Icon-iOS-Default-20x20@3x.png" 60 60
f "Icon-iOS-Default-20x20@2x.png" 40 40
f "Icon-iOS-Default-20x20@2x 1.png" 40 40
f "Icon-iOS-Default-20x20@2x 2.png" 40 40
f "Icon-iOS-Default-16x16@2x.png" 32 32
f "Icon-iOS-Default-16x16@1x.png" 16 16

echo ""
echo "Done! All icons generated."
