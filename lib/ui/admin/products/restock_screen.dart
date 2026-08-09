import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/error_text.dart';
import '../../../core/lang.dart';
import '../../../core/search_helper.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/models.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/mandatory_warehouse_picker.dart';

/// «Повторный завоз» — БАР тауарға жаңа партия қосу.
///
/// НЕГЕ ЖЕКЕ ЭКРАН: бұрын жалғыз жол «Добавить» формасын толық қайта толтыру
/// еді — атауын, брендін, түсін, түрін бір әріпке дейін дәл солай теру керек
/// болатын. Бір әріп қате болса ЖАҢА карточка пайда болатын (қойма екіге
/// бөлінеді), ал дәл сәйкес келсе — үнсіз жаңа партия. Екеуі де байқалмай
/// өтетін. Мұнда админ тауарды ТІЗІМНЕН таңдайды — қателесу мүмкіндігі жоқ.
///
/// [product] берілсе — тізім өткізіліп, бірден толтыру қадамына кіреді
/// (қосу формасындағы «мұндай тауар бар» ескертуінен осылай ашылады).
class RestockScreen extends StatefulWidget {
  final ProductModel? product;
  const RestockScreen({super.key, this.product});

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  final _service = FirestoreService();
  final _searchCtrl = TextEditingController();
  final _purchaseCtrl = TextEditingController();
  final _sellingCtrl = TextEditingController();

  List<ProductModel> _all = [];
  bool _loadingList = true;
  String _query = '';

  ProductModel? _selected;
  BatchModel? _lastBatch; // алдыңғы партия — «сол күйі қалдыру» үшін эталон
  bool _loadingBatch = false;
  bool _saving = false;

  /// Жаңа партияның размер торы (алдыңғысынан алдын ала толтырылады).
  final Map<String, int> _sizes = {};
  DateTime _dateArrived = DateTime.now();

  int get _total => _sizes.values.fold(0, (a, b) => a + b);

  /// Алдыңғы партияның КЕЛГЕН саны (қазіргі қалдығы емес!).
  ///
  /// ⚠️ Бұрын мұнда `sizesQuantity` тұрған — ол сатылған сайын азаятын
  /// ағымдағы қалдық. Соның кесірінен «прошлый завоз: 41-1» деп көрсетілетін
  /// (шын мәнінде 41-ден 5 жұп әкелініп, 4-і сатылған). Админ соны эталон
  /// деп қабылдап, келесі партияны да қате санмен әкелетін.
  Map<String, int> get _lastArrived =>
      _lastBatch?.arrivedSizes ?? const <String, int>{};

