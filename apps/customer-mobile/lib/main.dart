import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/auth_screen.dart';
import 'screens/shell.dart';
import 'theme.dart';

void main() => runApp(const GroceryMartCustomerApp());

class GroceryMartCustomerApp extends StatefulWidget {
  const GroceryMartCustomerApp({super.key});

  @override
  State<GroceryMartCustomerApp> createState() => _GroceryMartCustomerAppState();
}

class _GroceryMartCustomerAppState extends State<GroceryMartCustomerApp> {
  final ApiClient _api = ApiClient.instance;

  void _onAuthChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grocery-Mart',
      debugShowCheckedModeBanner: false,
      theme: Gm.themeData(),
      home: _api.isAuthenticated
          ? MainShell(onSignOut: _onAuthChanged)
          : AuthScreen(onAuthenticated: _onAuthChanged),
    );
  }
}
