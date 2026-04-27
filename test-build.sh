#!/bin/bash
echo "=== 测试Swift包构建 ==="
echo "1. 检查Swift版本..."
swift --version

echo "2. 检查当前目录结构..."
ls -la
ls -la Sources/PhotoOrganizer/

echo "3. 尝试构建调试版本..."
swift build --configuration debug

if [ $? -eq 0 ]; then
    echo "✅ 调试构建成功！"
else
    echo "❌ 调试构建失败"
    exit 1
fi

echo "4. 尝试构建发布版本..."
swift build --configuration release

if [ $? -eq 0 ]; then
    echo "✅ 发布构建成功！"
else
    echo "❌ 发布构建失败"
    exit 1
fi

echo "🎉 所有构建测试通过！"
