
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/lunar_calendar.dart';

class DateHeaderWidget extends StatefulWidget {
  const DateHeaderWidget({super.key});

  @override
  State<DateHeaderWidget> createState() => _DateHeaderWidgetState();
}

class _DateHeaderWidgetState extends State<DateHeaderWidget> {
  late DateTime _now;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _getViDate(DateTime d) {
    const weekdays = ["", "Thứ hai", "Thứ ba", "Thứ tư", "Thứ năm", "Thứ sáu", "Thứ bảy", "Chủ nhật"];
    return 'Hôm nay là ${weekdays[d.weekday]}, ngày ${d.day.toString().padLeft(2, '0')} tháng ${d.month.toString().padLeft(2, '0')} năm ${d.year}';
  }

  String _getLunarDate(DateTime d) {
    // Note: The LunarCalendar helper needs to be verified for accuracy.
    // Assuming typical 1900-2100 algorithm.
    try {
      final lunar = LunarCalendar.convertSolarToLunar(d);
      return 'Âm lịch: ngày ${lunar.day.toString().padLeft(2, '0')} tháng ${lunar.month.toString().padLeft(2, '0')} năm ${lunar.year}';
    } catch (e) {
      return 'Âm lịch: --/--/----';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            Theme.of(context).primaryColor.withOpacity(0.03),
          ],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.calendar_month_rounded, 
              color: Theme.of(context).primaryColor,
              size: 20
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getViDate(_now),
                  style: GoogleFonts.quicksand(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF334155),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  _getLunarDate(_now),
                  style: GoogleFonts.quicksand(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).primaryColor,
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
