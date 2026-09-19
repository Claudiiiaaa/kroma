import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/providers/auth_provider.dart';
import 'package:kroma/services/api_client.dart';
import 'package:kroma/services/token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// El cliente HTTP compartido por toda la app.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(ref.watch(tokenStorageProvider));

  // Cuando el servidor rechaza el token, la sesión se cierra sola y la app
  // vuelve al login. Se hace con `ref.read` dentro del callback, y no leyendo
  // el controlador al construir el cliente, porque el controlador de sesión
  // depende a su vez de este cliente: leerlo aquí crearía una dependencia
  // circular que Riverpod detectaría al arrancar.
  client.onUnauthorized = () {
    ref.read(authControllerProvider.notifier).handleSessionExpired();
  };

  return client;
});
