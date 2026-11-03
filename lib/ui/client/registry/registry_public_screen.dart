import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_user.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/registry_model.dart';
import '../../../data/services/client_service.dart';
import '../../../data/services/registry_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/error_view.dart';
import '../../shared/require_login.dart';
import '../client_shell.dart';
import '../gift/gift_create_sheet.dart';

/// Тілек тізімінің жария беті — сілтемені ашқан қонақ үшін.
///
/// Кірмей-ақ көреді (get_registry_public — anon-ға ашық RPC); сыйлық таңдау
/// кезінде ғана requireLogin. Иесі өз сілтемесін ашса — тек оқу режимі.
class RegistryPublicScreen extends StatefulWidget {
  final String token;
  const RegistryPublicScreen({super.key, required this.token});

  @override
  State<RegistryPublicScreen> createState() => _RegistryPublicScreenState();
}

class _RegistryPublicScreenState extends State<RegistryPublicScreen> {
  final _service = RegistryService();
  final _client = ClientService();

  PublicRegistry? _reg;
  bool _loading = true;
  Object? _error;
  String? _busyItem; // қазір брондалып жатқан позиция
  AppUser? _user;
  String _lastUid = '';

  @override
  void initState() {
    super.initState();
    _load();
    // Қонақ осы экраннан кіріп шықса, is_owner / my_claims қайта оқылуы тиіс
    // (бұрын guest ретінде жүктелген күй ескіріп қалады).
    _user = context.read<AppUser>();
    _lastUid = _user!.uid;
    _user!.addListener(_onUserChanged);
  }

  void _onUserChanged() {
    final uid = _user?.uid ?? '';
    if (uid == _lastUid) return;
    _lastUid = uid;
    if (mounted) _load(silent: true);
  }

