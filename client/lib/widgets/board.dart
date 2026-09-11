import 'package:flutter/material.dart';
import '../config.dart';
import '../models/point.dart';

// 棋盤繪製:格線 + 蛇身 + 食物。blind 效果時只露出蛇頭前方兩格,其餘蓋黑。
class Board extends StatelessWidget {
  final List<Point> snake;
  final List<Point> foods;
  final Direction dir;
  final bool blind;

  const Board({
    super.key,
    required this.snake,
    required this.foods,
    required this.dir,
    required this.blind,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _BoardPainter(snake: snake, foods: foods, dir: dir, blind: blind),
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

  _BoardPainter({required this.snake, required this.foods, required this.dir, required this.blind});

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

    for (var i = 0; i < snake.length; i++) {
      final p = snake[i];
      if (!_visible(p)) continue;
      final paint = Paint()..color = i == 0 ? Colors.lightGreenAccent : Colors.green;
      final rect = Rect.fromLTWH(p.x * cell + 1, p.y * cell + 1, cell - 2, cell - 2);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), paint);
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
      old.snake != snake || old.foods != foods || old.dir != dir || old.blind != blind;
}
