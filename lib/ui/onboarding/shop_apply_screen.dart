import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/card_utils.dart';
import '../../core/kz_cities.dart';
import '../../data/models/shop_request_model.dart';
import '../../data/repositories/shop_request_repository.dart';
import '../../theme/qoima_design.dart';
import 'contract_screen.dart';

/// Дүкен ашу заявкасының формасы. Owner толтырып жібереді — superadmin бекітеді.
/// Жіберілген соң `shopRequests`-ке жазылады; корневой gate күту экранына ауысады.
class ShopApplyScreen extends StatefulWidget {
  /// Алдыңғы заявка бас тартылса — себебін көрсету (қайта жіберу).
  final String? rejectedNote;

  /// Бас тарту = аккаунттан шығу.
  final VoidCallback? onCancel;

  const ShopApplyScreen({super.key, this.rejectedNote, this.onCancel});

  @override
  State<ShopApplyScreen> createState() => _ShopApplyScreenState();
}

class _ShopApplyScreenState extends State<ShopApplyScreen> {
  final _repo = ShopRequestRepository();

  final _shopNameCtrl = TextEditingController();
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _iinCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _cardHolderCtrl = TextEditingController();

  String? _city;
  String _category = '';
  bool _contractAccepted = false;
  bool _loading = false;

  static const _categories = [
    'Обувь',
    'Одежда',
    'Аксессуары',
    'Спорт',
    'Другое',
  ];

  @override
  void initState() {
    super.initState();
    // Тіркеуде енгізілген атпен/телефонмен алдын ала толтыру.
    final user = context.read<AppUser>();
    _ownerNameCtrl.text = user.name;
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    if (phone.isNotEmpty) _phoneCtrl.text = phone;
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _ownerNameCtrl.dispose();
    _phoneCtrl.dispose();
    _iinCtrl.dispose();
    _descCtrl.dispose();
    _cardCtrl.dispose();
    _cardHolderCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _shopNameCtrl.text.trim().isNotEmpty &&
      _city != null &&
      _category.isNotEmpty &&
      _ownerNameCtrl.text.trim().isNotEmpty &&
      _phoneCtrl.text.trim().isNotEmpty &&
      isCardValid(_cardCtrl.text) &&
      _contractAccepted &&
      !_loading;

  Future<void> _onSubmit() async {
    if (!_canSubmit) return;
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final req = ShopRequestModel(
        id: '',
        ownerUid: uid,
        ownerName: _ownerNameCtrl.text.trim(),
        ownerPhone: _phoneCtrl.text.trim(),
        ownerIin: _iinCtrl.text.trim(),
        shopName: _shopNameCtrl.text.trim(),
        city: _city ?? '',
        category: _category,
        description: _descCtrl.text.trim(),
        cardNumber: cardDigitsOnly(_cardCtrl.text),
        cardHolder: _cardHolderCtrl.text.trim().toUpperCase(),
        cardBank: '',
        contractAccepted: _contractAccepted,
        status: 'pending',
        createdAt: DateTime.now(),
      );
      final reqId = await _repo.submitRequest(req);

      // users/{uid}-ге заявка ID-сін жазамыз (owner өз құжаты — рұқсат бар).
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'shopRequestId': reqId,
        'shopStatus': 'pending',
      }, SetOptions(merge: true));

