import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/lang.dart';
import '../../theme/qoima_design.dart';

/// Қайтарымның Казпочта трек-нөмірі: басса көшіріледі (сайтқа апарып тексереді).
/// Клиент, дүкен және сатушы экрандарында бірдей.
class PostTrackingRow extends StatelessWidget {
  final String tracking;
  const PostTrackingRow(this.tracking, {super.key});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Clipboard.setData(ClipboardData(text: tracking));
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(tr('Скопировано', 'Көшірілді')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
            ));
        },
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Text(tr('Трек-номер', 'Трек-нөмір'),
                style: manrope(13, FontWeight.w500, color: cInk2)),
            const Spacer(),
            Flexible(
              child: Text(tracking,
                  style: manrope(13, FontWeight.w700, color: cInk),
                  textAlign: TextAlign.end),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.copy_outlined, size: 14, color: cInk3),
          ]),
        ),
      );
}
