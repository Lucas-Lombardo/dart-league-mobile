# Dart Rivals Mobile - Comprehensive Audit Report

**Date**: 2026-03-20
**Codebase**: Flutter/Dart mobile app (~28,000 lines across 83 files)
**Version**: 1.0.10+10

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Security](#security)
3. [Services Layer](#services-layer)
4. [State Management (Providers)](#state-management-providers)
5. [UI / Screens](#ui--screens)
6. [Models & Data Layer](#models--data-layer)
7. [Code Quality & Linting](#code-quality--linting)
9. [Architecture & Design](#architecture--design)
10. [Positive Findings](#positive-findings)
11. [Recommendations](#recommendations)

---

## Executive Summary

| Severity | Count | Fixed |
|----------|-------|-------|
| Critical | 5 | 5 |
| High     | 5 | 5 |
| Medium   | 25+ | 0 |
| Low      | 15+ | 0 |

**Top risks**: ~~Exposed credentials in source control~~, ~~memory leaks from undisposed providers~~, ~~race conditions in async/socket code~~, and 42+ unguarded `print()` statements shipping to production.

---

## Security

### ~~SEC-1: Android Keystore Password in Repository (CRITICAL)~~ FIXED

**File**: `android/key.properties`
Added `android/key.properties` to `.gitignore`. File was already untracked. Password rotation still recommended.

### ~~SEC-2: Stripe Test Key Hardcoded in Source (HIGH)~~ FIXED

**File**: `lib/main.dart:42`
Moved to `String.fromEnvironment('STRIPE_PUBLISHABLE_KEY')` with test key as default. Production builds use `--dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_...`.

### SEC-3: Firebase Config Files in Git (MEDIUM)

**Files**: `ios/Runner/GoogleService-Info.plist`, `android/app/google-services.json`
These are expected for mobile builds but should be protected by Firebase Security Rules and App Check. Verify these are in place.

### SEC-4: API Base URL Hardcoded (LOW)

**File**: `lib/utils/api_config.dart`
```dart
static const String baseUrl = 'https://api.dart-rivals.com';
```
Consider environment-specific configs for dev/staging/prod.

---

## Services Layer

### ~~SVC-1: Socket Listener Leakage (CRITICAL)~~ FIXED

**File**: `lib/services/socket_service.dart:123-131`
Removed fallback `_socket!.off(event)` that nuked all handlers. Now only removes the specific tracked handler.

### ~~SVC-2: PushNotificationService Stream Subscriptions Never Canceled (CRITICAL)~~ FIXED

**File**: `lib/services/push_notification_service.dart:47-61`
Stream subscriptions now stored in static fields, canceled before re-registration, and cleaned up in a new `dispose()` method.

### SVC-3: Race Condition in Socket Reconnect Token Refresh (MEDIUM)

**File**: `lib/services/socket_service.dart:68-82`
Token refresh fires asynchronously without awaiting. If `disconnect()` is called before `connect()` finishes, the socket enters an undefined state.

### SVC-4: No Timeout on ensureConnected (MEDIUM)

**File**: `lib/services/socket_service.dart:133-138`
Hardcoded 500ms delay is arbitrary and may be insufficient on slow connections.

### SVC-5: Agora Snapshot Handler Leak (MEDIUM)

**File**: `lib/services/agora_service.dart:180-223`
If the completer times out before the callback fires, the event handler remains registered in Agora's internal list.

### SVC-6: Missing JSON Decode Safety (MEDIUM)

**File**: `lib/services/api_service.dart:285`
`jsonDecode()` on response body can throw on malformed JSON. No try-catch around it.

### SVC-7: Static onAuthFailure Callback (MEDIUM)

**File**: `lib/services/api_service.dart:12, 80`
`ApiService.onAuthFailure` is a static property that's never cleared. If set by different screens, only the last one persists. Navigation may break on auth failure from unexpected contexts.

### SVC-8: No Exponential Backoff on Token Refresh (MEDIUM)

**File**: `lib/services/api_service.dart:36-77`
If token refresh fails, subsequent requests retry immediately. During server outages this hammers the endpoint.

### SVC-9: Google Pay testEnv=true in Production Code (MEDIUM)

**File**: `lib/services/payment_service.dart:29`
Google Pay is configured for test mode. Must be `false` for production.

### SVC-10: MatchmakingService URL Without Proper Encoding (LOW)

**File**: `lib/services/matchmaking_service.dart:18`
`leaveQueue()` uses string interpolation for query params instead of `Uri` with `queryParameters`.

---

## State Management (Providers)

### ~~PRV-1: TournamentProvider Missing dispose() (CRITICAL)~~ FIXED

**File**: `lib/providers/tournament_provider.dart`
Added `dispose()` override that calls `clearSocketListeners()` before `super.dispose()`.

### PRV-2: FriendsProvider Missing dispose() (MEDIUM)

**File**: `lib/providers/friends_provider.dart`
No `dispose()` override. Internal state is never reset if provider instances are recreated.

### PRV-3: PlacementProvider Missing dispose() (MEDIUM)

**File**: `lib/providers/placement_provider.dart`
No `dispose()` override. Match state persists between placement attempts.

### ~~PRV-4: Double Socket Listener Setup on Reconnect (HIGH)~~ FIXED

**File**: `lib/providers/matchmaking_provider.dart:80-86`
Reordered so `_setupSocketListeners()` is called once, then reconnect handler is set (only fires on actual reconnect).

### ~~PRV-5: Race Condition in Active Match Polling (HIGH)~~ FIXED

**File**: `lib/providers/matchmaking_provider.dart:146-165`
Added state re-check after `await` to prevent acting on stale `_isSearching`/`_matchFound` state.

### PRV-6: GameProvider Timer Not Disposed (MEDIUM)

**File**: `lib/providers/game_provider.dart:487-494, 780-783`
`_disconnectCountdownTimer` is created on opponent disconnect. It's canceled in `reset()` but not in `dispose()`. Timer persists if provider is disposed during active countdown.

### PRV-7: LocaleProvider Async in Constructor (MEDIUM)

**File**: `lib/providers/locale_provider.dart:11-12, 39`
`_loadLocale()` called in constructor calls `notifyListeners()` before provider is fully registered with the framework.

### PRV-8: Exposed Mutable Collections (MEDIUM)

**File**: `lib/providers/game_provider.dart:63-64, 68`
```dart
List<String> get currentRoundThrows => _currentRoundThrows;
List<String> get opponentRoundThrows => _opponentRoundThrows;
```
Returns mutable references. UI code could modify internal state directly, bypassing `notifyListeners()`.

### PRV-9: Reconnect Handler Not Cleared Before Re-registration (MEDIUM)

**File**: `lib/providers/matchmaking_provider.dart:80, 284`
`setReconnectHandler()` called without clearing old handler first. If `joinQueue()` is called twice, stale handler logic runs.

### PRV-10: No Post-Dispose Guard on notifyListeners (LOW)

**All provider files**
No providers check whether they've been disposed before calling `notifyListeners()` in async callbacks. Can throw if provider is disposed while an async operation is in-flight.

### PRV-11: FriendsProvider Future.wait Without Error Isolation (LOW)

**File**: `lib/providers/friends_provider.dart:96-102`
`Future.wait()` without `eagerError: false` means if any sub-call fails, entire load fails and state is partially loaded.

---

## UI / Screens

### ~~UI-1: Hardcoded Strings Missing Localization (HIGH)~~ FIXED

25+ hardcoded strings replaced with `AppLocalizations` keys across `game_screen.dart`, `matchmaking_screen.dart`, `tournament_game_screen.dart`, and `player_stats_screen.dart`.

### ~~UI-2: Empty Catch Blocks Swallow Errors (HIGH)~~ FIXED

All 13+ `catch (_) {}` blocks replaced with `catch (e) { debugPrint(...); }` across all 6 screen files. Also converted 2 `print()` calls to `debugPrint()` in camera setup screens.

### UI-3: Unsafe Async Dialog Handlers (MEDIUM)

**File**: `lib/screens/game/base_game_screen_state.dart:376, 387, 405+`
```dart
}).then((_) => winDialogShowing = false); // No mounted check
```
Dialog `.then()` callbacks execute without verifying widget is still mounted. Can call `setState` on disposed widget.

### UI-4: Large Monolithic Build Methods (MEDIUM)

| File | Build Method Size |
|------|-------------------|
| `screens/game/game_screen.dart` | 254+ lines (294-547) |
| `screens/tournament/tournament_game_screen.dart` | 80+ lines |
| `screens/matchmaking/camera_setup_screen.dart` | 300+ lines |

Should be extracted into separate widget classes for readability and rebuild performance.

### UI-5: Weak Email Validation (MEDIUM)

**Files**: `screens/auth/login_screen.dart:90`, `screens/auth/forgot_password_screen.dart:122`
```dart
if (!value.contains('@')) // Only checks for @ symbol
```
Should use proper regex or `email_validator` package.

### UI-6: Future.delayed Polling Patterns (MEDIUM)

**File**: `screens/matchmaking/matchmaking_screen.dart:250-254`
Uses recursive `Future.delayed` with 100ms/500ms intervals for navigation polling. Should use Provider state listeners instead.

### UI-7: Mixed Mounted Check Styles (LOW)

**File**: `screens/game/game_screen.dart`
Inconsistently uses both `mounted` and `context.mounted` within the same file. Should standardize on one pattern.

### UI-8: Dead Code (LOW)

**File**: `screens/game/game_screen.dart:40, 112`
```dart
final bool _didForfeit = false; // Declared final, never modified
if (!_didForfeit) leaveMatch(); // Always true
```

### UI-9: Missing Accessibility (LOW)

- Radar animation in matchmaking screen lacks semantic labels
- Dart indicators in game screen have no accessibility text
- AI toggle button missing semantic label
- Navigation items in home screen missing semantic labels for custom nav

### UI-10: Magic Numbers (LOW)

- `home_screen.dart:25` - `_currentIndex = 2` for "Play" tab
- `matchmaking_screen.dart:175-177` - `50` attempts, `100ms` delays, `5 seconds` timeout
- `camera_setup_screen.dart:146-149` - Spread thresholds `0.50`, `0.85`

---

## Models & Data Layer

### MDL-1: Unguarded DateTime.parse() Calls (MEDIUM)

**Files**: `models/match.dart:54`, `models/tournament.dart:51,53,56,199-206,270,342`, `models/user.dart:43-44`

`DateTime.parse()` throws `FormatException` on malformed strings. No try-catch around any of these calls. A single malformed timestamp from the API will crash the app.

### MDL-2: Missing Value Equality (MEDIUM)

**Files**: All model files (`match.dart`, `tournament.dart`, `user.dart`)

No `==` operator or `hashCode` overrides. Models compared by reference, not value. Can cause Provider to miss state changes or duplicate items in sets.

### MDL-3: No copyWith() Methods (LOW)

No immutable update pattern available. Makes state updates verbose and error-prone.

### MDL-4: Unsafe Type Casting (LOW)

**File**: `models/match.dart:61, 84, 112, 195-196`
```dart
json['statistics'] as Map<String, dynamic> // Can throw if not a Map
```
Should use `as?` or validate type before casting.

### MDL-5: False Default Timestamps (LOW)

**File**: `models/match.dart:55`
```dart
createdAt: json['createdAt'] != null ? DateTime.parse(...) : DateTime.now()
```
Missing `createdAt` gets current time, creating false historical data.

---

## Code Quality & Linting

### Lint Summary

```
flutter analyze: 49 info-level issues, 0 warnings, 0 errors (down from 51)
```

### CQ-1: 44+ print() Statements in Production Code (MEDIUM)

| File | Count |
|------|-------|
| `services/dart_detection_service.dart` | 11+ |
| `services/socket_service.dart` | 9+ |
| `services/auto_scoring_service.dart` | 3+ |
| `services/detection_isolate.dart` | 3+ |
| Camera setup screens | 3+ (2 fixed) |
| Other services | 13+ |

All should use `debugPrint()` which is stripped in release builds.

### CQ-2: BuildContext Across Async Gaps (INFO)

7 instances across 6 screen files where `BuildContext` is used after `await` without proper `mounted` checks:
- `game_screen.dart:217`
- `friends_screen.dart:185`
- `play_screen.dart:472`
- `tournament_detail_screen.dart:491,492`
- `tournament_screen.dart:882,883`
- `splash_screen.dart:63`

### CQ-3: Control Flow Without Braces (INFO)

**File**: `screens/game/base_game_screen_state.dart:202`
```dart
if (game.isMyTurn) autoScoringService!.startCapture(...)
```

### CQ-4: Unnecessary Import (INFO)

**File**: `providers/locale_provider.dart:2`
Imports `package:flutter/foundation.dart` when `package:flutter/material.dart` is already imported.

---

## Architecture & Design

### ARCH-1: Duplicated Camera Setup Logic

Three nearly identical camera setup screens:
- `screens/matchmaking/camera_setup_screen.dart`
- `screens/placement/placement_camera_setup_screen.dart`
- `screens/tournament/tournament_camera_setup_screen.dart`

Should be extracted into a shared base class or mixin.

### ARCH-2: Inconsistent Navigation Patterns

Mixed usage across screens:
- `Navigator.pushReplacementNamed()` (login)
- `Navigator.pushAndRemoveUntil()` (matchmaking)
- `Navigator.pushReplacement()` (tournament)
- `Navigator.popUntil(route.isFirst)` (game)

Should establish and document a consistent navigation strategy.

### ARCH-3: Inconsistent Error Handling in Services

All service methods use bare `rethrow` without context. Callers can't distinguish which operation failed without inspecting exception messages.

**Files**: `matchmaking_service.dart`, `placement_service.dart`, `user_service.dart`, `tournament_service.dart`, `friends_service.dart`, `match_service.dart`

---

## Positive Findings

1. **Solid API layer** - `api_service.dart` has proper 401/403/404/500 handling with token refresh retry
2. **Secure token storage** - `flutter_secure_storage` used for JWT tokens
3. **Good socket reconnection** - `socket_service.dart` handles reconnect with token refresh
4. **Smart isolate fallback** - `detection_isolate.dart` falls back to main thread if isolate fails
5. **Consistent theming** - `AppTheme` used throughout the app
6. **Localization infrastructure** - L10n configured with English and French
7. **Good widget composition** - Reusable widgets in `lib/widgets/` with proper parameters
8. **User-friendly errors** - `ErrorMessages` utility provides localized error strings
9. **Proper ProGuard rules** - Stripe and TFLite classes preserved correctly
10. **Wakelock management** - Screen kept awake during active games

---

## Recommendations

### Immediate (Before Next Release)

| Priority | Issue | Action | Status |
|----------|-------|--------|--------|
| P0 | SEC-1 | Remove `android/key.properties` from git, add to `.gitignore`, rotate password | FIXED |
| P0 | SEC-2 | Move Stripe key to `--dart-define` or environment config | FIXED |
| P0 | SVC-9 | Set Google Pay `testEnv: false` for production builds | |
| P1 | MDL-1 | Wrap all `DateTime.parse()` calls in try-catch | |
| P1 | UI-2 | Replace empty catch blocks with `debugPrint` logging | FIXED |
| P1 | PRV-1 | Add `dispose()` to TournamentProvider with socket cleanup | FIXED |

### Short-Term (Next Sprint)

| Priority | Issue | Action | Status |
|----------|-------|--------|--------|
| P2 | SVC-1 | Fix socket listener leakage in `off()` | FIXED |
| P2 | SVC-2 | Store and cancel push notification stream subscriptions | FIXED |
| P2 | PRV-4 | Fix double listener registration in MatchmakingProvider | FIXED |
| P2 | PRV-5 | Re-check state after await in polling callback | FIXED |
| P2 | CQ-1 | Replace all `print()` with `debugPrint()` | |
| P2 | UI-1 | Localize remaining hardcoded strings | FIXED |
| P2 | MDL-2 | Add `==` and `hashCode` to all models | |

### Long-Term

| Priority | Issue | Action |
|----------|-------|--------|
| P3 | ARCH-1 | Extract shared camera setup base class |
| P3 | ARCH-2 | Document and standardize navigation patterns |
| P3 | UI-9 | Add accessibility semantics throughout |
| P3 | PRV-8 | Return `UnmodifiableListView` from collection getters |
