import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Widget;

import '../services/socket_service.dart';
import '../services/spectate_service.dart';
import '../services/spectator_video_session.dart';
import '../utils/dart_caller_service.dart';
import '../widgets/game_turn_ui.dart' show notationPoints;

/// One completed visit shown in the spectator "last visits" feed.
class SpectatedVisit {
  final String playerId;
  final List<String> throws; // backend notations ('T20', 'S5', …)
  final int total;

  const SpectatedVisit({
    required this.playerId,
    required this.throws,
    required this.total,
  });
}

enum SpectatorStatus { connecting, live, waitingNextLeg, ended, denied }

/// Read-only live view of somebody else's ranked/tournament match.
///
/// Listens through [SocketService.onShared] — never through the single-slot
/// [SocketService.on] registry — so it can watch the exact event names the
/// game providers own without unhooking a live match. The server keeps this
/// socket in the match room (spectate_match) and self-heals any drift with
/// its periodic game_state_sync, so handlers here can stay simple.
class SpectatorProvider extends ChangeNotifier {
  String? _matchId;
  SpectatorStatus _status = SpectatorStatus.connecting;
  String? _denyReason;

  // Series identity behind the leg being watched, kept from the seed so a
  // stale leg id (30s hub poll, reconnect across a leg boundary) can be
  // resolved to the CURRENT leg instead of dying on not_live.
  String? _seedSeriesId;
  String? _seedTournamentMatchId;
  int _notLiveRetries = 2;

  SpectatorPlayer? _player1;
  SpectatorPlayer? _player2;

  int _player1Score = 0;
  int _player2Score = 0;
  List<int> _player1Rounds = const [];
  List<int> _player2Rounds = const [];
  String? _currentPlayerId;
  List<String> _currentRoundThrows = const [];

  int _bestOf = 3;
  int _legNumber = 1;
  int _player1LegsWon = 0;
  int _player2LegsWon = 0;

  int _spectatorCount = 0;
  String? _winnerId;
  final List<SpectatedVisit> _lastVisits = [];

  bool _listening = false;
  bool _disposed = false;
  Timer? _resnapshotTimer;

  // ── Cameras (series on Cloudflare Realtime) ──────────────────────────────
  // 'sfu' while the players' series runs on Cloudflare — then their cameras
  // can be watched; 'p2p' (old app on one side, or a fallback) = virtual
  // board only, exactly as before.
  String _videoTransport = 'p2p';
  // Players whose camera is published, and the publications behind them:
  // a change of session (a player's app rebuilt its connection) means the
  // pulled tracks are dead — watch again.
  Set<String> _videoPlayers = const {};
  String? _videoSignature;
  SpectatorVideoSession? _video;
  bool _watchInFlight = false;
  int _watchFailures = 0;
  Timer? _rewatchTimer;

  // Local caller mute for THIS screen only — the global caller setting is
  // left alone (it also drives the player's own matches).
  bool _callerMuted = false;

  // Getters
  String? get matchId => _matchId;
  SpectatorStatus get status => _status;
  String? get denyReason => _denyReason;
  SpectatorPlayer? get player1 => _player1;
  SpectatorPlayer? get player2 => _player2;
  int get player1Score => _player1Score;
  int get player2Score => _player2Score;
  String? get currentPlayerId => _currentPlayerId;
  List<String> get currentRoundThrows => _currentRoundThrows;
  int get bestOf => _bestOf;
  int get legNumber => _legNumber;
  int get player1LegsWon => _player1LegsWon;
  int get player2LegsWon => _player2LegsWon;
  int get spectatorCount => _spectatorCount;
  String? get winnerId => _winnerId;
  List<SpectatedVisit> get lastVisits => List.unmodifiable(_lastVisits);

  /// 'sfu' when the cameras can be watched, 'p2p' otherwise.
  String get videoTransport => _videoTransport;
  bool get camerasAvailable => _videoTransport == 'sfu';

  /// [playerId]'s camera is live (frames actually arriving).
  bool hasCameraFor(String? playerId) => _video?.hasVideoFor(playerId) ?? false;

  Widget? cameraViewFor(String? playerId) =>
      playerId == null ? null : _video?.viewFor(playerId);

  /// The caller can only be muted here when it is on in the settings.
  bool get callerAvailable => DartCallerService.enabled;
  bool get callerMuted => _callerMuted;

