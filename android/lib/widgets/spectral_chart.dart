import 'package:flutter/material.dart';
import '../models/preset_pair.dart';
import '../theme/app_theme.dart';

class SpectralChart extends StatelessWidget {
  final SpectralProfile spectral;

  const SpectralChart({super.key, required this.spectral});

  @override
  Widget build(BuildContext context) {
    final bands = [
      ('Bass', spectral.low),
      ('Low-Mid', spectral.lowMid),
      ('Mid', spectral.mid),
      ('Hi-Mid', spectral.highMid),
      ('Treble', spectral.high),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Perfil espectral', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: bands
                .map((band) => _Bar(label: band.$1, value: band.$2))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final double value;

  const _Bar({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final height = (value.clamp(0.0, 1.0) * 56).toDouble();
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 28,
          height: height.clamp(4, 56),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withOpacity(0.7 + value * 0.3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
      ],
    );
  }
}
