import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../core/phone_input.dart';
import '../../data/models/courier_change_request_model.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../data/services/courier_service.dart';
import '../../theme/qoima_design.dart';
import '../courier/courier_data_fields.dart';
import 'courier_change_requests_screen.dart';
import 'courier_orders_tab.dart';

/// Superadmin — курьерлерді басқару.
///
/// Курьер дүкенге емес, тікелей модераторға бағынады: тіркелген соң
/// 'pending' күйінде тұрады да, осы экраннан бекітілгенше бірде-бір
/// тапсырысты (демек, клиенттің мекенжайы мен телефонын) көрмейді.
class CouriersScreen extends StatefulWidget {
  const CouriersScreen({super.key});

  @override
  State<CouriersScreen> createState() => _CouriersScreenState();
}

class _CouriersScreenState extends State<CouriersScreen> {
  final _repo = StoreModerationRepository();
  final _service = CourierService();
  // Стримдер build()-те емес, бір рет жасалады (realtime арнасы көбеймесін).
  late final Stream<List<CourierProfile>> _couriersStream =
      _service.watchCourierProfiles();
  late final Stream<List<CourierChangeRequest>> _requestsStream =
      _service.watchAllChangeRequests();
  // 0 Күтуде · 1 Белсенді · 2 Бұғатталған · 3 ТАПСЫРЫСТАР (0060).
  // Соңғысы курьерлердің НАҚТЫ жұмысы: бос/жұмыста/тұрып қалғандары әрі
  // жоғалып кеткен курьерден тапсырысты босату.
  int _tab = 0;

  static const _statuses = ['pending', 'active', 'blocked'];

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

  Future<void> _set(CourierProfile c, String status, {String? city}) async {
    try {
      await _repo.setCourierStatus(c.uid, status, city: city);
      _snack(
          status == 'active'
              ? tr('Курьер допущен к заказам', 'Курьерге тапсырыс ашылды')
              : status == 'blocked'
                  ? tr('Доступ приостановлен', 'Рұқсат тоқтатылды')
                  : tr('Возвращён в ожидание', 'Күту күйіне қайтарылды'),
          status == 'blocked' ? cAmber : cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  Future<void> _changeCity(CourierProfile c) async {
    final city = await showCourierCityPicker(context, current: c.city);
    if (city == null) return;
    await _set(c, c.courierStatus.isEmpty ? 'pending' : c.courierStatus,
        city: city);
  }

  /// Superadmin курьер деректерін (аты/телефон/қала) тікелей түзейді (0074).
  Future<void> _edit(CourierProfile c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CourierEditSheet(profile: c, service: _service),
    );
    if (saved == true) {
      _snack(tr('Данные курьера обновлены', 'Курьер деректері жаңартылды'),
          cGreen);
    }
  }

  void _openRequests() {
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CourierChangeRequestsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<CourierProfile>>(
        stream: _couriersStream,
        builder: (context, snap) {
          final all = snap.data ?? [];
          final counts = {
            for (final s in _statuses)
              s: all.where((c) => _statusOf(c) == s).length,
          };
          final list =
              all.where((c) => _statusOf(c) == _statuses[_tab]).toList();
          return Column(children: [
            QGradientHeader(
              title: tr('Курьеры', 'Курьерлер'),
              subtitle: tr('${all.length} всего', 'барлығы ${all.length}'),
              compact: true,
              showBack: true,
              action: StreamBuilder<List<CourierChangeRequest>>(
                stream: _requestsStream,
                builder: (context, rs) {
                  final n = (rs.data ?? const <CourierChangeRequest>[])
                      .where((r) => r.isPending)
                      .length;
                  return _RequestsButton(count: n, onTap: _openRequests);
                },
              ),
              bottom: [
                const SizedBox(height: 12),
                Row(children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 7),
                    Expanded(
                      child: _Chip(
                        label: switch (i) {
                          0 => tr('Ожидают', 'Күтуде'),
                          1 => tr('Активные', 'Белсенді'),
                          2 => tr('Блок', 'Бұғат'),
                          _ => tr('Заказы', 'Тапсырыс'),
                        },
                        count: i < 3 ? (counts[_statuses[i]] ?? 0) : null,
                        selected: _tab == i,
                        onTap: () => setState(() => _tab = i),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
            Expanded(
              child: _tab == 3
                  ? const CourierOrdersTab()
                  : snap.connectionState == ConnectionState.waiting
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: cGreen, strokeWidth: 2))
                      : list.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                    _tab == 0
                                        ? tr('Новых заявок нет',
                                            'Жаңа өтінім жоқ')
                                        : tr('Пусто', 'Бос'),
                                    textAlign: TextAlign.center,
                                    style: manrope(14, FontWeight.w600,
                                        color: cInk3)),
                              ),
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 28),
                              children: list
                                  .map((c) => _CourierCard(
                                        courier: c,
                                        status: _statusOf(c),
                                        onApprove: () => _set(c, 'active'),
                                        onBlock: () => _set(c, 'blocked'),
                                        onCity: () => _changeCity(c),
                                        onEdit: () => _edit(c),
                                      ))
                                  .toList(),
                            ),
            ),
          ]);
        },
      ),
    );
  }

  /// Ескі жолдарда courier_status бос болуы мүмкін — оларды «күтуде» санаймыз
  /// (әдепкі — рұқсат БЕРІЛМЕГЕН).
  static String _statusOf(CourierProfile c) =>
      c.courierStatus.isEmpty ? 'pending' : c.courierStatus;
}

