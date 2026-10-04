#!/bin/bash
set -euo pipefail

# Uses the same test cases as swift test, including on Macs with CLT only.
VIBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIBE_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibe-core-tests.XXXXXX")"
trap 'rm -rf "$VIBE_TEST_DIR"' EXIT
VIBE_CORE="$VIBE_ROOT/apps/macos/Sources/VibeRemoteCore"
VIBE_TESTS="$VIBE_ROOT/apps/macos/Tests/VibeRemoteCoreTests"
VIBE_MODULE_CACHE="${TMPDIR:-/tmp}/viberemote-core-module-cache"

swiftc -swift-version 5 -emit-library -emit-module -enable-testing \
    -module-cache-path "$VIBE_MODULE_CACHE" \
    -module-name VibeRemoteCore "$VIBE_CORE"/*.swift \
    -emit-module-path "$VIBE_TEST_DIR/VibeRemoteCore.swiftmodule" \
    -o "$VIBE_TEST_DIR/libVibeRemoteCore.dylib"

python3 - "$VIBE_TESTS" "$VIBE_TEST_DIR/main.swift" <<'PY'
from pathlib import Path
import re
import sys

cases = []
for path in sorted(Path(sys.argv[1]).glob('*Tests.swift')):
    source = path.read_text()
    classes = re.findall(r'final class (\w+): XCTestCase', source)
    if len(classes) != 1:
        raise SystemExit(f'Expected one XCTestCase in {path}')
    for method in re.findall(r'func (test\w+)\(\)', source):
        cases.append((f'{classes[0]}.{method}', f'{classes[0]}().{method}'))
if not cases:
    raise SystemExit('No native test cases found')
lines = ['import Foundation', 'let cases: [(String, () throws -> Void)] = [']
lines += [f'    ("{name}", {method}),' for name, method in cases]
lines += [''']
for (name, run) in cases {
    let before = standaloneFailures
    do { try run() } catch { XCTFail("\\(name): \\(error)") }
    if before == standaloneFailures { print("PASS \\(name)") }
}
print("\\(cases.count) tests; \\(standaloneFailures) failures")
exit(standaloneFailures == 0 ? 0 : 1)
''']
Path(sys.argv[2]).write_text('\n'.join(lines))
PY

swiftc -swift-version 5 -D VIBE_STANDALONE_TESTS \
    -module-cache-path "$VIBE_MODULE_CACHE" \
    -I "$VIBE_TEST_DIR" -L "$VIBE_TEST_DIR" -lVibeRemoteCore \
    -Xlinker -rpath -Xlinker "$VIBE_TEST_DIR" \
    "$VIBE_TESTS"/*.swift "$VIBE_TEST_DIR/main.swift" \
    -o "$VIBE_TEST_DIR/core-tests"
"$VIBE_TEST_DIR/core-tests"
