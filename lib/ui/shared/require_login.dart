import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';
import '../auth/auth_widgets.dart';
import '../auth/login_screen.dart';

/// Әрекет алдында кіруді талап етеді (сыйлық, тілек тізімі, AI, live-чат).
///
/// Кірген болса — бірден true. Guest болса — «Кіру қажет» диалогын көрсетіп,
/// келіссе LoginScreen-ге жібереді және false қайтарады: кіргеннен кейін
/// _RootGate ағашты ClientShell-ге реактивті ауыстырады, әрекетті қолданушы
/// қайта бастайды.
Future<bool> requireLogin(
  BuildContext context, {
  required String reasonRu,
  required String reasonKk,
}) async {
  if (context.read<AppUser>().uid.isNotEmpty) return true;
  final goLogin = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(tr('Нужен вход', 'Кіру қажет'),
          style: manrope(16, FontWeight.w800, color: cInk)),
      content: Text(tr(reasonRu, reasonKk),
          style: manrope(14, FontWeight.w500, color: cInk2)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Отмена', 'Болдырмау'),
                style: manrope(14, FontWeight.w600, color: cInk2))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Войти', 'Кіру'),
                style: manrope(14, FontWeight.w700, color: cGreen))),
      ],
    ),
  );
  if (goLogin == true && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: kLoginRouteName),
        builder: (_) => const LoginScreen(),
      ),
    );
  }
  return false;
}
