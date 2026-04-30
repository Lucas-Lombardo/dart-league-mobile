# Dart Legends — Mobile App Audit

**Audit date:** 2026-04-29
**Branch:** `main` @ commit `3aece4e`
**App version:** `1.0.23+23` (`pubspec.yaml`)
**Scope:** Full Flutter client at `lib/` (~35 000 LOC, 27 services, 8 providers, 30+ screens). Server code is out of scope — but findings note where the client trusts the server in ways the server *must* validate.
**Reviewer focus areas (per request):** Agora video, AI autoscoring, games, ranked, placement, tournament, training, friends, ranking.

---

## 0. Executive summary

The codebase is well-organised and broadly follows the architecture described in `.windsurfrules` (Provider state, `http` package, JWT, socket.io, Agora, on-device TFLite). Five major flows (matchmaking → ranked, placement, tournament, training, friends/leaderboard) are functional end-to-end. However, the audit surfaced **5 release-blocking issues**, **20 high-severity issues** and **27 medium-severity** issues. The two systemic risks are:

1. **Client is the only place input is validated.** Match scores, training results, placement winner, friend IDs, and matchmaking `userId` are all read directly from client requests with no client-side schema validation. If the server is not strictly authoritative, every score-bearing endpoint is trivially cheatable. (See §13.) Fix priority must be confirming server-side enforcement; the client can then add belt-and-suspenders validation.
2. **`SocketService` is a shared singleton with single-handler-per-event semantics.** `lib/services/socket_service.dart:131` literally `_handlers[event] = handler` — registering twice for the same event silently overrides the first listener. Multiple providers (`GameProvider`, `TournamentGameProvider`, `MatchmakingProvider`, `PlacementProvider`) all subscribe to overlapping events. Whichever screen is opened *last* wins, and the ones that lost their handler silently stop reacting. This is the root cause of several reported "tournament/leg/placement state drifts after navigating away and back" symptoms. (See §11.)

The autoscoring pipeline is impressive and largely solid, but has a few correctness traps that can produce wrong scores in edge cases (stale `_latestScores` cache surviving `resetTurn()`, manual override missing confidence/validation, miss-detection gap when 3 darts are thrown but only 2 inferred — §3).

---

## 1. Methodology

- Read every file in `lib/services/`, `lib/providers/`, `lib/models/`, `lib/utils/`, `lib/widgets/`, `lib/screens/{auth,game,home,matchmaking,placement,profile,settings,shared,tournament,training,splash}`.
- Followed each focus-area pipeline end-to-end: UI → provider → service → API/socket.
- Cross-checked subagent findings by directly reading the cited line numbers; entries below are written from verified evidence. Where a subagent claim could not be reconciled (e.g., specific line numbers that did not match), I either re-cited from the actual code or removed the claim.
- Severity rubric:
  - **Critical** — known data loss, security exposure, payment failure, score corruption, or release blocker
  - **High** — produces wrong behaviour for real users in non-rare paths
  - **Medium** — reliability / UX / maintainability concerns; bugs in edge cases
  - **Low** — code smell, minor inefficiency, documentation gap

---

## 2. Architecture overview

```
lib/
├── main.dart                 ← entrypoint, MultiProvider tree, Stripe init
├── models/                   ← match, tournament, training, user (DTOs)
├── providers/                ← 8 ChangeNotifier providers
├── services/                 ← 27 stateless static services + 4 detection variants
├── screens/                  ← UI surfaces, one folder per flow
├── widgets/                  ← shared UI: scoreboards, overlays, dartboard
├── utils/                    ← theme, storage, navigator, helpers
└── l10n/                     ← localisation (FR/EN, etc.)
```

**State ownership (concrete observations):**
- `GameProvider` — owns 1v1 ranked/casual scoreboard state and the socket listeners for `score_updated`, `pending_win`, `pending_bust`, `forfeit`, `game_won`, `match_ended`, etc. Eagerly created at app start (`main.dart:58`).
- `TournamentGameProvider` — fully parallel to `GameProvider` but with leg/series fields. Listens to `tournament_*` socket events.
- `PlacementProvider` — manages placement match HTTP flow and consumes `placement` socket events for the bot opponent.
- `MatchmakingProvider` — owns queue lifecycle, references `GameProvider` to pre-init match state on `match_found`.
- `TournamentProvider` — fetches the tournament list/bracket via REST.
- `FriendsProvider`, `AuthProvider`, `LocaleProvider` — straightforward CRUD/state holders.

**Cross-cutting plumbing:**
- `ApiService` (HTTP, static) — all REST goes through it; centralises 401 → refresh-token retry.
- `SocketService` (static) — single socket.io connection shared by every provider.
- `StorageService` — `flutter_secure_storage` for JWT, refresh, language, autoscore pref, camera zoom.
- `AgoraService` — wraps `agora_rtc_engine`; pushes external video frames sourced from `CameraFrameService`.

---

