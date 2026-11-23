/// An app build a paired PC offers to phones (`update.json`, written by
/// scripts/deploy-all.sh next to the APK).
class UpdateOffer {
  const UpdateOffer({
    required this.versionCode,
    required this.versionName,
    required this.sha256,
    required this.size,
  });

  /// Android's build number of the APK (per-ABI builds add an offset, so
  /// it is compared with the installed app's own versionCode).
  final int versionCode;
  final String versionName;

  /// Hex SHA-256 of the APK; the download is checked against it.
  final String sha256;
  final int size;

  factory UpdateOffer.fromJson(Map<String, Object?> json) => UpdateOffer(
    versionCode: (json['versionCode']! as num).toInt(),
    versionName: json['versionName'] as String? ?? '',
    sha256: json['sha256']! as String,
    size: (json['size'] as num?)?.toInt() ?? 0,
  );
}
