import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:devota/apk_stream_extract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp('apk-test-'),
  );
  tearDown(() async => directory.delete(recursive: true));
  test(
    'extracts chunked gzip with matching hash and replaces cached APK',
    () async {
      final data = List<int>.generate(200000, (i) => (i * 31 + i ~/ 251) % 256);
      final compressed = gzip.encode(data);
      final destination = File('${directory.path}/app.apk');
      await destination.writeAsString('old cached file');
      final controller = StreamController<List<int>>();
      final extraction = extractApkStream(
        controller.stream,
        destination,
        expectedBytes: data.length,
      );
      for (var i = 0; i < compressed.length; i += 37) {
        controller.add(
          compressed.sublist(i, (i + 37).clamp(0, compressed.length)),
        );
      }
      await controller.close();
      await extraction;
      expect(
        sha256.convert(await destination.readAsBytes()),
        sha256.convert(data),
      );
      expect(directory.listSync().length, 1);
    },
  );
  test(
    'failed stream leaves existing APK intact and removes partial',
    () async {
      final destination = File('${directory.path}/app.apk');
      await destination.writeAsString('valid cached file');
      await expectLater(
        extractApkStream(
          Stream<List<int>>.error(const FileSystemException("read failed")),
          destination,
        ),
        throwsA(anything),
      );
      expect(await destination.readAsString(), 'valid cached file');
      expect(directory.listSync().length, 1);
    },
  );
  test(
    'wrong extracted size preserves cached APK and cleans partial',
    () async {
      final destination = File('${directory.path}/app.apk');
      await destination.writeAsString('valid cached file');
      await expectLater(
        extractApkStream(
          Stream.value(gzip.encode([1, 2, 3])),
          destination,
          expectedBytes: 4,
        ),
        throwsFormatException,
      );
      expect(await destination.readAsString(), 'valid cached file');
      expect(directory.listSync().length, 1);
    },
  );
}
