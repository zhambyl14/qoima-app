import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/banks.dart';
import '../../core/contact_utils.dart';
import '../../core/lang.dart';
import '../../data/models/order_model.dart';
import '../../data/models/store_model.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/client_service.dart';
import '../../data/services/cloudinary_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';

/// Төлем нұсқаулығы: төлем картасының нөмірі + чек тіркеу.
///
/// Екі режим (app_settings.payment_mode, superadmin ауыстырады):
///   • 'platform' — барлық аударым БІР модератор картасына, БІР чек барлық
///     суб-тапсырысқа тіркеледі (әдепкі).
///   • 'store' — әр дүкеннің тапсырыстары СОЛ дүкеннің картасына бөлек
///     аударылады; клиент әр дүкенге бөлек чек тіркейді. Дүкен картасын
///     толтырмаса — сол дүкен үшін модератор картасы (fallback). Бұл көп
///     сатушыдан сатып алғанда «біреуіне толық, екіншісіне түк» қатесін
///     болдырмайды — әр дүкеннің сомасы мен реквизиті бөлек.
///
/// Нәтиже: true — барлық чек тіркелді; null/false — жабылды (кейін
/// «Тапсырыстарым» экранынан қайта тіркеуге болады).
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

/// Бір карта — бір реквизит блогы. platform режимінде барлық тапсырысты
/// қамтитын жалғыз топ; store режимінде әр дүкенге бір топ.
class _PayGroup {
  final String id; // platform: 'platform'; store: adminUid
  final String storeName;
  final List<OrderModel> orders;
  // Банк QR сілтемелері {bank_id: qr_link}. Клиент кәдімгі QR-код ретінде көреді.
  final Map<String, String> bankQrs;
  final double amount;
  final bool isFallback; // дүкенде QR жоқ → модератор QR-лары
  _PayGroup({
    required this.id,
    required this.storeName,
    required this.orders,
    required this.bankQrs,
    required this.amount,
    this.isFallback = false,
  });
}

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
  bool _loading = true;
  List<_PayGroup> _groups = [];
  final Set<String> _done = {}; // чек тіркелген топтардың id-лары
  String? _uploadingGroupId; // қай топ жүктелуде

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = AppSettingsService();
      final mode = await settings.getPaymentMode();
      final modCard = await settings.getPaymentCard();

      final groups = <_PayGroup>[];
      if (mode == 'store') {
        // Дүкендердің карталарын аламыз (adminUid → StoreModel).
        Map<String, StoreModel> storeByAdmin = {};
        try {
          final stores = await ClientService().getPublishedStores();
          storeByAdmin = {for (final s in stores) s.adminUid: s};
        } catch (_) {}

        // Тапсырыстарды дүкен (adminUid) бойынша топтаймыз.
        final byAdmin = <String, List<OrderModel>>{};
        for (final o in widget.orders) {
          byAdmin.putIfAbsent(o.adminUid, () => []).add(o);
        }
        byAdmin.forEach((adminUid, orders) {
          final store = storeByAdmin[adminUid];
          // Дүкеннің банк QR-лары; жоқ болса — модератор QR-лары (fallback).
          final storeQrs = store?.bankQrs ?? const <String, String>{};
          final hasQrs = storeQrs.isNotEmpty;
          final qrs = hasQrs ? storeQrs : modCard.bankQrs;
          final amount = orders.fold<double>(0, (s, o) => s + o.depositAmount);
          groups.add(_PayGroup(
            id: adminUid,
            storeName: orders.first.storeName,
            orders: orders,
            bankQrs: qrs,
            amount: amount,
            isFallback: !hasQrs,
          ));
        });
      } else {
        // platform: барлық тапсырыс — модератор банк QR-лары.
        groups.add(_PayGroup(
          id: 'platform',
          storeName: '',
          orders: widget.orders,
          bankQrs: modCard.bankQrs,
          amount: widget.amount,
        ));
      }

      if (mounted) {
        setState(() {
          _groups = groups;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Топқа (дүкенге/платформаға) чек тіркеу: дереккөз таңдау → жүктеу →
  /// сол топтың БАРЛЫҚ суб-тапсырысына жазу. Барлық топ біткенде true қайтады.
  Future<void> _attachReceipt(_PayGroup group) async {
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

    setState(() => _uploadingGroupId = group.id);
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
        if (mounted) setState(() => _uploadingGroupId = null);
        return;
      }

      final fsvc = FirestoreService();
      for (final o in group.orders) {
        await fsvc.submitReceipt(o, url);
      }
      if (!mounted) return;
      setState(() {
        _done.add(group.id);
        _uploadingGroupId = null;
      });
      // Барлық топ біткенде — жабамыз.
      if (_done.length >= _groups.length) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingGroupId = null);
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
    final multi = _groups.length > 1;

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
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
        // Көп дүкенде ҮЛКЕН жалпы соманы КӨРСЕТПЕЙМІЗ — клиент оны бір дүкенге
        // толық аударып жіберуі мүмкін. Әр дүкеннің сомасы төменде бөлек тұрады.
        if (!multi) ...[
          const SizedBox(height: 6),
          Text(money(widget.amount),
              style: manrope(32, FontWeight.w800,
                  color: cInk, letterSpacing: -1)),
        ] else ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cAmberTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.info_outline, color: cAmber, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  tr('Заказ из ${_groups.length} магазинов — платите КАЖДОМУ отдельно по его сумме ниже',
                      '${_groups.length} дүкеннен тапсырыс — ӘРҚАЙСЫСЫНА төмендегі өз сомасымен бөлек төлеңіз'),
                  style: manrope(12.5, FontWeight.w700,
                      color: const Color(0xFF92400E)),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: CircularProgressIndicator(color: cGreen, strokeWidth: 2),
          )
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(children: [
                for (final g in _groups) _buildGroup(g, showTitle: multi),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _uploadingGroupId != null
              ? null
              : () => Navigator.pop(context, _done.isNotEmpty),
          child: Text(
              _done.isNotEmpty
                  ? tr('Готово', 'Дайын')
                  : tr('Прикреплю позже', 'Кейін тіркеймін'),
              style: manrope(14, FontWeight.w600, color: cInk3)),
        ),
      ]),
    );
  }

  Widget _buildGroup(_PayGroup g, {required bool showTitle}) {
    final qrs = orderedBankQrs(g.bankQrs);
    final done = _done.contains(g.id);
    final uploading = _uploadingGroupId == g.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: showTitle ? const EdgeInsets.all(12) : EdgeInsets.zero,
      decoration: showTitle
          ? BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: done ? cGreen : cLine),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showTitle) ...[
          Row(children: [
            const Icon(Icons.storefront_outlined, size: 16, color: cInk2),
            const SizedBox(width: 6),
            Expanded(
              child: Text(g.storeName,
                  style: manrope(14, FontWeight.w800, color: cInk)),
            ),
            Text(money(g.amount),
                style: manrope(18, FontWeight.w800, color: cGreen)),
          ]),
          const SizedBox(height: 10),
        ],
        if (qrs.isEmpty)
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
        else if (done)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cGreenTint,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cGreen.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_rounded, color: cGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Чек отправлен на проверку', 'Чек тексеруге жіберілді'),
                  style: manrope(13, FontWeight.w700, color: cGreenDeep),
                ),
              ),
            ]),
          )
        else ...[
          // ── Төленетін сома ─────────────────────────────────────────────────
          Center(
            child: Column(children: [
              Text(tr('Сумма к оплате', 'Төленетін сома'),
                  style: manrope(12.5, FontWeight.w500, color: cInk2)),
              Text(money(g.amount),
                  style: manrope(26, FontWeight.w800, color: cInk)),
            ]),
          ),
          const SizedBox(height: 10),
          // ── Единый QR нұсқауы ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: cGreenTint, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.qr_code_scanner_rounded,
                  color: cGreenDeep, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Отсканируйте QR любым банковским приложением (Kaspi, Halyk и др.) и переведите сумму.',
                      'QR-ды кез келген банк қосымшасымен (Kaspi, Halyk т.б.) сканерлеп, соманы аударыңыз.'),
                  style: manrope(12, FontWeight.w600, color: cGreenDeep),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // ── QR-код(тар): бір → үлкен; көп → жылжымалы қатар ─────────────────
          _QrArea(qrs: qrs),
          const SizedBox(height: 12),
          if (!showTitle)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          if (!showTitle) const SizedBox(height: 14),
          QPrimaryButton(
            label: tr('Прикрепить чек', 'Чекті тіркеу'),
            isLoading: uploading,
            icon: const Icon(Icons.attach_file_rounded,
                color: Colors.white, size: 18),
            onPressed:
                _uploadingGroupId != null ? null : () => _attachReceipt(g),
            height: 52,
          ),
        ],
      ]),
    );
  }
}

