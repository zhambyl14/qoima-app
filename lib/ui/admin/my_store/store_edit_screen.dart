import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/card_utils.dart';
import '../../../core/kz_cities.dart';
import '../../../data/models/store_edit_request_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/repositories/store_edit_repository.dart';
import '../../../theme/qoima_design.dart';
import 'store_edit_pending_screen.dart';

/// Owner — дүкен мәліметтерін өңдеу (v10 §8). Өрістер ағымдағы мәндермен
/// толтырылады; өзгерген өріс «ИЗМЕНЕНО» badge + «Было:» көрсетеді. «Отправить»
/// тек ӨЗГЕРГЕН өрістерден `changes` массивін құрып, storeEditRequests-ке жазады.
/// store/main ӨЗГЕРМЕЙДІ — тек модератор approve еткенде қолданылады.
class StoreEditScreen extends StatefulWidget {
  final StoreModel store;
  const StoreEditScreen({super.key, required this.store});

  @override
  State<StoreEditScreen> createState() => _StoreEditScreenState();
}

class _StoreEditScreenState extends State<StoreEditScreen> {
  final _repo = StoreEditRepository();

  late final _nameCtrl = TextEditingController(text: widget.store.storeName);
  late final _descCtrl = TextEditingController(text: widget.store.description);
  late final _ownerNameCtrl = TextEditingController(text: widget.store.ownerName);
  late final _iinCtrl = TextEditingController(text: widget.store.ownerIin);
  late final _phoneCtrl = TextEditingController(text: widget.store.phone);
  late final _cardCtrl = TextEditingController(
      text: formatCardDisplay(widget.store.paymentCardNumber));
  final _commentCtrl = TextEditingController();

  late String _city = widget.store.city;
  bool _loading = false;

  StoreModel get store => widget.store;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _ownerNameCtrl.dispose();
    _iinCtrl.dispose();
    _phoneCtrl.dispose();
    _cardCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  List<EditField> _collectChanges() {
    final changes = <EditField>[];
    void add(String field, String label, String oldV, String newV) {
      if (oldV.trim() != newV.trim()) {
        changes.add(EditField(
            field: field, label: label, oldValue: oldV.trim(), newValue: newV.trim()));
      }
    }

    add('storeName', 'Название', store.storeName, _nameCtrl.text);
    add('city', 'Город', store.city, _city);
    add('description', 'Описание', store.description, _descCtrl.text);
    add('ownerName', 'ФИО', store.ownerName, _ownerNameCtrl.text);
    add('ownerIin', 'ИИН / БИН', store.ownerIin, _iinCtrl.text);
    add('phone', 'Телефон', store.phone, _phoneCtrl.text);
    add('paymentCardNumber', 'Номер карты', store.paymentCardNumber,
        cardDigitsOnly(_cardCtrl.text));
    return changes;
  }

  int get _changedCount => _collectChanges().length;

  bool get _cardOk {
    final raw = cardDigitsOnly(_cardCtrl.text);
    return raw.isEmpty || isCardValid(raw);
  }

  bool get _canSubmit => _changedCount > 0 && _cardOk && !_loading;

