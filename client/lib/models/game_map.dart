import 'point.dart';

// 地圖的一塊矩形可通行範圍(房間或走廊),座標含頭尾(inclusive),對應伺服器地圖JSON格式(規格文件7.7節)。
class MapZone {
  final int x0, x1, y0, y1;
  const MapZone({required this.x0, required this.x1, required this.y0, required this.y1});

  bool contains(Point p) => p.x >= x0 && p.x <= x1 && p.y >= y0 && p.y <= y1;

  static MapZone? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final x0 = j["x0"], x1 = j["x1"], y0 = j["y0"], y1 = j["y1"];
    if (x0 is! num || x1 is! num || y0 is! num || y1 is! num) return null;
    return MapZone(x0: x0.toInt(), x1: x1.toInt(), y0: y0.toInt(), y1: y1.toInt());
  }
}

// type: crate | column | chest | monster;species 只有 monster 才有值(見規格文件7.7節)
// size: "big" 的大型怪物(big_demon/big_zombie/ogre)素材寬度是一般怪物的兩倍,
// 水平方向多佔右邊一格,碰撞/繪製都要涵蓋整個 cells(見 game/collision.dart、widgets/board.dart)
class MapObstacle {
  final Point pos;
  final String type;
  final String? species;
  final String? size;
  const MapObstacle(this.pos, this.type, this.species, [this.size]);

  List<Point> get cells => size == "big" ? [pos, Point(pos.x + 1, pos.y)] : [pos];

  static MapObstacle? fromJson(Map<String, dynamic>? j) {
    final pos = Point.fromJson(j);
    if (pos == null || j == null) return null;
    return MapObstacle(pos, j["type"] as String? ?? "crate", j["species"] as String?, j["size"] as String?);
  }
}

// 固定地圖池的一張地圖(伺服器 obstacle_layout 事件送整包給該玩家自己,見規格文件2.3/7.7節)
class GameMap {
  final String mapId;
  final int gridCols;
  final int gridRows;
  final List<MapZone> rooms;
  final List<MapZone> corridors;
  final Point spawnPos;
  final List<MapObstacle> obstacles;

  const GameMap({
    required this.mapId,
    required this.gridCols,
    required this.gridRows,
    required this.rooms,
    required this.corridors,
    required this.spawnPos,
    required this.obstacles,
  });

  // 房間或走廊範圍內才是可通行地板,以外一律是黑色虛空/牆體(見規格文件7.7節)
  bool isWalkable(Point p) => rooms.any((z) => z.contains(p)) || corridors.any((z) => z.contains(p));

  static GameMap? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final spawnPos = Point.fromJson(j["spawnPos"] as Map<String, dynamic>?);
    if (spawnPos == null) return null;
    return GameMap(
      mapId: j["mapId"] as String? ?? "",
      gridCols: (j["gridCols"] as num?)?.toInt() ?? 0,
      gridRows: (j["gridRows"] as num?)?.toInt() ?? 0,
      rooms: (j["rooms"] as List<dynamic>?)?.map((e) => MapZone.fromJson(e as Map<String, dynamic>?)).whereType<MapZone>().toList() ?? const [],
      corridors: (j["corridors"] as List<dynamic>?)?.map((e) => MapZone.fromJson(e as Map<String, dynamic>?)).whereType<MapZone>().toList() ?? const [],
      obstacles: (j["obstacles"] as List<dynamic>?)?.map((e) => MapObstacle.fromJson(e as Map<String, dynamic>?)).whereType<MapObstacle>().toList() ?? const [],
      spawnPos: spawnPos,
    );
  }
}
