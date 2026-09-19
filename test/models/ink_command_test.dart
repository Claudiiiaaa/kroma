import 'package:flutter_test/flutter_test.dart';
import 'package:kroma/models/stroke.dart';
import 'package:kroma/models/ink_command.dart';

import '../test_helpers.dart';

/// Los ids de los trazos, para comparar listas de un vistazo.
List<String> ids(List<Stroke> strokes) => [for (final s in strokes) s.id];

void main() {
  group('AddStrokeCommand', () {
    test('añade al final y deshace dejando la lista igual', () {
      final a = strokeFrom(const [(0.0, 0.0)], id: 'a');
      final nuevo = strokeFrom(const [(1.0, 1.0)], id: 'nuevo');
      final command = AddStrokeCommand(nuevo);

      final after = command.apply([a]);
      expect(ids(after), ['a', 'nuevo']);

      expect(ids(command.revert(after)), ['a']);
    });
  });

  group('EraseStrokesCommand', () {
    test('devuelve los trazos a su posición original', () {
      final a = strokeFrom(const [(0.0, 0.0)], id: 'a');
      final b = strokeFrom(const [(1.0, 1.0)], id: 'b');
      final c = strokeFrom(const [(2.0, 2.0)], id: 'c');

      // Se borró 'b', que estaba en medio.
      final command = EraseStrokesCommand([(index: 1, stroke: b)]);

      final after = command.apply([a, b, c]);
      expect(ids(after), ['a', 'c']);

      // Vuelve en medio, no al final: el orden de la lista es el orden de
      // pintado, así que devolverlo al final lo pondría encima de 'c'.
      expect(ids(command.revert(after)), ['a', 'b', 'c']);
    });

    test('restaura el orden con varios borrados en pasadas sucesivas', () {
      // Es el caso que rompe la implementación ingenua. Partiendo de
      // [a,b,c,d,e] se borra 'c' (índice 2) y después 'e', que para entonces
      // está en el índice 3 de la lista ya reducida [a,b,d,e]. Reinsertando de
      // menor a mayor índice saldría [a,b,c,e,d], con los dos últimos
      // intercambiados. Por eso el comando deshace en orden inverso.
      final strokes = [
        strokeFrom(const [(0.0, 0.0)], id: 'a'),
        strokeFrom(const [(1.0, 0.0)], id: 'b'),
        strokeFrom(const [(2.0, 0.0)], id: 'c'),
        strokeFrom(const [(3.0, 0.0)], id: 'd'),
        strokeFrom(const [(4.0, 0.0)], id: 'e'),
      ];

      final command = EraseStrokesCommand([
        (index: 2, stroke: strokes[2]), // 'c'
        (index: 3, stroke: strokes[4]), // 'e'
      ]);

      final after = command.apply(strokes);
      expect(ids(after), ['a', 'b', 'd']);

      expect(ids(command.revert(after)), ['a', 'b', 'c', 'd', 'e']);
    });

    test('restaura dos trazos contiguos borrados a la vez', () {
      // 'b' y 'c' se marcan en la misma pasada, así que ambos anotan el mismo
      // índice: la posición que ocupaban entre los supervivientes.
      final strokes = [
        strokeFrom(const [(0.0, 0.0)], id: 'a'),
        strokeFrom(const [(1.0, 0.0)], id: 'b'),
        strokeFrom(const [(2.0, 0.0)], id: 'c'),
        strokeFrom(const [(3.0, 0.0)], id: 'd'),
      ];

      final command = EraseStrokesCommand([
        (index: 1, stroke: strokes[1]),
        (index: 1, stroke: strokes[2]),
      ]);

      final after = command.apply(strokes);
      expect(ids(after), ['a', 'd']);
      expect(ids(command.revert(after)), ['a', 'b', 'c', 'd']);
    });
  });

  group('ClearCanvasCommand', () {
    test('vacía y restaura el lienzo entero', () {
      final strokes = [
        strokeFrom(const [(0.0, 0.0)], id: 'a'),
        strokeFrom(const [(1.0, 0.0)], id: 'b'),
      ];
      final command = ClearCanvasCommand(strokes);

      expect(command.apply(strokes), isEmpty);
      expect(ids(command.revert(const [])), ['a', 'b']);
    });
  });

  group('UndoStack', () {
    late UndoStack stack;

    setUp(() => stack = UndoStack());

    test('empieza sin nada que deshacer ni rehacer', () {
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
    });

    test('deshacer mueve el comando a la pila de rehacer', () {
      final command = AddStrokeCommand(strokeFrom(const [(0.0, 0.0)]));
      stack.push(command);

      expect(stack.canUndo, isTrue);
      expect(stack.canRedo, isFalse);

      expect(stack.popUndo(), same(command));
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isTrue);

      expect(stack.popRedo(), same(command));
      expect(stack.canUndo, isTrue);
      expect(stack.canRedo, isFalse);
    });

    test('una acción nueva descarta lo que se podía rehacer', () {
      // Igual que el historial de un navegador: al deshacer y dibujar algo
      // distinto se crea otra rama, y el futuro anterior deja de existir.
      stack.push(AddStrokeCommand(strokeFrom(const [(0.0, 0.0)])));
      stack.popUndo();
      expect(stack.canRedo, isTrue);

      stack.push(AddStrokeCommand(strokeFrom(const [(1.0, 1.0)])));
      expect(stack.canRedo, isFalse);
    });

    test('las pilas vacías devuelven null en vez de fallar', () {
      expect(stack.popUndo(), isNull);
      expect(stack.popRedo(), isNull);
    });

    test('el historial no crece más allá del tope', () {
      final limited = UndoStack(maxDepth: 3);
      for (var i = 0; i < 10; i++) {
        limited.push(AddStrokeCommand(strokeFrom([(i.toDouble(), 0.0)])));
      }

      // Solo quedan los tres últimos: los más antiguos se descartan para que
      // una sesión larga no acabe reteniendo en memoria todo lo dibujado.
      expect(limited.popUndo(), isNotNull);
      expect(limited.popUndo(), isNotNull);
      expect(limited.popUndo(), isNotNull);
      expect(limited.popUndo(), isNull);
    });
  });
}
