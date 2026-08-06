import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/promo_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';

/// «Досыңды шақыр» — клиент өзінің жеке кодын бөліседі. Досы сол кодпен
/// осы дүкендегі БІРІНШІ тапсырысын жасаса, екеуі де дүкен белгілеген
/// пайызда жеңілдік алады (досы бірден, шақырушы тапсырыс аяқталған соң
/// жеке сыйлық промокоды түрінде — 0044 триггері).
class ReferralScreen extends StatefulWidget {
  final StoreModel store;
  const ReferralScreen({super.key, required this.store});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _service = ClientService();
  final _shareKey = GlobalKey();
  String? _code;
  List<PromoModel> _rewards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _service.getMyReferralCode(widget.store.adminUid),
        _service.getMyReferralRewards(),
      ]);
      if (!mounted) return;
      setState(() {
        _code = results[0] as String?;
        _rewards = (results[1] as List<PromoModel>)
            .where((p) => p.value > 0)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Код скопирован', 'Код көшірілді')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _share() async {
    final code = _code;
    if (code == null) return;
    final pct = widget.store.referralPercent;
    final text = tr(
      'Магазин «${widget.store.storeName}» в Qoima!\n'
      'Мой код: $code — получи −$pct% на первый заказ.',
      '«${widget.store.storeName}» дүкені Qoima-да!\n'
      'Менің кодым: $code — бірінші тапсырысқа −$pct% ал.',
    );
    // iPad/iOS share sheet popover анкерін талап етеді.
    Rect? origin;
    final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    }
    try {
      await Share.share(text, sharePositionOrigin: origin);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pct = widget.store.referralPercent;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Пригласи друга', 'Досыңды шақыр'),
          subtitle: widget.store.storeName,
          showBack: true,
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: cGreen, strokeWidth: 2))
              : _code == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                            tr('В этом магазине программа приглашений пока не включена',
                                'Бұл дүкенде шақыру бағдарламасы әзірге қосылмаған'),
                            textAlign: TextAlign.center,
                            style: manrope(14, FontWeight.w600, color: cInk2)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        // ── Код карточкасы ──────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [cGreen, cGreenDeep],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: kShadowMd,
                          ),
                          child: Column(children: [
                            Text(tr('Ваш код приглашения', 'Сіздің шақыру кодыңыз'),
                                style: manrope(12.5, FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.85))),
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: () => _copy(_code!),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(_code!,
                                          style: manrope(20, FontWeight.w800,
                                              color: Colors.white,
                                              letterSpacing: 1.2)),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.copy_rounded,
                                          size: 17, color: Colors.white),
                                    ]),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              key: _shareKey,
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton.icon(
                                onPressed: _share,
                                icon: const Icon(Icons.share_rounded,
                                    size: 18, color: cGreenDeep),
                                label: Text(tr('Поделиться', 'Бөлісу'),
                                    style: manrope(14, FontWeight.w800,
                                        color: cGreenDeep)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(13)),
                                ),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 18),

                        // ── Қалай жұмыс істейді ─────────────────────────
                        QSecLabel(tr('Как это работает', 'Қалай жұмыс істейді')),
                        const SizedBox(height: 8),
                        _Step(
                            n: 1,
                            text: tr('Отправьте код другу',
                                'Кодты досыңызға жіберіңіз')),
                        _Step(
                            n: 2,
                            text: tr(
                                'Друг вводит его в корзине и получает −$pct% на первый заказ',
                                'Досыңыз оны себетте енгізіп, бірінші тапсырысқа −$pct% алады')),
                        _Step(
                            n: 3,
                            text: tr(
                                'Когда его заказ выполнен — вам придёт личный промокод на −$pct%',
                                'Оның тапсырысы орындалғанда — сізге −$pct% жеке промокод келеді'),
                            last: true),
                        const SizedBox(height: 20),

                        // ── Менің сыйлықтарым ───────────────────────────
                        QSecLabel(tr('Мои бонусы', 'Менің бонустарым')),
                        const SizedBox(height: 8),
                        if (_rewards.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cLine),
                            ),
                            child: Row(children: [
                              const Icon(Icons.card_giftcard_rounded,
                                  color: cInk3, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                    tr('Бонусов пока нет — пригласите друга',
                                        'Әзірге бонус жоқ — досыңызды шақырыңыз'),
                                    style: manrope(12.5, FontWeight.w600,
                                        color: cInk3)),
                              ),
                            ]),
                          )
                        else
                          ..._rewards.map((r) => GestureDetector(
                                onTap: () => _copy(r.code),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cGreenTint,
                                    borderRadius: BorderRadius.circular(15),
                                    border: Border.all(
                                        color: cGreen.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.card_giftcard_rounded,
                                        color: cGreen, size: 22),
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(r.code,
                                                style: manrope(14.5,
                                                    FontWeight.w800,
                                                    color: cGreenDeep)),
                                            Text(
                                                r.isPercent
                                                    ? '−${r.value.toStringAsFixed(0)}%'
                                                    : '−${money(r.value)}',
                                                style: manrope(12,
                                                    FontWeight.w600,
                                                    color: cGreen)),
                                          ]),
                                    ),
                                    const Icon(Icons.copy_rounded,
                                        size: 16, color: cGreen),
                                  ]),
                                ),
                              )),
                      ],
                    ),
        ),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  final bool last;
  const _Step({required this.n, required this.text, this.last = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: cGreenTint, borderRadius: BorderRadius.circular(8)),
            child: Text('$n',
                style: manrope(12, FontWeight.w800, color: cGreenDeep)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text,
                  style: manrope(12.5, FontWeight.w600, color: cInk2, height: 1.4)),
            ),
          ),
        ]),
      );
}
