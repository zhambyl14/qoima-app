import 'package:flutter/material.dart';

import '../../../../core/lang.dart';
import '../../../../data/models/description_templates.dart';
import '../../../../theme/qoima_design.dart';
import 'ai_fill_card.dart';

/// Сипаттама өрісінің астындағы «✨ Сипаттаманы AI жазсын» блогы:
///   • сипаттама тілі (RU/ҚАЗ) — UI тілінен БӨЛЕК таңдалады;
///   • AI батырмасы + бүгін қалған саны;
///   • «Үлгілер» чиптері — бір басып дайын мәтін қосады.
/// Блок өзі күй ұстамайды — логика формада (add / edit экрандарында ортақ).
class AiDescriptionAssist extends StatelessWidget {
  /// 'ru' | 'kk' — AI жазатын және үлгілер қосылатын тіл.
  final String lang;
  final ValueChanged<String> onLangChanged;
  final VoidCallback? onWrite;
  final bool busy;
  final int? remaining;
  final List<DescriptionTemplate> templates;
  final ValueChanged<DescriptionTemplate> onInsert;

  /// false болса — AI батырмасы өшік (мыс. сурет те, атау да жоқ).
  final bool canWrite;

  /// AI батырмасын көрсету ме (жалауша өшік болса — тек үлгілер).
  final bool showAi;

  /// «РУС | ҚАЗ» ауыстырғышы осында көрсетілсін бе. Сипаттама өрісінің өзінде
  /// екі тілдік таб болса (BilingualDescriptionField) — false: тіл бір жерде.
  final bool showLangToggle;

