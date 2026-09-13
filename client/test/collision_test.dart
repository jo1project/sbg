import 'package:flutter_test/flutter_test.dart';
import 'package:snake_battle/game/collision.dart';
import 'package:snake_battle/models/game_map.dart';
import 'package:snake_battle/models/point.dart';

void main() {
  test('撞牆:座標超出地圖邊界(x:0~11, y:0~23)判定死亡(map為null時退化成只檢查邊界)', () {
    expect(checkDeath(const Point(-1, 5), const [], grow: false).cause, "wall");
    expect(checkDeath(const Point(12, 5), const [], grow: false).cause, "wall");
    expect(checkDeath(const Point(5, 24), const [], grow: false).cause, "wall");
    expect(checkDeath(const Point(11, 23), const [Point(11, 22)], grow: false).cause, null);
  });

  const testMap = GameMap(
    mapId: "test",
    gridCols: 12,
    gridRows: 24,
    rooms: [MapZone(x0: 1, x1: 10, y0: 1, y1: 4)],
    corridors: [],
    spawnPos: Point(5, 2),
    obstacles: [MapObstacle(Point(3, 3), "crate", null)],
  );

  test('撞牆:落在地圖的房間/走廊範圍之外(黑色虛空)也算撞牆,即使沒超出地圖邊界', () {
    expect(checkDeath(const Point(5, 2), const [], grow: false, map: testMap).cause, null, reason: "房間內部不算撞牆");
    expect(checkDeath(const Point(0, 2), const [], grow: false, map: testMap).cause, "wall", reason: "房間範圍外的地板內座標算撞牆");
    expect(checkDeath(const Point(5, 15), const [], grow: false, map: testMap).cause, "wall", reason: "沒有房間/走廊覆蓋的座標算撞牆");
  });

  test('撞自己:新頭落在身體格子上(不含即將讓出的尾巴)判定死亡', () {
    final body = [const Point(5, 5), const Point(5, 6), const Point(5, 7), const Point(5, 8)];
    // 移動到尾巴(5,8)那格:非成長時尾巴會讓出,不算死亡
    expect(checkDeath(const Point(5, 8), body, grow: false).cause, null);
    // 移動到中段(5,6):撞到自己身體,死亡
    expect(checkDeath(const Point(5, 6), body, grow: false).cause, "self");
    // 成長狀態下尾巴不會讓出,撞到尾巴也算死亡
    expect(checkDeath(const Point(5, 8), body, grow: true).cause, "self");
  });

  test('撞障礙物:新頭落在地圖障礙物座標上判定死亡', () {
    expect(checkDeath(const Point(3, 3), const [], grow: false, map: testMap).cause, "obstacle");
    expect(checkDeath(const Point(3, 4), const [], grow: false, map: testMap).cause, null);
  });

  const bigMonsterMap = GameMap(
    mapId: "test_big",
    gridCols: 12,
    gridRows: 24,
    rooms: [MapZone(x0: 0, x1: 11, y0: 0, y1: 23)],
    corridors: [],
    spawnPos: Point(5, 2),
    obstacles: [MapObstacle(Point(5, 5), "monster", "ogre", "big")],
  );

  test('撞障礙物:size為big的大型怪物素材是一般的兩倍寬,撞到多佔的右邊那格也算死亡', () {
    expect(checkDeath(const Point(5, 5), const [], grow: false, map: bigMonsterMap).cause, "obstacle", reason: "錨點格");
    expect(checkDeath(const Point(6, 5), const [], grow: false, map: bigMonsterMap).cause, "obstacle", reason: "多佔的footprint格");
    expect(checkDeath(const Point(4, 5), const [], grow: false, map: bigMonsterMap).cause, null, reason: "footprint以外不算撞到");
  });

  test('advanceSnake:非成長移除尾巴,成長保留尾巴', () {
    final body = [const Point(5, 5), const Point(5, 6), const Point(5, 7)];
    final moved = advanceSnake(body, const Point(5, 4), grow: false);
    expect(moved, [const Point(5, 4), const Point(5, 5), const Point(5, 6)]);

    final grown = advanceSnake(body, const Point(5, 4), grow: true);
    expect(grown, [const Point(5, 4), const Point(5, 5), const Point(5, 6), const Point(5, 7)]);
  });
}
