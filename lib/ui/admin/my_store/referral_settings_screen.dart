import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

import '../../../core/lang.dart';
import '../../../core/error_text.dart';

/// Дүкен иесі «Досыңды шақыр» бағдарламасын қосады/өшіреді және жеңілдік
/// пайызын таңдайды. Бұл пайыз ЕКІ жаққа да қолданылады: досы бірінші
/// тапсырысында, шақырушы — досының тапсырысы аяқталған соң жеке промокод
/// түрінде (0044 триггері).
class ReferralSettingsScreen extends StatefulWidget {
  final StoreModel store;
  const ReferralSettingsScreen({super.key, required this.store});

  @override
  State<ReferralSettingsScreen> createState() => _ReferralSettingsScreenState();
}

class _ReferralSettingsScreenState extends State<ReferralSettingsScreen> {
  static const _options = [5, 7, 10, 15, 20];
  final _service = FirestoreService();
  late int _percent = widget.store.referralPercent;
  bool _saving = false;

  bool get _enabled => _percent > 0;

  Future<void> _save(int percent) async {
    if (_saving) return;
    final prev = _percent;
    setState(() {
      _percent = percent;
      _saving = true;
    });
    HapticFeedback.selectionClick();
    try {
      await _service.updateStoreFields({'referral_percent': percent});
    } catch (e) {
      if (!mounted) return;
      setState(() => _percent = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Приведи друга', 'Досыңды шақыр'),
          subtitle: _enabled
              ? tr('Включено · −$_percent%', 'Қосулы · −$_percent%')
              : tr('Выключено', 'Өшірулі'),
          showBack: true,
        ),
        Expanded(
          child: ListView(
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
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.card_giftcard_rounded,
                            color: cGreen, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              tr('Клиенты приводят новых клиентов',
                                  'Клиенттер жаңа клиент әкеледі'),
                              style: manrope(14, FontWeight.w800, color: cInk)),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                          tr(
                              'Ваш покупатель делится личным кодом. Друг вводит его в корзине и получает скидку на ПЕРВЫЙ заказ у вас. Когда заказ выполнен — пригласившему приходит личный промокод на такую же скидку.',
                              'Сатып алушыңыз жеке кодын бөліседі. Досы оны себетте енгізіп, сіздегі БІРІНШІ тапсырысына жеңілдік алады. Тапсырыс орындалғанда — шақырушыға сондай жеңілдікке жеке промокод келеді.'),
                          style: manrope(12, FontWeight.w500,
                              color: cInk2, height: 1.45)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 9),
                        decoration: BoxDecoration(
                          color: cAmberTint,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 15, color: Color(0xFFB4770A)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                tr('Скидку оплачиваете вы — это стоимость привлечения нового клиента',
                                    'Жеңілдікті сіз төлейсіз — бұл жаңа клиент тартудың құны'),
                                style: manrope(11.5, FontWeight.w600,
                                    color: const Color(0xFFB4770A))),
                          ),
                        ]),
                      ),
                    ]),
              ),
              const SizedBox(height: 20),

              QSecLabel(tr('Размер скидки', 'Жеңілдік мөлшері')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PctChip(
                    label: tr('Выкл.', 'Өшірулі'),
                    selected: _percent == 0,
                    onTap: () => _save(0),
                  ),
                  ..._options.map((p) => _PctChip(
                        label: '$p%',
                        selected: _percent == p,
                        onTap: () => _save(p),
                      )),
                ],
              ),
              if (_enabled) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cGreen.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: cGreen, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          tr('Клиенты видят «Пригласи друга» в меню вашего магазина',
                              'Клиенттер дүкен мәзірінде «Досыңды шақыр» дегенді көреді'),
                          style: manrope(12.5, FontWeight.w600, color: cGreenDeep)),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

class _PctChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PctChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? cGreen : cSurface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: selected ? cGreen : cLine),
          ),
          child: Text(label,
              style: manrope(13.5, FontWeight.w700,
                  color: selected ? Colors.white : cInk2)),
        ),
      );
}
