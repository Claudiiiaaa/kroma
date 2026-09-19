import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kroma/models/tool.dart';
import 'package:kroma/providers/ink_provider.dart';

import '../test_helpers.dart';

void main() {
  late ProviderContainer container;
  late InkCanvasNotifier notifier;

  setUp(() {
    // Un contenedor por test: así ninguno hereda el estado del anterior, que es
    // la causa habitual de tests que pasan sueltos y fallan en conjunto.
    container = ProviderContainer();
    notifier = container.read(inkCanvasProvider.notifier);
  });

  tearDown(() => container.dispose());

  List<String> currentIds() => [
        for (final s in container.read(inkCanvasProvider).strokes) s.id,
      ];

  group('dibujar', () {
    test('un trazo confirmado aparece y se puede deshacer', () {
      expect(container.read(inkCanvasProvider).canUndo, isFalse);

      notifier.commitStroke(strokeFrom(const [(0.0, 0.0), (10.0, 10.0)], id: 'a'));

      expect(currentIds(), ['a']);
      expect(container.read(inkCanvasProvider).canUndo, isTrue);

      notifier.undo();
      expect(currentIds(), isEmpty);

      notifier.redo();
      expect(currentIds(), ['a']);
    });
  });

  group('borrar', () {
    test('una pasada que borra varios trazos se deshace de una vez', () {
      // Es la razón de ser de `beginErase`/`endErase`. Si cada trazo borrado
      // generase su propio comando, el usuario tendría que pulsar deshacer tres
      // veces para recuperar lo que quitó con un solo gesto.
      notifier.commitStroke(strokeFrom(const [(0.0, 0.0), (10.0, 0.0)], id: 'a'));
      notifier.commitStroke(strokeFrom(const [(0.0, 10.0), (10.0, 10.0)], id: 'b'));
      notifier.commitStroke(strokeFrom(const [(0.0, 20.0), (10.0, 20.0)], id: 'c'));

      notifier.beginErase();
      notifier.eraseAt(x: 5, y: 0, radius: 2);
      notifier.eraseAt(x: 5, y: 10, radius: 2);
      notifier.eraseAt(x: 5, y: 20, radius: 2);
      notifier.endErase();

      expect(currentIds(), isEmpty);

      notifier.undo();
      expect(currentIds(), ['a', 'b', 'c']);
    });

    test('deshacer devuelve los trazos a su orden de pintado', () {
      notifier.commitStroke(strokeFrom(const [(0.0, 0.0), (10.0, 0.0)], id: 'a'));
      notifier.commitStroke(strokeFrom(const [(0.0, 10.0), (10.0, 10.0)], id: 'b'));
      notifier.commitStroke(strokeFrom(const [(0.0, 20.0), (10.0, 20.0)], id: 'c'));

      // Se borra el de en medio y luego el último, que es el caso en el que los
      // índices se capturan sobre listas de distinto tamaño.
      notifier.beginErase();
      notifier.eraseAt(x: 5, y: 10, radius: 2);
      notifier.eraseAt(x: 5, y: 20, radius: 2);
      notifier.endErase();

      expect(currentIds(), ['a']);

      notifier.undo();
      expect(currentIds(), ['a', 'b', 'c']);
    });

    test('pasar el borrador sin tocar nada no ensucia el historial', () {
      notifier.commitStroke(strokeFrom(const [(0.0, 0.0), (10.0, 0.0)], id: 'a'));
      notifier.undo();
      expect(container.read(inkCanvasProvider).canUndo, isFalse);

      notifier.beginErase();
      notifier.eraseAt(x: 900, y: 900, radius: 2);
      notifier.endErase();

      // Un gesto que no borró nada no es una acción, así que no debe dejar una
      // entrada vacía que obligue a pulsar deshacer dos veces más tarde.
      expect(container.read(inkCanvasProvider).canUndo, isFalse);
    });
  });

  group('vaciar', () {
    test('se puede deshacer', () {
      notifier.commitStroke(strokeFrom(const [(0.0, 0.0)], id: 'a'));
      notifier.commitStroke(strokeFrom(const [(1.0, 1.0)], id: 'b'));

      notifier.clear();
      expect(currentIds(), isEmpty);

      notifier.undo();
      expect(currentIds(), ['a', 'b']);
    });

    test('vaciar un lienzo vacío no hace nada', () {
      notifier.clear();
      expect(container.read(inkCanvasProvider).canUndo, isFalse);
    });
  });

  group('herramientas', () {
    test('elegir un color saca del borrador', () {
      // Los colores no aplican al borrador, así que quedarse en él tras tocar
      // la paleta dejaría al usuario borrando cuando quería escribir.
      notifier.setToolType(ToolType.eraser);
      notifier.setColor(0xFFDC2626);

      final tool = container.read(inkCanvasProvider).tool;
      expect(tool.type, ToolType.pen);
      expect(tool.colorArgb, 0xFFDC2626);
    });

    test('elegir un color con el marcador no cambia de herramienta', () {
      notifier.setToolType(ToolType.highlighter);
      notifier.setColor(0xFF16A34A);

      expect(container.read(inkCanvasProvider).tool.type, ToolType.highlighter);
    });

    test('el marcador dibuja más ancho que el bolígrafo al mismo grosor', () {
      notifier.setWidth(3);
      final pen = container.read(inkCanvasProvider).tool.effectiveWidth;

      notifier.setToolType(ToolType.highlighter);
      final highlighter = container.read(inkCanvasProvider).tool.effectiveWidth;

      expect(highlighter, greaterThan(pen));
    });
  });
}
