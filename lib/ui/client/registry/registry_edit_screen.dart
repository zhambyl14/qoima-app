import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_user.dart';
import '../../../core/feature_flags.dart';
import '../../../core/error_text.dart';
import '../../../core/lang.dart';
import '../../../data/models/registry_model.dart';
import '../../../data/services/registry_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/error_view.dart';
import 'registry_share.dart';
import 'registry_widgets.dart';

/// Тізімді жасау / өңдеу. [registry] null болса — жаңа тізім; сақтаған соң
/// экран өңдеу режиміне ауысады (тауар қосу, бөлісу).
class RegistryEditScreen extends StatefulWidget {
  final GiftRegistry? registry;
  const RegistryEditScreen({super.key, this.registry});

  @override
  State<RegistryEditScreen> createState() => _RegistryEditScreenState();
}

class _RegistryEditScreenState extends State<RegistryEditScreen> {
  final _service = RegistryService();
  final _title = TextEditingController();
  final _message = TextEditingController();
  final _city = TextEditingController();

  GiftRegistry? _reg;
  String _occasion = 'birthday';
  DateTime? _date;
  bool _saving = false;

  PublicRegistry? _pub;
  bool _pubLoading = false;
  Object? _pubError;

  @override
  void initState() {
    super.initState();
    _reg = widget.registry;
    final r = _reg;
    if (r != null) {
      _title.text = r.title;
      _message.text = r.message;
      _city.text = r.city;
      _occasion = r.occasion;
      _date = r.eventDate;
      _loadItems();
    } else {
      // Қала әдепкіде — профильдегі қала.
      _city.text = context.read<AppUser>().city;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    _city.dispose();
    super.dispose();
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

  Future<void> _loadItems() async {
    final r = _reg;
    if (r == null) return;
    setState(() {
      _pubLoading = true;
      _pubError = null;
    });
    try {
      final p = await _service.getPublic(r.shareToken);
      if (!mounted) return;
      setState(() {
        _pub = p;
        _pubLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pubError = e;
        _pubLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Өтіп кеткен күні бар тізімді өңдегенде initialDate < firstDate болып,
    // showDatePicker assert-пен құламауы үшін firstDate-ті соған түсіреміз.
    final cur =
        _date == null ? null : DateTime(_date!.year, _date!.month, _date!.day);
    final first = (cur != null && cur.isBefore(today)) ? cur : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: cur ?? now.add(const Duration(days: 30)),
      firstDate: first,
      lastDate: DateTime(now.year + 3, now.month, now.day),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: cGreen)),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast(tr('Введите название списка', 'Тізім атауын енгізіңіз'),
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final r = _reg;
      if (r == null) {
        final created = await _service.createRegistry(
          title: title,
          occasion: _occasion,
          eventDate: _date,
          message: _message.text,
          city: _city.text,
        );
        if (!mounted) return;
        setState(() => _reg = created);
        _toast(tr('Список создан — добавьте товары и поделитесь ссылкой',
            'Тізім жасалды — тауар қосып, сілтемені бөлісіңіз'));
        _loadItems();
      } else {
        await _service.updateRegistry(
          r.id,
          title: title,
          occasion: _occasion,
          eventDate: _date,
          message: _message.text,
          city: _city.text,
        );
        if (!mounted) return;
        // Жергілікті _reg жаңартылады: бөлісу мәтіні мен тақырып ескі атауды
        // көрсетпеуі үшін.
        setState(() => _reg = GiftRegistry(
              id: r.id,
              ownerUid: r.ownerUid,
              title: title,
              occasion: _occasion,
              eventDate: _date,
              message: _message.text.trim(),
              city: _city.text.trim(),
              shareToken: r.shareToken,
              isActive: r.isActive,
              createdAt: r.createdAt,
            ));
        _toast(tr('Сохранено', 'Сақталды'));
      }
    } catch (e) {
      if (mounted) _toast(registryErrorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(bool v) async {
    final r = _reg;
    if (r == null) return;
    try {
      // Тек жалау жіберіледі: сақталмаған/ескі өрістер DB-ға қайта жазылмайды.
      await _service.setActive(r.id, v);
      if (!mounted) return;
      setState(() => _reg = GiftRegistry(
            id: r.id,
            ownerUid: r.ownerUid,
            title: r.title,
            occasion: r.occasion,
            eventDate: r.eventDate,
            message: r.message,
            city: r.city,
            shareToken: r.shareToken,
            isActive: v,
            createdAt: r.createdAt,
          ));
    } catch (e) {
      if (mounted) _toast(registryErrorText(e), error: true);
    }
  }

  Future<bool> _confirm(String title, String body, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(body, style: manrope(14, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  Text(yes, style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteRegistry() async {
    final r = _reg;
    if (r == null) return;
    final ok = await _confirm(
      tr('Удалить список?', 'Тізімді жою керек пе?'),
      tr('Список и все брони гостей будут удалены. Это нельзя отменить.',
          'Тізім мен қонақтардың барлық брондары жойылады. Қайтару мүмкін емес.'),
      tr('Удалить', 'Жою'),
    );
    if (!ok) return;
    try {
      await _service.deleteRegistry(r.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast(registryErrorText(e), error: true);
    }
  }

  Future<void> _removeItem(RegistryItem it) async {
    final taken = it.qtyTaken > 0;
    final ok = await _confirm(
      tr('Убрать из списка?', 'Тізімнен алып тастау керек пе?'),
      taken
          ? tr('Этот подарок уже выбран гостем — он потеряет бронь.',
              'Бұл сыйлықты қонақ таңдап қойған — оның брондары жойылады.')
          : it.productName,
      tr('Убрать', 'Алып тастау'),
    );
    if (!ok) return;
    try {
      await _service.removeItem(it.id);
      _loadItems();
    } catch (e) {
      if (mounted) _toast(registryErrorText(e), error: true);
    }
  }

  Future<void> _changeQty(RegistryItem it, int qty) async {
    try {
      await _service.updateItem(it.id, qtyWanted: qty);
      _loadItems();
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
        QGradientHeader(
          title: r == null
              ? tr('Новый список', 'Жаңа тізім')
              : tr('Мой список', 'Менің тізімім'),
          subtitle: r == null
              ? tr('Для праздника', 'Мерекеге арналған')
              : RegistryOccasion.withEmoji(r.occasion),
          showBack: true,
          action: r == null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Builder(
                    builder: (ctx) => QHeaderBtn(
                      Icons.ios_share_rounded,
                      onTap: () => shareRegistryLink(ctx,
                          title: r.title,
                          occasion: r.occasion,
                          token: r.shareToken),
                    ),
                  ),
                  const SizedBox(width: 8),
                  QHeaderBtn(Icons.delete_outline_rounded,
                      onTap: _deleteRegistry),
                ]),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _form(),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: FeatureFlags.instance,
                builder: (context, _) {
                  final on =
                      FeatureFlags.instance.isOn(FeatureFlags.giftRegistry);
                  // Жаңа тізім жасау өшік болса — түсіндірме; ескі тізімді
                  // өзгерту/бөлісу жұмыс істей береді.
                  if (!on && r == null) {
                    return Text(
                        comingSoonText(),
                        textAlign: TextAlign.center,
                        style: manrope(13, FontWeight.w600, color: cInk2));
                  }
                  return QPrimaryButton(
                    label: r == null
                        ? tr('Создать список', 'Тізімді жасау')
                        : tr('Сохранить', 'Сақтау'),
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  );
                },
              ),
              if (r != null) ...[
                const SizedBox(height: 22),
                _itemsSection(r),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: manrope(13, FontWeight.w600, color: cInk3),
        filled: true,
        fillColor: cSurface,
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kR14),
            borderSide: const BorderSide(color: cLine)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kR14),
            borderSide: const BorderSide(color: cLine)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kR14),
            borderSide: const BorderSide(color: cGreen, width: 1.5)),
      );

  Widget _form() {
    return QCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _title,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          style: manrope(15, FontWeight.w600, color: cInk),
          decoration: _dec(tr('Название', 'Атауы'),
              hint: tr('Например: Свадьба Айдара и Асем',
                  'Мысалы: Айдар мен Әселдің тойы')),
        ),
        const SizedBox(height: 14),
        Text(tr('Повод', 'Мереке түрі'),
            style: manrope(12.5, FontWeight.w700, color: cInk3)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in RegistryOccasion.keys)
            RegistryOccasionChip(
              label: RegistryOccasion.withEmoji(k),
              selected: _occasion == k,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _occasion = k);
              },
            ),
        ]),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(kR14),
          onTap: _pickDate,
          child: InputDecorator(
            decoration: _dec(tr('Дата праздника', 'Мереке күні')),
            child: Row(children: [
              const Icon(Icons.event_rounded, size: 18, color: cGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    _date == null
                        ? tr('Не выбрана', 'Таңдалмаған')
                        : '${registryDateText(_date)}  ·  ${registryCountdownText(_date)}',
                    style: manrope(14.5, FontWeight.w600,
                        color: _date == null ? cInk3 : cInk)),
              ),
              if (_date != null)
                GestureDetector(
                  onTap: () => setState(() => _date = null),
                  child:
                      const Icon(Icons.close_rounded, size: 18, color: cInk3),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _city,
          maxLength: 80,
          style: manrope(15, FontWeight.w600, color: cInk),
          decoration: _dec(tr('Город', 'Қала')),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _message,
          maxLength: 500,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: manrope(14.5, FontWeight.w500, color: cInk),
          decoration: _dec(tr('Сообщение гостям', 'Қонақтарға хабарлама'),
              hint: tr('Будем рады вашему вниманию!',
                  'Қатысқандарыңызға қуаныштымыз!')),
        ),
      ]),
    );
  }

  Widget _itemsSection(GiftRegistry r) {
    final pub = _pub;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      QSecLabel(tr('Товары в списке', 'Тізімдегі тауарлар')),
      if (_pubLoading && pub == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
              child: CircularProgressIndicator(color: cGreen, strokeWidth: 2)),
        )
      else if (_pubError != null && pub == null)
        AppErrorView(error: _pubError, compact: true, onRetry: _loadItems)
      else if (pub == null || pub.items.isEmpty)
        const _AddHint()
      else ...[
        for (final it in pub.items) ...[
          _ItemRow(
            item: it,
            onRemove: () => _removeItem(it),
            onQty: (q) => _changeQty(it, q),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        const _AddHint(),
      ],
      const SizedBox(height: 18),
      Builder(
        builder: (ctx) => QSoftButton(
          label: tr('Поделиться ссылкой', 'Сілтемені бөлісу'),
          icon: const Icon(Icons.ios_share_rounded, color: cGreen, size: 18),
          onPressed: () => shareRegistryLink(ctx,
              title: r.title, occasion: r.occasion, token: r.shareToken),
        ),
      ),
      const SizedBox(height: 14),
      QCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: cGreen,
          title: Text(tr('Список открыт для гостей', 'Тізім қонақтарға ашық'),
              style: manrope(14, FontWeight.w700, color: cInk)),
          subtitle: Text(
              tr('Если выключить, по ссылке никто не увидит список',
                  'Өшірсеңіз, сілтеме бойынша ешкім тізімді көрмейді'),
              style: manrope(12, FontWeight.w500, color: cInk3)),
          value: r.isActive,
          onChanged: _toggleActive,
        ),
      ),
    ]);
  }
}

