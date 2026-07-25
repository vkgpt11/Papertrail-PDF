import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class PapertrailNotice {
  static const preferenceKey = 'show_in_app_messages';

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _show(
      context,
      message,
      isError: isError,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static Future<void> _show(
    BuildContext context,
    String message, {
    required bool isError,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(preferenceKey) ?? true) || !context.mounted) return;
    final colors = Theme.of(context).colorScheme;
    final accent = isError ? colors.error : colors.primary;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 8,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: Duration(seconds: isError ? 4 : 3),
          backgroundColor: colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: accent.withValues(alpha: .28)),
          ),
          content: Row(
            children: [
              Icon(
                icon ??
                    (isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded),
                color: accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(label: actionLabel, onPressed: onAction),
        ),
      );
  }
}
