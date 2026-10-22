import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/preset_pair.dart';
import '../services/preset_store.dart';

Future<bool> deletePresetPair(BuildContext context, PresetPair pair) async {
  final title = pair.rhythm.songTitle.isNotEmpty
      ? pair.rhythm.songTitle
      : pair.rhythm.name;
  final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
            title: const Text('Excluir da biblioteca?'),
            content: Text(
                'Excluir "$title" e seus presets de base e solo deste aplicativo?\n\nOs presets gravados na pedaleira e os backups permanecem intactos.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Excluir'))
            ],
          ));
  if (confirmed != true || !context.mounted) return false;
  try {
    await context.read<PresetStore>().remove(pair.id);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível excluir: $e')));
    }
    return false;
  }
}
