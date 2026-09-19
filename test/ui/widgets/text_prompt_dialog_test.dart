import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kroma/ui/widgets/text_prompt_dialog.dart';

/// Monta un botón que abre el diálogo y recoge lo que devuelve.
Future<void> pumpHost(WidgetTester tester, List<String?> results) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              results.add(await promptForText(
                context,
                title: 'Nueva tarjeta',
                label: 'Título',
                confirmLabel: 'Crear',
                initialValue: results.isEmpty ? '' : 'Antiguo',
              ));
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('devuelve el texto escrito', (tester) async {
    final results = <String?>[];
    await pumpHost(tester, results);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Comprar pinceles');
    await tester.tap(find.text('Crear'));
    // `pumpAndSettle` deja correr la animación de cierre entera. Es la clave de
    // este test: el fallo que reprodujo este diálogo ocurría justo ahí, después
    // de que showDialog devolviera el valor pero mientras el campo de texto
    // seguía reconstruyéndose con el controlador ya liberado.
    await tester.pumpAndSettle();

    expect(results.single, 'Comprar pinceles');
    // Si el controlador se hubiese liberado antes de tiempo, la excepción «A
    // TextEditingController was used after being disposed» habría saltado
    // durante el pumpAndSettle anterior y este test fallaría.
    expect(tester.takeException(), isNull);
  });

  testWidgets('recorta los espacios sobrantes', (tester) async {
    final results = <String?>[];
    await pumpHost(tester, results);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   con espacios   ');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(results.single, 'con espacios');
  });

  testWidgets('cancelar devuelve null', (tester) async {
    final results = <String?>[];
    await pumpHost(tester, results);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'esto se descarta');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(results.single, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('abrirlo y cerrarlo varias veces no rompe nada', (tester) async {
    // Cada apertura crea un controlador nuevo. Si alguno se liberase fuera de
    // tiempo, el segundo ciclo lo destaparía.
    final results = <String?>[];
    await pumpHost(tester, results);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'tarjeta $i');
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
    }

    expect(results, ['tarjeta 0', 'tarjeta 1', 'tarjeta 2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el texto inicial viene seleccionado para escribir encima',
      (tester) async {
    // Al renombrar, lo cómodo es empezar a teclear y que sustituya al título
    // anterior, sin tener que borrarlo primero.
    final results = <String?>['previo'];
    await pumpHost(tester, results);

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Antiguo');
    expect(field.controller!.selection.baseOffset, 0);
    expect(field.controller!.selection.extentOffset, 'Antiguo'.length);
  });
}
