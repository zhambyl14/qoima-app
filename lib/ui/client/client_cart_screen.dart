import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/models/cart_item_model.dart';
import '../../data/models/delivery_tariff.dart';
import '../../data/models/order_model.dart';
import '../../data/models/promo_model.dart';
import '../../data/services/app_settings_service.dart';
import '../../data/services/client_service.dart';
import '../../theme/qoima_design.dart';
import '../auth/auth_widgets.dart';
import '../auth/login_screen.dart';
import 'client_shell.dart';
import 'payment_instructions_sheet.dart';

import '../../core/lang.dart';
import '../../core/error_text.dart';
class ClientCartScreen extends StatefulWidget {
  /// Тапсырыс сәтті жасалғанда (төлемге дайын) шақырылады — ClientShell
  /// Профиль → Тапсырыстарым экранына ауыстырады. null болса (қонақ) — әрекет жоқ.
  final VoidCallback? onOrderSuccess;
  const ClientCartScreen({super.key, this.onOrderSuccess});

  @override
  State<ClientCartScreen> createState() => _ClientCartScreenState();
}

class _ClientCartScreenState extends State<ClientCartScreen> {
  final _service = ClientService();
  // Әдепкі таңдау ЖОҚ — клиент алу тәсілін өзі саналы түрде таңдауы керек
  // (бұрын «Бронь» алдын ала таңдаулы тұрып, көбі байқамай бронь жасайтын).
  String? _orderType;
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  bool _isLoading = false;
  bool _applyingPromo = false;

  Set<String> _unavailableKeys = {};

  // Себеттегі дүкендердің қалалары (adminUid → city) — доставка мәтіні үшін:
  // өз қала = тегін/келісім, басқа қала = Казпочта.
  Map<String, String> _storeCityByAdmin = {};

  // Жеткізу тарифі (0050) — superadmin баптайды, әдепкісі DeliveryTariff-те.
  DeliveryTariff _tariff = const DeliveryTariff();

  // Применённый промокод (привязан к магазину appliedAdminUid)
  PromoModel? _appliedPromo;
  String _appliedAdminUid = '';
  String? _promoError;

  String _itemKey(CartItemModel item) =>
      '${item.productId}_${item.batchId}_${item.size}';

  // ── Тапсырысқа кіретін жолдар (Wildberries/Kaspi стилі чекбокс) ─────────────
  // Чекбокспен таңдалған ЖӘНЕ қолжетімді (unavailable емес) товарлар ғана
  // қорытындыға/тапсырысқа кіреді — таңдалмағаны себетте қала береді.
  List<CartItemModel> _checkoutItems(CartProvider cart) => cart.items
      .where((i) => i.selected && !_unavailableKeys.contains(_itemKey(i)))
      .toList();

  // Позиции магазина, к которому применён промокод
  List<CartItemModel> _promoItems(List<CartItemModel> items) {
    final p = _appliedPromo;
    if (p == null) return const [];
    return items.where((i) {
      if (i.adminUid != _appliedAdminUid) return false;
      if (p.scope == 'products') return p.productIds.contains(i.productId);
      return true;
    }).toList();
  }

  // Текущая скидка по промокоду от актуальной корзины (0 если уже не валиден)
  double _promoDiscount(List<CartItemModel> items) {
    final p = _appliedPromo;
    if (p == null) return 0;
    final base = _promoItems(items).fold<double>(0, (s, i) => s + i.subtotal);
    if (base < p.minOrder) return 0;
    return p.discountFor(base);
  }

  // Сумма экономии по скидкам на товары (зачёркнутая − итоговая)
  double _productSavings(List<CartItemModel> items) =>
      items.fold<double>(0, (s, i) => s + (i.originalSubtotal - i.subtotal));

