import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/app_user.dart';
import '../../core/l10n_ext.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../main_shell.dart';

/// Seller-дің joinStatus-на байланысты 3 күй кепілдейді:
///  none    → бизнес-код енгізу UI
///  pending → күту экраны
///  active  → MainShell-ге жібереді (бұл экран көрінбейді)
class SellerJoinScreen extends StatefulWidget {
  const SellerJoinScreen({super.key});
  @override
  State<SellerJoinScreen> createState() => _SellerJoinScreenState();
}

class _SellerJoinScreenState extends State<SellerJoinScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  // 6 жеке input field үшін controllers
  final List<TextEditingController> _digits =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focuses = List.generate(6, (_) => FocusNode());

  String get _enteredCode => _digits.map((c) => c.text).join();

  @override
  void dispose() {
    _codeCtrl.dispose();
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
    setState(() { _loading = true; _error = null; });
    try {
      await FirestoreService().sendJoinRequest(code);
      // AppUser.joinStatus жаңартамыз
      AppUser.joinStatus = 'pending';
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
      AppUser.joinStatus = 'none';
      setState(() {});
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async => AuthService().signOut();

  @override
  Widget build(BuildContext context) {
    // Егер active болса — MainShell-ге жібереміз
    if (AppUser.joinStatus == 'active') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainShell()),
              (r) => false);
        }
      });
      return const SizedBox.shrink();
    }

    // Firestore-дан joinStatus live тыңдаймыз
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid ?? '')
          .snapshots(),
      builder: (_, snap) {
        final status = (snap.data?.data() as Map<String, dynamic>?)?['joinStatus']
                as String? ??
            AppUser.joinStatus;

        if (status == 'active') {
          AppUser.joinStatus = 'active';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const MainShell()),
                  (r) => false);
            }
          });
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: status == 'pending' ? _buildPending() : _buildNone(),
        );
      },
    );
  }

  // ── Бизнес-код енгізу UI ───────────────────────────────────────────────────
  Widget _buildNone() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 40),
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.storefront_rounded,
                color: AppTheme.primary, size: 40),
          ),
          const SizedBox(height: 24),
          Text(context.l10n.joinTitle,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(context.l10n.businessCodeSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(height: 40),

          // 6 жеке жасуша
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) => _DigitBox(
              controller: _digits[i],
              focusNode: _focuses[i],
              onChanged: (v) {
                if (v.isNotEmpty && i < 5) {
                  FocusScope.of(context).requestFocus(_focuses[i + 1]);
                }
                setState(() => _error = null);
              },
              onBackspace: () {
                if (_digits[i].text.isEmpty && i > 0) {
                  FocusScope.of(context).requestFocus(_focuses[i - 1]);
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
                  color: AppTheme.dangerLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3))),
              child: Row(children: [
                const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 13))),
              ]),
            ),
          ],

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : _sendRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(context.l10n.sendRequest,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),

          const SizedBox(height: 16),
          TextButton(
            onPressed: _signOut,
            child: Text(context.l10n.signOut,
                style: const TextStyle(color: AppTheme.textSecondary)),
          ),
        ]),
      ),
    );
  }

  // ── Күту экраны ───────────────────────────────────────────────────────────
  Widget _buildPending() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(
            width: 56, height: 56,
            child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
          ),
          const SizedBox(height: 32),
          Text(context.l10n.waitingApproval,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          Text(context.l10n.requestSentBody,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          const SizedBox(height: 40),
          OutlinedButton(
            onPressed: _loading ? null : _cancelRequest,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: AppTheme.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(context.l10n.cancelRequest),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _signOut,
            child: Text(context.l10n.signOut,
                style: const TextStyle(color: AppTheme.textSecondary)),
          ),
        ]),
      ),
    );
  }
}

// ── 6 жеке сандық ұяшық ───────────────────────────────────────────────────────
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
      width: 44, height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
            color: AppTheme.primary),
        decoration: InputDecoration(
          counterText: '',
          filled: true, fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2)),
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
