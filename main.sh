#!/bin/bash

# This script automates the modification of Xmrig source files
# to adjust donation levels and redirect donation servers.
#
# 这个脚本用于自动化修改 Xmrig 的源文件，
# 以调整捐赠等级和重定向捐赠服务器。

# --- File Paths ---
# 定义需要修改的文件的路径
DONATE_H_FILE="src/donate.h"
DONATE_CPP_FILE="src/net/strategies/DonateStrategy.cpp"

# --- Check if files exist ---
# 检查文件是否存在，以防脚本在错误的位置运行
if [ ! -f "$DONATE_H_FILE" ] || [ ! -f "$DONATE_CPP_FILE" ]; then
    echo "错误：找不到目标文件。请确保您在 Xmrig 仓库的根目录下运行此脚本。"
    exit 1
fi

echo "开始修改 Xmrig 源文件..."

# --- Modify src/donate.h ---
# 编辑 src/donate.h 文件，将捐赠等级设置为 0
echo "1. 修改 $DONATE_H_FILE..."
sed -i.bak 's/constexpr const int kMinimumDonateLevel = [0-9]*;/constexpr const int kMinimumDonateLevel = 0;/' "$DONATE_H_FILE"
sed -i.bak 's/constexpr const int kDefaultDonateLevel = [0-9]*;/constexpr const int kDefaultDonateLevel = 0;/' "$DONATE_H_FILE"
echo "   - kMinimumDonateLevel 已设置为 0"
echo "   - kDefaultDonateLevel 已设置为 0"

# --- Modify src/net/strategies/DonateStrategy.cpp ---
# 编辑 src/net/strategies/DonateStrategy.cpp，将捐赠服务器地址修改为本地地址
echo "2. 修改 $DONATE_CPP_FILE..."
sed -i.bak 's/static constexpr const char \*kDonateHost = ".*";/static constexpr const char *kDonateHost = "127.0.0.1";/' "$DONATE_CPP_FILE"
sed -i.bak 's/static constexpr const char \*kDonateHostTls = ".*";/static constexpr const char *kDonateHostTls = "127.0.0.1";/' "$DONATE_CPP_FILE"
echo "   - kDonateHost 已设置为 \"127.0.0.1\""
echo "   - kDonateHostTls 已设置为 \"127.0.0.1\""

# --- Clean up backup files ---
# 清理 sed 命令创建的备份文件
echo "3. 清理备份文件..."
find . -name "*.bak" -delete

echo "修改完成！"