  Future<void> _applyPromo() async {
    final cart = context.read<CartProvider>();
    final appUser = context.read<AppUser>();
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _applyingPromo = true;
      _promoError = null;
    });
    try {
      // Пробуем по каждому магазину в корзине — берём первый подходящий.
      // Тек тапсырысқа таңдалған товарлар бойынша (чекбокс).
      final checkoutItems = _checkoutItems(cart);
      final admins = checkoutItems.map((i) => i.adminUid).toSet();
      PromoResult? success;
      String? firstError;
      String okAdmin = '';
      for (final adminUid in admins) {
        final items =
            checkoutItems.where((i) => i.adminUid == adminUid).toList();
        final res = await _service.validatePromo(
          adminUid: adminUid,
          code: code,
          items: items,
          clientUid: appUser.uid,
        );
        if (res.isOk) {
          success = res;
          okAdmin = adminUid;
          break;
        }
        firstError ??= res.error;
      }
      if (!mounted) return;
      if (success != null) {
        setState(() {
          _appliedPromo = success!.promo;
          _appliedAdminUid = okAdmin;
          _promoError = null;
        });
      } else {
        setState(() {
          _appliedPromo = null;
          _appliedAdminUid = '';
          _promoError = firstError ?? tr('Промокод не найден', 'Промокод табылмады');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _promoError = tr('Не удалось проверить промокод', 'Промокодты тексеру мүмкін болмады'));
      }
    } finally {
      if (mounted) setState(() => _applyingPromo = false);
    }
  }

  void _removePromo() {
    setState(() {
      _appliedPromo = null;
      _appliedAdminUid = '';
      _promoError = null;
      _promoCtrl.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAvailability());
    AppSettingsService().getDeliveryTariff().then((t) {
      if (mounted) setState(() => _tariff = t);
    });
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty) {
      if (mounted) setState(() => _unavailableKeys = {});
      return;
    }
    try {
      final stores = await _service.getPublishedStores();
      final visibleByAdmin = {
        for (final s in stores) s.adminUid: s.visibleWarehouseIds,
      };
      _storeCityByAdmin = {for (final s in stores) s.adminUid: s.city};

      // Витринада НАҚТЫ көрінетін товар id-лері (фото бар, жасырылмаған, қолда
      // бар). Витринадан алынған товарды (фотосыз/жасырын) сатып алуға болмайды —
      // корзинада тұрса да «недоступен» болады.
      final admins = cart.items.map((i) => i.adminUid).toSet();
      final storefrontIds = <String>{};
      for (final adminUid in admins) {
        try {
          final prods = await _service.getStoreProducts(adminUid);
          storefrontIds.addAll(prods.map((p) => p.id));
        } catch (_) {}
      }

      final unavailable = <String>{};
      for (final item in cart.items) {
        final key = _itemKey(item);
        // Витринадан алынған (жасырылған/фотосыз) → сатуға жарамсыз.
        if (!storefrontIds.contains(item.productId)) {
          unavailable.add(key);
          continue;
        }
        final visible = visibleByAdmin[item.adminUid] ?? [];
        if (!visible.contains(item.warehouseId)) {
          unavailable.add(key);
          continue;
        }
        try {
          final avail = await _service.getBatchAvailability(
              item.adminUid, item.productId, item.batchId);
          if ((avail[item.size] ?? 0) < item.qty) {
            unavailable.add(key);
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _unavailableKeys = unavailable);
    } catch (_) {}
  }

  double _depositFor(double total) {
    if (_orderType == OrderModel.typeSmartReservation) {
      return (total * 0.1).ceilToDouble();
    }
    // Самовывоз — тауардың толық бағасы. Жеткізуде оған қызмет ақысы
    // (курьер + «өлшеп көру») қосылады — клиент бір аударыммен төлейді.
    return total;
  }

  // ── Жеткізу ақысы (0050) ────────────────────────────────────────────────────

  /// Курьер жеткізетін бе (қала ішінде)? Басқа қалаға — Казпочта, ол аппта
  /// есептелмейді. Қала белгісіз болса (гость/қала көрсетілмеген) курьер
  /// жеткізуі деп есептейміз — дүкендердің басым бөлігі бір қалада.
  bool _isCourierDelivery(List<CartItemModel> items) =>
      _orderType == OrderModel.typeDelivery &&
      _allStoresInMyCity(items) != false;

  /// Себеттегі тауарларды қойма бойынша топтайды (әр қойма — жеке суб-тапсырыс
  /// әрі курьердің жеке соғуы). Реті тұрақты: Map кірістіру ретін сақтайды,
  /// сондықтан ақы бөлу мен тапсырыс жасау бірдей индекс береді.
  Map<String, List<CartItemModel>> _byWarehouse(List<CartItemModel> items) {
    final map = <String, List<CartItemModel>>{};
    for (final i in items) {
      map.putIfAbsent(i.warehouseId, () => []).add(i);
    }
    return map;
  }

  /// Барлық қойма бойынша жеткізу ақысы (бірінші — толық, қалғаны жеңілдікпен).
  double _deliveryFee(List<CartItemModel> items) {
    if (!_isCourierDelivery(items)) return 0;
    final total = (items.fold<double>(0, (s, i) => s + i.subtotal) -
            _promoDiscount(items))
        .clamp(0.0, double.infinity);
    return _tariff.totalFee(
        orderTotal: total, storeCount: _byWarehouse(items).length);
  }

  /// «Өлшеп көру» ақысы — қосымша өлшем сұралған ӘР ҚОЙМА үшін бір рет
  /// (курьер сол қоймадан артық жүк алып шығады).
  double _fittingFee(List<CartItemModel> items) {
    if (!_isCourierDelivery(items)) return 0;
    final groups = _byWarehouse(items).values
        .where((g) => g.any((i) => i.hasAltSize))
        .length;
    return _tariff.fittingFee * groups;
  }

  /// Қосымша өлшем сұрауға бола ма (жеткізу + қала ішінде + лимит бітпеген).
  bool _canAddFitting(List<CartItemModel> items, CartItemModel item) {
    if (!_isCourierDelivery(items)) return false;
    if (item.hasAltSize) return true; // өзгертуге/алып тастауға болады
    final used = items.where((i) => i.hasAltSize).length;
    return used < _tariff.fittingMaxItems;
  }

  /// Қосалқы өлшемді таңдау парағы. Тек СОЛ партияның қолжетімді өлшемдері
  /// ұсынылады — бағасы бірдей болады да, клиент 39-ды алса ақша қозғалмайды.
  Future<void> _pickAltSize(int index, CartItemModel item) async {
    final cart = context.read<CartProvider>();
    Map<String, int> avail = {};
    try {
      avail = await _service.getBatchAvailability(
          item.adminUid, item.productId, item.batchId);
    } catch (_) {}
    if (!mounted) return;
    final sizes = avail.entries
        .where((e) => e.key != item.size && e.value >= item.qty)
        .map((e) => e.key)
        .toList()
      ..sort();

    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AltSizeSheet(
        item: item,
        sizes: sizes,
        fittingFee: _tariff.fittingFee,
      ),
    );
    if (picked == null || !mounted) return;
    cart.setAltSize(index, picked == item.altSize ? '' : picked);
  }

  /// Себеттегі барлық дүкен клиенттің қаласында ма? (доставка мәтіні үшін)
  /// null — белгісіз (клиент қаласы көрсетілмеген), true — өз қала, false —
  /// кемінде бір дүкен басқа қалада.
  bool? _allStoresInMyCity(List<CartItemModel> items) {
    final myCity = context.read<AppUser>().city.trim();
    if (myCity.isEmpty || items.isEmpty) return null;
    for (final i in items) {
      final storeCity = (_storeCityByAdmin[i.adminUid] ?? '').trim();
      if (storeCity.isNotEmpty && storeCity != myCity) return false;
    }
    return true;
  }

  String _deliverySubtitle(List<CartItemModel> items) {
    if (_allStoresInMyCity(items) == false) {
      return tr('В ваш город — Казпочтой после 100% оплаты',
          'Сіздің қалаға — 100% төлемнен кейін Казпочтамен');
    }
    if (items.isEmpty) {
      return tr('Курьер по городу — от ${money(_tariff.reducedFee)}',
          'Қала ішінде курьер — ${money(_tariff.reducedFee)}-ден бастап');
    }
    final total =
        (items.fold<double>(0, (s, i) => s + i.subtotal) - _promoDiscount(items))
            .clamp(0.0, double.infinity);
    final fee = _tariff.totalFee(
        orderTotal: total, storeCount: _byWarehouse(items).length);
    return tr('Курьер привезёт — ${money(fee)}',
        'Курьер жеткізеді — ${money(fee)}');
  }

  String _warehouseAddress(List<CartItemModel> items) =>
      items.isNotEmpty ? items.first.warehouseAddress : '';

  /// Төлем батырмасы: кірмеген → логин; кірген → бірден төлем (верификация жоқ).
  Future<void> _onCheckoutPressed() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      // Кіргеннен кейін басты бетке емес, Себетке оралу үшін белгі қоямыз.
      context.read<CartProvider>().pendingCheckout = true;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
          settings: const RouteSettings(name: kLoginRouteName),
        ),
      );
      return;
    }
    await _showPaymentConfirmation();
  }

  Future<void> _showPaymentConfirmation() async {
    final cart = context.read<CartProvider>();
    final appUser = context.read<AppUser>();
    final checkoutItems = _checkoutItems(cart);
    if (checkoutItems.isEmpty) return;
    if (_orderType == null) return; // алу тәсілі таңдалмаған

    if (_orderType == OrderModel.typeDelivery &&
        _addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Введите адрес доставки', 'Жеткізу мекенжайын енгізіңіз')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final subtotal = checkoutItems.fold<double>(0, (s, i) => s + i.subtotal);
    final promoDiscount = _promoDiscount(checkoutItems);
    final total = (subtotal - promoDiscount).clamp(0.0, subtotal);
    final deliveryFee = _deliveryFee(checkoutItems);
    final fittingFee = _fittingFee(checkoutItems);
    final deposit = _depositFor(total) + deliveryFee + fittingFee;

    // Тапсырыс қорытындысы — растау (true) немесе бас тарту (null).
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        orderType: _orderType!,
        subtotal: subtotal,
        promoDiscount: promoDiscount,
        promoCode: _appliedPromo?.code ?? '',
        total: total,
        deposit: deposit,
        deliveryFee: deliveryFee,
        fittingFee: fittingFee,
        kazpost: _allStoresInMyCity(checkoutItems) == false,
        warehouseAddress: _warehouseAddress(checkoutItems),
        deliveryAddress: _addressCtrl.text.trim(),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _checkAvailability();
      if (!mounted) return;
      // Растаудан кейін қайта тексереміз — таңдалған товарлардың бірі осы
      // аралықта қолжетімсіз болып қалуы мүмкін (тек ТАҢДАЛҒАНДАРЫ бөгейді,
      // себеттегі басқа/таңдалмаған товар кедергі жасамайды).
      final stillGood = _checkoutItems(cart);
      final droppedKeys = checkoutItems.map(_itemKey).toSet()
        ..removeAll(stillGood.map(_itemKey).toSet());
      if (droppedKeys.isNotEmpty) {
        final badItems = checkoutItems
            .where((i) => droppedKeys.contains(_itemKey(i)))
            .map((i) => '«${i.productName}»')
            .join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('$badItems недоступен. Удалите из корзины.', '$badItems қолжетімсіз. Себеттен өшіріңіз.')),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
        setState(() => _isLoading = false);
        return;
      }

      final Map<String, List<CartItemModel>> byWarehouse = {};
      for (final item in stillGood) {
        byWarehouse.putIfAbsent(item.warehouseId, () => []).add(item);
      }

      // ── Промокод: распределяем скидку по суб-заказам нужного магазина ─────
      // Учёт used_count ведёт ровно один суб-заказ (usageOwner), отмена которого
      // вернёт счётчик ровно один раз.
      final promo = _appliedPromo;
      final totalPromoDiscount = _promoDiscount(stillGood);
      final promoShares = <String, double>{}; // warehouseId → скидка ₸
      String usageOwnerWh = '';
      if (promo != null && totalPromoDiscount > 0) {
        final adminWhTotals = <String, double>{};
        double adminTotal = 0;
        for (final entry in byWarehouse.entries) {
          if (entry.value.first.adminUid != _appliedAdminUid) continue;
          // только подходящие по scope позиции участвуют в сумме скидки
          final base = entry.value
              .where((i) =>
                  promo.scope != 'products' ||
                  promo.productIds.contains(i.productId))
              .fold<double>(0, (s, i) => s + i.subtotal);
          if (base <= 0) continue;
          adminWhTotals[entry.key] = base;
          adminTotal += base;
        }
        if (adminTotal > 0) {
          final keys = adminWhTotals.keys.toList();
          usageOwnerWh = keys.first;
          double assigned = 0;
          for (var i = 0; i < keys.length; i++) {
            final share = i == keys.length - 1
                ? (totalPromoDiscount - assigned)
                : (totalPromoDiscount * adminWhTotals[keys[i]]! / adminTotal)
                    .roundToDouble();
            promoShares[keys[i]] = share;
            assigned += share;
          }
        }
      }

      // Әр қойма — жеке суб-тапсырыс (pending). Жеткізу ақысы да сол бойынша
      // бөлінеді: әр қойма — курьердің жеке соғуы, бірақ бірінші ғана толық
      // тариф төлейді (қалғаны extraStorePercent). Басқа қалаға — Казпочта,
      // ол аппта есептелмейді (0 қалады, дүкенмен келісіледі).
      final courierDelivery = _isCourierDelivery(stillGood);
      final feeBase = (stillGood.fold<double>(0, (s, i) => s + i.subtotal) -
              totalPromoDiscount)
          .clamp(0.0, double.infinity);

      final placedOrders = <OrderModel>[];
      var whIndex = 0;
      for (final entry in byWarehouse.entries) {
        final whItems = entry.value;
        final first = whItems.first;
        final whTotal = whItems.fold<double>(0, (s, i) => s + i.subtotal);
        final whPromo = (promoShares[entry.key] ?? 0).clamp(0.0, whTotal);
        final whFinal = (whTotal - whPromo).clamp(0.0, whTotal);
        final whDelivery = courierDelivery
            ? _tariff.feeForSubOrder(orderTotal: feeBase, index: whIndex)
            : 0.0;
        final whFitting = courierDelivery && whItems.any((i) => i.hasAltSize)
            ? _tariff.fittingFee
            : 0.0;
        whIndex++;
        final depositAmt = (_orderType == OrderModel.typeSmartReservation
                ? (whFinal * 0.1).ceilToDouble()
                : whFinal) +
            whDelivery +
            whFitting;
        final isUsageOwner = entry.key == usageOwnerWh;
        final order = OrderModel(
          id: '',
          clientPhone: appUser.phone,
          clientName: appUser.name,
          clientUid: appUser.uid,
          adminUid: first.adminUid,
          storeName: first.storeName,
          warehouseId: entry.key,
          warehouseAddress: first.warehouseAddress,
          // Курьер жеткізуі емес болса (самовывоз/бронь/Казпочта) қосалқы
          // өлшемді алып тастаймыз — әйтпесе оны ешкім апармаса да қоймада
          // бекер брондалып қалар еді.
          items: courierDelivery
              ? List.from(whItems)
              : whItems.map((i) => i.copyWith(altSize: '')).toList(),
          status: OrderModel.statusPending,
          orderType: _orderType!,
          createdAt: DateTime.now(),
          address: _addressCtrl.text.trim(),
          note: _noteCtrl.text.trim(),
          depositAmount: depositAmt,
          deliveryFee: whDelivery,
          fittingFee: whFitting,
          promoId: whPromo > 0 && promo != null ? promo.id : '',
          promoCode: whPromo > 0 && promo != null ? promo.code : '',
          promoDiscount: whPromo,
          promoCountsUsage: isUsageOwner && promo != null,
        );
        final placed = await _service.placeOrder(order);
        placedOrders.add(placed);
      }

      if (!mounted) return;
      // Тек тапсырысқа кеткен товарлар өшеді — таңдалмаған қалғаны себетте
      // қалады (Wildberries/Kaspi стилі).
      cart.removeItems(stillGood);
      _appliedPromo = null;
      _appliedAdminUid = '';
      _promoCtrl.clear();
      setState(() => _isLoading = false);

      // Төлем нұсқаулығы: модератор картасы + чек тіркеу. Жабылса да
      // тапсырыс сақталады — «Тапсырыстарым» экранынан қайта тіркеуге болады.
      final payNow = placedOrders.fold<double>(
          0, (s, o) => s + o.depositAmount);
      final attached = await showPaymentInstructionsSheet(
        context,
        amount: payNow,
        orders: placedOrders,
        isDeposit: _orderType == OrderModel.typeSmartReservation,
      );

      if (!mounted) return;
      final shell = context.findAncestorStateOfType<ClientShellState>();
      if (widget.onOrderSuccess != null) {
        widget.onOrderSuccess!();
      } else {
        shell?.openOrdersFromCart();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(attached == true
            ? tr('Чек отправлен на проверку ✓', 'Чек тексеруге жіберілді ✓')
            : tr('Заказ создан — оплатите и прикрепите чек в течение 30 минут',
                'Тапсырыс жасалды — 30 минут ішінде төлеп, чекті тіркеңіз')),
        backgroundColor: attached == true ? cGreen : cAmber,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final itemCount = cart.items.length;
    final checkoutItems = _checkoutItems(cart);
    // «Барлығын таңдау» — қолжетімді (unavailable емес) товарлардың бәрі
    // таңдалған ба (Wildberries/Kaspi стиліндегі шапка чекбоксы).
    final selectableItems =
        cart.items.where((i) => !_unavailableKeys.contains(_itemKey(i))).toList();
    final allSelected = selectableItems.isNotEmpty &&
        selectableItems.every((i) => i.selected);

    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: tr('Корзина', 'Себет'),
          subtitle: itemCount == 0
              ? tr('Пусто', 'Бос')
              : '$itemCount ${_pluralItem(itemCount)}',
          action: itemCount > 0
              ? QHeaderBtn(
                  Icons.delete_sweep_outlined,
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(tr('Очистить корзину', 'Себетті тазалау'),
                          style: manrope(17, FontWeight.w700, color: cInk)),
                      content: Text(tr('Убрать все товары?', 'Барлық тауарды алып тастау керек пе?'),
                          style: manrope(14, FontWeight.w500, color: cInk2)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(tr('Нет', 'Жоқ'),
                                style: manrope(14, FontWeight.w600,
                                    color: cInk2))),
                        TextButton(
                            onPressed: () {
                              cart.clear();
                              Navigator.pop(context);
                            },
                            child: Text(tr('Да', 'Иә'),
                                style: manrope(14, FontWeight.w600,
                                    color: cRed))),
                      ],
                    ),
                  ),
                )
              : null,
        ),
        Expanded(
          child: cart.items.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      const Icon(Icons.shopping_cart_outlined,
                          size: 64, color: cInk3),
                      const SizedBox(height: 16),
                      Text(tr('Корзина пуста', 'Себет бос'),
                          style: manrope(16, FontWeight.w500, color: cInk2)),
                    ]))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  children: [
                    // «Барлығын таңдау» — тек 2+ таңдай алатын товар болғанда
                    // көрсетеміз (бір товарда мағынасы жоқ).
                    if (selectableItems.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => cart.setAllSelected(!allSelected),
                          child: Row(children: [
                            _CartCheckbox(value: allSelected),
                            const SizedBox(width: 10),
                            Text(
                                allSelected
                                    ? tr('Все товары выбраны', 'Барлық тауар таңдалды')
                                    : tr('Выбрать все', 'Барлығын таңдау'),
                                style: manrope(13, FontWeight.w600, color: cInk2)),
                          ]),
                        ),
                      ),
                    // Cart items
                    ...cart.items.asMap().entries.map((entry) {
                      final i = entry.key;
                      final item = entry.value;
                      return _CartItemCard(
                        item: item,
                        isUnavailable:
                            _unavailableKeys.contains(_itemKey(item)),
                        showFitting: item.selected &&
                            _canAddFitting(checkoutItems, item),
                        fittingFee: _tariff.fittingFee,
                        onPickAlt: () => _pickAltSize(i, item),
                        onToggleSelected: () => cart.toggleSelected(i),
                        onDecrement: () {
                          cart.decrementAt(i);
                          _checkAvailability();
                        },
                        onIncrement: () {
                          cart.incrementAt(i);
                          _checkAvailability();
                        },
                        onRemove: () {
                          cart.removeAt(i);
                          _checkAvailability();
                        },
                      );
                    }),

                    const SizedBox(height: 8),
                    QSecLabel(tr('Способ получения *', 'Алу тәсілі *')),
                    // Ештеңе таңдалмаған кезде — таңдау міндетті екенін көрсету.
                    if (_orderType == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          const Icon(Icons.info_outline,
                              size: 15, color: cAmber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr('Выберите способ получения',
                                  'Алу тәсілін таңдаңыз'),
                              style:
                                  manrope(12, FontWeight.w600, color: cAmber),
                            ),
                          ),
                        ]),
                      ),

                    // Алу тәсілдері — халыққа түсінікті атаулар.
                    ...[
                      (
                        OrderModel.typeSmartReservation,
                        Icons.timer_outlined,
                        tr('Бронь', 'Бронь'),
                        tr('Платите 10% — товар ждёт вас 1 час, остальное в магазине',
                            '10% төлейсіз — тауар 1 сағат күтеді, қалғанын дүкенде'),
                        'blue',
                      ),
                      (
                        OrderModel.typeClickCollect,
                        Icons.storefront_outlined,
                        tr('Самовывоз', 'Өзім барып аламын'),
                        tr('Полная оплата онлайн, заберёте в магазине',
                            'Толық онлайн төлем, дүкеннен өзіңіз аласыз'),
                        'green',
                      ),
                      (
                        OrderModel.typeDelivery,
                        Icons.local_shipping_outlined,
                        tr('Доставка', 'Жеткізу'),
                        _deliverySubtitle(checkoutItems),
                        'amber',
                      ),
                    ].map((t) {
                      final (type, icon, title, subtitle, tone) = t;
                      final selected = _orderType == type;
                      return GestureDetector(
                        onTap: () => setState(() => _orderType = type),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: cSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected ? cGreen : cLine,
                              width: selected ? 1.5 : 1,
                            ),
                            boxShadow: kShadowSm,
                          ),
                          child: Row(children: [
                            QIconTile(
                              icon: Icon(_iconFor(type),
                                  color: _iconColor(tone), size: 19),
                              tone: tone,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(title,
                                        style: manrope(
                                            14, FontWeight.w700,
                                            color: cInk)),
                                    Text(subtitle,
                                        style: manrope(
                                            12, FontWeight.w500,
                                            color: cInk3)),
                                  ]),
                            ),
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected ? cGreen : cSurface,
                                border: Border.all(
                                  color: selected ? cGreen : cLine,
                                  width: 2,
                                ),
                              ),
                              child: selected
                                  ? const Icon(Icons.check_rounded,
                                      size: 13, color: Colors.white)
                                  : null,
                            ),
                          ]),
                        ),
                      );
                    }),

                    // Pickup address info (тек алу тәсілі таңдалғанда)
                    if (_orderType != null &&
                        _orderType != OrderModel.typeDelivery &&
                        _warehouseAddress(checkoutItems).isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cGreenTint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(children: [
                          const Icon(Icons.location_on_outlined,
                              color: cGreenDeep, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(
                            tr('Получение: ${_warehouseAddress(checkoutItems)}', 'Алу: ${_warehouseAddress(checkoutItems)}'),
                            style: manrope(12, FontWeight.w500,
                                color: cGreenDeep),
                          )),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Delivery address input
                    if (_orderType == OrderModel.typeDelivery) ...[
                      Text(tr('Адрес доставки *', 'Жеткізу мекенжайы *'),
                          style: manrope(12.5, FontWeight.w700, color: cInk2)),
                      const SizedBox(height: 6),
                      // Saved addresses picker
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _service.watchAddresses(),
                        builder: (context, snap) {
                          final saved = snap.data ?? [];
                          if (saved.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Сохранённые адреса', 'Сақталған мекенжайлар'),
                                  style: manrope(11.5, FontWeight.w600,
                                      color: cInk3)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: saved.map((a) {
                                  final label = a['label'] as String? ?? '';
                                  final addr = a['address'] as String? ?? '';
                                  final display =
                                      label.isNotEmpty ? label : addr;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() =>
                                          _addressCtrl.text = addr);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: _addressCtrl.text == addr
                                            ? cGreen
                                            : cSurface,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                            color: _addressCtrl.text == addr
                                                ? cGreen
                                                : cLine),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.location_on_outlined,
                                                size: 13,
                                                color: _addressCtrl.text ==
                                                        addr
                                                    ? Colors.white
                                                    : cInk3),
                                            const SizedBox(width: 4),
                                            Text(display,
                                                style: manrope(
                                                    12.5,
                                                    FontWeight.w600,
                                                    color: _addressCtrl
                                                                .text ==
                                                            addr
                                                        ? Colors.white
                                                        : cInk)),
                                          ]),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 10),
                            ],
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: cSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cLine, width: 1.5),
                        ),
                        child: TextField(
                          controller: _addressCtrl,
                          style: manrope(14, FontWeight.w500, color: cInk),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: tr('Город, улица, дом', 'Қала, көше, үй'),
                            hintStyle:
                                manrope(14, FontWeight.w500, color: cInk3),
                            prefixIcon: const Icon(Icons.location_on_outlined,
                                color: cInk3, size: 19),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Promo code
                    QSecLabel('Промокод'),
                    _PromoField(
                      controller: _promoCtrl,
                      applied: _appliedPromo,
                      discount: _promoDiscount(checkoutItems),
                      error: _promoError,
                      loading: _applyingPromo,
                      onApply: _applyPromo,
                      onRemove: _removePromo,
                    ),
                    const SizedBox(height: 12),

                    // Note
                    Text(tr('Примечание', 'Ескертпе'),
                        style: manrope(12.5, FontWeight.w700, color: cInk2)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: cSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cLine, width: 1.5),
                      ),
                      child: TextField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        style: manrope(14, FontWeight.w500, color: cInk),
                        decoration: InputDecoration(
                          hintText: tr('Дополнительная информация...', 'Қосымша ақпарат...'),
                          hintStyle:
                              manrope(14, FontWeight.w500, color: cInk3),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 120),
                  ],
                ),
        ),
      ]),
      bottomNavigationBar: cart.items.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                decoration: const BoxDecoration(
                  color: cSurface,
                  border: Border(top: BorderSide(color: cLine)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (checkoutItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        const Icon(Icons.info_outline, size: 15, color: cAmber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              tr('Выберите хотя бы 1 товар для заказа',
                                  'Тапсырыс үшін кемінде 1 тауар таңдаңыз'),
                              style: manrope(12, FontWeight.w600, color: cAmber)),
                        ),
                      ]),
                    ),
                  Builder(builder: (_) {
                    final checkoutTotal = checkoutItems.fold<double>(
                        0, (s, i) => s + i.subtotal);
                    final promoDiscount = _promoDiscount(checkoutItems);
                    final productSavings = _productSavings(checkoutItems);
                    final finalTotal = (checkoutTotal - promoDiscount)
                        .clamp(0.0, checkoutTotal);
                    final deliveryFee = _deliveryFee(checkoutItems);
                    final fittingFee = _fittingFee(checkoutItems);
                    return Column(children: [
                      if (productSavings > 0)
                        _SummaryLine(tr('Скидка по акции', 'Акция бойынша жеңілдік'),
                            '−${money(productSavings)}', color: cGreen),
                      if (promoDiscount > 0)
                        _SummaryLine(
                            'Промокод ${_appliedPromo?.code ?? ''}',
                            '−${money(promoDiscount)}',
                            color: cGreen),
                      if (deliveryFee > 0)
                        _SummaryLine(tr('Доставка курьером', 'Курьер жеткізуі'),
                            money(deliveryFee), color: cInk2),
                      if (fittingFee > 0)
                        _SummaryLine(tr('Примерка', 'Өлшеп көру'),
                            money(fittingFee), color: cInk2),
                      if (productSavings > 0 ||
                          promoDiscount > 0 ||
                          deliveryFee > 0 ||
                          fittingFee > 0)
                        const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _orderType == null
                                  ? tr('Итого', 'Барлығы')
                                  : _orderType ==
                                          OrderModel.typeSmartReservation
                                      ? tr('К оплате сейчас (депозит 10%)',
                                          'Қазір төленетіні (10% депозит)')
                                      : tr('К оплате', 'Төленетін сома'),
                              style: manrope(13.5, FontWeight.w600,
                                  color: cInk2),
                            ),
                            Text(
                              money(_orderType == null
                                  ? finalTotal
                                  : _depositFor(finalTotal) +
                                      deliveryFee +
                                      fittingFee),
                              style:
                                  manrope(20, FontWeight.w800, color: cInk),
                            ),
                          ]),
                    ]);
                  }),
                  const SizedBox(height: 11),
                  QPrimaryButton(
                    label: _orderType == null
                        ? tr('Выберите способ получения',
                            'Алу тәсілін таңдаңыз')
                        : _orderType == OrderModel.typeSmartReservation
                            ? tr('Забронировать', 'Брондау')
                            : tr('Оплатить', 'Төлеу'),
                    isLoading: _isLoading,
                    onPressed: (_isLoading ||
                            _orderType == null ||
                            checkoutItems.isEmpty)
                        ? null
                        : _onCheckoutPressed,
                    height: 54,
                  ),
                ]),
              ),
            ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case OrderModel.typeClickCollect:
        return Icons.storefront_outlined;
      case OrderModel.typeDelivery:
        return Icons.local_shipping_outlined;
      default:
        return Icons.timer_outlined;
    }
  }

  Color _iconColor(String tone) {
    switch (tone) {
      case 'amber':
        return cAmber;
      case 'green':
        return cGreen;
      default:
        return cBlue;
    }
  }

  String _pluralItem(int n) {
    if (n % 10 == 1 && n % 100 != 11) return tr('товар', 'тауар');
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return tr('товара', 'тауар');
    }
    return tr('товаров', 'тауар');
  }
}

