import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';
/// Шарттарды қабылдау экраны. Жаңа admin (owner) тіркелген соң алғашқы қадам.
/// Екі checkbox белгіленбейінше «Завершить» белсенді емес. Қабылдаған соң
/// users/{uid}.termsAccepted=true жазылып, AppUser жаңарады — ары қарай
/// корневой gate дүкен заявкасы экранына өзі ауыстырады.
class TermsScreen extends StatefulWidget {
  /// «Артқа»/бас тарту = аккаунттан шығу (бұл экран онбордингте root болуы мүмкін).
  final VoidCallback? onCancel;
  const TermsScreen({super.key, this.onCancel});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _terms = false;
  bool _privacy = false;
  bool _loading = false;

  bool get _bothChecked => _terms && _privacy;

  Future<void> _onAccept() async {
    if (!_bothChecked || _loading) return;
    setState(() => _loading = true);
    try {
      final sb = Supabase.instance.client;
      await sb.from('users').update({
        'terms_accepted': true,
        'terms_accepted_at': DateTime.now().toIso8601String(),
      }).eq('id', sb.auth.currentUser!.id);
      if (!mounted) return;
      // Gate осыны көріп, дүкен заявкасы экранына ауысады.
      context.read<AppUser>().termsAccepted = true;
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Условия использования', 'Қолдану шарттары'),
          subtitle: tr('Шаг 1 из 2', '2 қадамның 1-і'),
          showBack: widget.onCancel != null,
          onBack: _loading ? null : widget.onCancel,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress bar (2 қадам, 1-сі толық)
                Row(children: [
                  Expanded(
                      child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                              color: cGreen,
                              borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                              color: cLine,
                              borderRadius: BorderRadius.circular(2)))),
                ]),
                const SizedBox(height: 16),
                Text(tr('Ознакомьтесь с условиями', 'Шарттармен танысыңыз'),
                    style: manrope(15, FontWeight.w700, color: cInk)),
                const SizedBox(height: 12),