class _Chip extends StatelessWidget {
  final String label;

  /// null — сан көрсетілмейді («Тапсырыс» табы өз санауышын өзі жүргізеді).
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color:
                selected ? Colors.white : Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(count?.toString() ?? '·',
                style: manrope(15, FontWeight.w800,
                    color: selected ? cGreenDeep : Colors.white)),
            Text(label,
                style: manrope(10.5, FontWeight.w700,
                    color: selected
                        ? cGreenDeep
                        : Colors.white.withValues(alpha: 0.85))),
          ]),
        ),
      );
}

/// Header-дегі «Курьер сұраныстары» батырмасы (күтудегі саны белгімен).
class _RequestsButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _RequestsButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.edit_note_rounded,
                color: Colors.white, size: 22),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                    color: cRed, borderRadius: BorderRadius.circular(9)),
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: manrope(10.5, FontWeight.w800, color: Colors.white)),
              ),
            ),
        ]),
      );
}

class _CourierCard extends StatelessWidget {
  final CourierProfile courier;
  final String status;
  final VoidCallback onApprove, onBlock, onCity, onEdit;
  const _CourierCard({
    required this.courier,
    required this.status,
    required this.onApprove,
    required this.onBlock,
    required this.onCity,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            QIconTile(
              icon: Icon(Icons.delivery_dining_rounded,
                  color: status == 'active'
                      ? cGreen
                      : status == 'blocked'
                          ? cRed
                          : cAmber,
                  size: 20),
              tone: status == 'active'
                  ? 'green'
                  : status == 'blocked'
                      ? 'red'
                      : 'amber',
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(courier.name.isEmpty ? '—' : courier.name,
                        style: manrope(15, FontWeight.w800, color: cInk),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                        courier.phone.isEmpty
                            ? courier.user.email
                            : courier.phone,
                        style: manrope(12, FontWeight.w600, color: cInk3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
            GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.edit_outlined, size: 16, color: cGreen),
                  const SizedBox(width: 4),
                  Text(tr('Изменить', 'Өзгерту'),
                      style: manrope(12, FontWeight.w700, color: cGreen)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onCity,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.location_city_outlined,
                    size: 16, color: cInk3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      courier.city.isEmpty
                          ? tr('Город не указан', 'Қала көрсетілмеген')
                          : trValue(courier.city),
                      style: manrope(13, FontWeight.w700,
                          color: courier.city.isEmpty ? cRed : cInk)),
                ),
                Text(tr('изменить', 'өзгерту'),
                    style: manrope(11.5, FontWeight.w700, color: cGreen)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              tr('Курьер видит только заказы магазинов этого города',
                  'Курьер тек осы қаладағы дүкендердің тапсырысын көреді'),
              style: manrope(11, FontWeight.w600, color: cInk3)),
          const SizedBox(height: 12),
          Row(children: [
            if (status != 'active')
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: courier.city.isEmpty ? null : onApprove,
                  icon: const Icon(Icons.check_rounded, size: 17),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  label: Text(tr('Допустить', 'Рұқсат беру'),
                      style: manrope(13, FontWeight.w800, color: Colors.white)),
                ),
              ),
            if (status == 'active')
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onBlock,
                  icon: const Icon(Icons.block_rounded, size: 17, color: cRed),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cLine),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  label: Text(tr('Приостановить', 'Тоқтату'),
                      style: manrope(13, FontWeight.w800, color: cRed)),
                ),
              ),
          ]),
        ]),
      );
}

