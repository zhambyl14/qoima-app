import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/error_text.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/store_model.dart';
import '../../../data/services/ai_service.dart';
import '../../../theme/qoima_design.dart';
import '../../shared/require_login.dart';

enum _Step { pick, generating, result }

/// Онлайн киіп көру: клиент суретін жүктейді → сервер (FASHN) киімді кигізеді.
/// Адам суреті ешқайда сақталмайды (сервер жадында ғана өтеді).
class TryOnScreen extends StatefulWidget {
  final ProductModel product;
  final StoreModel store;

  const TryOnScreen({super.key, required this.product, required this.store});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  static const _maxBytes = 4 * 1024 * 1024;

  final _ai = AiService();
  final _picker = ImagePicker();
  final _shareKey = GlobalKey();

  _Step _step = _Step.pick;
  int _garmentIndex = 0;
  Uint8List? _person;
  TryOnResult? _result;
  bool _showAfter = true;
  bool _sharing = false;
  int? _remaining;
  String? _error;

  Timer? _ticker;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadQuota() async {
    final r = await _ai.quotaRemaining('tryon');
    if (!mounted) return;
    setState(() => _remaining = r);
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? cRed : cGreen,
        content: Text(msg),
      ));
  }

  Future<void> _pick(ImageSource source) async {
    HapticFeedback.selectionClick();
    try {
      final f = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      if (bytes.length > _maxBytes) {
        _snack(
            tr('Фото слишком большое, выберите другое',
                'Сурет тым үлкен, басқасын таңдаңыз'),
            error: true);
        return;
      }
      setState(() {
        _person = bytes;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(friendlyError(e), error: true);
    }
  }

  Future<void> _generate() async {
    final person = _person;
    if (person == null) return;
    final ok = await requireLogin(
      context,
      reasonRu: 'Войдите, чтобы примерить одежду онлайн',
      reasonKk: 'Киімді онлайн киіп көру үшін кіріңіз',
    );
    if (!ok || !mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _step = _Step.generating;
      _elapsed = 0;
      _error = null;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
    });
    try {
      final r =
          await _ai.virtualTryOn(widget.product.id, _garmentIndex, person);
      if (!mounted) return;
      _ticker?.cancel();
      setState(() {
        _result = r;
        _remaining = r.remaining ?? _remaining;
        _showAfter = true;
        _step = _Step.result;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      _ticker?.cancel();
      setState(() {
        _step = _Step.pick;
        _error = e.message;
      });
      if (e.isQuota) _remaining = 0;
    } catch (e) {
      if (!mounted) return;
      _ticker?.cancel();
      setState(() {
        _step = _Step.pick;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _share() async {
    final r = _result;
    if (r == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final res = await http
          .get(Uri.parse(r.imageUrl))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('download ${res.statusCode}');
      Rect? origin;
      final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        origin = box.localToGlobal(Offset.zero) & box.size;
      }
      await Share.shareXFiles(
        [
          XFile.fromData(res.bodyBytes,
              mimeType: 'image/jpeg', name: 'qoima-tryon.jpg')
        ],
        fileNameOverrides: const ['qoima-tryon.jpg'],
        text: '${widget.product.name} · Qoima',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (mounted) _snack(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _anotherPhoto() {
    setState(() {
      _person = null;
      _result = null;
      _step = _Step.pick;
      _error = null;
    });
    _loadQuota();
  }

  String get _progressText {
    if (_elapsed < 8) {
      return tr('Анализируем ваше фото…', 'Суретіңізді талдап жатырмыз…');
    }
    if (_elapsed < 18) {
      return tr('Подбираем посадку…', 'Киімнің сәйкестігін таңдап жатырмыз…');
    }
    if (_elapsed < 32) {
      return tr('Дорисовываем детали…', 'Бөлшектерін әрлеп жатырмыз…');
    }
    return tr('Почти готово, ещё чуть-чуть…', 'Дайын болып қалды…');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FeatureFlags.instance,
      builder: (context, _) {
        final on = FeatureFlags.instance.isOn(FeatureFlags.aiTryOn);
        return Scaffold(
          backgroundColor: cBg,
          body: Column(children: [
            QGradientHeader(
              title: tr('Онлайн-примерка', 'Онлайн киіп көру'),
              subtitle: widget.product.name,
              showBack: true,
            ),
            Expanded(
              child: !on
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          tr('Функция временно отключена',
                              'Функция уақытша өшірулі'),
                          textAlign: TextAlign.center,
                          style: manrope(15, FontWeight.w600, color: cInk2),
                        ),
                      ),
                    )
                  : switch (_step) {
                      _Step.pick => _buildPick(),
                      _Step.generating => _buildGenerating(),
                      _Step.result => _buildResult(),
                    },
            ),
          ]),
          bottomNavigationBar: on && _step == _Step.pick
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: QPrimaryButton(
                      label: tr('Создать примерку', 'Киіп көруді бастау'),
                      icon: const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 18),
                      onPressed: (_person == null || _remaining == 0)
                          ? null
                          : _generate,
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  // ── 1) Таңдау қадамы ──────────────────────────────────────────────────────
  Widget _buildPick() {
    final images = widget.product.images;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cRedTint,
              borderRadius: BorderRadius.circular(kR14),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline_rounded, color: cRedInk, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: manrope(13, FontWeight.w600, color: cRedInk)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],

        // Киім суретін таңдау
        QSecLabel(tr('Что примеряем', 'Нені киіп көреміз')),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final sel = i == _garmentIndex;
              return GestureDetector(
                onTap: () => setState(() => _garmentIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kR14),
                    border: Border.all(
                        color: sel ? cGreen : cLine, width: sel ? 2 : 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(kR12),
                    child: Image.network(images[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const ColoredBox(color: cLine2)),
                  ),
                ),
              );
            },
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 6),
          Text(
            tr('Выберите фото, где одежда видна лучше всего',
                'Киім анық көрінетін суретті таңдаңыз'),
            style: manrope(12, FontWeight.w500, color: cInk3),
          ),
        ],
        const SizedBox(height: 18),

        // Сіздің суретіңіз
        QSecLabel(tr('Ваше фото', 'Сіздің суретіңіз')),
        const SizedBox(height: 8),
        if (_person == null)
          QCard(
            child: Column(children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: cGreenTint, shape: BoxShape.circle),
                child: const Icon(Icons.person_outline_rounded,
                    color: cGreenDeep, size: 32),
              ),
              const SizedBox(height: 12),
              _tip(tr('Фото в полный рост, стоя прямо',
                  'Толық бойымен, түзу тұрып түскен сурет')),
              _tip(tr('Хорошее освещение, лицо и руки видны',
                  'Жарық жақсы, бет пен қол көрінсін')),
              _tip(tr('Однотонный фон, одежда не мешает',
                  'Фоны қарапайым, артық киім болмасын')),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: QSoftButton(
                    label: tr('Камера', 'Камера'),
                    icon: const Icon(Icons.photo_camera_outlined),
                    onPressed: () => _pick(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: QSoftButton(
                    label: tr('Галерея', 'Галерея'),
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: () => _pick(ImageSource.gallery),
                  ),
                ),
              ]),
            ]),
          )
        else
          Column(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(kR20),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Image.memory(_person!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: QSoftButton(
                  label: tr('Камера', 'Камера'),
                  icon: const Icon(Icons.photo_camera_outlined),
                  tone: 'gray',
                  onPressed: () => _pick(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: QSoftButton(
                  label: tr('Галерея', 'Галерея'),
                  icon: const Icon(Icons.photo_library_outlined),
                  tone: 'gray',
                  onPressed: () => _pick(ImageSource.gallery),
                ),
              ),
            ]),
          ]),
        const SizedBox(height: 14),

        // Құпиялылық
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cBlueTint,
            borderRadius: BorderRadius.circular(kR14),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_outline_rounded, color: cBlueInk, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('Ваше фото не сохраняется: оно используется только для примерки и сразу удаляется.',
                    'Суретіңіз сақталмайды: тек киіп көру үшін қолданылады да, бірден өшіріледі.'),
                style: manrope(12.5, FontWeight.w600,
                    color: cBlueInk, height: 1.35),
              ),
            ),
          ]),
        ),
        if (_remaining != null) ...[
          const SizedBox(height: 12),
          Center(
            child: QPill(
              _remaining == 0
                  ? tr('Лимит на сегодня исчерпан', 'Бүгінгі лимит бітті')
                  : tr('Осталось попыток сегодня: $_remaining',
                      'Бүгін қалған әрекет: $_remaining'),
              tone: _remaining == 0 ? 'red' : 'green',
              icon: const Icon(Icons.auto_awesome, size: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tip(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.check_circle_rounded, color: cGreen, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: manrope(13, FontWeight.w500, color: cInk2, height: 1.3)),
          ),
        ]),
      );

  // ── 2) Күту қадамы ────────────────────────────────────────────────────────
  Widget _buildGenerating() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_person != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(kR20),
              child: SizedBox(
                width: 180,
                height: 240,
                child: Stack(fit: StackFit.expand, children: [
                  Image.memory(_person!, fit: BoxFit.cover),
                  Container(color: Colors.white.withValues(alpha: 0.35)),
                  const Center(
                    child: CircularProgressIndicator(
                        color: cGreen, strokeWidth: 3),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 22),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _progressText,
              key: ValueKey(_progressText),
              textAlign: TextAlign.center,
              style: manrope(16, FontWeight.w800, color: cInk),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Обычно это занимает 20–40 секунд', 'Әдетте 20–40 секунд алады'),
            style: manrope(13, FontWeight.w500, color: cInk3),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kRPill),
              child: LinearProgressIndicator(
                value: (_elapsed / 45).clamp(0.05, 0.95),
                minHeight: 6,
                color: cGreen,
                backgroundColor: cGreenTint,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 3) Нәтиже ─────────────────────────────────────────────────────────────
  Widget _buildResult() {
    final r = _result!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kR24),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(
                color: cLine2,
                child: _showAfter
                    ? Image.network(
                        r.imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : const Center(
                                child: CircularProgressIndicator(
                                    color: cGreen, strokeWidth: 2)),
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                              tr('Не удалось загрузить результат',
                                  'Нәтиже жүктелмеді'),
                              style:
                                  manrope(13, FontWeight.w600, color: cInk3)),
                        ),
                      )
                    : Image.memory(_person!, fit: BoxFit.cover),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: QPill(
                  _showAfter
                      ? tr('С примеркой', 'Киіп көргенде')
                      : tr('Исходное фото', 'Түпнұсқа сурет'),
                  tone: _showAfter ? 'green' : 'gray',
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        // До / После
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: cLine2,
            borderRadius: BorderRadius.circular(kR14),
          ),
          child: Row(children: [
            _seg(tr('До', 'Дейін'), !_showAfter,
                () => setState(() => _showAfter = false)),
            _seg(tr('После', 'Кейін'), _showAfter,
                () => setState(() => _showAfter = true)),
          ]),
        ),
        const SizedBox(height: 14),
        KeyedSubtree(
          key: _shareKey,
          child: QPrimaryButton(
            label: tr('Поделиться', 'Бөлісу'),
            icon: const Icon(Icons.ios_share_rounded,
                color: Colors.white, size: 18),
            isLoading: _sharing,
            onPressed: _share,
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: QSoftButton(
              label: tr('Другое фото', 'Басқа сурет'),
              icon: const Icon(Icons.refresh_rounded),
              tone: 'gray',
              onPressed: _anotherPhoto,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: QSoftButton(
              label: tr('К товару', 'Тауарға'),
              icon: const Icon(Icons.shopping_bag_outlined),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          tr('Результат создан ИИ и приблизителен: реальная посадка может отличаться.',
              'Нәтижені жасанды интеллект жасады, шамамен ғана: нақты отыруы өзгеше болуы мүмкін.'),
          textAlign: TextAlign.center,
          style: manrope(11.5, FontWeight.w500, color: cInk3, height: 1.35),
        ),
        if (_remaining != null) ...[
          const SizedBox(height: 8),
          Text(
            tr('Осталось попыток сегодня: $_remaining',
                'Бүгін қалған әрекет: $_remaining'),
            textAlign: TextAlign.center,
            style: manrope(12, FontWeight.w600, color: cInk2),
          ),
        ],
      ],
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? cSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(kR12),
              boxShadow: selected ? kShadowXs : null,
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: manrope(13.5, FontWeight.w700,
                    color: selected ? cInk : cInk3)),
          ),
        ),
      );
}
