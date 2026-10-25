import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../data/models/support_models.dart';
import '../../data/services/support_service.dart';
import '../../theme/qoima_design.dart';
import '../shared/photo_gallery_viewer.dart';

/// Қолдау чатының ортақ денесі: хабарлама тізімі + жазу жолағы.
///
/// Пайдаланушы да, модератор да осыны қолданады — айырмасы тек [asStaff]
/// (қай көпіршік «менікі») және [onSend] (support_send не support_reply).
/// [threadId] null болса (пайдаланушы әлі жазбаған) — [emptyState] көрінеді,
/// бірінші хабарламадан кейін ата-ана жаңа id береді де, ағын қосылады.
class SupportConversationView extends StatefulWidget {
  final String? threadId;
  final bool asStaff;
  final Future<void> Function(String body, String? imageUrl) onSend;
  final Widget? emptyState;
  final TextEditingController? controller;
  final bool enabled;
  final String? disabledHint;

  const SupportConversationView({
    super.key,
    required this.threadId,
    required this.asStaff,
    required this.onSend,
    this.emptyState,
    this.controller,
    this.enabled = true,
    this.disabledHint,
  });

  @override
  State<SupportConversationView> createState() =>
      _SupportConversationViewState();
}

class _SupportConversationViewState extends State<SupportConversationView> {
  final _service = SupportService();
  final _scroll = ScrollController();
  late final TextEditingController _text =
      widget.controller ?? TextEditingController();
  StreamSubscription<List<SupportMessage>>? _sub;
  List<SupportMessage> _messages = const [];
  bool _loading = false;
  Object? _error;
  bool _sending = false;
  XFile? _pendingFile;
  Uint8List? _pendingBytes;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant SupportConversationView old) {
    super.didUpdateWidget(old);
    if (old.threadId != widget.threadId) _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    if (widget.controller == null) _text.dispose();
    super.dispose();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = null;
    final id = widget.threadId;
    if (id == null || id.isEmpty) {
      setState(() {
        _messages = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = _messages.isEmpty);
    _sub = _service.watchMessages(id).listen((list) {
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
      });
      _scrollToEnd();
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      // reverse:true тізімде «соңы» — 0 позициясы.
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: cSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: cLine, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            QMenuItem(
              icon: Icons.photo_camera_outlined,
              tone: 'green',
              title: tr('Камера', 'Камера'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
            QMenuItem(
              icon: Icons.photo_library_outlined,
              tone: 'blue',
              title: tr('Галерея', 'Галерея'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ]),
        ),
      ),
    );
    if (src == null) return;
    try {
      final file = await ImagePicker()
          .pickImage(source: src, imageQuality: 85, maxWidth: 1600);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingFile = file;
        _pendingBytes = bytes;
      });
    } catch (e) {
      _snack(friendlyError(e), cRed);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (_sending) return;
    if (body.isEmpty && _pendingFile == null) return;
    if (body.length > 2000) {
      _snack(
          tr('Сообщение слишком длинное (до 2000 символов).',
              'Хабарлама тым ұзын (2000 таңбаға дейін).'),
          cRed);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      String? url;
      if (_pendingFile != null) {
        url = await _service.uploadImage(_pendingFile!);
      }
      await widget.onSend(body, url);
      if (!mounted) return;
      _text.clear();
      setState(() {
        _pendingFile = null;
        _pendingBytes = null;
      });
      _scrollToEnd();
    } catch (e) {
      _snack(friendlyError(e), cRed);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: _buildBody()),
      if (widget.enabled)
        _Composer(
          controller: _text,
          sending: _sending,
          pendingBytes: _pendingBytes,
          onRemovePhoto: () => setState(() {
            _pendingFile = null;
            _pendingBytes = null;
          }),
          onPickPhoto: _pickPhoto,
          onSend: _send,
        )
      else if (widget.disabledHint != null)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Text(widget.disabledHint!,
                textAlign: TextAlign.center,
                style: manrope(12.5, FontWeight.w600, color: cInk3)),
          ),
        ),
    ]);
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: cGreen, strokeWidth: 2));
    }
    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(friendlyError(_error),
              textAlign: TextAlign.center,
              style: manrope(13, FontWeight.w600, color: cInk3)),
        ),
      );
    }
    if (_messages.isEmpty) {
      return widget.emptyState ?? const SizedBox.shrink();
    }
    // reverse:true — жаңа хабарлама төменде, пернетақта ашылғанда да
    // соңғы хабарлама көрініп тұрады.
    final items = _messages.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final m = items[i];
        final older = i + 1 < items.length ? items[i + 1] : null;
        final showDay =
            older == null || !_sameDay(older.createdAt, m.createdAt);
        return Column(children: [
          if (showDay) _DaySeparator(date: m.createdAt),
          SupportBubble(message: m, mine: m.isStaff == widget.asStaff),
        ]);
      },
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _two(int v) => v.toString().padLeft(2, '0');