  void toggleCallerMuted() {
    _callerMuted = !_callerMuted;
    if (_callerMuted) DartCallerService.stop();
    _safeNotify();
  }

  int get currentVisitTotal =>
      _currentRoundThrows.fold(0, (sum, n) => sum + notationPoints(n));

  /// 3-dart average of one player, from their per-visit totals. 0 when unknown.
  double averageOf(bool isPlayer1) {
    final rounds = isPlayer1 ? _player1Rounds : _player2Rounds;
    if (rounds.isEmpty) return 0;
    return rounds.fold<int>(0, (a, b) => a + b) / rounds.length;
  }

  /// Join [matchId] as a spectator. [seedRanked]/[seedTournament] pre-fill
  /// identities and legs from the hub list so the screen renders instantly,
  /// before the spectate_state snapshot lands.
  Future<void> startSpectating(
    String matchId, {
    LiveRankedSeries? seedRanked,
    LiveTournamentMatch? seedTournament,
  }) async {
    _matchId = matchId;
    _status = SpectatorStatus.connecting;
    _seedSeriesId = seedRanked?.seriesId;
    _seedTournamentMatchId = seedTournament?.tournamentMatchId;
    if (seedRanked != null) {
      _player1 = seedRanked.player1;
      _player2 = seedRanked.player2;
      _bestOf = seedRanked.bestOf;
      _legNumber = seedRanked.legNumber;
      _player1LegsWon = seedRanked.player1LegsWon;
      _player2LegsWon = seedRanked.player2LegsWon;
      _spectatorCount = seedRanked.spectatorCount;
    } else if (seedTournament != null) {
      _player1 = seedTournament.player1;
      _player2 = seedTournament.player2;
      _bestOf = seedTournament.bestOf;
      _legNumber = seedTournament.legNumber;
      _player1LegsWon = seedTournament.player1LegsWon;
      _player2LegsWon = seedTournament.player2LegsWon;
      _spectatorCount = seedTournament.spectatorCount;
    }
    _setupListeners();
    notifyListeners();

    try {
      await SocketService.ensureAuthenticated();
      if (!SocketService.supportsSpectate) {
        _deny('unsupported');
        return;
      }
      _emitSpectate();
    } catch (e) {
      debugPrint('SpectatorProvider: connect failed: $e');
      _deny('error');
    }
  }

  void _emitSpectate() {
    final id = _matchId;
    if (id == null) return;
    try {
      SocketService.emit('spectate_match', {'matchId': id});
    } catch (e) {
      debugPrint('SpectatorProvider: spectate_match emit failed: $e');
    }
  }

  /// Ask for a fresh snapshot shortly — used after game_started / next_leg,
  /// when the new leg's game_state may not exist yet server-side.
  void _scheduleResnapshot() {
    _resnapshotTimer?.cancel();
    _resnapshotTimer = Timer(const Duration(seconds: 3), _emitSpectate);
  }

  /// A rebuilt socket is no longer in the match room server-side — re-issue
  /// spectate_match so the room membership and snapshot come back.
  void _onReconnected() {
    if (_status == SpectatorStatus.ended || _status == SpectatorStatus.denied) {
      return;
    }
    _emitSpectate();
  }

  void _setupListeners() {
    if (_listening) return;
    _listening = true;
    SocketService.addReconnectListener(_onReconnected);
    SocketService.onShared('spectate_state', _handleSpectateState, owner: this);
    SocketService.onShared('spectate_left', _handleSpectateLeft, owner: this);
    SocketService.onShared(
      'spectate_denied',
      _handleSpectateDenied,
      owner: this,
    );
    SocketService.onShared(
      'spectator_count',
      _handleSpectatorCount,
      owner: this,
    );
    SocketService.onShared('score_updated', _handleScoreUpdated, owner: this);
    SocketService.onShared('round_complete', _handleRoundComplete, owner: this);
    SocketService.onShared(
      'game_state_sync',
      _handleGameStateSync,
      owner: this,
    );
    SocketService.onShared('dart_undone', _handleDartUndone, owner: this);
    SocketService.onShared('game_started', _handleGameStarted, owner: this);
    SocketService.onShared('ranked_next_leg', _handleNextLeg, owner: this);
    SocketService.onShared('tournament_next_leg', _handleNextLeg, owner: this);
    SocketService.onShared('ranked_leg_won', _handleLegWon, owner: this);
    SocketService.onShared('tournament_leg_won', _handleLegWon, owner: this);
    SocketService.onShared('ranked_match_won', _handleMatchWon, owner: this);
    SocketService.onShared(
      'tournament_match_won',
      _handleMatchWon,
      owner: this,
    );
    SocketService.onShared('game_won', _handleGameWon, owner: this);
    SocketService.onShared('player_forfeited', _handleMatchWon, owner: this);
    SocketService.onShared('sfu_tracks', _handleSfuTracks, owner: this);
    SocketService.onShared(
      'video_transport_changed',
      _handleVideoTransportChanged,
      owner: this,
    );
  }

