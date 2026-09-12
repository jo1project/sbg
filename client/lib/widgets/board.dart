import 'package:flutter/material.dart';
import '../config.dart';
import '../game/character_sprites.dart';
import '../models/point.dart';

// 棋盤繪製:格線 + 蛇身 + 食物。blind 效果時只露出蛇頭前方兩格,其餘蓋黑。
class Board extends StatelessWidget {
  final List<Point> snake;
  final List<Point> foods;
  final Direction dir;
  final bool blind;
  final int moveTick;

  const Board({
    super.key,
    required this.snake,
    required this.foods,
    required this.dir,
    required this.blind,
    required this.moveTick,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _BoardPainter(snake: snake, foods: foods, dir: dir, blind: blind, moveTick: moveTick),
        child: Container(),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  final List<Point> snake;
  final List<Point> foods;
  final Direction dir;
  final bool blind;
  final int moveTick;

  _BoardPainter({
    required this.snake,
    required this.foods,
    required this.dir,
    required this.blind,
    required this.moveTick,
  });

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
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF10231A));
    for (var i = 0; i <= GameConfig.mapSize; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), gridPaint);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), gridPaint);
    }

    final foodPaint = Paint()..color = Colors.redAccent;
    for (final f in foods) {
      if (!_visible(f)) continue;
      canvas.drawCircle(Offset((f.x + 0.5) * cell, (f.y + 0.5) * cell), cell * 0.3, foodPaint);
    }

    final frameCol = CharacterSprites.walkFrameCols[moveTick % CharacterSprites.walkFrameCols.length];
    for (var i = 0; i < snake.length; i++) {
      final p = snake[i];
      if (!_visible(p)) continue;
      // 蛇頭永遠面向實際移動方向;蛇身每一節面向「朝前一節」的方向,做出跟隨感
      final segDir = i == 0 ? dir : DirectionDelta.fromDelta(snake[i - 1] - p);
      final sprite = i == 0 ? CharacterSprites.hero : CharacterSprites.goblin;
      final dest = Rect.fromLTWH(p.x * cell, p.y * cell, cell, cell);
      if (sprite == null) {
        // 素材尚未載入完成時的備援畫法
        final paint = Paint()..color = i == 0 ? Colors.lightGreenAccent : Colors.green;
        canvas.drawRRect(RRect.fromRectAndRadius(dest.deflate(1), const Radius.circular(3)), paint);
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
      old.dir != dir ||
      old.blind != blind ||
      old.moveTick != moveTick;
}
