import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/services/api_exception.dart';
import 'package:kroma/providers/api_providers.dart';
import 'package:kroma/services/auth_service.dart';
import 'package:kroma/models/auth_user.dart';

/// En qué punto está la sesión.
sealed class AuthState {
  const AuthState();
}

/// Comprobando si hay una sesión guardada. Es el estado al arrancar.
class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut({this.message});

  /// Motivo por el que se cerró la sesión, si lo hubo.
  ///
  /// Sirve para avisar de que el token caducó en vez de devolver al login sin
  /// explicación, que se percibe como un fallo de la app.
  final String? message;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);

  final AuthUser user;
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // La restauración se lanza sin esperarla porque `build` es síncrono. El
    // estado arranca en «cargando» y cambia solo cuando se sabe la respuesta.
    Future.microtask(_restoreSession);
    return const AuthLoading();
  }

  /// Recupera la sesión guardada al abrir la app.
  Future<void> _restoreSession() async {
    final token = await ref.read(tokenStorageProvider).read();

    if (token == null) {
      state = const AuthSignedOut();
      return;
    }

    try {
      // No basta con que haya un token guardado: puede haber caducado o la
      // cuenta puede haberse borrado. Se pregunta al servidor quién es antes de
      // dar la sesión por buena, y así se entra ya validado.
      final user = await ref.read(authServiceProvider).me();
      state = AuthSignedIn(user);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await ref.read(tokenStorageProvider).clear();
        state = const AuthSignedOut();
      } else {
        // Un fallo de red no es una sesión inválida. Aun así hay que salir del
        // estado de carga, o la app se quedaría en la pantalla de espera para
        // siempre; el mensaje explica que fue la conexión.
        state = AuthSignedOut(message: error.message);
      }
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final result = await ref.read(authServiceProvider).login(
          email: email,
          password: password,
        );
    await _persist(result);
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final result = await ref.read(authServiceProvider).register(
          email: email,
          password: password,
          displayName: displayName,
        );
    await _persist(result);
  }

  Future<void> signOut() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AuthSignedOut();
  }

  /// Lo llama el cliente HTTP cuando el servidor rechaza el token.
  void handleSessionExpired() {
    // El token ya lo borró el propio cliente antes de avisar, así que aquí solo
    // queda reflejarlo en la interfaz.
    if (state is AuthSignedOut) return;
    state = const AuthSignedOut(
      message: 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
    );
  }

  Future<void> _persist(AuthResult result) async {
    await ref.read(tokenStorageProvider).write(result.token);
    state = AuthSignedIn(result.user);
  }
}
