import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_user.dart';
import '../../../core/deep_links.dart';
import '../../../core/error_text.dart';
import '../../../core/lang.dart';
import '../../../data/models/order_model.dart';
import '../../../data/services/client_service.dart';
import '../../../data/services/gift_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/photo_gallery_viewer.dart';
import '../../shared/require_login.dart';
import '../client_order_detail_screen.dart';
import 'gift_exchange_sheet.dart';
import 'gift_share_screen.dart';

/// Сыйлық сілтемесін ашқан алушының беті.
///
/// Күйлер (`get_gift_public.status`):
///   • ready_to_claim  — «орамды ашу» сәті → өлшем (сыйлаушы таңдаса — алдын
///     ала белгіленген) / басқа өлшем не сол дүкеннің басқа тауары / курьер
///     примеркасына екінші өлшем (+мекенжай) → қабылдау;
///   • awaiting_payment — сыйлаушы әлі төлемді растатпады;
///   • claimed         — алынған (алушы/сыйлаушы үшін бақылау батырмасы);
///   • expired / cancelled — мерзімі өтті / бас тартылды.
/// Қонақ та бетті көреді; кіру тек «Сыйлықты алу» басқанда сұралады.
class GiftReceiveScreen extends StatefulWidget {
  const GiftReceiveScreen({super.key, required this.token});
  final String token;

  @override
  State<GiftReceiveScreen> createState() => _GiftReceiveScreenState();
}

