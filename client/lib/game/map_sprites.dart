import 'dart:ui' as ui;
import 'sprite_loader.dart';

// 棋盤背景/障礙物美術素材(Kenney Cartography Pack,CC0),見 client/README.md「美術素材」一節。
class MapSprites {
  static ui.Image? background;
  static List<ui.Image> obstacleIcons = [];

  static Future<void> load() async {
    background = await loadUiImage('assets/map/background.png');
    obstacleIcons = await Future.wait([
      loadUiImage('assets/map/obstacle_mountain.png'),
      loadUiImage('assets/map/obstacle_tree.png'),
      loadUiImage('assets/map/obstacle_bush.png'),
    ]);
  }
}
