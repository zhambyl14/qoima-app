import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../core/l10n_ext.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../main_shell.dart';

class SellerJoinScreen extends StatefulWidget {
  const SellerJoinScreen({super.key});
  @override
  State<SellerJoinScreen> createState() => _SellerJoinScreenState();
}

class _SellerJoinScreenState extends State<SellerJoinScreen> {
  bool _loading = false;
  String? _error;

  final List<TextEditingController> _digits =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focuses = List.generate(6, (_) => FocusNode());

  String get _enteredCode => _digits.map((c) => c.text).join();

  @override
  void dispose() {
    for (final c in _digits) { c.dispose(); }
    for (final f in _focuses) { f.dispose(); }
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final code = _enteredCode.trim();
    if (code.length < 6) {
      setState(() => _error = context.l10n.validationCodeRequired);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirestoreService().sendJoinRequest(code);
      if (mounted) context.read<AppUser>().joinStatus = 'pending';
      setState(() {});
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancelRequest() async {
    setState(() => _loading = true);
    try {
      await FirestoreService().cancelJoinRequest();
      if (mounted) context.read<AppUser>().joinStatus = 'none';
      setState(() {});
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async => AuthService().signOut();

  @override
  Widget build(BuildContext context) {
    if (context.watch<AppUser>().joinStatus == 'active') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainShell()),
              (r) => false);
        }
      });
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
          .snapshots(),
      builder: (_, snap) {
        final status = (snap.data?.data()
                as Map<String, dynamic>?)?['joinStatus'] as String? ??
            context.read<AppUser>().joinStatus;

        if (status == 'active') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.read<AppUser>().joinStatus = 'active';
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                  (r) => false);
            }
          });
        }

        return Scaffold(
          backgroundColor: cBg,
          body: status == 'pending' ? _buildPending() : _buildNone(),
        );
      },
    );
  }

  // ── None state: enter code ─────────────────────────────────────────────────
  Widget _buildNone() {
    return Column(children: [
      QGradientHeader(
        title: 'Привязка к складу',
        subtitle: 'Шаг подключения',
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              22, 24, 22, MediaQuery.of(context).viewInsets.bottom + 30),
          child: Column(children: [
            // Icon box
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cGreenTint,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.storefront_outlined,
                  color: cGreen, size: 40),
            ),
            const SizedBox(height: 16),
            Text('Привяжитесь к складу',
                style: manrope(20, FontWeight.w800, color: cInk),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'Введите код склада или отправьте запрос владельцу',
              style: manrope(13.5, FontWeight.w500, color: cInk2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // 6-digit code input
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  6,
                  (i) => _DigitBox(
                        controller: _digits[i],
                        focusNode: _focuses[i],
                        onChanged: (v) {
                          if (v.isNotEmpty && i < 5) {
                            FocusScope.of(context)
                                .requestFocus(_focuses[i + 1]);
                          }
                          setState(() => _error = null);
                        },
                        onBackspace: () {
                          if (_digits[i].text.isEmpty && i > 0) {
                            FocusScope.of(context)
                                .requestFocus(_focuses[i - 1]);
                            _digits[i - 1].clear();
                          }
                        },
                      )),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
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
                          style: manrope(13, FontWeight.w500, color: cRed))),
                ]),
              ),
            ],

            const SizedBox(height: 28),
            QPrimaryButton(
              label: context.l10n.sendRequest,
              isLoading: _loading,
              onPressed: _sendRequest,
            ),
            const SizedBox(height: 12),
            Text(
              'Владелец увидит запрос и подтвердит привязку',
              style: manrope(12.5, FontWeight.w500, color: cInk3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _signOut,
              child: Text(context.l10n.signOut,
                  style: manrope(14, FontWeight.w600, color: cInk2)),
            ),
          ]),
        ),
      ),
    ]);
  }

  // ── Pending state ──────────────────────────────────────────────────────────
  Widget _buildPending() {
    return Column(children: [
      QGradientHeader(
        title: 'Привязка к складу',
        subtitle: 'Ожидание',
      ),
      Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Amber clock circle
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                      color: cAmberTint, shape: BoxShape.circle),
                  child: const Icon(Icons.access_time_rounded,
                      color: cAmber, size: 46),
                ),
                const SizedBox(height: 20),
                Text('Запрос отправлен',
                    style: manrope(20, FontWeight.w800, color: cInk),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Ожидаем подтверждения владельца склада',
                  style: manrope(13.5, FontWeight.w500, color: cInk2),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Warehouse info card
                QCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    QIconTile(
                      icon: const Icon(Icons.storefront_outlined,
                          color: cBlue, size: 20),
                      tone: 'blue',
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Ожидание ответа',
                          style: manrope(14, FontWeight.w600, color: cInk)),
                    ),
                    QPill('На рассмотрении',
                        tone: 'amber',
                        icon: const Icon(Icons.access_time_rounded,
                            size: 13, color: Color(0xFF9A6A06))),
                  ]),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _loading ? null : _cancelRequest,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cRed,
                      side: const BorderSide(color: cRed),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: cRed, strokeWidth: 2))
                        : Text(context.l10n.cancelRequest,
                            style: manrope(14, FontWeight.w700, color: cRed)),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _signOut,
                  child: Text(context.l10n.signOut,
                      style: manrope(14, FontWeight.w600, color: cInk2)),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

// ── 6-digit cell ───────────────────────────────────────────────────────────────
class _DigitBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;

  const _DigitBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: manrope(22, FontWeight.w800, color: cGreen),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: cSurface,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: cLine, width: 1.5)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: cLine, width: 1.5)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: cGreen, width: 1.5)),
        ),
        onChanged: (v) {
          if (v.isEmpty) {
            onBackspace();
          } else {
            onChanged(v);
          }
        },
      ),
    );
  }
}
