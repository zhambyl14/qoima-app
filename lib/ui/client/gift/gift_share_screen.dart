import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_user.dart';
import '../../../core/lang.dart';
import '../../../core/supabase_config.dart';
import '../../../data/models/order_model.dart';
import '../../../theme/qoima_design.dart';
import '../payment_instructions_sheet.dart';
import 'my_gifts_screen.dart';

/// Сыйлау сілтемесімен бірге жіберілетін жылы мәтін (WhatsApp/Telegram).
/// Бағасы ЕШҚАШАН мәтінге кірмейді — сыйлаушы жасырғысы келуі мүмкін.
String giftShareText({
  required String giver,
  required String product,
  required String store,
  required String url,
}) {
  final who = giver.trim();
  return tr(
    '🎁 Для тебя подарок!\n'
        '${who.isEmpty ? 'Тебе' : who} дарит «$product» из магазина «$store». '
        'Открой ссылку, выбери размер — остальное мы доставим:\n$url',
    '🎁 Саған сыйлық бар!\n'
        '${who.isEmpty ? 'Саған' : who} «$store» дүкенінен «$product» сыйлайды. '
        'Сілтемені аш, өлшемді таңда — қалғанын өзіміз жеткіземіз:\n$url',
  );
}

/// Сыйлық сілтемесін жүйелік бөлісу терезесі арқылы жібереді.
/// [originKey] — iPad popover анкері (батырманың RenderBox-ы).
Future<void> shareGiftToken(
  BuildContext context, {
  required String token,
  required String product,
  required String store,
  GlobalKey? originKey,
}) async {
  final url = SupabaseConfig.giftShareUrl(token);
  if (url.isEmpty) return;
  final giver = context.read<AppUser>().name.trim().split(' ').first;
  final text =
      giftShareText(giver: giver, product: product, store: store, url: url);
  Rect? origin;
  final box = originKey?.currentContext?.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    origin = box.localToGlobal(Offset.zero) & box.size;
  }
  try {
    await Share.share(text, sharePositionOrigin: origin);
  } catch (_) {}
}

Future<void> shareGiftLink(BuildContext context, OrderModel order,
        {GlobalKey? originKey}) =>
    shareGiftToken(
      context,
      token: order.giftToken,
      product: order.items.isNotEmpty ? order.items.first.productName : '',
      store: order.storeName,
      originKey: originKey,
    );

/// Сілтемені алмасу буферіне көшіреді.
Future<void> copyGiftToken(BuildContext context, String token) async {
  final url = SupabaseConfig.giftShareUrl(token);
  if (url.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: url));
  HapticFeedback.lightImpact();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(tr('Ссылка скопирована', 'Сілтеме көшірілді')),
      backgroundColor: cGreen,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
}

Future<void> copyGiftLink(BuildContext context, OrderModel order) =>
    copyGiftToken(context, order.giftToken);

/// Сыйлық төленгеннен кейінгі «сәттілік» беті: үлкен бөлісу батырмасы.
class GiftShareScreen extends StatefulWidget {
  final OrderModel order;

  /// true — чек әлі тіркелмеген (төлем нұсқаулығы жабылып қалған).
  final bool receiptPending;
  const GiftShareScreen(
      {super.key, required this.order, this.receiptPending = false});

  @override
  State<GiftShareScreen> createState() => _GiftShareScreenState();
}

class _GiftShareScreenState extends State<GiftShareScreen> {
  final _confetti = ConfettiController(duration: const Duration(seconds: 3));
  final _shareKey = GlobalKey();
  late bool _receiptPending = widget.receiptPending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _confetti.play();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  Future<void> _attachReceipt() async {
    final ok = await showPaymentInstructionsSheet(
      context,
      amount: widget.order.depositAmount,
      orders: [widget.order],
    );
    if (ok == true && mounted) setState(() => _receiptPending = false);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final item = o.items.isNotEmpty ? o.items.first : null;
    return Scaffold(
      backgroundColor: cBg,
      body: Stack(children: [
        SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: cInk),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    gradient: kGrad,
                    shape: BoxShape.circle,
                    boxShadow: kShadowGreen,
                  ),
                  child: const Icon(Icons.card_giftcard_rounded,
                      color: Colors.white, size: 52),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                tr('Подарок готов!', 'Сыйлық дайын!'),
                textAlign: TextAlign.center,
                style: manrope(26, FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Отправьте ссылку получателю. Как только магазин подтвердит оплату, он откроет подарок и выберет размер.',
                  'Сілтемені алушыға жіберіңіз. Дүкен төлемді растағанда, ол сыйлықты ашып, өлшемін таңдайды.',
                ),
                textAlign: TextAlign.center,
                style: manrope(14, FontWeight.w500, color: cInk2),
              ),
              const SizedBox(height: 22),
              QCard(
                child: Row(children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: QShoeImage(imageUrl: item?.imageUrl, height: 64),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item?.productName ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: manrope(15, FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          o.giftRecipientName.isNotEmpty
                              ? tr('Для: ${o.giftRecipientName}',
                                  'Кімге: ${o.giftRecipientName}')
                              : o.storeName,
                          style: manrope(13, FontWeight.w500, color: cInk2),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              if (_receiptPending) ...[
                const SizedBox(height: 12),
                QCard(
                  color: cAmberTint,
                  border: Border.all(color: cAmber.withValues(alpha: 0.4)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.receipt_long_rounded,
                            color: cAmberInk, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('Чек ещё не прикреплён', 'Чек әлі тіркелмеген'),
                            style:
                                manrope(14, FontWeight.w700, color: cAmberInk),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        tr(
                          'Заказ ждёт оплаты. Прикрепите чек в течение 30 минут, иначе заказ отменится.',
                          'Тапсырыс төлемді күтуде. Чекті 30 минут ішінде тіркеңіз, әйтпесе тапсырыс бас тартылады.',
                        ),
                        style: manrope(13, FontWeight.w500, color: cInk2),
                      ),
                      const SizedBox(height: 10),
                      QSoftButton(
                        label: tr(
                            'Оплатить и прикрепить чек', 'Төлеп, чекті тіркеу'),
                        tone: 'amber',
                        onPressed: _attachReceipt,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              KeyedSubtree(
                key: _shareKey,
                child: QPrimaryButton(
                  label: tr('Отправить подарок', 'Сыйлықты жіберу'),
                  icon: const Icon(Icons.ios_share_rounded,
                      color: Colors.white, size: 20),
                  height: 56,
                  onPressed: () =>
                      shareGiftLink(context, o, originKey: _shareKey),
                ),
              ),
              const SizedBox(height: 10),
              QSoftButton(
                label: tr('Скопировать ссылку', 'Сілтемені көшіру'),
                icon: const Icon(Icons.link_rounded, color: cGreen, size: 20),
                onPressed: () => copyGiftLink(context, o),
              ),
              const SizedBox(height: 10),
              QSoftButton(
                label: tr('Мои подарки', 'Менің сыйлықтарым'),
                tone: 'gray',
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const MyGiftsScreen())),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirection: math.pi / 2,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.05,
            numberOfParticles: 22,
            maxBlastForce: 22,
            minBlastForce: 8,
            gravity: 0.25,
            colors: const [
              cGreen,
              cGreenBright,
              cAmber,
              cBlue,
              cPurple,
              cRed,
            ],
          ),
        ),
      ]),
    );
  }
}
