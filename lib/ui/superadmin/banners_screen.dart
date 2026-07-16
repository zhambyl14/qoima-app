import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/banner_model.dart';
import '../../data/repositories/banner_repository.dart';
import '../../theme/qoima_design.dart';

import '../../core/lang.dart';
/// Superadmin — управление промо-баннерами клиентской главной.
/// Список с переключателем active, добавление/редактирование/удаление.
class BannersScreen extends StatelessWidget {
  const BannersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = BannerRepository();
    return Scaffold(
      backgroundColor: cBg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cGreen,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(context, repo, null),
        icon: const Icon(Icons.add_rounded),
        label: Text('Баннер', style: manrope(14.5, FontWeight.w700,
            color: Colors.white)),
      ),
      body: Column(children: [
        QGradientHeader(
          title: tr('Баннеры', 'Баннерлер'),
          subtitle: tr('Промо на главной', 'Басты беттегі промо'),
          showBack: true,
          compact: true,
        ),
        Expanded(
          child: StreamBuilder<List<BannerModel>>(
            stream: repo.watchAllBanners(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: cGreen, strokeWidth: 2));
              }
              final banners = snap.data ?? [];
              if (banners.isEmpty) return _empty();
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: banners.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _BannerRow(
                  banner: banners[i],
                  onTap: () => _openEditor(context, repo, banners[i]),
                  onToggle: (v) => repo.setActive(banners[i].id, v),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _empty() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration:
                const BoxDecoration(color: cGreenTint, shape: BoxShape.circle),
            child: const Icon(Icons.photo_library_outlined,
                color: cGreen, size: 34),
          ),
          const SizedBox(height: 14),
          Text(tr('Баннеров нет', 'Баннерлер жоқ'),
              style: manrope(16, FontWeight.w700, color: cInk)),
          const SizedBox(height: 4),
          Text(tr('Добавьте кнопкой «Баннер»', '«Баннер» батырмасымен қосыңыз'),
              style: manrope(13, FontWeight.w500, color: cInk3)),
        ]),
      );

  void _openEditor(
      BuildContext context, BannerRepository repo, BannerModel? banner) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BannerEditSheet(repo: repo, banner: banner),
    );
  }
}

// ── Banner row ───────────────────────────────────────────────────────────────
class _BannerRow extends StatelessWidget {
  final BannerModel banner;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  const _BannerRow(
      {required this.banner, required this.onTap, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cLine),
          boxShadow: kShadowSm,
        ),
        child: Row(children: [
          // Gradient preview swatch
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [banner.startColor, banner.endColor],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: banner.badge.isEmpty
                ? null
                : Center(
                    child: Text(banner.badge,
                        style: manrope(10, FontWeight.w800,
                            color: Colors.white))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          banner.title.isEmpty ? tr('(без названия)', '(атаусыз)') : banner.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              manrope(14.5, FontWeight.w800, color: cInk)),
                    ),
                    const SizedBox(width: 6),
                    QPill('#${banner.order}', tone: 'gray'),
                  ]),
                  if (banner.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(banner.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            manrope(12.5, FontWeight.w500, color: cInk3)),
                  ],
                ]),
          ),
          Switch(
            value: banner.active,
            onChanged: onToggle,
            activeThumbColor: Colors.white,
            activeTrackColor: cGreen,
          ),
        ]),
      ),
    );
  }
}

// ── Add / Edit bottom sheet ──────────────────────────────────────────────────
class _BannerEditSheet extends StatefulWidget {
  final BannerRepository repo;
  final BannerModel? banner; // null = создание
  const _BannerEditSheet({required this.repo, this.banner});

  @override
  State<_BannerEditSheet> createState() => _BannerEditSheetState();
}

