import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_user.dart';
import '../../core/feature_flags.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../data/models/support_models.dart';
import '../../data/services/support_service.dart';
import '../../theme/qoima_design.dart';
import '../shared/require_login.dart';
import '../superadmin/support_inbox_screen.dart';
import 'support_widgets.dart';

/// Қолдау чатын ашу — кез келген рөл (клиент, иесі, сатушы, курьер) үшін.
///
/// Guest болса «Кіру қажет» диалогы. Функцияны суперадмин өшірсе —
/// жаңа чат ашылмайды (бұрынғы жазбалар сақталады). Модератор өзі басса —
/// кіріс жәшігіне түседі.
Future<void> openSupportChat(BuildContext context) async {
  final ok = await requireLogin(
    context,
    reasonRu: 'Войдите, чтобы написать в поддержку.',
    reasonKk: 'Қолдау қызметіне жазу үшін кіріңіз.',
  );
  if (!ok || !context.mounted) return;

  if (context.read<AppUser>().isSuperadmin) {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const SupportInboxScreen()));
    return;
  }
  if (!FeatureFlags.instance.isOn(FeatureFlags.supportChat)) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content:
            Text(comingSoonText()),
        backgroundColor: cInk,
        behavior: SnackBarBehavior.floating,
      ));
    return;
  }
  await Navigator.push(
      context, MaterialPageRoute(builder: (_) => const SupportChatScreen()));
}

/// Пайдаланушының қолдау чаты (бір тред).
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _service = SupportService();
  final _text = TextEditingController();
  StreamSubscription<SupportThread?>? _sub;
  SupportThread? _thread;
  String? _threadId;
  bool _loading = true;
  bool _markedOnce = false;

  @override
  void initState() {
    super.initState();
    _sub = _service.watchMyThread().listen((t) {
      if (!mounted) return;
      setState(() {
        _thread = t;
        _threadId = t?.id ?? _threadId;
        _loading = false;
      });
      // Экран ашық кезде келген жауап та бірден оқылды болады.
      if (t != null && (!_markedOnce || t.unreadForUser > 0)) {
        _markedOnce = true;
        _service.markRead(t.id);
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String body, String? imageUrl) async {
    await _service.send(body, imageUrl: imageUrl);
    // Алғашқы хабарламада тред жаңа құрылады — id-ді бірден аламыз
    // (realtime INSERT оқиғасы кешігуі мүмкін).
    if (_threadId == null) {
      try {
        final t = await _service.getMyThread();
        if (mounted && t != null) {
          setState(() {
            _thread = t;
            _threadId = t.id;
          });
        }
      } catch (_) {
        // Хабарлама сақталып қойды — id-ді watchMyThread әлі жеткізеді.
        // Қатені лақтырсақ, пайдаланушы қайта басып, хабарлама қосарланады.
      }
    }
  }

  void _prefill(String text) {
    HapticFeedback.selectionClick();
    _text.text = text;
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  Widget _welcome() {
    final topics = <(String, String, String, String)>[
      ('Заказ', 'Тапсырыс', 'По заказу: ', 'Тапсырыс бойынша: '),
      ('Оплата', 'Төлем', 'По оплате: ', 'Төлем бойынша: '),
      ('Возврат', 'Қайтару', 'По возврату: ', 'Қайтару бойынша: '),
      ('Магазин', 'Дүкен', 'По магазину: ', 'Дүкен бойынша: '),
      ('Другое', 'Басқа', '', ''),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration:
                const BoxDecoration(color: cGreenTint, shape: BoxShape.circle),
            child: const Icon(Icons.support_agent_rounded,
                color: cGreen, size: 36),
          ),
        ),
        const SizedBox(height: 16),
        Text(tr('Здравствуйте! Чем помочь?', 'Сәлем! Қалай көмектесе аламыз?'),
            textAlign: TextAlign.center,
            style: manrope(18, FontWeight.w800, color: cInk)),
        const SizedBox(height: 8),
        Text(
            tr('Напишите свой вопрос — служба поддержки Qoima ответит прямо здесь. Можно прикрепить фото.',
                'Сұрағыңызды жазыңыз — Qoima қолдау қызметі дәл осы жерде жауап береді. Сурет тіркеуге болады.'),
            textAlign: TextAlign.center,
            style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.4)),
        const SizedBox(height: 20),
        Text(tr('Частые темы', 'Жиі тақырыптар'),
            textAlign: TextAlign.center,
            style: manrope(12, FontWeight.w700, color: cInk3)),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in topics)
              ActionChip(
                label: Text(tr(t.$1, t.$2),
                    style: manrope(13, FontWeight.w700, color: cGreenDeep)),
                backgroundColor: cGreenTint,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kRPill)),
                onPressed: () => _prefill(tr(t.$3, t.$4)),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final closed = _thread != null && !_thread!.isOpen;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Поддержка Qoima', 'Qoima қолдау қызметі'),
          subtitle: tr('Обычно отвечаем в течение дня',
              'Әдетте күн ішінде жауап береміз'),
          showBack: true,
          compact: true,
        ),
        if (closed)
          Container(
            width: double.infinity,
            color: cAmberTint,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
                tr('Обращение закрыто. Напишите — оно откроется снова.',
                    'Өтініш жабылған. Жазсаңыз — қайта ашылады.'),
                style: manrope(12, FontWeight.w600, color: cAmberInk)),
          ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : ListenableBuilder(
                  listenable: FeatureFlags.instance,
                  builder: (_, __) => SupportConversationView(
                    threadId: _threadId,
                    asStaff: false,
                    controller: _text,
                    onSend: _send,
                    emptyState: _welcome(),
                    enabled:
                        FeatureFlags.instance.isOn(FeatureFlags.supportChat),
                    disabledHint: tr(
                        'Чат поддержки скоро снова будет доступен. Прежние сообщения сохранены.',
                        'Қолдау чаты жақында қайта қолжетімді болады. Бұрынғы хабарламалар сақталған.'),
                  ),
                ),
        ),
      ]),
    );
  }
}
