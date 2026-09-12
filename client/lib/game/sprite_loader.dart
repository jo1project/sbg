import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;

// 共用的 asset PNG -> ui.Image 載入邏輯,給 CharacterSprites / MapSprites 用。
Future<ui.Image> loadUiImage(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  return frame.image;
}