class _GiftReceiveScreenState extends State<GiftReceiveScreen>
    with TickerProviderStateMixin {
  final _gifts = GiftService();
  final _client = ClientService();
  final _confetti = ConfettiController(duration: const Duration(seconds: 3));
  final _shareKey = GlobalKey();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pageCtrl = PageController();

  late final AnimationController _idle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat(reverse: true);
  late final AnimationController _open = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750));

  GiftPublic? _gift;
  bool _loading = true;
  Object? _error;
  bool _revealed = false;
  bool _opening = false;
  bool _claiming = false;
  bool _loadingOptions = false;
  String? _size;

  /// Курьер примеркасына екінші өлшем (міндетті емес).
  String? _altSize;

  /// Алушы сол дүкеннің БАСҚА тауарын таңдаса (null = сыйлықтың өз тауары).
  GiftExchangeProduct? _otherProduct;
  int _page = 0;

  /// Алушы таңдайтын жеткізу ('store' | 'courier') — тек gift.deliveryOpen болса.
  String _delivery = 'store';
  OrderModel? _claimedOrder;
  List<Map<String, dynamic>> _savedAddresses = const [];
  String _lastUid = '';

  @override
  void initState() {
    super.initState();
    _lastUid = AppUser.current.uid;
    DeepLinks.instance.giftScreenOpened(widget.token);
    AppUser.current.addListener(_onUserChanged);
    _prefillPhone();
    _load();
  }

  @override
  void dispose() {
    DeepLinks.instance.giftScreenClosed(widget.token);
    AppUser.current.removeListener(_onUserChanged);
    _idle.dispose();
    _open.dispose();
    _confetti.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _prefillPhone() {
    if (_phoneCtrl.text.isEmpty && AppUser.current.phone.isNotEmpty) {
      _phoneCtrl.text = AppUser.current.phone;
    }
  }

  /// Қонақ кіріп шықса — сыйлықты қайта оқимыз (is_giver/is_recipient өзгереді).
  void _onUserChanged() {
    final uid = AppUser.current.uid;
    if (uid == _lastUid) return;
    _lastUid = uid;
    _prefillPhone();
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final g = await _gifts.getPublic(widget.token);
      if (!mounted) return;
      setState(() {
        _gift = g;
        _loading = false;
        _error = null;
        // Сыйлаушы/қабылданған сыйлық — орам ашу сәті қажет емес.
        if (g != null && (g.isGiver || g.status != 'ready_to_claim')) {
          _revealed = true;
        }
        if (g != null && _otherProduct == null) {
          // Сыйлаушы таңдаған (брондалған) өлшем алдын ала белгіленеді.
          if (_size == null &&
              g.chosenSize.isNotEmpty &&
              g.availableSizes.contains(g.chosenSize)) {
            _size = g.chosenSize;
          }
          if (_size != null && !g.availableSizes.contains(_size)) {
            _size = null;
            _altSize = null;
          }
        }
      });
      if (g != null && g.readyToClaim && g.isCourier) _loadSavedAddresses();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadSavedAddresses() async {
    if (AppUser.current.uid.isEmpty) return;
    try {
      final list = await _client
          .watchAddresses()
          .first
          .timeout(const Duration(seconds: 6));
      if (mounted) setState(() => _savedAddresses = list);
    } catch (_) {}
  }

  // ── Орамды ашу ─────────────────────────────────────────────────────────────
  Future<void> _unwrap() async {
    if (_opening) return;
    HapticFeedback.mediumImpact();
    setState(() => _opening = true);
    _idle.stop();
    await _open.forward();
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    _confetti.play();
    setState(() => _revealed = true);
  }

  // ── Кіру (қабылдау да, басқа тауар таңдау да кірген соң ғана) ─────────────
  Future<bool> _ensureLogin() async {
    // Кіру: гость кірген соң экран жабылады → сілтемені еске сақтап, кейін қайта ашамыз.
    if (AppUser.current.uid.isEmpty) {
      DeepLinks.instance.rememberGift(widget.token);
    }
    final ok = await requireLogin(
      context,
      reasonRu: 'Чтобы получить подарок, войдите или зарегистрируйтесь.',
      reasonKk: 'Сыйлықты алу үшін кіріңіз немесе тіркеліңіз.',
    );
    if (!ok) {
      // Диалог «Болдырмау» болса LoginScreen ашылмайды (экран әлі ағымдағы) —
      // сақталған сілтеме кейін күтпеген жерде ашылмасын.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        DeepLinks.instance.clearPending();
      }
      return false;
    }
    if (!mounted) return false;
    DeepLinks.instance.clearPending();
    if (!AppUser.current.isClient) {
      _snack(
          tr('Подарки доступны только покупателям',
              'Сыйлық тек сатып алушыларға қолжетімді'),
          error: true);
      return false;
    }
    return true;
  }

  /// Қазір курьер ме: алушы таңдаса — оның таңдауы, әйтпесе сыйлаушы белгілеген.
  bool _courierNow(GiftPublic g) =>
      g.deliveryOpen ? _delivery == 'courier' : g.isCourier;

  // ── Өлшем нұсқалары (сыйлықтың өз тауары не таңдалған басқа тауар) ────────
  // Курьерде сыйлықтан қымбат тауар таңдалмайды (доплата — тек дүкеннен алғанда).
  List<GiftSizeOption> _options(GiftPublic g) => [
        for (final o in (_otherProduct?.sizes ?? g.sizeOptions))
          if (o.allowed &&
              !(g.deliveryOpen && _delivery == 'courier' && o.extra > 0))
            o,
      ];

  GiftSizeOption? _selectedOption(GiftPublic g) {
    for (final o in _options(g)) {
      if (o.size == _size) return o;
    }
    return null;
  }

  bool _fittingOn(GiftPublic g) =>
      g.fittingAvailable && !(_otherProduct?.nonReturnable ?? false);

  /// «Басқа өлшем не басқа тауар»: сол дүкеннің қолда бар тауарлары.
  Future<void> _pickOther() async {
    final g = _gift;
    if (g == null || _loadingOptions) return;
    if (!await _ensureLogin() || !mounted) return;
    setState(() => _loadingOptions = true);
    try {
      final opts = await _gifts.getExchangeOptions(widget.token);
      if (!mounted) return;
      setState(() => _loadingOptions = false);
      final choice = await showGiftExchangePicker(
        context,
        options: opts,
        selectedProductId: _otherProduct?.id ?? opts.currentProductId,
        selectedSize: _size,
      );
      if (choice == null || !mounted) return;
      HapticFeedback.selectionClick();
      setState(() {
        _otherProduct = choice.product.isCurrent ? null : choice.product;
        _size = choice.size;
        _altSize = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOptions = false);
      _snack(friendlyError(e), error: true);
    }
  }

  // ── Қабылдау ───────────────────────────────────────────────────────────────
  Future<void> _claim() async {
    final g = _gift;
    if (g == null) return;
    final opt = _selectedOption(g);
    if (_size == null || opt == null) {
      _snack(tr('Выберите размер', 'Өлшемді таңдаңыз'), error: true);
      return;
    }
    if (_courierNow(g) && _addressCtrl.text.trim().length < 4) {
      _snack(tr('Укажите адрес доставки', 'Жеткізу мекенжайын көрсетіңіз'),
          error: true);
      return;
    }
    if (_phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length < 7) {
      _snack(tr('Укажите номер телефона', 'Телефон нөмірін көрсетіңіз'),
          error: true);
      return;
    }
    if (!await _ensureLogin() || !mounted) return;

    final name = _otherProduct?.name ?? g.productName;
    final alt = _fittingOn(g) ? _altSize : null;
    final lines = <String>[
      '${tr('Товар', 'Тауар')}: $name',
      '${tr('Размер', 'Өлшемі')}: ${trValue(_size!)}',
      _courierNow(g)
          ? tr('Получение: курьером по адресу ${_addressCtrl.text.trim()}',
              'Алу: курьермен, мекенжай: ${_addressCtrl.text.trim()}')
          : tr('Получение: в магазине «${g.storeName}»',
              'Алу: «${g.storeName}» дүкенінен'),
      if (g.deliveryOpen && _courierNow(g) && g.courierFeeEstimate > 0)
        tr('Курьеру при получении: ~${money(g.courierFeeEstimate)}',
            'Алғанда курьерге: ~${money(g.courierFeeEstimate)}'),
      if (alt != null)
        tr('Второй размер для примерки: ${trValue(alt)}',
            'Өлшеп көруге екінші өлшем: ${trValue(alt)}'),
      if (opt.extra > 0)
        tr('Доплата ${money(opt.extra)} — в магазине при получении.',
            'Қосымша төлем ${money(opt.extra)} — дүкеннен алған кезде.')
      else if (_otherProduct != null)
        tr('Если товар дешевле подарка, разница не возвращается.',
            'Тауар сыйлықтан арзан болса, айырма қайтарылмайды.'),
      _courierNow(g)
          ? tr(
              'После подтверждения выбор изменить нельзя. После доставки обменять можно в магазине в течение 14 дней.',
              'Растаған соң таңдауды өзгерту мүмкін емес. Жеткізілген соң 14 күн ішінде дүкенде ауыстыруға болады.')
          : tr(
              'Если в магазине не подойдёт — там же обменяете на другой размер или товар (до 14 дней после получения).',
              'Дүкенде келмесе — сол жерде басқа өлшемге не тауарға ауыстырасыз (алғаннан кейін 14 күн ішінде).'),
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Подтвердите получение', 'Алуды растаңыз'),
            style: manrope(17, FontWeight.w800)),
        content: Text(
          lines.join('\n'),
          style: manrope(14, FontWeight.w500, color: cInk2, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Назад', 'Артқа'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Подтвердить', 'Растау'),
                  style: manrope(14, FontWeight.w700, color: cGreen))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _claiming = true);
    try {
      final order = await _gifts.claim(
        token: widget.token,
        size: _size!,
        address: _addressCtrl.text,
        city: _courierNow(g) ? g.storeCity : AppUser.current.city,
        phone: _phoneCtrl.text,
        productId: _otherProduct?.id,
        altSize: alt,
        delivery: g.deliveryOpen ? _delivery : null,
      );
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _confetti.play();
      setState(() {
        _claimedOrder = order;
        _claiming = false;
      });
      _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _claiming = false);
      _snack(friendlyError(e), error: true);
      // Өлшем таусылған болуы мүмкін — тізімді жаңартамыз.
      _load(silent: true);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? cRed : cGreen,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _openOrder() async {
    var order = _claimedOrder;
    if (order == null) {
      final id = _gift?.orderId ?? '';
      if (id.isEmpty) return;
      try {
        // Алушыға orders кестесін оқу құқығы жоқ — тазартылған RPC арқылы;
        // сыйлаушы өз тапсырысын тікелей оқи алады.
        order = (_gift?.isRecipient ?? false)
            ? await _gifts.receivedGift(id)
            : await _client.getOrderById(id);
      } catch (_) {
        order = null;
      }
    }
    if (order == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ClientOrderDetailScreen(order: order!)));
  }

  // ── Көмекшілер ─────────────────────────────────────────────────────────────
  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final g = _gift;
    final teaser = g != null && g.readyToClaim && !g.isGiver && !_revealed;
    return Scaffold(
      backgroundColor: cBg,
      body: Stack(children: [
        if (_loading)
          const Center(
              child: CircularProgressIndicator(color: cGreen, strokeWidth: 2))
        else if (_error != null)
          _errorView()
        else if (g == null)
          _messageView(
            icon: Icons.search_off_rounded,
            title: tr('Подарок не найден', 'Сыйлық табылмады'),
            text: tr(
                'Ссылка неверна или устарела. Попросите отправителя прислать её снова.',
                'Сілтеме қате немесе ескірген. Жіберушіден қайта жіберуді сұраңыз.'),
          )
        else
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, 0.04), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: teaser
                ? KeyedSubtree(key: const ValueKey('teaser'), child: _teaser(g))
                : KeyedSubtree(
                    key: const ValueKey('content'), child: _content(g)),
          ),
        Align(
          alignment: Alignment.topCenter,
          child: IgnorePointer(
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirection: math.pi / 2,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 26,
              maxBlastForce: 24,
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
        ),
      ]),
    );
  }

  Widget _errorView() => _messageView(
        icon: Icons.wifi_off_rounded,
        title: tr('Не удалось загрузить', 'Жүктеу мүмкін болмады'),
        text: friendlyError(_error),
        action: QSoftButton(
            label: tr('Повторить', 'Қайталау'), onPressed: () => _load()),
      );

  Widget _messageView({
    required IconData icon,
    required String title,
    required String text,
    Widget? action,
  }) =>
      SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, color: cInk),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 56, color: cInk3),
                  const SizedBox(height: 16),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: manrope(20, FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(text,
                      textAlign: TextAlign.center,
                      style: manrope(14, FontWeight.w500, color: cInk2)),
                  if (action != null) ...[
                    const SizedBox(height: 20),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ]),
      );

  // ── 1. Жабық қорап ─────────────────────────────────────────────────────────
  Widget _teaser(GiftPublic g) {
    final who = g.giverFirstName.isNotEmpty
        ? g.giverFirstName
        : tr('Кто-то особенный', 'Бір жақсы адам');
    return Container(
      decoration: const BoxDecoration(gradient: kGrad),
      child: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _unwrap,
            child: _GiftBox(idle: _idle, open: _open),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              Text(
                g.recipientName.isNotEmpty
                    ? tr('${g.recipientName}, для вас подарок!',
                        '${g.recipientName}, сізге сыйлық бар!')
                    : tr('Для вас подарок!', 'Сізге сыйлық бар!'),
                textAlign: TextAlign.center,
                style: manrope(26, FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                tr('$who отправил(а) вам сюрприз',
                    '$who сізге тосынсый жіберді'),
                textAlign: TextAlign.center,
                style: manrope(15, FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9)),
              ),
            ]),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _opening ? null : _unwrap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: cGreenDeep,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kR16)),
                ),
                icon: const Icon(Icons.card_giftcard_rounded),
                label: Text(tr('Открыть подарок', 'Сыйлықты ашу'),
                    style: manrope(16, FontWeight.w800, color: cGreenDeep)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 2. Ашылған мазмұн ──────────────────────────────────────────────────────
  Widget _content(GiftPublic g) {
    final claimed = _claimedOrder != null || g.status == 'claimed';
    final showForm = g.readyToClaim && !g.isGiver && _claimedOrder == null;
    return Column(children: [
      QGradientHeader(
        title: tr('Подарок', 'Сыйлық'),
        subtitle: g.giverFirstName.isNotEmpty
            ? tr('От: ${g.giverFirstName}', 'Кімнен: ${g.giverFirstName}')
            : null,
        showBack: true,
        compact: true,
      ),
      Expanded(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16,
              showForm ? 24 : 32 + MediaQuery.of(context).padding.bottom),
          children: [
            _statusBanner(g, claimed),
            _gallery(g),
            const SizedBox(height: 14),
            Text(g.productName, style: manrope(21, FontWeight.w800)),
            if (g.brand.isNotEmpty || g.color.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (g.brand.isNotEmpty) g.brand,
                  if (g.color.isNotEmpty) trValue(g.color),
                ].join(' · '),
                style: manrope(14, FontWeight.w500, color: cInk2),
              ),
            ],
            if (g.price != null) ...[
              const SizedBox(height: 4),
              Text(
                  tr('Стоимость: ${money(g.price!)}',
                      'Құны: ${money(g.price!)}'),
                  style: manrope(13, FontWeight.w600, color: cInk3)),
            ],
            if (g.message.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _messageCard(g),
            ],
            const SizedBox(height: 14),
            _storeCard(g),
            if (showForm) ...[
              const SizedBox(height: 22),
              _claimForm(g),
            ],
            if (_claimedOrder != null) ...[
              const SizedBox(height: 18),
              _claimedCard(_claimedOrder!),
            ],
            if (g.isGiver &&
                (g.status == 'ready_to_claim' ||
                    g.status == 'awaiting_payment')) ...[
              const SizedBox(height: 18),
              _giverActions(g),
            ],
            if ((g.isGiver || g.isRecipient) &&
                g.orderId.isNotEmpty &&
                _claimedOrder == null &&
                (claimed || g.status == 'awaiting_payment')) ...[
              const SizedBox(height: 14),
              QSoftButton(
                label: tr('Открыть заказ', 'Тапсырысты ашу'),
                icon: const Icon(Icons.receipt_long_rounded,
                    color: cGreen, size: 20),
                onPressed: _openOrder,
              ),
            ],
          ],
        ),
      ),
      if (showForm) _claimBar(),
    ]);
  }

  Widget _statusBanner(GiftPublic g, bool claimed) {
    String? title;
    String? text;
    IconData icon = Icons.info_outline_rounded;
    String tone = 'amber';
    switch (g.status) {
      case 'awaiting_payment':
        title = g.isGiver
            ? tr('Ждём подтверждения оплаты', 'Төлемнің расталуын күтудеміз')
            : tr('Подарок готовится', 'Сыйлық дайындалуда');
        text = g.isGiver
            ? tr(
                'Как только магазин подтвердит оплату, получатель сможет выбрать размер.',
                'Дүкен төлемді растағанда, алушы өлшемді таңдай алады.')
            : tr(
                'Отправитель ещё оформляет оплату. Откройте ссылку чуть позже.',
                'Жіберуші төлемді әлі рәсімдеп жатыр. Сілтемені сәл кейінірек ашыңыз.');
        icon = Icons.hourglass_top_rounded;
        break;
      case 'expired':
        title = tr('Срок получения истёк', 'Алу мерзімі өтіп кетті');
        text = g.isGiver
            ? tr(
                'Подарок никто не открыл за 30 дней. Вы можете запросить возврат у магазина.',
                'Сыйлықты 30 күн ішінде ешкім ашпады. Дүкеннен қайтаруды сұрай аласыз.')
            : tr(
                'К сожалению, подарок больше нельзя получить. Свяжитесь с отправителем.',
                'Өкінішке қарай, сыйлықты енді алу мүмкін емес. Жіберушімен хабарласыңыз.');
        icon = Icons.timer_off_rounded;
        tone = 'red';
        break;
      case 'cancelled':
        title = tr('Подарок отменён', 'Сыйлық бас тартылған');
        text = tr('Заказ был отменён магазином или отправителем.',
            'Тапсырысты дүкен немесе жіберуші бас тартты.');
        icon = Icons.cancel_outlined;
        tone = 'red';
        break;
      case 'claimed':
        if (_claimedOrder == null) {
          title = g.isRecipient
              ? tr('Вы получили подарок', 'Сыйлықты қабылдадыңыз')
              : g.isGiver
                  ? tr('Подарок получен', 'Сыйлық алынды')
                  : tr('Подарок уже получен', 'Сыйлық бұрын алынған');
          final parts = <String>[
            if (g.claimedSize.isNotEmpty)
              tr('Выбранный размер: ${trValue(g.claimedSize)}',
                  'Таңдалған өлшем: ${trValue(g.claimedSize)}'),
            if (g.extraDue > 0 && g.orderStatus != OrderModel.statusCompleted)
              tr('Доплата в магазине при получении: ${money(g.extraDue)}',
                  'Алған кезде дүкенде қосымша төлем: ${money(g.extraDue)}'),
            if (g.isRecipient && g.exchangeUntil != null)
              (DateTime.now().isBefore(g.exchangeUntil!)
                  ? tr(
                      'Подарок можно только обменять: принесите товар в магазин до ${_date(g.exchangeUntil!)}.',
                      'Сыйлықты тек ауыстыруға болады: тауарды ${_date(g.exchangeUntil!)} дейін дүкенге апарыңыз.')
                  : tr('Срок обмена истёк.', 'Ауыстыру мерзімі өтті.')),
          ];
          text = parts.isEmpty ? null : parts.join('\n');
          icon = Icons.check_circle_rounded;
          tone = 'green';
        }
        break;
      default:
        break;
    }
    if (title == null) return const SizedBox.shrink();
    final fg = tone == 'red'
        ? cRedInk
        : tone == 'green'
            ? cGreenDeep
            : cAmberInk;
    final bg = tone == 'red'
        ? cRedTint
        : tone == 'green'
            ? cGreenTint
            : cAmberTint;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(kR16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: manrope(15, FontWeight.w800, color: fg)),
            if (text != null) ...[
              const SizedBox(height: 3),
              Text(text, style: manrope(13, FontWeight.w500, color: cInk2)),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _gallery(GiftPublic g) {
    final imgs = g.images;
    if (imgs.isEmpty) {
      return AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kR24),
          child: const QShoeImage(height: 300),
        ),
      );
    }
    return Column(children: [
      AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kR24),
          child: Stack(children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: imgs.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () async {
                  final last = await openPhotoGallery(context,
                      images: imgs, initialIndex: i, heroTagPrefix: 'gift_');
                  if (last != null && _pageCtrl.hasClients) {
                    _pageCtrl.jumpToPage(last);
                  }
                },
                child: Hero(
                  tag: 'gift_$i',
                  child: Image.network(
                    imgs[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const QShoeImage(height: 300),
                  ),
                ),
              ),
            ),
            if (imgs.length > 1)
              Positioned(
                right: 12,
                bottom: 10,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(kRPill),
                    ),
                    child: Text('${_page + 1}/${imgs.length}',
                        style:
                            manrope(12, FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ),
          ]),
        ),
      ),
      if (imgs.length > 1) ...[
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < imgs.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _page ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _page ? cGreen : cLine,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
      ],
    ]);
  }

  Widget _messageCard(GiftPublic g) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8E8), Color(0xFFFFEFD0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(kR20),
          border: Border.all(color: cAmber.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.format_quote_rounded, color: cAmber, size: 28),
          Text(g.message.trim(),
              style: manrope(17, FontWeight.w600, height: 1.4)),
          if (g.giverFirstName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text('— ${g.giverFirstName}',
                  style: manrope(14, FontWeight.w700, color: cAmberInk)),
            ),
          ],
        ]),
      );

  Widget _storeCard(GiftPublic g) => QCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          QIconTile(
            icon: Icon(
                g.isCourier && !g.deliveryOpen
                    ? Icons.delivery_dining_rounded
                    : Icons.storefront_rounded,
                color: cGreen,
                size: 22),
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.storeName, style: manrope(15, FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                g.deliveryOpen && g.readyToClaim && !g.isGiver
                    ? [
                        tr('Магазин, где ждёт подарок',
                            'Сыйлық күтіп тұрған дүкен'),
                        if (g.storeCity.isNotEmpty) trValue(g.storeCity),
                      ].join(' · ')
                    : g.isCourier
                        ? tr(
                            'Курьер привезёт подарок по вашему адресу (г. ${trValue(g.storeCity)})',
                            'Курьер сыйлықты мекенжайыңызға әкеледі (${trValue(g.storeCity)} қ.)')
                        : [
                            tr('Заберёте в магазине', 'Дүкеннен аласыз'),
                            if (g.storeCity.isNotEmpty) trValue(g.storeCity),
                            if (g.storeAddress.isNotEmpty) g.storeAddress,
                          ].join(' · '),
                style: manrope(13, FontWeight.w500, color: cInk2),
              ),
              if (g.isCourier && !g.deliveryOpen && g.deliveryFee > 0) ...[
                const SizedBox(height: 4),
                Text(
                  tr('Доставка курьеру при получении: ${money(g.deliveryFee)}',
                      'Жеткізу ақысы алғанда курьерге: ${money(g.deliveryFee)}'),
                  style: manrope(12, FontWeight.w600, color: cAmberInk),
                ),
              ],
            ]),
          ),
        ]),
      );

  // ── Қабылдау формасы ───────────────────────────────────────────────────────
  Widget _claimForm(GiftPublic g) {
    final opts = _options(g);
    final byName = {for (final o in opts) o.size: o};
    final sizes =
        sortGiftSizes(byName.keys, _otherProduct?.categoryKey ?? g.categoryKey);
    final sel = _selectedOption(g);
    final canSwitch = !g.nonReturnable;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stepLabel(1, tr('Выберите размер', 'Өлшемді таңдаңыз')),
      const SizedBox(height: 10),
      if (_otherProduct != null) ...[
        _otherProductCard(_otherProduct!),
        const SizedBox(height: 10),
      ] else if (g.chosenSize.isNotEmpty) ...[
        _hint(
          g.nonReturnable
              ? tr(
                  'Размер ${trValue(g.chosenSize)} выбран отправителем. Этот товар обменять нельзя.',
                  '${trValue(g.chosenSize)} өлшемін сыйлаушы таңдаған. Бұл тауарды ауыстыруға болмайды.')
              : tr(
                  'Отправитель выбрал размер ${trValue(g.chosenSize)} и забронировал его. Не подходит — выберите другой размер или товар.',
                  'Сыйлаушы ${trValue(g.chosenSize)} өлшемін таңдап, брондап қойды. Келмесе — басқа өлшемді не тауарды таңдаңыз.'),
          icon: g.nonReturnable
              ? Icons.lock_outline_rounded
              : Icons.bookmark_added_rounded,
        ),
        const SizedBox(height: 10),
      ],
      if (sizes.isEmpty)
        QCard(
          color: cRedTint,
          border: Border.all(color: cRed.withValues(alpha: 0.3)),
          child: Text(
            canSwitch
                ? tr(
                    'Размеров этого товара не осталось. Выберите другой товар магазина ниже.',
                    'Бұл тауардың өлшемдері қалмады. Төменнен дүкеннің басқа тауарын таңдаңыз.')
                : tr(
                    'К сожалению, все размеры закончились. Свяжитесь с магазином или отправителем.',
                    'Өкінішке қарай, барлық өлшем таусылды. Дүкенмен немесе жіберушімен хабарласыңыз.'),
            style: manrope(13, FontWeight.w600, color: cRedInk),
          ),
        )
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in sizes) _sizeChip(s, byName[s]),
        ]),
      if (sel != null && sel.extra > 0) ...[
        const SizedBox(height: 10),
        _hint(
          tr('Доплата ${money(sel.extra)} — в магазине при получении.',
              'Қосымша төлем ${money(sel.extra)} — дүкеннен алған кезде.'),
          icon: Icons.payments_outlined,
          amber: true,
        ),
      ],
      if (canSwitch) ...[
        const SizedBox(height: 12),
        QSoftButton(
          label: _loadingOptions
              ? tr('Загружаем…', 'Жүктелуде…')
              : tr('Другой размер или товар', 'Басқа өлшем не тауар'),
          icon: const Icon(Icons.swap_horiz_rounded, color: cGreen, size: 20),
          onPressed: _loadingOptions ? null : _pickOther,
        ),
        const SizedBox(height: 6),
        Text(
          _courierNow(g)
              ? tr(
                  'Можно выбрать другой товар этого магазина не дороже подарка. Если он дешевле, разница не возвращается.',
                  'Осы дүкеннің сыйлықтан қымбат емес басқа тауарын таңдауға болады. Арзан болса, айырма қайтарылмайды.')
              : tr(
                  'Можно выбрать другой товар этого магазина. Дешевле — разница не возвращается; дороже — доплатите разницу в магазине.',
                  'Осы дүкеннің басқа тауарын таңдауға болады. Арзан болса — айырма қайтарылмайды; қымбат болса — айырманы дүкенде төлейсіз.'),
          style: manrope(12, FontWeight.w500, color: cInk3),
        ),
      ],
      if (_fittingOn(g) && sel != null && sel.alts.isNotEmpty) ...[
        const SizedBox(height: 22),
        QSecLabel(tr('Примерка: второй размер', 'Өлшеп көру: екінші өлшем')),
        const SizedBox(height: 6),
        Text(
          tr('Курьер привезёт ещё один размер — оставите подходящий, второй он заберёт обратно. Примерка уже оплачена отправителем.',
              'Курьер тағы бір өлшем әкеледі — сәйкесін қалдырасыз, екіншісін қайтарып әкетеді. Өлшеп көруді сыйлаушы төлеп қойған.'),
          style: manrope(12, FontWeight.w500, color: cInk2),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _altChip(null, tr('Не нужно', 'Керек емес')),
          for (final a in sortGiftSizes(
              sel.alts, _otherProduct?.categoryKey ?? g.categoryKey))
            _altChip(a, trValue(a)),
        ]),
      ],
      const SizedBox(height: 22),
      _stepLabel(2, tr('Как получить', 'Қалай алу')),
      const SizedBox(height: 10),
      if (g.deliveryOpen) ...[
        _modeCard(
          selected: _delivery == 'store',
          icon: Icons.storefront_rounded,
          title: tr('Заберу в магазине', 'Дүкеннен өзім аламын'),
          sub: [
            tr('Бесплатно', 'Тегін'),
            if (g.storeAddress.isNotEmpty) g.storeAddress,
          ].join(' · '),
          onTap: () => setState(() => _delivery = 'store'),
        ),
        const SizedBox(height: 8),
        _modeCard(
          selected: _delivery == 'courier',
          enabled: g.courierAvailable,
          icon: Icons.delivery_dining_rounded,
          title: tr('Курьер привезёт', 'Курьер әкеледі'),
          sub: g.courierAvailable
              ? tr(
                  'Курьеру при получении ~${money(g.courierFeeEstimate)} · только в г. ${trValue(g.storeCity)}',
                  'Алғанда курьерге ~${money(g.courierFeeEstimate)} · тек ${trValue(g.storeCity)} қаласында')
              : tr('В городе магазина курьера пока нет',
                  'Дүкен қаласында курьер әзірге жоқ'),
          onTap: () {
            setState(() {
              _delivery = 'courier';
              if (_selectedOption(g) == null) {
                _size = null;
                _altSize = null;
              }
            });
            _loadSavedAddresses();
          },
        ),
        if (_delivery == 'courier') ...[
          const SizedBox(height: 8),
          _hint(
            tr('С курьером можно выбрать товар не дороже подарка. Доплата возможна только при получении в магазине.',
                'Курьермен сыйлықтан қымбат емес тауар ғана таңдалады. Қосымша төлем тек дүкеннен алғанда мүмкін.'),
            icon: Icons.info_outline_rounded,
            amber: true,
          ),
        ],
      ] else
        _hint(
          g.isCourier
              ? tr('Отправитель выбрал доставку курьером — укажите адрес ниже.',
                  'Жіберуші курьермен жеткізуді таңдаған — мекенжайды төменге жазыңыз.')
              : tr('Подарок можно забрать в магазине.',
                  'Сыйлықты дүкеннен алуға болады.'),
          icon: g.isCourier
              ? Icons.delivery_dining_rounded
              : Icons.storefront_rounded,
        ),
      if (_courierNow(g)) ...[
        const SizedBox(height: 14),
        QSecLabel(tr('Адрес доставки', 'Жеткізу мекенжайы')),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: cGreenTint, borderRadius: BorderRadius.circular(kR12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_city_rounded, color: cGreen, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                tr('Город: ${trValue(g.storeCity)} — курьер доставляет только внутри города магазина',
                    'Қала: ${trValue(g.storeCity)} — курьер тек дүкен қаласының ішінде жеткізеді'),
                style: manrope(12, FontWeight.w600, color: cGreenDeep),
              ),
            ),
          ]),
        ),
        if (_savedAddresses.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in _savedAddresses)
              ActionChip(
                avatar: const Icon(Icons.bookmark_outline_rounded,
                    size: 16, color: cGreen),
                label: Text(
                    (a['label'] as String?)?.isNotEmpty == true
                        ? a['label'] as String
                        : (a['address'] as String? ?? ''),
                    style: manrope(13, FontWeight.w600)),
                backgroundColor: cSurface,
                side: const BorderSide(color: cLine),
                onPressed: () => setState(
                    () => _addressCtrl.text = (a['address'] as String?) ?? ''),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _addressCtrl,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: _dec(tr('Улица, дом, квартира', 'Көше, үй, пәтер'),
              icon: Icons.home_outlined),
        ),
      ],
      const SizedBox(height: 22),
      _stepLabel(3, tr('Ваш телефон', 'Телефон нөміріңіз')),
      const SizedBox(height: 8),
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        decoration: _dec('+7 700 000 00 00', icon: Icons.phone_outlined),
      ),
      const SizedBox(height: 6),
      Text(
        _courierNow(g)
            ? tr(
                'Магазин и курьер свяжутся с вами по этому номеру. Подарок нельзя вернуть деньгами — только обменять в магазине (14 дней после доставки).',
                'Дүкен мен курьер осы нөмір бойынша хабарласады. Сыйлықты ақшаға қайтаруға болмайды — тек дүкенде ауыстыру (жеткізілгеннен кейін 14 күн).')
            : tr(
                'Магазин свяжется с вами по этому номеру. Подарок нельзя вернуть деньгами — только обменять в магазине (14 дней после получения).',
                'Дүкен осы нөмір бойынша хабарласады. Сыйлықты ақшаға қайтаруға болмайды — тек дүкенде ауыстыру (алғаннан кейін 14 күн).'),
        style: manrope(12, FontWeight.w500, color: cInk3),
      ),
    ]);
  }

  Widget _stepLabel(int n, String text) => Row(children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: cGreen, shape: BoxShape.circle),
          child: Text('$n',
              style: manrope(13, FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: manrope(16, FontWeight.w800))),
      ]);

  Widget _modeCard({
    required bool selected,
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
    bool enabled = true,
  }) =>
      Opacity(
        opacity: enabled ? 1 : 0.5,
        child: InkWell(
          borderRadius: BorderRadius.circular(kR16),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? cGreenTint : cSurface,
              borderRadius: BorderRadius.circular(kR16),
              border: Border.all(
                  color: selected ? cGreen : cLine, width: selected ? 1.6 : 1),
            ),
            child: Row(children: [
              Icon(icon, color: selected ? cGreen : cInk3, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: manrope(14, FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: manrope(12, FontWeight.w500, color: cInk2)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: cGreen, size: 22),
            ]),
          ),
        ),
      );

  Widget _hint(String text, {required IconData icon, bool amber = false}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: amber ? cAmberTint : cGreenTint,
          borderRadius: BorderRadius.circular(kR14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: amber ? cAmberInk : cGreenDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: manrope(12.5, FontWeight.w600,
                    color: amber ? cAmberInk : cGreenDeep)),
          ),
        ]),
      );

  Widget _otherProductCard(GiftExchangeProduct p) => QCard(
        padding: const EdgeInsets.all(12),
        border: Border.all(color: cGreen, width: 1.4),
        child: Row(children: [
          SizedBox(
            width: 56,
            height: 56,
            child: QShoeImage(
                imageUrl: p.imageUrl.isNotEmpty ? p.imageUrl : null,
                height: 56),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Вместо подарка', 'Сыйлықтың орнына'),
                  style: manrope(11.5, FontWeight.w700, color: cGreenDeep)),
              const SizedBox(height: 2),
              Text(p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(14, FontWeight.w700)),
            ]),
          ),
          IconButton(
            tooltip: tr('Вернуть исходный подарок', 'Бастапқы сыйлыққа оралу'),
            onPressed: () => setState(() {
              _otherProduct = null;
              _size = null;
              _altSize = null;
              final g = _gift;
              if (g != null &&
                  g.chosenSize.isNotEmpty &&
                  g.availableSizes.contains(g.chosenSize)) {
                _size = g.chosenSize;
              }
            }),
            icon: const Icon(Icons.close_rounded, color: cInk3),
          ),
        ]),
      );

  Widget _sizeChip(String s, GiftSizeOption? o) {
    final sel = _size == s;
    final extra = o?.extra ?? 0;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _size = s;
          if (_altSize != null &&
              (_altSize == s || !(o?.alts.contains(_altSize) ?? false))) {
            _altSize = null;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minWidth: 56),
        padding:
            EdgeInsets.symmetric(horizontal: 16, vertical: extra > 0 ? 7 : 12),
        decoration: BoxDecoration(
          color: sel ? cGreen : cSurface,
          borderRadius: BorderRadius.circular(kR12),
          border: Border.all(color: sel ? cGreen : cLine, width: 1.4),
          boxShadow: sel ? kShadowGreen : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(trValue(s),
              textAlign: TextAlign.center,
              style: manrope(15, FontWeight.w700,
                  color: sel ? Colors.white : cInk)),
          if (extra > 0)
            Text('+${money(extra)}',
                style: manrope(10.5, FontWeight.w700,
                    color: sel ? Colors.white : cAmberInk)),
        ]),
      ),
    );
  }

  Widget _altChip(String? value, String label) {
    final sel = _altSize == value;
    return ChoiceChip(
      label: Text(label,
          style:
              manrope(13.5, FontWeight.w700, color: sel ? Colors.white : cInk)),
      selected: sel,
      showCheckmark: false,
      selectedColor: cGreen,
      backgroundColor: cSurface,
      side: BorderSide(color: sel ? cGreen : cLine),
      onSelected: (_) {
        HapticFeedback.selectionClick();
        setState(() => _altSize = value);
      },
    );
  }

  Widget _claimBar() => Container(
        padding: EdgeInsets.fromLTRB(
            16, 10, 16, 12 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: cSurface,
          border: const Border(top: BorderSide(color: cLine)),
          boxShadow: kShadowSm,
        ),
        child: QPrimaryButton(
          label: tr('Подтвердить получение', 'Алуды растау'),
          icon: const Icon(Icons.card_giftcard_rounded,
              color: Colors.white, size: 20),
          height: 56,
          isLoading: _claiming,
          onPressed: _claiming ? null : _claim,
        ),
      );

  // ── Қабылданған ────────────────────────────────────────────────────────────
  Widget _claimedCard(OrderModel o) {
    final item = o.items.isNotEmpty ? o.items.first : null;
    final courier = o.byPlatformCourier;
    return QCard(
      color: cGreenTint,
      border: Border.all(color: cGreenTint2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle_rounded, color: cGreen, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr('Подарок ваш!', 'Сыйлық сізде!'),
                style: manrope(18, FontWeight.w800, color: cGreenDeep)),
          ),
        ]),
        const SizedBox(height: 8),
        if (item != null) ...[
          Text(item.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: manrope(14, FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            tr('Размер: ${trValue(item.size)}',
                'Өлшемі: ${trValue(item.size)}'),
            style: manrope(14, FontWeight.w600),
          ),
          if (item.altSize.isNotEmpty)
            Text(
              tr('Второй размер для примерки: ${trValue(item.altSize)}',
                  'Өлшеп көруге екінші өлшем: ${trValue(item.altSize)}'),
              style: manrope(13, FontWeight.w600, color: cInk2),
            ),
        ],
        if (o.giftExtraDue > 0) ...[
          const SizedBox(height: 6),
          Text(
            tr('Доплата в магазине при получении: ${money(o.giftExtraDue)}',
                'Алған кезде дүкенде қосымша төлем: ${money(o.giftExtraDue)}'),
            style: manrope(13.5, FontWeight.w800, color: cAmberInk),
          ),
        ],
        const SizedBox(height: 6),
        if (courier)
          Text(
            tr('Курьер доставит подарок по адресу: ${o.address}. Курьер свяжется с вами.',
                'Курьер сыйлықты мына мекенжайға жеткізеді: ${o.address}. Курьер сізбен хабарласады.'),
            style: manrope(13, FontWeight.w500, color: cInk2),
          )
        else ...[
          Text(
            o.warehouseAddress.isNotEmpty
                ? tr('Заберите в магазине: ${o.warehouseAddress}',
                    'Дүкеннен алыңыз: ${o.warehouseAddress}')
                : tr('Заберите подарок в магазине «${o.storeName}»',
                    '«${o.storeName}» дүкенінен алыңыз'),
            style: manrope(13, FontWeight.w500, color: cInk2),
          ),
          if (o.pickupCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tr('Код получения: ${o.pickupCode}', 'Алу коды: ${o.pickupCode}'),
              style: manrope(16, FontWeight.w800, color: cGreenDeep),
            ),
          ],
        ],
        const SizedBox(height: 12),
        QPrimaryButton(
          label: tr('Отследить заказ', 'Тапсырысты қадағалау'),
          icon: const Icon(Icons.local_shipping_outlined,
              color: Colors.white, size: 20),
          onPressed: _openOrder,
        ),
      ]),
    );
  }

  // ── Сыйлаушыға әрекеттер ───────────────────────────────────────────────────
  Widget _giverActions(GiftPublic g) {
    return Column(children: [
      KeyedSubtree(
        key: _shareKey,
        child: QPrimaryButton(
          label: tr('Отправить подарок', 'Сыйлықты жіберу'),
          icon: const Icon(Icons.ios_share_rounded,
              color: Colors.white, size: 20),
          onPressed: () => shareGiftToken(context,
              token: widget.token,
              product: g.productName,
              store: g.storeName,
              originKey: _shareKey),
        ),
      ),
      const SizedBox(height: 10),
      QSoftButton(
        label: tr('Скопировать ссылку', 'Сілтемені көшіру'),
        icon: const Icon(Icons.link_rounded, color: cGreen, size: 20),
        onPressed: () => copyGiftToken(context, widget.token),
      ),
    ]);
  }

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        hintStyle: manrope(14, FontWeight.w500, color: cInk3),
        prefixIcon: icon == null ? null : Icon(icon, color: cInk3, size: 20),
        filled: true,
        fillColor: cSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR14),
          borderSide: const BorderSide(color: cLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR14),
          borderSide: const BorderSide(color: cLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kR14),
          borderSide: const BorderSide(color: cGreen, width: 1.6),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Анимациялы сыйлық қорабы: бос тұрғанда тербеледі, ашылғанда қақпағы ұшып кетеді