  void _teardownListeners() {
    if (!_listening) return;
    _listening = false;
    SocketService.removeReconnectListener(_onReconnected);
    for (final event in [
      'spectate_state',
      'spectate_left',
      'spectate_denied',
      'spectator_count',
      'score_updated',
      'round_complete',
      'game_state_sync',
      'dart_undone',
      'game_started',
      'ranked_next_leg',
      'tournament_next_leg',
      'ranked_leg_won',
      'tournament_leg_won',
      'ranked_match_won',
      'tournament_match_won',
      'game_won',
      'player_forfeited',
      'sfu_tracks',
      'video_transport_changed',
    ]) {
      SocketService.offShared(event, owner: this);
    }
  }

  bool _isForeign(dynamic data) =>
      data is! Map || (data['matchId'] != null && data['matchId'] != _matchId);

  void _deny(String reason) {
    _status = SpectatorStatus.denied;
    _denyReason = reason;
    _stopVideo();
    _safeNotify();
  }

  // ── Cameras ───────────────────────────────────────────────────────────────

  bool _isOurPlayer(dynamic id) =>
      id != null && (id == _player1?.id || id == _player2?.id);

  /// Adopt the video part of a spectate_state snapshot.
  void _adoptVideoSnapshot(Map map) {
    final transport = map['videoTransport'];
    if (transport is! String) return; // older backend: no cameras, ever
    final players = map['videoPlayers'];
    _videoTransport = transport == 'sfu' ? 'sfu' : 'p2p';
    if (players is List) {
      _videoPlayers = players.map((e) => '$e').toSet();
    }
    _syncVideo();
  }

  void _handleSfuTracks(dynamic data) {
    if (data is! Map) return;
    final players = data['players'];
    if (players is! Map || !players.keys.any(_isOurPlayer)) return;
    _videoTransport = data['transport'] == 'p2p' ? 'p2p' : 'sfu';
    final withVideo = <String>{};
    final signature = <String>[];
    players.forEach((id, pub) {
      if (pub is Map && pub['video'] != null) {
        withVideo.add('$id');
        signature.add('$id:${pub['sessionId']}');
      }
    });
    signature.sort();
    _videoPlayers = withVideo;
    final sig = signature.join(',');
    if (sig != _videoSignature) {
      _videoSignature = sig;
      // A (re)publication: the tracks we pulled are gone — watch again.
      _stopVideo(keepSignature: true);
    }
    _syncVideo();
    _safeNotify();
  }

  void _handleVideoTransportChanged(dynamic data) {
    if (data is! Map || data['transport'] != 'p2p') return;
    final players = data['players'];
    if (players is List && !players.any(_isOurPlayer)) return;
    _videoTransport = 'p2p';
    _videoPlayers = const {};
    _stopVideo();
    _safeNotify();
  }

  /// Start watching when the cameras are up and nothing is watched yet.
  void _syncVideo() {
    if (_disposed ||
        _videoTransport != 'sfu' ||
        _videoPlayers.isEmpty ||
        _status == SpectatorStatus.ended ||
        _status == SpectatorStatus.denied ||
        _video != null ||
        _watchInFlight) {
      return;
    }
    _rewatchTimer?.cancel();
    // Short debounce: both players usually (re)publish within a second.
    _rewatchTimer = Timer(const Duration(milliseconds: 600), _watch);
  }

