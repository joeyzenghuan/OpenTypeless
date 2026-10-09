#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/opentypeless-refinement-tests.XXXXXX")
trap 'rm -rf "$test_build_dir"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -swift-version 5 -parse-as-library \
  OpenTypeless/Services/Speech/SpeechRecognitionProvider.swift \
  OpenTypeless/Services/Speech/Providers/AzureSpeechSession.swift \
  OpenTypeless/Services/Database/HistoryDatabase.swift \
  OpenTypeless/Models/TranscriptionRecord.swift \
  OpenTypeless/Utils/Logger.swift \
  Tests/AzureSpeechSessionTests.swift \
  -o "$test_build_dir/refinement-tests"
"$test_build_dir/refinement-tests"
