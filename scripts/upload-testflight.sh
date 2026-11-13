#!/usr/bin/env bash
# Manual/CI release for App Store Connect app 6829997725. Never installed as a hook.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_ID="Q4F3H4FLRZ"
ISSUER_ID="69a6de91-4f5b-47e3-e053-5b8c7c11a4d1"
KEY_PATH="${HOME}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
RUN_CHECKS=1

usage() {
  printf 'Usage: scripts/upload-testflight.sh [--skip-checks]\n'
  printf 'Bump build, test/analyze, build a company-signed IPA, and upload to TestFlight.\n'
  printf 'Run CI releases serially from a checkout retaining the updated pubspec.yaml.\n'
}
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
for arg in "$@"; do
  case "$arg" in
    --skip-checks) RUN_CHECKS=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $arg" ;;
  esac
done

cd "$ROOT"
[[ -f "$KEY_PATH" && -r "$KEY_PATH" ]] || die "App Store Connect key missing or unreadable: $KEY_PATH (no files changed)."
for cmd in flutter xcrun python3; do
  command -v "$cmd" >/dev/null 2>&1 || die "$cmd not found in PATH"
done

# Prevent two invocations in this checkout from allocating the same build.
mkdir -p .dart_tool
LOCK="${ROOT}/.dart_tool/upload-testflight.lock"
mkdir "$LOCK" 2>/dev/null || die "Another release is running ($LOCK). Remove the lock only if that process has stopped."
trap 'rmdir "$LOCK"' EXIT

# Refuse to archive with a personal/upstream identity or mixed configurations.
python3 - <<'PY'
from pathlib import Path
import re
s = Path('ios/Runner.xcodeproj/project.pbxproj').read_text()
expected = {
    'DEVELOPMENT_TEAM': {'W4SX57U6XB'},
    'CODE_SIGN_STYLE': {'Automatic'},
    'PRODUCT_BUNDLE_IDENTIFIER': {
        'com.weallwitness.soundcore', 'com.weallwitness.soundcore.RunnerTests'},
}
for key, values in expected.items():
    actual = re.findall(r'\b' + key + r'\s*=\s*([^;]+);', s)
    if len(actual) != 6 or set(actual) != values:
        raise SystemExit(f'error: Unexpected iOS {key}; check all Runner and RunnerTests configurations.')
PY

# Reserve the build before doing work. Keep it even on failure, so a retry
# cannot reuse an upload whose server result was lost. Marketing version stays.
VERSION="$(python3 - <<'PY'
from datetime import datetime
from pathlib import Path
import re
p = Path('pubspec.yaml')
s = p.read_text()
m = re.search(r'^(version:\s*)(\d+\.\d+\.\d+)\+(\d+)(\s*(?:#.*)?)$', s, re.M)
if not m:
    raise SystemExit('error: Expected version: major.minor.patch+integer in pubspec.yaml')
next_build = max(int(m[3]) + 1, int(datetime.now().strftime('%Y%m%d') + '01'), 2026111301)
version = f'{m[2]}+{next_build}'
p.write_text(s[:m.start()] + m[1] + version + m[4] + s[m.end():])
print(version)
PY
)"
printf '==> Version/build: %s\n' "$VERSION"
printf '==> Signing: W4SX57U6XB / com.weallwitness.soundcore (Automatic)\n'

if (( RUN_CHECKS )); then
  flutter test
  flutter analyze
fi

# Move old artifacts aside so an export failure cannot upload a stale IPA.
IPA_DIR="${ROOT}/build/ios/ipa"
if [[ -d "$IPA_DIR" ]]; then
  ARCHIVE_DIR="$(mktemp -d "${ROOT}/build/ios/previous-ipa.XXXXXX")"
  mv "$IPA_DIR" "$ARCHIVE_DIR/ipa"
fi
if flutter build ipa --release --export-method app-store; then
  printf '==> IPA build succeeded for %s\n' "$VERSION"
else
  result=$?
  printf 'error: IPA build failed for %s (exit %s); build number remains reserved.\n' "$VERSION" "$result" >&2
  exit "$result"
fi
shopt -s nullglob
IPAS=("$IPA_DIR"/*.ipa)
((${#IPAS[@]} == 1)) || die "Expected exactly one new IPA in $IPA_DIR; found ${#IPAS[@]}"
IPA="${IPAS[0]}"
printf '==> IPA: %s\n' "$IPA"
if xcrun altool --upload-app --type ios \
  -f "$IPA" \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID"; then
  printf '==> altool upload succeeded: %s (%s). Apple processing is still pending.\n' "$VERSION" "$IPA"
else
  result=$?
  printf 'error: altool upload failed: %s (%s), exit %s.\n' "$VERSION" "$IPA" "$result" >&2
  exit "$result"
fi
