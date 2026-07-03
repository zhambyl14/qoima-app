import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/kz_cities.dart';
import '../../core/phone_input.dart';
import '../../core/warehouse_context.dart';
import '../../data/services/auth_service.dart';
import '../../theme/qoima_design.dart';

/// Google-мен алғаш кірген қолданушының профилін аяқтау экраны.
/// Auth сессиясы бар, бірақ users/clients жолы жоқ болғанда gate осыны
/// көрсетеді: рөл таңдалады + тіркеуде міндетті деректер толтырылады
/// (клиент: телефон + аты + қала; бизнес: аты). Сәтті болса AppUser
/// орнатылады да, реактивті gate дұрыс экранға ауыстырады.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _authService = AuthService();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: _authService.oauthDisplayName);
  final _phoneCtrl = TextEditingController();
  String? _selectedCity;

  String _role = 'client'; // 'client' | 'admin' | 'seller'
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _setErr(String? m) => setState(() => _error = m);

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().length < 2) {
      _setErr('Атыңызды енгізіңіз');
      return;
    }
    if (_role == 'client') {
      if (!isValidKzPhone(_phoneCtrl.text)) {
        _setErr('Телефон нөмірін толық енгізіңіз');
        return;
      }
      if (_selectedCity == null) {
        _setErr('Қаланы таңдаңыз');
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _authService.currentUid ?? '';
      final email = _authService.currentUser?.email ?? '';
      final appUser = context.read<AppUser>();

      if (_role == 'client') {
        final phone = kzPhoneToE164(_phoneCtrl.text);
        await _authService.completeClientProfile(
          phoneNumber: phone,
          name: _nameCtrl.text,
          city: _selectedCity!,
        );
        if (!mounted) return;
        // Gate реактивті — AppUser орнаған соң ClientShell ашылады.
        appUser.set(
          uid: uid,
          ownerUid: '',
          name: _nameCtrl.text.trim(),
          email: email,
          role: 'client',
          phone: phone,
          city: _selectedCity!,
          emailVerified: true,
        );
      } else {
        await _authService.completeBusinessProfile(
          name: _nameCtrl.text,
          role: _role,
        );
        if (!mounted) return;
        final doc = await _authService.getUserDoc(uid);
        if (!mounted) return;
        appUser.set(
          uid: uid,
          ownerUid: _role == 'admin' ? uid : '',
          name: _nameCtrl.text.trim(),
          email: email,
          role: _role,
          businessCode: doc?.businessCode ?? '',
          joinStatus: _role == 'admin' ? 'active' : 'none',
          shopStatus: doc?.shopStatus ?? 'approved',
        );
        if (_role == 'admin') {
          try {
            await context.read<WarehouseContext>().load();
          } catch (_) {}
        }
      }
    } on AuthFailure catch (e) {
      _setErr(e.message);
    } catch (e) {
      _setErr('Қате: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _authService.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        QGradientHeader(
          title: 'Тіркелуді аяқтау',
          subtitle: email,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                22, 20, 22, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Кім ретінде жалғастырасыз?',
                    style: manrope(13, FontWeight.w700, color: cInk)),
                const SizedBox(height: 10),
                _RoleTile(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Сатып алушы',
                  subtitle: 'Маркетплейстен тауар аламын',
                  selected: _role == 'client',
                  onTap: () => setState(() => _role = 'client'),
                ),
                const SizedBox(height: 10),
                _RoleTile(
                  icon: Icons.storefront_rounded,
                  title: 'Дүкен иесі',
                  subtitle: 'Өз дүкенім/қоймам бар',
                  selected: _role == 'admin',
                  onTap: () => setState(() => _role = 'admin'),
                ),
                const SizedBox(height: 10),
                _RoleTile(
                  icon: Icons.badge_outlined,
                  title: 'Сатушы',
                  subtitle: 'Дүкенге бизнес-кодпен қосыламын',
                  selected: _role == 'seller',
                  onTap: () => setState(() => _role = 'seller'),
                ),
                const SizedBox(height: 18),

                // Аты (барлық рөлге)
                Text('Атыңыз',
                    style: manrope(12.5, FontWeight.w700, color: cInk2)),
                const SizedBox(height: 6),
                _box(TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: manrope(15, FontWeight.w600, color: cInk),
                  cursorColor: cGreen,
                  decoration: _dec('Мысалы: Алия'),
                )),

                // Клиентке: телефон + қала
                if (_role == 'client') ...[
                  const SizedBox(height: 14),
                  Text('Телефон нөмірі',
                      style: manrope(12.5, FontWeight.w700, color: cInk2)),
                  const SizedBox(height: 6),
                  _box(TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KzPhoneInputFormatter()],
                    style: manrope(15, FontWeight.w600, color: cInk),
                    cursorColor: cGreen,
                    decoration: _dec('+7 (700) 000-00-00'),
                  )),
                  const SizedBox(height: 14),
                  Text('Қалаңыз',
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
                        hintText: 'Қаланы таңдаңыз',
                        hintStyle: manrope(15, FontWeight.w500, color: cInk3),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 4),
                        isDense: true,
                      ),
                      style: manrope(15, FontWeight.w600, color: cInk),
                      dropdownColor: cSurface,
                      items: kzCities
                          .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c,
                                  style: manrope(14, FontWeight.w500,
                                      color: cInk))))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCity = v),
                    ),
                  ),
                ],

                if (_role == 'seller') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded,
                          color: cGreen, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            'Келесі қадамда дүкен иесінің бизнес-кодын енгізесіз',
                            style:
                                manrope(12, FontWeight.w500, color: cGreen)),
                      ),
                    ]),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cRedTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cRed.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: cRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: manrope(13, FontWeight.w500,
                                  color: cRed))),
                    ]),
                  ),
                ],

                const SizedBox(height: 22),
                QPrimaryButton(
                  label: 'Жалғастыру',
                  isLoading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 14),
                Center(
                  child: GestureDetector(
                    onTap: _loading ? null : () => _authService.signOut(),
                    child: Text('Басқа аккаунтпен кіру',
                        style: manrope(14, FontWeight.w600, color: cInk2)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: manrope(15, FontWeight.w500, color: cInk3),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      );

  Widget _box(Widget child) => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cLine, width: 1.5),
        ),
        child: Center(child: child),
      );
}

// ── Рөл картасы ───────────────────────────────────────────────────────────────
class _RoleTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? cGreen.withValues(alpha: 0.08) : cSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? cGreen : cLine, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          QIconTile(
            icon: Icon(icon, color: selected ? cGreen : cInk3, size: 20),
            tone: selected ? 'green' : 'ink',
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: manrope(14.5, FontWeight.w800,
                        color: selected ? cGreen : cInk)),
                Text(subtitle,
                    style: manrope(12, FontWeight.w500, color: cInk2)),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle_rounded, color: cGreen, size: 20),
        ]),
      ),
    );
  }
}