      // Навигация жоқ — корневой gate watchMyRequest арқылы күту экранын көрсетеді.
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Открытие магазина',
          subtitle: 'Подача заявки',
          showBack: widget.onCancel != null,
          onBack: _loading ? null : widget.onCancel,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ескерту banner
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
                        'Магазин не открывается сразу. После отправки заявки '
                        'модератор проверит данные и уведомит вас.',
                        style: manrope(12.5, FontWeight.w500,
                            color: const Color(0xFF7A4F00), height: 1.4),
                      ),
                    ),
                  ]),
                ),

                if (widget.rejectedNote != null &&
                    widget.rejectedNote!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cRedTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(children: [
                      const Icon(Icons.cancel_outlined, color: cRed, size: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Предыдущая заявка отклонена',
                                style: manrope(12.5, FontWeight.w700,
                                    color: const Color(0xFFB11A2B))),
                            const SizedBox(height: 2),
                            Text(widget.rejectedNote!,
                                style: manrope(12.5, FontWeight.w500,
                                    color: cInk2, height: 1.4)),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 18),
                const QSecLabel('О магазине'),
                _Field(
                  controller: _shopNameCtrl,
                  label: 'Название магазина',
                  hint: 'Например: SneakerHub',
                  icon: Icons.store_outlined,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _CityDropdown(
                  value: _city,
                  onChanged: (v) => setState(() => _city = v),
                ),
                const SizedBox(height: 14),

                Text('Категория',
                    style: manrope(12.5, FontWeight.w700, color: cInk2)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.map((c) {
                    final sel = _category == c;
                    return GestureDetector(
                      onTap: () => setState(() => _category = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? cGreenTint : cSurface,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                              color: sel ? cGreen : cLine, width: 1.5),
                        ),
                        child: Text(c,
                            style: manrope(13.5, FontWeight.w700,
                                color: sel ? cGreenDeep : cInk2)),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),
                const QSecLabel('О владельце'),
                _Field(
                  controller: _ownerNameCtrl,
                  label: 'Полное имя',
                  hint: 'Имя и фамилия',
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _Field(
                  controller: _phoneCtrl,
                  label: 'Телефон',
                  hint: '+7 700 000 00 00',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _Field(
                  controller: _iinCtrl,
                  label: 'ИИН / БИН',
                  hint: '12 цифр',
                  icon: Icons.credit_card_outlined,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),

                const SizedBox(height: 14),
                Text('Краткое описание',
                    style: manrope(12.5, FontWeight.w700, color: cInk2)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: cSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cLine, width: 1.5),
                  ),
                  child: TextField(
                    controller: _descCtrl,
                    minLines: 3,
                    maxLines: 5,
                    style: manrope(15, FontWeight.w600, color: cInk),
                    cursorColor: cGreen,
                    decoration: InputDecoration(
                      hintText: 'Расскажите о своём магазине...',
                      hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14),
                      isDense: true,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const QSecLabel('Финансы'),
                _CardField(
                  controller: _cardCtrl,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _Field(
                  controller: _cardHolderCtrl,
                  label: 'Имя владельца карты (необязательно)',
                  hint: 'A. NURLAN',
                  icon: Icons.badge_outlined,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 6),
                Text('Имя владельца карты должно совпадать с владельцем ИИН',
                    style: manrope(11.5, FontWeight.w600, color: cInk3)),

                const SizedBox(height: 20),
                const QSecLabel('Договор'),
                _ContractRow(
                  accepted: _contractAccepted,
                  onOpen: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContractScreen()),
                  ),
                  onToggle: () =>
                      setState(() => _contractAccepted = !_contractAccepted),
                ),

                const SizedBox(height: 24),
                AnimatedOpacity(
                  opacity: _canSubmit ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: QPrimaryButton(
                    label: 'Отправить заявку',
                    isLoading: _loading,
                    icon: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white, size: 20),
                    onPressed: _canSubmit ? _onSubmit : null,
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

// ── City dropdown ──────────────────────────────────────────────────────────────
class _CityDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _CityDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Город',
            style: manrope(12.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: value != null ? cGreen : cLine, width: 1.5),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon:
                  const Icon(Icons.location_on_outlined, color: cGreen, size: 19),
              hintText: 'Выберите город',
              hintStyle: manrope(15, FontWeight.w500, color: cInk3),
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
      ],
    );
  }
}

// ── Field ──────────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: manrope(12.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cLine, width: 1.5),
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            Icon(icon, color: cInk3, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textCapitalization: textCapitalization,
                maxLength: maxLength,
                inputFormatters: inputFormatters,
                onChanged: onChanged,
                style: manrope(15, FontWeight.w600, color: cInk),
                cursorColor: cGreen,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 14),
          ]),
        ),
      ],
    );
  }
}

// ── Card field (для выплат) ──────────────────────────────────────────────────────
class _CardField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  const _CardField({required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final raw = cardDigitsOnly(controller.text);
    final valid = isCardValid(controller.text);
    final showError = raw.length == 16 && !valid;
    final borderColor = valid ? cGreen : (showError ? cRed : cLine);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Номер карты (для выплат)',
            style: manrope(12.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(children: [
            const SizedBox(width: 14),
            const Icon(Icons.credit_card_outlined, color: cInk3, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [CardNumberFormatter()],
                onChanged: onChanged,
                style: manrope(15, FontWeight.w700, color: cInk,
                    letterSpacing: 0.5),
                cursorColor: cGreen,
                decoration: InputDecoration(
                  hintText: '4400 4302 1183 5577',
                  hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            if (valid)
              const Icon(Icons.check_circle_rounded, color: cGreen, size: 19),
            const SizedBox(width: 14),
          ]),
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          Text('Карта должна содержать 16 цифр и пройти проверку',
              style: manrope(11.5, FontWeight.w600, color: cRed)),
        ],
      ],
    );
  }
}

// ── Contract row (договор оферты + согласие) ─────────────────────────────────────
class _ContractRow extends StatelessWidget {
  final bool accepted;
  final VoidCallback onOpen;
  final VoidCallback onToggle;
  const _ContractRow({
    required this.accepted,
    required this.onOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cLine, width: 1.5),
          ),
          child: Row(children: [
            QIconTile(
              icon: const Icon(Icons.description_outlined,
                  color: cGreen, size: 20),
              tone: 'green',
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Договор оферты',
                      style: manrope(14, FontWeight.w800, color: cInk)),
                  Text('Нажмите, чтобы прочитать',
                      style: manrope(12, FontWeight.w500, color: cInk3)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: cInk3, size: 20),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: accepted ? cGreenTint : cSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: accepted ? cGreen.withValues(alpha: 0.4) : cLine,
                width: 1.5),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: accepted ? cGreen : cSurface,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                    color: accepted ? cGreen : cLine, width: 1.5),
              ),
              child: accepted
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                  'Я ознакомился с договором оферты и принимаю условия',
                  style: manrope(13.5, FontWeight.w600, color: cInk,
                      height: 1.35)),
            ),
          ]),
        ),
      ),
    ]);
  }
}