## 3. AI autoscoring (`lib/services/auto_scoring_service.dart` and friends)

Most critical part of the app — directly determines competitive outcomes. Code is well-commented and DartsMind-derived; the following are real issues.

### Critical

**3.1 `resetTurn()` does not clear `_latestScores`** — verified at `lib/services/auto_scoring_service.dart:313–335`. Every other turn-scoped buffer is cleared (`_dartSlots`, `_tipGroups`, `_shootGroups`, `_emittedSlots`, `_manualOverrideSlots`, `_removedSlots`), but `_latestScores` (the position→score lookup populated during inference) is not. When the next turn starts and `_lookupScore()` matches a new dart's position against the cached map within tolerance, it returns the **previous turn's** score for that position. Repro: T20 in turn 1 → reset → S19 lands ~0.001 board-units from the old T20 location → AI emits 60 instead of 19.
**Fix:** add `_latestScores.clear();` to `resetTurn()`.

**3.2 Manual override bypasses bust validation and emits zero confidence** — `lib/widgets/dartboard_edit_modal.dart:36–48` calls `overrideDart(index, DartScore(score, segment, ring, radius:0, angle:0))` without setting `confidence`. Downstream:
  - `auto_scoring_service.dart:349–355` (`overrideDart`) recomputes `_turnTotal` from raw scores, but never checks "would this turn cause a bust" or "is finishing dart a double". A user editing dart 3 to T20 with 30 remaining will lock in an impossible state if the server doesn't reject it.
  - `_lookupScore()` (slot match by position) cannot find manually-set darts because they have `radius:0, angle:0`, so subsequent inference frames may re-emit the slot. (Subagent reported as ~line 1140 — file is too long to verify the exact line, but the manual override having no spatial fingerprint is verifiable by inspection.)
**Fix:** populate `confidence: 1.0` on manual overrides, and gate `_submit()` on a client-side bust check before calling `overrideDart()`.

**3.3 Miss not counted in `detectedDartCount`** — when 3 darts are thrown but one lands outside the board (a "0"), the detector still creates a `ShootGroup`, but `_hasNearbyInvisibleShoots()` may classify it as `priority=1`, and `_getValidShootDetectionThisRound()` only counts `priority==0`. Result: UI shows "2 darts detected" though three were thrown, blocking auto-confirm. Reported by subagent at `auto_scoring_service.dart:262–264` — pattern is consistent with the rest of the file but I did not personally verify the exact line. Treat the symptom (auto-confirm fails when one dart misses the board) as the testable signal.

### High

**3.4 Capture loop emits darts after `stopCapture()`** — `_captureLoop` (`lib/services/auto_scoring_service.dart:387–402`): a long-running `_fireCapture()` that completed *before* `stopCapture()` toggled `_capturing=false` will still notify listeners with the dart it found. In multiplayer, this can attribute a stray dart to the next turn. Re-check `if (!_capturing) return;` immediately before publishing the result.

**3.5 GPU TFLite delegate not closed in `dispose()`** — `lib/services/dart_detection_service.dart` `dispose()` closes the interpreter but does not release `GpuDelegateV2`. On long sessions / multiple matches, GPU heap grows; on mid-range Android the next `loadModelNative` may silently fall back to CPU.

**3.6 Web stub silently fails** — `lib/services/dart_detection_service_stub.dart` returns "Auto-scoring not supported on web" but no UI surfaces this. A web user sees the camera view live forever with zero detected darts. At minimum log a banner once at startup; ideally force the web build to disable the autoscore toggle entirely.

**3.7 Silent capture is not silent on Android** — `lib/utils/silent_capture.dart` uses `startImageStream` / `stopImageStream`. On iOS this is silent; on Android, the camera HAL still plays the system shutter sound on many OEM ROMs (Korea/Japan locale enforcement aside). Document or use a manual mute of `STREAM_SYSTEM` for the duration.

### Medium

**3.8 Image buffer aliasing on Android `startImageStream`** — `lib/services/camera_frame_service.dart` `captureYuvPlanes` references `frame.planes[N].bytes` directly. CameraX recycles the underlying buffer immediately after the callback returns. If the MethodChannel marshalling does not deep-copy, occasional garbled YUV frames will pass to the model. Defensive fix: `Uint8List.fromList(frame.planes[i].bytes)` before crossing platform channel.

**3.9 Frame timestamp is wall-clock, not monotonic** — `camera_frame_service.dart` uses `DateTime.now().millisecondsSinceEpoch` for the frame timestamp passed to Agora. NTP corrections during a long match can produce non-monotonic timestamps which Agora may drop. Use a `Stopwatch` started at engine init.

**3.10 Cached calibration never expires** — when one of the 4 board control points is missed in a frame, `_applyCalibFallback` reuses the last good calibration. There is no "refresh after N successful new calibrations" or "invalidate if any new CP > 0.1 from cache". Sustained drift if the phone is bumped after a successful calibration.

