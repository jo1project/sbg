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
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _BoardPainter(
          snake: snake,
          foods: foods,
          obstacles: obstacles,
          dir: dir,
          blind: blind,
          moveTick: moveTick,
        ),
        child: Container(),
      ),
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

  // 格子中心不變,畫出來的圖案邊長是格子的 _spriteScale 倍,蓋過鄰近格子做放大效果
  Rect _enlargedCell(Point p, double cell) {
    final w = cell * _spriteScale;
    return Rect.fromLTWH(p.x * cell + cell / 2 - w / 2, p.y * cell + cell / 2 - w / 2, w, w);
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
    final cell = size.width / GameConfig.mapSize;
    final boardRect = Rect.fromLTWH(0, 0, size.width, size.height);

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
      final dest = _enlargedCell(o, cell);
      if (obstacleIcons.isNotEmpty) {
        // 座標決定固定圖示,同一格每次重繪都一樣、整局不變動
        final icon = obstacleIcons[(o.x * 31 + o.y * 17).abs() % obstacleIcons.length];
        _drawOutlinedIcon(canvas, icon, dest);
      } else {
        // 素材尚未載入完成時的備援畫法
        canvas.drawRect(dest.deflate(cell * 0.3), Paint()..color = Colors.white54);
      }
    }

    final foodPaint = Paint()..color = Colors.redAccent;
    for (final f in foods) {
      if (!_visible(f)) continue;
      canvas.drawCircle(Offset((f.x + 0.5) * cell, (f.y + 0.5) * cell), cell * 0.3, foodPaint);
    }

    final frameCol = CharacterSprites.walkFrameCols[moveTick % CharacterSprites.walkFrameCols.length];
    // 從蛇尾畫到蛇頭,確保蛇頭(放大後)蓋在身體上面而不是被身體蓋住
    for (var i = snake.length - 1; i >= 0; i--) {
      final p = snake[i];
      if (!_visible(p)) continue;
      // 蛇頭永遠面向實際移動方向;蛇身每一節面向「朝前一節」的方向,做出跟隨感
      final segDir = i == 0 ? dir : DirectionDelta.fromDelta(snake[i - 1] - p);
      final sprite = i == 0 ? CharacterSprites.hero : CharacterSprites.goblin;
      final dest = _enlargedCell(p, cell);
      if (sprite == null) {
        // 素材尚未載入完成時的備援畫法
        final paint = Paint()..color = i == 0 ? Colors.lightGreenAccent : Colors.green;
        canvas.drawRRect(RRect.fromRectAndRadius(dest.deflate(cell * 0.5), const Radius.circular(3)), paint);
        continue;
      }
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
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), maskPaint);
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
