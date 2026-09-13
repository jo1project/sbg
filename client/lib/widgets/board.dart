import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../config.dart';
import '../game/character_sprites.dart';
import '../game/map_sprites.dart';
import '../models/game_map.dart';
import '../models/point.dart';

// 蛇身視覺上放大成幾格大小(格子仍是原本的碰撞格,只是圖案畫得比格子大、
// 蓋過鄰近格子,做出Q版放大的效果)
const double _spriteScale = 3.0;

// 蛇頭(英雄)/蛇身(哥布林)在_spriteScale基準上各自的額外縮放倍率
const double _heroScale = 0.75; // 英雄縮小25%
const double _goblinScale = 0.5; // 哥布林縮小50%

// 障礙物圖示相對格子的放大倍率(0x72 DungeonTilesetII的圖案本身比16x16高,錨定格子底部往上延伸,
// 做出類似深度的堆疊感,見 _drawObstacle)
const double _obstacleScale = 1.4;

// 棋盤繪製:地板+牆體(依地圖房間/走廊佈局)+障礙物+蛇身+食物。blind 效果時只露出蛇頭前方兩格,其餘蓋黑。
class Board extends StatelessWidget {
  final List<Point> snake;
  final List<Point> foods;
  final GameMap? map;
  final Direction dir;
  final bool blind;
  final int moveTick;

  const Board({
    super.key,
    required this.snake,
    required this.foods,
    required this.map,
    required this.dir,
    required this.blind,
    required this.moveTick,
  });