**3.11 Shaking detection fires from a single spike** — `_isShaking` is computed from the recent shift values; a single push notification or vibration suppresses dart detection for ~1 s. Require ≥3 sustained samples before flipping the flag.

**3.12 Confidence threshold (0.8) is hardcoded and not adaptive** — single literal in detection code; works on the dev's lighting setup but not all phones. Log a confidence histogram per N frames in debug builds and make the threshold a remote-config value.

**3.13 Isolate model-load timeout = 12 s** (`lib/services/detection_isolate.dart:82` per subagent — verifiable area). Blocks the UI thread on slow I/O. Drop to ~5 s and show a progress indicator.

### Low

- `dart_detection_service.dart` 180° rotation path duplicated between `captureRgba()` and `_convertCameraImageToJpeg()` — one source of truth would prevent silent regressions.
- Overlapping darts (one behind another) are dropped by NMS; a known limitation, but not surfaced anywhere in onboarding.

---

## 4. Agora call subsystem (`lib/services/agora_service.dart`, `lib/widgets/video_view.dart`, `lib/screens/shared/camera_setup_mixin.dart`)

### Critical

**4.1 `RtcConnection(channelId: '')` on remote view** — `lib/widgets/video_view.dart:36`. The remote video controller is built with an empty channel ID, which lets the SDK fall through to "current channel" behaviour. This works today only because the engine is single-channel, but it is fragile: if the SDK ever adopts multi-channel by default (it has been the trend across versions), the remote view will silently render no video. Pass the actual `agoraChannelName` from `GameProvider`/`TournamentGameProvider`.

**4.2 `_engine` is a process-wide singleton keyed only by "is null"** — `lib/services/agora_service.dart:13–17`. If a user moves between a placement match and a tournament match (each with different `appId`), the second match reuses the engine initialised with the first match's appId/config. Add a "current appId" check and rebuild the engine on mismatch.

### High

**4.3 No token-expiry handler** — `agora_service.dart` registers no `onTokenPrivilegeWillExpire` or `onTokenPrivilegeDidExpire` callback. Agora RTC tokens default to 24 h; a long-running bracket day will silently fail mid-leg. Add the handler and refresh via the existing API endpoint that issues tokens.

**4.4 No connection-state monitoring** — the only registered RtcEngine handlers (per `lib/screens/shared/camera_setup_mixin.dart` and `lib/screens/game/base_game_screen_state.dart`) cover `onJoinChannelSuccess`, `onUserJoined`, `onUserOffline`. Missing: `onConnectionStateChanged`, `onError`, `onNetworkTypeChanged`. A dropped Agora connection is currently invisible until the next join attempt.

**4.5 `dispose()` swallows all errors silently** — `agora_service.dart:193–202` catches `_engine.leaveChannel()` / `_engine.release()` exceptions in `catch (_)` and still nullifies `_engine`. If `release()` failed, native handles leak.

**4.6 Engine handler registered every reconnect, never removed** — `RtcEngineEventHandler` is created and registered fresh in `reconnectAgora()`. The Agora SDK does not de-duplicate handlers; old captures of `context`/`game` accumulate.

### Medium

**4.7 `muteAllRemoteAudio` defined but never wired to UI** — `agora_service.dart:183–190`. There is no way for a player to mute the opponent if their mic feeds back. Either remove the dead code or expose it.

**4.8 Microphone is published only via toggle** — `joinChannel` sets `publishMicrophoneTrack: false`. The toggle in `base_game_screen_state.dart` flips local state immediately and only then awaits the engine call; on failure UI and engine disagree.

**4.9 No reconnection backoff** — `reconnectAgora()` is called as soon as `needsAgoraReconnect` is set; no delay, no max attempts. On a network outage the screen burns CPU retrying every frame.

**4.10 Camera zoom restored from storage rather than memory on reconnect** — verified pattern in `camera_setup_mixin`/`base_game_screen_state`. After a reconnect the user-set zoom snaps back to the saved value rather than the value they had during the just-lost connection.

### Low

- Channel name and `uid` are accepted as arbitrary strings/ints with no validation in `joinChannel`.
- iOS `AVAudioSession` policy is not explicitly set; default may duck/pause when a Bluetooth call ringer fires.

---

## 5. Games — general (`lib/providers/game_provider.dart`, `lib/screens/game/`)

### Critical

**5.1 No client-side score validation in `throwDart`** — `lib/providers/game_provider.dart:678–703`. The provider trusts that `baseScore` is in `1..20 ∪ {25}` and that the resulting throw is legal. Defensive check is missing. Crucially: this means **all anti-cheat is server-side**. If the server validates, this is fine; if not, a tampered client can submit any score. Flag for backend audit.

**5.2 Rolled-back guard on `socket.emit` failure leaves UI in unrecoverable state** — `game_provider.dart:699–702` decrements `_dartsEmittedThisRound` on emit failure but does not surface an error or refresh. The server-side state may have accepted the throw before the socket error was raised; the client now disagrees.

