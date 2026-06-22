import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// Auth gate: customers either sign in or self-register as CUSTOMER.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});
  final VoidCallback onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _api = ApiClient.instance;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }
    if (_register && _displayName.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a display name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await _api.register(email, password, _displayName.text.trim());
      } else {
        await _api.login(email, password);
      }
      if (!mounted) return;
      widget.onAuthenticated();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GmBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GmGlass(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const GmGradientText(
                        'Grocery-Mart',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _register
                            ? 'Create your customer account'
                            : 'Compare prices, build a basket, order cheapest.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Gm.textDim, height: 1.4, fontSize: 13.5),
                      ),
                      const SizedBox(height: 24),
                      if (_register) ...[
                        TextField(
                          controller: _displayName,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                              labelText: 'Display name',
                              prefixIcon: Icon(Icons.person_outline,
                                  color: Gm.textDim)),
                          style: const TextStyle(color: Gm.text),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon:
                                Icon(Icons.mail_outline, color: Gm.textDim)),
                        style: const TextStyle(color: Gm.text),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon:
                                Icon(Icons.lock_outline, color: Gm.textDim)),
                        style: const TextStyle(color: Gm.text),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Gm.danger.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(Gm.radiusSm),
                            border: Border.all(
                                color: Gm.danger.withValues(alpha: 0.4)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline,
                                color: Gm.danger, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(_error!,
                                    style: const TextStyle(
                                        color: Gm.text, fontSize: 13))),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 22),
                      GmButton(
                        label: _register ? 'Create account' : 'Get started',
                        busy: _busy,
                        onPressed: _busy ? null : _submit,
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _register = !_register;
                                  _error = null;
                                }),
                        child: Text(
                          _register
                              ? 'Already have an account? Sign in'
                              : "New here? Create an account",
                          style: const TextStyle(color: Gm.accent2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
