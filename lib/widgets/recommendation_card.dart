import 'package:flutter/material.dart';

class RecommendationCard extends StatelessWidget {
  final String text;
  final bool isUrgent;

  const RecommendationCard({
    super.key,
    required this.text,
    this.isUrgent = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isUrgent ? Colors.red.shade50 : const Color(0xFFF0FDF4);
    final iconColor = isUrgent ? Colors.red.shade500 : const Color(0xFF2F6B3B);

    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: iconColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: iconColor.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Icon(
              isUrgent ? Icons.warning_rounded : Icons.lightbulb_rounded,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}