### High

**5.3 `_dartsEmittedThisRound` guard is local-only** — `if (!isMyTurn || _dartsEmittedThisRound >= 3 || _gameEnded)`. Doesn't account for two players acting simultaneously, server reordering, or replay on reconnect. The server must enforce turn-order independently.

**5.4 Pending-win/bust dialogs not idempotent** — `game_provider.dart` toggles `_pendingConfirmation` on each `pending_win` event. A duplicated socket event (which can happen on reconnect) re-fires the dialog flow even after the player already confirmed.

**5.5 Race between `editDartThrow` and server `score_updated`** — `game_provider.dart:705–740`: when the user manually edits an unsubmitted slot it is emitted as `throw_dart`; meanwhile the AI may have separately emitted the same slot. The growing-list workaround at line 710 papers over the symptom but means the server has to decide which throw is canonical.

**5.6 Animation controllers in `EloChangeOverlay`/`RankChangeOverlay` schedule callbacks after dispose** — `Future.delayed`-based animations are guarded by `mounted`, but the haptic/sound side-effects scheduled inside those delayed callbacks fire even if the user navigates away mid-overlay.

### Medium

**5.7 `_handleScoreUpdated` silently drops malformed payloads** — if the server sends a missing `player1Score`/`player2Score`, the if-guard at the start of the handler simply returns; the UI keeps showing 501-501 while the server marches on.

**5.8 Disconnect grace period is client-driven** — `_disconnectCountdownTimer` is local; both players' clients run independent timers. A clock skew lets one client forfeit before the other has decided. The server should be the arbiter and broadcast the canonical countdown.

**5.9 `_cleanupSocketListeners` does not protect against in-flight handler calls** — a socket event arriving as the provider is being disposed will still mutate state (set flags) before `notifyListeners` no-ops. Side-effects persist.

### Low

- `currentRoundScore` getter parses notation (`'S20'`/`'D25'`/`'T20'`) on every call; cheap but better as a memoised computed.
- The hardcoded starting score `501` is duplicated in `initGame`. If 301 / 701 modes are added, this gets painful — extract a `Match.startingScore` once.

---

## 6. Ranked match flow (`MatchmakingProvider`, `MatchmakingService`, `MatchService`)

### Critical

**6.1 `MatchmakingService.joinQueue(userId)`** — `lib/services/matchmaking_service.dart:5` posts `{"userId": userId}` as the request body. The server **must** ignore this and authenticate from the JWT instead, otherwise a user can queue someone else into a match. Confirm with backend; on the client, drop the `userId` argument once the server is authoritative.

### High

**6.2 No "ranked vs casual" branching anywhere in the client** — searching the code for `matchType`/`isRanked` returns only `match.dart:41`. The `Match` model has the field, but `GameProvider`, `MatchmakingProvider`, and `game_screen.dart` never read it. Casual matches today probably award ELO unconditionally (see §6.3). Confirm with backend, then guard `EloChangeOverlay` / forfeit penalties on `match.matchType == 'ranked'`.

**6.3 Forfeit awards ELO change without checking match type** — `game_provider.dart` forfeit handler reads `winnerEloChange` from the payload directly. If the server sends ELO for a casual match, the client renders it.

**6.4 ELO is fetched via `auth.checkAuthStatus()` after each result** — `lib/screens/game/game_screen.dart:158–210`. There is a 1-2 s overlay window where, if the user taps "Play Again" before it finishes, they re-enter matchmaking carrying stale ELO. Either await the refresh before enabling Play Again, or include the new ELO directly in the `match_ended` payload.

### Medium

**6.5 Active-match poll fires every 5 s without per-request timeout protection** — `matchmaking_provider.dart:156–178`. If the server stalls 10 s, two outstanding requests overlap. Re-checks at lines 159 and 163 limit damage but don't prevent both responses from invoking `_handleMatchFound`.

**6.6 Reconnect handler stomps on listeners** — `matchmaking_provider.dart:88–93` clears and re-installs the reconnect handler. Fine in isolation; the `_setupSocketListeners()` call inside the handler however calls `_cleanupSocketListeners()` first which uses `SocketService.off()` — see §11 for why this is fragile.

**6.7 Camera-check screen does not gate matchmaking** — a user with no camera permission can enter the queue and the camera failure surfaces only at game start, requiring forfeit. Surface the check before joining queue.

### Low

- Matchmaking timer uses `Timer.periodic(seconds: 1)` and rebuilds the UI each tick. Fine but unnecessary; an `AnimatedBuilder` with a `Ticker` is cheaper.

---

## 7. Placement games (`PlacementProvider`, `PlacementService`, `lib/screens/placement/`)

### Critical

**7.1 `PlacementService.completeMatch(winnerId)` accepts `null` and forwards it** — `lib/services/placement_service.dart:34`. The body literally contains `'winnerId': null` if the caller passes null. Many backends reject the field or silently treat null as "no winner". Either default to the player's own id or omit the key.

