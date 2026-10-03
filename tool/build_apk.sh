#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required. Install Flutter 3.47+ first." >&2
  exit 2
fi

# Generate the platform shell with the installed Flutter template if needed.
if [ ! -d android ]; then
  cp lib/main.dart /tmp/tvinder_main.dart
  flutter create . --platforms=android --org com.tvinder --project-name tvinder_mvp
  cp /tmp/tvinder_main.dart lib/main.dart
fi

# Required for runtime calls to Gemini/TMDB.
# Export these before running, or leave blank to build the built-in demo mode.
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.5-flash-lite}"
TMDB_BEARER_TOKEN="${TMDB_BEARER_TOKEN:-}"

# Ensure internet access and portrait-only behavior.
MANIFEST="android/app/src/main/AndroidManifest.xml"
python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
if 'android.permission.INTERNET' not in s:
    s=s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">', '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    <uses-permission android:name="android.permission.INTERNET"/>')
if 'android:screenOrientation="portrait"' not in s:
    s=s.replace('android:name=".MainActivity"', 'android:name=".MainActivity"\n            android:screenOrientation="portrait"')
p.write_text(s)
PY

flutter pub get
flutter build apk --release \
  --dart-define="GEMINI_API_KEY=$GEMINI_API_KEY" \
  --dart-define="GEMINI_MODEL=$GEMINI_MODEL" \
  --dart-define="TMDB_BEARER_TOKEN=$TMDB_BEARER_TOKEN"

OUT="$ROOT/tvinder-mvp.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"
echo "$OUT"