class _AddHint extends StatelessWidget {
  const _AddHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cGreenTint,
        borderRadius: BorderRadius.circular(kR16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.lightbulb_outline_rounded, color: cGreen, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              tr('Откройте любой товар и нажмите «В список желаний» — он появится здесь.',
                  'Кез келген тауарды ашып, «Тілек тізіміне қосу» батырмасын басыңыз — ол осында пайда болады.'),
              style: manrope(13, FontWeight.w600,
                  color: cGreenDeep, height: 1.35)),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final RegistryItem item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQty;
  const _ItemRow(
      {required this.item, required this.onRemove, required this.onQty});

  @override
  Widget build(BuildContext context) {
    final it = item;
    final st = it.state;
    final (label, tone) = switch (st) {
      RegistryItemState.free => (tr('Свободен', 'Бос'), 'green'),
      RegistryItemState.reserved => (tr('Забронирован', 'Брондалған'), 'amber'),
      RegistryItemState.purchased => (tr('Куплен', 'Сатып алынды'), 'blue'),
    };
    return QCard(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kR12),
          child: SizedBox(
            width: 64,
            height: 64,
            child: QShoeImage(imageUrl: it.imageUrl, height: 64),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: manrope(13.5, FontWeight.w700, color: cInk)),
            const SizedBox(height: 3),
            Text(
              [
                if (it.size.isNotEmpty) it.size,
                if (it.price > 0) money(it.price),
              ].join(' · '),
              style: manrope(12, FontWeight.w600, color: cInk3),
            ),
            const SizedBox(height: 6),
            Row(children: [
              QPill(label, tone: tone),
              const SizedBox(width: 8),
              _Stepper(
                value: it.qtyWanted,
                min: it.qtyTaken > 1 ? it.qtyTaken : 1,
                onChanged: onQty,
              ),
            ]),
          ]),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, color: cInk3, size: 20),
          tooltip: tr('Убрать', 'Алып тастау'),
        ),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int value;
  final int min;
  final ValueChanged<int> onChanged;
  const _Stepper(
      {required this.value, required this.min, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool enabled, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(kRPill),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 18, color: enabled ? cGreen : cLine),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove_circle_outline_rounded, value > min,
          () => onChanged(value - 1)),
      Text('×$value', style: manrope(13, FontWeight.w800, color: cInk)),
      btn(Icons.add_circle_outline_rounded, value < 20,
          () => onChanged(value + 1)),
    ]);
  }
}