class _BannerEditSheetState extends State<_BannerEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _badge;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _order;
  late bool _active;
  bool _saving = false;

  // Баннер сілтейтін дүкен ('' = сілтеме жоқ) + таңдау тізімі.
  late String _storeUid;
  late String _storeName;
  List<({String uid, String name})> _stores = [];

  bool get _isNew => widget.banner == null;

  @override
  void initState() {
    super.initState();
    final b = widget.banner;
    _title = TextEditingController(text: b?.title ?? '');
    _subtitle = TextEditingController(text: b?.subtitle ?? '');
    _badge = TextEditingController(text: b?.badge ?? '');
    _start = TextEditingController(text: b?.gradientStart ?? '#00713F');
    _end = TextEditingController(text: b?.gradientEnd ?? '#12C97A');
    _order = TextEditingController(text: (b?.order ?? 0).toString());
    _active = b?.active ?? true;
    _storeUid = b?.storeAdminUid ?? '';
    _storeName = b?.storeName ?? '';
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      final rows = await Supabase.instance.client
          .from('stores')
          .select('admin_uid,store_name')
          .eq('is_published', true)
          .order('store_name');
      if (!mounted) return;
      setState(() => _stores = rows
          .map((r) => (
                uid: r['admin_uid'] as String? ?? '',
                name: r['store_name'] as String? ?? '',
              ))
          .toList());
    } catch (_) {}
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _badge.dispose();
    _start.dispose();
    _end.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      _snack(tr('Заголовок не должен быть пустым', 'Тақырып бос болмауы керек'), cRed);
      return;
    }
    setState(() => _saving = true);
    final base = widget.banner;
    final banner = BannerModel(
      id: base?.id ?? '',
      title: _title.text.trim(),
      subtitle: _subtitle.text.trim(),
      badge: _badge.text.trim(),
      gradientStart: _start.text.trim(),
      gradientEnd: _end.text.trim(),
      order: int.tryParse(_order.text.trim()) ?? 0,
      active: _active,
      startsAt: base?.startsAt,
      endsAt: base?.endsAt,
      storeAdminUid: _storeUid,
      storeName: _storeName,
    );
    try {
      await widget.repo.saveBanner(banner);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack(e.toString(), cRed);
      }
    }
  }

  Future<void> _delete() async {
    final b = widget.banner;
    if (b == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Удалить баннер', 'Баннерді жою'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(tr('Удалить баннер «${b.title}»?', '«${b.title}» баннерін жоясыз ба?'),
            style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text(tr('Нет', 'Жоқ'), style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text(tr('Удалить', 'Жою'), style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.deleteBanner(b.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack(e.toString(), cRed);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Баннер сілтейтін дүкенді таңдау («Без ссылки» + жарияланған дүкендер).
  Future<void> _pickStore() async {
    final picked = await showModalBottomSheet<({String uid, String name})>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: cLine, borderRadius: BorderRadius.circular(2)),
          ),
          Text(tr('Магазин для баннера', 'Баннер дүкені'),
              style: manrope(17, FontWeight.w800, color: cInk)),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.link_off_rounded, color: cInk3),
                  title: Text(tr('Без ссылки', 'Сілтемесіз'),
                      style: manrope(14.5, FontWeight.w600, color: cInk)),
                  onTap: () => Navigator.pop(ctx, (uid: '', name: '')),
                ),
                ..._stores.map((s) => ListTile(
                      leading: const Icon(Icons.storefront_rounded,
                          color: cGreen),
                      title: Text(s.name,
                          style:
                              manrope(14.5, FontWeight.w600, color: cInk)),
                      trailing: s.uid == _storeUid
                          ? const Icon(Icons.check_rounded, color: cGreen)
                          : null,
                      onTap: () => Navigator.pop(ctx, s),
                    )),
              ],
            ),
          ),
        ]),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _storeUid = picked.uid;
        _storeName = picked.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final startColor = BannerModel.hexColor(_start.text);
    final endColor = BannerModel.hexColor(_end.text);

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, ctrl) => ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: cLine, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(_isNew ? tr('Новый баннер', 'Жаңа баннер') : tr('Редактировать баннер', 'Баннерді өңдеу'),
                  style: manrope(18, FontWeight.w800, color: cInk)),
              const SizedBox(height: 16),

              // Live preview
              Container(
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [startColor, endColor],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_badge.text.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(_badge.text.trim(),
                            style: manrope(10.5, FontWeight.w800,
                                color: Colors.white)),
                      ),
                    if (_badge.text.trim().isNotEmpty)
                      const SizedBox(height: 6),
                    Text(
                        _title.text.trim().isEmpty
                            ? tr('Заголовок', 'Тақырып')
                            : _title.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(17, FontWeight.w800,
                            color: Colors.white, letterSpacing: -0.3)),
                    if (_subtitle.text.trim().isNotEmpty)
                      Text(_subtitle.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: manrope(12.5, FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              _field(tr('Заголовок', 'Тақырып'), _title, hint: tr('Мега Скидка!', 'Мега Жеңілдік!')),
              _field(tr('Описание', 'Сипаттама'), _subtitle,
                  hint: tr('До 30% на все товары', 'Барлық тауарларға 30% дейін')),
              _field(tr('Метка (badge)', 'Белгі (badge)'), _badge, hint: '🔥 11.11'),
              _hexField(tr('Начало градиента', 'Градиент басы'), _start, startColor),
              _hexField(tr('Конец градиента', 'Градиент соңы'), _end, endColor),
              _field(tr('Порядок (order)', 'Реті (order)'), _order,
                  hint: '0', keyboardType: TextInputType.number),

              // ── Дүкен сілтемесі: клиент баннерді басқанда осы дүкен ашылады
              Text(tr('Магазин (при нажатии на баннер)', 'Дүкен (баннерді басқанда)'),
                  style: manrope(12.5, FontWeight.w700, color: cInk2)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickStore,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: cBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(
                        _storeUid.isEmpty
                            ? Icons.link_off_rounded
                            : Icons.storefront_rounded,
                        size: 18,
                        color: _storeUid.isEmpty ? cInk3 : cGreen),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          _storeUid.isEmpty
                              ? tr('Без ссылки (просто баннер)',
                                  'Сілтемесіз (жай баннер)')
                              : _storeName,
                          style: manrope(14, FontWeight.w600,
                              color: _storeUid.isEmpty ? cInk3 : cInk)),
                    ),
                    const Icon(Icons.expand_more_rounded,
                        color: cInk3, size: 20),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 6),

              // Active toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: cBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(tr('Активен (показывать)', 'Белсенді (көрсету)'),
                        style: manrope(14, FontWeight.w700, color: cInk)),
                  ),
                  Switch(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                    activeThumbColor: Colors.white,
                    activeTrackColor: cGreen,
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              QPrimaryButton(
                label: tr('Сохранить', 'Сақтау'),
                isLoading: _saving,
                onPressed: _save,
              ),
              if (!_isNew) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cRed,
                      side: const BorderSide(color: cRed),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(tr('Удалить баннер', 'Баннерді жою'),
                        style: manrope(14, FontWeight.w700, color: cRed)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String? hint, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: manrope(12.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          onChanged: (_) => setState(() {}), // live preview
          style: manrope(14.5, FontWeight.w600, color: cInk),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: manrope(14, FontWeight.w500, color: cInk3),
            filled: true,
            fillColor: cBg,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
      ]),
    );
  }

  Widget _hexField(String label, TextEditingController ctrl, Color preview) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: manrope(12.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              ],
              onChanged: (_) => setState(() {}),
              style: manrope(14.5, FontWeight.w600, color: cInk),
              decoration: InputDecoration(
                hintText: '#C62828',
                hintStyle: manrope(14, FontWeight.w500, color: cInk3),
                filled: true,
                fillColor: cBg,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Басқанда цветовой палитра ашылады — hex кодты білудің қажеті жоқ.
          GestureDetector(
            onTap: () => _pickColor(ctrl),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: preview,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cLine),
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.palette_outlined,
                      size: 12, color: cInk2),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  // Цветовой палитрадан түс таңдау → hex өрісіне жазылады.
  Future<void> _pickColor(TextEditingController ctrl) async {
    final picked = await showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColorPickerSheet(initial: BannerModel.hexColor(ctrl.text)),
    );
    if (picked != null && mounted) {
      ctrl.text = _colorToHex(picked);
      setState(() {}); // live preview жаңарту
    }
  }

  String _colorToHex(Color c) {
    String ch(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${ch(c.r)}${ch(c.g)}${ch(c.b)}'.toUpperCase();
  }
}