  @override
  Widget build(BuildContext context) {
    // 沒有AspectRatio限制,填滿外層給多少空間就畫多少(滿版地圖,不會有黑邊),
    // 格子因此不一定是正方形,見 _BoardPainter 裡 cellW/cellH 分開計算
    return CustomPaint(
      painter: _BoardPainter(
        snake: snake,
        foods: foods,
        map: map,
        dir: dir,
        blind: blind,
        moveTick: moveTick,
      ),
      child: Container(),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final List<Point> snake;
  final List<Point> foods;
  final GameMap? map;
  final Direction dir;
  final bool blind;
  final int moveTick;

  _BoardPainter({
    required this.snake,
    required this.foods,
    required this.map,
    required this.dir,
    required this.blind,
    required this.moveTick,
  });

  // 格子中心點用cellW/cellH各自算(滿版地圖下棋盤不一定是正方形),但畫出來的圖案
  // 邊長用min(cellW,cellH)乘上倍率、寬高相同,維持素材原本比例(正方形),不會因為
  // 棋盤不是正方形就被拉伸變形。
  Rect _enlargedCell(Point p, double cellW, double cellH, double scaleFactor) {
    final s = math.min(cellW, cellH) * _spriteScale * scaleFactor;
    final cx = p.x * cellW + cellW / 2;
    final cy = p.y * cellH + cellH / 2;
    return Rect.fromLTWH(cx - s / 2, cy - s / 2, s, s);
  }

  bool _visible(Point p) {
    if (!blind || snake.isEmpty) return true;
    final head = snake.first;
    final ahead1 = head + dir.delta;
    final ahead2 = ahead1 + dir.delta;
    return p == head || p == ahead1 || p == ahead2;
  }

  void _drawImageInCell(Canvas canvas, ui.Image img, int x, double cellW, double cellH, int y, {bool flipY = false}) {
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dest = Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH);
    final paint = Paint()..filterQuality = FilterQuality.none;
    if (!flipY) {
      canvas.drawImageRect(img, src, dest, paint);
      return;
    }
    // 素材包沒有專門的底牆圖磚,底部邊界以頂牆圖磚上下翻轉湊成(規格文件2.5節)
    canvas.save();
    canvas.translate(dest.left, dest.top + dest.height);
    canvas.scale(1, -1);
    canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, dest.width, dest.height), paint);
    canvas.restore();
  }

  void _paintFloors(Canvas canvas, GameMap map, double cellW, double cellH) {
    for (final z in [...map.rooms, ...map.corridors]) {
      for (var x = z.x0; x <= z.x1; x++) {
        for (var y = z.y0; y <= z.y1; y++) {
          _drawImageInCell(canvas, MapSprites.floorFor(x, y), x, cellW, cellH, y);
        }
      }
    }
  }

  // 房間邊界畫牆(頂/底/左/右),遇到房間跟走廊相接的開口(該格本身可通行)就跳過不畫,
  // 形成走廊出入口。走廊本身不畫這種實體牆,只在上下邊緣加一條薄邊界線(見 _paintCorridorEdges)。
  void _paintRoomWalls(Canvas canvas, GameMap map, MapZone room, double cellW, double cellH) {
    void wall(int x, int y, ui.Image? img, {bool flipY = false}) {
      if (img == null) return;
      if (x < 0 || y < 0 || (map.gridCols > 0 && x >= map.gridCols) || (map.gridRows > 0 && y >= map.gridRows)) return;
      if (map.isWalkable(Point(x, y))) return; // 開口(接走廊),不畫牆
      _drawImageInCell(canvas, img, x, cellW, cellH, y, flipY: flipY);
    }

    final topY = room.y0 - 1;
    final botY = room.y1 + 1;
    wall(room.x0 - 1, topY, MapSprites.wallTopLeft);
    wall(room.x1 + 1, topY, MapSprites.wallTopRight);
    wall(room.x0 - 1, botY, MapSprites.wallTopLeft, flipY: true);
    wall(room.x1 + 1, botY, MapSprites.wallTopRight, flipY: true);
    for (var x = room.x0; x <= room.x1; x++) {
      wall(x, topY, MapSprites.wallTopMid);
      wall(x, botY, MapSprites.wallTopMid, flipY: true);
    }
    for (var y = room.y0; y <= room.y1; y++) {
      wall(room.x0 - 1, y, MapSprites.wallLeft);
      wall(room.x1 + 1, y, MapSprites.wallRight);
    }
  }

  // 走廊淨空、不畫實體牆,僅在上下邊緣(非房間開口處)加一條薄白線標示地板邊界,
  // 方便辨識可移動範圍(規格文件2.4節)。
  // ponytail: 用半透明線條示意「薄邊界」,沒有另外接0x72的wall_edge_*薄磚素材,
  // 若之後覺得視覺不夠融入地牢風格,可換成該素材包的 wall_edge_mid_left/right。
  void _paintCorridorEdges(Canvas canvas, GameMap map, double cellW, double cellH) {
    final paint = Paint()..color = Colors.white24;
    const thickness = 2.0;
    for (final c in map.corridors) {
      for (var x = c.x0; x <= c.x1; x++) {
        if (!map.isWalkable(Point(x, c.y0 - 1))) {
          canvas.drawRect(Rect.fromLTWH(x * cellW, c.y0 * cellH - thickness, cellW, thickness), paint);
        }
        if (!map.isWalkable(Point(x, c.y1 + 1))) {
          canvas.drawRect(Rect.fromLTWH(x * cellW, (c.y1 + 1) * cellH - thickness, cellW, thickness), paint);
        }
      }
    }
  }

  ui.Image? _obstacleImage(MapObstacle o) {
    switch (o.type) {
      case "crate":
        return MapSprites.crate;
      case "column":
        return MapSprites.column;
      case "chest":
        return MapSprites.chest;
      case "monster":
        final frames = MapSprites.monsterIdle[o.species];
        if (frames == null || frames.isEmpty) return null;
        // 待機動畫跟moveTick同步循環播放,不另外開獨立計時器(見board.dart文件頂端註解)
        return frames[moveTick % frames.length];
      default:
        return null;
    }
  }

  // 障礙物圖案本身比16x16高(木箱/石柱/怪物立繪),錨定格子底部往上延伸,
  // 做出類似深度堆疊的視覺效果,而不是硬塞進單一格子裡拉伸變形。
  // 大型怪物(size:"big")的素材寬度是一般的兩倍,寬度基準改成整個footprint(2格),
  // 並以footprint中心對齊,而不是只塞進單一格子裡。
  void _drawObstacle(Canvas canvas, ui.Image img, MapObstacle o, double cellW, double cellH) {
    final footprintCells = o.cells.length;
    final cellSize = math.min(cellW, cellH);
    final scale = cellSize * footprintCells / img.width.toDouble() * _obstacleScale;
    final w = img.width * scale;
    final h = img.height * scale;
    final spanWidthPx = footprintCells * cellW;
    final cx = o.pos.x * cellW + spanWidthPx / 2;
    final bottomY = o.pos.y * cellH + cellH;
    final dest = Rect.fromLTWH(cx - w / 2, bottomY - h, w, h);
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.drawImageRect(img, src, dest, Paint()..filterQuality = FilterQuality.none);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / GameConfig.mapWidth;
    final cellH = size.height / GameConfig.mapHeight;
    final boardRect = Rect.fromLTWH(0, 0, size.width, size.height);
    // 放大後的障礙物/人物圖案可能蓋過地圖邊界外,裁切掉超出棋盤範圍的部分
    canvas.clipRect(boardRect);

    // 房間/走廊以外一律是黑色虛空(規格文件7.7節),先鋪底色再疊地板/牆
    canvas.drawRect(boardRect, Paint()..color = const Color(0xFF000000));

    final map = this.map;
    if (map != null) {
      _paintFloors(canvas, map, cellW, cellH);
      for (final room in map.rooms) {
        _paintRoomWalls(canvas, map, room, cellW, cellH);
      }
      _paintCorridorEdges(canvas, map, cellW, cellH);

      for (final o in map.obstacles) {
        if (!_visible(o.pos)) continue;
        final img = _obstacleImage(o);
        if (img != null) _drawObstacle(canvas, img, o, cellW, cellH);
      }
    }

    final foodPaint = Paint()..color = Colors.redAccent;
    final foodRadius = math.min(cellW, cellH) * 0.3;
    for (final f in foods) {
      if (!_visible(f)) continue;
      canvas.drawCircle(Offset((f.x + 0.5) * cellW, (f.y + 0.5) * cellH), foodRadius, foodPaint);
    }

    // 從蛇尾畫到蛇頭,確保蛇頭(放大後)蓋在身體上面而不是被身體蓋住
    for (var i = snake.length - 1; i >= 0; i--) {
      final p = snake[i];
      if (!_visible(p)) continue;
      // 蛇頭永遠面向實際移動方向;蛇身每一節面向「朝前一節」的方向,做出跟隨感
      final segDir = i == 0 ? dir : DirectionDelta.fromDelta(snake[i - 1] - p);
      final sprite = i == 0 ? CharacterSprites.hero : CharacterSprites.goblin;
      // 每節都往內縮7.5px,讓相鄰兩節之間多留15px距離,不要貼那麼近
      final dest = _enlargedCell(p, cellW, cellH, i == 0 ? _heroScale : _goblinScale).deflate(7.5);
      if (sprite == null) {
        // 素材尚未載入完成時的備援畫法
        final paint = Paint()..color = i == 0 ? Colors.lightGreenAccent : Colors.green;
        canvas.drawRRect(RRect.fromRectAndRadius(dest.deflate(math.min(cellW, cellH) * 0.5), const Radius.circular(3)), paint);
        continue;
      }
      // 左右移動時改用攻擊動畫循環,上下移動維持走路動畫
      final frameCols = (segDir == Direction.left || segDir == Direction.right)
          ? CharacterSprites.attackFrameCols
          : CharacterSprites.walkFrameCols;
      final frameCol = frameCols[moveTick % frameCols.length];
      final src = Rect.fromLTWH(
        frameCol * CharacterSprites.frameSize,
        segDir.spriteRow * CharacterSprites.frameSize,
        CharacterSprites.frameSize,
        CharacterSprites.frameSize,
      );
      canvas.drawImageRect(sprite, src, dest, Paint()..filterQuality = FilterQuality.none);
    }

    if (blind) {
      final maskPaint = Paint()..color = Colors.black;
      for (var x = 0; x < GameConfig.mapWidth; x++) {
        for (var y = 0; y < GameConfig.mapHeight; y++) {
          final p = Point(x, y);
          if (_visible(p)) continue;
          canvas.drawRect(Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH), maskPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.snake != snake ||
      old.foods != foods ||
      old.map != map ||
      old.dir != dir ||
      old.blind != blind ||
      old.moveTick != moveTick;
}
