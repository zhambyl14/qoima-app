import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';

/// Функция әлі қосылмаған кездегі жұмсақ күй: «Скоро будет доступно».
///
/// Сатып алушыға функция НЕГЕ жұмыс істемейтінін (жалауша, кілт, провайдер)
/// түсіндірмейміз — тек жақында болатынын айтамыз. Қате емес, сондықтан қызыл
/// түс те, «қайталау» батырмасы да жоқ. Кіру нүктесі әдетте жасырылады; бұл
/// виджет deep link/push арқылы жеткен экрандарға ғана керек.
class ComingSoonView extends StatelessWidget {
  final IconData icon;

  const ComingSoonView({super.key, this.icon = Icons.auto_awesome_rounded});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF2FDF8), cGreenTint],
                ),
              ),
              child:
                  Icon(icon, size: 40, color: cGreen.withValues(alpha: 0.75)),
            ),
            const SizedBox(height: 16),
            Text(comingSoonText(),
                textAlign: TextAlign.center,
                style: manrope(16, FontWeight.w800, color: cInk)),
            const SizedBox(height: 6),
            Text(
                tr('Мы уже работаем над этим — загляните позже',
                    'Біз бұған дайындалып жатырмыз — кейінірек кіріңіз'),
                textAlign: TextAlign.center,
                style: manrope(13.5, FontWeight.w500, color: cInk2)),
          ]),
        ),
      );
}
