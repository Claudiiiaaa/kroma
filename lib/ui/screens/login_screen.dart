import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kroma/services/api_exception.dart';
import 'package:kroma/providers/auth_provider.dart';

/// Pantalla de acceso, con registro e inicio de sesión en la misma vista.
///
/// Se alternan con un botón en lugar de ponerlos en pantallas separadas: son
/// casi el mismo formulario y así no hay que decidir a cuál llegar primero.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isRegistering = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    // Los controladores de texto retienen memoria y escuchan cambios; sin
    // liberarlos, cada visita a esta pantalla dejaría un rastro que no se
    // recoge.
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final controller = ref.read(authControllerProvider.notifier);

      if (_isRegistering) {
        await controller.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
        );
      } else {
        await controller.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      // No hace falta navegar: al cambiar el estado de sesión, la raíz de la
      // app sustituye esta pantalla por el tablero.
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      // `mounted` porque si la sesión se abrió, este widget ya no existe y
      // llamar a setState sobre un widget desmontado lanza una excepción.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            // Sin límite de ancho, en un monitor grande el formulario se
            // estiraría de lado a lado y sería incómodo de leer.
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.draw_outlined,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    _isRegistering ? 'Crea tu cuenta' : 'Entra en tus notas',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  if (_isRegistering) ...[
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Tu nombre',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'Escribe tu nombre'
                              : null,
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    // Evita que el teclado del móvil ponga mayúscula inicial en
                    // un correo, que siempre va en minúsculas.
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Escribe tu correo';
                      if (!text.contains('@')) return 'Ese correo no es válido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        tooltip: _obscurePassword ? 'Mostrar' : 'Ocultar',
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Escribe tu contraseña';
                      }
                      // Solo al registrarse: al entrar, una contraseña antigua
                      // más corta debe poder usarse igualmente.
                      if (_isRegistering && value.length < 8) {
                        return 'Al menos 8 caracteres';
                      }
                      return null;
                    },
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: theme.colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _busy
                        // Indicador dentro del propio botón: mantiene el
                        // tamaño, así que la pantalla no da un salto al pulsar.
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isRegistering ? 'Crear cuenta' : 'Entrar'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _isRegistering = !_isRegistering;
                              _error = null;
                            }),
                    child: Text(_isRegistering
                        ? '¿Ya tienes cuenta? Entra'
                        : '¿No tienes cuenta? Créala'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
