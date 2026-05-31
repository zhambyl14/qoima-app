import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/kz_cities.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';
import '../client/client_shell.dart';

class ClientRegisterScreen extends StatefulWidget {
  final String uid;
  final String phone;
  const ClientRegisterScreen(
      {super.key, required this.uid, required this.phone});

  @override
  State<ClientRegisterScreen> createState() => _ClientRegisterScreenState();
}

class _ClientRegisterScreenState extends State<ClientRegisterScreen> {
  final _authService = AuthService();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _selectedCity;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final name = _nameCtrl.text.trim();
      final city = _selectedCity ?? '';
      await _authService.createClientDoc(
        uid: widget.uid,
        phone: widget.phone,
        name: name,
        city: city,
      );
      if (!mounted) return;
      context.read<AppUser>().set(
            uid: widget.uid,
            ownerUid: '',
            name: name,
            email: '',
            role: 'client',
            phone: widget.phone,
            city: city,
          );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ClientShell()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: cRed,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Знакомство',
          subtitle: 'Шаг 2 из 2',
          showBack: true,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                22, 20, 22, MediaQuery.of(context).viewInsets.bottom + 30),
            child: Form(
              key: _formKey,
              child: Column(children: [
                // Avatar icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: cGreenTint,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      color: cGreen, size: 40),
                ),
                const SizedBox(height: 16),
                Text('Как вас зовут?',
                    style: manrope(20, FontWeight.w800, color: cInk),
                    textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text(
                  'Имя увидят продавцы при выдаче заказа',
                  style: manrope(13.5, FontWeight.w500, color: cInk2),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Name field
                _QFormField(
                  controller: _nameCtrl,
                  label: 'Ваше имя',
                  hint: 'Например: Алия',
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Имя обязательно';
                    if (v.trim().length < 2) return 'Минимум 2 символа';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // City dropdown
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ваш город *',
                        style: manrope(12.5, FontWeight.w700, color: cInk2)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        color: cSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _selectedCity != null ? cGreen : cLine,
                            width: 1.5),
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCity,
                        isExpanded: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.location_city_outlined,
                              color: cGreen, size: 19),
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
                        onChanged: (v) => setState(() => _selectedCity = v),
                        validator: (v) =>
                            v == null ? 'Выберите город' : null,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
                QPrimaryButton(
                  label: 'Начать покупки',
                  isLoading: _isLoading,
                  onPressed: _register,
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Styled form field ─────────────────────────────────────────────────────────
class _QFormField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _QFormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  State<_QFormField> createState() => _QFormFieldState();
}

class _QFormFieldState extends State<_QFormField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: manrope(12.5, FontWeight.w700, color: cInk2)),
        const SizedBox(height: 6),
        Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: cSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _focused ? cGreen : cLine, width: 1.5),
              boxShadow: _focused
                  ? [BoxShadow(color: cGreenTint, blurRadius: 0, spreadRadius: 4)]
                  : null,
            ),
            child: Row(children: [
              const SizedBox(width: 14),
              Icon(widget.icon, color: _focused ? cGreen : cInk3, size: 19),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  textCapitalization: widget.textCapitalization,
                  style: manrope(15, FontWeight.w600, color: cInk),
                  validator: widget.validator,
                  cursorColor: cGreen,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    errorStyle: const TextStyle(height: 0),
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ]),
          ),
        ),
      ],
    );
  }
}