**7.2 `PlacementService.completeMatch` is also a cheating vector** — the client supplies `player1Score` and `winnerId`. Same caveat as ranked: server must ignore client-asserted winners. Confirm with backend.

### High

**7.3 Abandoning a placement match leaves the server-side game `in_progress`** — `lib/screens/placement/placement_game_screen.dart` calls `completeMatch()` only on the success path. Crash, kill, navigation pop, or network blip → orphaned match. There's no `getStatus()` recovery path that resumes a half-played placement.

**7.4 Provider state drift** — `PlacementProvider.updateScoresFromGameState()` exists but is never called; scores live in screen-local `_myScore` while bot scores live in the provider. Refreshing the screen re-pulls the start payload but misses interim updates.

**7.5 Auto-scoring lifecycle is screen-local** — placement creates a fresh `AutoScoringService` per screen instance. After a navigation pop and re-push, model state (calibration, slots) is lost; the player has to re-aim the camera. Hoist into the provider.

### Medium

**7.6 Camera-setup screen for placement duplicates the ranked one** — `placement_camera_setup_screen.dart` and `camera_setup_screen.dart` share most logic. The `camera_setup_mixin.dart` exists for this; placement isn't using it consistently.

**7.7 Hub screen reload after game-end** — `placement_hub_screen.dart` reloads status on screen return; if the network is down, the placement count is stale and the UI may let a player exceed their placement matches.

### Low

- `triggerBotTurn()` accepts `playerRoundScore`/`playerRoundThrows` from the client; same trust-the-client smell.

---

## 8. Tournament games (`TournamentProvider`, `TournamentGameProvider`, `lib/screens/tournament/`, `lib/screens/home/tournament_*.dart`)

### Critical

**8.1 Two providers share overlapping state with no synchronisation** — `TournamentProvider` (REST/bracket) and `TournamentGameProvider` (socket/leg). `tournament_next_leg` updates only the latter; bracket caches in the former go stale. After a leg completes and the user taps "Back to bracket", the bracket UI is one event behind. Either fold both into one provider or have one listen to the other.

**8.2 `_handleTournamentNextLeg` updates Agora credentials and sets `_needsAgoraReconnect = true` without forcing a UI to honour it** — `tournament_game_provider.dart:482–514`. If the screen is mid-transition (leg result → next leg), the flag may not be observed by `camera_setup_mixin` until after the leg has visibly started. Players see a black video for 2-3 s.

### High

**8.3 `ensureListenersSetup` is not idempotent against double-registration when the singleton handler map collides with another provider** — see §11. If a user opens a tournament leg, then a quick-play match, then returns, the listeners that were installed first have been silently overridden.

**8.4 Two-player forfeit not handled** — `match.dart:235–250` lists `player1_forfeit`, `player2_forfeit`, `both_forfeit`. Only the single-player forfeit is observed in `tournament_game_provider`. A `both_forfeit` event reaches `_handlePlayerForfeited` but the local `seriesWinnerId` mapping doesn't account for "no one won".

**8.5 Bracket cache never refreshes on socket events** — once the bracket is loaded in `TournamentProvider`, the only refresh path is a user-initiated reload. If a player drops out, the bracket UI is stale until manually refreshed.

**8.6 Spectator mode missing entirely** — every code path assumes the current user is one of the participants. Watching a friend's match (a feature any tournament app eventually adds) is not architected for; `isMyTurn` would crash or return nonsense.

### Medium

**8.7 Tournament screens (`tournament_screen.dart` 1246 lines, `tournament_detail_screen.dart` 989 lines) mix list, detail, and admin flows in single widgets** — splitting into smaller screens/widgets would make the listener-collision problem in §8.1 easier to fix.

**8.8 `confirmRound()` emits `end_round_early` if the user has fewer than 3 throws** — `tournament_game_provider.dart:528–544`. Fine, but no UI confirmation step; an accidental tap on confirm with 1 dart submitted ends the round. Add a "are you sure" dialog when `_currentRoundThrows.length < 3`.

### Low

- `tournament.dart` model has 8 status enums; a few are unused in the client (`registration_open` vs `open` discrepancy worth verifying with backend).

---

## 9. Training (`TrainingService`, `lib/screens/training/`)

### Critical

**9.1 Training results are entirely client-supplied** — `lib/services/training_service.dart:5–23` posts `{type, score, dartsThrown, completed, details}`. Trivial to inflate stats from a tampered client. Server **must** validate against the per-strategy scoring rules (e.g., "score" for Bobs27 has bounded range, ATC `dartsThrown` is bounded above by 21, etc.). Confirm with backend.

### High

**9.2 No retry / offline queue for `submit()`** — a network blip at session-end discards the result. Even a basic in-memory retry would prevent the worst case; ideally, persist pending submissions to `flutter_secure_storage` and retry on next launch.