  Future<void> _watch() async {
    final matchId = _matchId;
    if (_disposed || matchId == null || _video != null || _watchInFlight) {
      return;
    }
    _watchInFlight = true;
    final session = SpectatorVideoSession(
      matchId: matchId,
      onChanged: _safeNotify,
    );
    final error = await session.watch();
    _watchInFlight = false;
    if (_disposed || error != null) {
      await session.dispose();
      if (_disposed) return;
      debugPrint('SpectatorProvider: camera watch failed: $error');
      if (error == 'not_sfu') {
        _videoTransport = 'p2p';
        _safeNotify();
        return;
      }
      if (error == 'no_video_yet') return; // sfu_tracks will bring them
      // Transient (socket, Cloudflare): retry with a short backoff.
      if (_watchFailures++ < 5) {
        _rewatchTimer?.cancel();
        _rewatchTimer = Timer(
          Duration(seconds: 2 * _watchFailures),
          _syncVideo,
        );
      }
      return;
    }
    _watchFailures = 0;
    _video = session;
    _safeNotify();
  }

  void _stopVideo({bool keepSignature = false}) {
    _rewatchTimer?.cancel();
    final video = _video;
    _video = null;
    if (!keepSignature) _videoSignature = null;
    video?.dispose();
  }

  /// Announce the visit that just ended and the next thrower's finish, like
  /// the players' own screens — played locally from the scores, no sound
  /// ever comes from the players' phones.
  void _callVisit({
    required Map map,
    required String? thrower,
    required List<String> throws,
  }) {
    if (_callerMuted || !DartCallerService.enabled) return;
    if (thrower == null || throws.isEmpty) return;
    if (map['cricket'] != null ||
        map['gameMode'] is String &&
            (map['gameMode'] as String).startsWith('cricket')) {
      return; // cricket has no called score
    }
    final total = map['reason'] == 'bust_confirmed'
        ? 0
        : throws.fold<int>(0, (sum, n) => sum + notationPoints(n));
    DartCallerService.callScore(total);
    final next = map['nextPlayerId'] as String?;
    if (next == null || next == thrower) return;
    final remaining = next == _player1?.id
        ? _player1Score
        : next == _player2?.id
        ? _player2Score
        : null;
    if (remaining != null) DartCallerService.callCheckout(remaining);
  }

  void _handleSpectateDenied(dynamic data) {
    if (_isForeign(data)) return;
    final reason = (data as Map)['reason']?.toString() ?? 'error';
    // not_live is often just a STALE leg id (the hub serves the previous leg
    // for up to 30s; a reconnect can replay one) — resolve the series'
    // current leg before giving up.
    if (reason == 'not_live' && _notLiveRetries > 0) {
      _notLiveRetries--;
      _resolveCurrentLeg();
      return;
    }
    _deny(reason);
  }

  Future<void> _resolveCurrentLeg() async {
    final live = await SpectateService.fetchLive();
    String? newMatchId;
    if (live != null) {
      if (_seedSeriesId != null) {
        for (final series in live.ranked) {
          if (series.seriesId == _seedSeriesId) {
            newMatchId = series.matchId;
            break;
          }
        }
      } else if (_seedTournamentMatchId != null) {
        for (final group in live.tournaments) {
          for (final match in group.matches) {
            if (match.tournamentMatchId == _seedTournamentMatchId) {
              newMatchId = match.matchId;
              break;
            }
          }
        }
      }
    }
    if (_disposed) return;
    if (newMatchId != null && newMatchId != _matchId) {
      _matchId = newMatchId;
      _status = SpectatorStatus.connecting;
      _safeNotify();
      _emitSpectate();
    } else {
      // Same leg (or gone from the feed): the match really is over.
      _deny('not_live');
    }
  }

  /// Server-side eviction (the user's own match started while spectating):
  /// freeze the screen on a terminal state instead of silently going deaf.
  void _handleSpectateLeft(dynamic data) {
    if (_isForeign(data)) return;
    if ((data as Map)['reason'] == 'entered_own_match') {
      _deny('entered_own_match');
    }
  }

  void _handleSpectatorCount(dynamic data) {
    if (_isForeign(data)) return;
    _spectatorCount =
        ((data as Map)['count'] as num?)?.toInt() ?? _spectatorCount;
    _safeNotify();
  }

