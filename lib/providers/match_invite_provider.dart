import 'package:flutter/foundation.dart';

import '../models/rtc_v2_config.dart';
import '../services/push_notification_service.dart';
import '../services/socket_service.dart';
import '../services/turn_report_service.dart';
import '../utils/haptic_service.dart';
import 'game_provider.dart';

class IncomingInvite {
  final String inviteId;
  final String inviterId;
  final String inviterUsername;

  /// 'x01' (default) | 'cricket_score' | 'cricket_noscore'. Additive server
  /// field — an old backend never sends it, so it falls back to x01.
  final String gameMode;

  IncomingInvite({
    required this.inviteId,
    required this.inviterId,
    required this.inviterUsername,
    this.gameMode = 'x01',
  });

  bool get isCricket => gameMode.startsWith('cricket');
}

/// Drives the friend-invite (non-ranked "friendly" match) flow on the client.
///
/// Always-on while authenticated so an invite can arrive on any screen. Mirrors
/// [MatchmakingProvider]'s handling of `friendly_match_found` (same payload shape
/// as `match_found`) so the existing game flow is reused. The UI side lives in
/// the global `FriendMatchGate`, which reacts to this provider's state.
class MatchInviteProvider with ChangeNotifier {
  bool _disposed = false;
  bool _started = false;
  String? _currentUserId;
  GameProvider? _gameProvider;

  // Incoming invite (invitee side).
  IncomingInvite? _incoming;

  // Outgoing invite (inviter side).
  String? _outgoingInviteId;
  String? _outgoingFriendId;
  String? _outgoingFriendUsername;
  String _outgoingGameMode = 'x01';
  bool _outgoingWaiting = false;
  String? _outgoingResolved; // 'declined' once the friend declines / accept fails

  // Friendly match starting (both sides).
  bool _friendlyMatchFound = false;
  String? _matchId;
  String? _opponentId;
  String? _opponentUsername;
  RtcV2Config? _rtcV2Config;

  String? _lastError; // invite_error reason, surfaced once by the gate

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  IncomingInvite? get incoming => _incoming;
  bool get outgoingWaiting => _outgoingWaiting;
  String? get outgoingFriendUsername => _outgoingFriendUsername;
  String get outgoingGameMode => _outgoingGameMode;
  String? get outgoingResolved => _outgoingResolved;
  bool get friendlyMatchFound => _friendlyMatchFound;
  String? get matchId => _matchId;
  String? get opponentId => _opponentId;
  String? get opponentUsername => _opponentUsername;
  RtcV2Config? get rtcV2Config => _rtcV2Config;
  String? get lastError => _lastError;

  void setGameProvider(GameProvider provider) {
    _gameProvider = provider;
  }

  /// Connects the socket (if needed) and registers invite listeners. Idempotent.
  Future<void> start(String userId) async {
    _currentUserId = userId;
    if (_started) return;
    try {
      await SocketService.ensureConnected();
      _registerListeners();
      _started = true;
      // Re-pull any invite that arrived while we were offline, both now (after
      // the listeners are guaranteed attached) and on every reconnect. This is
      // how an app opened from an invite push surfaces the popup.
      SocketService.addReconnectListener(_onSocketReconnect);
      PushNotificationService.onMessageOpened = _handlePushOpened;
      _requestPendingInvite();
    } catch (e) {
      debugPrint('MatchInviteProvider.start failed: $e');
    }
  }

  /// Ask the server to re-emit any still-pending incoming invite. Safe to call
  /// repeatedly; the server only replays if one is still cached.
  void _requestPendingInvite() {
    if (!_started) return;
    _safeEmit('get_pending_invite', <String, dynamic>{});
  }

  void _onSocketReconnect() => _requestPendingInvite();

  /// A notification tap (background or cold start) brought the app forward —
  /// if it was an invite, pull it now in case the socket stayed connected and
  /// no reconnect fired.
  void _handlePushOpened(Map<String, dynamic> data) {
    if (data['type'] == 'match_invite') _requestPendingInvite();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    SocketService.removeReconnectListener(_onSocketReconnect);
    PushNotificationService.onMessageOpened = null;
    _cleanupListeners();
    _incoming = null;
    _outgoingInviteId = null;
    _outgoingFriendId = null;
    _outgoingFriendUsername = null;
    _outgoingGameMode = 'x01';
    _outgoingWaiting = false;
    _outgoingResolved = null;
    _friendlyMatchFound = false;
    _lastError = null;
    notifyListeners();
  }