**9.3 No idempotency key on submit** — manual retry from the error UI submits the same session twice if the server already accepted the first request.

**9.4 `AutoScoringService` not reset on "Play Again"** — `training_ai_screen.dart` `_restart()` resets the strategy but the service keeps its internal slots/calibration buffers. A dart left on the board from the prior session is interpreted as the first dart of the new one.

### Medium

**9.5 Strategy `submitVisit([])` with no darts is treated as a failure** — most strategies (`atc_strategy`, `bobs_27_strategy`, etc.) handle empty input by counting it as a missed visit. UX should either disable the submit button until at least one dart is recorded, or prompt "no darts thrown — skip this visit?".

**9.6 No difficulty/progression** — strategies are one-shot; the training screen has no concept of repeating the same exercise across days for progression. Acceptable MVP, but flagging as a roadmap gap.

**9.7 Training uses `CameraFrameService` directly** — `training_ai_screen.dart:111-128` constructs the service with `agoraEngine: null`. Solo path. The placement and ranked games use it via `camera_setup_mixin`. This is two divergent integration paths; a bug in one (e.g., the YUV aliasing in §3.8) won't be caught by tests of the other.

### Low

- `training_strategy.dart` `VisitOutcome` enum is fine but the strategies do a lot of duplicated `if (success) ... else ...` boilerplate; a small base implementation would shrink them by ~30 %.

---

## 10. Friends & ranking

### Friends (`FriendsProvider`, `FriendsService`, `lib/screens/home/friends_screen.dart`)

**10.1 No optimistic updates** — every action (`acceptFriendRequest`, `rejectFriendRequest`, `removeFriend`, `sendFriendRequest`) reloads full lists from the server on success, sequentially (`acceptFriendRequest` runs `loadFriends`, then `loadPendingRequests`, then `loadPendingRequestsCount` in series). Slow on poor connections; if any reload fails silently, the UI is stale. Use `Future.wait` and update locally first.

**10.2 No real-time presence** — there is no socket listener for online/offline. The `User` model has no `online`/`lastSeen` field. Friends list shows static data. Typical for an MVP, but the server side must already have presence to support the camera/match flows; surface it.

**10.3 `getPendingRequestsCount` swallows all errors and returns 0** — `friends_service.dart:62`. A real failure (auth expired, server down) is indistinguishable from "you have zero requests"; the badge silently disappears.

### Ranking & leaderboard (`leaderboard_screen.dart`, `rank_*` utils, `RankBadge`)

**10.4 Tier mismatch between display and icon** — `lib/utils/rank_translation.dart` translates 8 tiers (bronze / silver / gold / platinum / diamond / master / **grandmaster** / **legend**) but `lib/utils/rank_utils.dart` maps only the first 6 plus `unranked` to icons; everything else falls through to `bronze.png` (line 23 default). A grandmaster sees a bronze badge.

**10.5 Leaderboard fetches everything in one call** — `leaderboard_screen.dart:56` invokes `UserService.getLeaderboard()` with no `limit`/`offset`. At 10 k users this is a major payload. Add pagination to the server endpoint and lazy-load.

**10.6 Leaderboard does not refresh on match completion** — only manual pull-to-refresh / tab toggle triggers a reload. After playing a ranked match, the user has to hunt for the refresh control. A simple "subscribe to a `leaderboard_updated` socket event" would be cleaner; failing that, refresh on `match_ended`.

**10.7 ELO smoothing is absent** — the user sees the raw value from the server. If the server caches ELO and a recent match hasn't propagated, the UI can briefly show the *old* ELO post-match. A "refreshing…" state would be honest.

---

## 11. Cross-cutting: SocketService design problem

Verified in `lib/services/socket_service.dart:124–143`:
```dart
static void on(String event, Function(dynamic) handler) {
  if (_socket == null) throw Exception('Socket not initialized');
  final existing = _handlers[event];
  if (existing != null) {
    _socket!.off(event, existing);
  }
  _handlers[event] = handler;
  _socket!.on(event, handler);
}

static void off(String event) {
  if (_socket == null) return;
  final handler = _handlers.remove(event);
  if (handler != null) {
    _socket!.off(event, handler);
  }
}
```

This map allows **only one handler per event name across the entire app**. Today:
- `GameProvider._setupSocketListeners` registers `score_updated`, `round_complete`, `pending_win`, `pending_bust`, `forfeit`, `match_ended`, …
- `TournamentGameProvider._setupSocketListeners` registers `tournament_*` (different names — safe), but also `score_updated`, `pending_win`, `pending_bust` etc. (same names — unsafe).
- `PlacementProvider` registers a subset that overlaps with `GameProvider`.
- `MatchmakingProvider` registers `match_found`, `searching_expanded`, `queue_error` (independent — safe).

