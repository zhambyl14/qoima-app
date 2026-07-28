import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/lang.dart';
import '../../theme/qoima_design.dart';

/// Экран ішіндегі қате күйі: түсінікті мәтін + «Қайталау» батырмасы.
///
/// Бұрын экрандар қате орнына шикі техникалық мәтінді көрсететін де,
/// пайдаланушыға шығар жол қалмайтын (батырма жоқ). Мұнда екеуі де шешілген:
/// мәтін [friendlyError] арқылы аударылады, [onRetry] берілсе — қайталау
/// батырмасы шығады.
class AppErrorView extends StatelessWidget {
  /// Шикі қате нысаны (мәтінге өзі айналады). [message] берілсе — елеусіз.
  final Object? error;

  /// Дайын мәтін (қате нысаны жоқ жағдайда).
  final String? message;

  /// Қайталау әрекеті (null болса — батырма көрсетілмейді).
  final Future<void> Function()? onRetry;

  /// Компакт нұсқа (карточка/тізім ішінде) — кішірек шрифт/иконка.
  final bool compact;

  const AppErrorView({
    super.key,
    this.error,
    this.message,
    this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isNet = message == null && isNetworkError(error);
    final text = message ?? friendlyError(error);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32, vertical: compact ? 16 : 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: compact ? 56 : 72,
              height: compact ? 56 : 72,
              decoration: BoxDecoration(
                color: isNet ? cAmberTint : cRedTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isNet ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                size: compact ? 28 : 34,
                color: isNet ? cAmber : cRed,
              ),
            ),
            SizedBox(height: compact ? 12 : 18),
            Text(
              isNet
                  ? tr('Нет интернета', 'Интернет жоқ')
                  : tr('Не получилось', 'Орындалмады'),
              textAlign: TextAlign.center,
              style: manrope(compact ? 15 : 17, FontWeight.w800, color: cInk),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: manrope(compact ? 13 : 14, FontWeight.w500, color: cInk2),
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? 14 : 20),
              _RetryButton(onRetry: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatefulWidget {
  final Future<void> Function() onRetry;
  const _RetryButton({required this.onRetry});

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: _busy ? null : _tap,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.refresh_rounded, size: 18),
        label: Text(tr('Повторить', 'Қайталау')),
        style: ElevatedButton.styleFrom(
          backgroundColor: cGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: manrope(14.5, FontWeight.w700, color: Colors.white),
        ),
      );
}
