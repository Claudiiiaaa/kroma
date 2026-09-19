import 'package:flutter_test/flutter_test.dart';
import 'package:kroma/models/stroke.dart';
import 'package:kroma/models/stroke_point.dart';
import 'package:kroma/models/tool.dart';

import '../test_helpers.dart';

void main() {
  group('Stroke.fromPoints', () {
    test('calcula los límites envolviendo todos los puntos', () {
      final stroke = strokeFrom(const [(0.0, 0.0), (10.0, 20.0), (5.0, -5.0)]);

      // Los límites se inflan por el grosor, así que se comprueba que contienen
      // al rectángulo real en vez de exigir valores exactos.
      expect(stroke.minX, lessThanOrEqualTo(0));
      expect(stroke.minY, lessThanOrEqualTo(-5));
      expect(stroke.maxX, greaterThanOrEqualTo(10));
      expect(stroke.maxY, greaterThanOrEqualTo(20));
    });

    test('infla los límites por el grosor del trazo', () {
      // Un trazo de un solo punto no tiene extensión, así que todo su tamaño
      // viene del inflado. Si el margen fuese cero, los límites serían un punto
      // y el borrador no podría tocarlo nunca.
      final stroke = strokeFrom(const [(0.0, 0.0)], width: 10);

      expect(stroke.maxX - stroke.minX, greaterThan(0));
      expect(stroke.maxY - stroke.minY, greaterThan(0));
    });

    test('rechaza un trazo sin puntos', () {
      expect(
        () => Stroke.fromPoints(
          id: 'x',
          points: const [],
          tool: ToolType.pen,
          colorArgb: 0xFF000000,
          baseWidth: 3,
          simulatePressure: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Stroke.hitTest', () {
    test('detecta un toque en mitad de un segmento, no solo en los vértices',
        () {
      // Este es el caso que importa de verdad. Con el lápiz rápido, dos puntos
      // consecutivos quedan muy separados; si solo se comprobaran los vértices,
      // el borrador cruzaría el trazo por el medio sin borrarlo.
      final stroke = strokeFrom(const [(0.0, 0.0), (100.0, 0.0)], width: 2);

      expect(stroke.hitTest(50, 0, 5), isTrue);
      expect(stroke.hitTest(50, 3, 5), isTrue);
    });

    test('no detecta un punto lejos del trazo', () {
      final stroke = strokeFrom(const [(0.0, 0.0), (100.0, 0.0)], width: 2);

      expect(stroke.hitTest(50, 500, 5), isFalse);
      expect(stroke.hitTest(-500, 0, 5), isFalse);
    });

    test('no detecta un punto alineado pero fuera del segmento', () {
      // Mide contra el segmento y no contra la recta infinita que lo contiene.
      // Sin el recorte de la proyección, este punto daría distancia cero por
      // estar perfectamente alineado con el trazo.
      final stroke = strokeFrom(const [(0.0, 0.0), (10.0, 0.0)], width: 1);

      expect(stroke.hitTest(1000, 0, 5), isFalse);
    });

    test('el radio del borrador amplía el área sensible', () {
      final stroke = strokeFrom(const [(0.0, 0.0), (100.0, 0.0)], width: 2);

      expect(stroke.hitTest(50, 40, 1), isFalse);
      expect(stroke.hitTest(50, 40, 60), isTrue);
    });
  });

  group('serialización', () {
    test('sobrevive a una ida y vuelta por JSON', () {
      final original = Stroke.fromPoints(
        id: 'trazo-1',
        points: const [
          StrokePoint(x: 1.5, y: 2.5, pressure: 0.25, tMs: 0),
          StrokePoint(x: 10.0, y: 20.0, pressure: 0.75, tMs: 16),
        ],
        tool: ToolType.highlighter,
        colorArgb: 0xFF2563EB,
        baseWidth: 4.5,
        simulatePressure: true,
      );

      final restored = Stroke.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.tool, original.tool);
      expect(restored.colorArgb, original.colorArgb);
      expect(restored.baseWidth, original.baseWidth);
      expect(restored.simulatePressure, original.simulatePressure);
      expect(restored.points.length, original.points.length);
      expect(restored.points.first.x, 1.5);
      expect(restored.points.first.pressure, 0.25);
      expect(restored.points.last.tMs, 16);

      // Los límites son datos derivados y se recalculan al leer, así que deben
      // coincidir exactamente con los del original.
      expect(restored.minX, original.minX);
      expect(restored.maxY, original.maxY);
    });

    test('lee un trazo sin el campo de presión simulada', () {
      // Compatibilidad hacia atrás: una nota guardada antes de que existiera
      // ese campo tiene que seguir abriéndose en lugar de reventar.
      final json = {
        'id': 'antiguo',
        'tool': 'pen',
        'color': 0xFF000000,
        'width': 3.0,
        'points': [
          [0, 0, 0.5, 0],
          [5, 5, 0.5, 10],
        ],
      };

      final stroke = Stroke.fromJson(json);
      expect(stroke.simulatePressure, isFalse);
    });

    test('una herramienta desconocida no rompe la lectura', () {
      final json = {
        'id': 'futuro',
        'tool': 'caligrafia-que-aun-no-existe',
        'color': 0xFF000000,
        'width': 3.0,
        'points': [
          [0, 0, 0.5, 0],
        ],
      };

      expect(Stroke.fromJson(json).tool, ToolType.pen);
    });
  });
}
