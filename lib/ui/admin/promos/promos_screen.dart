import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/models/promo_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import 'promo_edit_sheet.dart';

/// Админ-экран управления промокодами магазина.
class PromosScreen extends StatelessWidget {
  const PromosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Промокоды',
          subtitle: 'Скидки по коду для клиентов',
          showBack: true,
        ),
        Expanded(
          child: StreamBuilder<List<PromoModel>>(
            stream: service.watchPromos(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }
              if (snap.hasError) {
                return _Empty(
                    icon: Icons.error_outline_rounded,
                    message: 'Ошибка загрузки промокодов');
              }
              final promos = snap.data ?? [];
              if (promos.isEmpty) {
                return _Empty(
                    icon: Icons.local_activity_outlined,
                    message: 'Пока нет промокодов.\nСоздайте первый.');
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                itemCount: promos.length,
                itemBuilder: (_, i) =>
                    _PromoCard(promo: promos[i], service: service),
              );
            },
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cGreen,
        foregroundColor: Colors.white,
        onPressed: () => showPromoEditSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: Text('Создать', style: manrope(14, FontWeight.w700,
            color: Colors.white)),
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final PromoModel promo;
  final FirestoreService service;
  const _PromoCard({required this.promo, required this.service});

  String get _discountLabel =>
      promo.isPercent ? '−${promo.value.toStringAsFixed(0)}%'
                      : '−${money(promo.value)}';

  String get _scopeLabel => promo.scope == 'products'
      ? 'На ${promo.productIds.length} тов.'
      : 'На всё';

  ({String text, Color color}) get _status {
    if (!promo.active) return (text: 'Выключен', color: cInk3);
    if (promo.isExpired) return (text: 'Завершён', color: cRed);
    if (promo.isExhausted) return (text: 'Исчерпан', color: cRed);
    if (!promo.isStarted) return (text: 'Запланирован', color: cAmber);
    return (text: 'Активен', color: cGreen);
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    return Container(
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
          // Код (моноширинный) + копировать
          Expanded(
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: promo.code));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Код ${promo.code} скопирован'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: cGreen,
                ));
              },
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(promo.code,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: 1,
                          color: cGreenDeep)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy_rounded, size: 14, color: cInk3),
              ]),
            ),
          ),
          // Вкл/выкл
          Switch(
            value: promo.active,
            activeTrackColor: cGreen,
            onChanged: (v) => service.setPromoActive(promo.id, v),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _Chip(_discountLabel, cRed),
          const SizedBox(width: 6),
          _Chip(_scopeLabel, cInk2),
          const Spacer(),
          Text(st.text,
              style: manrope(12.5, FontWeight.w700, color: st.color)),
        ]),
        const SizedBox(height: 10),
        // Прогресс использований
        if (promo.maxUses != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: promo.maxUses! > 0
                  ? (promo.usedCount / promo.maxUses!).clamp(0.0, 1.0)
                  : 0,
              minHeight: 6,
              backgroundColor: cLine,
              valueColor: AlwaysStoppedAnimation(
                  promo.isExhausted ? cRed : cGreen),
            ),
          ),
          const SizedBox(height: 4),
          Text('${promo.usedCount} / ${promo.maxUses} использований',
              style: manrope(11.5, FontWeight.w500, color: cInk3)),
        ] else
          Text('${promo.usedCount} использований · без лимита',
              style: manrope(11.5, FontWeight.w500, color: cInk3)),
        const SizedBox(height: 6),
        Row(children: [
          if (promo.daysLeft != null)
            Text('Осталось ${promo.daysLeft} дн.',
                style: manrope(11.5, FontWeight.w500, color: cInk3)),
          const Spacer(),
          TextButton(
            onPressed: () => showPromoEditSheet(context, existing: promo),
            child: Text('Изменить',
                style: manrope(12.5, FontWeight.w600, color: cGreen)),
          ),
          TextButton(
            onPressed: () => _confirmDelete(context),
            child: Text('Удалить',
                style: manrope(12.5, FontWeight.w600, color: cRed)),
          ),
        ]),
      ]),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Удалить промокод?',
            style: manrope(17, FontWeight.w700, color: cInk)),
        content: Text('«${promo.code}» будет удалён безвозвратно.',
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена',
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () {
                service.deletePromo(promo.id);
                Navigator.pop(ctx);
              },
              child: Text('Удалить',
                  style: manrope(14, FontWeight.w600, color: cRed))),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: manrope(12, FontWeight.w700, color: color)),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String message;
  const _Empty({required this.icon, required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 56, color: cInk3),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: manrope(15, FontWeight.w500, color: cInk2)),
        ]),
      );
}
