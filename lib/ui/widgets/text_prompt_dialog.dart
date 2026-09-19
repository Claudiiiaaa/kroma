import 'package:flutter/material.dart';

/// Pide un texto al usuario y lo devuelve, o `null` si cancela.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String initialValue = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextPromptDialog(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      initialValue: initialValue,
    ),
  );
}

/// Diálogo con un único campo de texto.
///
/// Es un widget con estado **porque tiene que serlo**, y el motivo es una
/// trampa clásica de Flutter. Lo natural parece crear el `TextEditingController`
/// en la función que abre el diálogo y liberarlo en cuanto `showDialog`
/// devuelve el valor:
///
/// ```dart
/// final controller = TextEditingController();
/// final result = await showDialog(...);
/// controller.dispose();   // ← revienta
/// ```
///
/// Pero `showDialog` devuelve el valor **en cuanto se pulsa el botón**, no
/// cuando el diálogo desaparece de la pantalla: todavía queda la animación de
/// cierre, durante la cual el campo de texto se sigue reconstruyendo. Para
/// entonces el controlador ya está liberado y salta el error «A
/// TextEditingController was used after being disposed», que además arrastra un
/// «Tried to build dirty widget in the wrong build scope».
///
/// Teniendo el controlador dentro de un `State`, Flutter llama a `dispose`
/// cuando el widget sale del árbol de verdad, ya terminada la animación.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.initialValue,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String initialValue;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      // Deja el cursor al final y el texto seleccionado, para que al renombrar
      // se pueda escribir encima directamente sin tener que borrar antes.
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialValue.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        // Enter confirma, que es lo que espera quien escribe con teclado.
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
