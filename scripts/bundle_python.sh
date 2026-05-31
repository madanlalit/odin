#!/bin/bash
set -e

# Configuration
PYTHON_VERSION="3.12.7"
RELEASE_TAG="20241016"
ARCH=$(uname -m)

if [ "$ARCH" = "arm64" ]; then
    TARBALL_NAME="cpython-${PYTHON_VERSION}+${RELEASE_TAG}-aarch64-apple-darwin-install_only.tar.gz"
else
    TARBALL_NAME="cpython-${PYTHON_VERSION}+${RELEASE_TAG}-x86_64-apple-darwin-install_only.tar.gz"
fi

DOWNLOAD_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${RELEASE_TAG}/${TARBALL_NAME}"

REPO_ROOT="$(pwd)"
BUILD_DIR="${REPO_ROOT}/.build"

echo "=== Preparing Build Directories ==="
mkdir -p "${BUILD_DIR}"

# 1. Download Standalone Python Runtime if not cached
if [ ! -f "${BUILD_DIR}/${TARBALL_NAME}" ]; then
    echo "=== Downloading Standalone Python Runtime (macOS ${ARCH}) ==="
    curl -L "${DOWNLOAD_URL}" -o "${BUILD_DIR}/${TARBALL_NAME}"
else
    echo "=== Found cached stand-alone Python tarball ==="
fi

# 2. Extract Python Runtime
echo "=== Extracting Python Runtime ==="
rm -rf "${BUILD_DIR}/python-runtime"
mkdir -p "${BUILD_DIR}/python-runtime"
tar -xzf "${BUILD_DIR}/${TARBALL_NAME}" -C "${BUILD_DIR}/python-runtime"

# 3. Install dependencies using uv into site-packages
echo "=== Installing dependencies into site-packages ==="
rm -rf "${BUILD_DIR}/site-packages"
mkdir -p "${BUILD_DIR}/site-packages"

uv pip install \
    --python "${BUILD_DIR}/python-runtime/python/bin/python3" \
    --target "${BUILD_DIR}/site-packages" \
    --extra all \
    -r "${REPO_ROOT}/pyproject.toml"

# 4. Clean up unnecessary files to reduce bundle size (tests, caches, documentation)
echo "=== Optimizing Python and site-packages to reduce size ==="
find "${BUILD_DIR}/python-runtime/python" -type d -name "test" -exec rm -rf {} + || true
find "${BUILD_DIR}/python-runtime/python" -type d -name "tests" -exec rm -rf {} + || true
find "${BUILD_DIR}/python-runtime/python" -type d -name "__pycache__" -exec rm -rf {} + || true
find "${BUILD_DIR}/site-packages" -type d -name "__pycache__" -exec rm -rf {} + || true
find "${BUILD_DIR}/site-packages" -type d -name "*.dist-info" -exec rm -rf {} + || true

# 5. Stage source code in build folder
echo "=== Staging source code in build folder ==="
rm -rf "${BUILD_DIR}/src"
mkdir -p "${BUILD_DIR}/src/odin"
cp -R "${REPO_ROOT}/src/odin/" "${BUILD_DIR}/src/odin/"

echo "=== Embedded Python Environment Prepared Successfully in .build/ ==="
