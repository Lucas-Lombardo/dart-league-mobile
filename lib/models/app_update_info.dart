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

  const AppUpdateInfo({
    required this.updateAvailable,
    this.latestVersion,
    this.message,
    this.storeUrl,
    this.tournamentUpdateRequired = false,
    this.datasetCaptureEnabled = false,
    this.placementDebugEnabled = false,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        updateAvailable: json['updateAvailable'] == true,
        latestVersion: json['latestVersion'] as String?,
        message: json['message'] as String?,
        storeUrl: json['storeUrl'] as String?,
        tournamentUpdateRequired: json['tournamentUpdateRequired'] == true,
        datasetCaptureEnabled: json['datasetCaptureEnabled'] == true,
        placementDebugEnabled: json['placementDebugEnabled'] == true,
      );
}