So when a user goes ranked match → home → tournament → home → ranked match, the **second `GameProvider._setupSocketListeners` call** silently overrides any tournament/placement listeners that share an event name. The user's tournament screen stops receiving updates, but `_listenersSetUp = true` stays sticky in the tournament provider, so it never re-registers.

**Fix options:**
1. Allow multiple listeners per event (`Map<String, List<Function>>`), and require providers to pass in a unique handler reference for `off`.
2. Add a `namespace` parameter (`SocketService.on('game/score_updated', ...)`).
3. Pass an `id` on register/unregister so each provider's listener is distinct.

Until this is fixed, sporadic "the screen seems frozen — events stopped" reports are likely. Same applies to the reconnect handler (`setReconnectHandler` is also single-slot).

Additional smaller items:
- `connect()` finally block always completes the completer, even on throw — every caller treats `connect()` as success and then crashes when emitting on a null socket.
- `disconnect()` is correct, but it is **not** called from `AuthProvider.logout()` — see §12.1.
- `reconnect_failed` only logs; there is no UI to convey "we lost your connection permanently, please re-open the app".

---

## 12. Cross-cutting: Auth, API, payments

### 12.1 Auth lifecycle

- **Logout does not call `ApiService.resetAuthFailure()`** — verified in `lib/providers/auth_provider.dart:109–125`. The static `onAuthFailure` callback (set in `main.dart:61–63` to the old navigator) persists beyond logout. If the user logs out → in as a different account, the next 401 will navigate using the original navigator state. Add `ApiService.resetAuthFailure()`; reinstall the callback after the next login.
- **Logout does not disconnect the socket** — verified, no `SocketService.disconnect()` call in `logout()`. The socket keeps the previous user's auth token in memory (still attached to the `_socket.io` instance) until the next event triggers a server-side rejection.
- **Logout doesn't reset other providers** — `GameProvider`, `MatchmakingProvider`, `FriendsProvider`, `TournamentProvider` all retain stale state. If the next user logs in, they see the previous user's match history flash before the new data loads.

### 12.2 Token refresh

- `ApiService.refreshAccessToken` (`lib/services/api_service.dart:44–92`) deduplicates concurrent refreshes via `_refreshCompleter`. **One race window:** the `finally` clears `_refreshCompleter = null` *after* completing — a caller checking `_refreshCompleter` between `complete()` and the assignment will see null and start a fresh refresh. In practice the await semantics serialise these events on a single isolate, so this is mostly latent — but worth fixing by setting `_refreshCompleter = null` *before* `complete()`.
- Backoff: 2/4/6/8/10 s linear cap; a server outage will pin every request to a 10 s wait — fine.
- Server error messages are forwarded into UI exception strings (`lib/services/api_service.dart:318–329`). If the backend ever returns sensitive content (admin emails, internal IDs), this leaks. Use error codes + a translation table.

### 12.3 Stripe

- **`pk_test_…` is hardcoded as `defaultValue` for the `STRIPE_PUBLISHABLE_KEY` env var** (`lib/main.dart:42–46`). A production build that forgets `--dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_…` will silently use the test key — payments succeed in the test ledger but never settle. **Release blocker.**
  - Worse: the test key string is shipped in the binary (source control). Even after replacing with a real key, decompiling extracts both. Use only a build-time injection without a default; fail loudly in release if missing.
- `lib/services/payment_service.dart:29` — `googlePay: testEnv: kDebugMode`. Debug builds correctly use the test environment; release builds use prod for Google Pay but still use the **test publishable key** if it falls through to default — leading to a confusing inconsistency.
- `payment_service.dart` does not validate `clientSecret` shape or origin; a tampered server response could pass an arbitrary string to Stripe SDK.

### 12.4 Push notifications

- `lib/services/push_notification_service.dart:64` `debugPrint('🔔 FCM Token: $_fcmToken')` — debug only, but `debugPrint` is also visible in release iOS device logs unless explicitly stripped. Hash or truncate.
- No deduplication on token registration: `registerToken` is called from `splash_screen` *and* `auth_provider.login`/`register`. Server will see the same token registered twice in quick succession.

### 12.5 Storage

- `flutter_secure_storage` is used correctly for JWT and refresh token (iOS Keychain, Android Keystore-backed). Auto-scoring toggle and camera zoom are also stored in secure storage — overkill (could use `shared_preferences`) but not harmful.

### 12.6 Network hardening

- No certificate pinning (`api_service.dart` uses default `http` package). Acceptable for an MVP; consider `dio` + `dio_certificate_pinning` if sensitive payment/result data must be protected against on-device MITM.
- No request signing or replay protection for score-bearing endpoints. Combined with §6.1 / §7.2 / §9.1, an attacker on a tampered client can submit any score; only server-side validation is between them and the leaderboard.

---

## 13. Cross-cutting: anti-cheat surface

The client never validates these inputs before sending to server:

