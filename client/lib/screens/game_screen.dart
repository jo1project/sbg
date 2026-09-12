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
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(c: c),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
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
                          dir: c.dir,
                          blind: c.isBlind,
                          moveTick: c.moveTick,
                        ),
                      ),
                    ),
                  ),
                ),
                _BottomBelt(c: c),
              ],
            ),
            if (c.opponentDisconnectGraceSec != null) _DisconnectBanner(sec: c.opponentDisconnectGraceSec!),
            if (c.incomingAttack != null) const _DodgeAlert(),
            if (c.banner != null) _Banner(text: c.banner!, onClose: c.clearBanner),
            if (c.gameOver != null) _GameOverOverlay(c: c),
          ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          : CustomPaint(painter: _DotPainter(pos!.x / GameConfig.mapSize, pos!.y / GameConfig.mapSize)),
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
