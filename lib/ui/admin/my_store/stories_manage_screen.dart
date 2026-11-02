import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/app_user.dart';
import '../../../core/error_text.dart';
import '../../../core/feature_flags.dart';
import '../../../core/lang.dart';
import '../../../data/models/story_model.dart';
import '../../../data/services/stories_service.dart';
import '../../../theme/qoima_design.dart';
import '../../client/client_product_card.dart' show ClientEmptyState;
import '../../client/stories/story_viewer_screen.dart';
import '../../shared/error_view.dart';
import 'story_crop.dart';

/// Суретті таңдау: камера/галерея → 9:16 кесілген JPEG (бас тартса — null).
typedef StoryPhotoPicker = Future<Uint8List?> Function(ImageSource source);

/// Әдепкі таңдағыш: image_picker (сапа ~85, ені ≤ 1440) + авто-кесу 9:16.
Future<Uint8List?> pickAndCropStoryPhoto(ImageSource source) async {
  final file = await ImagePicker()
      .pickImage(source: source, imageQuality: 85, maxWidth: 1440);
  if (file == null) return null;
  final raw = await file.readAsBytes();
  final cropped = await autoStoryCropAsync(raw);
  if (cropped == null) {
    // Оқылмайтын формат — friendlyError емес, түсінікті мәтін.
    throw Exception(tr('Не удалось обработать это фото. Выберите другое.',
        'Бұл суретті өңдеу мүмкін болмады. Басқасын таңдаңыз.'));
  }
  return cropped;
}

/// Дүкен иесінің «Сторис» беті (0084): белсенді стористер торы (қалған уақыт,
/// өшіру), «Қосу» → фото → превью + жазу → жүктеу. Бір мезетте ≤ 10 сторис.
class StoriesManageScreen extends StatefulWidget {
  /// Тек тест үшін.
  final StoriesService? service;
  final StoryPhotoPicker? picker;
  final String? storeUid;
  const StoriesManageScreen(
      {super.key, this.service, this.picker, this.storeUid});

  @override
  State<StoriesManageScreen> createState() => _StoriesManageScreenState();
}

class _StoriesManageScreenState extends State<StoriesManageScreen> {
  late final StoriesService _svc = widget.service ?? StoriesService();
  String get _storeUid => widget.storeUid ?? AppUser.current.ownerUid;

  List<StoryModel>? _items;
  Object? _error;
  bool _busy = false; // фото таңдалып/кесіліп жатыр
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // «Қалған уақыт» жаңарсын, мерзімі өткен тақтайша өздігінен кетсін.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() => _items = _items?.where((s) => !s.isExpired).toList());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _svc.storiesForStore(_storeUid);
      if (mounted) {
        setState(() {
          _items = list.where((s) => !s.isExpired).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _items == null) setState(() => _error = e);
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? cRed : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Лимит хабары — сервердің stories_limit қатесімен бірдей мәтін.
  String _limitText() =>
      friendlyError(const PostgrestException(message: 'stories_limit'));

  int get _count => _items?.length ?? 0;
  bool get _atLimit => _count >= StoryModel.maxActivePerStore;

  Future<void> _add() async {
    if (_busy) return;
    if (_atLimit) {
      _toast(_limitText(), error: true);
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: cSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('pick-camera'),
            leading: const Icon(Icons.photo_camera_outlined, color: cGreen),
            title: Text(tr('Камера', 'Камера'),
                style: manrope(15, FontWeight.w700, color: cInk)),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            key: const ValueKey('pick-gallery'),
            leading: const Icon(Icons.photo_library_outlined, color: cGreen),
            title: Text(tr('Галерея', 'Галерея'),
                style: manrope(15, FontWeight.w700, color: cInk)),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    Uint8List? bytes;
    try {
      bytes = await (widget.picker ?? pickAndCropStoryPhoto)(source);
    } catch (e) {
      // Камераға рұқсат берілмесе де осында түседі.
      if (mounted) _toast(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (bytes == null || !mounted) return;
    final created = await Navigator.of(context).push<StoryModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryComposeScreen(bytes: bytes!, service: _svc),
      ),
    );
    if (created != null && mounted) {
      setState(() => _items = [...?_items, created]);
      _toast(
          tr('Сторис опубликован на 24 часа', 'Сторис 24 сағатқа жарияланды'));
    }
  }

  Future<void> _delete(StoryModel s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Удалить сторис?', 'Стористі өшіру керек пе?'),
            style: manrope(16, FontWeight.w800, color: cInk)),
        content: Text(
            tr('Он сразу пропадёт у клиентов. Отменить нельзя.',
                'Ол клиенттерден бірден жоғалады. Қайтару мүмкін емес.'),
            style: manrope(13.5, FontWeight.w500, color: cInk2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена', 'Болдырмау'),
                  style: manrope(14, FontWeight.w600, color: cInk2))),
          TextButton(
              key: const ValueKey('confirm-delete'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Удалить', 'Өшіру'),
                  style: manrope(14, FontWeight.w700, color: cRed))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _svc.delete(s.id);
      if (mounted) {
        setState(() => _items = _items?.where((e) => e.id != s.id).toList());
      }
    } catch (e) {
      if (mounted) _toast(friendlyError(e), error: true);
    }
  }

  Future<void> _preview(int index) async {
    final list = _items;
    if (list == null || index >= list.length) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StoryViewerScreen(
        groups: [
          StoryViewerGroup(
            storeUid: _storeUid,
            storeName: tr('Ваш магазин', 'Сіздің дүкеніңіз'),
            stories: list.sublist(index),
          ),
        ],
        service: widget.service,
      ),
    ));
  }

