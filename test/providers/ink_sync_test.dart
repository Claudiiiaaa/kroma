import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kroma/providers/ink_provider.dart';

import '../test_helpers.dart';

/// Comprueba el cálculo de qué hay que enviar al servidor.
///
/// Es la parte donde un error no se ve en pantalla: los trazos aparecen bien
/// dibujados y el fallo solo sale a la luz al reabrir la nota y descubrir que
/// falta algo o que ha vuelto algo borrado.
void main() {
  late ProviderContainer container;
  late InkCanvasNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(inkCanvasProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('un lienzo recién cargado no tiene nada pendiente', () {
    notifier.loadStrokes([
      strokeFrom(const [(0.0, 0.0), (10.0, 10.0)], id: 'del-servidor'),
    ]);

    expect(notifier.hasPendingChanges, isFalse);
  });

  test('un trazo nuevo queda pendiente de subir', () {
    notifier.loadStrokes([strokeFrom(const [(0.0, 0.0)], id: 'viejo')]);
    notifier.commitStroke(strokeFrom(const [(5.0, 5.0)], id: 'nuevo'));

    final changes = notifier.pendingChanges;
    expect(changes.added.map((s) => s.id), ['nuevo']);
    expect(changes.deleted, isEmpty);
  });

  test('borrar un trazo del servidor queda pendiente de borrar', () {
    notifier.loadStrokes([
      strokeFrom(const [(0.0, 0.0), (10.0, 0.0)], id: 'a'),
    ]);

    notifier.beginErase();
    notifier.eraseAt(x: 5, y: 0, radius: 2);
    notifier.endErase();

    final changes = notifier.pendingChanges;
    expect(changes.added, isEmpty);
    expect(changes.deleted, ['a']);
  });

  test('dibujar y deshacer no deja nada que subir', () {
    // Aquí es donde falla el enfoque de ir apuntando cada operación: un
    // registro de acciones habría anotado «añadir» y subiría un trazo que el
    // usuario ya ha deshecho y no ve en pantalla.
    notifier.loadStrokes([]);

    notifier.commitStroke(strokeFrom(const [(0.0, 0.0)], id: 'arrepentido'));
    notifier.undo();

    expect(notifier.hasPendingChanges, isFalse);
  });

  test('borrar y deshacer no borra nada en el servidor', () {
    // El reverso del caso anterior, y el más peligroso de los dos: un registro
    // de operaciones borraría del servidor un trazo que el usuario recuperó.
    notifier.loadStrokes([
      strokeFrom(const [(0.0, 0.0), (10.0, 0.0)], id: 'rescatado'),
    ]);

    notifier.beginErase();
    notifier.eraseAt(x: 5, y: 0, radius: 2);
    notifier.endErase();
    expect(notifier.pendingChanges.deleted, ['rescatado']);

    notifier.undo();
    expect(notifier.hasPendingChanges, isFalse);
  });

  test('rehacer vuelve a dejarlo pendiente', () {
    notifier.loadStrokes([]);
    notifier.commitStroke(strokeFrom(const [(0.0, 0.0)], id: 'ida-y-vuelta'));
    notifier.undo();
    notifier.redo();

    expect(notifier.pendingChanges.added.map((s) => s.id), ['ida-y-vuelta']);
  });

  test('tras sincronizar no queda nada pendiente', () {
    notifier.loadStrokes([]);
    notifier.commitStroke(strokeFrom(const [(0.0, 0.0)], id: 'subido'));
    expect(notifier.hasPendingChanges, isTrue);

    notifier.markSynced();
    expect(notifier.hasPendingChanges, isFalse);
  });

  test('cargar otra tarjeta borra el historial de la anterior', () {
    // Sin esto, deshacer en una tarjeta haría desaparecer trazos dibujados en
    // la tarjeta anterior, que además seguirían guardados en el servidor.
    notifier.loadStrokes([]);
    notifier.commitStroke(strokeFrom(const [(0.0, 0.0)], id: 'de-la-primera'));

    notifier.loadStrokes([strokeFrom(const [(1.0, 1.0)], id: 'de-la-segunda')]);

    expect(container.read(inkCanvasProvider).canUndo, isFalse);
    expect(notifier.hasPendingChanges, isFalse);
  });

  test('reset deja el lienzo limpio al salir de la tarjeta', () {
    notifier.loadStrokes([strokeFrom(const [(0.0, 0.0)], id: 'a')]);
    notifier.reset();

    expect(container.read(inkCanvasProvider).strokes, isEmpty);
    expect(notifier.hasPendingChanges, isFalse);
  });
}
