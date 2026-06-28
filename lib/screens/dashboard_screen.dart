import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../widgets/feature_action_card.dart';
import 'monitoring_screen.dart';
import 'scan_screen.dart';
import 'weather_screen.dart';
import 'sell_crop_screen.dart';
import 'orders_screen.dart';
import 'shared/health_logs_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await AuthService().signOut();

    if (!context.mounted) return;

    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF7),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              _buildHeroCard(),
              const SizedBox(height: 32),
              const Text(
                'Farmer Tools',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E2A1F),
                ),
              ),
              const SizedBox(height: 16),
              _buildToolsGrid(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome Back,',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 1.2,
              ),
            ),
            const Text(
              'Farmer Dashboard',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1E2A1F),
              ),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
              ),
            ],
          ),
          child: IconButton(
            onPressed: () => _logout(context),
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.redAccent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF2F6B3B),
            Color(0xFF1E4A27),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F6B3B).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      AppConfig.isDemoMode
                          ? Icons.science_rounded
                          : Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppConfig.isDemoMode ? 'DEMO MODE' : 'LIVE MODE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.eco_rounded,
                color: Colors.white,
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Farmer tools ready.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use ESP32-CAM scanning, scan history logs, weather tracking, crop selling, and order management from one dashboard.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        FeatureActionCard(
          title: 'Smart\nMonitoring',
          icon: Icons.dashboard_customize_rounded,
          color: const Color(0xFF2F6B3B),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MonitoringScreen(),
            ),
          ),
        ),
        FeatureActionCard(
          title: 'Scan History\nLogs',
          icon: Icons.history_rounded,
          color: Colors.teal,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const HealthLogsScreen(
                readOnlyBuyer: false,
                title: 'Scan History Logs',
              ),
            ),
          ),
        ),
        FeatureActionCard(
          title: 'Scan\nDisease',
          icon: Icons.document_scanner_rounded,
          color: Colors.indigo,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ScanScreen(),
            ),
          ),
        ),
        FeatureActionCard(
          title: 'Weather\nTracking',
          icon: Icons.cloud_rounded,
          color: Colors.lightBlue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const WeatherScreen(),
            ),
          ),
        ),
        FeatureActionCard(
          title: 'Sell\nCrop',
          icon: Icons.storefront_rounded,
          color: Colors.orange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SellCropScreen(),
            ),
          ),
        ),
        FeatureActionCard(
          title: 'Order\nManagement',
          icon: Icons.receipt_long_rounded,
          color: Colors.purple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const OrdersScreen(),
            ),
          ),
        ),
      ],
    );
  }
}