  @override
  void dispose() {
    _user?.removeListener(_onUserChanged);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await _service.getPublic(widget.token);
      if (!mounted) return;
      setState(() {
        _reg = r;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? cRed : cGreen,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── «Мен сыйлаймын» ──────────────────────────────────────────────────────
  Future<void> _gift(RegistryItem it) async {
    if (_busyItem != null) return;
    final ok = await requireLogin(
      context,
      reasonRu: 'Войдите в аккаунт, чтобы выбрать подарок',
      reasonKk: 'Сыйлық таңдау үшін аккаунтқа кіріңіз',
    );
    if (!ok || !mounted) return;

    setState(() => _busyItem = it.id);
    try {
      // 1. Дүкен мен тауар әлі сатылымда ма (қоймалар көрінетін болуы тиіс).
      final store = await _client.getStoreByAdminUid(it.adminUid);
      if (store == null || !store.isPublished || store.isBlocked) {
        throw _GiftUnavailable(
            tr('Магазин сейчас недоступен', 'Дүкен қазір қолжетімсіз'));
      }
      final product = await _client.getProductById(it.adminUid, it.productId);
      if (product == null || product.storefrontHidden) {
        throw _GiftUnavailable(
            tr('Товар больше недоступен', 'Тауар енді қолжетімсіз'));
      }
      final batches = await _client.getProductBatches(
        it.adminUid,
        it.productId,
        store.visibleWarehouseIds,
      );
      // Өлшем бойынша ЕҢ ҮЛКЕН бір партиядағы қалдық (қосынды емес): себет
      // жолы бір ғана партияға (batchId) байланады, сондықтан саны сол
      // партиядан аспауы тиіс — әйтпесе checkout-та «қолжетімсіз» болады.
      final avail = <String, int>{};
      for (final b in batches) {
        b.availableSizes.forEach((s, q) {
          if (q > (avail[s] ?? 0)) avail[s] = q;
        });
      }
      if (avail.isEmpty) {
        throw _GiftUnavailable(tr('Товара нет в наличии', 'Тауар қоймада жоқ'));
      }
      if (it.size.isNotEmpty && !avail.containsKey(it.size)) {
        throw _GiftUnavailable(tr('Нужного размера (${it.size}) нет в наличии',
            'Қажетті өлшем (${it.size}) қоймада жоқ'));
      }

      // 2. Бір бронь = бір дана. Өлшем тізімнен бекітілген (бос болса алушы
      //    өзі таңдайды). Қайта басқанда бұрынғы ашық бронь түзетіледі.
      if (!mounted) return;
      final claimId = await _service.reserve(it.id, qty: 1);
      if (!mounted) return;

      // 3. Төлеуші сыйлық ағынынан өтеді: себет/жеткізу/бронь таңдауы ЖОҚ.
      //    Жеткізуді, телефонды, мекенжайды тізім иесі алғанда өзі көрсетеді.
      await showGiftSheet(
        context,
        product: product,
        store: store,
        registryClaimId: claimId,
        fixedSize: it.size,
        recipientName: _reg?.ownerName ?? '',
      );
      if (mounted) _load(silent: true);
    } on _GiftUnavailable catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (e) {
      if (mounted) {
        _toast(registryErrorText(e), error: true);
        _load(silent: true); // біреу бұрын алып қойған болуы мүмкін
      }
    } finally {
      if (mounted) setState(() => _busyItem = null);
    }
  }

  Future<void> _release(RegistryClaim c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
            tr('Отказаться от подарка?', 'Сыйлықтан бас тарту керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Подарок снова станет доступен другим гостям.',
                'Сыйлық басқа қонақтарға қайта қолжетімді болады.'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Назад', 'Артқа'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Отказаться', 'Бас тарту'),
                  style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _service.release(c.id);
      if (!mounted) return;
      // Себеттегі сол бронь жолы да алынады (жетім жол қалмауы үшін).
      final cart = context.read<CartProvider>();
      final idx = cart.items.indexWhere((e) => e.registryClaimId == c.id);
      if (idx >= 0) cart.removeAt(idx);
      if (mounted) _toast(tr('Бронь снята', 'Бронь алынып тасталды'));
      _load(silent: true);
    } catch (e) {
      if (mounted) _toast(registryErrorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _reg;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        if (r != null)
          QGradientHeader(
            title: '${RegistryOccasion.emoji(r.occasion)} ${r.title}',
            subtitle: _subtitle(r),
            showBack: true,
            bottom: [
              if (r.message.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(r.message,
                    style: manrope(13, FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.35)),
              ],
            ],
          )
        else
          QGradientHeader(
            title: tr('Список желаний', 'Той тілек тізімі'),
            showBack: true,
          ),
        Expanded(child: _body()),
      ]),
    );
  }

  String _subtitle(PublicRegistry r) {
    final parts = <String>[
      if (r.ownerName.isNotEmpty) r.ownerName,
      RegistryOccasion.label(r.occasion),
      if (r.eventDate != null) registryDateText(r.eventDate),
      if (r.eventDate != null && (registryDaysLeft(r.eventDate) ?? -1) >= 0)
        registryCountdownText(r.eventDate),
    ];
    return parts.join(' · ');
  }

  Widget _body() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    if (_error != null) {
      return AppErrorView(error: _error, onRetry: () => _load());
    }
    final r = _reg;
    if (r == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎁', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
                tr('Список не найден или закрыт владельцем',
                    'Тізім табылмады немесе иесі жапқан'),
                textAlign: TextAlign.center,
                style: manrope(15, FontWeight.w700, color: cInk2)),
          ]),
        ),
      );
    }

    final itemsById = {for (final i in r.items) i.id: i};
    final myActive = r.myClaims.where((c) => itemsById.containsKey(c.itemId));

    return RefreshIndicator(
      color: cGreen,
      onRefresh: () => _load(silent: true),
      child: ListenableBuilder(
        listenable: FeatureFlags.instance,
        builder: (context, _) {
          final giftingOn =
              FeatureFlags.instance.isOn(FeatureFlags.giftRegistry);
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (r.isOwner)
                SliverToBoxAdapter(
                  child: _Banner(
                    icon: Icons.visibility_rounded,
                    text: r.isActive
                        ? tr('Это ваш список — гости видят его так',
                            'Бұл сіздің тізіміңіз — қонақтар осылай көреді')
                        : tr('Это ваш список — он закрыт для гостей',
                            'Бұл сіздің тізіміңіз — қонақтарға жабық'),
                  ),
                ),
              if (!giftingOn && !r.isOwner)
                SliverToBoxAdapter(
                  child: _Banner(
                    icon: Icons.info_outline_rounded,
                    text: tr('Выбор подарков скоро будет доступен',
                        'Сыйлық таңдау жақында қолжетімді болады'),
                    tone: 'amber',
                  ),
                ),
              if (!r.isOwner && myActive.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          QSecLabel(tr('Мои подарки', 'Менің сыйлықтарым')),
                          for (final c in myActive) ...[
                            _MyClaimRow(
                              item: itemsById[c.itemId]!,
                              claim: c,
                              onRelease: () => _release(c),
                              onToCart: giftingOn
                                  ? () => _gift(itemsById[c.itemId]!)
                                  : null,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ]),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: QSecLabel(tr('Список подарков', 'Сыйлықтар тізімі')),
                ),
              ),
              if (r.items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        tr('Владелец пока ничего не добавил',
                            'Иесі әзірге ештеңе қоспаған'),
                        textAlign: TextAlign.center,
                        style: manrope(14, FontWeight.w600, color: cInk3)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 296 *
                          MediaQuery.textScalerOf(context)
                              .scale(1)
                              .clamp(1.0, 1.3)
                              .toDouble(),
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final it = r.items[i];
                        final mine = r.myClaimFor(it.id);
                        return _ItemCard(
                          item: it,
                          mine: mine,
                          canGift: giftingOn && !r.isOwner && r.isActive,
                          isOwner: r.isOwner,
                          busy: _busyItem == it.id,
                          onGift: () => _gift(it),
                        );
                      },
                      childCount: r.items.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GiftUnavailable implements Exception {
  final String message;
  _GiftUnavailable(this.message);
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String tone;
  const _Banner({required this.icon, required this.text, this.tone = 'green'});

  @override
  Widget build(BuildContext context) {
    final amber = tone == 'amber';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: amber ? cAmberTint : cGreenTint,
        borderRadius: BorderRadius.circular(kR14),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: amber ? cAmberInk : cGreenDeep),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: manrope(13, FontWeight.w700,
                  color: amber ? cAmberInk : cGreenDeep)),
        ),
      ]),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final RegistryItem item;
  final RegistryClaim? mine;
  final bool canGift;
  final bool isOwner;
  final bool busy;
  final VoidCallback onGift;
  const _ItemCard({
    required this.item,
    required this.mine,
    required this.canGift,
    required this.isOwner,
    required this.busy,
    required this.onGift,
  });

  @override
  Widget build(BuildContext context) {
    final it = item;
    final st = it.state;
    final (label, tone) = switch (st) {
      RegistryItemState.free => (tr('Свободен', 'Бос'), 'green'),
      RegistryItemState.reserved => (tr('Забронирован', 'Брондалған'), 'amber'),
      RegistryItemState.purchased => (tr('Куплен', 'Сатып алынды'), 'blue'),
    };
    final isMine = mine != null;
    // Бірнеше дана қалаған позицияда да «бос дана» бар болса — таңдауға болады.
    final canTap = canGift && it.remaining > 0 && it.inStock && !busy;

    return QCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(kR20)),
          child: SizedBox(
            height: 130,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              QShoeImage(imageUrl: it.imageUrl, height: 130),
              if (st != RegistryItemState.free)
                Container(color: Colors.white.withValues(alpha: 0.45)),
              Positioned(left: 8, top: 8, child: QPill(label, tone: tone)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    manrope(13.5, FontWeight.w700, color: cInk, height: 1.25)),
            const SizedBox(height: 4),
            Text(
              [
                if (it.size.isNotEmpty) it.size,
                if (it.qtyWanted > 1)
                  tr('${it.qtyWanted - it.remaining} из ${it.qtyWanted}',
                      '${it.qtyWanted - it.remaining} / ${it.qtyWanted}'),
              ].join(' · '),
              style: manrope(12, FontWeight.w600, color: cInk3),
            ),
            const SizedBox(height: 2),
            Text(it.price > 0 ? money(it.price) : '',
                style: manrope(14, FontWeight.w800, color: cInk)),
            if (it.note.isNotEmpty)
              Text(it.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(11.5, FontWeight.w500, color: cInk3)),
            const Spacer(),
            if (isMine)
              Center(
                child: QPill(
                    mine!.isPurchased
                        ? tr('Вы подарили', 'Сіз сыйладыңыз')
                        : tr('Ваш подарок', 'Сіздің сыйлығыңыз'),
                    tone: 'green',
                    icon: const Icon(Icons.card_giftcard_rounded,
                        size: 13, color: cGreenDeep)),
              )
            else if (isOwner)
              // Тізім иесі өз беті: тек оқу — «Мен сыйлаймын» батырмасы жоқ.
              const SizedBox.shrink()
            else if (!it.inStock && st == RegistryItemState.free)
              Center(
                  child: Text(tr('Нет в наличии', 'Қоймада жоқ'),
                      style: manrope(12.5, FontWeight.w700, color: cInk3)))
            else
              SizedBox(
                width: double.infinity,
                child: QSoftButton(
                  label: tr('Я подарю', 'Мен сыйлаймын'),
                  height: 40,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cGreen))
                      : const Icon(Icons.card_giftcard_rounded,
                          size: 17, color: cGreen),
                  onPressed: canTap ? onGift : null,
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _MyClaimRow extends StatelessWidget {
  final RegistryItem item;
  final RegistryClaim claim;
  final VoidCallback onRelease;
  final VoidCallback? onToCart;
  const _MyClaimRow({
    required this.item,
    required this.claim,
    required this.onRelease,
    required this.onToCart,
  });

  @override
  Widget build(BuildContext context) {
    final c = claim;
    String status;
    if (c.isPurchased) {
      status = tr('Куплено — спасибо!', 'Сатып алынды — рақмет!');
    } else if (c.inOrder) {
      status = tr('В заказе — ожидает оплаты', 'Тапсырыста — төлем күтілуде');
    } else if (c.reservedUntil != null) {
      final t = c.reservedUntil!.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      status = tr(
          'Бронь до ${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}',
          'Бронь: ${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)} дейін');
    } else {
      status = tr('Забронировано', 'Брондалған');
    }
    return QCard(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kR12),
          child: SizedBox(
              width: 52,
              height: 52,
              child: QShoeImage(imageUrl: item.imageUrl, height: 52)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item.productName}${c.qty > 1 ? ' ×${c.qty}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(13.5, FontWeight.w700, color: cInk)),
            const SizedBox(height: 2),
            Text(status, style: manrope(12, FontWeight.w600, color: cInk3)),
          ]),
        ),
        if (c.canRelease) ...[
          if (onToCart != null)
            IconButton(
              tooltip: tr('Оплатить подарок', 'Сыйлықты төлеу'),
              onPressed: onToCart,
              icon: const Icon(Icons.card_giftcard_rounded, color: cGreen),
            ),
          TextButton(
            onPressed: onRelease,
            child: Text(tr('Отказаться', 'Бас тарту'),
                style: manrope(12.5, FontWeight.w700, color: cRed)),
          ),
        ],
      ]),
    );
  }
}

