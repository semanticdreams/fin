import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/account.dart';
import 'data/account_database.dart';
import 'data/accounts_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initDatabaseFactory();
  runApp(const FinApp());
}

Future<void> _initDatabaseFactory() async {
  if (kIsWeb) {
    return;
  }
  const desktopPlatforms = <TargetPlatform>{
    TargetPlatform.windows,
    TargetPlatform.linux,
  };
  if (desktopPlatforms.contains(defaultTargetPlatform)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

class FinApp extends StatelessWidget {
  const FinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Personal Accounts',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AccountsPage(),
    );
  }
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  late final AccountsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AccountsController(AccountDatabase.instance)
      ..addListener(_handleControllerChange);
    _controller.loadAccounts();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _createAccount,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.isLoading && _controller.accounts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.accounts.isEmpty) {
      return const Center(
        child: Text('No accounts yet. Tap + to create one.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _controller.accounts.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final account = _controller.accounts[index];
        return ListTile(
          title: Text(account.name),
          subtitle: Text(account.currency),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              account.currency.substring(0, 1),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _formatBalance(account),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete account',
                onPressed: () => _confirmDelete(account),
              ),
            ],
          ),
          onTap: () => _editAccount(account),
        );
      },
    );
  }

  Future<void> _createAccount() async {
    await _controller.createAccount();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account created with default values.')),
    );
  }

  Future<void> _editAccount(Account account) async {
    final updated = await showDialog<Account>(
      context: context,
      builder: (context) {
        return _AccountDialog(account: account);
      },
    );

    if (updated != null) {
      await _controller.updateAccount(updated);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account updated.')),
      );
    }
  }

  Future<void> _confirmDelete(Account account) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete account?'),
          content: Text('This will remove ${account.name}.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _controller.deleteAccount(account);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${account.name} deleted.')),
      );
    }
  }

  String _formatBalance(Account account) {
    final balance = account.balance.toStringAsFixed(2);
    return '$balance ${account.currency}';
  }
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.account});

  final Account account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late final TextEditingController _currencyController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account.name);
    _balanceController =
        TextEditingController(text: widget.account.balance.toStringAsFixed(2));
    _currencyController =
        TextEditingController(text: widget.account.currency);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _balanceController,
            decoration: const InputDecoration(
              labelText: 'Balance',
              hintText: '0.00',
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currencyController,
            decoration: const InputDecoration(
              labelText: 'Currency',
              hintText: 'USD',
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _error = 'Name cannot be empty.';
      });
      return;
    }

    final parsedBalance =
        double.tryParse(_balanceController.text.trim());
    if (parsedBalance == null) {
      setState(() {
        _error = 'Balance must be a number.';
      });
      return;
    }

    final currency = _currencyController.text.trim().isEmpty
        ? widget.account.currency
        : _currencyController.text.trim().toUpperCase();

    final updated = widget.account.copyWith(
      name: name,
      balance: parsedBalance,
      currency: currency,
    );

    Navigator.of(context).pop(updated);
  }
}
