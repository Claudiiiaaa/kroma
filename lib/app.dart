import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/providers/auth_provider.dart';
import 'package:kroma/ui/screens/login_screen.dart';
import 'package:kroma/ui/screens/board_screen.dart';

class NotesApp extends StatelessWidget {
  const NotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kroma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Decide qué pantalla mostrar según el estado de la sesión.
///
/// Se resuelve observando el estado en lugar de navegando a mano, y por eso al
/// iniciar sesión nadie llama a `Navigator.push`: el estado cambia y esta
/// pantalla se sustituye sola. Lo mismo al caducar el token desde cualquier
/// punto de la app: la sesión se cierra y aquí se vuelve al login sin que la
/// pantalla que estuviera abierta tenga que enterarse.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    // `ref.listen` y no un aviso dentro de `build`: los mensajes son efectos
    // secundarios, y `build` puede ejecutarse muchas veces, lo que repetiría el
    // aviso en cada reconstrucción.
    ref.listen(authControllerProvider, (previous, next) {
      if (next is AuthSignedOut && next.message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(next.message!)));
      }
    });

    return switch (auth) {
      AuthLoading() => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthSignedOut() => const LoginScreen(),
      AuthSignedIn() => const BoardScreen(),
    };
  }
}
