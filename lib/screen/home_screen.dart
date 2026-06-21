import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/custom_bottom_nav.dart';
import 'dashboard_page.dart';
import 'favorites_page.dart';
import 'profile_page.dart';
import 'upload_page.dart';
import 'wardrobe_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    DashboardPage(),
    WardrobePage(),
    UploadPage(),
    FavoritesPage(),
    ProfilePage(),
  ];

  void _changePage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 106),
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: CustomBottomNav(
              currentIndex: _selectedIndex,
              onTap: _changePage,
            ),
          ),
        ],
      ),
    );
  }
}
