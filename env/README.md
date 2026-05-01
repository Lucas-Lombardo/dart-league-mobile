# Build environments

These JSON files are passed to Flutter via `--dart-define-from-file=…` at build time.
Values land in code via `String.fromEnvironment('KEY')`.

## Files

- `dev.json` — test-mode keys, used for local dev (Stripe test account, test webhook)
- `prod.json` — live-mode keys, used for App Store / Play Store releases

## Keys

| Key | Where it's used | Secret? |
|---|---|---|
| `STRIPE_PUBLISHABLE_KEY` | `lib/main.dart` → `Stripe.publishableKey` | No — Stripe publishable keys are client-side by design |

## Build commands

```bash
# Local dev (default)
flutter run --dart-define-from-file=env/dev.json

# Release builds
make release-android       # uses env/prod.json
make release-ios           # uses env/prod.json
```

## Before shipping prod

Replace `pk_live_REPLACE_ME` in `prod.json` with the real `pk_live_…` from your
Stripe live dashboard → Développeurs → Clés API.

## Note on git

Both files are committed because publishable keys are not secrets. If you add
**secret** keys (like API tokens) here later, add `env/prod.json` to `.gitignore`
and document where to find the values.
