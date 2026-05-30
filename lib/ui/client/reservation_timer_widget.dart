import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/qoima_design.dart';

class ReservationTimerWidget extends StatefulWidget {
  final DateTime expiresAt;
  final VoidCallback? onExpired;
  const ReservationTimerWidget({
    super.key,
    required this.expiresAt,
    this.onExpired,
  });

  @override
  State<ReservationTimerWidget> createState() => _ReservationTimerWidgetState();
}

class _ReservationTimerWidgetState extends State<ReservationTimerWidget> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (mounted) {
      setState(
          () => _remaining = remaining.isNegative ? Duration.zero : remaining);
    }
    if (remaining.isNegative) {
      _timer.cancel();
      widget.onExpired?.call();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes =
        _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final expired = _remaining == Duration.zero;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: expired ? cRedTint : cAmberTint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          expired ? Icons.timer_off_outlined : Icons.timer_outlined,
          size: 16,
          color: expired ? cRed : cAmber,
        ),
        const SizedBox(width: 6),
        Text(
          expired ? 'Мерзімі өтті' : '$minutes:$seconds',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: expired ? cRed : cAmber,
          ),
        ),
      ]),
    );
  }
}
