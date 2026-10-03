# Tvinder MVP

Flutter MVP for adaptive Persian movie recommendations.

## Runtime behavior
- Portrait-only Android MVP.
- Splash -> swipe guide -> exactly 25 adaptive yes/no swipe cards.
- Right = بله, left = نه.
- No counter, no account, no persistence.
- Warm-white / subtle-gold glass UI, haptics, subtle system click.
- Final internal analysis is hidden from the user.
- One movie per screen: poster, original title, «بعدی», «دیدم».
- Five rounds of three unique movie slots. «دیدم» replaces the current movie and does not consume a slot.
- After round five: «از نو» / «خروج».

## Live services
The app is built to use:
- Gemini Developer API: `gemini-3.5-flash-lite` by default.
- TMDB v3 via a read-access bearer token.

Pass secrets only at build time for this private MVP:

```bash
export GEMINI_API_KEY='...'
export TMDB_BEARER_TOKEN='...'
./tool/build_apk.sh
```

If keys are omitted, the app still runs in a built-in demo mode with adaptive local questions and a curated high-quality movie pool. Demo mode uses stylized poster placeholders.

For a public production release, do not ship long-lived API secrets in the APK. Put Gemini/TMDB behind a small backend or Firebase AI Logic/App Check.


## Zero-local-toolchain APK build
A GitHub Actions workflow is included at `.github/workflows/build-apk.yml`. It installs stable Flutter, builds the release APK, and uploads `tvinder-mvp.apk` as an artifact. With no secrets it builds Demo Mode. For live mode add repository secrets `GEMINI_API_KEY` and `TMDB_BEARER_TOKEN`.