  void _handleSpectateState(dynamic data) {
    if (_isForeign(data)) return;
    final map = data as Map;

    final p1 = SpectatorPlayer.fromJson(map['player1']);
    final p2 = SpectatorPlayer.fromJson(map['player2']);
    if (p1 != null) _player1 = p1;
    if (p2 != null) _player2 = p2;
    _spectatorCount =
        (map['spectatorCount'] as num?)?.toInt() ?? _spectatorCount;

    if (map['player1Score'] == null) {
      // Leg still in its start pipeline: no game_state yet. Stay on the
      // waiting state, the room's game_started will follow.
      if (_status != SpectatorStatus.live) {
        _status = SpectatorStatus.waitingNextLeg;
      }
      _adoptVideoSnapshot(map);
      _scheduleResnapshot();
      _safeNotify();
      return;
    }

    _adoptStateFields(map);
    _status = SpectatorStatus.live;
    // A successful snapshot re-credits the stale-leg recovery budget.
    _notLiveRetries = 2;
    _adoptVideoSnapshot(map);
    _safeNotify();
  }

  /// Shared adoption of the authoritative state fields present in both
  /// spectate_state and game_state_sync payloads.
  void _adoptStateFields(Map map) {
    _player1Score = (map['player1Score'] as num?)?.toInt() ?? _player1Score;
    _player2Score = (map['player2Score'] as num?)?.toInt() ?? _player2Score;
    _currentPlayerId = map['currentPlayerId'] as String? ?? _currentPlayerId;
    _player1Rounds = _intList(map['player1Rounds']) ?? _player1Rounds;
    _player2Rounds = _intList(map['player2Rounds']) ?? _player2Rounds;
    final throws = map['currentRoundThrows'];
    if (throws is List) {
      _currentRoundThrows = throws.map((t) => t.toString()).toList();
    }
    _bestOf = (map['bestOf'] as num?)?.toInt() ?? _bestOf;
    _legNumber = (map['legNumber'] as num?)?.toInt() ?? _legNumber;
    _player1LegsWon =
        (map['player1LegsWon'] as num?)?.toInt() ?? _player1LegsWon;
    _player2LegsWon =
        (map['player2LegsWon'] as num?)?.toInt() ?? _player2LegsWon;
  }

  static List<int>? _intList(dynamic raw) {
    if (raw is! List) return null;
    return raw.map((v) => (v as num?)?.toInt() ?? 0).toList();
  }

  void _handleScoreUpdated(dynamic data) {
    if (_isForeign(data)) return;
    final map = data as Map;
    _player1Score = (map['player1Score'] as num?)?.toInt() ?? _player1Score;
    _player2Score = (map['player2Score'] as num?)?.toInt() ?? _player2Score;
    _currentPlayerId = map['currentPlayerId'] as String? ?? _currentPlayerId;
    final throws = map['currentRoundThrows'];
    if (throws is List) {
      _currentRoundThrows = throws.map((t) => t.toString()).toList();
    }
    _status = SpectatorStatus.live;
    _safeNotify();
  }

  void _handleRoundComplete(dynamic data) {
    if (_isForeign(data)) return;
    final map = data as Map;

    // The visit that just ended belongs to whoever was throwing before the
    // turn switch we're being told about.
    final thrower = _currentPlayerId;
    final visitThrows = List<String>.of(_currentRoundThrows);
    if (thrower != null && _currentRoundThrows.isNotEmpty) {
      _lastVisits.insert(
        0,
        SpectatedVisit(
          playerId: thrower,
          throws: List.of(_currentRoundThrows),
          total: currentVisitTotal,
        ),
      );
      if (_lastVisits.length > 8) _lastVisits.removeLast();
    }

    _player1Score = (map['player1Score'] as num?)?.toInt() ?? _player1Score;
    _player2Score = (map['player2Score'] as num?)?.toInt() ?? _player2Score;
    _player1Rounds = _intList(map['player1Rounds']) ?? _player1Rounds;
    _player2Rounds = _intList(map['player2Rounds']) ?? _player2Rounds;
    _currentPlayerId = map['nextPlayerId'] as String? ?? _currentPlayerId;
    _currentRoundThrows = const [];
    _callVisit(map: map, thrower: thrower, throws: visitThrows);
    _safeNotify();
  }

