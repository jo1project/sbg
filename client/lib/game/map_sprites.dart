import 'dart:ui' as ui;
import 'sprite_loader.dart';

// 怪物哨兵可選種類,見規格文件2.4節
const monsterSpecies = ["goblin", "skelet", "imp", "chort", "big_demon", "big_zombie", "ogre"];

// 棋盤地板/牆體/障礙物美術素材(0x72 DungeonTilesetII,CC0),見 client/README.md「美術素材」一節。
class MapSprites {
  // floors[0] = floor_1(主要地板,約88%權重),floors[1..7] = floor_2~floor_8(裂痕/苔蘚變化,約12%)
  static List<ui.Image> floors = [];
  static ui.Image? wallTopLeft;
  static ui.Image? wallTopMid;
  static ui.Image? wallTopRight;
  static ui.Image? wallLeft;
  static ui.Image? wallRight;

  static ui.Image? crate;
  static ui.Image? column;
  static ui.Image? chest;
  static ui.Image? food; // 食物圖示(Kenney Simplified Platformer Pack,CC0),見client/README.md
  static final Map<String, List<ui.Image>> monsterIdle = {}; // species -> 4格待機動畫

  static Future<void> load() async {
    floors = await Future.wait([for (var i = 1; i <= 8; i++) loadUiImage('assets/dungeon/floor_$i.png')]);
    wallTopLeft = await loadUiImage('assets/dungeon/wall_top_left.png');
    wallTopMid = await loadUiImage('assets/dungeon/wall_top_mid.png');
    wallTopRight = await loadUiImage('assets/dungeon/wall_top_right.png');
    wallLeft = await loadUiImage('assets/dungeon/wall_left.png');
    wallRight = await loadUiImage('assets/dungeon/wall_right.png');
    crate = await loadUiImage('assets/dungeon/crate.png');
    column = await loadUiImage('assets/dungeon/column.png');
    chest = await loadUiImage('assets/dungeon/chest_full_open_anim_f0.png');
    food = await loadUiImage('assets/ui/food_gem.png');
    for (final species in monsterSpecies) {
      monsterIdle[species] = await Future.wait(
        [for (var f = 0; f < 4; f++) loadUiImage('assets/dungeon/${species}_idle_anim_f$f.png')],
      );
    }
  }

  // 座標決定固定選用哪張floor貼圖,同一格每次重繪都一樣(不是每幀隨機換)。
  // 88%權重落在floor_1(index 0),剩下12%平均分給floor_2~8(index 1~7)。
  static ui.Image floorFor(int x, int y) {
    final h = (x * 928371 + y * 51329) % 100;
    final index = h < 88 ? 0 : 1 + (h - 88) % 7;
    return floors[index];
  }
}
