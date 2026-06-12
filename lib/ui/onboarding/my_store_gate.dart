import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_user.dart';
import '../../data/models/shop_request_model.dart';
import '../../data/models/store_model.dart';
import '../../data/repositories/shop_request_repository.dart';
import '../../data/services/firestore_service.dart';
import '../../theme/qoima_design.dart';
import '../auth/terms_screen.dart';
import '../admin/my_store/admin_my_store_hub_screen.dart';
import 'shop_apply_screen.dart';
import 'shop_pending_screen.dart';

/// Профиль → «Менің дүкенім» экраны. Интернет-дүкен ашу — міндетті емес,
/// сондықтан бұл экранды admin өзі ашқанда ғана көрінеді. Логика:
///   • Дүкен бар (бекітілген немесе ескі) → AdminMyStoreHubScreen (басқару).
///   • Дүкен жоқ → заявка ағыны: Terms → ShopApply → ShopPending → бекіту.
///     Бекітілгенде дүкен provision етіліп, AdminMyStoreHubScreen ашылады.
class MyStoreGate extends StatefulWidget {
  const MyStoreGate({super.key});

  @override
  State<MyStoreGate> createState() => _MyStoreGateState();
}

class _MyStoreGateState extends State<MyStoreGate> {
  final _repo = ShopRequestRepository();
  final _service = FirestoreService();

  // _provisioning: provision қазір жүріп жатыр (қайта кіруден қорғайды).
  // _provisioned:  provision сәтті аяқталды → setState арқылы бірден
  //                AdminMyStoreHubScreen-ге ауыстырамыз, watchStore() кешіккен
  //                жағдайда да экран қатып қалмайды.
  bool _provisioning = false;
  bool _provisioned = false;

  void _back() => Navigator.of(context).maybePop();

  Future<void> _onApproved(ShopRequestModel req) async {
    if (_provisioning || _provisioned) return;
    setState(() => _provisioning = true);
    try {
      await _repo.provisionApprovedShop(req);
      if (mounted) setState(() { _provisioned = true; _provisioning = false; });
    } catch (_) {
      if (mounted) setState(() => _provisioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Provision аяқталды → watchStore() эмиттемесе де бірден Settings.
    if (_provisioned) return const AdminMyStoreHubScreen();
    // Provision жүріп жатыр → loader көрсет, rebuild тудырма.
    if (_provisioning) return const _Loading();

    return StreamBuilder<StoreModel?>(
      stream: _service.watchStore(),
      builder: (context, storeSnap) {
        if (storeSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        // Дүкен бар (бекітілген немесе ескі admin) → басқару экраны.
        if (storeSnap.data != null) {
          return const AdminMyStoreHubScreen();
        }
        return _RequestFlow(
          repo: _repo,
          onApproved: _onApproved,
          onBack: _back,
        );
      },
    );
  }
}

class _RequestFlow extends StatelessWidget {
  final ShopRequestRepository repo;
  final void Function(ShopRequestModel) onApproved;
  final VoidCallback onBack;

  const _RequestFlow({
    required this.repo,
    required this.onApproved,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppUser>();

    if (!user.termsAccepted) {
      return TermsScreen(onCancel: onBack);
    }

    return StreamBuilder<ShopRequestModel?>(
      stream: repo.watchMyRequest(user.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final req = snap.data;

        if (req == null || req.isRejected) {
          return ShopApplyScreen(
            rejectedNote: req?.reviewNote,
            onCancel: onBack,
          );
        }

        if (req.isApproved) {
          // addPostFrameCallback — build ішінде side-effect орындаудың жалғыз
          // қауіпсіз жолы. onApproved ішіндегі (_provisioning || _provisioned)
          // қорғауы бірнеше рет жинала берген callback-тардың қайта-қайта
          // шақырылуынан сақтайды.
          WidgetsBinding.instance.addPostFrameCallback((_) => onApproved(req));
          return const _Loading();
        }

        return ShopPendingScreen(req: req, onCancel: onBack);
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: cBg,
        body: Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2),
        ),
      );
}
