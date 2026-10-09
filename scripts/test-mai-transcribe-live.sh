#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-all}"
if [[ "$mode" != "batch" && "$mode" != "streaming" && "$mode" != "all" ]]; then
  echo "Usage: $0 [batch|streaming|all]" >&2
  exit 2
fi
test_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/opentypeless-mai-live.XXXXXX")
trap 'rm -rf "$test_build_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
say -v Tingting -r 170 -o "$test_build_dir/zh.aiff" '你好，这是语音输入测试，微软模型正在识别中文。'
say -v Samantha -r 170 -o "$test_build_dir/en.aiff" 'Hello, this is an Azure speech recognition test. The weather is clear today.'
afconvert -f WAVE -d LEI16@16000 -c 1 "$test_build_dir/zh.aiff" "$test_build_dir/zh.wav"
afconvert -f WAVE -d LEI16@16000 -c 1 "$test_build_dir/en.aiff" "$test_build_dir/en.wav"
xcrun swiftc -swift-version 5 -parse-as-library \
  OpenTypeless/Services/Speech/SpeechRecognitionProvider.swift \
  OpenTypeless/Services/Speech/Providers/MAITranscribeSession.swift \
  OpenTypeless/Services/Speech/Providers/MAITranscribeSpeechProvider.swift \
  OpenTypeless/Services/Speech/Providers/MAITranscribeBatchClient.swift \
  OpenTypeless/Utils/Logger.swift \
  Tests/MAITranscribeLiveTests.swift \
  -o "$test_build_dir/mai-live-tests"
"$test_build_dir/mai-live-tests" "$mode" "$test_build_dir/zh.wav" "$test_build_dir/en.wav"
