import 'package:flutter/material.dart';
import '../config/app_config.dart';

class DeviceStatusCard extends StatelessWidget {
  final String deviceName;
  final IconData icon;

  const DeviceStatusCard({
    super.key,
    required this.deviceName,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = AppConfig.isDemoMode ? Colors.amber.shade600 : const Color(0xFF5DBB63);
    final statusText = AppConfig.isDemoMode ? "Demo Active" : "Online";

    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 24, color: const Color(0xFF2F6B3B)),
              Container(
                height: 8,
                width: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
            ],
          ),
          const Spacer(),
          Text(
            deviceName,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E2A1F)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            statusText,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: statusColor),
          ),
        ],
      ),
    );
  }
}