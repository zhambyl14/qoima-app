import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/app_user.dart';
import '../../../core/feature_flags.dart';
import '../../../core/error_text.dart';
import '../../../core/lang.dart';
import '../../../data/models/batch_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/registry_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/client_service.dart';
import '../../../data/services/registry_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/require_login.dart';
import 'registry_widgets.dart';

/// Тауар бетінен «Тілек тізіміне қосу» парағы.
///
/// Тізім таңдалады немесе тікелей осы жерде жаңасы жасалады; өлшем міндетті
/// емес («кез келген өлшем» — қонақ өзі таңдайды). [size] берілсе — алдын ала
/// таңдалады.
Future<void> showAddToRegistrySheet(
  BuildContext context, {
  required ProductModel product,
  required StoreModel store,
  String? size,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String msg, {bool error = false}) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? cRed : cGreen,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // Сервер де тексереді (feature_disabled); мұнда тек қолданушыға түсінікті жауап.
  if (!FeatureFlags.instance.isOn(FeatureFlags.giftRegistry)) {
    toast(comingSoonText());
    return;
  }
  final ok = await requireLogin(
    context,
    reasonRu: 'Войдите в аккаунт, чтобы добавлять товары в список желаний',
    reasonKk: 'Тілек тізіміне тауар қосу үшін аккаунтқа кіріңіз',
  );
  if (!ok || !context.mounted) return;

  List<GiftRegistry> mine;
  try {
    mine = await RegistryService().getMyRegistries();
  } catch (e) {
    toast(registryErrorText(e), error: true);
    return;
  }
  if (!context.mounted) return;

  final added = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: cSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _AddSheet(
      product: product,
      store: store,
      initialSize: size,
      registries: mine,
    ),
  );
  if (added != null) {
    HapticFeedback.lightImpact();
    toast(tr('Добавлено в список «$added»', 'Тізімге қосылды: «$added»'));
  }
}

