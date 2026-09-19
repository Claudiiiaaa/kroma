import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/services/api_client.dart';
import 'package:kroma/providers/api_providers.dart';
import 'package:kroma/models/auth_user.dart';

/// Habla con los endpoints de `/auth`.
///
/// El repositorio es la única capa que conoce las rutas y la forma del JSON.
/// Ni la interfaz ni el controlador saben que existe una URL llamada
/// `/auth/login`, así que un cambio en la API se queda dentro de este archivo.
class AuthService {
  const AuthService(this._api);

  final ApiClient _api;

  Future<AuthResult> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final data = await _api.post('/auth/register', body: {
      'email': email,
      'password': password,
      'displayName': displayName,
    });
    return AuthResult.fromJson(data as Map<String, dynamic>);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final data = await _api.post('/auth/login', body: {
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(data as Map<String, dynamic>);
  }

  /// Comprueba que el token guardado sigue siendo válido.
  Future<AuthUser> me() async {
    final data = await _api.get('/auth/me');
    return AuthUser.fromJson(data as Map<String, dynamic>);
  }
}

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(apiClientProvider)),
);
