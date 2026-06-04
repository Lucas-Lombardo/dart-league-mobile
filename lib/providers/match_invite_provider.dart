import 'package:flutter/foundation.dart';

import '../services/socket_service.dart';
import '../utils/haptic_service.dart';
import 'game_provider.dart';

class IncomingInvite {
  final String inviteId;
  final String inviterId;
  final String inviterUsername;

  IncomingInvite({
    required this.inviteId,
    required this.inviterId,
    required this.inviterUsername,
  });
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
  String? _outgoingFriendUsername;
  bool _outgoingWaiting = false;
  String? _outgoingResolved; // 'declined' once the friend declines / accept fails

  // Friendly match starting (both sides).
  bool _friendlyMatchFound = false;
  String? _matchId;
  String? _opponentId;
  String? _opponentUsername;
  String? _agoraAppId;
  String? _agoraToken;
  String? _agoraTokenStrict;
  String? _agoraChannelName;
  int? _agoraUid;
  int? _opponentAgoraUid;

  String? _lastError; // invite_error reason, surfaced once by the gate

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  IncomingInvite? get incoming => _incoming;
  bool get outgoingWaiting => _outgoingWaiting;
  String? get outgoingFriendUsername => _outgoingFriendUsername;
  String? get outgoingResolved => _outgoingResolved;
  bool get friendlyMatchFound => _friendlyMatchFound;
  String? get matchId => _matchId;
  String? get opponentId => _opponentId;
  String? get opponentUsername => _opponentUsername;
  String? get agoraAppId => _agoraAppId;
  String? get agoraToken => _agoraToken;
  String? get agoraTokenStrict => _agoraTokenStrict;
  String? get agoraChannelName => _agoraChannelName;
  int? get agoraUid => _agoraUid;
  int? get opponentAgoraUid => _opponentAgoraUid;
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
    } catch (e) {
      debugPrint('MatchInviteProvider.start failed: $e');
    }
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _cleanupListeners();
    _incoming = null;
    _outgoingInviteId = null;
    _outgoingFriendUsername = null;
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

  Future<void> invite(String friendId, {String? friendUsername}) async {
    try {
      await SocketService.ensureConnected();
      if (!_started) {
        _registerListeners();
        _started = true;
      }
      _outgoingFriendUsername = friendUsername;
      _outgoingResolved = null;
      // Don't raise the waiting dialog yet: this runs from the camera-setup
      // screen which pops itself immediately after. We let the server's
      // invite_sent ack flip outgoingWaiting so the dialog appears only after
      // that pop (otherwise the pop would dismiss the dialog by mistake).
      SocketService.emit('invite_friend', {'friendId': friendId});
    } catch (e) {
      _outgoingWaiting = false;
      _lastError = 'server_error';
      notifyListeners();
    }
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
    _outgoingFriendUsername = null;
    _outgoingResolved = null;
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
    // Inviter side: the friend declined or the accept failed.
    _outgoingWaiting = false;
    _outgoingResolved = 'declined';
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
    _matchId = data['matchId'] as String?;
    _opponentId = data['opponentId'] as String?;
    _opponentUsername = data['opponentUsername'] as String?;

    final newAgoraAppId = data['agoraAppId'] as String?;
    final newAgoraToken = data['agoraToken'] as String?;
    final newAgoraTokenStrict = data['agoraTokenStrict'] as String?;
    final newAgoraChannelName = data['agoraChannelName'] as String?;
    final newAgoraUid = (data['agoraUid'] as num?)?.toInt();
    final newOpponentAgoraUid = (data['opponentAgoraUid'] as num?)?.toInt();
    if (newAgoraAppId != null) _agoraAppId = newAgoraAppId;
    if (newAgoraToken != null) _agoraToken = newAgoraToken;
    if (newAgoraTokenStrict != null && newAgoraTokenStrict.isNotEmpty) {
      _agoraTokenStrict = newAgoraTokenStrict;
    }
    if (newAgoraChannelName != null) _agoraChannelName = newAgoraChannelName;
    if (newAgoraUid != null) _agoraUid = newAgoraUid;
    if (newOpponentAgoraUid != null) _opponentAgoraUid = newOpponentAgoraUid;

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
      _gameProvider!.ensureListenersSetup();
      _gameProvider!.initGame(
        _matchId!,
        _currentUserId!,
        _opponentId!,
        agoraAppId: _agoraAppId,
        agoraToken: _agoraToken,
        agoraTokenStrict: _agoraTokenStrict,
        agoraChannelName: _agoraChannelName,
        agoraUid: _agoraUid,
        opponentAgoraUid: _opponentAgoraUid,
      );
    }

    _friendlyMatchFound = true;
    HapticService.heavyImpact();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cleanupListeners();
    super.dispose();
  }
}
