import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credit_screen.dart';
import 'dashboard_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'sell_screen.dart';

/// Flat navigation: five destinations, nothing nested behind a drawer. The app
/// opens on Sell because selling is the overwhelming majority of what happens
/// here -- the reports are for the end of the day.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.point_of_sale_outlined),
      selectedIcon: Icon(Icons.point_of_sale),
      label: 'Sell',
    ),
    NavigationDestination(
      icon: Icon(Icons.space_dashboard_outlined),
      selectedIcon: Icon(Icons.space_dashboard),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.sell_outlined),
      selectedIcon: Icon(Icons.sell),
      label: 'Products',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Credit',
    ),
    NavigationDestination(
      icon: Icon(Icons.insert_chart_outlined),
      selectedIcon: Icon(Icons.insert_chart),
      label: 'Reports',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          SellScreen(),
          DashboardScreen(),
          ProductsScreen(),
          CreditScreen(),
          ReportsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (next) => setState(() => _index = next),
        destinations: _destinations,
      ),
    );
  }
}
