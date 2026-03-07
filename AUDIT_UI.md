# UI/UX Audit — Dart Rivals Mobile

---

## GAME SCREEN (core feature)

### Critical

**1. 5-second artificial loading delay**
`base_game_screen_state.dart:71` — `await Future.delayed(const Duration(seconds: 5))` blocks init before the camera and AI model load. Users stare at a static screen for at least 5 seconds before anything happens.
- Remove the fixed delay. Start Agora and model loading immediately, and show per-step progress: "Joining match…", "Starting camera…", "Loading AI…"

**2. Dart slot tap targets too small**
`base_game_screen_state.dart:575` — The three dart edit slots are 36×36px. The minimum recommended tap target is 44×44dp. Users frequently miss when trying to select a slot to edit.
- Increase to 44×44px minimum.

**3. MISS button tap target too short**
`base_game_screen_state.dart:598` — The MISS button is 44×36px (height is 36). Same issue as above.
- Increase height to 44px.
---

### Major

**5. "END ROUND EARLY (0/3)" button label is verbose and confusing**
`base_game_screen_state.dart:678` — When no darts have been thrown the label reads "END ROUND EARLY (0/3)", which makes no sense as a CTA. The button is also greyed but still tappable.
- 0 darts thrown: button disabled, label "CONFIRM ROUND (0/3)"
- 1–2 darts: "END ROUND EARLY (1/3)" or "(2/3)" — keep as-is, wording is fine here
- 3 darts: "CONFIRM ROUND" with a filled check icon

**6. Static loading screen with no progress feedback**
`base_game_screen_state.dart:395-412` — The loading screen shows "Setting up camera & AI scoring…" as a fixed subtitle. During the 5+ second wait users have no idea what step is being performed or whether something is stuck.
- Replace with a step-by-step indicator: "Connecting… / Starting camera… / Loading AI model… / Ready"

**7. Score overlay at top conflicts with dartboard layout**
`base_game_screen_state.dart:729-730` and `game_screen.dart:483` — During my turn, `buildMyTurnOverlay` / the score panel is `Positioned(top: 8)` floating over the body content. On smaller screens this overlay covers the top of the dartboard.
- Integrate the score row directly into the layout flow (before the dartboard, not overlaid on it) to avoid overlap.

**8. Editing mode red banner is too intrusive**
`base_game_screen_state.dart:761-774` — When editing a dart, a full-width red `Material(elevation: 100)` banner slides over the top of the screen, covering the score overlay. This is jarring and hides important context.
- Replace with an inline edit indicator below the dart slots, or a subtle border highlight on the active slot with a small "tap to cancel" label. No need for a full-width banner.

**9. Checkout hint is missing**
`base_game_screen_state.dart:564` — When `myScore <= 170`, the score turns green to hint at a possible checkout, but no actual checkout combination is shown. This is one of the most-wanted features in competitive darts apps.
- When score is ≤ 170 and reachable, show the standard 3-dart checkout path (e.g. "T20 T19 D12") beneath the score.

**10. "Dart X/3" AppBar counter is always active, even on opponent turn**
`game_screen.dart:372`, `tournament_game_screen.dart:396` — `Dart ${dartsThrown + 1}/3` is shown in the AppBar regardless of whose turn it is. During the opponent's turn it shows "Dart 1/3" which is confusing.
- Hide or replace with "Waiting…" when it is not the player's turn.

**11. AI toggle FAB may be obscured by Android gesture nav bar**
`base_game_screen_state.dart:732` — The AI toggle is `Positioned(bottom: 80, right: 12)`. On Android devices with gesture navigation the system bar can be 80–100px tall, placing this button right behind the nav gesture zone.
- Use `MediaQuery.of(context).viewPadding.bottom` to offset the FAB correctly: `bottom: 80 + viewPadding.bottom`.

**12. "YOUR SCORE:" label is 10px — illegible**
`base_game_screen_state.dart:563` — The "YOUR SCORE: " label is `fontSize: 10`. At that size it provides no real value. The score number below it (22px) is self-explanatory.
- Remove the label entirely, or replace it with a tiny colored dot/indicator to distinguish the box.

**13. Dartboard triple ring is disproportionately large**
`interactive_dartboard.dart:62-64` — The triple ring spans radius 0.28–0.48 (20% of the board radius as a ring width). On a real dartboard the triple is a very thin ring. The current size means it is dramatically easier to hit triples than in real play, which undermines competitive integrity.
- Adjust to a more realistic ratio, e.g. tripleStart: `0.55`, tripleEnd: `0.62` (matching real proportions). Recalibrate all ring positions accordingly.

