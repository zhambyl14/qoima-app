import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/services/auth_service.dart';
import '../../theme/app_theme.dart';
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
      await _authService.createClientDoc(
        uid: widget.uid,
        phone: widget.phone,
        name: name,
      );
      if (!mounted) return;
      context.read<AppUser>().set(
            uid: widget.uid,
            ownerUid: '',
            name: name,
            email: '',
            role: 'client',
            phone: widget.phone,
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
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Профильді толтыру'),
        backgroundColor: AppTheme.primary,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded,
                        color: AppTheme.success, size: 36),
                  ),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text('Телефон расталды!',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.3)),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text('Атыңызды енгізіңіз',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                ),
                const SizedBox(height: 32),
                const Text('Атыңыз *',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Мысалы: Айгерім',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Аты міндетті';
                    if (v.trim().length < 2) return 'Кем дегенде 2 таңба';
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Жалғастыру',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
