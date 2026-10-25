import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../core/push_navigation.dart';
import '../../data/models/live_models.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import '../client/client_shell.dart';
import '../guest/guest_shell.dart';
import '../shared/require_login.dart';
import 'live_viewer_screen.dart';

/// Эфирді көрермен ретінде ашу (home қатары, дүкен баннері, push, deep link).
///
/// Көру үшін LiveKit токені керек → алдымен кіруді талап етеміз. Эфир
/// табылмаса не аяқталған болса — snackbar, экран ашылмайды.
Future<void> openLiveSession(BuildContext context, String sessionId) async {
  if (sessionId.isEmpty) return;
  // Суперадмин өшірсе — push/deep link арқылы келсе де ашылмайды.
  await FeatureFlags.instance.refresh();
  if (!context.mounted) return;
  if (!FeatureFlags.instance.isOn(FeatureFlags.liveShopping)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(tr('Функция временно отключена', 'Функция уақытша өшірулі')),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  final ok = await requireLogin(
    context,
    reasonRu: 'Войдите, чтобы смотреть эфир и общаться в чате.',
    reasonKk: 'Эфирді көріп, чатта жазу үшін кіріңіз.',
  );
  if (!ok || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  LiveSession? session;
  try {
    session = await LiveService().getSession(sessionId);
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(liveErrorText(e)),
      backgroundColor: cRed,
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  if (!context.mounted) return;
  if (session == null || !session.isLive) {
    messenger.showSnackBar(SnackBar(
      content: Text(session == null
          ? tr('Эфир не найден', 'Эфир табылмады')
          : tr('Эфир завершён', 'Эфир аяқталды')),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => LiveViewerScreen(session: session!),
  ));
}

/// Кез келген (push етілген) экраннан Себет табына өту: стекті бірінші
/// маршрутқа дейін жабамыз да, shell-ді элемент ағашынан тауып таб ауыстырамыз.
///
/// НЕГЕ АҒАШТАН ІЗДЕЙМІЗ: push етілген экран shell-дің ұрпағы емес (бір
/// Navigator-дағы көрші маршрут), сондықтан findAncestorStateOfType оны
/// таппайды. Shell-де GlobalKey жоқ — оны өзгертпеу үшін ағашты бір рет
/// аралаймыз (тек батырма басылғанда).
void openCartTab(BuildContext context) {
  Navigator.of(context).popUntil((r) => r.isFirst);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final root = rootNavigatorKey.currentContext;
    if (root == null) return;
    State? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement &&
          (e.state is ClientShellState || e.state is GuestShellState)) {
        found = e.state;
        return;
      }
      e.visitChildren(visit);
    }

    root.visitChildElements(visit);
    final s = found;
    if (s is ClientShellState) {
      s.setIndex(2); // 2 = Себет
    } else if (s is GuestShellState) {
      s.setIndex(2);
    }
  });
}