class _AddSheet extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;
  final String? initialSize;
  final List<GiftRegistry> registries;
  const _AddSheet({
    required this.product,
    required this.store,
    required this.initialSize,
    required this.registries,
  });

  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _service = RegistryService();
  final _newTitle = TextEditingController();
  final _note = TextEditingController();

  late List<GiftRegistry> _registries;
  String? _registryId; // null = жаңа тізім жасау
  String _occasion = 'birthday';
  String _size = '';
  int _qty = 1;
  List<String> _sizes = const [];
  double _price = 0;
  bool _sizesLoading = true;
  bool _saving = false;
  String? _error;

  bool get _creating => _registryId == null;

  @override
  void initState() {
    super.initState();
    _registries = widget.registries;
    _registryId = _registries.isNotEmpty ? _registries.first.id : null;
    _size = widget.initialSize ?? '';
    _loadSizes();
  }

  @override
  void dispose() {
    _newTitle.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Барлық партиялардағы өлшемдер (таусылғанын да қосқанда — тілек тізімі
  /// болашаққа арналған) және көрсетілім бағасы.
  Future<void> _loadSizes() async {
    try {
      final batches = await ClientService().getProductBatches(
        widget.store.adminUid,
        widget.product.id,
        widget.store.visibleWarehouseIds,
        onlyAvailable: false,
      );
      final set = <String>{};
      for (final b in batches) {
        set.addAll(b.sizesQuantity.keys);
      }
      final list = set.toList()
        ..sort((a, b) {
          final na = num.tryParse(a), nb = num.tryParse(b);
          if (na != null && nb != null) return na.compareTo(nb);
          return a.compareTo(b);
        });
      BatchModel? priceBatch;
      for (final b in batches) {
        if (!b.isEffectivelySoldOut) {
          priceBatch = b;
          break;
        }
      }
      priceBatch ??= batches.isNotEmpty ? batches.first : null;
      if (!mounted) return;
      setState(() {
        _sizes = list;
        _price = priceBatch == null ? 0 : effectivePrice(priceBatch);
        if (_size.isNotEmpty && !list.contains(_size)) _size = '';
        _sizesLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _sizesLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final p = widget.product;
    String registryId;
    String registryTitle;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_creating) {
        final title = _newTitle.text.trim();
        if (title.isEmpty) {
          setState(() {
            _saving = false;
            _error = tr('Введите название списка', 'Тізім атауын енгізіңіз');
          });
          return;
        }
        final created = await _service.createRegistry(
          title: title,
          occasion: _occasion,
          city: context.read<AppUser>().city,
        );
        registryId = created.id;
        registryTitle = created.title;
        // addItem сәтсіз болса, қайталағанда екінші тізім жасалмауы үшін
        // жаңа тізімді таңдалған күйге көшіреміз.
        _registries = [created, ..._registries];
        _registryId = created.id;
      } else {
        final r = _registries.firstWhere((e) => e.id == _registryId);
        registryId = r.id;
        registryTitle = r.title;
      }
      await _service.addItem(
        registryId: registryId,
        productId: p.id,
        adminUid: widget.store.adminUid,
        productName: p.name,
        imageUrl: p.images.isNotEmpty ? p.images.first : '',
        price: _price,
        size: _size,
        qty: _qty,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, registryTitle);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = registryErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: cLine, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(tr('В список желаний', 'Тілек тізіміне қосу'),
                style: manrope(18, FontWeight.w800, color: cInk)),
            const SizedBox(height: 12),
            Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(kR12),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: QShoeImage(
                      imageUrl: p.images.isNotEmpty ? p.images.first : null,
                      height: 56),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: manrope(14, FontWeight.w700, color: cInk)),
              ),
            ]),
            const SizedBox(height: 16),
            Text(tr('Список', 'Тізім'),
                style: manrope(12.5, FontWeight.w700, color: cInk3)),
            const SizedBox(height: 8),
            for (final r in _registries)
              _RegistryTile(
                title: r.title,
                subtitle: RegistryOccasion.withEmoji(r.occasion),
                selected: _registryId == r.id,
                onTap: () => setState(() => _registryId = r.id),
              ),
            _RegistryTile(
              title: tr('Новый список', 'Жаңа тізім'),
              subtitle: tr('Создать прямо сейчас', 'Дәл қазір жасау'),
              icon: Icons.add_rounded,
              selected: _creating,
              onTap: () => setState(() => _registryId = null),
            ),
            if (_creating) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _newTitle,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                style: manrope(15, FontWeight.w600, color: cInk),
                decoration: _dec(tr('Название списка', 'Тізім атауы')),
              ),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in RegistryOccasion.keys)
                  RegistryOccasionChip(
                    label: RegistryOccasion.withEmoji(k),
                    selected: _occasion == k,
                    onTap: () => setState(() => _occasion = k),
                  ),
              ]),
            ],
            const SizedBox(height: 16),
            if (_sizesLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(
                    color: cGreen, backgroundColor: cLine2, minHeight: 2),
              )
            else if (_sizes.isNotEmpty) ...[
              Text(tr('Размер', 'Өлшем'),
                  style: manrope(12.5, FontWeight.w700, color: cInk3)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                RegistryOccasionChip(
                  label: tr('Любой', 'Кез келген'),
                  selected: _size.isEmpty,
                  onTap: () => setState(() => _size = ''),
                ),
                for (final s in _sizes)
                  RegistryOccasionChip(
                    label: s,
                    selected: _size == s,
                    onTap: () => setState(() => _size = s),
                  ),
              ]),
              const SizedBox(height: 16),
            ],
            Row(children: [
              Text(tr('Сколько штук', 'Саны'),
                  style: manrope(12.5, FontWeight.w700, color: cInk3)),
              const Spacer(),
              _QtyStepper(
                value: _qty,
                onChanged: (v) => setState(() => _qty = v),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              style: manrope(14.5, FontWeight.w500, color: cInk),
              decoration: _dec(tr('Заметка для гостей (необязательно)',
                  'Қонақтарға жазба (міндетті емес)')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: manrope(12.5, FontWeight.w600, color: cRed)),
            ],
            const SizedBox(height: 12),
            QPrimaryButton(
              label: tr('Добавить в список', 'Тізімге қосу'),
              isLoading: _saving,
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: manrope(13, FontWeight.w600, color: cInk3),
        filled: true,
        fillColor: cBg,
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
}

class _RegistryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;
  const _RegistryTile({
    required this.title,
    required this.subtitle,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(kR14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cGreenTint : cSurface,
            borderRadius: BorderRadius.circular(kR14),
            border: Border.all(
                color: selected ? cGreen : cLine, width: selected ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? cGreen : cInk3),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: manrope(14, FontWeight.w700, color: cInk)),
                    Text(subtitle,
                        style: manrope(12, FontWeight.w500, color: cInk3)),
                  ]),
            ),
            if (icon != null) Icon(icon, color: cGreen),
          ]),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _QtyStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool enabled, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(kRPill),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 26, color: enabled ? cGreen : cLine),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.remove_circle_outline_rounded, value > 1,
          () => onChanged(value - 1)),
      SizedBox(
        width: 30,
        child: Text('$value',
            textAlign: TextAlign.center,
            style: manrope(16, FontWeight.w800, color: cInk)),
      ),
      btn(Icons.add_circle_outline_rounded, value < 20,
          () => onChanged(value + 1)),
    ]);
  }
}
