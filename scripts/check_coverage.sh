#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-60}"
MEMBERS_FILE="$(mktemp "${TMPDIR:-/tmp}/koi-workspace-members.XXXXXX")"

cleanup() {
  rm -f "$MEMBERS_FILE"
}
trap cleanup EXIT INT TERM

if ! awk -v value="$COVERAGE_THRESHOLD" '
  BEGIN {
    valid = value ~ /^[0-9]+([.][0-9]+)?$/ && value >= 60 && value <= 100
    exit(valid ? 0 : 1)
  }
' </dev/null; then
  echo "COVERAGE_THRESHOLD 必须是 60 到 100 之间的数字。" >&2
  exit 2
fi

cd "$ROOT_DIR"
"$ROOT_DIR/tool/melos" list --parsable --relative >"$MEMBERS_FILE"

if [[ ! -s "$MEMBERS_FILE" ]]; then
  echo "未发现 workspace 成员。" >&2
  exit 2
fi

missing_tests=0
while IFS= read -r member; do
  [[ -n "$member" ]] || continue
  if ! find "$member/test" -type f -name '*_test.dart' -print -quit 2>/dev/null | grep -q .; then
    echo "缺少测试: $member 下未找到 test/**/*_test.dart" >&2
    missing_tests=1
  fi
done <"$MEMBERS_FILE"

if [[ "$missing_tests" -ne 0 ]]; then
  exit 1
fi

coverage_reports=()
while IFS= read -r member; do
  [[ -n "$member" ]] || continue
  echo "生成覆盖率: $member"
  (
    cd "$member"
    "$ROOT_DIR/tool/flutterw" test --coverage
  )

  report="$member/coverage/lcov.info"
  if [[ ! -s "$report" ]]; then
    echo "覆盖率报告缺失或为空: $report" >&2
    exit 1
  fi
  "$ROOT_DIR/tool/dartw" run tool/check_coverage_sources.dart "$member" "$report"
  coverage_reports[${#coverage_reports[@]}]="$report"
done <"$MEMBERS_FILE"

awk -v threshold="$COVERAGE_THRESHOLD" '
  function is_generated(path) {
    return path ~ /[.]g[.]dart$/ || path ~ /[.]freezed[.]dart$/
  }

  function is_library_source(path) {
    return path ~ /^lib\// || path ~ /\/lib\//
  }

  /^SF:/ {
    source_file = substr($0, 4)
    include_file = is_library_source(source_file) && !is_generated(source_file)
    next
  }

  include_file && /^DA:/ {
    split(substr($0, 4), fields, ",")
    line_key = FILENAME ":" source_file ":" fields[1]
    if (!(line_key in seen)) {
      seen[line_key] = 1
      total_lines++
      if ((fields[2] + 0) > 0) {
        covered_lines++
      }
    }
  }

  END {
    if (total_lines == 0) {
      print "未在覆盖率报告中找到手写 Dart 代码的可执行行。" > "/dev/stderr"
      exit 2
    }

    coverage = covered_lines * 100 / total_lines
    printf "手写代码合并行覆盖率: %.2f%% (%d/%d)\n", coverage, covered_lines, total_lines
    printf "覆盖率门槛: %.2f%%\n", threshold

    if (coverage + 0.000001 < threshold) {
      print "覆盖率未达到门槛。" > "/dev/stderr"
      exit 1
    }
  }
' "${coverage_reports[@]}"
