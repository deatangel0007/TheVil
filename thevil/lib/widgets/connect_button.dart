import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';

class ConnectButton extends StatefulWidget {
  final ConnStatus status;
  final VoidCallback onTap;
  const ConnectButton({super.key, required this.status, required this.onTap});

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.status == ConnStatus.connected;
    final connecting = widget.status == ConnStatus.connecting;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          final glow = connected ? 30 + 25 * _pulse.value : 6.0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: connected
                    ? [AppColors.red, AppColors.redDark]
                    : [AppColors.cardAlt, AppColors.card],
              ),
              border: Border.all(
                color: connected ? AppColors.red : const Color(0xFF2A2A2A),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withOpacity(connected ? 0.55 : 0.12),
                  blurRadius: glow,
                  spreadRadius: connected ? 6 : 0,
                ),
              ],
            ),
            child: Center(
              child: connecting
                  ? const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        color: AppColors.red,
                        strokeWidth: 4,
                      ),
                    )
                  : Icon(
                      Icons.power_settings_new_rounded,
                      size: 84,
                      color: connected ? Colors.white : AppColors.textDim,
                    ),
            ),
          );
        },
      ),
    );
  }
}
