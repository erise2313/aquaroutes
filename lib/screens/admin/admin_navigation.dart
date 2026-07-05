import 'package:flutter/material.dart';
import 'admin_dashboard.dart';
import 'orders_screen.dart';
import 'tracking_screen.dart';

class AdminNavigation extends StatefulWidget {
  @override
  _AdminNavigationState createState() => _AdminNavigationState();
}

class _AdminNavigationState extends State<AdminNavigation> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    AdminDashboard(), // Home/Overview
    Center(child: Text("Orders Screen")), // Orders
    Center(child: Text("Tracking Screen")), // Map/Track
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Track'),
        ],
      ),
    );
  }
}