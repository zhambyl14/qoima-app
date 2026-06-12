import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/app_user.dart';
import '../../../core/kz_cities.dart';
import '../../../core/warehouse_context.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';

// ── Luhn algorithm ──────────────────────────────────────────────────────────────
bool _luhnCheck(String digits) {
  if (digits.isEmpty) return false;
  int sum = 0;
  bool alternate = false;
  for (int i = digits.length - 1; i >= 0; i--) {
    int n = int.parse(digits[i]);
    if (alternate) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

String _formatCardDisplay(String digits) {
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && i % 4 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return buf.toString();
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 19 ? digits.substring(0, 19) : digits;
    final formatted = _formatCardDisplay(capped);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}


class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _service = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _cardHolderCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();

  StoreModel? _store;
  String? _selectedCity;
  bool _isPublished = false;
  List<String> _visibleWarehouseIds = [];
  bool _isLoading = false;
  bool _isDirty = false;
  // Card validation state
  bool _cardLoadedFromDb = false; // true when card was loaded from Firestore
  bool _cardIsValid = false;      // live Luhn result
  String? _cardError;             // inline error message under the field

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    _cardNumberCtrl.dispose();
    _cardHolderCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await _service.getStore();
    if (!mounted) return;
    if (store != null) {
      _nameCtrl.text = store.storeName;
      _phoneCtrl.text = store.phone;
      _descCtrl.text = store.description;
      _cardNumberCtrl.text = _formatCardDisplay(store.paymentCardNumber);
      _cardHolderCtrl.text = store.paymentCardHolder;
      _bankCtrl.text = store.paymentBank;
      final loadedRaw = store.paymentCardNumber;
      setState(() {
        _store = store;
        _selectedCity = store.city.isNotEmpty ? store.city : null;
        _isPublished = store.isPublished;
        _visibleWarehouseIds = List<String>.from(store.visibleWarehouseIds);
        _cardLoadedFromDb = loadedRaw.isNotEmpty;
        _cardIsValid = _isCardValid(loadedRaw);
        if (loadedRaw.isNotEmpty && !_isCardValid(loadedRaw)) {
          _cardError = 'Бұрын сақталған нөмір тексеруден өтпеді. Картаны қайта енгізіңіз';
        }
      });
    }
  }

  bool _isCardValid(String digits) {
    final raw = digits.replaceAll(RegExp(r'\s'), '');
    if (raw.length < 13 || raw.length > 19) return false;
    return _luhnCheck(raw);
  }

  void _onCardChanged(String text) {
    final raw = text.replaceAll(RegExp(r'\s'), '');
    _markDirty();
    setState(() {
      _cardLoadedFromDb = false;
      _cardIsValid = raw.isNotEmpty && _isCardValid(raw);
      if (raw.isEmpty) {
        _cardError = null;
      } else if (raw.length < 13) {
        _cardError = null; // still typing
      } else if (!_isCardValid(raw)) {
        _cardError = 'Карта нөмірі дұрыс емес — цифрларды тексеріңіз';
      } else {
        _cardError = null;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isLoading) return;

    final adminUid = context.read<AppUser>().uid;
    final rawCard = _cardNumberCtrl.text.replaceAll(RegExp(r'\s'), '');
    if (rawCard.isNotEmpty) {
      if (!_isCardValid(rawCard)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_cardLoadedFromDb
              ? 'Бұрын сақталған нөмір тексеруден өтпеді. Картаны қайта енгізіңіз'
              : 'Карта нөмірі дұрыс емес — цифрларды тексеріңіз'),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _cardError = _cardLoadedFromDb
            ? 'Бұрын сақталған нөмір тексеруден өтпеді. Картаны қайта енгізіңіз'
            : 'Карта нөмірі дұрыс емес — цифрларды тексеріңіз');
        return;
      }
      if (_cardHolderCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Карта иесінің атын енгізіңіз'),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      // Confirmation dialog before saving card
      if (!mounted) return;
      final maskedCard =
          '•••• •••• •••• ${rawCard.substring(rawCard.length - 4)}';
      final holder = _cardHolderCtrl.text.trim().toUpperCase();
      // ignore: use_build_context_synchronously
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Реквизиттерді тексеріңіз',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Клиенттер төлем жасайтын картаңыз:',
                style: TextStyle(color: cInk2, fontSize: 13)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cGreen.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(maskedCard,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: cInk)),
                const SizedBox(height: 6),
                Text(holder,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cInk)),
                if (_bankCtrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_bankCtrl.text.trim(),
                      style: const TextStyle(fontSize: 12, color: cInk2)),
                ],
              ]),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Өзгерту',
                    style: TextStyle(color: cInk2))),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: cGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Растау')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final name = _nameCtrl.text.trim();
      final rawCardFinal = _cardNumberCtrl.text.replaceAll(RegExp(r'\s'), '');
      final updated = StoreModel(
        adminUid: adminUid,
        storeName: name,
        storeSlug: StoreModel.generateSlug(name),
        logoUrl: _store?.logoUrl ?? '',
        city: _selectedCity ?? '',
        phone: _phoneCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        visibleWarehouseIds: _visibleWarehouseIds,
        isPublished: _isPublished,
        createdAt: _store?.createdAt ?? now,
        updatedAt: now,
        paymentCardNumber: rawCardFinal,
        paymentCardHolder: _cardHolderCtrl.text.trim().toUpperCase(),
        paymentBank: _bankCtrl.text.trim(),
      );
      await _service.saveStore(updated);
      if (mounted) {
        setState(() {
          _store = updated;
          _isDirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Сақталды'),
          backgroundColor: cGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _markDirty() => setState(() => _isDirty = true);

  @override
  Widget build(BuildContext context) {
    final warehouses = context.watch<WarehouseContext>().all;

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        title: const Text('Менің дүкенім'),
        actions: [
          if (_isDirty)
            TextButton(
              onPressed: _isLoading ? null : _save,
              child: const Text('Сақтау',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          onChanged: _markDirty,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section: Мой магазин ───────────────────────────────────
              _SectionHeader('Менің дүкенім'),
              const SizedBox(height: 12),

              _SettingsCard(children: [
                // Store name
                _FieldLabel('Дүкен атауы *'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      hintText: 'Мысалы: Alina Shoes',
                      prefixIcon: Icon(Icons.store_outlined)),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Міндетті';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // City
                _FieldLabel('Қала'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCity,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.location_city_outlined),
                      hintText: 'Қаланы таңдаңыз'),
                  items: kzCities
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedCity = v;
                      _isDirty = true;
                    });
                  },
                ),
                const SizedBox(height: 14),

                // Phone
                _FieldLabel('Телефон *'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                      hintText: '87001234567',
                      prefixIcon: Icon(Icons.phone_outlined),
                      prefixText: '+7 '),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Телефон нөмірін енгізіңіз';
                    }
                    if (v.trim().length < 10) {
                      return 'Телефон нөмірі дұрыс емес';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Description
                _FieldLabel('Сипаттама (120 таңба)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    hintText: 'Дүкен туралы қысқаша...',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.notes_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Published toggle
                Row(children: [
                  const Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Жарияланған',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: cInk)),
                      SizedBox(height: 2),
                      Text('Сатып алушылар дүкенді көреді',
                          style: TextStyle(
                              fontSize: 11, color: cInk2)),
                    ],
                  )),
                  Switch(
                    value: _isPublished,
                    activeThumbColor: cGreen,
                    onChanged: (v) => setState(() {
                      _isPublished = v;
                      _isDirty = true;
                    }),
                  ),
                ]),
              ]),
              const SizedBox(height: 20),

              // ── Section: Видимость складов ─────────────────────────────
              _SectionHeader('Қойма көрінуі'),
              const SizedBox(height: 6),
              const Text(
                  'Сатып алушыларға қандай қоймалардан тауар көрсету керек?',
                  style:
                      TextStyle(fontSize: 12, color: cInk2)),
              const SizedBox(height: 10),

              if (warehouses.isEmpty)
                const _EmptyNote('Қойма жоқ')
              else
                _SettingsCard(
                  children: warehouses.map((wh) {
                    final visible = _visibleWarehouseIds.contains(wh.id);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        const Icon(Icons.warehouse_outlined,
                            color: cGreen, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(wh.name,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: cInk))),
                        Switch(
                          value: visible,
                          activeThumbColor: cGreen,
                          onChanged: (v) {
                            setState(() {
                              _isDirty = true;
                              if (v) {
                                _visibleWarehouseIds.add(wh.id);
                              } else {
                                _visibleWarehouseIds.remove(wh.id);
                              }
                            });
                          },
                        ),
                      ]),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 20),

              // ── Section: Card requisites ───────────────────────────────
              _SectionHeader('Төлем реквизиттері'),
              const SizedBox(height: 6),
              const Text(
                  'Клиент тапсырыс берген кезде осы картаға ақша аударады',
                  style: TextStyle(fontSize: 12, color: cInk2)),
              const SizedBox(height: 10),
              _SettingsCard(children: [
                _FieldLabel('Карта нөмірі'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _cardNumberCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_CardNumberFormatter()],
                  decoration: InputDecoration(
                    hintText: '#### #### #### ####',
                    prefixIcon: const Icon(Icons.credit_card_outlined),
                    errorText: _cardError,
                    suffixIcon: _cardNumberCtrl.text.isEmpty
                        ? null
                        : _cardIsValid
                            ? const Icon(Icons.check_circle_rounded,
                                color: cGreen, size: 20)
                            : null,
                  ),
                  onChanged: _onCardChanged,
                ),
                const SizedBox(height: 14),
                _FieldLabel('Карта иесінің аты (картадағыдай)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _cardHolderCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'IVAN IVANOV',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 14),
                _FieldLabel('Банк (міндетті емес)'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _bankCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Kaspi, Halyk...',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ]),
              const SizedBox(height: 20),

              // ── Section: Preview ───────────────────────────────────────
              _SectionHeader('Сатып алушыларға арналған ақпарат'),
              const SizedBox(height: 10),
              _StorePreviewCard(
                storeName:
                    _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Дүкен атауы',
                city: _selectedCity ?? '',
                phone: _phoneCtrl.text,
                description: _descCtrl.text,
                isPublished: _isPublished,
              ),
              const SizedBox(height: 32),

              // ── Save button ────────────────────────────────────────────
              if (_isDirty)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Сақтау',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Store preview card ─────────────────────────────────────────────────────────
class _StorePreviewCard extends StatelessWidget {
  final String storeName, city, phone, description;
  final bool isPublished;
  const _StorePreviewCard({
    required this.storeName,
    required this.city,
    required this.phone,
    required this.description,
    required this.isPublished,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isPublished
                ? cGreen.withValues(alpha: 0.3)
                : cLine),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: cGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.storefront_rounded,
                  color: cGreen, size: 26)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(storeName,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cInk)),
              if (city.isNotEmpty)
                Text(city,
                    style: const TextStyle(
                        fontSize: 12, color: cInk2)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: (isPublished ? cGreen : cInk3)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(
              isPublished ? 'Жарияланған' : 'Жарияланбаған',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isPublished ? cGreen : cInk3),
            ),
          ),
        ]),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(description,
              style:
                  const TextStyle(fontSize: 13, color: cInk2)),
        ],
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.phone_outlined,
                size: 14, color: cInk3),
            const SizedBox(width: 4),
            Text('+7 $phone',
                style: const TextStyle(
                    fontSize: 12, color: cInk2)),
          ]),
        ],
      ]),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: cInk));
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: cInk2));
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, color: cInk3));
}

