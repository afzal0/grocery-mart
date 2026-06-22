import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.onSignOut});
  final Future<void> Function() onSignOut;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _api = ApiClient.instance;

  Map<String, dynamic>? _me;
  bool _loadingMe = true;
  String? _meError;

  List<dynamic> _wallet = const [];
  bool _loadingWallet = false;

  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _loadWallet();
    _loadUnread();
  }

  Future<void> _loadMe() async {
    setState(() {
      _loadingMe = true;
      _meError = null;
    });
    try {
      final res = await _api.get('/me');
      setState(() => _me = res as Map<String, dynamic>);
    } on ApiException catch (e) {
      setState(() => _meError = e.detail);
    } finally {
      if (mounted) setState(() => _loadingMe = false);
    }
  }

  Future<void> _loadWallet() async {
    setState(() => _loadingWallet = true);
    try {
      final res = await _api.get('/wallet');
      setState(() => _wallet = (res as List?) ?? const []);
    } on ApiException catch (_) {
      // wallet may be empty; ignore quietly
    } finally {
      if (mounted) setState(() => _loadingWallet = false);
    }
  }

  Future<void> _loadUnread() async {
    try {
      final res =
          await _api.get('/notifications', query: {'limit': 1}) as Map<String, dynamic>;
      setState(() => _unread = (res['unreadCount'] as num?)?.toInt() ?? 0);
    } on ApiException catch (_) {}
  }

  Future<void> _topUp() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TopUpSheet(),
    );
    if (ok == true) _loadWallet();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const GmGradientText('Account',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),

          // ---- Profile / me ----
          GmGlass(
            child: _loadingMe
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Gm.accent)))
                : _meError != null
                    ? Row(children: [
                        Expanded(
                            child: Text(_meError!,
                                style: const TextStyle(color: Gm.danger))),
                        IconButton(
                            onPressed: _loadMe,
                            icon: const Icon(Icons.refresh, color: Gm.text)),
                      ])
                    : Row(children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Gm.accent, Gm.accent2]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.person,
                              color: Color(0xFF06281C)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${_me?['userId'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Gm.text,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  '${(_me?['roles'] as List?)?.join(', ') ?? ''}',
                                  style: const TextStyle(
                                      color: Gm.textDim, fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ]),
          ),
          const SizedBox(height: 14),

          // ---- Wallet ----
          GmGlass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: Gm.accent),
                  const SizedBox(width: 10),
                  const Text('Wallet',
                      style: TextStyle(
                          color: Gm.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GmGhostButton(
                      label: 'Top up',
                      icon: Icons.add,
                      color: Gm.accent,
                      onPressed: _topUp),
                ]),
                const SizedBox(height: 10),
                if (_loadingWallet)
                  const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Gm.accent))
                else if (_wallet.isEmpty)
                  const Text('No balance yet. Top up to add funds.',
                      style: TextStyle(color: Gm.textDim))
                else
                  ..._wallet.map((w) {
                    final m = w as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${m['currency']}',
                              style: const TextStyle(color: Gm.textDim)),
                          Text(
                              GmUi.money(m['balance'] as num?,
                                  '${m['currency'] ?? 'AUD'}'),
                              style: const TextStyle(
                                  color: Gm.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ---- Settings list ----
          _navTile(Icons.notifications_outlined, 'Notifications',
              badge: _unread > 0 ? '$_unread' : null, onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const NotificationsScreen()));
            _loadUnread();
          }),
          _navTile(Icons.tune, 'Notification preferences', onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PreferencesScreen()));
          }),
          _navTile(Icons.edit_outlined, 'Edit profile', onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const EditProfileScreen()));
          }),
          _navTile(Icons.privacy_tip_outlined, 'Privacy policy', onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PrivacyScreen()));
          }),
          _navTile(Icons.download_outlined, 'Export my data', onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ExportScreen()));
          }),
          _navTile(Icons.delete_outline, 'Delete account',
              danger: true, onTap: _deleteAccount),
          const SizedBox(height: 14),

          GmGhostButton(
            label: 'Sign out',
            icon: Icons.logout,
            color: Gm.textDim,
            onPressed: () => widget.onSignOut(),
          ),
        ],
      ),
    );
  }

  Widget _navTile(IconData icon, String label,
      {VoidCallback? onTap, String? badge, bool danger = false}) {
    final color = danger ? Gm.danger : Gm.text;
    return GmGlass(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(children: [
        Icon(icon, color: danger ? Gm.danger : Gm.accent, size: 20),
        const SizedBox(width: 14),
        Expanded(
            child: Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        if (badge != null)
          GmBadge(badge, color: Gm.danger)
        else
          const Icon(Icons.chevron_right, color: Gm.textDim),
      ]),
    );
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Gm.bg1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Gm.radius)),
        title: const Text('Delete account?',
            style: TextStyle(color: Gm.text)),
        content: const Text(
            'Your account will be anonymized and you will be signed out. This cannot be undone.',
            style: TextStyle(color: Gm.textDim)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child:
                  const Text('Cancel', style: TextStyle(color: Gm.textDim))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete',
                  style: TextStyle(
                      color: Gm.danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await _api.delete('/account') as Map<String, dynamic>?;
      if (!mounted) return;
      GmUi.snack(context,
          'Account ${res?['status'] ?? 'deleted'}${res?['anonymized'] == true ? ' (anonymized)' : ''}.');
      await widget.onSignOut();
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    }
  }
}