**14. "YOUR SCORE" overlay label in opponent video is 9px**
`base_game_screen_state.dart:458` — The "YOUR SCORE" label inside the opponent-turn video overlay is `fontSize: 9`. It is unreadable on most screens.
- Remove the label; the context (your score in the top-right green box) is obvious. Or increase to 11px minimum.

---

### Minor

**15. Win dialog "Edit Darts" has too low visual prominence**
`base_game_screen_state.dart:324` — In the win confirmation dialog, "Edit Darts" is a `TextButton` while "Confirm Win" is an `ElevatedButton`. Since a false-positive checkout detection is plausible, editing should be at least an `OutlinedButton` to be equally discoverable.

**16. Bust dialog same issue**
`base_game_screen_state.dart:347` — Same asymmetry: "Edit Darts" is `TextButton`. In a bust scenario, the player is equally likely to want to edit. Use `OutlinedButton` for "Edit Darts".

**17. `buildOpponentWaitingPanel` has `SingleChildScrollView` wrapping a small fixed content block**
`base_game_screen_state.dart:628` — The waiting panel is tiny and will never scroll. The wrapper adds unnecessary nesting.
- Remove the `SingleChildScrollView`.

**18. Warning box in waiting panel is too narrow**
`base_game_screen_state.dart:636` — `margin: EdgeInsets.symmetric(horizontal: 40)` makes the "Do not play during opponent's turn" box very narrow on small screens (320px wide devices would have only 240px of content width).
- Reduce horizontal margin to 16–20px.

**19. Tournament series scoreboard text sizes are very small**
`tournament_game_screen.dart:434,455` — Round name is `fontSize: 9`, "Best of X" is `fontSize: 9`. These are effectively invisible on most screens.
- Increase to 11px minimum.

**20. ELO change not shown on ranked match end screen**
`game_screen.dart:242-244` — After VICTORY/DEFEAT, the end screen shows no ELO gain or loss. Players care deeply about this number.
- Show ELO delta (e.g. "+18 ELO" in green or "-12 ELO" in red) prominently on the result screen after accepting.

---

## HOME SCREEN

**21. AppBar logo container is 80px tall**
`home_screen.dart:50-55` — `SizedBox(height: 80)` for the logo makes the AppBar significantly taller than standard (56px). This wastes vertical space on every screen in the app.
- Reduce logo height to 36–40px, or use a text-only title.

**22. User card duplicates info already on Play tab**
`home_screen.dart:88-154` — The persistent user card at the top of HomeScreen shows rank badge, username, and ELO — the same information visible in the Play tab rank progression widget. It occupies ~100px of vertical space on every tab.
- Consider removing the card and relying on the Play tab for rank/ELO context, or shrinking it to a single-line compact header (avatar + username + ELO inline, ~44px tall).

**23. Bottom nav tab label font is 9px**
`home_screen.dart:300` — `fontSize: 9` for tab labels is below the minimum recommended size (11px) for legibility, especially for users with lower visual acuity.
- Increase to 11px.

---

## PLAY SCREEN

**24. Hardcoded static "Pro Tip"**
`play_screen.dart:927-948` — The tip box always shows "Practice your doubles! They are crucial for closing out games." This string is hardcoded, not localized, and never changes.
- Either rotate through a list of tips, make it dynamic from the backend, or remove it.

**25. "Play your first game to see history" is not localized**
`play_screen.dart:896` — Hardcoded English string, unlike the rest of the screen.
- Add to `app_localizations`.

**26. Previous rank ELO display is misleading**
`play_screen.dart:322` — The previous rank label shows `-X` (e.g. "-200") in red, which looks like the user lost 200 ELO. It actually means "200 ELO above the previous rank threshold".
- Change the label to something like "Prev: [Rank Name]" without a negative number, or show it as "X above [Rank]" in a neutral color.

**27. "Refresh" button does not navigate to full match history**
`play_screen.dart:856-863` — The "Refresh" TextButton next to "Recent Matches" just reloads the same 3 matches. Standard UX expectation is "View All" to go to the full history.
- Rename to "View All" and navigate to `MatchHistoryScreen`.

**28. No pull-to-refresh on Play screen**
`play_screen.dart` — The recent matches list has no pull-to-refresh gesture.
- Wrap the `SingleChildScrollView` in a `RefreshIndicator` that calls `_loadRecentMatches()` and `_checkActiveMatch()`.

---

## CAMERA SETUP SCREEN

**29. "Connected" label refers to socket, not camera**
`camera_setup_screen.dart:544-551` — Inside the camera preview overlay, a green dot with "Connected" label shows the socket connection status. On this screen, users expect camera-related feedback. The word "Connected" with no context is confusing.
- Remove the socket status indicator from this screen, or replace with "Camera Ready" once the camera is initialized.

