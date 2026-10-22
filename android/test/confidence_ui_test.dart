import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_tone_studio/widgets/confidence_badge.dart';
import 'package:ai_tone_studio/screens/upload_screen.dart';

void main() {
  testWidgets('Confiança explica estimativa sem prometer fidelidade',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ConfidenceBadge(
                level: 'low',
                rationale: 'Modelo original não identificado.'))));
    await tester.tap(find.text('Confiança baixa'));
    await tester.pumpAndSettle();
    expect(find.text('Confiança da estimativa'), findsOneWidget);
    expect(find.textContaining('Não é um percentual de semelhança'),
        findsOneWidget);
    expect(find.textContaining('Modelo original não identificado.'),
        findsOneWidget);
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('Música completa continua padrão e trecho tem duração editável',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UploadScreen()));
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .initialValue,
        'mix');
    expect(find.text('Início do trecho (segundos)'), findsNothing);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Início do trecho (segundos)'), findsOneWidget);
    expect(find.text('Duração do trecho (3–120 segundos)'), findsOneWidget);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller!.text, '0');
    expect(fields[1].controller!.text, '20');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Início do trecho (segundos)'), findsNothing);
  });
}
