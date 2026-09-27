#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${INPUTSOURCELOCK_BUILD_DIR:-$PROJECT_DIR/.build}"

echo "==> Running InputSourceLock pure logic and throttling tests..."
cd "$PROJECT_DIR"
swift run --scratch-path "$BUILD_DIR" InputSourceLockTests
