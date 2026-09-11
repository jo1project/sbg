import 'package:flutter/material.dart';
import 'game/game_controller.dart';
import 'screens/game_screen.dart';

void main() {
  runApp(const SnakeBattleApp());
}

class SnakeBattleApp extends StatelessWidget {
  const SnakeBattleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '貪食蛇對戰',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final controller = GameController();
  final _urlController = TextEditingController();
  final _friendIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChange);
    _init();
  }

  Future<void> _init() async {
    await controller.bootstrap();
    _urlController.text = controller.serverUrl;
    await controller.connectAndIdentify();
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    controller.removeListener(_onChange);
    controller.dispose();
    _urlController.dispose();
    _friendIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller.matchStatus == MatchStatus.inRoom || controller.gameOver != null) {
      return GameScreen(c: controller);
    }
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: _buildLobbyContent()),
            if (controller.recoveryCode != null) _RecoveryCodeOverlay(controller: controller),
            if (controller.incomingInviteFromId != null) _IncomingInviteOverlay(controller: controller),
          ],
        ),
      ),
    );
  }

  Widget _buildLobbyContent() {
    if (controller.connStatus != ConnStatus.connected) {
      return _ConnectGate(controller: controller, urlController: _urlController);
    }
    switch (controller.matchStatus) {
      case MatchStatus.waitingQueue:
        return _WaitingView(text: "配對中...(逾時會自動配對電腦)", onCancel: controller.leaveRoom);
      case MatchStatus.waitingInviteSent:
        return _WaitingView(text: "已送出邀請,等待對方回應...", onCancel: controller.cancelInvite);
      default:
        return _LobbyMenu(controller: controller, friendIdController: _friendIdController);
    }
  }
}

class _ConnectGate extends StatelessWidget {
  final GameController controller;
  final TextEditingController urlController;
  const _ConnectGate({required this.controller, required this.urlController});

  @override
  Widget build(BuildContext context) {
    final connecting = controller.connStatus == ConnStatus.connecting;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("貪食蛇對戰", style: TextStyle(fontSize: 28)),
          const SizedBox(height: 24),
          TextField(
            controller: urlController,
            decoration: const InputDecoration(labelText: "伺服器位址(ws:// 或 wss://)"),
          ),
          const SizedBox(height: 16),
          if (controller.banner != null) Text(controller.banner!, style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 8),
          connecting
              ? const CircularProgressIndicator()
              : ElevatedButton(
                  onPressed: () async {
                    await controller.setServerUrl(urlController.text.trim());
                    await controller.connectAndIdentify();
                  },
                  child: const Text("連線"),
                ),
        ],
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  final String text;
  final VoidCallback onCancel;
  const _WaitingView({required this.text, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(text),
        const SizedBox(height: 16),
        TextButton(onPressed: onCancel, child: const Text("取消")),
      ],
    );
  }
}

class _LobbyMenu extends StatelessWidget {
  final GameController controller;
  final TextEditingController friendIdController;
  const _LobbyMenu({required this.controller, required this.friendIdController});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("貪食蛇對戰", style: TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text("你的ID:${controller.playerId ?? "-"}", style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 32),
          if (controller.banner != null) ...[
            Text(controller.banner!, style: const TextStyle(color: Colors.amberAccent)),
            const SizedBox(height: 12),
          ],
          ElevatedButton(onPressed: controller.joinQueue, child: const Text("隨機配對")),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: friendIdController,
                  decoration: const InputDecoration(labelText: "輸入好友ID"),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final id = friendIdController.text.trim();
                  if (id.isNotEmpty) controller.challengeFriend(id);
                },
                child: const Text("邀請"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecoveryCodeOverlay extends StatelessWidget {
  final GameController controller;
  const _RecoveryCodeOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("請截圖保存你的還原碼", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text("換裝置或重灌APP後,用這組還原碼找回帳號", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 16),
                  SelectableText(
                    controller.recoveryCode!,
                    style: const TextStyle(fontSize: 20, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(onPressed: controller.clearRecoveryCode, child: const Text("我已保存")),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingInviteOverlay extends StatelessWidget {
  final GameController controller;
  const _IncomingInviteOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("${controller.incomingInviteFromId} 邀請你對戰", style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(onPressed: controller.acceptInvite, child: const Text("接受")),
                      const SizedBox(width: 16),
                      OutlinedButton(onPressed: controller.rejectInvite, child: const Text("拒絕")),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
