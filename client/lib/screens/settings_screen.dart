import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

// 唯一一個設定項:棋盤光影特效(移軸模糊/暖冷色調/暗角/火把/落地陰影,見widgets/board.dart)
// 開關,關閉時board.dart直接跳過整個_paintLighting/_paintTorches/_drawShadow,退回清晰版本。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("設定")),
      body: SwitchListTile(
        title: const Text("高畫質光影"),
        subtitle: const Text("移軸模糊、火把、暗角等效果。低階裝置掉幀時可關閉,退回清晰版本"),
        value: GameConfig.highQualityLighting,
        onChanged: (value) async {
          setState(() => GameConfig.highQualityLighting = value);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool("highQualityLighting", value);
        },
      ),
    );
  }
}
