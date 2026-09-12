import '../config.dart';
import '../models/point.dart';

// 純邏輯,不依賴 Flutter,方便寫 test。對應伺服器 room.js 的 validateDeathReport 邏輯,
// 客戶端在本地先行判定死亡(6.1節:客戶端判定、伺服器驗證後採信)。
class DeathCheck {
  final String? cause; // "wall" | "self" | "obstacle" | null(沒死)
  const DeathCheck(this.cause);
  bool get isDead => cause != null;
}

// body 是移動前的完整蛇身(index 0為頭)。尾巴這一格在非成長移動時會讓出,
// 所以不算撞自己;成長時尾巴不動,要算進碰撞檢查。
// obstacles 是伺服器在房間建立時生成、只給這位玩家自己的障礙物座標(見 GameController.obstacles)。
DeathCheck checkDeath(Point newHead, List<Point> body, {required bool grow, List<Point> obstacles = const []}) {
  if (newHead.x < 0 || newHead.x >= GameConfig.mapWidth || newHead.y < 0 || newHead.y >= GameConfig.mapHeight) {
    return const DeathCheck("wall");
  }
  final bodyToCheck = grow ? body : body.sublist(0, body.length - 1);
  if (bodyToCheck.contains(newHead)) {
    return const DeathCheck("self");
  }
  if (obstacles.contains(newHead)) {
    return const DeathCheck("obstacle");
  }
  return const DeathCheck(null);
}

// 蛇移動一格:不含成長時把尾巴移除,成長時保留尾巴(整條變長1格)。
// 回傳新的身體(含新頭,index 0 為頭)。
List<Point> advanceSnake(List<Point> body, Point newHead, {required bool grow}) {
  final next = [newHead, ...body];
  if (!grow) next.removeLast();
  return next;
}
