# Meta (Facebook) Ads — setup

The SDK is installed and wired, and the credentials are in place. What is left
is the Meta-side configuration.

## 1. Credentials (done)

App **Dart Rivals**, ID `1595576982237919`. The App ID and the client token live
in `android/app/src/main/res/values/facebook.xml` and `ios/Runner/Info.plist`.
Both are public — they ship inside every build, like the Stripe publishable key
— so they are committed rather than kept in `env/`.

They came from developers.facebook.com → the app → *Paramètres → Général*
(App ID) and *→ Avancé* (Jeton client). If they are ever rotated, change both
files: `make check-facebook` (run by every release target) fails if either is
left on a placeholder.

## 2. Register the platforms in the Meta console

Under *Paramètres → De base → Ajouter une plateforme*:

- **Android** — package `com.dartrivals.app`, class `com.dartrivals.app.MainActivity`.
- **iOS** — bundle ID `com.llombardo.dartrivals`.

The *Key hashes* field only matters for Facebook Login, which this app does not
use — App Events work without it. If it is ever filled in, do NOT derive it from
`upload-keystore.jks`: the app ships through Play App Signing, so the signature
users actually run is Google's. Take the SHA-1 of the **app signing**
certificate from Play Console (*Test and release → Setup → App signing*) and
convert it to the base64 Meta expects:

```bash
echo "AA:BB:CC:…" | tr -d ':' | xxd -r -p | openssl base64
```

Then in *Events Manager → your app*, turn on **App Events** and, for iOS,
configure **SKAdNetwork / AEM** (Meta calls it « Mesure des événements
agrégés ») — that is what still reports conversions for users who decline the
ATT prompt.

## 3. What the app reports

| Meta event | When | Code |
|---|---|---|
| install / session | automatic | `MetaEventsService.init()` (`lib/services/meta_events_service.dart`) |
| `CompleteRegistration` | account created (not on login) | `AuthProvider.register` |
| `InitiatedCheckout` | paywall → Apple sheet or Stripe Checkout | `SubscriptionProvider.startCheckout` |
| `Purchase` + `Subscribe` | new paid subscription only, never a restore | `IapService` (Apple, real charged price) / `SubscriptionProvider` (Stripe) |

iOS asks for App Tracking Transparency once, from the home screen rather than
at launch — a refusal is permanent, so the prompt waits until the user has seen
the app.

## 4. Verifying before spending money

1. `make run-dev` on a device (debug logging is on in debug builds).
2. Events Manager → *Test des événements d'application* → enter the device's
   advertiser ID; create an account and start a checkout.
3. Both events must appear within a minute or so. If nothing arrives, the App
   ID / client token pair or the platform registration in step 2 is wrong.

## Not done (deliberately)

- **Conversions API.** Everything is client-side for now. Server-side events
  from the backend would survive ad blockers and ATT refusals, and would let
  Meta see renewals and Stripe webhooks the app never observes.
- **Consent gating on Android.** iOS is covered by ATT; on Android the SDK
  starts collecting on first launch. If a GDPR consent banner is ever added,
  it should drive `setAdvertiserIdCollectionEnabled`.
- **Activation event.** "Finished a first match" would likely be the strongest
  optimisation signal for a game, but it is not wired yet.
