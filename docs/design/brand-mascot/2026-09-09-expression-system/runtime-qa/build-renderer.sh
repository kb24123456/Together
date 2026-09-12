#!/bin/zsh
set -euo pipefail
rive_qa_framework="${1:?Pass the directory containing the macOS RiveRuntime.framework}"
rive_qa_output="${2:-/private/tmp/together-rive-frame-probe/render-sequence}"
rive_qa_source_dir="${0:A:h}"
rive_qa_sdk="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "${rive_qa_output:h}" /private/tmp/together-rive-frame-probe/modules
xcrun swiftc -parse-as-library -sdk "$rive_qa_sdk" \
  "$rive_qa_source_dir/sequence.swift" -o "$rive_qa_output" \
  -F "$rive_qa_framework" -framework RiveRuntime \
  -Xlinker -rpath -Xlinker "$rive_qa_framework" \
  -module-cache-path /private/tmp/together-rive-frame-probe/modules
print -r -- "$rive_qa_output"
