class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);

  Point operator +(Point o) => Point(x + o.x, y + o.y);

  @override
  bool operator ==(Object other) => other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  Map<String, dynamic> toJson() => {"x": x, "y": y};

  static Point? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final x = json["x"];
    final y = json["y"];
    if (x is! num || y is! num) return null;
    return Point(x.toInt(), y.toInt());
  }
}

enum Direction { up, down, left, right }

extension DirectionDelta on Direction {
  Point get delta => switch (this) {
        Direction.up => const Point(0, -1),
        Direction.down => const Point(0, 1),
        Direction.left => const Point(-1, 0),
        Direction.right => const Point(1, 0),
      };

  static bool areOpposite(Direction a, Direction b) {
    final d1 = a.delta;
    final d2 = b.delta;
    return d1.x == -d2.x && d1.y == -d2.y;
  }
}
