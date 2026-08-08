import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/lang.dart';
import '../../data/models/return_model.dart';
import '../../theme/qoima_design.dart';

/// Курьердің ВОЗВРАТ карточкасы — жеткізумен БІРДЕЙ маңызды жұмыс, сондықтан
/// сол «Жаңа тапсырыстар» тізімінде тұрады, тек бағыты кері:
///
///   клиенттен алу (pickup_address) → дүкенге апару (warehouse_address)
///
/// Ақшасы да курьердікі әрі клиентке қайтарылатын тауар сомасынан
/// ЕШҚАШАН шегерілмейді (0052/0053).
class CourierReturnCard extends StatelessWidget {
  final ReturnModel ret;
  final VoidCallback? onTake;
  /// [feeCollected] — қайтару жеткізуінің ақысын клиенттен алды ма.
  final void Function(bool feeCollected)? onPickup;
  final VoidCallback? onDeliver;

  const CourierReturnCard({
    super.key,
    required this.ret,
    this.onTake,
    this.onPickup,
    this.onDeliver,
  });

  @override
  Widget build(BuildContext context) {
    final done = ret.courierDelivered;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: ret.courierPickedUp ? cBlue.withValues(alpha: 0.5) : cLine),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Шапка ───────────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: (done ? cGreen : cBlue).withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            QPill(_statusLabel, tone: done ? 'green' : 'blue'),
            const SizedBox(width: 8),
            Text(tr('ВОЗВРАТ', 'ҚАЙТАРЫМ'),
                style: manrope(11, FontWeight.w800, color: cBlue)),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(ret.courierFee),
                  style: manrope(15, FontWeight.w800, color: cGreenDeep)),
              Text(tr('вам от клиента', 'клиенттен сізге'),
                  style: manrope(9.5, FontWeight.w700, color: cInk3)),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── 1) Клиенттен алу ──────────────────────────────────────────
            _AddressRow(
              icon: Icons.person_pin_circle_rounded,
              tone: 'amber',
              step: '1',
              title: ret.clientName.isEmpty
                  ? tr('Клиент', 'Клиент')
                  : ret.clientName,
              subtitle: ret.pickupAddress.isEmpty
                  ? tr('Адрес не указан — позвоните клиенту',
                      'Мекенжай жоқ — клиентке қоңырау шалыңыз')
                  : ret.pickupAddress,
              phone: ret.clientPhone,
            ),
            const SizedBox(height: 10),
            // ── 2) Дүкенге апару ──────────────────────────────────────────
            _AddressRow(
              icon: Icons.storefront_rounded,
              tone: 'green',
              step: '2',
              title: ret.storeName.isEmpty
                  ? tr('Магазин', 'Дүкен')
                  : ret.storeName,
              subtitle: ret.warehouseAddress.isEmpty
                  ? tr('Адрес склада не указан', 'Қойма мекенжайы жоқ')
                  : ret.warehouseAddress,
              phone: ret.storePhone,
            ),

            const SizedBox(height: 12),
            // ── Тауарлар ──────────────────────────────────────────────────
            ...ret.items.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(children: [
                    const Icon(Icons.check_box_outline_blank_rounded,
                        size: 15, color: cInk3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${i.productTitle} · ${i.size}',
                          style: manrope(12.5, FontWeight.w600, color: cInk),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('  ×${i.quantity}',
                        style: manrope(12, FontWeight.w700, color: cInk3)),
                  ]),
                )),

            // Клиенттің ақшасына тимейміз — есеп ашық болу үшін жазып қоямыз.
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: cBg, borderRadius: BorderRadius.circular(11)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, size: 15, color: cInk3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      tr('Деньги за товар (${money(ret.totalAmount)}) возвращает магазин — вы к ним не прикасаетесь. Ваш заработок: ${money(ret.courierFee)} от клиента.',
                          'Тауар ақысын (${money(ret.totalAmount)}) дүкен қайтарады — сіз оған тимейсіз. Сіздің табысыңыз: клиенттен ${money(ret.courierFee)}.'),
                      style: manrope(11, FontWeight.w600, color: cInk3,
                          height: 1.35)),
                ),
              ]),
            ),

            if (!done) ...[
              const SizedBox(height: 14),
              _actions(context),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _actions(BuildContext context) {
    if (onTake != null) {
      return QPrimaryButton(
          label: tr('Взять возврат', 'Қайтарымды алу'),
          onPressed: onTake,
          height: 46);
    }
    if (ret.courierAssigned) {
      return QPrimaryButton(
        label: tr('Забрал у клиента', 'Клиенттен алдым'),
        onPressed: () => _askFee(context),
        height: 46,
      );
    }
    if (ret.courierPickedUp) {
      return QPrimaryButton(
        label: tr('Сдал в магазин', 'Дүкенге тапсырдым'),
        onPressed: onDeliver,
        height: 46,
      );
    }
    return const SizedBox.shrink();
  }

  /// Ақыны клиенттен алды ма — курьердің есебі ашық болуы үшін сұралады.
  Future<void> _askFee(BuildContext context) async {
    final got = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Забрали товар у клиента?', 'Тауарды клиенттен алдыңыз ба?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Клиент платит вам ${money(ret.courierFee)} за доставку возврата. Эта сумма из его возврата НЕ вычитается.',
                'Клиент қайтарымды жеткізгені үшін сізге ${money(ret.courierFee)} төлейді. Бұл сома оның қайтарымынан ШЕГЕРІЛМЕЙДІ.'),
            style: manrope(13, FontWeight.w500, color: cInk2, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Забрал, но не заплатил', 'Алдым, бірақ төлемеді'),
                  style: manrope(13, FontWeight.w600, color: cRed))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Забрал и получил', 'Алдым әрі төледі'))),
        ],
      ),
    );
    if (got != null) onPickup?.call(got);
  }

  String get _statusLabel {
    if (ret.courierDelivered) return tr('Сдан', 'Тапсырылды');
    if (ret.courierPickedUp) return tr('Везу в магазин', 'Дүкенге апарамын');
    if (ret.courierAssigned) return tr('Забрать у клиента', 'Клиенттен алу');
    return tr('Свободен', 'Бос');
  }
}

// ── Мекенжай жолы (нөмірленген қадам) ────────────────────────────────────────
class _AddressRow extends StatelessWidget {
  final IconData icon;
  final String tone, step, title, subtitle, phone;
  const _AddressRow({
    required this.icon,
    required this.tone,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.phone,
  });

  Future<void> _call() async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _map() async {
    if (subtitle.isEmpty) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(subtitle)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = tone == 'green' ? cGreen : cAmber;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(step, style: manrope(15, FontWeight.w800, color: color)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: GestureDetector(
          onTap: _map,
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: subtitle));
            HapticFeedback.lightImpact();
          },
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(title,
                    style: manrope(13.5, FontWeight.w800, color: cInk),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            Text(subtitle,
                style:
                    manrope(12, FontWeight.w600, color: cInk2, height: 1.3)),
          ]),
        ),
      ),
      if (phone.isNotEmpty)
        GestureDetector(
          onTap: _call,
          child: Container(
            width: 34,
            height: 34,
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: cGreenTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.call_rounded, color: cGreenDeep, size: 17),
          ),
        ),
    ]);
  }
}
