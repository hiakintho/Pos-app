import 'dart:math' as math;

import 'package:flutter/material.dart';

class ModernLoadingIndicator extends StatefulWidget {
  final Color? color;
  final double strokeWidth;
  final double size;

  const ModernLoadingIndicator({
    super.key,
    this.color,
    this.strokeWidth = 2,
    this.size = 34,
  });

  @override
  State<ModernLoadingIndicator> createState() => _ModernLoadingIndicatorState();
}

class _ModernLoadingIndicatorState extends State<ModernLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(3, (index) {
            final wave =
                (math.sin((controller.value * math.pi * 2) - index * .8) + 1) /
                2;
            return Transform.translate(
              offset: Offset(0, -3 * wave),
              child: Container(
                width: 6,
                height: 8 + 9 * wave,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .45 + .55 * wave),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .18 * wave),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