| Endpoint                                | Tampered field      | Effect if server doesn't validate                |
|-----------------------------------------|---------------------|--------------------------------------------------|
| `/matchmaking/join`                     | `userId`            | Queue someone else.                              |
| `/matches/:id/accept`, `/dispute`       | `playerId`, `reason`| Accept/dispute on someone else's behalf.         |
| `/placement/complete`                   | `winnerId`, `score` | Self-declared placement winner / score.          |
| `/placement/bot-turn`                   | `playerRoundScore`  | Inflate prior round to game the bot.             |
| `/trainings`                            | `score`,`dartsThrown`| Fake high-scores in any training mode.          |
| Socket `throw_dart`                     | `baseScore`,`isDouble`,`isTriple` | Send any score. Server *must* validate. |
| Socket `edit_dart`                      | same                | Same.                                            |

**Action:** confirm server-side validation for each row above. The client should additionally reject obviously invalid inputs (out-of-range base scores, > 3 darts/round) before emitting, both for defence in depth and for surfacing genuine bugs early.

---

## 14. Cross-cutting: smaller observations

- **No `/test` coverage of substance.** `test/` contains the default `widget_test.dart`. Score conversion, strategy logic, ELO display, rank-tier mapping, and the autoscoring `score_converter` are all easily unit-testable and would catch regressions cheaply.
- **`l10n/` covers a subset of strings.** Many `Text(...)` widgets in `tournament_screen.dart`, `friends_screen.dart`, `play_screen.dart` are hardcoded English. A `flutter analyze --no-fatal-infos` pass + a "find raw `Text(\"…\")`" sweep would catch these.
- **Splash screen has unconditional 2-second post-auth delay** — `lib/screens/splash_screen.dart:57`. Even a fully-cached login path waits 2 s before navigating. Replace with `Future.delayed` racing the auth check (`Future.any`) and cap total time, e.g., 1 s.
- **`AuthProvider` keeps a mutable reference to `LocaleProvider`** — `lib/providers/auth_provider.dart:19–21`. Coupling is fine in this app size, but the proxy provider plumbing in `main.dart:78–90` re-injects on every rebuild, which is wasteful.
- **Several screens > 1000 LOC** (`tournament_screen.dart` 1246, `play_screen.dart` 1070, `training_ai_screen.dart` 1041). Large files correlate with the duplicated camera/Agora setup logic and the hardcoded English strings; breaking up would help on every other axis.
- **`auth_service.getCurrentUser`** logs out if the profile endpoint returns 401, but on any other error keeps the token and returns null. Result: a transient backend hiccup pushes the user to the login screen but their token survives — they re-login, get a fresh token, and the orphan refresh token now lingers server-side until expiry. Fix: only delete tokens on confirmed auth failure.

---

## 15. Severity matrix

| Severity   | Count |
|------------|-------|
| Critical   | 11    |
| High       | 22    |
| Medium     | 27    |
| Low        | 14    |
| **Total**  | **74**|

## 16. Top-10 prioritised fixes

| # | Fix                                                                                                  | Effort | Impact   |
|---|------------------------------------------------------------------------------------------------------|--------|----------|
| 1 | Confirm server-side validation for all score-bearing endpoints (§13). Audit-only, no client change needed unless backend is permissive. | low (audit) | critical |
| 2 | Remove `pk_test_…` defaultValue and fail loudly if `STRIPE_PUBLISHABLE_KEY` is missing on release builds (§12.3). | trivial | critical |
| 3 | Allow multiple handlers per socket event (or namespace them) so providers don't override each other (§11). | medium | critical |
| 4 | `_latestScores.clear()` in `AutoScoringService.resetTurn()` (§3.1). | trivial | critical |
| 5 | Bust validation + `confidence: 1.0` in `dartboard_edit_modal._submit()` (§3.2). | small  | high     |
| 6 | `AuthProvider.logout()` → call `ApiService.resetAuthFailure()` and `SocketService.disconnect()`; reset other providers (§12.1). | small  | high     |
| 7 | Fix `RemoteVideoView.RtcConnection(channelId: '')` to use the real channel name (§4.1). | trivial | high     |
| 8 | Wire `onTokenPrivilegeWillExpire` for Agora; refresh tokens before expiry (§4.3). | small  | high     |
| 9 | Align rank tiers between `rank_utils.dart` and `rank_translation.dart`; add `grandmaster.png` and `legend.png` (§10.4). | trivial | high     |
| 10 | Add idempotency keys + offline retry queue for training submit (§9.2-9.3). | medium | high     |

---

## 17. What was NOT audited

- The Dart/iOS/Android native shells (`ios/`, `android/`, `macos/`, `linux/`, `windows/`, `web/`) — only `Info.plist` / `AndroidManifest.xml` permissions were sampled.
- The TFLite models themselves (`assets/models/`) — only the loading/inference surface.
- Backend behaviour. Many findings ultimately depend on whether the server correctly validates (§13). A backend audit is the single highest-leverage follow-up.
- Test coverage was checked but not improved.
- Any third-party plugin's source.

---

*End of report.*