// ── Superadmin: курьер деректерін өңдеу парағы (0074) ────────────────────────
class _CourierEditSheet extends StatefulWidget {
  final CourierProfile profile;
  final CourierService service;
  const _CourierEditSheet({required this.profile, required this.service});

  @override
  State<_CourierEditSheet> createState() => _CourierEditSheetState();
}

class _CourierEditSheetState extends State<_CourierEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late String _city;
  bool _busy = false;
  String? _nameErr;
  String? _phoneErr;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _phone = TextEditingController(
        text: CourierPhoneField.mask(widget.profile.phone));
    _city = widget.profile.city;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = widget.profile;
    final name = _name.text.trim();
    final phoneRaw = _phone.text.trim();
    final phone = phoneRaw.isEmpty ? '' : kzPhoneToE164(phoneRaw);

    final nameErr = (name.length < 2 || name.length > 60)
        ? tr('Имя: от 2 до 60 символов', 'Есім: 2-ден 60 таңбаға дейін')
        : null;
    // Телефоны бос ескі жолдарда аты/қаласын телефонсыз түзетуге болады:
    // нөмір тек ШЫНЫМЕН өзгерсе ғана тексеріледі.
    final phoneErr = (phone != p.phone && !isValidKzPhone(phone))
        ? tr('Номер в формате +7XXXXXXXXXX', 'Нөмір +7XXXXXXXXXX форматында')
        : null;
    setState(() {
      _nameErr = nameErr;
      _phoneErr = phoneErr;
      _error = null;
    });
    if (nameErr != null || phoneErr != null) return;

    final nameCh = name != p.name ? name : null;
    final phoneCh = (phone.isNotEmpty && phone != p.phone) ? phone : null;
    final cityCh = (_city.isNotEmpty && _city != p.city) ? _city : null;
    if (nameCh == null && phoneCh == null && cityCh == null) {
      Navigator.pop(context, false);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      await widget.service.adminUpdateCourier(p.uid,
          name: nameCh, phone: phoneCh, city: cityCh);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = courierDataErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 12, 18, media.viewInsets.bottom + media.padding.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: cLine, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(tr('Данные курьера', 'Курьер деректері'),
                style: manrope(17, FontWeight.w800, color: cInk)),
            const SizedBox(height: 4),
            Text(
                tr('Телефон — это номер для входа. Курьер получит уведомление.',
                    'Телефон — кіру нөмірі. Курьерге хабарлама барады.'),
                style: manrope(12.5, FontWeight.w500, color: cInk3)),
            const SizedBox(height: 16),
            CourierTextField(
              label: tr('Имя', 'Есім'),
              controller: _name,
              maxLength: 60,
              errorText: _nameErr,
            ),
            CourierPhoneField(controller: _phone, errorText: _phoneErr),
            CourierCityField(
              value: _city,
              onChanged: (c) => setState(() => _city = c),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style: manrope(12.5, FontWeight.w700, color: cRed)),
              ),
            QPrimaryButton(
              label: tr('Сохранить', 'Сақтау'),
              isLoading: _busy,
              onPressed: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
