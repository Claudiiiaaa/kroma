import 'package:dio/dio.dart';

import 'package:kroma/services/api_config.dart';
import 'package:kroma/services/api_exception.dart';
import 'package:kroma/services/token_storage.dart';

/// Cliente HTTP de la aplicación.
///
/// Concentra en un solo sitio tres cosas que si no acabarían repetidas por
/// todas partes: añadir el token a cada petición, traducir los errores a
/// [ApiException] y avisar cuando la sesión deja de valer.
class ApiClient {
  ApiClient(this._tokenStorage, {Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = ApiConfig.effectiveBaseUrl
      ..connectTimeout = ApiConfig.connectTimeout
      ..receiveTimeout = ApiConfig.receiveTimeout
      ..contentType = Headers.jsonContentType
      // Sin esto, Dio lanza una excepción con cualquier código que no sea 2xx,
      // incluidos los 400 de validación que aquí interesa leer para saber qué
      // campo está mal. Se aceptan todos y se decide después.
      ..validateStatus = (status) => status != null && status < 500;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokenStorage.read();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// Se llama cuando el servidor rechaza el token.
  ///
  /// Lo conecta el controlador de sesión para cerrarla y volver al login. Es un
  /// callback y no una dependencia directa para no crear un ciclo: el
  /// controlador de sesión ya depende de este cliente.
  void Function()? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query));

  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => _dio.post<dynamic>(path, data: body));

  Future<dynamic> put(String path, {Object? body}) =>
      _send(() => _dio.put<dynamic>(path, data: body));

  Future<dynamic> delete(String path) =>
      _send(() => _dio.delete<dynamic>(path));

  /// Ejecuta la petición y convierte cualquier fallo en [ApiException].
  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final status = response.statusCode ?? 0;

      if (status >= 200 && status < 300) return response.data;

      if (status == 401) {
        // El token ya no vale: se borra antes de avisar, para que una petición
        // que llegue justo después no vuelva a mandar uno inservible.
        await _tokenStorage.clear();
        onUnauthorized?.call();
      }

      throw ApiException.fromDio(
        DioException.badResponse(
          statusCode: status,
          requestOptions: response.requestOptions,
          response: response,
        ),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}
