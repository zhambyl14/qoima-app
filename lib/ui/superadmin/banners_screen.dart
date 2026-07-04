import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// ── Цветовой палитра (hex кодсыз визуалды таңдау) ────────────────────────────
class _ColorPickerSheet extends StatelessWidget {
  final Color initial;
  const _ColorPickerSheet({required this.initial});

  static List<Color> get _palette {
    final out = <Color>[];
    // Сұр реңктер: ақтан қараға
    for (var i = 0; i <= 5; i++) {
      out.add(Color.lerp(Colors.white, Colors.black, i / 5)!);
    }
    // Спектр: 12 тон × 3 жарықтық
    for (var h = 0; h < 360; h += 30) {
      for (final v in [1.0, 0.78, 0.55]) {
        out.add(HSVColor.fromAHSV(1, h.toDouble(), 0.82, v).toColor());
      }
    }
    return out;
  }

  bool _same(Color a, Color b) =>
      (a.r - b.r).abs() < 0.02 &&
      (a.g - b.g).abs() < 0.02 &&
      (a.b - b.b).abs() < 0.02;

  @override
  Widget build(BuildContext context) {
    final colors = _palette;
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
          margin: const EdgeInsets.only(bottom: 16),
          decoration:
              BoxDecoration(color: cLine, borderRadius: BorderRadius.circular(2)),
        ),
        Text(tr('Выбор цвета', 'Түс таңдау'), style: manrope(17, FontWeight.w800, color: cInk)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: colors.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemBuilder: (_, i) {
            final c = colors[i];
            final sel = _same(c, initial);
            final isLight = c.computeLuminance() > 0.8;
            return GestureDetector(
              onTap: () => Navigator.pop(context, c),
              child: Container(
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: sel ? cInk : (isLight ? cLine : Colors.transparent),
                    width: sel ? 2.5 : 1,
                  ),
                ),
                child: sel
                    ? Icon(Icons.check_rounded,
                        size: 18, color: isLight ? cInk : Colors.white)
                    : null,
              ),
            );
          },
        ),
      ]),
    );
  }
}
