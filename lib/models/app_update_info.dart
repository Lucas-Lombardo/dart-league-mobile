/// Server response from GET /app/version-config — whether a newer app version
/// is available for this client, plus the store link and optional message.
class AppUpdateInfo {
  final bool updateAvailable;
  final String? latestVersion;
  final String? message;
  final String? storeUrl;

  const AppUpdateInfo({
    required this.updateAvailable,
    this.latestVersion,
    this.message,
    this.storeUrl,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        updateAvailable: json['updateAvailable'] == true,
        latestVersion: json['latestVersion'] as String?,
        message: json['message'] as String?,
        storeUrl: json['storeUrl'] as String?,
      );
}
