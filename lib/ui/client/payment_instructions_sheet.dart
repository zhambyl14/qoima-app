import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/card_utils.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/cloudinary_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';

/// Төлем нұсқаулығы: модератор картасының нөмірі + чек тіркеу.
///
/// Барлық онлайн-төлем платформа (модератор) картасына аударылады. Клиент
/// аударым жасап, чекті (фото/PDF) тіркейді — чек Cloudinary-ге жүктеліп,
/// [orders] тізіміндегі әр тапсырысқа жазылады (submitReceipt). Дүкен иесі
/// чекті тексеріп растағаннан кейін ғана тауар беріледі.
///
/// Нәтиже: true — чек тіркелді; null/false — жабылды (кейін «Тапсырыстарым»
/// экранынан қайта тіркеуге болады).
Future<bool?> showPaymentInstructionsSheet(
  BuildContext context, {
  required double amount,
  required List<OrderModel> orders,
  bool isDeposit = false,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentInstructionsSheet(
        amount: amount,
        orders: orders,
        isDeposit: isDeposit,
      ),
    );

class _PaymentInstructionsSheet extends StatefulWidget {
  final double amount;
  final List<OrderModel> orders;
  final bool isDeposit;
  const _PaymentInstructionsSheet({
    required this.amount,
    required this.orders,
    required this.isDeposit,
  });

  @override
  State<_PaymentInstructionsSheet> createState() =>
      _PaymentInstructionsSheetState();
}

class _PaymentInstructionsSheetState extends State<_PaymentInstructionsSheet> {
  PaymentCardSettings? _card;
  bool _loadingCard = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadCard();
  }

  Future<void> _loadCard() async {
    try {
      final card = await AppSettingsService().getPaymentCard();
      if (mounted) {
        setState(() {
          _card = card;
          _loadingCard = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCard = false);
    }
  }

  Future<void> _attachReceipt() async {
    // Дереккөзді таңдау: галерея / камера / PDF файл.
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: cGreen),
            title: Text(tr('Из галереи', 'Галереядан'),
                style: manrope(14.5, FontWeight.w600, color: cInk)),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: cGreen),
            title: Text(tr('Сделать фото', 'Фото түсіру'),
                style: manrope(14.5, FontWeight.w600, color: cInk)),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: cGreen),
            title: Text(tr('PDF-файл', 'PDF-файл'),
                style: manrope(14.5, FontWeight.w600, color: cInk)),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      String? url;
      if (source == 'pdf') {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
          withData: true,
        );
        final file =
            (res != null && res.files.isNotEmpty) ? res.files.first : null;
        if (file != null && file.bytes != null) {
          url = await CloudinaryService()
              .uploadReceiptBytes(file.bytes!, file.name);
        }
      } else {
        final picked = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 2000,
          imageQuality: 88,
        );
        if (picked != null) {
          url = await CloudinaryService().uploadReceipt(picked);
        }
      }
      if (url == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }

      final fsvc = FirestoreService();
      for (final o in widget.orders) {
        await fsvc.submitReceipt(o, url);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final cardNumber = formatCardDisplay(card?.number ?? '');

    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        Text(
          widget.isDeposit
              ? tr('Оплата депозита', 'Депозит төлеу')
              : tr('Оплата заказа', 'Тапсырысты төлеу'),
          style: manrope(18, FontWeight.w800, color: cInk),
        ),
        const SizedBox(height: 6),
        Text(money(widget.amount),
            style:
                manrope(32, FontWeight.w800, color: cInk, letterSpacing: -1)),
        const SizedBox(height: 16),

        if (_loadingCard)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: CircularProgressIndicator(color: cGreen, strokeWidth: 2),
          )
        else if (card == null || !card.isConfigured)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cAmberTint,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cAmber.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: cAmber, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Реквизиты для оплаты временно недоступны. Попробуйте позже.',
                      'Төлем реквизиттері уақытша қолжетімсіз. Кейінірек көріңіз.'),
                  style: manrope(13, FontWeight.w600,
                      color: const Color(0xFF92400E)),
                ),
              ),
            ]),
          )
        else ...[
          // ── Карта картасы ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: kGrad,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Переведите деньги на карту', 'Ақшаны осы картаға аударыңыз'),
                    style: manrope(12.5, FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: Text(cardNumber,
                          style: manrope(21, FontWeight.w800,
                              color: Colors.white, letterSpacing: 1.2)),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: cardDigitsOnly(card.number)));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr('Номер карты скопирован',
                              'Карта нөмірі көшірілді')),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.copy_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ]),
                  if (card.holder.isNotEmpty || card.bank.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        if (card.holder.isNotEmpty) card.holder,
                        if (card.bank.isNotEmpty) card.bank,
                      ].join(' · '),
                      style: manrope(12.5, FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ],
                ]),
          ),
          const SizedBox(height: 14),
          // ── Түсіндірме ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.receipt_long_outlined, color: cGreen, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('После перевода прикрепите чек (скриншот или PDF). Магазин проверит оплату и подтвердит заказ.',
                      'Аударымнан кейін чекті тіркеңіз (скриншот немесе PDF). Дүкен төлемді тексеріп, тапсырысты растайды.'),
                  style: manrope(12.5, FontWeight.w500, color: cInk2),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          QPrimaryButton(
            label: tr('Прикрепить чек', 'Чекті тіркеу'),
            isLoading: _uploading,
            icon: const Icon(Icons.attach_file_rounded,
                color: Colors.white, size: 18),
            onPressed: _uploading ? null : _attachReceipt,
            height: 52,
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed:
              _uploading ? null : () => Navigator.pop(context, false),
          child: Text(tr('Прикреплю позже', 'Кейін тіркеймін'),
              style: manrope(14, FontWeight.w600, color: cInk3)),
        ),
      ]),
    );
  }
}