  void _registerListeners() {
    SocketService.on('match_invite', _handleMatchInvite);
    SocketService.on('invite_sent', _handleInviteSent);
    SocketService.on('invite_declined', _handleInviteDeclined);
    SocketService.on('invite_cancelled', _handleInviteCancelled);
    SocketService.on('invite_error', _handleInviteError);
    SocketService.on('friendly_match_found', _handleFriendlyMatchFound);
  }

  void _cleanupListeners() {
    SocketService.off('match_invite');
    SocketService.off('invite_sent');
    SocketService.off('invite_declined');
    SocketService.off('invite_cancelled');
    SocketService.off('invite_error');
    SocketService.off('friendly_match_found');
  }

  // ----- Actions (from UI) -----

  /// [gameMode] 'x01' (default) or 'cricket_score' / 'cricket_noscore'. The
  /// X01 payload stays exactly {friendId} — byte-identical to before cricket
  /// existed — so an old backend keeps behaving as today.
  Future<void> invite(
    String friendId, {
    String? friendUsername,
    String gameMode = 'x01',
  }) async {
    try {
      await SocketService.ensureConnected();
      if (!_started) {
        _registerListeners();
        _started = true;
      }
      _outgoingFriendId = friendId;
      _outgoingFriendUsername = friendUsername;
      _outgoingGameMode = gameMode;
      _outgoingResolved = null;
      _lastError = null;
      // The previous invite's id is dead the moment we re-send (the server
      // supersedes it): a Cancel tapped before the new invite_sent ack must
      // not emit cancel_invite with the stale id — it would cancel nothing
      // and leave the fresh invite pending for its full TTL.
      _outgoingInviteId = null;
      // Don't raise the waiting dialog yet: this runs from the camera-setup
      // screen which pops itself immediately after. We let the server's
      // invite_sent ack flip outgoingWaiting so the dialog appears only after
      // that pop (otherwise the pop would dismiss the dialog by mistake).
      final isCricket = gameMode.startsWith('cricket');
      SocketService.emit('invite_friend', {
        'friendId': friendId,
        if (isCricket) 'gameMode': 'cricket',
        if (isCricket)
          'cricketScoreMode':
              gameMode == 'cricket_noscore' ? 'noScore' : 'score',
      });
    } catch (e) {
      _outgoingWaiting = false;
      _lastError = 'server_error';
      notifyListeners();
    }
  }

  /// "Offer a 501 instead": re-invites the same friend in X01 after a cricket
  /// invite was refused (opponent_needs_update). The waiting screen stays put.
  Future<void> retryAsX01() async {
    final friendId = _outgoingFriendId;
    if (friendId == null) return;
    _outgoingResolved = null;
    _lastError = null;
    notifyListeners();
    await invite(friendId, friendUsername: _outgoingFriendUsername);
  }

  void accept(String inviteId) {
    _incoming = null; // hide popup; navigation happens on friendly_match_found
    notifyListeners();
    _safeEmit('accept_invite', {'inviteId': inviteId});
  }

  void decline(String inviteId) {
    _incoming = null;
    notifyListeners();
    _safeEmit('decline_invite', {'inviteId': inviteId});
  }

  void cancelOutgoing() {
    final id = _outgoingInviteId;
    _clearOutgoing();
    if (id != null) _safeEmit('cancel_invite', {'inviteId': id});
  }

  void clearOutgoing() => _clearOutgoing();

  void _clearOutgoing() {
    _outgoingWaiting = false;
    _outgoingInviteId = null;
    _outgoingFriendId = null;
    _outgoingFriendUsername = null;
    _outgoingGameMode = 'x01';
    _outgoingResolved = null;
    // A failed invite must not leak its error into the next one — the waiting
    // screen would open already "resolved".
    _lastError = null;
    notifyListeners();
  }

