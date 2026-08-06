import 'package:flutter/material.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../products/product_detail_screen.dart';

import '../../../core/lang.dart';

/// «Сұраныс сигналы» — клиенттердің Избранное-ге қосуы арқылы білдірген
/// нақты қызығушылығын admin-ге көрсетеді (viewCount-тан айырмашылығы:
/// таңдаулы «сатып алуға дайын» ниетті білдіреді, кездейсоқ баспаны емес).
///
/// Екі әрекетке шақыратын блок:
///  1. Таңдаулыда көп, бірақ қоймада ЖОҚ — жедел қайта әкелу керек (тікелей
///     сатылымды жоғалтасыз: адамдар қалайды, сатып ала алмайды).
///  2. Таңдаулыда көп, қоймада БАР, бірақ 0 сатылған — баға/фото/сипаттаманы
///     тексеру керек болуы мүмкін (қызығушылық бар, конверсия жоқ).
class DemandSignalsScreen extends StatefulWidget {
  const DemandSignalsScreen({super.key});

  @override
  State<DemandSignalsScreen> createState() => _DemandSignalsScreenState();
}

class _DemandSignalsScreenState extends State<DemandSignalsScreen> {
  final _service = FirestoreService();
  late Future<List<DemandSignalEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getDemandSignals();
  }

  Future<void> _openProduct(String id) async {
    try {
      final product = await _service.getProduct(id);
      if (product == null || !mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Спрос клиентов', 'Клиенттер сұранысы'),
          subtitle: tr('Кого добавили в избранное', 'Кімдер таңдаулыға қосты'),
          showBack: true,
        ),
        Expanded(
          child: FutureBuilder<List<DemandSignalEntry>>(
            future: _future,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
              }
              final all = snap.data!;
              if (all.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.favorite_border_rounded,
                          size: 56, color: cInk3.withValues(alpha: 0.4)),
                      const SizedBox(height: 14),
                      Text(tr('Пока никто не добавил ваши товары в избранное',
                              'Әзірге ешкім тауарыңызды таңдаулыға қосқан жоқ'),
                          textAlign: TextAlign.center,
                          style: manrope(14, FontWeight.w600, color: cInk2)),
                    ]),
                  ),
                );
              }
              final restock = all.where((e) => e.needsRestock).toList();
              final notConverting = all.where((e) => e.notConverting).toList();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  if (restock.isNotEmpty) ...[
                    _SectionCard(
                      icon: Icons.priority_high_rounded,
                      tone: 'red',
                      title: tr('Срочно завезите — товар хотят, но его нет',
                          'Жедел әкеліңіз — тауарды қалайды, бірақ жоқ'),
                    ),
                    const SizedBox(height: 8),
                    ...restock.map((e) =>
                        _DemandCard(entry: e, onTap: () => _openProduct(e.productId))),
                    const SizedBox(height: 20),
                  ],
                  if (notConverting.isNotEmpty) ...[
                    _SectionCard(
                      icon: Icons.help_outline_rounded,
                      tone: 'amber',
                      title: tr('В избранном, но не покупают — проверьте цену/фото',
                          'Таңдаулыда бар, бірақ сатып алмайды — баға/фотоны тексеріңіз'),
                    ),
                    const SizedBox(height: 8),
                    ...notConverting.map((e) =>
                        _DemandCard(entry: e, onTap: () => _openProduct(e.productId))),
                    const SizedBox(height: 20),
                  ],
                  QSecLabel(tr('Все товары в избранном', 'Таңдаулыдағы барлық тауар')),
                  const SizedBox(height: 8),
                  ...all.map((e) =>
                      _DemandCard(entry: e, onTap: () => _openProduct(e.productId))),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String tone;
  final String title;
  const _SectionCard({required this.icon, required this.tone, required this.title});

  Color get _bg => tone == 'red' ? cRedTint : cAmberTint;
  Color get _fg => tone == 'red' ? cRed : const Color(0xFFB4770A);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(13)),
        child: Row(children: [
          Icon(icon, color: _fg, size: 18),
          const SizedBox(width: 9),
          Expanded(
              child: Text(title, style: manrope(12.5, FontWeight.w700, color: _fg))),
        ]),
      );
}

class _DemandCard extends StatelessWidget {
  final DemandSignalEntry entry;
  final VoidCallback onTap;
  const _DemandCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cGreenTint,
              borderRadius: BorderRadius.circular(12),
              image: entry.imageUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(entry.imageUrl), fit: BoxFit.cover)
                  : null,
            ),
            child: entry.imageUrl.isEmpty
                ? const Icon(Icons.checkroom_rounded, color: cGreenDeep, size: 22)
                : null,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.name,
                  style: manrope(13.5, FontWeight.w700, color: cInk),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Row(children: [
                _MiniStat(
                    icon: Icons.favorite_rounded,
                    color: cRed,
                    value: '${entry.favorites}'),
                const SizedBox(width: 10),
                _MiniStat(
                    icon: Icons.shopping_bag_outlined,
                    color: cInk3,
                    value: tr('${entry.sold} продано', '${entry.sold} сатылды')),
                const SizedBox(width: 10),
                _MiniStat(
                    icon: Icons.inventory_2_outlined,
                    color: entry.available > 0 ? cGreen : cRed,
                    value: tr('${entry.available} шт.', '${entry.available} дана')),
              ]),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
        ]),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  const _MiniStat({required this.icon, required this.color, required this.value});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12.5, color: color),
        const SizedBox(width: 3),
        Text(value, style: manrope(11, FontWeight.w600, color: cInk3)),
      ]);
}
