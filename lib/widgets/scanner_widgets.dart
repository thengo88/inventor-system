
import 'package:flutter/material.dart';

class ScannerCornerPainter extends CustomPainter {
  final Color color;
  ScannerCornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const double cornerLength = 30;
    const double radius = 24;

    // Top Left
    canvas.drawArc(Rect.fromLTWH(0, 0, radius * 2, radius * 2), 3.14, 1.57, false, paint);
    canvas.drawLine(const Offset(0, radius), const Offset(0, cornerLength + radius), paint);
    canvas.drawLine(const Offset(radius, 0), const Offset(cornerLength + radius, 0), paint);

    // Top Right
    canvas.drawArc(Rect.fromLTWH(size.width - radius * 2, 0, radius * 2, radius * 2), -1.57, 1.57, false, paint);
    canvas.drawLine(Offset(size.width, radius), Offset(size.width, cornerLength + radius), paint);
    canvas.drawLine(Offset(size.width - radius, 0), Offset(size.width - radius - cornerLength, 0), paint);

    // Bottom Left
    canvas.drawArc(Rect.fromLTWH(0, size.height - radius * 2, radius * 2, radius * 2), 1.57, 1.57, false, paint);
    canvas.drawLine(Offset(0, size.height - radius), Offset(0, size.height - cornerLength - radius), paint);
    canvas.drawLine(Offset(radius, size.height), Offset(cornerLength + radius, size.height), paint);

    // Bottom Right
    canvas.drawArc(Rect.fromLTWH(size.width - radius * 2, size.height - radius * 2, radius * 2, radius * 2), 0, 1.57, false, paint);
    canvas.drawLine(Offset(size.width, size.height - radius), Offset(size.width, size.height - cornerLength - radius), paint);
    canvas.drawLine(Offset(size.width - radius, size.height), Offset(size.width - radius - cornerLength, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ScanningAnimation extends StatefulWidget {
  final double width;
  const ScanningAnimation({super.key, this.width = 260});

  @override
  State<ScanningAnimation> createState() => _ScanningAnimationState();
}

class _ScanningAnimationState extends State<ScanningAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Center(
          child: Container(
            width: widget.width,
            height: widget.width,
            alignment: Alignment.topCenter,
            padding: EdgeInsets.only(top: _controller.value * widget.width),
            child: Container(
              height: 2,
              width: widget.width - 20,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.8),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.withOpacity(0),
                    Colors.blue,
                    Colors.blue.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
