import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/lang.dart';
import '../../../core/supabase_config.dart';
import '../../../data/models/registry_model.dart';
import '../../../theme/qoima_design.dart';
import '../client_shell.dart';
import '../../guest/guest_shell.dart';

/// Тілек тізімінің сілтемесін бөлісу (referral_screen үлгісі).
///
/// [originContext] — батырманың контексі: iPad/iOS share-sheet popover
/// анкерін (sharePositionOrigin) осыдан есептейміз.
Future<void> shareRegistryLink(
  BuildContext originContext, {
  required String title,
  required String occasion,
  required String token,
}) async {
  final url = SupabaseConfig.registryShareUrl(token);
  if (url.isEmpty) {
    ScaffoldMessenger.of(originContext).showSnackBar(SnackBar(
      content: Text(tr('Ссылка пока недоступна', 'Сілтеме әзірге қолжетімсіз')),
      backgroundColor: cRed,
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  final text = tr(
    '${RegistryOccasion.emoji(occasion)} «$title» — мой список желаний в Qoima.\n'
        'Выберите подарок, чтобы мы не повторялись: $url',
    '${RegistryOccasion.emoji(occasion)} «$title» — Qoima-дағы менің тілек тізімім.\n'
        'Сыйлықтар қайталанбауы үшін таңдап алыңыз: $url',
  );
  Rect? origin;
  final box = originContext.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    origin = box.localToGlobal(Offset.zero) & box.size;
  }
  try {
    await Share.share(text, sharePositionOrigin: origin);
  } catch (_) {
    // Бөлісу парағы ашылмаса — сілтемені көшіріп қоямыз.
    await Clipboard.setData(ClipboardData(text: url));
    if (originContext.mounted) {
      ScaffoldMessenger.of(originContext).showSnackBar(SnackBar(
        content: Text(tr('Ссылка скопирована', 'Сілтеме көшірілді')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

/// Тізімнен шыққан push-route-тан Себет табына өту.
///
/// ClientShell — тамыр бет, ал біздің экран оның ҮСТІНЕ push болған route:
/// ол shell-дің ұрпағы емес, сондықтан findAncestorStateOfType жұмыс істемейді.
/// Тамыр route-қа дейін popUntil жасап, кадрдан кейін element ағашынан
/// shell күйін іздейміз (shell-дің кодына тиіспейміз).
void goToCartTab(BuildContext context) {
  Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    State? shell;
    void visit(Element e) {
      if (shell != null) return;
      if (e is StatefulElement &&
          (e.state is ClientShellState || e.state is GuestShellState)) {
        shell = e.state;
        return;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    final s = shell;
    if (s is ClientShellState) {
      s.setIndex(2);
    } else if (s is GuestShellState) {
      s.setIndex(2);
    }
  });
}