  Future<void> _onSubmit() async {
    final changes = _collectChanges();
    if (changes.isEmpty) {
      _snack('Вы ничего не изменили');
      return;
    }
    if (!_cardOk) {
      _snack('Карта должна содержать 16 цифр и пройти проверку');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Отправить на проверку?',
            style: manrope(16.5, FontWeight.w800, color: cInk)),
        content: Text(
            'Будет изменено ${changes.length} ${_plural(changes.length)}. '
            'Изменения вступят в силу после одобрения модератором.',
            style: manrope(13.5, FontWeight.w500, color: cInk2, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена',
                style: manrope(14, FontWeight.w600, color: cInk2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Отправить',
                style: manrope(14, FontWeight.w800, color: cGreen)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final req = StoreEditRequestModel(
        id: '',
        ownerUid: Supabase.instance.client.auth.currentUser!.id,
        shopName: store.storeName,
        changes: changes,
        ownerComment: _commentCtrl.text.trim(),
        status: 'pending',
        createdAt: DateTime.now(),
      );
      await _repo.submitEdit(req);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const StoreEditPendingScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(e.toString());
      }
    }
  }

  String _plural(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'поле';
    if ([2, 3, 4].contains(n % 10) && !(n % 100 >= 12 && n % 100 <= 14)) {
      return 'поля';
    }
    return 'полей';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: cInk,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final count = _changedCount;
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Редактирование',
          subtitle:
              count > 0 ? '$count ${_plural(count)} изменено' : 'Без изменений',
          showBack: true,
          onBack: _loading ? null : () => Navigator.maybePop(context),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cAmberTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        color: cAmber, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'Изменения применяются не сразу. После сохранения '
                          'запрос отправляется модератору на проверку.',
                          style: manrope(12.5, FontWeight.w500,
                              color: const Color(0xFF7A4F00), height: 1.4)),
                    ),
                  ]),
                ),

                const SizedBox(height: 20),
                const QSecLabel('Магазин'),
                _EditField(
                  label: 'Название',
                  icon: Icons.store_outlined,
                  controller: _nameCtrl,
                  original: store.storeName,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _CityEdit(
                  value: _city,
                  original: store.city,
                  onChanged: (v) => setState(() => _city = v ?? _city),
                ),
                const SizedBox(height: 14),
                _EditField(
                  label: 'Описание',
                  icon: Icons.notes_rounded,
                  controller: _descCtrl,
                  original: store.description,
                  onChanged: (_) => setState(() {}),
                  multiline: true,
                ),

                const SizedBox(height: 20),
                const QSecLabel('Владелец'),
                _EditField(
                  label: 'ФИО',
                  icon: Icons.person_outline_rounded,
                  controller: _ownerNameCtrl,
                  original: store.ownerName,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _EditField(
                  label: 'ИИН / БИН',
                  icon: Icons.credit_card_outlined,
                  controller: _iinCtrl,
                  original: store.ownerIin,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 12,
                ),
                const SizedBox(height: 14),
                _EditField(
                  label: 'Телефон',
                  icon: Icons.phone_outlined,
                  controller: _phoneCtrl,
                  original: store.phone,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.phone,
                ),

                const SizedBox(height: 20),
                const QSecLabel('Выплаты'),
                _EditField(
                  label: 'Номер карты',
                  icon: Icons.account_balance_wallet_outlined,
                  controller: _cardCtrl,
                  original: formatCardDisplay(store.paymentCardNumber),
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  formatters: [CardNumberFormatter()],
                  errorText: (!_cardOk) ? '16 цифр, проверка не пройдена' : null,
                ),

                const SizedBox(height: 14),
                const QSecLabel('Комментарий (необязательно)'),
                _EditField(
                  label: 'Для модератора',
                  icon: Icons.chat_bubble_outline_rounded,
                  controller: _commentCtrl,
                  original: '',
                  onChanged: (_) {},
                  multiline: true,
                  showChanged: false,
                ),

                const SizedBox(height: 24),
                AnimatedOpacity(
                  opacity: _canSubmit ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: QPrimaryButton(
                    label: 'Отправить изменения',
                    isLoading: _loading,
                    icon: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 20),
                    onPressed: _canSubmit ? _onSubmit : null,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed:
                        _loading ? null : () => Navigator.maybePop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cInk2,
                      side: const BorderSide(color: cLine),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    child: Text('Отмена',
                        style: manrope(14.5, FontWeight.w700, color: cInk2)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Editable field (өзгерген күйді көрсетеді) ────────────────────────────────────
class _EditField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String original;
  final ValueChanged<String> onChanged;
  final bool multiline;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final int? maxLength;
  final String? errorText;
  final bool showChanged;

  const _EditField({
    required this.label,
    required this.icon,
    required this.controller,
    required this.original,
    required this.onChanged,
    this.multiline = false,
    this.keyboardType,
    this.formatters,
    this.maxLength,
    this.errorText,
    this.showChanged = true,
  });

  bool get _changed =>
      showChanged && controller.text.trim() != original.trim();

  @override
  Widget build(BuildContext context) {
    final changed = _changed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: manrope(12.5, FontWeight.w700, color: cInk2)),
          const Spacer(),
          if (changed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cAmberTint,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text('ИЗМЕНЕНО',
                  style: manrope(9.5, FontWeight.w800,
                      color: const Color(0xFF9A6A06), letterSpacing: 0.5)),
            ),
        ]),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: errorText != null
                    ? cRed
                    : (changed ? cAmber : cLine),
                width: 1.5),
            boxShadow: changed
                ? [
                    BoxShadow(
                        color: cAmber.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: multiline
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 14),
              Padding(
                padding: EdgeInsets.only(top: multiline ? 14 : 0),
                child: Icon(icon, color: cInk3, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  inputFormatters: formatters,
                  maxLength: maxLength,
                  minLines: multiline ? 3 : 1,
                  maxLines: multiline ? 5 : 1,
                  onChanged: onChanged,
                  style: manrope(15, FontWeight.w600, color: cInk),
                  cursorColor: cGreen,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterText: '',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        vertical: multiline ? 14 : 15),
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(errorText!, style: manrope(11.5, FontWeight.w600, color: cRed)),
        ] else if (changed) ...[
          const SizedBox(height: 4),
          Text('Было: ${original.isEmpty ? '—' : original}',
              style: manrope(11.5, FontWeight.w500, color: cInk3)
                  .copyWith(decoration: TextDecoration.lineThrough)),
        ],
      ],
    );
  }
}

// ── City dropdown (өзгерген күй) ─────────────────────────────────────────────────
class _CityEdit extends StatelessWidget {
  final String value;
  final String original;
  final ValueChanged<String?> onChanged;
  const _CityEdit({
    required this.value,
    required this.original,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final changed = value.trim() != original.trim();
    final current = value.isNotEmpty ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Город', style: manrope(12.5, FontWeight.w700, color: cInk2)),
          const Spacer(),
          if (changed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cAmberTint,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text('ИЗМЕНЕНО',
                  style: manrope(9.5, FontWeight.w800,
                      color: const Color(0xFF9A6A06), letterSpacing: 0.5)),
            ),
        ]),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: changed ? cAmber : cLine, width: 1.5),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: current,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon:
                  const Icon(Icons.location_on_outlined, color: cInk3, size: 19),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              isDense: true,
            ),
            style: manrope(15, FontWeight.w600, color: cInk),
            dropdownColor: cSurface,
            items: kzCities
                .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c,
                        style: manrope(14, FontWeight.w500, color: cInk))))
                .toList(),
            onChanged: onChanged,
          ),
        ),
        if (changed) ...[
          const SizedBox(height: 4),
          Text('Было: ${original.isEmpty ? '—' : original}',
              style: manrope(11.5, FontWeight.w500, color: cInk3)
                  .copyWith(decoration: TextDecoration.lineThrough)),
        ],
      ],
    );
  }
}