/// «14:05» — хабарлама уақыты.
String supportTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Тізімдегі қысқа уақыт: бүгін — сағат, әйтпесе күн.ай.
String supportShortDate(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  if (_sameDay(d, now)) return supportTime(d);
  if (_sameDay(d, now.subtract(const Duration(days: 1)))) {
    return tr('Вчера', 'Кеше');
  }
  return '${_two(d.day)}.${_two(d.month)}';
}

class _DaySeparator extends StatelessWidget {
  final DateTime date;
  const _DaySeparator({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = _sameDay(date, now)
        ? tr('Сегодня', 'Бүгін')
        : _sameDay(date, now.subtract(const Duration(days: 1)))
            ? tr('Вчера', 'Кеше')
            : '${_two(date.day)}.${_two(date.month)}.${date.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: cLine2, borderRadius: BorderRadius.circular(kRPill)),
          child: Text(label, style: manrope(11, FontWeight.w700, color: cInk3)),
        ),
      ),
    );
  }
}

/// Бір хабарлама көпіршігі. [mine] — оң жақта, жасыл.
class SupportBubble extends StatelessWidget {
  final SupportMessage message;
  final bool mine;
  const SupportBubble({super.key, required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final m = message;
    final bg = mine ? cGreen : cSurface;
    final fg = mine ? Colors.white : cInk;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: mine ? null : Border.all(color: cLine),
            boxShadow: kShadowXs,
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!mine && m.isStaff)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(tr('Поддержка Qoima', 'Qoima қолдауы'),
                      style: manrope(11, FontWeight.w800, color: cGreenDeep)),
                ),
              if (m.hasImage)
                Padding(
                  padding: EdgeInsets.only(bottom: m.body.isEmpty ? 2 : 6),
                  child: GestureDetector(
                    onTap: () => openPhotoGallery(context,
                        images: [m.imageUrl], heroTagPrefix: 'support_${m.id}'),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        m.imageUrl,
                        width: 220,
                        height: 220,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 220,
                          height: 120,
                          color: cLine2,
                          child: const Icon(Icons.broken_image_outlined,
                              color: cInk3),
                        ),
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : Container(
                                width: 220,
                                height: 220,
                                color: mine
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : cLine2,
                                child: const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: cGreen)),
                              ),
                      ),
                    ),
                  ),
                ),
              if (m.body.isNotEmpty)
                SelectableText(m.body,
                    style:
                        manrope(14, FontWeight.w500, color: fg, height: 1.35)),
              const SizedBox(height: 2),
              Text(supportTime(m.createdAt),
                  style: manrope(10.5, FontWeight.w600,
                      color:
                          mine ? Colors.white.withValues(alpha: 0.8) : cInk3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final Uint8List? pendingBytes;
  final VoidCallback onRemovePhoto;
  final VoidCallback onPickPhoto;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.pendingBytes,
    required this.onRemovePhoto,
    required this.onPickPhoto,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: cSurface,
        border: Border(top: BorderSide(color: cLine)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (pendingBytes != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 4),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(pendingBytes!,
                          width: 72, height: 72, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: sending ? null : onRemovePhoto,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: cInk,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                tooltip: tr('Прикрепить фото', 'Сурет тіркеу'),
                onPressed: sending ? null : onPickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined,
                    color: cInk2),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  style: manrope(14, FontWeight.w500, color: cInk),
                  decoration: InputDecoration(
                    hintText: tr('Сообщение…', 'Хабарлама…'),
                    hintStyle: manrope(14, FontWeight.w500, color: cInk3),
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: cBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: cLine),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: cLine),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: cGreen),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: cGreen,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: sending ? null : onSend,
                    child: Center(
                      child: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Рөлдің адамша атауы (сүзгі чиптері мен ақпарат карточкасы үшін).
String supportRoleLabel(String role) {
  switch (role) {
    case SupportThread.roleAdmin:
      return tr('Владелец магазина', 'Дүкен иесі');
    case SupportThread.roleSeller:
      return tr('Продавец', 'Сатушы');
    case SupportThread.roleCourier:
      return tr('Курьер', 'Курьер');
    default:
      return tr('Покупатель', 'Сатып алушы');
  }
}

/// Рөлге сәйкес түс тоны (QPill/QIconTile).
String supportRoleTone(String role) {
  switch (role) {
    case SupportThread.roleAdmin:
    case SupportThread.roleSeller:
      return 'blue';
    case SupportThread.roleCourier:
      return 'amber';
    default:
      return 'green';
  }
}

IconData supportRoleIcon(String role) {
  switch (role) {
    case SupportThread.roleAdmin:
    case SupportThread.roleSeller:
      return Icons.storefront_outlined;
    case SupportThread.roleCourier:
      return Icons.delivery_dining_outlined;
    default:
      return Icons.person_outline_rounded;
  }
}
