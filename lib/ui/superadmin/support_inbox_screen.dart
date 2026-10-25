import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/contact_utils.dart';
import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../data/models/support_models.dart';
import '../../data/services/support_service.dart';
import '../../theme/qoima_design.dart';
import '../support/support_widgets.dart';

/// Superadmin: қолдау чатының кіріс жәшігі (барлық пайдаланушы тредтері).
class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen({super.key});

  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

enum _StatusFilter { open, closed, all }

enum _RoleFilter { all, client, store, courier }

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  final _service = SupportService();
  final _search = TextEditingController();
  StreamSubscription<List<SupportThread>>? _sub;
  List<SupportThread> _threads = const [];
  bool _loading = true;
  Object? _error;
  _StatusFilter _status = _StatusFilter.open;
  _RoleFilter _role = _RoleFilter.all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _sub = _service.watchAllThreads().listen((list) {
      if (!mounted) return;
      setState(() {
        _threads = list;
        _loading = false;
        _error = null;
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<SupportThread> get _filtered {
    final q = _query.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return _threads.where((t) {
      switch (_status) {
        case _StatusFilter.open:
          if (!t.isOpen) return false;
        case _StatusFilter.closed:
          if (t.isOpen) return false;
        case _StatusFilter.all:
          break;
      }
      switch (_role) {
        case _RoleFilter.client:
          if (t.userRole != SupportThread.roleClient) return false;
        case _RoleFilter.store:
          if (!t.isStoreSide) return false;
        case _RoleFilter.courier:
          if (t.userRole != SupportThread.roleCourier) return false;
        case _RoleFilter.all:
          break;
      }
      if (q.isEmpty) return true;
      if (t.userName.toLowerCase().contains(q)) return true;
      if (t.storeName.toLowerCase().contains(q)) return true;
      if (digits.length >= 3 &&
          t.userPhone.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)) {
        return true;
      }
      return false;
    }).toList();
  }

  int get _totalUnread => _threads.where((t) => t.unreadForStaff > 0).length;

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Чат поддержки', 'Қолдау чаты'),
          subtitle: _totalUnread > 0
              ? tr('Ждут ответа: $_totalUnread', 'Жауап күтеді: $_totalUnread')
              : tr('Обращения пользователей', 'Пайдаланушы өтініштері'),
          showBack: true,
          compact: true,
          bottom: [
            const SizedBox(height: 12),
            _searchField(),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _Chip(
                      label: tr('Открытые', 'Ашық'),
                      active: _status == _StatusFilter.open,
                      onTap: () =>
                          setState(() => _status = _StatusFilter.open)),
                  _Chip(
                      label: tr('Закрытые', 'Жабық'),
                      active: _status == _StatusFilter.closed,
                      onTap: () =>
                          setState(() => _status = _StatusFilter.closed)),
                  _Chip(
                      label: tr('Все', 'Барлығы'),
                      active: _status == _StatusFilter.all,
                      onTap: () => setState(() => _status = _StatusFilter.all)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _Chip(
                      label: tr('Все роли', 'Барлық рөл'),
                      active: _role == _RoleFilter.all,
                      onTap: () => setState(() => _role = _RoleFilter.all)),
                  _Chip(
                      label: tr('Клиент', 'Клиент'),
                      active: _role == _RoleFilter.client,
                      onTap: () => setState(() => _role = _RoleFilter.client)),
                  _Chip(
                      label: tr('Магазин', 'Дүкен'),
                      active: _role == _RoleFilter.store,
                      onTap: () => setState(() => _role = _RoleFilter.store)),
                  _Chip(
                      label: tr('Курьер', 'Курьер'),
                      active: _role == _RoleFilter.courier,
                      onTap: () => setState(() => _role = _RoleFilter.courier)),
                ],
              ),
            ),
          ],
        ),
        Expanded(child: _body(list)),
      ]),
    );
  }

  Widget _searchField() => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(kRPill),
        ),
        child: Row(children: [
          const Icon(Icons.search_rounded, color: Colors.white, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: manrope(14, FontWeight.w600, color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText:
                    tr('Имя, магазин или телефон', 'Аты, дүкен немесе телефон'),
                hintStyle: manrope(14, FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.75)),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _search.clear();
                _query = '';
              }),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
        ]),
      );

  Widget _body(List<SupportThread> list) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    if (_error != null && _threads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(friendlyError(_error),
              textAlign: TextAlign.center,
              style: manrope(13, FontWeight.w600, color: cInk3)),
        ),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.forum_outlined, size: 44, color: cInk3),
          const SizedBox(height: 10),
          Text(tr('Обращений нет', 'Өтініштер жоқ'),
              style: manrope(14, FontWeight.w700, color: cInk2)),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ThreadTile(
        thread: list[i],
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SupportThreadScreen(threadId: list[i].id))),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(kRPill),
        ),
        child: Text(label,
            style: manrope(12.5, FontWeight.w700,
                color: active ? cGreenDeep : Colors.white)),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final SupportThread thread;
  final VoidCallback onTap;
  const _ThreadTile({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = thread;
    final name = t.userName.isNotEmpty
        ? t.userName
        : (t.userPhone.isNotEmpty ? t.userPhone : tr('Без имени', 'Аты жоқ'));
    return GestureDetector(
      onTap: onTap,
      child: QCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          QIconTile(
            tone: supportRoleTone(t.userRole),
            size: 44,
            icon: Icon(supportRoleIcon(t.userRole),
                color: t.userRole == SupportThread.roleCourier
                    ? cAmberInk
                    : (t.isStoreSide ? cBlueInk : cGreenDeep),
                size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(14, FontWeight.w800, color: cInk)),
                  ),
                  const SizedBox(width: 6),
                  Text(supportShortDate(t.lastMessageAt),
                      style: manrope(11, FontWeight.w600, color: cInk3)),
                ]),
                const SizedBox(height: 2),
                Text(
                    [
                      supportRoleLabel(t.userRole),
                      if (t.storeName.isNotEmpty) t.storeName,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(11.5, FontWeight.w600, color: cInk3)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Text(t.lastMessagePreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(
                            13,
                            t.unreadForStaff > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: t.unreadForStaff > 0 ? cInk : cInk2)),
                  ),
                  if (!t.isOpen)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: QPill(tr('Закрыт', 'Жабық'), tone: 'gray'),
                    ),
                  if (t.unreadForStaff > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      constraints:
                          const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                          color: cRed,
                          borderRadius: BorderRadius.circular(kRPill)),
                      child: Center(
                        child: Text(
                            t.unreadForStaff > 99
                                ? '99+'
                                : '${t.unreadForStaff}',
                            style: manrope(10.5, FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Бір тред: пайдаланушы туралы карточка + хат алмасу + жауап жолағы.
class SupportThreadScreen extends StatefulWidget {
  final String threadId;
  const SupportThreadScreen({super.key, required this.threadId});

  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  final _service = SupportService();
  StreamSubscription<SupportThread?>? _sub;
  SupportThread? _thread;
  bool _loading = true;
  bool _infoOpen = true;
  bool _markedOnce = false;

  @override
  void initState() {
    super.initState();
    _sub = _service.watchThread(widget.threadId).listen((t) {
      if (!mounted) return;
      setState(() {
        _thread = t;
        _loading = false;
      });
      if (t != null && (!_markedOnce || t.unreadForStaff > 0)) {
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
    super.dispose();
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

  Future<void> _toggleStatus() async {
    final t = _thread;
    if (t == null) return;
    final next =
        t.isOpen ? SupportThread.statusClosed : SupportThread.statusOpen;
    try {
      await _service.setStatus(t.id, next);
      _snack(
          t.isOpen
              ? tr('Обращение закрыто', 'Өтініш жабылды')
              : tr('Обращение открыто снова', 'Өтініш қайта ашылды'),
          cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _thread;
    final title = t == null
        ? tr('Обращение', 'Өтініш')
        : (t.userName.isNotEmpty
            ? t.userName
            : (t.userPhone.isNotEmpty
                ? t.userPhone
                : tr('Обращение', 'Өтініш')));
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: title,
          subtitle: t == null ? null : supportRoleLabel(t.userRole),
          showBack: true,
          compact: true,
          action: t == null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  QHeaderBtn(
                      _infoOpen
                          ? Icons.expand_less_rounded
                          : Icons.info_outline_rounded,
                      onTap: () => setState(() => _infoOpen = !_infoOpen)),
                  const SizedBox(width: 8),
                  QHeaderBtn(
                      t.isOpen
                          ? Icons.check_circle_outline_rounded
                          : Icons.replay_rounded,
                      onTap: _toggleStatus),
                ]),
        ),
        if (t != null && _infoOpen) _infoCard(t),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : t == null
                  ? Center(
                      child: Text(tr('Чат не найден', 'Чат табылмады'),
                          style: manrope(14, FontWeight.w600, color: cInk3)))
                  : SupportConversationView(
                      threadId: t.id,
                      asStaff: true,
                      onSend: (body, img) =>
                          _service.reply(t.id, body, imageUrl: img),
                    ),
        ),
      ]),
    );
  }

  Widget _infoCard(SupportThread t) {
    final phone = t.userPhone;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: QCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            QPill(supportRoleLabel(t.userRole),
                tone: supportRoleTone(t.userRole)),
            const SizedBox(width: 8),
            QPill(t.isOpen ? tr('Открыт', 'Ашық') : tr('Закрыт', 'Жабық'),
                tone: t.isOpen ? 'green' : 'gray'),
          ]),
          const SizedBox(height: 10),
          _row(Icons.person_outline_rounded,
              t.userName.isEmpty ? '—' : t.userName),
          if (t.storeName.isNotEmpty)
            _row(Icons.storefront_outlined, t.storeName),
          _row(Icons.phone_outlined, phone.isEmpty ? '—' : phone),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: QSoftButton(
                  label: tr('Позвонить', 'Қоңырау'),
                  height: 40,
                  icon: const Icon(Icons.call_rounded, size: 18),
                  onPressed: () => _safe(() => makePhoneCall(phone)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: QSoftButton(
                  label: 'WhatsApp',
                  height: 40,
                  tone: 'blue',
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  onPressed: () => _safe(() => openWhatsApp(
                      phone,
                      tr('Здравствуйте! Это поддержка Qoima.',
                          'Сәлем! Бұл Qoima қолдау қызметі.'))),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: cInk3),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(text,
                style: manrope(13, FontWeight.w600, color: cInk)),
          ),
        ]),
      );
}