// ═════════════════════════════════════════════════════════════════════════════
class _GiftBox extends StatelessWidget {
  final Animation<double> idle;
  final Animation<double> open;
  const _GiftBox({required this.idle, required this.open});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([idle, open]),
      builder: (_, __) {
        final t = Curves.easeInCubic.transform(open.value);
        final wiggle = math.sin(idle.value * math.pi * 2) * 0.035;
        final bounce = -6 * math.sin(idle.value * math.pi);
        return Transform.translate(
          offset: Offset(0, bounce),
          child: Transform.rotate(
            angle: wiggle * (1 - open.value),
            child: SizedBox(
              width: 220,
              height: 230,
              child: Stack(alignment: Alignment.bottomCenter, children: [
                // жарқыл (ашылғанда күшейеді)
                Positioned(
                  bottom: 30,
                  child: Container(
                    width: 190 + 40 * t,
                    height: 190 + 40 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        Colors.white.withValues(alpha: 0.30 + 0.35 * t),
                        Colors.white.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
                // қорап денесі
                Positioned(
                  bottom: 8,
                  child: Container(
                    width: 156,
                    height: 112,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF5D73), Color(0xFFE02F4B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 24,
                            offset: const Offset(0, 12)),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 28,
                        decoration:
                            const BoxDecoration(color: Color(0xFFFFD66B)),
                      ),
                    ),
                  ),
                ),
                // қақпақ
                Positioned(
                  bottom: 112 + 6,
                  child: Opacity(
                    opacity: (1 - t * 1.1).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(26 * t, -120 * t),
                      child: Transform.rotate(
                        angle: 0.5 * t,
                        child: SizedBox(
                          width: 176,
                          height: 78,
                          child: Stack(
                              alignment: Alignment.bottomCenter,
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 176,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFFF7487),
                                        Color(0xFFEA3B58)
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 28,
                                      decoration: const BoxDecoration(
                                          color: Color(0xFFFFD66B)),
                                    ),
                                  ),
                                ),
                                // бант
                                Positioned(
                                  bottom: 30,
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Transform.rotate(
                                          angle: -0.5,
                                          child: _bowLoop(),
                                        ),
                                        const SizedBox(width: 6),
                                        Transform.rotate(
                                          angle: 0.5,
                                          child: _bowLoop(),
                                        ),
                                      ]),
                                ),
                                Positioned(
                                  bottom: 28,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                        color: Color(0xFFFFC53D),
                                        shape: BoxShape.circle),
                                  ),
                                ),
                              ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _bowLoop() => Container(
        width: 34,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFFFD66B),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: const Color(0xFFFFB92E), width: 2),
        ),
      );
}
