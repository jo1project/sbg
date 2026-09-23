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
const double _goblinScale = 0.75; // 哥布林在縮小50%(0.5)的基礎上再放大50%

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

  // 手繪火把(沒有現成素材,用canvas原生圖形畫木壁架+雙層火焰+暖色光暈):
  // 房間左右牆面各挑最多3個非開口的格子掛壁架火把,每根石柱(column障礙物)頂端另加一個無壁架版本。
  void _paintTorches(Canvas canvas, GameMap map, double cellW, double cellH) {
    for (final room in map.rooms) {
      _wallTorches(canvas, map, room.x0 - 1, room.y0, room.y1, cellW, cellH, pointRight: true);
      _wallTorches(canvas, map, room.x1 + 1, room.y0, room.y1, cellW, cellH, pointRight: false);
    }
    for (final o in map.obstacles) {
      if (o.type != "column") continue;
      final cx = o.pos.x * cellW + cellW / 2;
      final topY = o.pos.y * cellH;
      _drawTorch(canvas, Offset(cx, topY), math.min(cellW, cellH), withBracket: false, pointRight: true);
    }
  }

  void _wallTorches(Canvas canvas, GameMap map, int wallX, int y0, int y1, double cellW, double cellH, {required bool pointRight}) {
    final wallYs = [for (var y = y0; y <= y1; y++) y].where((y) => !map.isWalkable(Point(wallX, y))).toList();
    for (final y in _evenSpaced(wallYs, 3)) {
      final cx = wallX * cellW + cellW / 2;
      final cy = y * cellH + cellH * 0.4;
      _drawTorch(canvas, Offset(cx, cy), math.min(cellW, cellH), withBracket: true, pointRight: pointRight);
    }
  }

  // 從清單裡挑最多count個大致平均分布的元素(用於火把間距),清單本身不夠就全部回傳。
  List<int> _evenSpaced(List<int> items, int count) {
    if (items.length <= count) return items;
    return [for (var i = 0; i < count; i++) items[(i * (items.length - 1) / (count - 1)).round()]];
  }

  void _drawTorch(Canvas canvas, Offset base, double cellSize, {required bool withBracket, required bool pointRight}) {
    final glowRadius = cellSize * 1.8;
    canvas.drawCircle(
      base,
      glowRadius,
      Paint()..shader = ui.Gradient.radial(base, glowRadius, const [Color(0x55FF9433), Color(0x00FF9433)]),
    );

    if (withBracket) {
      final bracketW = cellSize * 0.28;
      final bracketH = cellSize * 0.14;
      final dx = pointRight ? bracketW * 0.5 : -bracketW * 0.5;
      canvas.drawRect(
        Rect.fromCenter(center: base + Offset(dx, cellSize * 0.22), width: bracketW, height: bracketH),
        Paint()..color = const Color(0xFF6B4226),
      );
    }

    final flameH = cellSize * 0.5;
    final flameW = cellSize * 0.26;
    final fc = base + Offset(0, -flameH * 0.15);
    void flame(double wScale, double hOffsetTop, double hOffsetBot, Color color) {
      final path = Path()
        ..moveTo(fc.dx, fc.dy - flameH * hOffsetTop)
        ..quadraticBezierTo(fc.dx + flameW * wScale, fc.dy, fc.dx, fc.dy + flameH * hOffsetBot)
        ..quadraticBezierTo(fc.dx - flameW * wScale, fc.dy, fc.dx, fc.dy - flameH * hOffsetTop)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    flame(0.5, 0.5, 0.5, const Color(0xFFE8611C)); // 外層:橘紅
    flame(0.28, 0.32, 0.3, const Color(0xFFFFD24C)); // 內層:黃芯
  }

  // 每個物件腳下的淡橢圓陰影,錨在物件所佔格子的底部中心。
  void _drawShadow(Canvas canvas, double cx, double footY, double cellSize, int footprintCells) {
    final w = cellSize * 0.55 * footprintCells;
    final h = w * 0.32;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, footY), width: w, height: h),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
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

  void _paintFoods(Canvas canvas, double cellW, double cellH) {
    final foodImg = MapSprites.food;
    if (foodImg == null) return;
    // 食物圖示(橘色寶石,見client/README.md「美術素材」):固定顯示在生成的棋盤格上,
    // 不做動畫/方向變化,依格子大小等比縮放後置中畫出。
    final foodScale = math.min(cellW, cellH) * 0.7 / math.max(foodImg.width, foodImg.height);
    final fw = foodImg.width * foodScale;
    final fh = foodImg.height * foodScale;
    final foodSrc = Rect.fromLTWH(0, 0, foodImg.width.toDouble(), foodImg.height.toDouble());
    final foodPaint = Paint()..filterQuality = FilterQuality.none;
    for (final f in foods) {
      if (!_visible(f)) continue;
      final cx = (f.x + 0.5) * cellW;
      final cy = (f.y + 0.5) * cellH;
      canvas.drawImageRect(foodImg, foodSrc, Rect.fromLTWH(cx - fw / 2, cy - fh / 2, fw, fh), foodPaint);
    }
  }

  void _paintSnake(Canvas canvas, double cellW, double cellH) {
    // 從蛇尾畫到蛇頭,確保蛇頭(放大後)蓋在身體上面而不是被身體蓋住
    for (var i = snake.length - 1; i >= 0; i--) {
      final p = snake[i];
      if (!_visible(p)) continue;
      if (GameConfig.highQualityLighting) {
        _drawShadow(canvas, p.x * cellW + cellW / 2, p.y * cellH + cellH * 0.85, math.min(cellW, cellH), 1);
      }
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
  }

  void _paintBlindMask(Canvas canvas, double cellW, double cellH) {
    final maskPaint = Paint()..color = Colors.black;
    for (var x = 0; x < GameConfig.mapWidth; x++) {
      for (var y = 0; y < GameConfig.mapHeight; y++) {
        final p = Point(x, y);
        if (_visible(p)) continue;
        canvas.drawRect(Rect.fromLTWH(x * cellW, y * cellH, cellW, cellH), maskPaint);
      }
    }
  }

  // 規格文件步驟1-5的基礎場景繪製(地板/牆/火把/障礙物/角色/食物),獨立成一個方法讓
  // _paintLighting可以重畫一次拿去做模糊,而不必額外用ui.Image做bitmap快取——Board本身
  // 是CustomPainter,shouldRepaint只在snake/foods/map/blind/moveTick(跳格)變動時才觸發
  // 重繪,所以這裡「重畫兩次」的成本只發生在每次移動tick(預設275ms一次),不是每畫面幀,
  // 不需要額外的離散跳格快取機制。
  void _paintScene(Canvas canvas, Rect boardRect, double cellW, double cellH) {
    // 房間/走廊以外一律是黑色虛空(規格文件7.7節),先鋪底色再疊地板/牆
    canvas.drawRect(boardRect, Paint()..color = const Color(0xFF000000));

    final map = this.map;
    if (map != null) {
      _paintFloors(canvas, map, cellW, cellH);
      for (final room in map.rooms) {
        _paintRoomWalls(canvas, map, room, cellW, cellH);
      }
      _paintCorridorEdges(canvas, map, cellW, cellH);
      if (GameConfig.highQualityLighting) _paintTorches(canvas, map, cellW, cellH);

      for (final o in map.obstacles) {
        if (!_visible(o.pos)) continue;
        final img = _obstacleImage(o);
        if (img == null) continue;
        if (GameConfig.highQualityLighting) {
          _drawShadow(canvas, o.pos.x * cellW + o.cells.length * cellW / 2, o.pos.y * cellH + cellH * 0.95,
              math.min(cellW, cellH), o.cells.length);
        }
        _drawObstacle(canvas, img, o, cellW, cellH);
      }
    }

    _paintFoods(canvas, cellW, cellH);
    _paintSnake(canvas, cellW, cellH);
    if (blind) _paintBlindMask(canvas, cellW, cellH);
  }

  // 即時光影效果(套用在整個棋盤,非靜態烘焙):
  // 1. 移軸景深模糊 - 整個場景重畫一次套進blur saveLayer,再用垂直漸層(dstIn)只留清晰帶
  //    (約22%~80%)以外的模糊部分蓋在清晰版上面
  // 2. 暖冷雙色調 - 左上暖、右下冷的柔和對角漸層,BlendMode.overlay疊加
  // 3. 四角暗角 - 徑向漸層,BlendMode.multiply疊加聚焦視覺中心
  // 陰影已經在_paintScene裡跟著角色/障礙物一起畫。Bloom第一版先跳過。
  void _paintLighting(Canvas canvas, Rect boardRect, double cellW, double cellH) {
    const blurSigma = 6.0;
    canvas.saveLayer(boardRect, Paint());
    canvas.saveLayer(boardRect, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma));
    _paintScene(canvas, boardRect, cellW, cellH);
    canvas.restore();
    canvas.drawRect(
      boardRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, boardRect.top),
          Offset(0, boardRect.bottom),
          const [Colors.black, Colors.black, Colors.transparent, Colors.transparent, Colors.black, Colors.black],
          const [0.0, 0.22, 0.22, 0.80, 0.80, 1.0],
        )
        ..blendMode = BlendMode.dstIn,
    );
    canvas.restore();

    canvas.drawRect(
      boardRect,
      Paint()
        ..shader = ui.Gradient.linear(boardRect.topLeft, boardRect.bottomRight, const [Color(0x33FF8A3D), Color(0x332255FF)])
        ..blendMode = BlendMode.overlay,
    );

    canvas.drawRect(
      boardRect,
      Paint()
        ..shader = ui.Gradient.radial(
          boardRect.center,
          boardRect.longestSide * 0.75,
          const [Colors.transparent, Colors.black54],
          const [0.55, 1.0],
        )
        ..blendMode = BlendMode.multiply,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / GameConfig.mapWidth;
    final cellH = size.height / GameConfig.mapHeight;
    final boardRect = Rect.fromLTWH(0, 0, size.width, size.height);
    // 放大後的障礙物/人物圖案可能蓋過地圖邊界外,裁切掉超出棋盤範圍的部分
    canvas.clipRect(boardRect);

    _paintScene(canvas, boardRect, cellW, cellH);
    if (GameConfig.highQualityLighting) _paintLighting(canvas, boardRect, cellW, cellH);
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
