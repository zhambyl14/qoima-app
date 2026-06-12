import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../data/models/store_edit_request_model.dart';
import '../../../data/repositories/store_edit_repository.dart';
import '../../../data/services/firestore_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/edit_field_display.dart';
import 'store_edit_screen.dart';

/// Owner — өзгерту запросын күту экраны (v10 §9). Статус өзгерісін бақылайды:
/// approved → дүкен мәліметтеріне қайтару; rejected → себеп + «Редактировать заново».
class StoreEditPendingScreen extends StatelessWidget {
  const StoreEditPendingScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _cancel(BuildContext context, String editId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Отозвать запрос?',
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text('Изменения не будут отправлены модератору.',
            style: manrope(13.5, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Нет', style: manrope(14, FontWeight.w600, color: cInk2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('Отозвать', style: manrope(14, FontWeight.w700, color: cRed)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await StoreEditRepository().cancelEdit(editId);
    if (context.mounted) Navigator.maybePop(context);
  }

  Future<void> _reEdit(BuildContext context) async {
    final store = await FirestoreService().getStore();
    if (!context.mounted || store == null) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => StoreEditScreen(store: store)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = StoreEditRepository();
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<StoreEditRequestModel?>(
        stream: repo.watchMyLatest(_uid),
        builder: (context, snap) {
          final req = snap.data;
          return Column(children: [
            QGradientHeader(
              title: 'Данные магазина',
              subtitle: req?.shopName ?? 'Изменения',
              showBack: true,
            ),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: cGreen, strokeWidth: 2))
                  : (req == null || req.isCancelled)
                      ? _empty()
                      : SingleChildScrollView(
                          padding:
                              const EdgeInsets.fromLTRB(20, 16, 20, 28),
                          child: _content(context, req),
                        ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: cGreenTint, shape: BoxShape.circle),
              child:
                  const Icon(Icons.inbox_outlined, color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text('Нет активных запросов',
                style: manrope(15, FontWeight.w700, color: cInk)),
          ],
        ),
      );

  Widget _content(BuildContext context, StoreEditRequestModel req) {
    if (req.isApproved) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _StatusCard(
          tone: 'green',
          icon: Icons.check_circle_rounded,
          title: 'Изменения одобрены!',
          sub: 'Данные магазина обновлены модератором.',
        ),
        const SizedBox(height: 16),
        _ChangesCard(req: req, title: 'Применённые изменения'),
        const SizedBox(height: 18),
        QPrimaryButton(
          label: 'К данным магазина',
          icon: const Icon(Icons.chevron_right_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
      ]);
    }

    if (req.isRejected) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _StatusCard(
          tone: 'red',
          icon: Icons.cancel_rounded,
          title: 'Изменения отклонены',
          sub: req.reviewNote.isNotEmpty
              ? req.reviewNote
              : 'Модератор отклонил запрос.',
        ),
        const SizedBox(height: 16),
        _ChangesCard(req: req, title: 'Отклонённые изменения'),
        const SizedBox(height: 18),
        QPrimaryButton(
          label: 'Редактировать заново',
          icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 19),
          onPressed: () => _reEdit(context),
        ),
        const SizedBox(height: 10),
        _outlineBack(context),
      ]);
    }

    // pending
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cAmber.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(children: [
          QIconTile(
            icon: const Icon(Icons.hourglass_top_rounded,
                color: cAmber, size: 20),
            tone: 'amber',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Изменения отправлены модератору',
                    style: manrope(14, FontWeight.w800, color: cInk)),
                const SizedBox(height: 2),
                Text(
                    'Отправлено: ${_fmtDateTime(req.createdAt)} · '
                    '${req.changes.length} поля · решение в течение 1–2 дней',
                    style: manrope(11.5, FontWeight.w500,
                        color: cInk2, height: 1.35)),
              ],
            ),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      _ChangesCard(req: req, title: 'Изменения на проверке', pending: true),
      const SizedBox(height: 16),
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
                'До решения эти поля нельзя редактировать повторно. '
                'Запрос можно отозвать.',
                style: manrope(12, FontWeight.w500, color: cInk2, height: 1.4)),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: () => _cancel(context, req.id),
          icon: const Icon(Icons.close_rounded, color: cRed, size: 19),
          label: Text('Отозвать запрос',
              style: manrope(15, FontWeight.w700, color: cRed)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: cRed),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15)),
          ),
        ),
      ),
    ]);
  }

  Widget _outlineBack(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton(
          onPressed: () => Navigator.maybePop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: cInk2,
            side: const BorderSide(color: cLine),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          child: Text('Назад',
              style: manrope(14.5, FontWeight.w700, color: cInk2)),
        ),
      );
}

// ── Status card ──────────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final String tone; // green|red
  final IconData icon;
  final String title;
  final String sub;
  const _StatusCard({
    required this.tone,
    required this.icon,
    required this.title,
    required this.sub,
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: isRed ? cRed : cGreen, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: manrope(14.5, FontWeight.w800,
                      color: isRed ? const Color(0xFFB11A2B) : cGreenDeep)),
              const SizedBox(height: 2),
              Text(sub,
                  style: manrope(12.5, FontWeight.w500,
                      color: cInk2, height: 1.4)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Changes card ─────────────────────────────────────────────────────────────────
class _ChangesCard extends StatelessWidget {
  final StoreEditRequestModel req;
  final String title;
  final bool pending;
  const _ChangesCard(
      {required this.req, required this.title, this.pending = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QSecLabel(title),
        QCard(
          child: Column(
            children: List.generate(req.changes.length, (i) {
              final c = req.changes[i];
              return Padding(
                padding: EdgeInsets.only(
                    bottom: i == req.changes.length - 1 ? 0 : 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(editFieldIcon(c.field), color: cInk3, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.label.toUpperCase(),
                              style: manrope(10.5, FontWeight.w700,
                                  color: cInk3, letterSpacing: 0.5)),
                          const SizedBox(height: 3),
                          Row(children: [
                            Flexible(
                              child: Text(
                                  editFieldDisplay(c.field, c.oldValue),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: manrope(12.5, FontWeight.w600,
                                          color: cInk3)
                                      .copyWith(
                                          decoration:
                                              TextDecoration.lineThrough)),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: cAmber, size: 16),
                            Flexible(
                              child: Text(
                                  editFieldDisplay(c.field, c.newValue),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: manrope(12.5, FontWeight.w800,
                                      color: cInk)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                    if (pending) ...[
                      const SizedBox(width: 6),
                      const QPill('Ожидание', tone: 'amber'),
                    ],
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

String _two(int v) => v.toString().padLeft(2, '0');
String _fmtDateTime(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';