**30. No pinch-to-zoom on camera preview**
`camera_setup_screen.dart:633-659` — Zoom is only adjustable via `+` / `-` buttons. On mobile, users expect pinch-to-zoom on a camera view.
- Add a `GestureDetector` with `onScaleUpdate` to handle pinch-to-zoom natively.

**31. Camera preview overlay is too information-dense**
`camera_setup_screen.dart:519-630` — The overlay inside the preview box stacks: socket status, instructions, AI detection status — all in a single card. It occupies a large portion of the preview area.
- Separate concerns: show instructions as a bottom bar, and AI detection status as a small colored badge at the top (not a full card). Move socket status out of the camera preview entirely.

---

## MATCHMAKING SCREEN

**32. ELO range expansion is not explained to the user**
`matchmaking_screen.dart:507` — The `±eloRange` value updates silently as wait time increases. Users may notice the number changing and not understand why.
- Add a small label like "expanding as you wait" or a subtle animation when the range updates.

**33. `debugPrint` calls left in production code**
`matchmaking_screen.dart:76-77` — Multiple `debugPrint('DEBUG: ...')` calls remain in the matchmaking update and navigation flow. These should be removed before production.
- Remove or guard with `kDebugMode`.

---

## AUTH SCREENS

**34. "Don't have an account?" text and Register button are visually separated**
`login_screen.dart:198-224` — The text "Don't have account?" is in a `Row` with a trailing space and no inline button; the Register button is on a separate line below. This is an unusual layout — standard UX puts these inline.
- Use a single `Row` with a `TextButton` inline: `"Don't have an account?" [Register]`.

---

## TOURNAMENT SCREENS

**35. `TournamentMatchResultScreen` player column shows no leg count**
`tournament_match_result_screen.dart:219-238` — `_buildPlayerColumn` only shows the username and a trophy icon, with no legs-won number. The number is shown only in the center score "X - Y". This creates a disconnect between the player names and their scores.
- Add the legs-won count inside each player column, below the username.

**36. Leg indicator dots color assignment is ambiguous**
`tournament_leg_result_screen.dart:133-154` — The dots are colored green for my legs, red for opponent legs, grey for remaining. But they are shown in a single row in chronological order, not per-player. This makes it unclear which dots belong to which player.
- Change to two rows of dots (one labeled "You", one labeled the opponent name), or use a split progress bar with two colors.

**37. `TournamentGameScreen` end screen labels "LEG WON/LOST" for a best-of series**
`tournament_game_screen.dart:289` — The `buildEndScreen` (shown after each leg) says "LEG WON!" / "LEG LOST" and "Match Result / Please confirm the match result". This is shown after every leg, so "Match Result" is misleading when the series is still ongoing.
- Distinguish between mid-series leg end ("Leg X Result") and final match end ("Match Result"). Use the tournament state to determine the correct label.

---

## GLOBAL / CROSS-CUTTING

**38. Multiple hardcoded strings not in l10n**
The following strings are hardcoded in English and bypass the localization system:
- `"LIVE MATCH"` — `game_screen.dart`
- `"TOURNAMENT"` — `tournament_game_screen.dart`
- `"Dart 1/3"` — both game screens
- `"INITIALIZING MATCH..."` — both game screens
- `"Continue Playing"` — `game_screen.dart` forfeit dialog
- `"Match Result"`, `"Please confirm the match result"`, `"ACCEPT RESULT"`, `"REPORT PLAYER"` — end screens
- `"You have proven yourself a legend."`, `"Training is the path to greatness."` — ranked end screen
- `"Pro Tip"`, `"Practice your doubles!..."` — play screen
- `"Play your first game to see history"` — play screen
- `"Loading auto-scoring..."` — game body
- `"Setting up camera & AI scoring..."` — loading screen
- `"Opponent disconnected — X left to reconnect"` — game body

All of these should be added to `app_localizations`.

**39. Inconsistent screen background treatment**
Some screens use `AppTheme.surfaceGradient` (matchmaking, end screens, login), others use flat `AppTheme.background` (game loading, waiting screens). This creates a visual inconsistency between screens in the same flow.
- Define a standard: use `AppTheme.background` (flat) for functional/in-game screens and `AppTheme.surfaceGradient` for lobby/result screens.

**40. No ELO gain/loss preview before or after confirming result**
Players have no way to see how much ELO they will gain or lose from the current match before, during, or immediately after accepting the result. This is a major engagement feature in competitive apps.
- Show the projected ELO change (fetched from the backend after game ends) on the end screen before the player taps "Accept Result".
