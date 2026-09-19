import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kroma/providers/ink_provider.dart';
import 'package:kroma/ui/widgets/ink_canvas.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  /// Monta el lienzo compartiendo el contenedor con el test, para poder
  /// inspeccionar el estado resultante sin tocar la interfaz.
  Future<void> pumpCanvas(WidgetTester tester) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: InkCanvas())),
      ),
    );
  }

  /// Dibuja un trazo recto con el tipo de puntero indicado.
  Future<void> drawLine(
    WidgetTester tester, {
    required PointerDeviceKind kind,
    Offset from = const Offset(100, 100),
    Offset to = const Offset(200, 200),
  }) async {
    final gesture = await tester.createGesture(kind: kind);
    await gesture.down(from);
    // Varios pasos intermedios: un solo salto se parece poco a un gesto real y
    // además el filtro de distancia mínima podría descartarlo.
    for (var i = 1; i <= 5; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 5)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('el lápiz dibuja un trazo', (tester) async {
    await pumpCanvas(tester);

    await drawLine(tester, kind: PointerDeviceKind.stylus);

    final strokes = container.read(inkCanvasProvider).strokes;
    expect(strokes, hasLength(1));
    expect(strokes.first.points.length, greaterThan(1));
  });

  testWidgets('el lápiz marca su trazo como de presión real', (tester) async {
    await pumpCanvas(tester);

    await drawLine(tester, kind: PointerDeviceKind.stylus);

    // Viniendo de un lápiz, el grosor sale de la presión medida y no hay que
    // deducirlo de la velocidad.
    expect(container.read(inkCanvasProvider).strokes.first.simulatePressure,
        isFalse);
  });

  testWidgets('el ratón marca su trazo para simular la presión',
      (tester) async {
    await pumpCanvas(tester);

    await drawLine(tester, kind: PointerDeviceKind.mouse);

    // Un ratón no mide presión, así que el trazo debe recordar que su grosor se
    // deduce de la velocidad. Es lo que hace que se vea igual al reabrirlo.
    expect(container.read(inkCanvasProvider).strokes.first.simulatePressure,
        isTrue);
  });

  group('rechazo de palma', () {
    testWidgets('con el dibujo táctil desactivado, el dedo no dibuja',
        (tester) async {
      container.read(inkCanvasProvider.notifier).setDrawWithTouch(false);
      await pumpCanvas(tester);

      await drawLine(tester, kind: PointerDeviceKind.touch);

      expect(container.read(inkCanvasProvider).strokes, isEmpty);
    });

    testWidgets('con el dibujo táctil desactivado, el lápiz sí dibuja',
        (tester) async {
      container.read(inkCanvasProvider.notifier).setDrawWithTouch(false);
      await pumpCanvas(tester);

      await drawLine(tester, kind: PointerDeviceKind.stylus);

      expect(container.read(inkCanvasProvider).strokes, hasLength(1));
    });

    testWidgets('con el dibujo táctil activado, el dedo dibuja',
        (tester) async {
      await pumpCanvas(tester);

      await drawLine(tester, kind: PointerDeviceKind.touch);

      expect(container.read(inkCanvasProvider).strokes, hasLength(1));
    });
  });

  testWidgets('un segundo dedo cancela el trazo y pasa a modo gesto',
      (tester) async {
    await pumpCanvas(tester);

    final first = await tester.createGesture(kind: PointerDeviceKind.touch);
    await first.down(const Offset(100, 100));
    await first.moveTo(const Offset(120, 120));
    await tester.pump();

    // Llega el segundo dedo: el usuario quiere ampliar, no escribir.
    final second = await tester.createGesture(kind: PointerDeviceKind.touch);
    await second.down(const Offset(300, 300));
    await tester.pump();

    await first.up();
    await second.up();
    await tester.pump();

    // El trazo a medias se descarta en lugar de quedar guardado como una raya
    // accidental en mitad de la nota.
    expect(container.read(inkCanvasProvider).strokes, isEmpty);
  });

  testWidgets('los puntos se guardan en coordenadas del documento, no de '
      'pantalla', (tester) async {
    await pumpCanvas(tester);

    // Con el lienzo al doble y anclado en el origen, la pantalla y el documento
    // difieren en un factor de dos.
    container.read(canvasTransformProvider).zoomBy(2.0, Offset.zero);
    await tester.pump();

    await drawLine(
      tester,
      kind: PointerDeviceKind.stylus,
      from: const Offset(100, 100),
      to: const Offset(200, 200),
    );

    final stroke = container.read(inkCanvasProvider).strokes.single;

    // Es el error clásico de las apps de dibujo caseras: guardar la coordenada
    // de pantalla tal cual. Si eso pasara, aquí saldría 100 en vez de 50 y el
    // trazo aparecería en otro sitio al cambiar el zoom.
    expect(stroke.points.first.x, closeTo(50, 0.01));
    expect(stroke.points.first.y, closeTo(50, 0.01));
  });
}
