import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../config.dart';
import '../game/character_sprites.dart';
import '../game/map_sprites.dart';
import '../models/point.dart';

// 人物/障礙物視覺上放大成幾格大小(格子仍是原本的碰撞格,只是圖案畫得比格子大、
// 蓋過鄰近格子,做出Q版放大的效果)
const double _spriteScale = 3.0;

// 棋盤繪製:背景 + 障礙物 + 蛇身 + 食物(無格線)。blind 效果時只露出蛇頭前方兩格,其餘蓋黑。
class Board extends StatelessWidget {
  final List<Point> snake;
  final List<Point> foods;
  final List<Point> obstacles;
  final Direction dir;
  final bool blind;
  final int moveTick;

  const Board({
    super.key,
    required this.snake,
    required this.foods,
    required this.obstacles,
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
        obstacles: obstacles,
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
  final List<Point> obstacles;
  final Direction dir;
  final bool blind;
  final int moveTick;

  _BoardPainter({
    required this.snake,
    required this.foods,
    required this.obstacles,
    required this.dir,
    required this.blind,
    required this.moveTick,
  });

  // 格子中心點用cellW/cellH各自算(滿版地圖下棋盤不一定是正方形),但畫出來的圖案
  // 邊長用min(cellW,cellH)乘上倍率、寬高相同,維持素材原本比例(正方形),不會因為
  // 棋盤不是正方形就被拉伸變形。
  Rect _enlargedCell(Point p, double cellW, double cellH) {
    final s = math.min(cellW, cellH) * _spriteScale;
    final cx = p.x * cellW + cellW / 2;
    final cy = p.y * cellH + cellH / 2;
    return Rect.fromLTWH(cx - s / 2, cy - s / 2, s, s);
  }

  // 白色外框沿著圖案本身的輪廓(不透明像素)畫,不是格子的矩形框:
  // 做法是先用白色貼幾份位移過的圖(只保留alpha輪廓),再疊上原圖蓋住中間
  void _drawOutlinedIcon(Canvas canvas, ui.Image icon, Rect dest) {
    final src = Rect.fromLTWH(0, 0, icon.width.toDouble(), icon.height.toDouble());
    final outlinePaint = Paint()
      ..filterQuality = FilterQuality.none
      ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn);
    const o = 2.5;
    for (final d in const [
      Offset(-o, 0), Offset(o, 0), Offset(0, -o), Offset(0, o),
      Offset(-o, -o), Offset(o, -o), Offset(-o, o), Offset(o, o),
    ]) {
      canvas.drawImageRect(icon, src, dest.shift(d), outlinePaint);
    }
    canvas.drawImageRect(icon, src, dest, Paint()..filterQuality = FilterQuality.none);
  }

  bool _visible(Point p) {
    if (!blind || snake.isEmpty) return true;
    final head = snake.first;
    final ahead1 = head + dir.delta;
    final ahead2 = ahead1 + dir.delta;
    return p == head || p == ahead1 || p == ahead2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / GameConfig.mapSize;
    final cellH = size.height / GameConfig.mapSize;
    final boardRect = Rect.fromLTWH(0, 0, size.width, size.height);
    // 放大後的障礙物/人物圖案可能蓋過地圖邊界外,裁切掉超出棋盤範圍的部分
    canvas.clipRect(boardRect);

    final bg = MapSprites.background;
    if (bg != null) {
      canvas.drawImageRect(
        bg,
        Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()),
        boardRect,
        Paint(),
      );
    } else {
      // 素材尚未載入完成時的備援畫法
      canvas.drawRect(boardRect, Paint()..color = const Color(0xFF10231A));
    }

    final obstacleIcons = MapSprites.obstacleIcons;
    for (final o in obstacles) {
      if (!_visible(o)) continue;
      final dest = _enlargedCell(o, cellW, cellH);
      if (obstacleIcons.isNotEmpty) {
        // 座標決定固定圖示,同一格每次重繪都一樣、整局不變動
        final icon = obstacleIcons[(o.x * 31 + o.y * 17).abs() % obstacleIcons.length];
        _drawOutlinedIcon(canvas, icon, dest);
      } else {
        // 素材尚未載入完成時的備援畫法
        canvas.drawRect(dest.deflate(math.min(cellW, cellH) * 0.3), Paint()..color = Colors.white54);
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
      final dest = _enlargedCell(p, cellW, cellH).deflate(7.5);
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
      for (var x = 0; x < GameConfig.mapSize; x++) {
        for (var y = 0; y < GameConfig.mapSize; y++) {
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
      old.obstacles != obstacles ||
      old.dir != dir ||
      old.blind != blind ||
      old.moveTick != moveTick;
}
