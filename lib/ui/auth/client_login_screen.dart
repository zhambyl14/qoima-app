import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'client_register_screen.dart';
import 'login_screen.dart';

class ClientLoginScreen extends StatefulWidget {
  const ClientLoginScreen({super.key});

  @override
  State<ClientLoginScreen> createState() => _ClientLoginScreenState();
}

class _ClientLoginScreenState extends State<ClientLoginScreen> {
  final _authService     = AuthService();
  final _phoneCtrl       = TextEditingController();
  final _otpCtrl         = TextEditingController();

  bool    _isLoading      = false;
  bool    _otpSent        = false;
  String? _verificationId;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _fullPhone => '+7${_phoneCtrl.text.trim()}';

  // debug tip: тест нөмірлері Firebase Console-де белгіленген
  // +7 747 400 5347 → код: 123456
  // +1 747-400-5347 → код: 505050
  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 10) {
      setState(() => _errorMessage = 'Телефон нөмерін толық енгізіңіз');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    await _authService.verifyPhone(
      phoneNumber: _fullPhone,
      onCodeSent: (verificationId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _otpSent        = true;
              _isLoading      = false;
            });
          }
        });
      },
      onError: (error) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() { _errorMessage = error; _isLoading = false; });
        });
      },
    );
  }

  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'SMS кодын толық енгізіңіз (6 цифр)');
      return;
    }
    if (_verificationId == null) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final cred = await _authService.signInWithOtp(
        verificationId: _verificationId!,
        smsCode: code,
      );
      final uid = cred.user?.uid;
      if (uid == null || !mounted) return;

      final existing = await _authService.getClientDoc(uid);
      if (!mounted) return;

      if (existing != null) {
        // Pop back to the root so main.dart's StreamBuilder can show ClientShell
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      // New client — collect name
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ClientRegisterScreen(
            uid: uid,
            phone: _fullPhone,
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AuthService.parsePhoneError(e);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _errorMessage = 'Белгісіз қате'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Сатып алушы ретінде кіру'),
        backgroundColor: AppTheme.primary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shopping_bag_outlined,
                      color: AppTheme.primary, size: 36),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text('Телефон арқылы кіру',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary, letterSpacing: -0.3)),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _otpSent
                      ? 'SMS-пен жіберілген 6 цифрлық кодты енгізіңіз'
                      : 'Телефон нөміріңізді енгізіңіз',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 32),

              if (!_otpSent) ...[
                const Text('Телефон нөмірі',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 10,
                  decoration: const InputDecoration(
                    hintText: '7001234567',
                    prefixText: '+7 ',
                    prefixIcon: Icon(Icons.phone_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('SMS жіберу',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ] else ...[
                const Text('SMS коды',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8,
                      fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '——————',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Растау',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() {
                              _otpSent        = false;
                              _verificationId = null;
                              _otpCtrl.clear();
                              _errorMessage   = null;
                            }),
                    child: const Text('Нөмірді өзгерту',
                        style: TextStyle(color: AppTheme.textSecondary)),
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMessage!,
                        style: const TextStyle(color: AppTheme.danger, fontSize: 13))),
                  ]),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Qoima seller үшін',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios,
                        size: 12, color: AppTheme.primary),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