  /// Размер линиясы алдыңғы партиямен ДӘЛ бірдей ме (админге «сол күйі» деп
  /// растау үшін).
  bool get _sameAsLast {
    final last = _lastArrived;
    final cur = {..._sizes}..removeWhere((_, v) => v <= 0);
    final prev = {...last}..removeWhere((_, v) => v <= 0);
    if (cur.length != prev.length) return false;
    for (final e in cur.entries) {
      if (prev[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _selected = widget.product;
      _loadBatch(widget.product!);
    }
    _loadProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _purchaseCtrl.dispose();
    _sellingCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final list = await _service.getAllProducts();
      if (mounted) setState(() { _all = list; _loadingList = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  /// Таңдалған тауардың СОҢҒЫ партиясын тартып, форманы алдын ала толтырады.
  Future<void> _loadBatch(ProductModel p) async {
    setState(() {
      _loadingBatch = true;
      _sizes.clear();
      _purchaseCtrl.clear();
      _sellingCtrl.clear();
    });
    try {
      final b = await _service.lastBatchWithCost(p.id);
      if (!mounted) return;
      setState(() {
        _lastBatch = b;
        _loadingBatch = false;
        if (b != null) {
          // Алдыңғы жолы ҚАНША ӘКЕЛГЕНІ (қалдығы емес) — жаңа партияның
          // әдепкі торы да сол.
          _sizes.addAll(Map<String, int>.from(b.arrivedSizes)
            ..removeWhere((_, v) => v <= 0));
          if (b.purchasePrice > 0) {
            _purchaseCtrl.text = b.purchasePrice.toStringAsFixed(0);
          }
          if (b.sellingPrice > 0) {
            _sellingCtrl.text = b.sellingPrice.toStringAsFixed(0);
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBatch = false);
    }
  }

  List<ProductModel> get _filtered {
    final q = _query.trim();
    if (q.isEmpty) return _all;
    final hits = _all
        .where((p) => SearchHelper.allWordsMatch(
            '${p.name} ${p.brand} ${p.type} ${trValue(p.color)} ${p.color} '
            '${p.variantNote} ${p.articul}',
            q))
        .toList();
    hits.sort((a, b) =>
        SearchHelper.score(b.name, q).compareTo(SearchHelper.score(a.name, q)));
    return hits;
  }

  void _err(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _save() async {
    final p = _selected;
    if (p == null || _saving) return;
    if (_total == 0) {
      return _err(tr('Укажите количество хотя бы для одного размера',
          'Кемінде бір өлшемге сан енгізіңіз'));
    }
    final selling = double.tryParse(_sellingCtrl.text.trim()) ?? 0;
    if (selling <= 0) {
      return _err(tr('Укажите цену продажи', 'Сату бағасын енгізіңіз'));
    }
    setState(() => _saving = true);
    if (!await ensureWarehouseSelected(context)) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    final warehouseId = context.read<WarehouseContext>().current?.id ?? '';
    try {
      await _service.addNewBatchToProduct(
        productId: p.id,
        batch: BatchModel(
          id: '',
          dateArrived: _dateArrived,
          purchasePrice: double.tryParse(_purchaseCtrl.text.trim()) ?? 0,
          sellingPrice: selling,
          sizesQuantity: {..._sizes}..removeWhere((_, v) => v <= 0),
        ),
        dateArrived: _dateArrived,
        warehouseId: warehouseId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Завоз оформлен: +$_total шт. к «${p.name}»',
            'Завоз рәсімделді: «${p.name}» тауарына +$_total дана')),
        backgroundColor: cGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _err(friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: cBg,
        body: Column(children: [
          QGradientHeader(
            title: tr('Повторный завоз', 'Қайта завоз'),
            subtitle: _selected == null
                ? tr('Выберите товар из склада', 'Қоймадан тауарды таңдаңыз')
                : tr('Новая партия существующего товара',
                    'Бар тауардың жаңа партиясы'),
            showBack: true,
            onBack: () {
              // Тауар таңдалған соң «артқа» тізімге қайтарады (экраннан
              // шығып кетпейді) — қате таңдағанда ыңғайлы.
              if (_selected != null && widget.product == null) {
                setState(() => _selected = null);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          Expanded(
            child: _selected == null ? _buildPicker() : _buildForm(_selected!),
          ),
        ]),
      );

  // ── 1-қадам: тауарды тізімнен таңдау ───────────────────────────────────────
  Widget _buildPicker() {
    if (_loadingList) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    final list = _filtered;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cLine),
          ),
          child: Row(children: [
            const SizedBox(width: 12),
            const Icon(Icons.search_rounded, color: cInk3, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: manrope(14.5, FontWeight.w600, color: cInk),
                decoration: InputDecoration(
                  hintText: tr('Название, бренд, артикул…',
                      'Атауы, бренді, артикул…'),
                  hintStyle: manrope(14, FontWeight.w500, color: cInk3),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_query.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: cInk3),
                onPressed: () => setState(() {
                  _searchCtrl.clear();
                  _query = '';
                }),
              ),
          ]),
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                      _all.isEmpty
                          ? tr('На складе пока нет товаров',
                              'Қоймада әзірге тауар жоқ')
                          : tr('Ничего не найдено', 'Ештеңе табылмады'),
                      textAlign: TextAlign.center,
                      style: manrope(14, FontWeight.w600, color: cInk3)),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length,
                itemBuilder: (_, i) => _ProductRow(
                  product: list[i],
                  onTap: () {
                    setState(() => _selected = list[i]);
                    _loadBatch(list[i]);
                  },
                ),
              ),
      ),
    ]);
  }

  // ── 2-қадам: партияны толтыру (алдыңғысынан көшірілген) ───────────────────
  Widget _buildForm(ProductModel p) {
    if (_loadingBatch) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    final last = _lastBatch;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _ProductRow(product: p, selected: true),
            if (widget.product == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.swap_horiz_rounded,
                      size: 17, color: cInk3),
                  label: Text(tr('Другой товар', 'Басқа тауар'),
                      style: manrope(13, FontWeight.w700, color: cInk3)),
                ),
              ),
            const SizedBox(height: 6),

            // ── Размер линиясы ───────────────────────────────────────────
            QSecLabel(tr('Размерная линейка', 'Өлшем линиясы')),
            const SizedBox(height: 8),
            if (last == null)
              _hint(tr('У товара ещё не было партий — заполните размеры сами',
                  'Тауарда әлі партия болмаған — өлшемдерді өзіңіз толтырыңыз'))
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _sameAsLast ? cGreenTint : cAmberTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          _sameAsLast
                              ? Icons.check_circle_rounded
                              : Icons.edit_rounded,
                          color: _sameAsLast ? cGreen : cAmber,
                          size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  _sameAsLast
                                      ? tr('Как в прошлый завоз',
                                          'Алдыңғы завоздағыдай')
                                      : tr('Изменено вручную',
                                          'Қолмен өзгертілді'),
                                  style: manrope(12.5, FontWeight.w800,
                                      color: cInk)),
                              const SizedBox(height: 2),
                              // ⚠️ ЗАВЕЗЕНО, а не остаток: это эталон
                              // «сколько я привожу», он не должен таять
                              // по мере продаж.
                              Text(
                                  '${_fmtDate(last.dateArrived)} · ${tr('завезено', 'әкелінген')}: ${_fmtLine(_lastArrived)}',
                                  style: manrope(11.5, FontWeight.w600,
                                      color: cInk2)),
                              // Қазіргі қалдық — бөлек жол. Екеуі бір санға
                              // қосылып кетпеуі керек.
                              Text(
                                  '${tr('сейчас на складе', 'қазір қоймада')}: ${_fmtLine(last.sizesQuantity)}',
                                  style: manrope(11, FontWeight.w600,
                                      color: cInk3)),
                            ]),
                      ),
                      if (!_sameAsLast)
                        GestureDetector(
                          onTap: () => setState(() {
                            _sizes
                              ..clear()
                              ..addAll(Map<String, int>.from(_lastArrived)
                                ..removeWhere((_, v) => v <= 0));
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: cSurface,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(tr('Вернуть', 'Қайтару'),
                                style: manrope(11.5, FontWeight.w800,
                                    color: cGreenDeep)),
                          ),
                        ),
                    ]),
              ),
            const SizedBox(height: 12),
            ..._sizes.keys.toList().map((s) => _SizeRow(
                  size: s,
                  qty: _sizes[s] ?? 0,
                  onMinus: () => setState(() {
                    final v = (_sizes[s] ?? 0) - 1;
                    if (v <= 0) {
                      _sizes.remove(s);
                    } else {
                      _sizes[s] = v;
                    }
                  }),
                  onPlus: () => setState(() => _sizes[s] = (_sizes[s] ?? 0) + 1),
                  onRemove: () => setState(() => _sizes.remove(s)),
                )),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _promptAddSize,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: cLine, style: BorderStyle.solid),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_rounded, size: 18, color: cGreen),
                  const SizedBox(width: 6),
                  Text(tr('Добавить размер', 'Өлшем қосу'),
                      style: manrope(13.5, FontWeight.w800, color: cGreen)),
                ]),
              ),
            ),
            const SizedBox(height: 18),

            // ── Бағалар ──────────────────────────────────────────────────
            QSecLabel(tr('Цены', 'Бағалар')),
            const SizedBox(height: 8),
            _PriceField(
              controller: _purchaseCtrl,
              label: tr('Закуп за пару', 'Бір жұп үшін өзіндік құн'),
              icon: Icons.payments_outlined,
              previous: last?.purchasePrice ?? 0,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 10),
            _PriceField(
              controller: _sellingCtrl,
              label: tr('Цена продажи *', 'Сату бағасы *'),
              icon: Icons.sell_outlined,
              previous: last?.sellingPrice ?? 0,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 18),

            // ── Келген күні ──────────────────────────────────────────────
            QSecLabel(tr('Дата прихода', 'Келген күні')),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _dateArrived,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (d != null) setState(() => _dateArrived = d);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: cSurface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: cLine),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 17, color: cInk3),
                  const SizedBox(width: 10),
                  Text(_fmtDate(_dateArrived),
                      style: manrope(14, FontWeight.w700, color: cInk)),
                ]),
              ),
            ),
          ],
        ),
      ),
      // ── Қорытынды + сақтау ──────────────────────────────────────────────
      SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          decoration: const BoxDecoration(
            color: cSurface,
            border: Border(top: BorderSide(color: cLine)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text(tr('В партии', 'Партияда'),
                    style: manrope(13, FontWeight.w600, color: cInk2)),
              ),
              Text(tr('$_total шт.', '$_total дана'),
                  style: manrope(19, FontWeight.w800, color: cInk)),
            ]),
            const SizedBox(height: 10),
            QPrimaryButton(
              label: tr('Оформить завоз', 'Завозды рәсімдеу'),
              isLoading: _saving,
              onPressed: (_saving || _total == 0) ? null : _save,
              height: 52,
            ),
          ]),
        ),
      ),
    ]);
  }

  Future<void> _promptAddSize() async {
    final ctrl = TextEditingController();
    final size = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Новый размер', 'Жаңа өлшем'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textAlign: TextAlign.center,
          style: manrope(17, FontWeight.w800, color: cInk),
          decoration: InputDecoration(
            hintText: tr('Напр. 42 или XL', 'Мыс. 42 немесе XL'),
            hintStyle: manrope(15, FontWeight.w600, color: cInk3),
            filled: true,
            fillColor: cBg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: cGreen, foregroundColor: Colors.white),
              child: Text(tr('Добавить', 'Қосу'))),
        ],
      ),
    );
    ctrl.dispose();
    if (size == null || size.isEmpty) return;
    setState(() => _sizes[size] = (_sizes[size] ?? 0) + 1);
  }

  Widget _hint(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(13)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: cInk3),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text,
                style: manrope(12, FontWeight.w600, color: cInk2)),
          ),
        ]),
      );

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// «38-2, 39-1» түріндегі қысқа жазу — админ бір қараған сәтте таниды.
  static String _fmtLine(Map<String, int> sizes) {
    final keys = sizes.keys.where((k) => (sizes[k] ?? 0) > 0).toList()..sort();
    if (keys.isEmpty) return '—';
    return keys.map((k) => '$k-${sizes[k]}').join(', ');
  }
}

