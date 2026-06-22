import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'account_screen.dart';
import 'basket_screen.dart';
import 'discover_screen.dart';
import 'orders_screen.dart';

/// Bottom-navigation main shell with 5 destinations.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final GlobalKey<OrdersScreenState> _ordersKey =
      GlobalKey<OrdersScreenState>();

  void _goToOrders() {
    setState(() => _index = 2);
    _ordersKey.currentState?.refresh();
  }

  Future<void> _signOut() async {
    await ApiClient.instance.logout();
    widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DiscoverScreen(onCheckedOut: _goToOrders),
      BasketScreen(onCheckedOut: _goToOrders),
      OrdersScreen(key: _ordersKey),
      AccountScreen(onSignOut: _signOut),
    ];

    return Scaffold(
      extendBody: false,
      body: GmBackground(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Gm.surface,
          border: Border(top: BorderSide(color: Gm.line)),
          boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, -4))],
        ),
        child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              indicatorColor: Gm.accent.withValues(alpha: 0.14),
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? Gm.accent : Gm.textDim,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return IconThemeData(color: selected ? Gm.accent : Gm.textDim);
              }),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              height: 64,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              onDestinationSelected: (i) {
                setState(() => _index = i);
                if (i == 2) _ordersKey.currentState?.refresh();
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore),
                    label: 'Discover'),
                NavigationDestination(
                    icon: Icon(Icons.compare_arrows_outlined),
                    selectedIcon: Icon(Icons.compare_arrows),
                    label: 'Basket'),
                NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: 'Orders'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Account'),
              ],
            ),
          ),
        ),
    );
  }
}