  void clearIncoming() {
    _incoming = null;
    notifyListeners();
  }

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Called by the gate once it has navigated into the game.
  void consumeFriendlyMatch() {
    _friendlyMatchFound = false;
    notifyListeners();
  }

  void _safeEmit(String event, dynamic data) {
    try {
      SocketService.emit(event, data);
    } catch (e) {
      debugPrint('MatchInviteProvider emit $event failed: $e');
    }
  }

  // ----- Socket handlers -----

  void _handleMatchInvite(dynamic data) {
    final inviteId = data['inviteId'] as String?;
    final inviterId = data['inviterId'] as String?;
    if (inviteId == null || inviterId == null) return;
    _incoming = IncomingInvite(
      inviteId: inviteId,
      inviterId: inviterId,
      inviterUsername: data['inviterUsername'] as String? ?? 'A friend',
      gameMode: data['gameMode'] as String? ?? 'x01',
    );
    HapticService.heavyImpact();
    notifyListeners();
  }

  void _handleInviteSent(dynamic data) {
    _outgoingInviteId = data['inviteId'] as String?;
    _outgoingWaiting = true;
    notifyListeners();
  }

  void _handleInviteDeclined(dynamic data) {
    // Inviter side: the friend declined or the accept failed. A cricket
    // invite refused because the friend's app predates the mode keeps its
    // reason, so the waiting screen can offer "send a 501 instead".
    _outgoingWaiting = false;
    _outgoingResolved = data is Map && data['reason'] == 'opponent_needs_update'
        ? 'opponent_needs_update'
        : 'declined';
    notifyListeners();
  }

  void _handleInviteCancelled(dynamic data) {
    // Invitee side: the inviter cancelled / left — dismiss the popup.
    final inviteId = data['inviteId'] as String?;
    if (_incoming != null &&
        (inviteId == null || _incoming!.inviteId == inviteId)) {
      _incoming = null;
      notifyListeners();
    }
  }

  void _handleInviteError(dynamic data) {
    _outgoingWaiting = false;
    _lastError = data['reason'] as String? ?? 'server_error';
    notifyListeners();
  }

  void _handleFriendlyMatchFound(dynamic data) {
    final incomingMatchId = data['matchId'] as String?;
    // A different matchId = a new friendly: drop the previous match's P2P
    // verdict so it can't leak onto an opponent with an old client. The
    // keep-if-null parse below still protects same-match re-emissions that
    // carry partial fields.
    if (incomingMatchId != null && incomingMatchId != _matchId) {
      _rtcV2Config = null;
      TurnReportService.resetForMatch();
    }
    _matchId = incomingMatchId;
    _opponentId = data['opponentId'] as String?;
    _opponentUsername = data['opponentUsername'] as String?;

    _rtcV2Config = RtcV2Config.adopt(data, _rtcV2Config);
    TurnReportService.applyMatchPayload(data);

    // Match is starting — clear any invite dialogs.
    _incoming = null;
    _outgoingWaiting = false;
    _outgoingResolved = null;

    // Initialise the game now so myUserId is set before game_started arrives
    // (mirrors MatchmakingProvider._handleMatchFound).
    if (_gameProvider != null &&
        _currentUserId != null &&
        _matchId != null &&
        _opponentId != null) {
      // Clear stale state from a previous match BEFORE initGame — same
      // protection as MatchmakingProvider.joinQueue. Without it, a BO3 series
      // abandoned with gameStarted still true leaked its series state into
      // this friendly (BO3 header on a friendly board; worst case the
      // buttonless "next leg" spinner instead of the play-again panel).
      if (_gameProvider!.gameStarted || _gameProvider!.gameEnded) {
        debugPrint('INVITE DEBUG: Resetting stale game provider state before friendly match');
        _gameProvider!.reset();
      }
      _gameProvider!.ensureListenersSetup();
      _gameProvider!.initGame(
        _matchId!,
        _currentUserId!,
        _opponentId!,
        rtcV2Config: _rtcV2Config,
      );
    }

    _friendlyMatchFound = true;
    HapticService.heavyImpact();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    SocketService.removeReconnectListener(_onSocketReconnect);
    PushNotificationService.onMessageOpened = null;
    _cleanupListeners();
    super.dispose();
  }
}
