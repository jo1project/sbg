import 'package:flutter/material.dart';
import '../config.dart';

class EnergyBar extends StatelessWidget {
  final String label;
  final double energy;
  final bool mine;
  const EnergyBar({super.key, required this.label, required this.energy, required this.mine});

  Color _color() {
    final ratio = (energy / GameConfig.energyCap).clamp(0, 1);
    if (!mine) return Colors.amber.shade400; // 對手一律黃色系,示意威脅感(9.1節)
    if (ratio < 0.5) return Colors.green;
    if (ratio < 1.0) return Colors.yellow.shade700;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (energy / GameConfig.energyCap).clamp(0.0, 1.0);
    final full = energy >= GameConfig.energyCap;
    return Column(
      crossAxisAlignment: mine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 2),
        Container(
          width: 90,
          height: 10,
          decoration: BoxDecoration(
            border: full ? Border.all(color: Colors.white, width: 1.5) : null,
            borderRadius: BorderRadius.circular(4),
            color: Colors.white24,
          ),
          child: Align(
            alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: ratio,
              child: Container(
                decoration: BoxDecoration(color: _color(), borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ),
        Text(energy.toStringAsFixed(0), style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ],
    );
  }
}
