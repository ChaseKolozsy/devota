import 'dart:io';

/// Extracts a gzip stream beside [destination], replacing it only on success.
Future<void> extractApkStream(
  Stream<List<int>> compressed,
  File destination, {
  int? expectedBytes,
}) async {
  final staging = await destination.parent.createTemp('.apk-extract-');
  try {
    final partial = File('${staging.path}/payload.apk');
    await compressed.transform(gzip.decoder).pipe(partial.openWrite());
    if (expectedBytes != null &&
        expectedBytes > 0 &&
        await partial.length() != expectedBytes) {
      throw const FormatException('Extracted APK size does not match build');
    }
    await partial.rename(destination.path);
  } finally {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