  String _left(Duration d) {
    if (d.inMinutes < 60) {
      final m = d.inMinutes < 1 ? 1 : d.inMinutes;
      return tr('ещё $m мин', '$m мин қалды');
    }
    return tr('ещё ${d.inHours} ч', '${d.inHours} сағ қалды');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: ListenableBuilder(
        listenable: FeatureFlags.instance,
        builder: (_, __) => Column(children: [
          QGradientHeader(
            title: tr('Сторис', 'Сторис'),
            subtitle: tr('Фото на 24 часа для подписчиков',
                'Жазылушыларға 24 сағаттық фото'),
            showBack: true,
            compact: true,
          ),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (!FeatureFlags.instance.isOn(FeatureFlags.stories)) {
      return ClientEmptyState(
          icon: Icons.history_toggle_off_rounded,
          message: tr('Функция временно отключена', 'Функция уақытша өшірулі'));
    }
    if (_error != null && _items == null) {
      return AppErrorView(
          error: _error,
          onRetry: () async {
            setState(() => _error = null);
            await _load();
          });
    }
    final items = _items;
    if (items == null) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Row(children: [
          Expanded(
            child: Text(
                tr('Активных: $_count из ${StoryModel.maxActivePerStore}',
                    'Белсенді: $_count / ${StoryModel.maxActivePerStore}'),
                key: const ValueKey('stories-count'),
                style: manrope(13.5, FontWeight.w700, color: cInk2)),
          ),
        ]),
      ),
      if (_atLimit)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Container(
            key: const ValueKey('stories-limit-note'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cAmberTint, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: cAmberInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_limitText(),
                    style: manrope(12.5, FontWeight.w600,
                        color: cAmberInk, height: 1.35)),
              ),
            ]),
          ),
        ),
      Expanded(
        child: RefreshIndicator(
          color: cGreen,
          onRefresh: _load,
          child: items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: 300,
                      child: ClientEmptyState(
                          icon: Icons.add_a_photo_outlined,
                          message: tr(
                              'Пока нет сторис. Добавьте фото — оно будет видно подписчикам 24 часа.',
                              'Әзірге сторис жоқ. Фото қосыңыз — жазылушыларға 24 сағат көрінеді.')),
                    ),
                  ],
                )
              : GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 9 / 16,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _tile(items[i], i),
                ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: QPrimaryButton(
            label: tr('Добавить', 'Қосу'),
            icon: const Icon(Icons.add_a_photo_outlined,
                color: Colors.white, size: 18),
            isLoading: _busy,
            onPressed: _add,
          ),
        ),
      ),
    ]);
  }

  Widget _tile(StoryModel s, int i) {
    return ClipRRect(
      key: ValueKey('tile-${s.id}'),
      borderRadius: BorderRadius.circular(kR16),
      child: GestureDetector(
        onTap: () => _preview(i),
        child: Stack(fit: StackFit.expand, children: [
          Image.network(s.imageUrl,
              fit: BoxFit.cover,
              cacheWidth: 360,
              errorBuilder: (_, __, ___) => Container(
                  color: cLine2,
                  child:
                      const Icon(Icons.broken_image_outlined, color: cInk3))),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x99000000)],
                stops: [0.55, 1],
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              key: ValueKey('delete-${s.id}'),
              onTap: () => _delete(s),
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                    color: Color(0x99000000), shape: BoxShape.circle),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.white, size: 17),
              ),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Text(_left(s.remaining),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: manrope(11, FontWeight.w700, color: Colors.white)),
          ),
        ]),
      ),
    );
  }
}

/// Превью + жазу + жариялау. Сәтті болса жаңа [StoryModel]-мен жабылады.
/// Жүктеу кезінде экран бұғатталады; қате болса — осында қалады (қайталауға).
class StoryComposeScreen extends StatefulWidget {
  final Uint8List bytes;
  final StoriesService service;
  const StoryComposeScreen(
      {super.key, required this.bytes, required this.service});

  @override
  State<StoryComposeScreen> createState() => _StoryComposeScreenState();
}

class _StoryComposeScreenState extends State<StoryComposeScreen> {
  final _caption = TextEditingController();
  bool _uploading = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_uploading) return;
    FocusScope.of(context).unfocus();
    setState(() => _uploading = true);
    try {
      final created = await widget.service
          .create(imageBytes: widget.bytes, caption: _caption.text);
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: cRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_uploading, // жүктеліп жатқанда кездейсоқ жабылмасын
      child: Scaffold(
        backgroundColor: cBg,
        appBar: AppBar(
          backgroundColor: cBg,
          elevation: 0,
          iconTheme: const IconThemeData(color: cInk),
          title: Text(tr('Новый сторис', 'Жаңа сторис'),
              style: manrope(17, FontWeight.w800, color: cInk)),
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(kR16),
                          child: Image.memory(widget.bytes,
                              key: const ValueKey('compose-preview'),
                              fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('compose-caption'),
                    controller: _caption,
                    enabled: !_uploading,
                    maxLength: StoryModel.maxCaption,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText:
                          tr('Подпись (необязательно)', 'Жазу (міндетті емес)'),
                    ),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_uploading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      const Expanded(
                        child: LinearProgressIndicator(
                          key: ValueKey('compose-progress'),
                          color: cGreen,
                          backgroundColor: cLine,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(tr('Загрузка…', 'Жүктелуде…'),
                          style: manrope(12.5, FontWeight.w700, color: cInk2)),
                    ]),
                  ),
                QPrimaryButton(
                  label: tr('Опубликовать', 'Жариялау'),
                  isLoading: _uploading,
                  onPressed: _publish,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
