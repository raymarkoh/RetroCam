import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:retro_cam/photo_storage.dart';
import 'package:retro_cam/retro_filter.dart';

void main() {
  late Directory temporaryDirectory;
  late File sourcePhoto;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'retro_cam_test_',
    );
    final source = img.Image(width: 640, height: 480);
    img.fill(source, color: img.ColorRgb8(120, 80, 40));
    sourcePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}capture.jpg',
    );
    await sourcePhoto.writeAsBytes(img.encodeJpg(source));
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'saved photos are stamped and remain in the gallery after restart',
    () async {
      final storage = PhotoStorage(rootDirectory: temporaryDirectory);
      final capturedAt = DateTime(2026, 10, 21, 10, 45);

      final savedFile = await storage.savePhoto(
        source: sourcePhoto,
        filter: RetroFilter.warm,
        capturedAt: capturedAt,
      );

      expect(await savedFile.exists(), isTrue);
      final savedImage = img.decodeImage(await savedFile.readAsBytes());
      expect(savedImage, isNotNull);
      final stampPanelCorner = savedImage!.getPixel(
        savedImage.width - 2,
        savedImage.height - 2,
      );
      expect(stampPanelCorner.r, lessThan(40));
      expect(stampPanelCorner.g, lessThan(40));
      expect(stampPanelCorner.b, lessThan(40));

      final photosAfterRestart = await PhotoStorage(
        rootDirectory: temporaryDirectory,
      ).listPhotos();

      expect(photosAfterRestart, hasLength(1));
      expect(photosAfterRestart.single.file.path, savedFile.path);
    },
  );
}