// ── Cart item card ─────────────────────────────────────────────────────────────
class _CartItemCard extends StatelessWidget {
  final CartItemModel item;
  final bool isUnavailable;
  /// «Өлшеп көру» чипі көрінсін бе (жеткізу + қала ішінде + лимит бітпеген).
  final bool showFitting;
  final double fittingFee;
  final VoidCallback onPickAlt;
  final VoidCallback onToggleSelected;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final VoidCallback onRemove;
  const _CartItemCard({
    required this.item,
    required this.isUnavailable,
    required this.showFitting,
    required this.fittingFee,
    required this.onPickAlt,
    required this.onToggleSelected,
    required this.onDecrement,
    required this.onIncrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    // Тапсырысқа таңдалмаған/қолжетімсіз позиция сәл көмескі көрінеді —
    // чекбокс күйінің көзге бірден түсуі үшін (Wildberries/Kaspi стилі).
    final dimmed = isUnavailable || !item.selected;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUnavailable ? cRed.withValues(alpha: 0.44) : cLine,
        ),
        boxShadow: kShadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
        if (!isUnavailable) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleSelected,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _CartCheckbox(value: item.selected),
            ),
          ),
        ],
        SizedBox(
          width: 72,
          height: 72,
          child: Opacity(
            opacity: dimmed ? 0.55 : 1.0,
            child: QShoeImage(
              imageUrl: item.imageUrl.isNotEmpty ? item.imageUrl : null,
              height: 72,
              tone: item.productId.hashCode % 5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.productName,
                  style: manrope(13.5, FontWeight.w700, color: cInk),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(tr('Размер ${item.size}', 'Өлшем ${item.size}'),
                  style: manrope(12, FontWeight.w500, color: cInk3)),
              const SizedBox(height: 6),
              if (isUnavailable)
                QPill(tr('Недоступен для заказа', 'Тапсырысқа қолжетімсіз'), tone: 'red',
                    icon: const Icon(Icons.info_outline,
                        size: 12, color: Color(0xFFB11A2B)))
              else if (item.hasDiscount)
                Row(children: [
                  Text(money(item.subtotal),
                      style: manrope(15.5, FontWeight.w800, color: cRed)),
                  const SizedBox(width: 6),
                  Text(money(item.originalSubtotal),
                      style: manrope(12, FontWeight.w500, color: cInk3)
                          .copyWith(decoration: TextDecoration.lineThrough)),
                ])
              else
                Text(money(item.subtotal),
                    style: manrope(15.5, FontWeight.w800, color: cInk)),
            ],
          ),
        ),
        // Quantity stepper
        if (isUnavailable)
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.delete_outline_rounded, color: cRed, size: 20),
            ),
          )
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            _QtyBtn(
              icon: item.qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
              color: item.qty <= 1 ? cRed : cInk2,
              onTap: onDecrement,
            ),
            SizedBox(
              width: 28,
              child: Text('${item.qty}',
                  textAlign: TextAlign.center,
                  style: manrope(15, FontWeight.w800, color: cInk)),
            ),
            _QtyBtn(icon: Icons.add_rounded, color: cGreen, onTap: onIncrement),
          ]),
        ]),
        // ── «Өлшеп көру»: курьер қосалқы өлшемді ҚОСА алып барады ───────────
        // Мұнда тұрғаны маңызды — клиент дәл сол тауардың өлшемін таңдап
        // жатқанда «ал 39-ы дұрыс болса ше?» деген ой келеді.
        if (showFitting) ...[
          const SizedBox(height: 9),
          GestureDetector(
            onTap: onPickAlt,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: item.hasAltSize ? cGreenTint : cBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: item.hasAltSize
                        ? cGreen.withValues(alpha: 0.35)
                        : cLine),
              ),
              child: Row(children: [
                Icon(
                    item.hasAltSize
                        ? Icons.check_circle_rounded
                        : Icons.add_circle_outline_rounded,
                    size: 17,
                    color: item.hasAltSize ? cGreen : cInk3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.hasAltSize
                        ? tr('Курьер привезёт ещё размер ${item.altSize}',
                            'Курьер ${item.altSize} өлшемін де әкеледі')
                        : tr('Привезти ещё один размер на примерку',
                            'Өлшеп көруге тағы бір өлшем әкелу'),
                    style: manrope(12, FontWeight.w700,
                        color: item.hasAltSize ? cGreenDeep : cInk2),
                  ),
                ),
                Text(
                    item.hasAltSize
                        ? tr('изменить', 'өзгерту')
                        : '+${money(fittingFee)}',
                    style: manrope(11.5, FontWeight.w700, color: cInk3)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Қосалқы өлшемді таңдау парағы («өлшеп көру») ───────────────────────────────
class _AltSizeSheet extends StatelessWidget {
  final CartItemModel item;
  final List<String> sizes;
  final double fittingFee;
  const _AltSizeSheet({
    required this.item,
    required this.sizes,
    required this.fittingFee,
  });

  @override
  Widget build(BuildContext context) => Container(
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
          Text(tr('Запасной размер', 'Қосалқы өлшем'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          const SizedBox(height: 6),
          Text(
            tr('Курьер привезёт ваш размер ${item.size} и ещё один — примерите на месте. Платите только за одну пару.',
                'Курьер сіздің ${item.size} өлшеміңізді және тағы бірін әкеледі — орнында өлшеп көресіз. Тек біреуіне ғана төлейсіз.'),
            textAlign: TextAlign.center,
            style: manrope(12.5, FontWeight.w600, color: cInk2, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (sizes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                  tr('Других размеров на складе нет',
                      'Қоймада басқа өлшем жоқ'),
                  style: manrope(13, FontWeight.w600, color: cInk3)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: sizes.map((s) {
                final selected = s == item.altSize;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                    decoration: BoxDecoration(
                      color: selected ? cGreen : cBg,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: selected ? cGreen : cLine, width: 1.5),
                    ),
                    child: Text(s,
                        style: manrope(15, FontWeight.w800,
                            color: selected ? Colors.white : cInk)),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          Text(
            item.hasAltSize
                ? tr('Нажмите на выбранный размер, чтобы убрать примерку',
                    'Өлшеп көруді алып тастау үшін таңдалған өлшемді басыңыз')
                : tr('Услуга: +${money(fittingFee)} к заказу',
                    'Қызмет: тапсырысқа +${money(fittingFee)}'),
            textAlign: TextAlign.center,
            style: manrope(11.5, FontWeight.w600, color: cInk3),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Отмена', 'Болдырмау'),
                style: manrope(14, FontWeight.w600, color: cInk3)),
          ),
        ]),
      );
}

// ── Себет чекбоксы (Wildberries/Kaspi стилі — тапсырысқа таңдау) ────────────────
class _CartCheckbox extends StatelessWidget {
  final bool value;
  const _CartCheckbox({required this.value});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: value ? cGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: value ? cGreen : cLine, width: 2),
        ),
        child: value
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
            : null,
      );
}

// ── Quantity button ────────────────────────────────────────────────────────────
class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      );
}