  const AiDescriptionAssist({
    super.key,
    required this.lang,
    required this.onLangChanged,
    required this.onWrite,
    required this.busy,
    required this.remaining,
    required this.templates,
    required this.onInsert,
    this.canWrite = true,
    this.showAi = true,
    this.showLangToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    final noQuota = remaining != null && remaining! <= 0;
    final enabled = canWrite && !busy && !noQuota && onWrite != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (showAi) ...[
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: enabled ? onWrite : null,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: enabled || busy ? 1 : 0.5,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: cPurpleTint,
                    borderRadius: BorderRadius.circular(kR14),
                    border: Border.all(color: cPurple.withValues(alpha: 0.4)),
                  ),
                  alignment: Alignment.center,
                  child: busy
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: cPurple, strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text(tr('AI пишет…', 'AI жазып жатыр…'),
                              style: manrope(13, FontWeight.w700,
                                  color: cPurpleInk)),
                        ])
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.auto_awesome_rounded,
                              color: cPurple, size: 17),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                                tr('✨ Описание — пусть напишет AI',
                                    '✨ Сипаттаманы AI жазсын'),
                                overflow: TextOverflow.ellipsis,
                                style: manrope(13, FontWeight.w800,
                                    color: cPurpleInk)),
                          ),
                        ]),
                ),
              ),
            ),
          ),
          if (showLangToggle) ...[
            const SizedBox(width: 8),
            _LangToggle(lang: lang, onChanged: busy ? null : onLangChanged),
          ],
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: AiRemainingText(remaining: remaining)),
        ]),
        if (!canWrite)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
                tr('Добавьте фото или название — тогда AI сможет написать.',
                    'Фото немесе атауын қосыңыз — сонда AI жаза алады.'),
                style: manrope(11, FontWeight.w500, color: cInk3)),
          ),
        const SizedBox(height: 10),
      ],
      Text(tr('Шаблоны — нажмите, чтобы добавить', 'Үлгілер — басып қосыңыз'),
          style: manrope(11.5, FontWeight.w700, color: cInk3)),
      const SizedBox(height: 6),
      SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: templates.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final t = templates[i];
            return GestureDetector(
              onTap: () => onInsert(t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(kRPill),
                  border: Border.all(color: cLine),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.add_rounded, size: 14, color: cGreen),
                  const SizedBox(width: 4),
                  Text(t.title,
                      style: manrope(12, FontWeight.w700, color: cInk2)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _LangToggle extends StatelessWidget {
  final String lang;
  final ValueChanged<String>? onChanged;
  const _LangToggle({required this.lang, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String code, String label) {
      final sel = lang == code;
      return GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(code),
        child: Container(
          width: 46,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? cPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(label,
              style: manrope(12, FontWeight.w800,
                  color: sel ? Colors.white : cInk2)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cLine2,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: cLine),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('ru', 'РУС'),
        seg('kk', 'ҚАЗ'),
      ]),
    );
  }
}

/// Иесінің AI мәтінімен не істейтіні.
enum AiDescriptionChoice { replace, append, retry }

/// «AI мынаны жазды» алдын ала қарау парақшасы. Ешнәрсе автоматты
/// сақталмайды: иесі «Алмастыру» / «Соңына қосу» / «Қайта жазу» таңдайды.
Future<AiDescriptionChoice?> showAiDescriptionPreview(
  BuildContext context, {
  required String text,
  required bool hasExisting,
  required int? remaining,
}) {
  return showModalBottomSheet<AiDescriptionChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: cLine, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: cPurple, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('AI предлагает описание', 'AI сипаттама ұсынады'),
                  style: manrope(16, FontWeight.w800, color: cInk)),
            ),
          ]),
          const SizedBox(height: 10),
          Flexible(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cPurpleTint,
                borderRadius: BorderRadius.circular(kR14),
              ),
              child: SingleChildScrollView(
                child: SelectableText(text,
                    style: manrope(13.5, FontWeight.w500,
                        color: cInk, height: 1.45)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
                tr('Проверьте текст: AI мог ошибиться в деталях. После вставки его можно править.',
                    'Мәтінді тексеріңіз: AI бөлшектерде қателесуі мүмкін. Қосқаннан кейін өңдеуге болады.'),
                style: manrope(11, FontWeight.w500, color: cInk3, height: 1.3)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, AiDescriptionChoice.replace),
              style: ElevatedButton.styleFrom(
                backgroundColor: cGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(kR14)),
              ),
              child: Text(
                  hasExisting
                      ? tr('Заменить моё описание',
                          'Менің сипаттамамды алмастыру')
                      : tr('Вставить в описание', 'Сипаттамаға қою'),
                  style: manrope(14.5, FontWeight.w800, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (hasExisting)
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(ctx, AiDescriptionChoice.append),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cLine),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kR14)),
                    ),
                    child: Text(tr('Добавить в конец', 'Соңына қосу'),
                        style: manrope(13, FontWeight.w700, color: cInk2)),
                  ),
                ),
              ),
            if (hasExisting) const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: (remaining != null && remaining <= 0)
                      ? null
                      : () => Navigator.pop(ctx, AiDescriptionChoice.retry),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cPurple.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kR14)),
                  ),
                  child: Text(tr('Написать заново', 'Қайта жазу'),
                      style: manrope(13, FontWeight.w700, color: cPurpleInk)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Отмена', 'Бас тарту'),
                style: manrope(13, FontWeight.w700, color: cInk3)),
          ),
        ]),
      ),
    ),
  );
}

/// Сипаттамада толтырылмаған «…» қалса — сақтау алдында сұрайды.
/// true = жалғастыру (сақтау), false = қайтып түзету.
Future<bool> confirmUnfilledPlaceholders(
    BuildContext context, String text) async {
  if (!hasUnfilledPlaceholder(text)) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(tr('В описании остались «…»', 'Сипаттамада «…» қалды'),
          style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(
          tr('Вы вставили шаблон, но не заполнили пропуски «…». Покупатели увидят их в описании.',
              'Үлгіні қостыңыз, бірақ «…» орындарын толтырмадыңыз. Сатып алушылар оларды сипаттамада көреді.'),
          style: manrope(13.5, FontWeight.w500, color: cInk2)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Исправить', 'Түзету'))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Сохранить так', 'Солай сақтау'))),
      ],
    ),
  );
  return ok == true;
}
