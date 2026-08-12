import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'rewards_screen.dart';

/// Bottom-navigation shell: Home / Rewards / Orders / Account.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.onSignOut});
  final VoidCallback onSignOut;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final GlobalKey<OrdersScreenState> _ordersKey = GlobalKey<OrdersScreenState>();
  final GlobalKey<RewardsScreenState> _rewardsKey = GlobalKey<RewardsScreenState>();

  void _goToOrders() {
    setState(() => _index = 2);
    _ordersKey.currentState?.refresh();
    // A placed order changes the credit balance, so refresh Rewards too rather than
    // letting the tab show a stale number until the user pulls to refresh.
    _rewardsKey.currentState?.refresh();
  }

  Future<void> _signOut() async {
    await ApiClient.instance.logout();
    widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(onCheckedOut: _goToOrders),
      RewardsScreen(key: _rewardsKey),
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
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
                if (i == 1) _rewardsKey.currentState?.refresh();
                if (i == 2) _ordersKey.currentState?.refresh();
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.storefront_outlined),
                    selectedIcon: Icon(Icons.storefront),
                    label: 'Shop'),
                NavigationDestination(
                    icon: Icon(Icons.card_giftcard_outlined),
                    selectedIcon: Icon(Icons.card_giftcard),
                    label: 'Rewards'),
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
