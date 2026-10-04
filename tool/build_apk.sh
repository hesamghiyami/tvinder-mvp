#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "======================================"
echo "Building: Tvinder Online Test"
echo "======================================"

# --------------------------------------------------
# 1. Check Flutter
# --------------------------------------------------

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter SDK is required." >&2
  exit 2
fi

flutter --version


# --------------------------------------------------
# 2. Require real online API credentials
# --------------------------------------------------

GEMINI_API_KEY="${GEMINI_API_KEY:-}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.5-flash-lite}"
TMDB_BEARER_TOKEN="${TMDB_BEARER_TOKEN:-}"

if [ -z "$GEMINI_API_KEY" ]; then
  echo "ERROR: GEMINI_API_KEY is missing." >&2
  exit 3
fi

if [ -z "$TMDB_BEARER_TOKEN" ]; then
  echo "ERROR: TMDB_BEARER_TOKEN is missing." >&2
  exit 4
fi

echo "Gemini API key: configured"
echo "Gemini model: $GEMINI_MODEL"
echo "TMDB token: configured"


# --------------------------------------------------
# 3. Generate Android project if needed
# --------------------------------------------------

if [ ! -d android ]; then
  echo "Generating Android platform..."

  cp lib/main.dart /tmp/tvinder_main.dart

  flutter create . \
    --platforms=android \
    --org com.tvinder \
    --project-name tvinder_mvp

  cp /tmp/tvinder_main.dart lib/main.dart
fi


# --------------------------------------------------
# 4. Configure AndroidManifest.xml
# --------------------------------------------------

MANIFEST="android/app/src/main/AndroidManifest.xml"

python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

# Add internet permission.
if 'android.permission.INTERNET' not in text:
    text = text.replace(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <uses-permission android:name="android.permission.INTERNET"/>'
    )

# Force portrait orientation.
if 'android:screenOrientation="portrait"' not in text:
    text = text.replace(
        'android:name=".MainActivity"',
        'android:name=".MainActivity"\n'
        '            android:screenOrientation="portrait"'
    )

# Give this build an unmistakable visible name.
text = re.sub(
    r'android:label="[^"]*"',
    'android:label="Tvinder Online Test"',
    text,
    count=1
)

path.write_text(text)
PY


# --------------------------------------------------
# 5. Install Flutter dependencies
# --------------------------------------------------

flutter pub get


# --------------------------------------------------
# 6. Build real online APK
# --------------------------------------------------

echo "Building release APK..."

flutter build apk --release \
  --dart-define="GEMINI_API_KEY=$GEMINI_API_KEY" \
  --dart-define="GEMINI_MODEL=$GEMINI_MODEL" \
  --dart-define="TMDB_BEARER_TOKEN=$TMDB_BEARER_TOKEN"


# --------------------------------------------------
# 7. Copy APK with a UNIQUE filename
# --------------------------------------------------

SOURCE_APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
OUTPUT_APK="$ROOT/tvinder-online-test.apk"

if [ ! -f "$SOURCE_APK" ]; then
  echo "ERROR: APK was not generated." >&2
  exit 5
fi

cp "$SOURCE_APK" "$OUTPUT_APK"


# --------------------------------------------------
# 8. Final verification
# --------------------------------------------------

echo
echo "======================================"
echo "BUILD SUCCESSFUL"
echo "APK: $OUTPUT_APK"
echo "App name: Tvinder Online Test"
echo "======================================"

ls -lh "$OUTPUT_APK"

if command -v sha256sum >/dev/null 2>&1; then
  echo
  echo "SHA256:"
  sha256sum "$OUTPUT_APK"
fi
