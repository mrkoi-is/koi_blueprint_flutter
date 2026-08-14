#!/usr/bin/env bash
# 生成物（*.g.dart / *.freezed.dart）不入库，由本地与 CI 按需生成。
# 本脚本的语义：在干净检出上验证代码生成可以完整跑通——
# 直接运行 `melos run generate --no-select`，并以其退出码为准。
# 不再做 `git diff` 一致性校验，因为仓库中不存在可对比的生成物基线。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"
"$ROOT_DIR/tool/melos" run generate --no-select
