import 'package:flutter/material.dart';
import 'merchant_dashboard.dart';
import 'orders_screen.dart';
import 'tracking_screen.dart';
// 1. Import the new Merchant Profile Screen
import 'merchant_profile_screens.dart';

class MerchantNavigation extends StatefulWidget {
  const MerchantNavigation({super.key});

  @override
  State<MerchantNavigation> createState() => _MerchantNavigationState();
}

class _MerchantNavigationState extends State<MerchantNavigation> {
  int _currentIndex = 0;

  // 2. Add the Profile Screen to the active pages array
  final List<Widget> _pages = const [
    MerchantDashboard(),
    OrdersScreen(),
    TrackingScreen(),
    MerchantProfileScreen(), // 🚨 The new 4th page!
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue.shade700,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Orders'),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Track',
          ),
          // 3. Add the physical button to the UI
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
