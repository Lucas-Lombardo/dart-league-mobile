/// Server response from GET /app/version-config — whether a newer app version
/// is available for this client, plus the store link and optional message.
class AppUpdateInfo {
  final bool updateAvailable;
  final String? latestVersion;
  final String? message;
  final String? storeUrl;

  /// True when this install is below the tournament minimum version — the
  /// backend refuses tournament registration until the app is updated.
  final bool tournamentUpdateRequired;

  /// Remote flag of the AI dataset capture (missing on old backends → false).
  final bool datasetCaptureEnabled;

  /// Remote flag of the first-placement-match diagnostic capture (missing on
  /// old backends → false).
  final bool placementDebugEnabled;

  /// The AI scorer rollout: which model key the backend wants installs to run
  /// ('auto' = keep the per-device probe), the share of installs it applies
  /// to, and whether it is restricted to heavy-capable phones. Missing on old
  /// backends → 'auto', which is exactly the no-op.
  final String aiModel;
  final int aiModelRolloutPercent;
  final bool aiModelCapableOnly;

  const AppUpdateInfo({
    required this.updateAvailable,
    this.latestVersion,
    this.message,
    this.storeUrl,
    this.tournamentUpdateRequired = false,
    this.datasetCaptureEnabled = false,
    this.placementDebugEnabled = false,
    this.aiModel = 'auto',
    this.aiModelRolloutPercent = 100,
    this.aiModelCapableOnly = false,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        updateAvailable: json['updateAvailable'] == true,
        latestVersion: json['latestVersion'] as String?,
        message: json['message'] as String?,
        storeUrl: json['storeUrl'] as String?,
        tournamentUpdateRequired: json['tournamentUpdateRequired'] == true,
        datasetCaptureEnabled: json['datasetCaptureEnabled'] == true,
        placementDebugEnabled: json['placementDebugEnabled'] == true,
        aiModel: json['aiModel'] as String? ?? 'auto',
        aiModelRolloutPercent: json['aiModelRolloutPercent'] is int
            ? json['aiModelRolloutPercent'] as int
            : 100,
        aiModelCapableOnly: json['aiModelCapableOnly'] == true,
      );
}
