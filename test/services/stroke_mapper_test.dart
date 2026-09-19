import 'package:flutter_test/flutter_test.dart';
import 'package:kroma/services/stroke_mapper.dart';
import 'package:kroma/models/tool.dart';

import '../test_helpers.dart';

void main() {
  group('StrokeMapper', () {
    test('aplana los puntos de cuatro en cuatro', () {
      final stroke = strokeFrom(const [(1.0, 2.0), (3.0, 4.0)]);

      final json = StrokeMapper.toJson(stroke);
      final points = json['points'] as List;

      // Dos puntos por cuatro valores cada uno.
      expect(points, hasLength(8));
      expect(points[0], 1.0);
      expect(points[1], 2.0);
      expect(points[4], 3.0);
      expect(points[5], 4.0);
    });

    test('sobrevive a una ida y vuelta completa', () {
      final original = strokeFrom(
        const [(0.0, 0.0), (10.5, 20.25), (30.0, 5.0)],
        tool: ToolType.highlighter,
        width: 18,
        colorArgb: 0xFF2563EB,
      );

      final restored = StrokeMapper.fromJson(StrokeMapper.toJson(original));

      expect(restored.id, original.id);
      expect(restored.tool, ToolType.highlighter);
      expect(restored.colorArgb, 0xFF2563EB);
      expect(restored.baseWidth, 18);
      expect(restored.points, hasLength(3));
      expect(restored.points[1].x, 10.5);
      expect(restored.points[1].y, 20.25);
      expect(restored.points.last.x, 30.0);
    });

    test('ignora valores sobrantes que no completan un punto', () {
      // El servidor lo valida, pero el cliente no se fía: unos datos corruptos
      // deben perder el último punto incompleto, no tumbar la pantalla entera
      // al intentar leer fuera de la lista.
      final json = {
        'id': 'trazo-suelto',
        'tool': 'pen',
        'colorArgb': 0xFF000000,
        'baseWidth': 3.0,
        'simulatePressure': false,
        'points': [0, 0, 0.5, 0, 10, 10, 0.5, 16, 99, 99],
      };

      final stroke = StrokeMapper.fromJson(json);
      expect(stroke.points, hasLength(2));
    });

    test('conserva la marca de presión simulada', () {
      // Es lo que hace que un trazo dibujado con ratón se vea igual al
      // recargarlo desde el servidor que mientras se dibujaba.
      final json = {
        'id': 'con-raton',
        'tool': 'pen',
        'colorArgb': 0xFF000000,
        'baseWidth': 3.0,
        'simulatePressure': true,
        'points': [0, 0, 0.5, 0, 5, 5, 0.5, 16],
      };

      expect(StrokeMapper.fromJson(json).simulatePressure, isTrue);
    });
  });
}