// ── Тапсырыс қорытындысы (растау) ──────────────────────────────────────────────
// Растағанда true қайтады → тапсырыс жасалады да, карта + чек тіркеу
// нұсқаулығы (payment_instructions_sheet) ашылады.
class _PaymentSheet extends StatelessWidget {
  final String orderType, warehouseAddress, deliveryAddress, promoCode;
  final double total, deposit, subtotal, promoDiscount;
  final double deliveryFee, fittingFee;
  final bool kazpost;
  const _PaymentSheet({
    required this.orderType,
    required this.subtotal,
    required this.promoDiscount,
    required this.promoCode,
    required this.total,
    required this.deposit,
    required this.deliveryFee,
    required this.fittingFee,
    required this.kazpost,
    required this.warehouseAddress,
    required this.deliveryAddress,
  });

  @override
  Widget build(BuildContext context) {
    final isSmartRes = orderType == OrderModel.typeSmartReservation;
    final isDelivery = orderType == OrderModel.typeDelivery;
    final isCC = orderType == OrderModel.typeClickCollect;

    final String typeLabel = isSmartRes
        ? tr('Бронь', 'Бронь')
        : isCC
            ? tr('Самовывоз', 'Өзім барып аламын')
            : tr('Доставка', 'Жеткізу');

    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        QPill(typeLabel, tone: isSmartRes ? 'blue' : isCC ? 'green' : 'amber'),
        const SizedBox(height: 16),
        Text(money(deposit),
            style: manrope(34, FontWeight.w800, color: cInk, letterSpacing: -1)),
        const SizedBox(height: 4),
        Text(
          isSmartRes ? tr('К оплате сейчас (10% депозит)', 'Қазір төленетіні (10% депозит)') : tr('Итого к оплате', 'Барлығы төленетіні'),
          style: manrope(13, FontWeight.w500, color: cInk2),
        ),
        if (isSmartRes) ...[
          const SizedBox(height: 6),
          Text(
            tr('В магазине: ${money((total - deposit).clamp(0, total))}', 'Дүкенде: ${money((total - deposit).clamp(0, total))}'),
            style: manrope(13, FontWeight.w500, color: cInk3),
          ),
        ],
        if (isDelivery) ...[
          const SizedBox(height: 6),
          Text(
            kazpost
                ? tr('Доставка Казпочтой — согласуете с магазином после оплаты',
                    'Казпочтамен жеткізу — төлемнен кейін дүкенмен келісесіз')
                : tr('Курьер заберёт заказ со склада и привезёт вам',
                    'Курьер тапсырысты қоймадан алып, сізге жеткізеді'),
            style: manrope(13, FontWeight.w500, color: cInk3),
          ),
        ],
        const SizedBox(height: 16),
        Container(height: 1, color: cLine),
        const SizedBox(height: 12),
        // Подытог → Промокод → Доставка → Примерка → Итого
        if (promoDiscount > 0 || deliveryFee > 0 || fittingFee > 0) ...[
          _SummaryLine(tr('Подытог', 'Аралық сома'), money(subtotal), color: cInk2),
          if (promoDiscount > 0)
            _SummaryLine(
                promoCode.isNotEmpty ? 'Промокод $promoCode' : 'Промокод',
                '−${money(promoDiscount)}',
                color: cGreen),
          if (deliveryFee > 0)
            _SummaryLine(tr('Доставка курьером', 'Курьер жеткізуі'),
                money(deliveryFee), color: cInk2),
          if (fittingFee > 0)
            _SummaryLine(tr('Примерка (запасной размер)',
                    'Өлшеп көру (қосалқы өлшем)'),
                money(fittingFee), color: cInk2),
          _SummaryLine(tr('Итого', 'Барлығы'),
              money(total + deliveryFee + fittingFee),
              color: cInk, bold: true),
          const SizedBox(height: 8),
        ],
        // Курьер жол шығынын өтейді — бас тартқанда жеткізу ақысы қайтпайды.
        // Клиент мұны ТӨЛЕМГЕ ДЕЙІН көруі керек.
        if (deliveryFee > 0) ...[
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: cAmberTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, color: cAmber, size: 17),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  tr('Если откажетесь от заказа при доставке — стоимость доставки не возвращается.',
                      'Жеткізу кезінде тапсырыстан бас тартсаңыз — жеткізу ақысы қайтарылмайды.'),
                  style: manrope(12, FontWeight.w600, color: cInk2, height: 1.35),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (!isDelivery && warehouseAddress.isNotEmpty)
          _InfoRow(Icons.location_on_outlined, tr('Адрес получения', 'Алу мекенжайы'),
              warehouseAddress),
        if (isDelivery && deliveryAddress.isNotEmpty)
          _InfoRow(Icons.local_shipping_outlined, tr('Доставка', 'Жеткізу'), deliveryAddress),
        if (isSmartRes)
          _InfoRow(Icons.timer_outlined, tr('Срок брони', 'Бронь мерзімі'), tr('1 час', '1 сағат')),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.credit_card_rounded, color: cGreen, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Оплата переводом на карту. На следующем шаге появятся реквизиты и кнопка «Прикрепить чек».',
                    'Төлем — картаға аударым. Келесі қадамда реквизиттер мен «Чекті тіркеу» батырмасы шығады.'),
                style: manrope(12.5, FontWeight.w500, color: cInk2),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        QPrimaryButton(
          label: tr('Продолжить к оплате', 'Төлемге өту'),
          onPressed: () => Navigator.pop(context, true),
          height: 52,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(tr('Отмена', 'Болдырмау'),
              style: manrope(14, FontWeight.w600, color: cInk3)),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: cGreen),
          const SizedBox(width: 8),
          Expanded(
              child: RichText(
                  text: TextSpan(children: [
            TextSpan(
                text: '$label: ',
                style: manrope(13, FontWeight.w500, color: cInk2)),
            TextSpan(
                text: value,
                style: manrope(13, FontWeight.w700, color: cInk)),
          ]))),
        ]),
      );
}

