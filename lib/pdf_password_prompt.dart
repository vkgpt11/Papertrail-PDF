import 'package:flutter/material.dart';

class PdfPasswordPromptResult {
  const PdfPasswordPromptResult.password(this.password) : cancelled = false;
  const PdfPasswordPromptResult.cancelled() : password = null, cancelled = true;

  final String? password;
  final bool cancelled;
}

class PdfPasswordPromptDialog extends StatefulWidget {
  const PdfPasswordPromptDialog({required this.incorrectPassword, super.key});

  final bool incorrectPassword;

  @override
  State<PdfPasswordPromptDialog> createState() =>
      _PdfPasswordPromptDialogState();
}

class _PdfPasswordPromptDialogState extends State<PdfPasswordPromptDialog> {
  final _controller = TextEditingController();
  bool _canSubmit = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isEmpty) return;
    Navigator.pop(context, PdfPasswordPromptResult.password(password));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Password required'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'PDF password',
          errorText: widget.incorrectPassword
              ? 'Incorrect password. Try again.'
              : null,
        ),
        onChanged: (value) {
          final canSubmit = value.isNotEmpty;
          if (canSubmit != _canSubmit) {
            setState(() => _canSubmit = canSubmit);
          }
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, const PdfPasswordPromptResult.cancelled()),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('Open'),
        ),
      ],
    ),
  );
}
