import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_user.dart';
import '../../core/lang.dart';
import '../../data/models/courier_change_request_model.dart';
import '../../data/services/courier_service.dart';
import '../../theme/qoima_design.dart';
import '../auth/account_security_screen.dart';
import '../shared/error_view.dart';
import 'courier_change_request_screen.dart';

/// Курьер — «Менің деректерім» (0074).
///
/// Ағымдағы деректер (аты, телефон, қала, күйі) + соңғы өзгеріс сұранысының
/// күйі. Курьер деректерін ТІКЕЛЕЙ өзгертпейді: «Өзгертуге сұраныс» жібереді,
/// модератор бекітеді. Жұмыс қаласы — курьер қай қаланың тапсырысын
/// көретінін шешеді, сондықтан ол тек модератор арқылы ауысады.
class CourierProfileScreen extends StatefulWidget {
  const CourierProfileScreen({super.key});

  @override
  State<CourierProfileScreen> createState() => _CourierProfileScreenState();
}

class _CourierProfileScreenState extends State<CourierProfileScreen> {
  final _service = CourierService();
  StreamSubscription<CourierProfile?>? _profileSub;
  StreamSubscription<List<CourierChangeRequest>>? _reqSub;

  CourierProfile? _profile;
  List<CourierChangeRequest> _requests = const [];
  bool _loading = true;
  Object? _error;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final uid = AppUser.current.uid;
    _profileSub?.cancel();
    _reqSub?.cancel();
    _profileSub = _service.watchMyProfile(uid).listen((p) {
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
        _error = null;
      });
      // Модератор өзгерткен деректер shell-дегі тақырыпқа да бірден түссін.
      if (p != null) {
        final u = AppUser.current;
        u.updateName(p.name);
        u.updatePhone(p.phone);
        u.updateCity(p.city);
      }
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    });
    _reqSub = _service.watchMyRequests(uid).listen((list) {
      if (!mounted) return;
      setState(() => _requests = list);
    }, onError: (_) {});
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _subscribe();
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _reqSub?.cancel();
    super.dispose();
  }

  CourierChangeRequest? get _pending {
    for (final r in _requests) {
      if (r.isPending) return r;
    }
    return null;
  }

  /// Соңғы шешім (бекітілген/қабылданбаған) — курьер нәтижесін көрсін.
  CourierChangeRequest? get _lastDecision {
    for (final r in _requests) {
      if (r.isApproved || r.isRejected) return r;
    }
    return null;
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _openRequestForm() async {
    final p = _profile;
    if (p == null) return;
    HapticFeedback.selectionClick();
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CourierChangeRequestScreen(profile: p)),
    );
    if (sent == true) {
      _snack(tr('Запрос отправлен модератору', 'Сұраныс модераторға жіберілді'),
          cGreen);
    }
  }

  Future<void> _cancel(CourierChangeRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Отозвать запрос?', 'Сұранысты қайтарып алу керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Нет', 'Жоқ'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cRed, foregroundColor: Colors.white),
              child: Text(tr('Отозвать', 'Қайтарып алу'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await _service.cancelChangeRequest(r.id);
      _snack(tr('Запрос отозван', 'Сұраныс қайтарылды'), cGreen);
    } catch (e) {
      _snack(courierDataErrorText(e), cRed);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Мои данные', 'Менің деректерім'),
          subtitle: tr(
              'Изменения — через модератора', 'Өзгерістер — модератор арқылы'),
          showBack: true,
          compact: true,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : _error != null
                  ? AppErrorView(error: _error, onRetry: _retry)
                  : _profile == null
                      ? AppErrorView(
                          message: tr('Профиль не найден', 'Профиль табылмады'),
                          onRetry: _retry)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          children: [
                            _dataCard(_profile!),
                            const SizedBox(height: 16),
                            if (pending != null) ...[
                              _PendingCard(
                                req: pending,
                                cancelling: _cancelling,
                                onCancel: () => _cancel(pending),
                              ),
                              const SizedBox(height: 16),
                            ] else if (_lastDecision != null) ...[
                              _DecisionCard(req: _lastDecision!),
                              const SizedBox(height: 16),
                            ],
                            QMenuItem(
                              icon: Icons.lock_outline_rounded,
                              tone: 'amber',
                              title: tr('Пароль и номер входа',
                                  'Құпиясөз және кіру нөмірі'),
                              subtitle: tr(
                                  'Сразу, с подтверждением через Telegram',
                                  'Бірден, Telegram арқылы растаумен'),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AccountSecurityScreen(
                                        showPhone: true)),
                              ),
                            ),
                          ],
                        ),
        ),
      ]),
      bottomNavigationBar: (_profile == null || pending != null)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: QPrimaryButton(
                  label: tr('Запросить изменение', 'Өзгертуге сұраныс'),
                  icon: const Icon(Icons.edit_note_rounded,
                      color: Colors.white, size: 20),
                  onPressed: _openRequestForm,
                ),
              ),
            ),
    );
  }

  Widget _dataCard(CourierProfile p) {
    final status = p.courierStatus.isEmpty ? 'pending' : p.courierStatus;
    final (tone, label) = switch (status) {
      'active' => ('green', tr('Допущен к заказам', 'Тапсырысқа рұқсат бар')),
      'blocked' => ('red', tr('Доступ приостановлен', 'Рұқсат тоқтатылған')),
      _ => ('amber', tr('Ожидает проверки', 'Тексеруді күтуде')),
    };
    return QCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          QIconTile(
            icon: const Icon(Icons.delivery_dining_rounded,
                color: cGreen, size: 22),
            tone: 'green',
            size: 46,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(p.name.isEmpty ? '—' : p.name,
                style: manrope(16, FontWeight.w800, color: cInk),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          QPill(label, tone: tone),
        ]),
        const SizedBox(height: 14),
        _row(Icons.badge_outlined, tr('Имя', 'Есім'), p.name),
        _row(Icons.phone_outlined, tr('Телефон (вход)', 'Телефон (кіру)'),
            p.phone),
        _row(Icons.location_city_outlined, tr('Город работы', 'Жұмыс қаласы'),
            p.city.isEmpty ? '' : trValue(p.city)),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Icon(icon, size: 17, color: cInk3),
          const SizedBox(width: 10),
          Text(label, style: manrope(12.5, FontWeight.w600, color: cInk3)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                textAlign: TextAlign.end,
                style: manrope(13.5, FontWeight.w800,
                    color: value.isEmpty ? cRed : cInk)),
          ),
        ]),
      );
}

