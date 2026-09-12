import 'dart:ui' as ui;
import 'package:flutter/services.dart' show rootBundle;

// 英雄(蛇頭)/哥布林(蛇身)精靈表,素材來源見 client/README.md「美術素材」一節。
// 兩張表格式相同:928x256,29欄x8列,每格32x32像素。
// 欄:0=站立,1~4=走路循環(4格,跟一次移動tick同步用)。
// 列:見 Direction.spriteRow(models/point.dart),只用到上下左右四個主要方向。
class CharacterSprites {
  static const frameSize = 32.0;
  static const walkFrameCols = [1, 2, 3, 4];

  static ui.Image? hero;
  static ui.Image? goblin;

  static Future<void> load() async {
    hero = await _loadImage('assets/sprites/hero.png');
    goblin = await _loadImage('assets/sprites/goblin.png');
  }

  static Future<ui.Image> _loadImage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
