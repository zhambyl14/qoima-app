import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../core/push_navigation.dart';
import '../../data/models/live_models.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import '../client/client_shell.dart';
import '../guest/guest_shell.dart';
import '../shared/require_login.dart';
import 'live_viewer_screen.dart';

/// Жалаушалар жүктелгенше күтеді. refresh() басқа жүктеу жүріп жатса бірден
/// қайтады (суық старттағы push/deep link), сондықтан бос кэшті «өшік» деп
/// оқымас үшін жүктелгенше аз-аздап қайталаймыз (ең көбі ~3 с).
Future<void> ensureLiveFlagLoaded() async {
  for (var i = 0; i < 20 && !FeatureFlags.instance.isLoaded; i++) {
    await FeatureFlags.instance.refresh();
    if (FeatureFlags.instance.isLoaded) break;
    await Future.delayed(const Duration(milliseconds: 150));
  }
  // Жүктелген болса да, ескірген мәнді жаңартып аламыз.
  await FeatureFlags.instance.refresh();
}

/// Эфирді көрермен ретінде ашу (home қатары, дүкен баннері, push, deep link).
///
/// Көру үшін LiveKit токені керек → алдымен кіруді талап етеміз. Эфир
/// табылмаса не аяқталған болса — snackbar, экран ашылмайды.
///
/// [onUnavailable] — эфир табылмаса/аяқталса snackbar-дан кейін шақырылады
/// (push: «Барлық эфирлер» тізімін ашу үшін).
Future<void> openLiveSession(BuildContext context, String sessionId,
    {VoidCallback? onUnavailable}) async {
  if (sessionId.isEmpty) return;
  // Суперадмин өшірсе — push/deep link арқылы келсе де ашылмайды.
  await ensureLiveFlagLoaded();
  if (!context.mounted) return;
  if (!FeatureFlags.instance.isOn(FeatureFlags.liveShopping)) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(comingSoonText()),
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
    onUnavailable?.call();
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
  // Экран жабылып қойған болуы мүмкін (snackbar әрекеті кейін басылады) —
  // сондықтан контекстке емес, түбірлік Navigator-ға сүйенеміз.
  final nav = rootNavigatorKey.currentState ??
      (context.mounted ? Navigator.of(context) : null);
  nav?.popUntil((r) => r.isFirst);
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
