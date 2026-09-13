import 'package:flutter/material.dart';
import '../config.dart';
import '../game/game_controller.dart';
import '../models/point.dart';
import '../widgets/board.dart';
import '../widgets/energy_bar.dart';
import '../widgets/joystick.dart';
import '../widgets/attack_button.dart';

class GameScreen extends StatelessWidget {
  final GameController c;
  const GameScreen({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1712),
      body: SafeArea(
        // 地圖滿版鋪整個畫面,能量條/搖桿/攻擊鍵都是半透明浮在地圖上面的overlay,
        // 不再用Column把畫面切成一塊一塊、把地圖擠成中間一個正方形留大片黑邊。
        // LayoutBuilder包住Stack才能拿到跟Board的CustomPaint一致的畫面尺寸,
        // 用來換算_AttackCrosshairIndicator該疊在蛇頭正上方哪個像素位置(見該widget)。
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: c.incomingAttack != null ? Colors.redAccent : Colors.transparent,
                        width: 4,
                      ),
                    ),
                    child: Board(
                      snake: c.mySnake,
                      foods: c.myFoods.values.toList(),
                      map: c.map,
                      dir: c.dir,
                      blind: c.isBlind,
                      moveTick: c.moveTick,
                    ),
                  ),
                ),
                Positioned(top: 0, left: 0, right: 0, child: _TopBar(c: c)),
                Positioned(bottom: 0, left: 0, right: 0, child: _BottomBelt(c: c)),
                _AttackHitBanner(show: c.showAttackHitBanner, screenWidth: constraints.maxWidth),
                if (c.opponentDisconnectGraceSec != null) _DisconnectBanner(sec: c.opponentDisconnectGraceSec!),
                if (c.incomingAttack != null) const _DodgeAlert(),
                if (c.incomingAttack != null && c.mySnake.isNotEmpty)
                  _AttackCrosshairIndicator(headPos: c.mySnake.first, boardSize: constraints.biggest),
                if (c.banner != null) _Banner(text: c.banner!, onClose: c.clearBanner),
                if (c.gameOver != null) _GameOverOverlay(c: c),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final GameController c;
  const _TopBar({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black45, // 浮在地圖上面,加半透明底色避免看不清楚文字
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnergyBar(label: "你", energy: c.myEnergy, mine: true),
          const Spacer(),
          _MiniMap(pos: c.oppFuzzyPos),
          const Spacer(),
          EnergyBar(label: "對手", energy: c.oppEnergy, mine: false),
        ],
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  final Point? pos;
  const _MiniMap({required this.pos});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: pos == null
          ? null
          : CustomPaint(painter: _DotPainter(pos!.x / GameConfig.mapWidth, pos!.y / GameConfig.mapHeight)),
    );
  }
}

class _DotPainter extends CustomPainter {
  final double fx;
  final double fy;
  _DotPainter(this.fx, this.fy);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(fx.clamp(0, 1) * size.width, fy.clamp(0, 1) * size.height),
      4,
      Paint()..color = Colors.amberAccent,
    );
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) => old.fx != fx || old.fy != fy;
}

class _BottomBelt extends StatelessWidget {
  final GameController c;
  const _BottomBelt({required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AttackButton(
            icon: Icons.flash_on,
            tooltip: "直接攻擊 · 對手變長",
            disabled: c.pendingOutgoingAttack,
            onTap: () => c.attack("direct"),
          ),
          Joystick(onDirection: c.setDirection, onRelease: c.tryDodge),
          AttackButton(
            icon: Icons.casino,
            tooltip: "隨機效果 · 加速/暫停/致盲",
            disabled: c.pendingOutgoingAttack,
            onTap: () => c.attack("random"),
          ),
        ],
      ),
    );
  }
}

class _DisconnectBanner extends StatelessWidget {
  final int sec;
  const _DisconnectBanner({required this.sec});
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
          child: Text("對手連線中斷,等待重連... $sec", style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

// 攻擊來襲時,除了畫面邊緣的紅框(見上方DecoratedBox),額外在被攻擊方(自己)的蛇頭
// 正上方疊一個閃爍的瞄準圖案(Kenney Crosshair Pack, CC0授權),雙重提示更醒目。
// 只在有incomingAttack時才會被mount,State的生命週期跟著攻擊視窗自動開始/結束,
// 不需要另外在GameController裡管理blink計時器。
class _AttackCrosshairIndicator extends StatefulWidget {
  final Point headPos;
  final Size boardSize;
  const _AttackCrosshairIndicator({required this.headPos, required this.boardSize});

  @override
  State<_AttackCrosshairIndicator> createState() => _AttackCrosshairIndicatorState();
}

class _AttackCrosshairIndicatorState extends State<_AttackCrosshairIndicator> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    final cellW = widget.boardSize.width / GameConfig.mapWidth;
    final cellH = widget.boardSize.height / GameConfig.mapHeight;
    final left = widget.headPos.x * cellW + cellW / 2 - size / 2;
    final top = widget.headPos.y * cellH - size; // 貼著蛇頭那一格的上緣,往上疊
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: Image.asset('assets/ui/crosshair.png', width: size, height: size),
        ),
      ),
    );
  }
}

class _DodgeAlert extends StatelessWidget {
  const _DodgeAlert();
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 140,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(10)),
        child: const Text(
          "⚡ 被攻擊了!放開搖桿閃躲",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// 攻擊命中時橫幅圖片從畫面中央的右邊滑入,經過中央短暫停留後繼續往左滑出畫面
// (見GameController.showAttackHitBanner)。用一個2秒的AnimationController跑完整段
// 「進場(右→中)→停留→出場(中→左)」,在show從false翻true的當下觸發一次,
// 不像舊版(從上方滑入/退回)只是在show和false兩個位置之間來回。
class _AttackHitBanner extends StatefulWidget {
  final bool show;
  final double screenWidth;
  const _AttackHitBanner({required this.show, required this.screenWidth});

  @override
  State<_AttackHitBanner> createState() => _AttackHitBannerState();
}

class _AttackHitBannerState extends State<_AttackHitBanner> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
  late final _position = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 25),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant _AttackHitBanner old) {
    super.didUpdateWidget(old);
    if (widget.show && !old.show) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _position,
        builder: (context, child) => Center(
          child: Transform.translate(
            offset: Offset(_position.value * widget.screenWidth, 0),
            child: child,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AspectRatio(
            aspectRatio: 900 / 340,
            child: Image.asset("assets/sprites/attack_banner.png", fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const _Banner({required this.text, required this.onClose});
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text(text, style: const TextStyle(color: Colors.white))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 16), onPressed: onClose),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  final GameController c;
  const _GameOverOverlay({required this.c});

  @override
  Widget build(BuildContext context) {
    final result = c.gameOver!;
    final draw = result.draw;
    final won = !draw && result.winnerId == c.playerId;
    final text = draw ? "平手(Double KO)" : (won ? "你贏了!" : "你輸了");
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: c.backToLobbyAfterGameOver, child: const Text("返回大廳")),
            ],
          ),
        ),
      ),
    );
  }
}
