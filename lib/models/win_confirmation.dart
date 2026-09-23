/// Server-owned checkout deadline, translated to the local clock once per sync.
class WinConfirmation {
  final String playerId;
  final String phase;
  final DateTime? deadline;
  final bool closesCall;
  final bool callClosed;

  const WinConfirmation({
    required this.playerId,
    this.phase = 'pending',
    this.deadline,
    this.closesCall = false,
    this.callClosed = false,
  });

  static WinConfirmation? fromJson(dynamic value) {
    if (value is! Map || value['playerId'] is! String) return null;
    final end = DateTime.tryParse(value['deadline']?.toString() ?? '');
    final server = DateTime.tryParse(value['serverNow']?.toString() ?? '');
    return WinConfirmation(
      playerId: value['playerId'] as String,
      phase: value['phase'] as String? ?? 'pending',
      deadline: end == null
          ? null
          : server == null
          ? end
          : DateTime.now().add(end.difference(server)),
      closesCall: value['closesCall'] == true,
      callClosed: value['callClosed'] == true,
    );
  }

  /// A null deadline also describes legacy games and an ongoing correction.
  /// Use the board state to reconcile the notice independently of the clock.
  static WinConfirmation? fromSync(
    Map data, {
    WinConfirmation? previous,
  }) {
    if (!data.containsKey('winConfirmation') &&
        !data.containsKey('pendingState')) {
      return previous;
    }
    final confirmation = fromJson(data['winConfirmation']);
    if (confirmation != null) return confirmation;
    final playerId = data['pendingPlayerId'];
    if (data['pendingState'] == 'pending_win' && playerId is String) {
      // No server deadline means manual confirmation, including after a
      // capability downgrade. Never retain the previous automatic deadline.
      return WinConfirmation(playerId: playerId);
    }
    if (previous != null &&
        previous.correcting &&
        data['pendingState'] == null &&
        data['currentPlayerId'] == previous.playerId) {
      return previous;
    }
    return null;
  }

  int? get secondsLeft => deadline == null
      ? null
      : ((deadline!.difference(DateTime.now()).inMilliseconds / 1000).ceil())
            .clamp(0, 300);
  bool get warning => secondsLeft != null && secondsLeft! <= 30;
  bool get pending => phase == 'pending';
  bool get correcting => phase == 'correcting';
  bool get shouldCloseCall =>
      closesCall && phase == 'confirmed' && (callClosed || secondsLeft == 0);
}