  void _handleGameStateSync(dynamic data) {
    if (_isForeign(data)) return;
    if (_status == SpectatorStatus.ended || _status == SpectatorStatus.denied) {
      return;
    }
    _adoptStateFields(data as Map);
    _status = SpectatorStatus.live;
    _safeNotify();
  }

  void _handleDartUndone(dynamic data) {
    if (_isForeign(data)) return;
    final map = data as Map;
    _player1Score = (map['player1Score'] as num?)?.toInt() ?? _player1Score;
    _player2Score = (map['player2Score'] as num?)?.toInt() ?? _player2Score;
    final throws = map['currentRoundThrows'];
    if (throws is List) {
      _currentRoundThrows = throws.map((t) => t.toString()).toList();
    } else if (_currentRoundThrows.isNotEmpty) {
      _currentRoundThrows = _currentRoundThrows.sublist(
        0,
        _currentRoundThrows.length - 1,
      );
    }
    _safeNotify();
  }

  void _handleGameStarted(dynamic data) {
    if (_isForeign(data)) return;
    final map = data as Map;
    // Fresh leg: adopt the opening state the payload carries right away —
    // going "live" while still showing the previous leg's final scores for
    // the resnapshot round-trip looked broken. The resnapshot still runs for
    // the series/legs context.
    _player1Score = (map['player1Score'] as num?)?.toInt() ?? _player1Score;
    _player2Score = (map['player2Score'] as num?)?.toInt() ?? _player2Score;
    _currentPlayerId = map['currentPlayerId'] as String? ?? _currentPlayerId;
    _currentRoundThrows = const [];
    _player1Rounds = const [];
    _player2Rounds = const [];
    _status = SpectatorStatus.live;
    _scheduleResnapshot();
    _safeNotify();
  }

  void _handleNextLeg(dynamic data) {
    if (data is! Map) return;
    final newMatchId = data['newMatchId'] as String?;
    if (newMatchId == null) return;
    // Only react if this event is about the leg we're watching.
    final aboutUs = data['matchId'] == null || data['matchId'] == _matchId;
    if (!aboutUs && newMatchId != _matchId) return;

    _matchId = newMatchId;
    _legNumber = (data['legNumber'] as num?)?.toInt() ?? (_legNumber + 1);
    _player1LegsWon =
        (data['player1LegsWon'] as num?)?.toInt() ?? _player1LegsWon;
    _player2LegsWon =
        (data['player2LegsWon'] as num?)?.toInt() ?? _player2LegsWon;
    _bestOf = (data['bestOf'] as num?)?.toInt() ?? _bestOf;
    _currentRoundThrows = const [];
    _player1Rounds = const [];
    _player2Rounds = const [];
    _lastVisits.clear();
    _status = SpectatorStatus.waitingNextLeg;
    // The server moves this socket to the new room on its own; re-subscribing
    // is an idempotent belt-and-braces that also fetches the new snapshot.
    _scheduleResnapshot();
    _safeNotify();
  }

  void _handleLegWon(dynamic data) {
    if (data is! Map) return;
    _player1LegsWon =
        (data['player1LegsWon'] as num?)?.toInt() ?? _player1LegsWon;
    _player2LegsWon =
        (data['player2LegsWon'] as num?)?.toInt() ?? _player2LegsWon;
    _safeNotify();
  }

  void _handleMatchWon(dynamic data) {
    if (_isForeign(data)) return;
    final map = data as Map;
    _winnerId = map['winnerId'] as String? ?? _winnerId;
    _player1LegsWon =
        (map['player1LegsWon'] as num?)?.toInt() ?? _player1LegsWon;
    _player2LegsWon =
        (map['player2LegsWon'] as num?)?.toInt() ?? _player2LegsWon;
    _status = SpectatorStatus.ended;
    _stopVideo();
    _safeNotify();
  }

  void _handleGameWon(dynamic data) {
    if (_isForeign(data)) return;
    final map = data as Map;
    // For a BO3 leg, ranked_leg_won / next_leg follow; only a decisive
    // game_won without a series context ends the spectate.
    _winnerId = map['winnerId'] as String? ?? map['playerId'] as String?;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _resnapshotTimer?.cancel();
    _stopVideo();
    _teardownListeners();
    final id = _matchId;
    if (id != null) {
      try {
        SocketService.emit('leave_spectate', {'matchId': id});
      } catch (_) {}
    }
    super.dispose();
  }
}
