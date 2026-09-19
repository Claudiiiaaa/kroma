import 'package:dio/dio.dart';

/// Un fallo al hablar con la API, ya traducido a algo que se puede enseñar.
///
/// Existe para que ni la interfaz ni la lógica de negocio tengan que saber qué
/// es un `DioException` ni un código 422. Si algún día cambiamos de cliente
/// HTTP, el cambio se queda en este archivo.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}});

  /// Mensaje listo para mostrar al usuario, en su idioma.
  final String message;

  final int? statusCode;

  /// Errores por campo que devuelve la API al validar.
  ///
  /// Permite pintar el error justo debajo del campo que lo provoca —«ya existe
  /// una cuenta con ese correo» bajo el correo— en vez de soltar un aviso
  /// genérico que obliga a adivinar qué hay que corregir.
  final Map<String, List<String>> fieldErrors;

  /// La sesión no vale: hay que volver a iniciarla.
  bool get isUnauthorized => statusCode == 401;

  /// Traduce un fallo de Dio a algo comprensible.
  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(
          'El servidor está tardando demasiado. Si es la primera vez que '
          'entras hoy, puede estar despertando: inténtalo de nuevo en un '
          'minuto.',
        );

      case DioExceptionType.connectionError:
        return ApiException(
          'No se ha podido conectar. Comprueba tu conexión a internet.',
        );

      case DioExceptionType.cancel:
        return ApiException('Petición cancelada.');

      case DioExceptionType.badResponse:
        return _fromResponse(error.response);

      default:
        return ApiException('Ha ocurrido un error inesperado.');
    }
  }

  static ApiException _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final data = response?.data;

    // ASP.NET Core devuelve los errores de validación en el formato estándar
    // ProblemDetails, con un diccionario `errors` de campo a lista de mensajes.
    if (data is Map<String, dynamic> && data['errors'] is Map) {
      final raw = data['errors'] as Map;
      final parsed = <String, List<String>>{};

      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is List) {
          parsed[entry.key.toString()] = value.map((e) => e.toString()).toList();
        }
      }

      return ApiException(
        // Se muestra el primer mensaje como resumen, y el resto queda
        // disponible por campo para quien quiera pintarlos junto al formulario.
        parsed.values.firstOrNull?.firstOrNull ?? 'Revisa los datos.',
        statusCode: status,
        fieldErrors: parsed,
      );
    }

    final message = switch (status) {
      401 => 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
      403 => 'No tienes permiso para hacer eso.',
      404 => 'No se ha encontrado lo que buscabas.',
      // El patrón con `final int` descarta de paso el caso nulo, que es
      // posible cuando la respuesta ni siquiera llegó a tener código.
      final int code when code >= 500 =>
        'El servidor ha tenido un problema. Inténtalo más tarde.',
      _ => 'No se ha podido completar la operación.',
    };

    return ApiException(message, statusCode: status);
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
