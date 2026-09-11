import 'dart:math';
import 'package:flutter/material.dart';
import '../models/point.dart';

// 拖曳搖桿:回傳離散的四方向(貪食蛇只需要上下左右),不做類比搖桿。
class Joystick extends StatefulWidget {
  final ValueChanged<Direction> onDirection;
  const Joystick({super.key, required this.onDirection});

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knob = Offset.zero;
  static const _radius = 45.0;

  void _handleDrag(Offset delta) {
    final next = _knob + delta;
    final dist = next.distance;
    _knob = dist > _radius ? next / dist * _radius : next;
    setState(() {});

    if (dist < 10) return; // 死區,避免手指微抖動誤觸發
    final angle = atan2(_knob.dy, _knob.dx);
    final deg = angle * 180 / pi;
    Direction dir;
    if (deg >= -45 && deg < 45) {
      dir = Direction.right;
    } else if (deg >= 45 && deg < 135) {
      dir = Direction.down;
    } else if (deg >= -135 && deg < -45) {
      dir = Direction.up;
    } else {
      dir = Direction.left;
    }
    widget.onDirection(dir);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => _handleDrag(d.delta),
      onPanEnd: (_) => setState(() => _knob = Offset.zero),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Align(
          alignment: Alignment(_knob.dx / _radius, _knob.dy / _radius),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
