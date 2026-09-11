import 'package:flutter/material.dart';

// 一般點擊發動攻擊;長按顯示效果說明氣泡(9.2節),放開才觸發攻擊或取消。
class AttackButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool disabled;
  const AttackButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.disabled,
  });

  @override
  State<AttackButton> createState() => _AttackButtonState();
}

class _AttackButtonState extends State<AttackButton> {
  bool _showTip = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (_showTip)
          Positioned(
            bottom: 55,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
              child: Text(widget.tooltip, style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
        GestureDetector(
          onLongPressStart: (_) => setState(() => _showTip = true),
          onLongPressEnd: (_) => setState(() => _showTip = false),
          onTap: widget.disabled ? null : widget.onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (widget.disabled ? Colors.grey : Colors.deepOrange).withValues(alpha: _showTip ? 0.9 : 0.45),
              border: Border.all(color: Colors.white.withValues(alpha: _showTip ? 0.8 : 0.3)),
            ),
            child: Icon(widget.icon, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
