import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/game_map.dart';
import '../models/point.dart';
import '../net/socket_service.dart';
import 'collision.dart';

enum ConnStatus { disconnected, connecting, connected }

enum MatchStatus { idle, waitingQueue, waitingInviteSent, inRoom }

class ActiveEffect {
  final String type; // pause | blind | speedup
  final DateTime endsAt;
  ActiveEffect(this.type, this.endsAt);
}

class IncomingAttack {
  final String attackId;
  final String attackerId;
  final int dodgeWindowMs;
  IncomingAttack(this.attackId, this.attackerId, this.dodgeWindowMs);
}

class GameOverResult {
  final String reason;
  final String? winnerId;
  final bool draw;
  GameOverResult(this.reason, this.winnerId, this.draw);
}

// 整個對戰的狀態機 + 本地預測邏輯,對應規格文件第7章的協定。
// UI 只讀這裡的欄位 + 呼叫這裡的方法,不直接碰 SocketService。
class GameController extends ChangeNotifier {
  final _socket = SocketService();
  Timer? _moveTimer;
  Timer? _positionSyncTimer;
  Timer? _pingTimer;
  Timer? _disconnectCountdownTimer;
  Timer? _bannerClearTimer;
  Timer? _preGameCountdownTimer;

  ConnStatus connStatus = ConnStatus.disconnected;
  MatchStatus matchStatus = MatchStatus.idle;

  String? playerId;
  String? recoveryCode; // 只在剛建立新帳號時有值一次,UI顯示後應呼叫 clearRecoveryCode()

  String? opponentId;
  String? incomingInviteFromId; // 收到別人邀請待回應
  List<String> recentOpponents = []; // 連線記錄:曾經對戰過的對象ID,最新的在最前面
  String? banner; // 一次性訊息(邀請失敗/攻擊被拒/連線異常等),顯示後淡出

  double myEnergy = 0;
  double oppEnergy = 0;

  List<Point> mySnake = const [];
  Direction dir = Direction.right;
  Direction? _pendingDir;
  int _growthPending = 0;
  int moveTick = 0; // 每次實際移動+1,驅動走路動畫的欄位切換(見 CharacterSprites)
  int? countdown; // 對戰開始前的3-2-1倒數,見 _startPreGameCountdown;null代表倒數已結束/未開始

  final Map<String, Point> myFoods = {};
  GameMap? map; // 固定地圖池抽到的地圖,伺服器房間建立時一次性推送,整局不變動,見 room.js sendMapToPlayer
  Point? oppFuzzyPos;

  ActiveEffect? myEffect;
  final Map<String, String> _attackerByAttackId = {}; // attackId -> attackerId
  bool pendingOutgoingAttack = false;
  IncomingAttack? incomingAttack;

  int? opponentDisconnectGraceSec;
  bool _frozenByDisconnect = false;

  GameOverResult? gameOver;

  // 攻擊命中(非閃躲)時,雙方畫面都短暫顯示橫幅圖片,見 _triggerAttackHitBanner
  bool showAttackHitBanner = false;
  int _attackHitToken = 0;