/// Өріс атауы (UI үшін).
String courierFieldLabel(String key) => switch (key) {
      'name' => tr('Имя', 'Есім'),
      'phone' => tr('Телефон', 'Телефон'),
      'city' => tr('Город', 'Қала'),
      _ => key,
    };

/// Өріс мәнін көрсету (қала — канондық мән, trValue арқылы).
String courierFieldValue(String key, String value) {
  if (value.isEmpty) return '—';
  return key == 'city' ? trValue(value) : value;
}

class _PendingCard extends StatelessWidget {
  final CourierChangeRequest req;
  final bool cancelling;
  final VoidCallback onCancel;
  const _PendingCard(
      {required this.req, required this.cancelling, required this.onCancel});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cAmberTint,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cAmber.withValues(alpha: 0.6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.hourglass_top_rounded, color: cAmber, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('Запрос на рассмотрении', 'Сұраныс қаралуда'),
                  style: manrope(14, FontWeight.w800, color: cInk)),
            ),
          ]),
          const SizedBox(height: 10),
          for (final e in req.changes.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${courierFieldLabel(e.key)}: '
                '${courierFieldValue(e.key, req.oldValues[e.key] ?? '')} → '
                '${courierFieldValue(e.key, e.value)}',
                style: manrope(12.5, FontWeight.w700, color: cInk2),
              ),
            ),
          if (req.reason.isNotEmpty)
            Text('«${req.reason}»',
                style: manrope(12, FontWeight.w600, color: cInk3)),
          const SizedBox(height: 10),
          QSoftButton(
            label: tr('Отозвать запрос', 'Сұранысты қайтарып алу'),
            tone: 'red',
            height: 40,
            onPressed: cancelling ? null : onCancel,
          ),
        ]),
      );
}

class _DecisionCard extends StatelessWidget {
  final CourierChangeRequest req;
  const _DecisionCard({required this.req});

  @override
  Widget build(BuildContext context) {
    final ok = req.isApproved;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok ? cGreenTint : cRedTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: ok ? cGreen : cRed, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                ok
                    ? tr('Последний запрос одобрен', 'Соңғы сұраныс мақұлданды')
                    : tr('Последний запрос отклонён',
                        'Соңғы сұраныс қабылданбады'),
                style: manrope(13.5, FontWeight.w800, color: cInk)),
            if (!ok && req.rejectReason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(trValue(req.rejectReason),
                  style: manrope(12.5, FontWeight.w600, color: cInk2)),
            ],
          ]),
        ),
      ]),
    );
  }
}
