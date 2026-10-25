import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/lang.dart';
import '../../data/services/support_service.dart';
import '../../theme/qoima_design.dart';
import 'support_chat_screen.dart';

/// Профиль мәзіріндегі «Қолдау чаты» жолы (клиент / иесі / сатушы / курьер).
///
/// - Функция өшік болса (feature_support_chat) — жасырын.
/// - Кірген пайдаланушыға оқылмаған жауап саны бейдж болып шығады.
/// - Guest болса бейдж жоқ; басқанда openSupportChat кіруді сұрайды.
class SupportMenuTile extends StatefulWidget {
  const SupportMenuTile({super.key, this.spacing = 8});

  /// Жолдан кейінгі аралық (клиент профилінде мәзір аралығы 10).
  final double spacing;

  @override
  State<SupportMenuTile> createState() => _SupportMenuTileState();
}

class _SupportMenuTileState extends State<SupportMenuTile> {
  StreamSubscription<int>? _sub;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _sub = SupportService().watchMyUnread().listen((n) {
      if (mounted) setState(() => _unread = n);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        if (!FeatureFlags.instance.isOn(FeatureFlags.supportChat)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(bottom: widget.spacing),
          child: QMenuItem(
            icon: Icons.support_agent_rounded,
            tone: 'green',
            title: tr('Чат поддержки', 'Қолдау чаты'),
            subtitle: tr('Написать в Qoima', 'Qoima-ға жазу'),
            badgeCount: _unread,
            onTap: () => openSupportChat(context),
          ),
        );
      },
    );
  }
}

/// Хедердегі «Қолдау» дөңгелек батырмасы (мыс. курьер экраны).
/// Функция өшік болса — жасырын; оқылмаған жауап саны бейдж болады.
class SupportHeaderButton extends StatefulWidget {
  const SupportHeaderButton({super.key});

  @override
  State<SupportHeaderButton> createState() => _SupportHeaderButtonState();
}

class _SupportHeaderButtonState extends State<SupportHeaderButton> {
  StreamSubscription<int>? _sub;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _sub = SupportService().watchMyUnread().listen((n) {
      if (mounted) setState(() => _unread = n);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        if (!FeatureFlags.instance.isOn(FeatureFlags.supportChat)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: QHeaderBtn(Icons.support_agent_rounded,
              badge: _unread, onTap: () => openSupportChat(context)),
        );
      },
    );
  }
}