  bool get isPaused => myEffect != null && myEffect!.type == "pause" && myEffect!.endsAt.isAfter(DateTime.now());
  bool get isBlind => myEffect != null && myEffect!.type == "blind" && myEffect!.endsAt.isAfter(DateTime.now());
  bool get isSpeedup => myEffect != null && myEffect!.type == "speedup" && myEffect!.endsAt.isAfter(DateTime.now());

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    playerId = prefs.getString("playerId");
    recentOpponents = prefs.getStringList("recentOpponents") ?? [];
  }

  Future<void> _recordOpponent(String id) async {
    recentOpponents.remove(id);
    recentOpponents.insert(0, id);
    if (recentOpponents.length > 10) recentOpponents = recentOpponents.sublist(0, 10);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("recentOpponents", recentOpponents);
    notifyListeners();
  }

  Future<void> connectAndIdentify() async {
    connStatus = ConnStatus.connecting;
    notifyListeners();
    try {
      await _socket.connect(GameConfig.serverUrl);
    } catch (_) {
      connStatus = ConnStatus.disconnected;
      _setBanner("連線失敗,請檢查網路連線");
      notifyListeners();
      return;
    }
    _socket.messages.listen(_onMessage);
    _socket.onDone.listen((_) => _onDisconnected());
    connStatus = ConnStatus.connected;
    _socket.send(Ev.identify, playerId == null ? {} : {"playerId": playerId});
    _startPing();
  }

  void _onDisconnected() {
    connStatus = ConnStatus.disconnected;
    _stopMatchTimers();
    notifyListeners();
  }

  void restoreAccount(String code) {
    _socket.send(Ev.restoreAccount, {"recoveryCode": code});
  }

  void clearRecoveryCode() {
    recoveryCode = null;
    notifyListeners();
  }

  void clearBanner() {
    _bannerClearTimer?.cancel();
    banner = null;
    notifyListeners();
  }

  // 所有一次性訊息都走這裡設定,自動幾秒後清除,避免卡在畫面上蓋到下一個狀態
  // (例如回大廳後還顯示上一場的攻擊結果)。
  void _setBanner(String text, {Duration duration = const Duration(seconds: 3)}) {
    banner = text;
    _bannerClearTimer?.cancel();
    _bannerClearTimer = Timer(duration, () {
      banner = null;
      notifyListeners();
    });
  }

  // ---------- 配對 ----------

  void joinQueue() {
    _socket.send(Ev.joinQueue);
    matchStatus = MatchStatus.waitingQueue;
    notifyListeners();
  }

  void challengeFriend(String targetId) {
    _socket.send(Ev.challengeFriend, {"targetPlayerId": targetId});
  }

  void acceptInvite() {
    _socket.send(Ev.inviteAccept);
    incomingInviteFromId = null;
  }

  void rejectInvite() {
    _socket.send(Ev.inviteReject);
    incomingInviteFromId = null;
    notifyListeners();
  }

  void cancelInvite() {
    _socket.send(Ev.inviteCancel);
    matchStatus = MatchStatus.idle;
    notifyListeners();
  }

  // ---------- 對戰中操作 ----------

  void setDirection(Direction next) {
    if (isPaused) return;
    if (DirectionDelta.areOpposite(dir, next)) return; // 不能直接反向自撞
    _pendingDir = next;
  }

  void attack(String attackType) {
    if (pendingOutgoingAttack || isPaused) return;
    pendingOutgoingAttack = true;
    notifyListeners();
    _socket.send(Ev.attackRequest, {
      "attackType": attackType,
      "clientTime": DateTime.now().millisecondsSinceEpoch,
    });
  }

  void tryDodge() {
    final atk = incomingAttack;
    if (atk == null) return;
    _socket.send(Ev.dodgeAttempt, {
      "attackId": atk.attackId,
      "clientActionTime": DateTime.now().millisecondsSinceEpoch,
    });
    incomingAttack = null;
    notifyListeners();
  }

  void leaveRoom() {
    _socket.send(Ev.leaveRoom);
    _resetMatchState();
  }

  void backToLobbyAfterGameOver() {
    _resetMatchState();
  }

  // ---------- 訊息處理 ----------

  void _onMessage(Map<String, dynamic> msg) {
    final type = msg["type"];
    switch (type) {
      case Ev.identified:
        playerId = msg["playerId"] as String?;
        _persistPlayerId();
        if (msg["recoveryCode"] != null) recoveryCode = msg["recoveryCode"] as String;
        break;

      case Ev.accountRestored:
        playerId = msg["playerId"] as String?;
        _persistPlayerId();
        _socket.send(Ev.identify, {"playerId": playerId});
        break;

      case Ev.restoreFailed:
        _setBanner("還原碼查無資料");
        break;

      case Ev.matchWaiting:
        matchStatus = MatchStatus.waitingQueue;
        break;

      case Ev.inviteSent:
        matchStatus = MatchStatus.waitingInviteSent;
        break;

      case Ev.inviteReceived:
        incomingInviteFromId = msg["fromPlayerId"] as String?;
        break;

      case Ev.inviteFailed:
        _setBanner("邀請失敗:${msg["reason"]}");
        matchStatus = MatchStatus.idle;
        break;

      case Ev.inviteRejected:
        _setBanner("對方拒絕了邀請");
        matchStatus = MatchStatus.idle;
        break;

      case Ev.inviteTimeout:
        _setBanner("邀請逾時未回應");
        matchStatus = MatchStatus.idle;
        incomingInviteFromId = null;
        break;

      case Ev.inviteCancelled:
        _setBanner("對方已撤回邀請");
        incomingInviteFromId = null;
        break;

      case Ev.matchFound:
        opponentId = msg["opponentId"] as String?;
        if (opponentId != null) _recordOpponent(opponentId!);
        _startMatch();
        break;

      case Ev.energyUpdate:
        final pid = msg["playerId"];
        final energy = (msg["energy"] as num).toDouble();
        if (pid == playerId) {
          myEnergy = energy;
        } else {
          oppEnergy = energy;
        }
        break;

      case Ev.foodSpawned:
        final foodId = msg["foodId"] as String;
        final pos = Point.fromJson(msg["position"] as Map<String, dynamic>?);
        if (pos != null) myFoods[foodId] = pos;
        break;

      case Ev.obstacleLayout:
        final parsed = GameMap.fromJson(msg["map"] as Map<String, dynamic>?);
        if (parsed != null) map = parsed;
        break;

      case Ev.opponentPositionFuzzy:
        oppFuzzyPos = Point.fromJson(msg["position"] as Map<String, dynamic>?);
        break;

      case Ev.attackIncoming:
        final attackId = msg["attackId"] as String;
        final attackerId = msg["attackerId"] as String;
        final windowMs = (msg["dodgeWindowMs"] as num).toInt();
        _attackerByAttackId[attackId] = attackerId;
        if (attackerId != playerId) {
          incomingAttack = IncomingAttack(attackId, attackerId, windowMs);
          HapticFeedback.heavyImpact();
          Timer(Duration(milliseconds: windowMs + 100), () {
            if (incomingAttack?.attackId == attackId) {
              incomingAttack = null;
              notifyListeners();
            }
          });
        }
        break;

      case Ev.attackResult:
        _handleAttackResult(msg);
        break;

      case Ev.attackRejected:
        pendingOutgoingAttack = false;
        _setBanner("攻擊未成立:${msg["reason"]}");
        break;

      case Ev.selfPausedBySpam:
        final durationMs = (msg["durationMs"] as num).toInt();
        myEffect = ActiveEffect("pause", DateTime.now().add(Duration(milliseconds: durationMs)));
        _setBanner("連續被閃躲,自己暫停${durationMs ~/ 1000}秒");
        break;

      case Ev.deathReportRejected:
        _setBanner("死亡回報未通過伺服器驗證,已返回大廳");
        _resetMatchState();
        break;

      case Ev.opponentDisconnected:
        final graceMs = (msg["graceMs"] as num).toInt();
        _startDisconnectCountdown(graceMs);
        break;

      case Ev.opponentReconnected:
        _frozenByDisconnect = false;
        opponentDisconnectGraceSec = null;
        _disconnectCountdownTimer?.cancel();
        break;

      case Ev.gameOver:
        gameOver = GameOverResult(
          msg["reason"] as String,
          msg["winnerId"] as String?,
          msg["draw"] == true,
        );
        _stopMatchTimers();
        break;

      case Ev.error:
        _setBanner(msg["message"]?.toString() ?? "發生未知錯誤");
        break;
    }
    notifyListeners();
  }

  void _handleAttackResult(Map<String, dynamic> msg) {
    final attackId = msg["attackId"] as String;
    final attackerId = _attackerByAttackId.remove(attackId);
    final iAmAttacker = attackerId == playerId;
    final iAmDefender = attackerId != null && !iAmAttacker;
    final dodged = msg["dodged"] == true;

    if (iAmAttacker) pendingOutgoingAttack = false;
    incomingAttack = null;

    if (dodged) {
      _setBanner(iAmAttacker ? "對方閃躲成功" : "閃躲成功!");
      return;
    }

    _triggerAttackHitBanner();

    final effectType = msg["effectType"] as String?;
    if (effectType == "direct_lengthen") {
      if (iAmDefender) {
        _growthPending += (msg["lengthenBy"] as num).toInt();
      }
      _setBanner(iAmAttacker ? "命中!對手變長了" : "被直接攻擊命中,身體變長了");
      return;
    }

    // random 效果類:speedup / pause / blind,預告 previewDelayMs 後才生效,只套用在防守方
    final durationMs = (msg["effectDuration"] as num?)?.toInt() ?? 0;
    final previewDelayMs = (msg["previewDelayMs"] as num?)?.toInt() ?? 0;
    _setBanner(iAmAttacker ? "命中!對手即將受到 $effectType 效果" : "即將發動:$effectType 效果");
    if (iAmDefender && effectType != null) {
      Timer(Duration(milliseconds: previewDelayMs), () {
        myEffect = ActiveEffect(effectType, DateTime.now().add(Duration(milliseconds: durationMs)));
        notifyListeners();
      });
    }
  }

  // 攻擊命中橫幅:用token讓連續命中時,舊的隱藏Timer不會把新的一次提早關掉
  void _triggerAttackHitBanner() {
    _attackHitToken++;
    final token = _attackHitToken;
    showAttackHitBanner = true;
    Timer(const Duration(milliseconds: 2000), () {
      if (_attackHitToken == token) {
        showAttackHitBanner = false;
        notifyListeners();
      }
    });
  }

  Future<void> _persistPlayerId() async {
    final prefs = await SharedPreferences.getInstance();
    if (playerId != null) await prefs.setString("playerId", playerId!);
  }

  // ---------- 對戰生命週期 ----------

  void _startMatch() {
    matchStatus = MatchStatus.inRoom;
    gameOver = null;
    myEnergy = 0;
    oppEnergy = 0;
    // 注意:伺服器在 match_found 之前就會送 food_spawned / obstacle_layout(Room建構時),
    // 這裡不能清 myFoods / map,否則會把剛到的初始資料清掉
    oppFuzzyPos = null;
    myEffect = null;
    _growthPending = 0;
    moveTick = 0;
    pendingOutgoingAttack = false;
    incomingAttack = null;
    _attackerByAttackId.clear();
    _frozenByDisconnect = false;
    opponentDisconnectGraceSec = null;
    showAttackHitBanner = false;

    // 重生點固定在該玩家抽到的地圖房間內(見map.spawnPos);map理應已在match_found之前送達,
    // 萬一還沒到(不應發生)就退回地圖正中央,避免蛇身座標缺值
    final start = map?.spawnPos ?? Point(GameConfig.mapWidth ~/ 2, GameConfig.mapHeight ~/ 2);
    dir = Direction.right;
    _pendingDir = null;
    mySnake = List.generate(GameConfig.initialSnakeLength, (i) => Point(start.x - i, start.y));

    _startPreGameCountdown();
  }

  // 對戰畫面(棋盤/雙方初始蛇身)先完整顯示,倒數3-2-1結束才真的開始移動+回報位置,
  // 純client端各自倒數,不等伺服器同步(誤差最多一次網路延遲,不影響對戰公平性)。
  void _startPreGameCountdown() {
    _preGameCountdownTimer?.cancel();
    countdown = 3;
    _preGameCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (countdown ?? 1) - 1;
      if (left <= 0) {
        t.cancel();
        countdown = null;
        _startMoveLoop();
        _startPositionSync();
      } else {
        countdown = left;
      }
      notifyListeners();
    });
  }

  void _resetMatchState() {
    matchStatus = MatchStatus.idle;
    opponentId = null;
    gameOver = null;
    myFoods.clear();
    map = null;
    _bannerClearTimer?.cancel();
    banner = null;
    countdown = null;
    _stopMatchTimers();
    notifyListeners();
  }

  void _startMoveLoop() {
    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(
      Duration(milliseconds: isSpeedup ? GameConfig.speedupTickMs : GameConfig.moveTickMs),
      (_) => _tick(),
    );
  }

  void _tick() {
    // 加速/效果結束會改變移動間隔,每次 tick 都檢查一次是否要重建 timer
    final wantMs = isSpeedup ? GameConfig.speedupTickMs : GameConfig.moveTickMs;
    if (wantMs != _lastTickMs) {
      _lastTickMs = wantMs;
      _startMoveLoop();
    }

    // 攻擊命中橫幅顯示期間(見_triggerAttackHitBanner),雙方都暫停移動,
    // 讓橫幅播完這段時間畫面上的蛇不會動,兩邊感受一致。
    if (isPaused || _frozenByDisconnect || showAttackHitBanner) {
      notifyListeners();
      return;
    }

    final nextDir = _pendingDir ?? dir;
    _pendingDir = null;
    final head = mySnake.first;
    final newHead = head + nextDir.delta;
    final grow = _growthPending > 0;

    final death = checkDeath(newHead, mySnake, grow: grow, map: map);
    if (death.isDead) {
      _moveTimer?.cancel();
      _socket.send(Ev.deathReport, {
        "cause": death.cause,
        "headPos": newHead.toJson(),
        "bodyCells": mySnake.map((p) => p.toJson()).toList(),
      });
      // 保險:萬一 death_report 的回應(game_over / death_report_rejected)因網路問題
      // 沒送達,不能讓玩家永遠卡死在畫面上動不了,逾時就強制回大廳
      Timer(const Duration(seconds: 5), () {
        if (matchStatus == MatchStatus.inRoom && gameOver == null) {
          _setBanner("連線異常,已返回大廳");
          _resetMatchState();
        }
      });
      notifyListeners();
      return;
    }

    dir = nextDir;
    mySnake = advanceSnake(mySnake, newHead, grow: grow);
    if (grow) _growthPending--;
    moveTick++;

    final eatenId = myFoods.entries.where((e) => e.value == newHead).map((e) => e.key).firstOrNull;
    if (eatenId != null) {
      myFoods.remove(eatenId);
      myEnergy += 1; // 樂觀預測,稍後由 energy_update 校正權威值
      _socket.send(Ev.foodEatenRequest, {"foodId": eatenId, "headPos": newHead.toJson()});
    }

    notifyListeners();
  }

  int _lastTickMs = GameConfig.moveTickMs;

  void _startPositionSync() {
    _positionSyncTimer?.cancel();
    _positionSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mySnake.isEmpty) return;
      _socket.send(Ev.snakePositionUpdate, {
        "headPos": mySnake.first.toJson(),
        "bodyCells": mySnake.map((p) => p.toJson()).toList(),
      });
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _socket.send(Ev.ping, {"clientTime": DateTime.now().millisecondsSinceEpoch});
    });
  }

  void _startDisconnectCountdown(int graceMs) {
    _disconnectCountdownTimer?.cancel();
    _frozenByDisconnect = true;
    opponentDisconnectGraceSec = (graceMs / 1000).ceil();
    _disconnectCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (opponentDisconnectGraceSec ?? 1) - 1;
      opponentDisconnectGraceSec = left;
      if (left <= 0) t.cancel();
      notifyListeners();
    });
  }

  void _stopMatchTimers() {
    _moveTimer?.cancel();
    _positionSyncTimer?.cancel();
    _disconnectCountdownTimer?.cancel();
    _preGameCountdownTimer?.cancel();
  }

  @override
  void dispose() {
    _stopMatchTimers();
    _pingTimer?.cancel();
    _bannerClearTimer?.cancel();
    _socket.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
