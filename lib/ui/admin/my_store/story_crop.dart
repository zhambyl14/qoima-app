import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// Сторис суретін 9:16 (тік) етіп ортасынан кесу. Тауар фотосының авто-кесуімен
// (image_crop_screen.dart → autoCenterCrop) бір идея, бірақ шаршы емес; ол
// файл басқа ағымдарда өзгеріп жатқандықтан, бұл жерде бөлек тұр.

const int kStoryWidth = 1080;
const int kStoryHeight = 1920;
const int kStoryQuality = 85;

/// [width]×[height] суреттен 9:16 ортаңғы кесіндінің тіктөртбұрышы.
/// Сурет енсіз болса (тарлау) — биіктігі қиылады, кең болса — ені.
({int x, int y, int w, int h}) storyCropRect(int width, int height) {
  if (width < 1 || height < 1) return (x: 0, y: 0, w: 1, h: 1);
  if (width * 16 >= height * 9) {
    final cw = (height * 9 / 16).round().clamp(1, width);
    return (x: (width - cw) ~/ 2, y: 0, w: cw, h: height);
  }
  final ch = (width * 16 / 9).round().clamp(1, height);
  return (x: 0, y: (height - ch) ~/ 2, w: width, h: ch);
}

/// Суретті ортасынан 9:16 кесіп JPEG қайтарады (EXIF бағыты ескеріледі, EXIF
/// өзі өшіріледі — GPS жариялануы керек емес). Үлкен болса [width]×[height]-ге
/// кішірейтеді, кішісін ЕШҚАШАН үлкейтпейді. Оқылмаса — null.
Uint8List? autoStoryCrop(
  Uint8List raw, {
  int width = kStoryWidth,
  int height = kStoryHeight,
  int quality = kStoryQuality,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(raw);
  } catch (_) {
    return null; // бүлінген файл
  }
  if (decoded == null) return null;
  final ifd = decoded.exif.imageIfd;
  if (ifd.hasOrientation && ifd.orientation != 1) {
    decoded = img.bakeOrientation(decoded);
  }
  final r = storyCropRect(decoded.width, decoded.height);
  var out = img.copyCrop(decoded, x: r.x, y: r.y, width: r.w, height: r.h);
  if (out.width > width) {
    out = img.copyResize(out,
        width: width, height: height, interpolation: img.Interpolation.average);
  }
  out.exif.clear();
  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}

Uint8List? _cropIsolate((Uint8List, int, int, int) a) =>
    autoStoryCrop(a.$1, width: a.$2, height: a.$3, quality: a.$4);

/// [autoStoryCrop] фондық isolate-та. `image` пакеті оқи алмаған формат (мыс.
/// Android-тағы HEIC) engine арқылы PNG-ге айналып, бір рет қайта сыналады.
Future<Uint8List?> autoStoryCropAsync(Uint8List raw) async {
  final out = await compute(
      _cropIsolate, (raw, kStoryWidth, kStoryHeight, kStoryQuality));
  if (out != null) return out;
  final png = await _engineDecodeToPng(raw);
  if (png == null) return null;
  return compute(_cropIsolate, (png, kStoryWidth, kStoryHeight, kStoryQuality));
}

Future<Uint8List?> _engineDecodeToPng(Uint8List raw) async {
  try {
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