// ── Тауар жолы (тізімде де, таңдалғанда да) ───────────────────────────────────
class _ProductRow extends StatelessWidget {
  final ProductModel product;
  final bool selected;
  final VoidCallback? onTap;
  const _ProductRow({
    required this.product,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = product;
    final sub = [
      if (p.brand.isNotEmpty) p.brand,
      if (p.color.isNotEmpty) trValue(p.color),
      if (p.variantNote.isNotEmpty) p.variantNote,
    ].join(' · ');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? cGreen : cLine, width: selected ? 1.5 : 1),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          SizedBox(
            width: 56,
            height: 56,
            child: QShoeImage(
              imageUrl: p.images.isNotEmpty ? p.images.first : null,
              height: 56,
              tone: p.id.hashCode % 5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: manrope(14, FontWeight.w800, color: cInk),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: manrope(12, FontWeight.w600, color: cInk2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  if (p.articul.isNotEmpty)
                    Text(p.articul,
                        style: manrope(11, FontWeight.w600, color: cInk3)),
                ]),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
          if (selected)
            const Icon(Icons.check_circle_rounded, color: cGreen, size: 20),
        ]),
      ),
    );
  }
}

// ── Размер жолы (өлшем + санағыш) ─────────────────────────────────────────────
class _SizeRow extends StatelessWidget {
  final String size;
  final int qty;
  final VoidCallback onMinus, onPlus, onRemove;
  const _SizeRow({
    required this.size,
    required this.qty,
    required this.onMinus,
    required this.onPlus,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: cLine),
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: cGreenTint, borderRadius: BorderRadius.circular(9)),
            child: Text(size,
                style: manrope(14, FontWeight.w800, color: cGreenDeep)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tr('$qty шт.', '$qty дана'),
                style: manrope(13.5, FontWeight.w700, color: cInk)),
          ),
          _Btn(
              icon: qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
              color: qty <= 1 ? cRed : cInk2,
              onTap: qty <= 1 ? onRemove : onMinus),
          const SizedBox(width: 8),
          _Btn(icon: Icons.add_rounded, color: cGreen, onTap: onPlus),
        ]),
      );
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      );
}

// ── Баға өрісі («прошлый раз» хинтімен) ──────────────────────────────────────
class _PriceField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final double previous;
  final VoidCallback onChanged;
  const _PriceField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.previous,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cur = double.tryParse(controller.text.trim()) ?? 0;
    final changed = previous > 0 && cur > 0 && cur != previous;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: changed ? cAmber : cLine),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: cInk3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: manrope(13, FontWeight.w700, color: cInk)),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              onChanged: (_) => onChanged(),
              style: manrope(15, FontWeight.w800, color: cInk),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: manrope(15, FontWeight.w600, color: cInk3),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text('₸', style: manrope(13, FontWeight.w700, color: cInk3)),
        ]),
      ),
      if (previous > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            changed
                ? tr('В прошлый раз было ${money(previous)} — изменено',
                    'Алдыңғы жолы ${money(previous)} болған — өзгертілді')
                : tr('Как в прошлый завоз: ${money(previous)}',
                    'Алдыңғы завоздағыдай: ${money(previous)}'),
            style: manrope(11, FontWeight.w600,
                color: changed ? cAmber : cInk3),
          ),
        ),
    ]);
  }
}