// ── Summary line (Подытог / Скидка / Промокод / Итого) ──────────────────────────
class _SummaryLine extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool bold;
  const _SummaryLine(this.label, this.value,
      {required this.color, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: manrope(bold ? 14.5 : 13, FontWeight.w600,
                    color: bold ? cInk : cInk2)),
            Text(value,
                style: manrope(bold ? 16 : 13.5,
                    bold ? FontWeight.w800 : FontWeight.w700,
                    color: color)),
          ],
        ),
      );
}

// ── Promo code field ────────────────────────────────────────────────────────────
class _PromoField extends StatelessWidget {
  final TextEditingController controller;
  final PromoModel? applied;
  final double discount;
  final String? error;
  final bool loading;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  const _PromoField({
    required this.controller,
    required this.applied,
    required this.discount,
    required this.error,
    required this.loading,
    required this.onApply,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    // Применён и действует
    if (applied != null) {
      final ineffective = discount <= 0;
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: ineffective ? cAmberTint : cGreenTint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: ineffective
                  ? cAmber.withValues(alpha: 0.4)
                  : cGreen.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(ineffective ? Icons.info_outline : Icons.check_circle_rounded,
              size: 18, color: ineffective ? cAmber : cGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(applied!.code,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: cGreenDeep)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: ineffective ? cAmber : cGreen,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(ineffective ? tr('Не активен', 'Белсенді емес') : tr('Применён', 'Қолданылды'),
                        style: manrope(10, FontWeight.w700,
                            color: Colors.white)),
                  ),
                ]),
                Text(
                  ineffective
                      ? tr('Не хватает до минимальной суммы заказа', 'Тапсырыстың ең аз сомасына жетпейді')
                      : tr('Скидка −${money(discount)}', 'Жеңілдік −${money(discount)}'),
                  style: manrope(12, FontWeight.w600,
                      color: ineffective ? cAmber : cGreenDeep),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: cInk3),
            onPressed: onRemove,
          ),
        ]),
      );
    }

    // Поле ввода
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: error != null ? cRed : cLine, width: 1.5),
            ),
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              style: manrope(14, FontWeight.w700, color: cInk),
              decoration: InputDecoration(
                hintText: tr('Введите промокод', 'Промокод енгізіңіз'),
                hintStyle: manrope(14, FontWeight.w500, color: cInk3),
                prefixIcon:
                    const Icon(Icons.local_offer_outlined, color: cInk3, size: 19),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: loading ? null : onApply,
            style: ElevatedButton.styleFrom(
              backgroundColor: cGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text(tr('Применить', 'Қолдану'),
                    style: manrope(14, FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]),
      if (error != null) ...[
        const SizedBox(height: 6),
        Text(error!, style: manrope(12, FontWeight.w600, color: cRed)),
      ],
    ]);
  }
}
