#!/bin/bash

# This script automates the entire build process for XMRig.
# It ensures dependencies are built before compiling the main project.
#
# 这个脚本自动化了 XMRig 的整个构建过程。
# 它会确保在编译主项目之前，先构建所有依赖项。

# --- Stop on error ---
# 'set -e' will cause the script to exit immediately if any command fails.
# 'set -e' 会让脚本在任何命令执行失败时立即退出。
set -e

# --- Define Base Directory ---
# Assuming this script is run from the xmrig project's root directory.
# 假设此脚本在 xmrig 项目的根目录下运行。
XMRIG_DIR=$(pwd)
BUILD_DIR="$XMRIG_DIR/build"
SCRIPTS_DIR="$XMRIG_DIR/scripts"
DEPS_DIR="$SCRIPTS_DIR/deps"

echo "Starting XMRig build process..."

# 1. Create the build directory if it doesn't exist.
#    如果构建目录不存在，则创建它。
echo "1. Creating build directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 2. Navigate to the scripts directory and build dependencies.
#    进入脚本目录并构建依赖。
echo "2. Building dependencies..."
cd "$SCRIPTS_DIR"
./build_deps.sh

# 3. Navigate to the build directory.
#    进入构建目录。
echo "3. Navigating to build directory..."
cd "$BUILD_DIR"

# 4. Run CMake to configure the project.
#    运行 CMake 来配置项目。
echo "4. Configuring project with CMake..."
cmake .. -DXMRIG_DEPS="$DEPS_DIR"

# 5. Compile the project using all available processor cores.
#    使用所有可用的处理器核心来编译项目。
#    nproc is a command that prints the number of processing units available.
#    nproc 是一个打印可用处理单元数量的命令。
echo "5. Compiling XMRig... (This may take a while)"
make -j$(nproc)

echo ""
echo "Build complete!"
echo "The XMRig executable can be found in the '$BUILD_DIR' directory."
