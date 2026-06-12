import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/card_utils.dart';
import '../../../data/models/store_edit_request_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/repositories/store_edit_repository.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import 'store_edit_pending_screen.dart';
import 'store_edit_screen.dart';

/// Owner — «Данные магазина» (оқу режимі, v10 §7). «Менің Дүкенім» ішінен ашылады.
/// Кез келген өзгеріс бірден қолданылмайды — модераторға запрос болып барады.
class StoreDataScreen extends StatelessWidget {
  const StoreDataScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    final editRepo = StoreEditRepository();

    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<StoreModel?>(
        stream: service.watchStore(),
        builder: (context, snap) {
          final store = snap.data;
          return Column(children: [
            QGradientHeader(
              title: 'Данные магазина',
              subtitle: store == null
                  ? 'Менің Дүкенім'
                  : 'Менің Дүкенім · ${store.storeName}',
              showBack: true,
            ),
            Expanded(
              child: store == null
                  ? (snap.connectionState == ConnectionState.waiting
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: cGreen, strokeWidth: 2))
                      : Center(
                          child: Text('Магазин не найден',
                              style: manrope(14, FontWeight.w600,
                                  color: cInk3))))
                  : StreamBuilder<StoreEditRequestModel?>(
                      stream: editRepo.watchMyPending(_uid),
                      builder: (context, pendSnap) {
                        final pending = pendSnap.data;
                        return _Body(store: store, pending: pending);
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final StoreModel store;
  final StoreEditRequestModel? pending;
  const _Body({required this.store, this.pending});

  @override
  Widget build(BuildContext context) {
    final blocked = store.isBlocked;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Статус-баннер ─────────────────────────────────────────────
          if (blocked)
            _Banner(
              tone: 'red',
              icon: Icons.lock_outline_rounded,
              title: 'Магазин заблокирован',
              sub: store.blockReason.isNotEmpty
                  ? store.blockReason
                  : 'Обратитесь в поддержку',
              pillLabel: 'Заблокирован',
            )
          else
            _Banner(
              tone: 'green',
              icon: Icons.verified_user_outlined,
              title: 'Магазин подтверждён',
              sub: 'Одобрено модератором',
              pillLabel: 'Активен',
            ),

          const SizedBox(height: 18),
          const QSecLabel('Магазин'),
          QCard(
            child: Column(children: [
              _InfoRow('Название', store.storeName),
              const SizedBox(height: 8),
              _InfoRow('Город', store.city.isEmpty ? '—' : store.city),
              const SizedBox(height: 8),
              _InfoRow('Категория',
                  store.category.isEmpty ? '—' : store.category),
              if (store.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: cLine),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ОПИСАНИЕ',
                      style: manrope(11.5, FontWeight.w700,
                          color: cInk3, letterSpacing: 0.5)),
                ),
                const SizedBox(height: 4),
                Text(store.description,
                    style: manrope(13.5, FontWeight.w500,
                        color: cInk2, height: 1.45)),
              ],
            ]),
          ),

          const SizedBox(height: 18),
          const QSecLabel('Владелец'),
          QCard(
            child: Column(children: [
              _InfoRow('ФИО', store.ownerName.isEmpty ? '—' : store.ownerName),
              const SizedBox(height: 8),
              _InfoRow('ИИН / БИН',
                  store.ownerIin.isEmpty ? '—' : store.ownerIin, mono: true),
              const SizedBox(height: 8),
              _InfoRow('Телефон',
                  store.phone.isEmpty ? '—' : store.phone, mono: true),
            ]),
          ),

          const SizedBox(height: 18),
          const QSecLabel('Выплаты'),
          QCard(
            child: Row(children: [
              Container(
                width: 56,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [cAmber, Color(0xFFF5C451)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Center(
                  child: Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(maskCardDisplay(store.paymentCardNumber),
                        style: manrope(15, FontWeight.w800,
                            color: cInk, letterSpacing: 1.0)),
                    if (store.paymentBank.isNotEmpty ||
                        store.paymentCardHolder.isNotEmpty)
                      Text(
                          [
                            if (store.paymentBank.isNotEmpty) store.paymentBank,
                            if (store.paymentCardHolder.isNotEmpty)
                              store.paymentCardHolder,
                          ].join(' · '),
                          style:
                              manrope(12, FontWeight.w600, color: cInk3)),
                  ],
                ),
              ),
              if (store.paymentCardNumber.isNotEmpty)
                const Icon(Icons.check_circle_rounded, color: cGreen, size: 20),
            ]),
          ),

          const SizedBox(height: 18),

          // ── Pending / редактировать ───────────────────────────────────
          if (pending != null) ...[
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: cAmberTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.hourglass_top_rounded,
                    color: cAmber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Изменения на проверке',
                          style: manrope(13.5, FontWeight.w700,
                              color: Color(0xFF9A6A06))),
                      Text(
                          '${pending!.changes.length} поля · решение в течение 1–2 дней',
                          style: manrope(12, FontWeight.w500, color: cInk2)),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            QSoftButton(
              label: 'Перейти к запросу',
              icon: const Icon(Icons.chevron_right_rounded,
                  color: cGreenDeep, size: 19),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const StoreEditPendingScreen()),
              ),
            ),
          ] else if (!blocked) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cBg,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: cLine),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: cInk3, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'Чтобы изменить любое поле — нажмите «Редактировать». '
                      'Изменения вступят в силу после одобрения модератором.',
                      style: manrope(12, FontWeight.w500,
                          color: cInk2, height: 1.4)),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            QPrimaryButton(
              label: 'Редактировать данные',
              icon: const Icon(Icons.edit_outlined,
                  color: Colors.white, size: 19),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => StoreEditScreen(store: store)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Status banner ────────────────────────────────────────────────────────────────
class _Banner extends StatelessWidget {
  final String tone; // green|red
  final IconData icon;
  final String title;
  final String sub;
  final String pillLabel;
  const _Banner({
    required this.tone,
    required this.icon,
    required this.title,
    required this.sub,
    required this.pillLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isRed = tone == 'red';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRed ? cRedTint : cGreenTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(icon, color: isRed ? cRed : cGreen, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: manrope(14.5, FontWeight.w800,
                      color: isRed ? const Color(0xFFB11A2B) : cGreenDeep)),
              Text(sub,
                  style: manrope(12, FontWeight.w500,
                      color: cInk2, height: 1.35)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        QPill(pillLabel,
            tone: isRed ? 'red' : 'green',
            icon: Icon(isRed ? Icons.lock_rounded : Icons.check_rounded,
                color: isRed ? const Color(0xFFB11A2B) : cGreenDeep, size: 13)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _InfoRow(this.label, this.value, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: manrope(12.5, FontWeight.w500, color: cInk3)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: manrope(13.5, FontWeight.w700,
                  color: cInk, letterSpacing: mono ? 0.5 : 0)),
        ),
      ],
    );
  }
}
