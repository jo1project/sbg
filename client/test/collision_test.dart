import 'package:flutter_test/flutter_test.dart';
import 'package:snake_battle/game/collision.dart';
import 'package:snake_battle/models/point.dart';

void main() {
  test('撞牆:座標超出地圖邊界(0~19)判定死亡', () {
    expect(checkDeath(const Point(-1, 5), const [], grow: false).cause, "wall");
    expect(checkDeath(const Point(20, 5), const [], grow: false).cause, "wall");
    expect(checkDeath(const Point(5, 20), const [], grow: false).cause, "wall");
    expect(checkDeath(const Point(19, 19), const [Point(19, 18)], grow: false).cause, null);
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

  test('advanceSnake:非成長移除尾巴,成長保留尾巴', () {
    final body = [const Point(5, 5), const Point(5, 6), const Point(5, 7)];
    final moved = advanceSnake(body, const Point(5, 4), grow: false);
    expect(moved, [const Point(5, 4), const Point(5, 5), const Point(5, 6)]);

    final grown = advanceSnake(body, const Point(5, 4), grow: true);
    expect(grown, [const Point(5, 4), const Point(5, 5), const Point(5, 6), const Point(5, 7)]);
  });
}
