#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/opentypeless-mai-tests.XXXXXX")
trap 'rm -rf "$test_build_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -swift-version 5 -parse-as-library \
  OpenTypeless/Services/Speech/SpeechRecognitionProvider.swift \
  OpenTypeless/Services/Speech/Providers/MAITranscribeSession.swift \
  OpenTypeless/Services/Speech/Providers/MAITranscribeSpeechProvider.swift \
  OpenTypeless/Services/Speech/Providers/MAITranscribeBatchClient.swift \
  OpenTypeless/Services/Speech/Providers/MAITranscribeBatchSpeechProvider.swift \
  OpenTypeless/Utils/Logger.swift \
  Tests/MAITranscribeSessionTests.swift \
  Tests/MAITranscribeBatchTests.swift \
  -o "$test_build_dir/mai-transcribe-tests"
"$test_build_dir/mai-transcribe-tests"
