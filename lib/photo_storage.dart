import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'retro_filter.dart';

class SavedPhoto {
  const SavedPhoto({required this.file, required this.capturedAt});

  final File file;
  final DateTime capturedAt;
}

class PhotoStorage {
  PhotoStorage({this.rootDirectory});

  final Directory? rootDirectory;

  Future<File> savePhoto({
    required File source,
    required RetroFilter filter,
    DateTime? capturedAt,
  }) async {
    final date = (capturedAt ?? DateTime.now()).toLocal();
    final directory = await _getDirectory();
    final fileName = 'retro_${date.microsecondsSinceEpoch}.jpg';
    final targetPath = '${directory.path}${Platform.pathSeparator}$fileName';

    await compute(_processPhoto, <String, String>{
      'sourcePath': source.path,
      'targetPath': targetPath,
      'filter': filter.index.toString(),
      'stamp': _formatStamp(date),
    });

    return File(targetPath);
  }

  Future<List<SavedPhoto>> listPhotos() async {
    final directory = await _getDirectory();
    final photos = <SavedPhoto>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.jpg')) {
        continue;
      }
      photos.add(
        SavedPhoto(file: entity, capturedAt: await entity.lastModified()),
      );
    }

    photos.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return photos;
  }

  Future<Directory> _getDirectory() async {
    final root = rootDirectory ?? await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}RetroCam',
    );
    await directory.create(recursive: true);
    return directory;
  }
}

String _formatStamp(DateTime date) {
  const months = <String>[
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour < 12 ? 'AM' : 'PM';
  return '${date.day.toString().padLeft(2, '0')} '
      '${months[date.month - 1]} ${date.year} '
      '${hour.toString().padLeft(2, '0')}:$minute $period';
}

Future<String> _processPhoto(Map<String, String> arguments) async {
  final sourceBytes = await File(arguments['sourcePath']!).readAsBytes();
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const FormatException('The captured photo could not be decoded.');
  }

  final photo = img.bakeOrientation(decoded);
  final filterIndex = int.tryParse(arguments['filter']!);
  if (filterIndex == null ||
      filterIndex < 0 ||
      filterIndex >= RetroFilter.values.length) {
    throw FormatException('Unknown photo filter: ${arguments['filter']}');
  }
  final matrix = RetroFilter.values[filterIndex].matrix;
  if (matrix != null) {
    for (final pixel in photo) {
      final red = pixel.r;
      final green = pixel.g;
      final blue = pixel.b;
      final alpha = pixel.a;
      pixel
        ..r =
            (matrix[0] * red +
                    matrix[1] * green +
                    matrix[2] * blue +
                    matrix[3] * alpha +
                    matrix[4])
                .round()
                .clamp(0, 255)
        ..g =
            (matrix[5] * red +
                    matrix[6] * green +
                    matrix[7] * blue +
                    matrix[8] * alpha +
                    matrix[9])
                .round()
                .clamp(0, 255)
        ..b =
            (matrix[10] * red +
                    matrix[11] * green +
                    matrix[12] * blue +
                    matrix[13] * alpha +
                    matrix[14])
                .round()
                .clamp(0, 255)
        ..a =
            (matrix[15] * red +
                    matrix[16] * green +
                    matrix[17] * blue +
                    matrix[18] * alpha +
                    matrix[19])
                .round()
                .clamp(0, 255);
    }
  }

  final stamp = arguments['stamp']!;
  final font = photo.width > 1200 ? img.arial48 : img.arial24;
  final textWidth = stamp.codeUnits.fold<int>(0, (width, codeUnit) {
    return width + (font.characters[codeUnit]?.xAdvance ?? 14);
  });
  final horizontalPadding = math.max(12, (photo.width * 0.025).round());
  final verticalPadding = math.max(8, (photo.height * 0.018).round());
  final panelHeight = font.lineHeight + verticalPadding * 2;
  final panelTop = math.max(0, photo.height - panelHeight);
  final panelLeft = math.max(
    0,
    photo.width - textWidth - horizontalPadding * 2,
  );

  img.fillRect(
    photo,
    x1: panelLeft,
    y1: panelTop,
    x2: photo.width - 1,
    y2: photo.height - 1,
    color: img.ColorRgb8(19, 16, 13),
  );
  img.drawString(
    photo,
    stamp,
    font: font,
    x: panelLeft + horizontalPadding,
    y: panelTop + verticalPadding,
    color: img.ColorRgb8(255, 199, 125),
  );

  final target = File(arguments['targetPath']!);
  await target.writeAsBytes(img.encodeJpg(photo, quality: 92), flush: true);
  return target.path;
}