                // Шарттар картасы — ішінде scroll
                Expanded(
                  child: QCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          QIconTile(
                            icon: Icon(Icons.verified_user_outlined,
                                color: cGreen, size: 20),
                            tone: 'green',
                            size: 40,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Qoima Маркетплейс',
                                    style: manrope(14.5, FontWeight.w800,
                                        color: cInk)),
                                Text(tr('Условия и политика', 'Шарттар мен саясат'),
                                    style: manrope(12, FontWeight.w500,
                                        color: cInk3)),
                              ],
                            ),
                          ),
                        ]),
                        SizedBox(height: 12),
                        Container(height: 1, color: cLine),
                        SizedBox(height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _TermsSection(
                                  title: tr('1. Общие положения', '1. Жалпы ережелер'),
                                  points: [
                                    tr('Используя платформу Qoima, вы полностью принимаете настоящие условия.', 'Qoima платформасын қолдана отырып, осы шарттарды толық қабылдайсыз.'),
                                    tr('Платформа предназначена только для законной торговой деятельности.', 'Платформа тек заңды сауда қызметіне арналған.'),
                                    tr('Безопасность данных аккаунта — ваша ответственность.', 'Аккаунт деректерінің қауіпсіздігі — сіздің жауапкершілігіңіз.'),
                                  ],
                                ),
                                _TermsSection(
                                  title: tr('2. Сбор данных', '2. Деректерді жинау'),
                                  points: [
                                    tr('При регистрации сохраняются имя, телефон и город.', 'Тіркелу кезінде аты, телефоны және қаласы сақталады.'),
                                    tr('Данные продаж обрабатываются в аналитических целях.', 'Сатылым деректері аналитикалық мақсатта өңделеді.'),
                                    tr('Данные не передаются третьим лицам; раскрываются только по закону.', 'Деректер үшінші тұлғаларға берілмейді; тек заң бойынша ашылады.'),
                                  ],
                                ),
                                _TermsSection(
                                  title: tr('3. Разрешённые действия', '3. Рұқсат етілген әрекеттер'),
                                  points: [
                                    tr('Открывать магазин и продавать товары как физ. или юр. лицо.', 'Жеке немесе заңды тұлға ретінде дүкен ашып, тауар сату.'),
                                    tr('Добавлять продавцов и контролировать их работу.', 'Сатушыларды қосып, жұмысын бақылау.'),
                                    tr('Использовать онлайн-продажи, доставку и самовывоз.', 'Онлайн-сатылым, жеткізу және өзі алып кетуді қолдану.'),
                                  ],
                                ),
                                _TermsSection(
                                  title: tr('4. Запрещённые действия', '4. Тыйым салынған әрекеттер'),
                                  points: [
                                    tr('Реклама товаров с ложными или вводящими в заблуждение сведениями.', 'Жалған немесе жаңылыстыратын мәліметпен тауар жарнамалау.'),
                                    tr('Нарушение работы платформы, автоматизированный спам.', 'Платформа жұмысын бұзу, автоматтандырылған спам.'),
                                    tr('Обман покупателей или получение оплаты без отправки товара.', 'Сатып алушыларды алдау немесе тауар жібермей төлем алу.'),
                                  ],
                                ),
                                _TermsSection(
                                  title: tr('5. Прекращение работы', '5. Жұмысты тоқтату'),
                                  points: [
                                    tr('При нарушении правил Qoima вправе закрыть магазин без предупреждения.', 'Ережелер бұзылса, Qoima дүкенді ескертусіз жабуға құқылы.'),
                                    tr('Для добровольного закрытия — обратитесь в поддержку.', 'Өз еркімен жабу үшін — қолдау қызметіне хабарласыңыз.'),
                                  ],
                                  last: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Checkbox блогы
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: _bothChecked ? cGreenTint : cSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _bothChecked
                            ? cGreen.withValues(alpha: 0.27)
                            : cLine),
                  ),
                  child: Column(children: [
                    _CheckRow(
                      checked: _terms,
                      label: tr('Ознакомился с условиями использования и принимаю их', 'Қолдану шарттарымен таныстым және оларды қабылдаймын'),
                      onTap: () => setState(() => _terms = !_terms),
                    ),
                    Container(
                        height: 1,
                        color: _bothChecked
                            ? cGreen.withValues(alpha: 0.2)
                            : cLine),
                    _CheckRow(
                      checked: _privacy,
                      label: tr('Согласен с политикой конфиденциальности', 'Құпиялылық саясатына келісемін'),
                      sub: tr('Разрешаю хранение моих данных на платформе', 'Деректерімнің платформада сақталуына рұқсат беремін'),
                      onTap: () => setState(() => _privacy = !_privacy),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),

                AnimatedOpacity(
                  opacity: _bothChecked ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: QPrimaryButton(
                    label: tr('Принять и продолжить', 'Қабылдап жалғастыру'),
                    isLoading: _loading,
                    onPressed: _bothChecked ? _onAccept : null,
                  ),
                ),
                if (!_bothChecked) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(tr('Отметьте оба пункта, чтобы продолжить', 'Жалғастыру үшін екі тармақты да белгілеңіз'),
                        style: manrope(12, FontWeight.w500, color: cInk3)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Шарттар бөлімі ─────────────────────────────────────────────────────────────
class _TermsSection extends StatelessWidget {
  final String title;
  final List<String> points;
  final bool last;
  const _TermsSection(
      {required this.title, required this.points, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: manrope(13, FontWeight.w800, color: cInk)),
        const SizedBox(height: 6),
        ...points.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ',
                      style: manrope(13, FontWeight.w800, color: cGreen)),
                  Expanded(
                    child: Text(p,
                        style: manrope(12.5, FontWeight.w500,
                            color: cInk2, height: 1.45)),
                  ),
                ],
              ),
            )),
        if (!last) const SizedBox(height: 8),
      ],
    );
  }
}

// ── Checkbox жолы ──────────────────────────────────────────────────────────────
class _CheckRow extends StatelessWidget {
  final bool checked;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  const _CheckRow(
      {required this.checked,
      required this.label,
      this.sub,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: checked ? cGreen : cSurface,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: checked ? cGreen : cLine, width: 1.5),
              ),
              child: checked
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: manrope(14, FontWeight.w600, color: cInk,
                          height: 1.35)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!,
                        style: manrope(12, FontWeight.w500, color: cInk3)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
