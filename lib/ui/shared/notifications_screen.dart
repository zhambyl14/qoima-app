import 'package:flutter/material.dart';
import '../../core/lang.dart';
import '../../core/push_navigation.dart';
import '../../data/services/notifications_service.dart';
import '../../theme/qoima_design.dart';

/// Іштегі хабарламалар (қоңырау зілі) — рөлге тәуелсіз ортақ экран.
/// Тапталған жол handlePushOpen(data)-мен дәл сол push тапталғандай навигация
/// жасайды (data payload пішіні бірдей).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = NotificationsService();
    return Scaffold(
      backgroundColor: cBg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(gradient: kGrad),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('Уведомления', 'Хабарламалар'),
                      style:
                          manrope(20, FontWeight.w800, color: Colors.white)),
                ),
                GestureDetector(
                  onTap: () => service.markAllRead(),
                  child: Text(tr('Прочитать все', 'Барлығын оқу'),
                      style: manrope(12.5, FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.85))),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<NotificationModel>>(
            stream: service.watchNotifications(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: cGreen));
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.notifications_none_rounded,
                        size: 60, color: cInk3.withValues(alpha: 0.35)),
                    const SizedBox(height: 14),
                    Text(tr('Пока нет уведомлений', 'Әзірге хабарлама жоқ'),
                        style: manrope(16, FontWeight.w700, color: cInk2)),
                  ]),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _NotificationTile(
                    key: ValueKey(items[i].id),
                    n: items[i],
                    service: service),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel n;
  final NotificationsService service;
  const _NotificationTile({super.key, required this.n, required this.service});

  Future<void> _open(BuildContext context) async {
    if (n.isUnread) await service.markRead(n.id);
    await handlePushOpen(n.data);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: n.isUnread ? cGreen.withValues(alpha: 0.3) : cLine),
          boxShadow: kShadowSm,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: n.isUnread ? cGreen : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title,
                  style: manrope(
                      14, n.isUnread ? FontWeight.w800 : FontWeight.w700,
                      color: cInk)),
              if (n.body.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(n.body,
                    style: manrope(13, FontWeight.w500, color: cInk2),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 5),
              Text(_relativeTime(n.createdAt),
                  style: manrope(11.5, FontWeight.w600, color: cInk3)),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return tr('Только что', 'Дәл қазір');
    if (diff.inMinutes < 60) {
      return tr('${diff.inMinutes} мин назад', '${diff.inMinutes} мин бұрын');
    }
    if (diff.inHours < 24) {
      return tr('${diff.inHours} ч назад', '${diff.inHours} сағ бұрын');
    }
    if (diff.inDays < 7) {
      return tr('${diff.inDays} дн назад', '${diff.inDays} күн бұрын');
    }
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }
}
