import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/lang.dart';
import '../../../../theme/qoima_design.dart';

/// «✨ AI» белгісі — AI толтырған өрістің жанында тұрады. Иесі өрісті өзі
/// өзгертсе, белгі алынады (форма жағы басқарады).
class AiMark extends StatelessWidget {
  const AiMark({super.key});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cPurpleTint,
          borderRadius: BorderRadius.circular(kRPill),
          border: Border.all(color: cPurple.withValues(alpha: 0.35)),
        ),
        child: Text('✨ AI',
            style: manrope(10, FontWeight.w800, color: cPurpleInk)),
      );
}

/// Бүгін қалған AI шақыру саны — кішкентай жол.
class AiRemainingText extends StatelessWidget {
  final int? remaining;
  const AiRemainingText({super.key, required this.remaining});

  @override
  Widget build(BuildContext context) {
    final r = remaining;
    if (r == null) return const SizedBox.shrink();
    return Text(
      r > 0
          ? tr('Сегодня осталось AI-запросов: $r',
              'Бүгін қалған AI сұраулары: $r')
          : tr(
              'Лимит AI на сегодня исчерпан', 'AI-дың бүгінгі лимиті таусылды'),
      style: manrope(11, FontWeight.w600, color: r > 0 ? cInk3 : cRedInk),
    );
  }
}

/// Қосу формасының басындағы «✨ AI көмегі» карточкасы.
///
/// Иесі алдымен тауарды суретке түсіреді, сосын «Суреттен толтыру» басады —
/// AI категория/түр/кімге/түс/сезон/материал/бренд/атауды ұсынады. Нәтиже
/// формаға ТЕК бос өрістерге толтырылады, иесі қарап растайды (өзі ештеңе
/// сақтамайды). Карточка өзі күй ұстамайды — логика формада.
class AiFillCard extends StatelessWidget {
  final List<Uint8List> photos;
  final int maxPhotos;
  final VoidCallback onAddPhotos;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback? onFill;
  final bool busy;
  final int? remaining;

  /// Соңғы толтыруда AI нешінші өрісті толтырды (null — әлі толтырылмаған).
  final int? filledCount;
  final bool lowConfidence;

  /// AI фотодан ештеңе анықтай алмады (фото тауарға ұқсамайды/анық емес).
  final bool unclear;

  const AiFillCard({
    super.key,
    required this.photos,
    required this.maxPhotos,
    required this.onAddPhotos,
    required this.onRemovePhoto,
    required this.onFill,
    this.busy = false,
    this.remaining,
    this.filledCount,
    this.lowConfidence = false,
    this.unclear = false,
  });

  @override
  Widget build(BuildContext context) {
    final noQuota = remaining != null && remaining! <= 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cPurpleTint, Colors.white],
        ),
        borderRadius: BorderRadius.circular(kR16),
        border: Border.all(color: cPurple.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cPurple,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('✨ AI-помощник', '✨ AI көмегі'),
                  style: manrope(14.5, FontWeight.w800, color: cInk)),
              const SizedBox(height: 2),
              Text(
                  tr('Сфотографируйте товар — AI предложит категорию, тип, цвет и название',
                      'Тауарды суретке түсіріңіз — AI категориясын, түрін, түсін және атауын ұсынады'),
                  style: manrope(11.5, FontWeight.w500,
                      color: cInk2, height: 1.3)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 68,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(photos[i],
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          cacheWidth: 200),
                    ),
                    Positioned(
                      top: 3,
                      right: 3,
                      child: GestureDetector(
                        onTap: busy ? null : () => onRemovePhoto(i),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 12),
                        ),
                      ),
                    ),
                  ]),
                ),
              if (photos.length < maxPhotos)
                GestureDetector(
                  onTap: busy ? null : onAddPhotos,
                  child: Container(
                    width: photos.isEmpty ? 150 : 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: cPurple.withValues(alpha: 0.4), width: 1.3),
                    ),
                    child: photos.isEmpty
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                const Icon(Icons.add_a_photo_outlined,
                                    color: cPurple, size: 20),
                                const SizedBox(width: 8),
                                Text(tr('Добавить фото', 'Фото қосу'),
                                    style: manrope(12.5, FontWeight.w700,
                                        color: cPurpleInk)),
                              ])
                        : const Icon(Icons.add_rounded,
                            color: cPurple, size: 24),
                  ),
                ),
            ],
          ),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
              tr('Эти фото сохранятся для первого цвета. Для остальных цветов добавите на шаге «Фото».',
                  'Бұл фотолар бірінші түске сақталады. Басқа түстерге «Фото» қадамында қосасыз.'),
              style: manrope(10.5, FontWeight.w500, color: cInk3)),
          const SizedBox(height: 10),
          _FillButton(
            busy: busy,
            onTap: noQuota ? null : onFill,
          ),
        ],
        if (filledCount != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: lowConfidence ? cAmberTint : cGreenTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unclear
                  ? tr(
                      'AI не смог определить товар по фото — заполните поля вручную или загрузите более чёткое фото.',
                      'AI суреттен тауарды анықтай алмады — өрістерді қолмен толтырыңыз немесе анығырақ сурет жүктеңіз.')
                  : filledCount == 0
                      ? tr('Поля уже заполнены — AI ничего не менял.',
                          'Өрістер толтырылған — AI ештеңе өзгертпеді.')
                      : lowConfidence
                          ? tr(
                              'Фото нечёткое — AI заполнил $filledCount полей неуверенно. Обязательно проверьте отмеченные ✨ AI.',
                              'Фото анық емес — AI $filledCount өрісті сенімсіз толтырды. ✨ AI белгісі бар өрістерді міндетті түрде тексеріңіз.')
                          : tr(
                              'AI заполнил $filledCount полей. Проверьте отмеченные ✨ AI — всё можно изменить.',
                              'AI $filledCount өрісті толтырды. ✨ AI белгісі бар өрістерді тексеріңіз — бәрін өзгертуге болады.'),
              style: manrope(11.5, FontWeight.w700,
                  color: lowConfidence ? cAmberInk : cGreenDeep, height: 1.3),
            ),
          ),
        ],
        const SizedBox(height: 8),
        AiRemainingText(remaining: remaining),
      ]),
    );
  }
}

class _FillButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;
  const _FillButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          height: 46,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cPurple,
            borderRadius: BorderRadius.circular(kR14),
            boxShadow: [
              BoxShadow(
                  color: cPurple.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          alignment: Alignment.center,
          child: busy
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text(tr('AI смотрит фото…', 'AI суретті қарап жатыр…'),
                      style: manrope(14, FontWeight.w700, color: Colors.white)),
                ])
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(tr('Заполнить по фото', 'Суреттен толтыру'),
                      style:
                          manrope(14.5, FontWeight.w800, color: Colors.white)),
                ]),
        ),
      ),
    );
  }
}