// -----------------------------------------------------------------------------
// Top-up sheet
// -----------------------------------------------------------------------------

class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet();

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  final _api = ApiClient.instance;
  final _amount = TextEditingController(text: '50');
  String _currency = 'AUD';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.post('/wallet/topup',
          body: {'amount': amount, 'currency': _currency});
      if (!mounted) return;
      GmUi.snack(context,
          'Top-up initiated — balance is credited shortly via webhook.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: GmGlass(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top up wallet',
                style: TextStyle(
                    color: Gm.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  style: const TextStyle(color: Gm.text),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _currency,
                dropdownColor: Gm.bg1,
                style: const TextStyle(color: Gm.text),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'AUD', child: Text('AUD')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                ],
                onChanged: (v) => setState(() => _currency = v ?? 'AUD'),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Gm.danger)),
            ],
            const SizedBox(height: 18),
            GmButton(
                label: 'Initiate top-up',
                busy: _busy,
                onPressed: _busy ? null : _submit),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Notifications inbox
// -----------------------------------------------------------------------------

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<dynamic> _items = const [];
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/notifications', query: {'limit': 30})
          as Map<String, dynamic>;
      setState(() {
        _items = (res['items'] as List?) ?? const [];
      });
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAll() async {
    setState(() => _marking = true);
    try {
      await _api.post('/notifications/read');
      await _load();
      if (mounted) GmUi.snack(context, 'All notifications marked read.');
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  Future<void> _markOne(String id) async {
    try {
      await _api.post('/notifications/$id/read');
      _load();
    } on ApiException catch (e) {
      if (mounted) GmUi.snack(context, e.detail, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Gm.text),
        title: const Text('Notifications',
            style: TextStyle(color: Gm.text, fontSize: 17)),
        actions: [
          TextButton(
            onPressed: _marking ? null : _markAll,
            child: const Text('Mark all read',
                style: TextStyle(color: Gm.accent)),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: GmBackground(
        child: SafeArea(
          child: _loading
              ? const GmLoading()
              : _error != null
                  ? GmError(message: _error!, onRetry: _load)
                  : _items.isEmpty
                      ? const GmEmpty(
                          message: 'No notifications.',
                          icon: Icons.notifications_off_outlined)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                          children: _items.map((n) {
                            final m = n as Map<String, dynamic>;
                            final read = m['read'] == true;
                            return GmGlass(
                              margin: const EdgeInsets.only(bottom: 10),
                              strong: !read,
                              onTap: read
                                  ? null
                                  : () => _markOne('${m['id']}'),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    if (!read)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin:
                                            const EdgeInsets.only(right: 8),
                                        decoration: const BoxDecoration(
                                            color: Gm.accent,
                                            shape: BoxShape.circle),
                                      ),
                                    Expanded(
                                      child: Text('${m['title'] ?? ''}',
                                          style: TextStyle(
                                              color: Gm.text,
                                              fontWeight: read
                                                  ? FontWeight.w500
                                                  : FontWeight.w700)),
                                    ),
                                    if (m['category'] != null)
                                      GmBadge('${m['category']}',
                                          color: Gm.textDim),
                                  ]),
                                  if (m['body'] != null) ...[
                                    const SizedBox(height: 6),
                                    Text('${m['body']}',
                                        style: const TextStyle(
                                            color: Gm.textDim,
                                            height: 1.35)),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Notification preferences
// -----------------------------------------------------------------------------

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  List<dynamic> _prefs = const [];
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/notifications/preferences');
      setState(() => _prefs = (res as List?) ?? const []);
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> pref, bool value) async {
    final category = '${pref['category']}';
    setState(() {
      _saving.add(category);
      pref['pushEnabled'] = value;
    });
    try {
      await _api.put('/notifications/preferences',
          body: {'category': category, 'pushEnabled': value});
    } on ApiException catch (e) {
      setState(() => pref['pushEnabled'] = !value);
      if (mounted) GmUi.snack(context, e.detail, error: true);
    } finally {
      if (mounted) setState(() => _saving.remove(category));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Gm.text),
        title: const Text('Notification preferences',
            style: TextStyle(color: Gm.text, fontSize: 17)),
      ),
      extendBodyBehindAppBar: true,
      body: GmBackground(
        child: SafeArea(
          child: _loading
              ? const GmLoading()
              : _error != null
                  ? GmError(message: _error!, onRetry: _load)
                  : _prefs.isEmpty
                      ? const GmEmpty(message: 'No preference categories.')
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                          children: _prefs.map((p) {
                            final m = p as Map<String, dynamic>;
                            final category = '${m['category']}';
                            final enabled = m['pushEnabled'] == true;
                            final busy = _saving.contains(category);
                            return GmGlass(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Row(children: [
                                Expanded(
                                  child: Text(GmUi.titleize(category),
                                      style: const TextStyle(
                                          color: Gm.text,
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (busy)
                                  const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Gm.accent))
                                else
                                  Switch(
                                    value: enabled,
                                    activeThumbColor: Gm.accent,
                                    onChanged: (v) => _toggle(m, v),
                                  ),
                              ]),
                            );
                          }).toList(),
                        ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Edit profile (PATCH /account)
// -----------------------------------------------------------------------------

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _api = ApiClient.instance;
  final _displayName = TextEditingController();
  final _country = TextEditingController(text: 'AU');
  final _currency = TextEditingController(text: 'AUD');
  final _locale = TextEditingController(text: 'en-AU');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _country.dispose();
    _currency.dispose();
    _locale.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{};
      if (_displayName.text.trim().isNotEmpty) {
        body['displayName'] = _displayName.text.trim();
      }
      if (_country.text.trim().isNotEmpty) body['country'] = _country.text.trim();
      if (_currency.text.trim().isNotEmpty) {
        body['currency'] = _currency.text.trim();
      }
      if (_locale.text.trim().isNotEmpty) body['locale'] = _locale.text.trim();
      await _api.patch('/account', body: body);
      if (!mounted) return;
      GmUi.snack(context, 'Profile updated.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Gm.text),
        title: const Text('Edit profile',
            style: TextStyle(color: Gm.text, fontSize: 17)),
      ),
      extendBodyBehindAppBar: true,
      body: GmBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
            children: [
              GmGlass(
                child: Column(children: [
                  TextField(
                    controller: _displayName,
                    decoration:
                        const InputDecoration(labelText: 'Display name'),
                    style: const TextStyle(color: Gm.text),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _country,
                    decoration: const InputDecoration(
                        labelText: 'Country (e.g. AU)'),
                    style: const TextStyle(color: Gm.text),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _currency,
                    decoration: const InputDecoration(
                        labelText: 'Currency (e.g. AUD)'),
                    style: const TextStyle(color: Gm.text),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locale,
                    decoration: const InputDecoration(
                        labelText: 'Locale (e.g. en-AU)'),
                    style: const TextStyle(color: Gm.text),
                  ),
                ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Gm.danger)),
              ],
              const SizedBox(height: 18),
              GmButton(
                  label: 'Save changes',
                  busy: _busy,
                  onPressed: _busy ? null : _save),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Privacy policy
// -----------------------------------------------------------------------------

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _privacy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/privacy', auth: false);
      setState(() => _privacy = res as Map<String, dynamic>);
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _privacy;
    final categories = (p?['dataCategories'] as List?) ?? const [];
    final rights = (p?['rights'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Gm.text),
        title: const Text('Privacy',
            style: TextStyle(color: Gm.text, fontSize: 17)),
      ),
      extendBodyBehindAppBar: true,
      body: GmBackground(
        child: SafeArea(
          child: _loading
              ? const GmLoading()
              : _error != null
                  ? GmError(message: _error!, onRetry: _load)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                      children: [
                        if (p?['effectiveDate'] != null)
                          GmGlass(
                            child: Text('Effective: ${p?['effectiveDate']}',
                                style: const TextStyle(color: Gm.textDim)),
                          ),
                        const SizedBox(height: 12),
                        const Text('Data we collect',
                            style: TextStyle(
                                color: Gm.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        ...categories.map((c) {
                          final m = c as Map<String, dynamic>;
                          return GmGlass(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${m['category']}',
                                    style: const TextStyle(
                                        color: Gm.text,
                                        fontWeight: FontWeight.w700)),
                                if (m['data'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text('${m['data']}',
                                      style: const TextStyle(
                                          color: Gm.textDim, fontSize: 13)),
                                ],
                                if (m['purpose'] != null) ...[
                                  const SizedBox(height: 4),
                                  Text('Purpose: ${m['purpose']}',
                                      style: const TextStyle(
                                          color: Gm.textDim, fontSize: 12.5)),
                                ],
                              ],
                            ),
                          );
                        }),
                        if (rights.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text('Your rights',
                              style: TextStyle(
                                  color: Gm.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          GmGlass(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: rights
                                  .map((r) => Padding(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 4),
                                        child: Text('• $r',
                                            style: const TextStyle(
                                                color: Gm.textDim)),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],
                        if (p?['accountDeletion'] != null) ...[
                          const SizedBox(height: 12),
                          GmGlass(
                            child: Text('${p?['accountDeletion']}',
                                style: const TextStyle(color: Gm.textDim)),
                          ),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Export data
// -----------------------------------------------------------------------------

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final _api = ApiClient.instance;
  bool _loading = true;
  String? _error;
  String? _json;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/account/export');
      const encoder = JsonEncoder.withIndent('  ');
      setState(() => _json = encoder.convert(res));
    } on ApiException catch (e) {
      setState(() => _error = e.detail);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Gm.text),
        title: const Text('Export my data',
            style: TextStyle(color: Gm.text, fontSize: 17)),
      ),
      extendBodyBehindAppBar: true,
      body: GmBackground(
        child: SafeArea(
          child: _loading
              ? const GmLoading()
              : _error != null
                  ? GmError(message: _error!, onRetry: _load)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                      children: [
                        const Text(
                            'A machine-readable copy of your account data.',
                            style: TextStyle(color: Gm.textDim)),
                        const SizedBox(height: 12),
                        GmGlass(
                          child: SelectableText(
                            _json ?? '{}',
                            style: const TextStyle(
                                color: Gm.text,
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