/// QR-код(тар) аймағы: бір банк болса — үлкен ортаға; көп болса — жылжымалы
/// қатар (оң нан солға). Единый QR — кез келген банк қосымшасы сканерлейді.
class _QrArea extends StatelessWidget {
  final List<MapEntry<String, String>> qrs;
  const _QrArea({required this.qrs});

  @override
  Widget build(BuildContext context) {
    if (qrs.length == 1) {
      return Center(
          child: _QrTile(
              bankId: qrs.first.key, link: qrs.first.value, size: 130));
    }
    return SizedBox(
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: qrs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) =>
            _QrTile(bankId: qrs[i].key, link: qrs[i].value, size: 110),
      ),
    );
  }
}

/// Бір банктің QR коды: банк аты + QR суреті. Басу — сілтемені қосымшада ашу
/// (клиент сол телефонда болса, өз банк қосымшасы ашылады).
class _QrTile extends StatelessWidget {
  final String bankId;
  final String link;
  final double size;
  const _QrTile(
      {required this.bankId, required this.link, required this.size});

  Future<void> _open() async {
    try {
      await openExternalUrl(link);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cLine),
            boxShadow: kShadowSm,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(bankName(bankId),
                style: manrope(12.5, FontWeight.w800, color: cInk)),
            const SizedBox(height: 6),
            // QR-дың үстіне «ашылады» белгісі — сурет екені емес, батырма
            // екені бірден көрінсін деп.
            Stack(alignment: Alignment.center, children: [
              QrImageView(
                data: link,
                version: QrVersions.auto,
                size: size,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  color: cGreen,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(Icons.touch_app_rounded,
                    color: Colors.white, size: size * 0.16),
              ),
            ]),
            const SizedBox(height: 8),
            // Айқын, түсті «Открыть» батырмасы — тек жазу емес.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.open_in_new_rounded,
                    size: 12, color: cGreenDeep),
                const SizedBox(width: 4),
                Text(tr('Открыть', 'Ашу'),
                    style: manrope(11, FontWeight.w800, color: cGreenDeep)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
