import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';

const _kCooldown = Duration(days: 7);

/// Дүкеннің өз жарнама push-ы: таңдаулыға қосқан + бұрын сатып алған
/// клиенттерге бірыңғай хабарлама (акция, жаңа коллекция т.б.). Спамнан
/// қорғау — аптасына 1 рет (0043 БД триггерінде нақты шектеледі, бұл
/// экран тек соны алдын ала көрсетеді/есептейді).
class StoreBroadcastScreen extends StatefulWidget {
  const StoreBroadcastScreen({super.key});

  @override
  State<StoreBroadcastScreen> createState() => _StoreBroadcastScreenState();
}

class _StoreBroadcastScreenState extends State<StoreBroadcastScreen> {
  final _service = FirestoreService();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  DateTime? _lastSentAt;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait(
          [_service.getLastBroadcastAt(), _service.getBroadcastHistory()]);
      if (!mounted) return;
      setState(() {
        _lastSentAt = results[0] as DateTime?;
        _history = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Duration? get _remainingCooldown {
    final last = _lastSentAt;
    if (last == null) return null;
    final left = _kCooldown - DateTime.now().difference(last);
    return left.isNegative ? null : left;
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty || _sending || _remainingCooldown != null) {
      return;
    }
    setState(() => _sending = true);
    try {
      await _service.sendStoreBroadcast(title: title, body: body);
      if (!mounted) return;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Рассылка отправлена!', 'Хабарлама жіберілді!')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      final rateLimited = e is PostgrestException &&
          (e.message.contains('broadcast_rate_limited'));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(rateLimited
            ? tr('Рассылку можно отправлять раз в 7 дней',
                'Хабарламаны 7 күнде 1 рет жіберуге болады')
            : tr('Не удалось отправить рассылку', 'Хабарламаны жіберу мүмкін болмады')),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _cooldownLabel(Duration d) {
    if (d.inDays >= 1) {
      return tr('через ${d.inDays} дн.', '${d.inDays} күннен кейін');
    }
    return tr('через ${d.inHours} ч.', '${d.inHours} сағаттан кейін');
  }

  @override
  Widget build(BuildContext context) {
    final cooldown = _remainingCooldown;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Рассылка клиентам', 'Клиенттерге хабарлама'),
          subtitle: tr('Акции и новости — раз в 7 дней', 'Акция мен жаңалық — 7 күнде 1 рет'),
          showBack: true,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cSurface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cLine),
                        boxShadow: kShadowSm,
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('Новое сообщение', 'Жаңа хабарлама'),
                            style: manrope(15, FontWeight.w800, color: cInk)),
                        const SizedBox(height: 3),
                        Text(
                            tr('Получат все, кто добавил ваш товар в избранное или уже покупал у вас',
                                'Тауарыңызды таңдаулыға қосқан немесе сізден бұрын сатып алған клиенттер алады'),
                            style: manrope(11.5, FontWeight.w500, color: cInk3)),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _titleCtrl,
                          maxLength: 60,
                          enabled: cooldown == null,
                          decoration: InputDecoration(
                            labelText: tr('Заголовок', 'Тақырып'),
                            hintText: tr('Новая коллекция уже в магазине!',
                                'Жаңа коллекция дүкенде!'),
                            prefixIcon: const Icon(Icons.campaign_outlined, color: cGreen, size: 20),
                          ),
                        ),
                        TextField(
                          controller: _bodyCtrl,
                          maxLength: 200,
                          maxLines: 3,
                          enabled: cooldown == null,
                          decoration: InputDecoration(
                            labelText: tr('Текст сообщения', 'Хабарлама мәтіні'),
                            hintText: tr('Скидка 20% на всё до конца недели',
                                'Аптаның соңына дейін бәріне 20% жеңілдік'),
                            alignLabelWithHint: true,
                            prefixIcon: const Icon(Icons.notes_rounded, color: cGreen, size: 20),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (cooldown != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: cAmberTint,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Row(children: [
                              const Icon(Icons.schedule_rounded, size: 16, color: cAmber),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                    tr('Следующая рассылка доступна ${_cooldownLabel(cooldown)}',
                                        'Келесі хабарлама ${_cooldownLabel(cooldown)} қолжетімді'),
                                    style: manrope(12, FontWeight.w700,
                                        color: const Color(0xFFB4770A))),
                              ),
                            ]),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _sending ? null : _send,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cGreen,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(13)),
                              ),
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : Text(tr('Отправить', 'Жіберу'),
                                      style: manrope(14.5, FontWeight.w700)),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    if (_history.isNotEmpty) ...[
                      QSecLabel(tr('История рассылок', 'Хабарламалар тарихы')),
                      const SizedBox(height: 8),
                      ..._history.map((h) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: cSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cLine),
                            ),
                            child: Row(children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: cGreenTint, borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.campaign_rounded, color: cGreen, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(h['title'] as String? ?? '',
                                      style: manrope(13, FontWeight.w700, color: cInk),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(h['body'] as String? ?? '',
                                      style: manrope(11.5, FontWeight.w500, color: cInk3),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ]),
                              ),
                              Text(
                                  tr('${h['recipient_count'] ?? 0} получат',
                                      '${h['recipient_count'] ?? 0} алды'),
                                  style: manrope(11, FontWeight.w700, color: cGreen)),
                            ]),
                          )),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }
}
