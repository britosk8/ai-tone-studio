import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ConfidenceBadge extends StatelessWidget {
  final String level;
  final String rationale;

  const ConfidenceBadge({super.key, required this.level, this.rationale = ""});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (level.toLowerCase()) {
      'high' => (AppTheme.primaryGreen, 'Alta confiança'),
      'medium' => (AppTheme.warnYellow, 'Confiança média'),
      'low' => (AppTheme.accentOrange, 'Confiança baixa'),
      _ => (Colors.grey, 'Especulativo'),
    };

    return Semantics(
        button: true,
        label: "Explicar confiança da estimativa",
        child: InkWell(
            onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                      title: const Text("Confiança da estimativa"),
                      content: SingleChildScrollView(
                          child: Text(
                              "$label\n\nA confiança indica a incerteza da sugestão. Não é um percentual de semelhança ao áudio original e não comprova o modelo de equipamento usado.\n\n${rationale.isEmpty ? 'Este registro não contém uma justificativa detalhada. Reanalise um trecho com a guitarra em destaque e compare uma gravação USB do pedal com a mesma passagem.' : rationale}\n\nUse a gravação USB e a comparação de timbre para orientar os ajustes.")),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("Entendi"))
                      ],
                    )),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                border: Border.all(color: color.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 12, color: color),
                  const SizedBox(width: 4),
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            )));
  }
}
