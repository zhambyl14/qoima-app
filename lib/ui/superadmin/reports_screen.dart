import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/lang.dart';
import '../../data/models/report_model.dart';
import '../../data/repositories/report_repository.dart';
import '../../data/repositories/store_moderation_repository.dart';
import '../../theme/qoima_design.dart';
import 'reject_reason_sheet.dart';
import '../../core/error_text.dart';

/// Superadmin — контент шағымдары (тауар/дүкен/пікір/сұрақ/сторис).
///
/// App Store Guideline 1.2: шағымдарға уақтылы жауап беру механизмі.
/// Әрекеттер: шағымды жабу (шешілді/қабылданбады), пікірді өшіру,
/// стористі өшіру, дүкенді онлайн-блоктау.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _repo = ReportRepository();
  final _storeRepo = StoreModerationRepository();
  late final Stream<List<ReportModel>> _reports = _repo.watchReports();
  int _tab = 0; // 0 Новые · 1 Все · 2 Обработанные

  String get _uid => Supabase.instance.client.auth.currentUser!.id;

  List<ReportModel> _filter(List<ReportModel> all) {
    switch (_tab) {
      case 0:
        return all.where((r) => r.isNew).toList();
      case 2:
        return all.where((r) => !r.isNew).toList();
      default:
        return all;
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Шағымды жабу (шешілді/қабылданбады) — түсіндірмемен.
  Future<void> _close(ReportModel r, String status) async {
    final note = await showRejectReasonSheet(
      context,
      title: status == 'resolved'
          ? tr('Решение по жалобе', 'Шағым бойынша шешім')
          : tr('Отклонение жалобы', 'Шағымды қабылдамау'),
      subtitle: r.targetName,
      reasons: status == 'resolved'
          ? [
              tr('Контент удалён', 'Контент өшірілді'),
              tr('Магазин заблокирован', 'Дүкен блокталды'),
              tr('Продавцу вынесено предупреждение',
                  'Сатушыға ескерту жасалды'),
            ]
          : [
              tr('Нарушение не подтвердилось', 'Бұзушылық расталмады'),
              tr('Недостаточно информации', 'Ақпарат жеткіліксіз'),
            ],
    );
    if (note == null) return;
    try {
      await _repo.resolve(
          reportId: r.id, status: status, resolvedBy: _uid, note: note);
      _snack(
          status == 'resolved'
              ? tr('Жалоба закрыта как решённая', 'Шағым шешілді деп жабылды')
              : tr('Жалоба отклонена', 'Шағым қабылданбады'),
          cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  /// Пікірді модерациялап өшіру (шағым авто-жабылмайды — модератор өзі жабады).
  Future<void> _deleteReview(ReportModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Удалить отзыв?', 'Пікірді өшіру керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Отзыв будет удалён безвозвратно, рейтинг товара пересчитается.',
                'Пікір біржола өшіріледі, тауар рейтингі қайта есептеледі.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Удалить', 'Өшіру'),
                  style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteReview(r.targetId);
      _snack(tr('Отзыв удалён', 'Пікір өшірілді'), cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  /// Стористі модерациялап өшіру (шағым авто-жабылмайды — модератор өзі жабады).
  Future<void> _deleteStory(ReportModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Удалить сторис?', 'Стористі өшіру керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            // «Фото удалится» деп жазылмайды: шағымдағы сурет снапшоты
            // (target_image) 0089 бойынша Cloudinary-ден өшірілмейді.
            tr('Сторис исчезнет у всех покупателей.',
                'Сторис барлық сатып алушыдан жойылады.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Удалить', 'Өшіру'),
                  style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteStory(r.targetId);
      _snack(tr('Сторис удалена', 'Сторис өшірілді'), cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  /// Дүкенді онлайн-блоктау (маркетплейстен жасырылады).
  Future<void> _blockStore(ReportModel r) async {
    final reason = await showRejectReasonSheet(
      context,
      title: tr('Причина блокировки', 'Блоктау себебі'),
      subtitle: r.storeName.isNotEmpty ? r.storeName : r.targetName,
      reasons: [
        tr('Жалобы покупателей', 'Сатып алушылардың шағымдары'),
        tr('Запрещённый контент', 'Тыйым салынған контент'),
        tr('Мошенничество', 'Алаяқтық'),
      ],
    );
    if (reason == null) return;
    try {
      await _storeRepo.blockStore(
          ownerUid: r.adminUid, reason: reason, blockedBy: _uid);
      _snack(tr('Магазин заблокирован', 'Дүкен блокталды'), cGreen);
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: StreamBuilder<List<ReportModel>>(
        stream: _reports,
        builder: (context, snap) {
          final all = snap.data ?? [];
          final newCount = all.where((r) => r.isNew).length;
          final list = _filter(all);

          return Column(children: [
            QGradientHeader(
              title: tr('Жалобы', 'Шағымдар'),
              subtitle: tr('Модерация контента', 'Контент модерациясы'),
              compact: true,
              bottom: [
                const SizedBox(height: 14),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _TabChip(
                          label: tr('Новые ($newCount)', 'Жаңа ($newCount)'),
                          active: _tab == 0,
                          onTap: () => setState(() => _tab = 0)),
                      _TabChip(
                          label: tr(
                              'Все (${all.length})', 'Барлығы (${all.length})'),
                          active: _tab == 1,
                          onTap: () => setState(() => _tab = 1)),
                      _TabChip(
                          label: tr('Обработанные', 'Өңделгендер'),
                          active: _tab == 2,
                          onTap: () => setState(() => _tab = 2)),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: snap.connectionState == ConnectionState.waiting
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: cGreen, strokeWidth: 2))
                  : list.isEmpty
                      ? _empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => ReportCard(
                            report: list[i],
                            onResolve: () => _close(list[i], 'resolved'),
                            onDismiss: () => _close(list[i], 'dismissed'),
                            onDeleteReview: () => _deleteReview(list[i]),
                            onDeleteStory: () => _deleteStory(list[i]),
                            onBlockStore: () => _blockStore(list[i]),
                          ),
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
              child: const Icon(Icons.flag_outlined, color: cGreen, size: 34),
            ),
            const SizedBox(height: 14),
            Text(tr('Жалоб нет', 'Шағым жоқ'),
                style: manrope(16, FontWeight.w700, color: cInk)),
            const SizedBox(height: 4),
            Text(tr('В этой категории пока пусто', 'Бұл санатта әзірге бос'),
                style: manrope(13, FontWeight.w500, color: cInk3)),
          ],
        ),
      );
}

// ── Шағым карточкасы ──────────────────────────────────────────────────────────
/// Бір шағым карточкасы (тест үшін ашық).
class ReportCard extends StatelessWidget {
  final ReportModel report;
  final VoidCallback onResolve;
  final VoidCallback onDismiss;
  final VoidCallback onDeleteReview;
  final VoidCallback onDeleteStory;
  final VoidCallback onBlockStore;
  const ReportCard({
    super.key,
    required this.report,
    required this.onResolve,
    required this.onDismiss,
    required this.onDeleteReview,
    required this.onDeleteStory,
    required this.onBlockStore,
  });

  IconData get _icon {
    switch (report.targetType) {
      case 'store':
        return Icons.storefront_outlined;
      case 'review':
        return Icons.rate_review_outlined;
      case 'question':
        return Icons.help_outline_rounded;
      case 'story':
        return Icons.amp_stories_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  Widget _iconBox() => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(_icon, color: cRed, size: 20),
      );

  Color get _statusColor {
    if (report.isResolved) return cGreen;
    if (report.isDismissed) return cInk3;
    return cAmber;
  }

  String get _statusLabel {
    if (report.isResolved) return tr('Решена', 'Шешілді');
    if (report.isDismissed) return tr('Отклонена', 'Қабылданбады');
    return tr('Новая', 'Жаңа');
  }

  @override
  Widget build(BuildContext context) {
    final date =
        DateFormat('dd.MM.yyyy HH:mm').format(report.createdAt.toLocal());

    return QCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (report.targetImage.isNotEmpty)
            _Thumb(url: report.targetImage, fallback: _icon)
          else
            _iconBox(),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${reportTargetLabel(report.targetType)} · ${reportReasonLabel(report.reason)}',
                    style: manrope(13.5, FontWeight.w800, color: cInk)),
                Text(report.targetName,
                    style: manrope(12.5, FontWeight.w600, color: cInk2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_statusLabel,
                style: manrope(10.5, FontWeight.w800, color: _statusColor)),
          ),
        ]),
        if (report.storeName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.storefront_outlined, size: 14, color: cInk3),
            const SizedBox(width: 5),
            // Flexible: ұзын дүкен атауы тар экранда (320px) Row-дан шықпасын.
            Flexible(
              child: Text(report.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: manrope(12, FontWeight.w600, color: cInk3)),
            ),
          ]),
        ],
        if (report.comment.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(report.comment,
                style: manrope(12.5, FontWeight.w500, color: cInk2)),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${report.reporterName.isNotEmpty ? report.reporterName : tr('Пользователь', 'Қолданушы')}'
          '${report.reporterPhone.isNotEmpty ? ' · ${report.reporterPhone}' : ''} · $date',
          style: manrope(11.5, FontWeight.w500, color: cInk3),
        ),
        if (report.isNew) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _ActionBtn(
              label: tr('Решена', 'Шешілді'),
              icon: Icons.check_rounded,
              color: cGreen,
              onTap: onResolve,
            ),
            _ActionBtn(
              label: tr('Отклонить', 'Қабылдамау'),
              icon: Icons.close_rounded,
              color: cInk2,
              onTap: onDismiss,
            ),
            if (report.isStory)
              _ActionBtn(
                key: const ValueKey('report-delete-story'),
                label: tr('Удалить сторис', 'Стористі өшіру'),
                icon: Icons.delete_outline_rounded,
                color: cRed,
                onTap: onDeleteStory,
              ),
            if (report.targetType == 'review')
              _ActionBtn(
                label: tr('Удалить отзыв', 'Пікірді өшіру'),
                icon: Icons.delete_outline_rounded,
                color: cRed,
                onTap: onDeleteReview,
              ),
            if (report.adminUid.isNotEmpty)
              _ActionBtn(
                label: tr('Блок магазина', 'Дүкенді блоктау'),
                icon: Icons.block_rounded,
                color: cRed,
                onTap: onBlockStore,
              ),
          ]),
        ] else if (report.resolutionNote.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('→ ${report.resolutionNote}',
              style: manrope(12, FontWeight.w600, color: cInk2)),
        ],
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {super.key,
      required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label, style: manrope(12.5, FontWeight.w700, color: color)),
          ]),
        ),
      );
}

// ── Tab chip (shop_requests стилімен бірдей) ──────────────────────────────────
class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(label,
              style: manrope(12.5, FontWeight.w700,
                  color: active ? cGreenDeep : Colors.white)),
        ),
      ),
    );
  }
}

// ── Нысан суретінің кішкентай нұсқасы (сторис 9:16) — басса толық көрінеді ──
class _Thumb extends StatelessWidget {
  final String url;
  final IconData fallback;
  const _Thumb({required this.url, required this.fallback});

  Widget _broken() => Container(
        color: cRed.withValues(alpha: 0.08),
        alignment: Alignment.center,
        child: Icon(fallback, color: cRed, size: 20),
      );

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Фото уже удалено', 'Сурет өшіріліп қойған'),
                      style:
                          manrope(14, FontWeight.w600, color: Colors.white70)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const ValueKey('report-thumb'),
        onTap: () => _preview(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 44,
            height: 66,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 132,
              errorBuilder: (_, __, ___) => _broken(),
            ),
          ),
        ),
      );
}