// ── Толық түс палитрасы (HSV): кез келген түсті таңдау ────────────────────────
// Жоғарыда S/V алаңы (қанықтық × жарықтық), астында Hue жолағы, жылдам
// пресеттер және hex көрсеткіші. Ешқандай сыртқы пакет қолданылмайды.
class _ColorPickerSheet extends StatefulWidget {
  final Color initial;
  const _ColorPickerSheet({required this.initial});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  String get _hex {
    String ch(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final c = _color;
    return '#${ch(c.r)}${ch(c.g)}${ch(c.b)}'.toUpperCase();
  }

  // Жылдам пресеттер — жиі қолданылатын брендтік реңктер.
  static final List<Color> _quick = [
    const Color(0xFF00713F), const Color(0xFF12C97A),
    const Color(0xFF1A5BD0), const Color(0xFF5A3DD0),
    const Color(0xFFB11A2B), const Color(0xFFE8590C),
    const Color(0xFFC2255C), const Color(0xFF9A6A06),
    const Color(0xFF0C120F), const Color(0xFF3C4D45),
  ];

  void _setSv(Offset local, Size size) {
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1 - (local.dy / size.height).clamp(0.0, 1.0);
    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
  }

  void _setHue(Offset local, double width) {
    final h = (local.dx / width).clamp(0.0, 1.0) * 360;
    setState(() => _hsv = _hsv.withHue(h.clamp(0, 359.9)));
  }

  @override
  Widget build(BuildContext context) {
    final hueColor =
        HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(); // таза тон
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        Row(children: [
          Expanded(
            child: Text(tr('Выбор цвета', 'Түс таңдау'),
                style: manrope(17, FontWeight.w800, color: cInk)),
          ),
          // Ағымдағы түс + hex
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: cLine),
                ),
              ),
              const SizedBox(width: 8),
              Text(_hex,
                  style: manrope(12.5, FontWeight.w800, color: cInk)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),

        // ── S/V алаңы: солдан оңға қанықтық, жоғарыдан төмен жарықтық ────
        LayoutBuilder(builder: (ctx, constraints) {
          final size = Size(constraints.maxWidth, 180.0);
          return GestureDetector(
            onPanDown: (d) => _setSv(d.localPosition, size),
            onPanUpdate: (d) => _setSv(d.localPosition, size),
            child: Container(
              width: size.width,
              height: size.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cLine),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(children: [
                // ақ → таза тон (қанықтық)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.white, hueColor]),
                  ),
                  child: const SizedBox.expand(),
                ),
                // мөлдір → қара (жарықтық)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
                // Нүсқағыш
                Positioned(
                  left: (_hsv.saturation * size.width - 10)
                      .clamp(0.0, size.width - 20),
                  top: ((1 - _hsv.value) * size.height - 10)
                      .clamp(0.0, size.height - 20),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 14),

        // ── Hue жолағы (кемпірқосақ) ─────────────────────────────────────
        LayoutBuilder(builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          return GestureDetector(
            onPanDown: (d) => _setHue(d.localPosition, w),
            onPanUpdate: (d) => _setHue(d.localPosition, w),
            child: SizedBox(
              height: 34,
              child: Stack(children: [
                Positioned.fill(
                  top: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: LinearGradient(colors: [
                        for (var h = 0; h <= 360; h += 30)
                          HSVColor.fromAHSV(1, h % 360.0, 1, 1).toColor(),
                      ]),
                    ),
                  ),
                ),
                Positioned(
                  left: (_hsv.hue / 360 * w - 11).clamp(0.0, w - 22),
                  top: 0,
                  child: Container(
                    width: 22,
                    height: 34,
                    decoration: BoxDecoration(
                      color: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 14),

        // ── Жылдам пресеттер ─────────────────────────────────────────────
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _quick
                .map((c) => GestureDetector(
                      onTap: () =>
                          setState(() => _hsv = HSVColor.fromColor(c)),
                      child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cLine),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        QPrimaryButton(
          label: tr('Выбрать этот цвет', 'Осы түсті таңдау'),
          onPressed: () => Navigator.pop(context, _color),
          height: 50,
        ),
      ]),
    );
  }
}
