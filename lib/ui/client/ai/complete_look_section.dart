import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/error_text.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/cart_item_model.dart';
import '../../../data/models/catalog_hit.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/ai_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/require_login.dart';
import '../client_shell.dart';
import 'ai_navigation.dart';
import 'try_on_eligibility.dart';

/// «AI-стилист: образ құрастыру» — тауар карточкасындағы бөлім.
/// Басқанда ai-stylist функциясы осы тауарға лайық басқа тауарларды таңдайды;
/// қолданушы өлшемдерін таңдап, бүкіл образды бірден себетке қосады.
class CompleteLookSection extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;

  const CompleteLookSection({
    super.key,
    required this.product,
    required this.store,
  });

  @override
  State<CompleteLookSection> createState() => _CompleteLookSectionState();
}

class _CompleteLookSectionState extends State<CompleteLookSection> {
  final _ai = AiService();

  LookResult? _look;
  bool _loading = false;
  String? _error;
  bool _errorIsSoft = false; // «сәйкес тауар жоқ» — қате емес, ескерту

  /// productId → таңдалған өлшем
  final Map<String, String> _sizes = {};

  /// Образдан алынып тасталған тауарлар
  final Set<String> _excluded = {};

  Future<void> _generate() async {
    HapticFeedback.selectionClick();
    final ok = await requireLogin(
      context,
      reasonRu: 'Войдите, чтобы AI-стилист собрал образ',
      reasonKk: 'AI-стилист образ құрастыруы үшін кіріңіз',
    );
    if (!ok || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _errorIsSoft = false;
    });
    try {
      // Қала: базалық дүкеннің қаласы (образ бір қаладан жиналады).
      final city = widget.store.city.trim();
      final look = await _ai.buildLook(widget.product.id, city: city);
      if (!mounted) return;
      _sizes.clear();
      _excluded.clear();
      for (final it in look.items) {
        // Бір ғана өлшем болса — алдын ала таңдаймыз.
        if (it.availableSizes.length == 1) {
          _sizes[it.productId] = it.availableSizes.keys.first;
        }
      }
      setState(() {
        _look = look;
        _loading = false;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _errorIsSoft = e.code == 'not_enough_items' ||
            e.code == 'not_supported' ||
            e.isComingSoon;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = genericErrorText();
      });
    }
  }

  double get _total {
    final look = _look;
    if (look == null) return 0;
    var sum = 0.0;
    for (final it in look.items) {
      if (_excluded.contains(it.productId)) continue;
      sum += it.priceFor(_sizes[it.productId]);
    }
    return sum;
  }

  void _addAll() {
    final look = _look;
    if (look == null) return;
    final lines = <CartItemModel>[];
    for (final it in look.items) {
      if (_excluded.contains(it.productId)) continue;
      final size = _sizes[it.productId];
      if (size == null) {
        aiSnack(context,
            tr('Выберите размер: ${it.name}', 'Өлшемді таңдаңыз: ${it.name}'),
            error: true);
        return;
      }
      lines.add(it.toCartItem(size));
    }
    if (lines.isEmpty) {
      aiSnack(context,
          tr('Выберите хотя бы одну вещь', 'Кемінде бір затты таңдаңыз'),
          error: true);
      return;
    }
    HapticFeedback.lightImpact();
    context.read<CartProvider>().addItems(lines);
    aiSnack(
      context,
      tr('Образ добавлен в корзину (${lines.length})',
          'Образ себетке қосылды (${lines.length})'),
      action: SnackBarAction(
        label: tr('В корзину', 'Себетке'),
        textColor: Colors.white,
        onPressed: () {
          // Тауар карточкасы true қайтарса — ата-экран Себет табына өтеді.
          if (mounted) Navigator.of(context).pop(true);
        },
      ),
    );
  }

  Future<void> _open(CatalogHit hit) async {
    final goCart = await openCatalogHit(context, hit);
    if (goCart == true && mounted) Navigator.of(context).pop(true);
  }

  String _slotLabel(String slot) {
    switch (slot) {
      case 'top':
        return tr('Верх', 'Үсті');
      case 'outer':
        return tr('Верхняя одежда', 'Сырт киім');
      case 'bottom':
        return tr('Низ', 'Асты');
      case 'one_piece':
        return tr('Платье / костюм', 'Көйлек / костюм');
      case 'shoes':
        return tr('Обувь', 'Аяқ киім');
      case 'accessory':
        return tr('Аксессуар', 'Аксессуар');
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isLookEligible(widget.product)) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        if (!FeatureFlags.instance.isOn(FeatureFlags.aiStylist)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: _loading
                ? _buildLoading()
                : _look != null
                    ? _buildLook(_look!)
                    : _buildCta(),
          ),
        );
      },
    );
  }

  // ── CTA картасы ───────────────────────────────────────────────────────────
  Widget _buildCta() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GestureDetector(
        onTap: _generate,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [cGreenTint, Color(0xFFF1FBF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(kR20),
            border: Border.all(color: cGreenTint2),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: kGrad,
                borderRadius: BorderRadius.circular(kR14),
              ),
              child:
                  const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('AI-стилист: собрать образ',
                          'AI-стилист: образ құрастыру'),
                      style: manrope(14.5, FontWeight.w800, color: cInk),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr('Подберём, с чем носить этот товар',
                          'Бұл тауармен не киюге болатынын таңдап береміз'),
                      style: manrope(12.5, FontWeight.w500,
                          color: cInk2, height: 1.3),
                    ),
                  ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: cGreenDeep),
          ]),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: manrope(12.5, FontWeight.w600,
              color: _errorIsSoft ? cInk3 : cRedInk),
        ),
      ],
    ]);
  }

  // ── Жүктелу (shimmer) ─────────────────────────────────────────────────────
  Widget _buildLoading() {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return QCard(
      child: Shimmer.fromColors(
        baseColor: cLine2,
        highlightColor: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bar(180, 16),
          const SizedBox(height: 8),
          bar(double.infinity, 12),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            Row(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(kR14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bar(120, 12),
                      const SizedBox(height: 8),
                      bar(double.infinity, 12),
                      const SizedBox(height: 8),
                      bar(80, 12),
                    ]),
              ),
            ]),
            const SizedBox(height: 14),
          ],
        ]),
      ),
    );
  }

  // ── Образ картасы ─────────────────────────────────────────────────────────
  Widget _buildLook(LookResult look) {
    return QCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: cGreen, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              look.title.isNotEmpty
                  ? look.title
                  : tr('Образ от AI-стилиста', 'AI-стилист образы'),
              style: manrope(15.5, FontWeight.w800, color: cInk),
            ),
          ),
        ]),
        if (look.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(look.summary,
              style: manrope(13, FontWeight.w500, color: cInk2, height: 1.4)),
        ],
        const SizedBox(height: 12),
        // Таңдалған (базалық) тауар
        _baseRow(look.base),
        const Divider(height: 22, color: cLine2),
        for (var i = 0; i < look.items.length; i++) ...[
          _itemRow(look.items[i]),
          if (i != look.items.length - 1) const SizedBox(height: 14),
        ],
        const Divider(height: 24, color: cLine2),
        Row(children: [
          Expanded(
            child: Text(
              tr('Итого за дополнения', 'Қосымша заттардың жиынтығы'),
              style: manrope(13, FontWeight.w600, color: cInk2),
            ),
          ),
          Text(money(_total), style: manrope(17, FontWeight.w800, color: cInk)),
        ]),
        const SizedBox(height: 12),
        QPrimaryButton(
          label:
              tr('Добавить весь образ в корзину', 'Бүкіл образды себетке қосу'),
          icon: const Icon(Icons.shopping_bag_outlined,
              color: Colors.white, size: 18),
          onPressed: _addAll,
        ),
        const SizedBox(height: 8),
        QSoftButton(
          label: tr('Другой образ', 'Басқа образ'),
          icon: const Icon(Icons.refresh_rounded),
          tone: 'gray',
          onPressed: _generate,
        ),
      ]),
    );
  }

  Widget _thumb(String url, {double size = 64}) => ClipRRect(
        borderRadius: BorderRadius.circular(kR14),
        child: SizedBox(
          width: size,
          height: size,
          child: url.isEmpty
              ? const ColoredBox(color: cLine2)
              : Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: cLine2)),
        ),
      );

  Widget _baseRow(CatalogHit base) => Row(children: [
        _thumb(base.imageUrl, size: 44),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Ваш выбор', 'Сіздің таңдауыңыз'),
                style: manrope(11.5, FontWeight.w700, color: cGreenDeep)),
            Text(base.name.isNotEmpty ? base.name : widget.product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(13.5, FontWeight.w700, color: cInk)),
          ]),
        ),
      ]);

  Widget _itemRow(CatalogHit it) {
    final included = !_excluded.contains(it.productId);
    final size = _sizes[it.productId];
    return Opacity(
      opacity: included ? 1 : 0.45,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => setState(() {
            included
                ? _excluded.add(it.productId)
                : _excluded.remove(it.productId);
          }),
          child: Padding(
            padding: const EdgeInsets.only(top: 20, right: 8),
            child: Icon(
              included
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: included ? cGreen : cInk3,
              size: 22,
            ),
          ),
        ),
        GestureDetector(
            onTap: () => _open(it), child: _thumb(it.imageUrl, size: 68)),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_slotLabel(it.slot).toUpperCase(),
                style: manrope(10.5, FontWeight.w800,
                    color: cGreenDeep, letterSpacing: 0.6)),
            const SizedBox(height: 2),
            GestureDetector(
              onTap: () => _open(it),
              child: Text(it.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(13.5, FontWeight.w700, color: cInk)),
            ),
            const SizedBox(height: 2),
            Text(
              '${it.storeName} · ${money(it.priceFor(size))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: manrope(12, FontWeight.w600, color: cInk2),
            ),
            if (it.why.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(it.why,
                  style:
                      manrope(12, FontWeight.w500, color: cInk3, height: 1.35)),
            ],
            if (included && it.availableSizes.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizeChips(
                sizes: it.sizeList,
                selected: size,
                onSelect: (s) => setState(() => _sizes[it.productId] = s),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
