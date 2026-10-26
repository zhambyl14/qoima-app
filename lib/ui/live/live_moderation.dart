import 'package:flutter/material.dart';

import '../../core/lang.dart';
import '../../data/models/live_models.dart';
import '../../data/services/live_service.dart';
import '../../theme/qoima_design.dart';
import '../client/report_sheet.dart';

/// Чат хабарына ұзақ басқанда ашылатын әрекеттер парағы (UGC талаптары:
/// шағымдану + бұғаттау). Көрермен: шағым + осы қолданушыны жасыру (тек өзіне).
/// Хост: шағым + хабарды жою + қолданушыны чатта бұғаттау (серверде).
///
/// Шағым бар `content_reports` ағынымен кетеді: target_type='store' (CHECK
/// тізімін өзгертпеу үшін), target_name-де хабар мәтіні мен автор көрсетіледі.
Future<void> showLiveMessageActions(
  BuildContext context, {
  required LiveMessage message,
  required String sessionId,
  required String adminUid,
  required String storeName,
  required bool asHost,
  VoidCallback? onHideUser,
}) async {
  final svc = LiveService();
  final messenger = ScaffoldMessenger.of(context);
  void say(String text, {bool error = false}) {
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? cRed : cGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  final preview = message.body.length > 60
      ? '${message.body.substring(0, 60)}…'
      : message.body;
  final who = message.userName.isNotEmpty
      ? message.userName
      : tr('Покупатель', 'Сатып алушы');

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: cSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) {
      Widget tile(IconData icon, String label, Color color, VoidCallback tap) =>
          ListTile(
            leading: Icon(icon, color: color),
            title: Text(label,
                style: manrope(14.5, FontWeight.w700, color: color)),
            onTap: () {
              Navigator.pop(ctx);
              tap();
            },
          );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              decoration: BoxDecoration(
                  color: cLine, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('$who: $preview',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(13, FontWeight.w500, color: cInk3)),
            ),
            tile(Icons.flag_outlined, tr('Пожаловаться', 'Шағымдану'), cInk,
                () {
              showReportSheet(
                context,
                targetType: 'store',
                targetId: adminUid,
                targetName:
                    '💬 ${tr('Чат эфира', 'Эфир чаты')}: «$preview» — $who',
                adminUid: adminUid,
                storeName: storeName,
              );
            }),
            if (!asHost && onHideUser != null)
              tile(
                  Icons.visibility_off_outlined,
                  tr('Скрыть сообщения этого пользователя',
                      'Бұл қолданушының хабарларын жасыру'),
                  cInk, () {
                onHideUser();
                say(tr('Сообщения пользователя скрыты',
                    'Қолданушының хабарлары жасырылды'));
              }),
            if (asHost) ...[
              tile(Icons.delete_outline_rounded,
                  tr('Удалить сообщение', 'Хабарды жою'), cRed, () async {
                try {
                  await svc.deleteMessage(sessionId, message.id);
                } catch (e) {
                  say(liveErrorText(e), error: true);
                }
              }),
              if (message.userUid.isNotEmpty)
                tile(
                    Icons.block_rounded,
                    tr('Заблокировать в чате', 'Чатта бұғаттау'),
                    cRed, () async {
                  try {
                    await svc.muteUser(sessionId, message.userUid);
                    say(tr('Пользователь заблокирован в чате',
                        'Қолданушы чатта бұғатталды'));
                  } catch (e) {
                    say(liveErrorText(e), error: true);
                  }
                }),
            ],
          ]),
        ),
      );
    },
  );
}
