import 'package:flutter/material.dart';
import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../data/services/return_service.dart';
import '../../theme/qoima_design.dart';

/// Superadmin — қай дүкен өз тауарына «қайтарылмайды» белгісін қоя алады (0073).
/// Рұқсат — stores.allow_non_returnable; тек set_store_non_returnable_permission
/// RPC арқылы өзгереді (иесі тікелей жаза алмайды: DB guard триггері).
class ReturnPolicyStoresScreen extends StatefulWidget {
  const ReturnPolicyStoresScreen({super.key});

  @override
  State<ReturnPolicyStoresScreen> createState() =>
      _ReturnPolicyStoresScreenState();
}

class _ReturnPolicyStoresScreenState extends State<ReturnPolicyStoresScreen> {
  final _repo = StoreModerationRepository();
  final _searchCtrl = TextEditingController();
  // Stream бір рет қана құрылады (build() ішінде емес).
  late final Stream<List<StoreModel>> _stream = _repo.watchAllShops();
  String _q = '';
  final Set<String> _busy = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _toggle(StoreModel s, bool allow) async {
    if (_busy.contains(s.adminUid)) return;
    if (!allow) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title:
              Text(tr('Забрать разрешение?', 'Рұқсатты қайтарып аласыз ба?')),
          content: Text(tr(
              'У магазина «${s.storeName}» будут сняты отметки «без возврата» со всех товаров. Уже оформленные заказы не изменятся.',
              '«${s.storeName}» дүкенінің барлық тауарынан «қайтарылмайды» белгісі алынады. Рәсімделген тапсырыстар өзгермейді.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Отмена', 'Болдырмау'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Забрать', 'Қайтарып алу'),
                    style: const TextStyle(color: cRed))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy.add(s.adminUid));
    try {
      final cleared = await ReturnService()
          .setStoreNonReturnablePermission(s.adminUid, allow);
      if (allow) {
        _snack(tr('Разрешение выдано', 'Рұқсат берілді'), cGreen);
      } else {
        _snack(
            cleared > 0
                ? tr('Разрешение снято, отметок снято: $cleared',
                    'Рұқсат алынды, алынған белгі: $cleared')
                : tr('Разрешение снято', 'Рұқсат алынды'),
            cInk);
      }
    } catch (e) {
      _snack(policyErrorText(e), cRed);
    } finally {
      if (mounted) setState(() => _busy.remove(s.adminUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<StoreModel>>(
        stream: _stream,
        builder: (context, snap) {
          final all = snap.data ?? const <StoreModel>[];
          final q = _q.trim().toLowerCase();
          final list = q.isEmpty
              ? all
              : all
                  .where((s) =>
                      s.storeName.toLowerCase().contains(q) ||
                      s.city.toLowerCase().contains(q) ||
                      s.ownerName.toLowerCase().contains(q))
                  .toList();
          final allowed = all.where((s) => s.allowNonReturnable).length;
          return Column(children: [
            QGradientHeader(
              title: tr('Правила возврата', 'Қайтару ережесі'),
              subtitle: tr('Разрешено магазинам: $allowed из ${all.length}',
                  'Рұқсат берілген дүкен: $allowed / ${all.length}'),
              compact: true,
              showBack: true,
              bottom: [
                const SizedBox(height: 12),
                _SearchField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _q = v),
                ),
              ],
            ),
            ListenableBuilder(
              listenable: FeatureFlags.instance,
              builder: (_, __) =>
                  FeatureFlags.instance.isOn(FeatureFlags.nonReturnable)
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                          child: QCard(
                            color: cAmberTint,
                            padding: const EdgeInsets.all(12),
                            child: Text(
                                tr('Функция «Товары без возврата» сейчас выключена в настройках платформы — владельцы и покупатели её не видят.',
                                    '«Қайтарылмайтын тауарлар» функциясы платформа баптауларында өшірулі — иелер мен сатып алушылар көрмейді.'),
                                style: manrope(12.5, FontWeight.w600,
                                    color: cAmberInk)),
                          ),
                        ),
            ),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: cGreen, strokeWidth: 2))
                  : list.isEmpty
                      ? Center(
                          child: Text(
                              tr('Магазины не найдены', 'Дүкен табылмады'),
                              style:
                                  manrope(14, FontWeight.w600, color: cInk3)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _StoreRow(
                            store: list[i],
                            busy: _busy.contains(list[i].adminUid),
                            onChanged: (v) => _toggle(list[i], v),
                          ),
                        ),
            ),
          ]);
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kR14),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: manrope(14, FontWeight.w600),
        decoration: InputDecoration(
          hintText:
              tr('Поиск: магазин, город, владелец', 'Іздеу: дүкен, қала, ие'),
          hintStyle: manrope(13.5, FontWeight.w500, color: cInk3),
          prefixIcon: const Icon(Icons.search_rounded, color: cInk3, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _StoreRow extends StatelessWidget {
  final StoreModel store;
  final bool busy;
  final ValueChanged<bool> onChanged;
  const _StoreRow(
      {required this.store, required this.busy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (store.city.isNotEmpty) trValue(store.city),
      if (store.ownerName.isNotEmpty) store.ownerName,
    ].join(' · ');
    return QCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(store.storeName,
                style: manrope(14.5, FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (sub.isNotEmpty)
              Text(sub,
                  style: manrope(12, FontWeight.w500, color: cInk3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
                store.allowNonReturnable
                    ? tr('Может ставить «без возврата»',
                        '«Қайтарылмайды» қоя алады')
                    : tr('Все товары возвратные', 'Барлық тауар қайтарылады'),
                style: manrope(11.5, FontWeight.w700,
                    color: store.allowNonReturnable ? cAmberInk : cGreenDeep)),
          ]),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
                width: 20,
                height: 20,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: cGreen)),
          )
        else
          Switch(
            value: store.allowNonReturnable,
            activeTrackColor: cGreen,
            activeThumbColor: Colors.white,
            onChanged: onChanged,
          ),
      ]),
    );
  }
}
