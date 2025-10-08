import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'data/account.dart';
import 'data/account_database.dart';
import 'data/account_update.dart';
import 'data/account_updates_controller.dart';
import 'data/accounts_controller.dart';
import 'data/currency_rates_service.dart';
import 'data/stats_controller.dart';
import 'data/transaction_record.dart';
import 'data/transactions_controller.dart';

int suggestPrecision(String currency) {
  switch (currency.toUpperCase()) {
    case 'BTC':
      return 8;
    case 'ETH':
      return 6;
    default:
      return 2;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initWindowIcon();
  await _initDatabaseFactory();
  runApp(const FinApp());
}

Future<void> _initWindowIcon() async {
  if (kIsWeb) {
    return;
  }
  if (!(Platform.isWindows || Platform.isLinux)) {
    return;
  }
  try {
    await windowManager.ensureInitialized();
    final data = await rootBundle.load('assets/icon.png');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/fin_window_icon.png');
    await file.writeAsBytes(data.buffer.asUint8List());
    await windowManager.setIcon(file.path);
  } catch (error, stackTrace) {
    debugPrint('Failed to set window icon: $error\n$stackTrace');
  }
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
      debugShowCheckedModeBanner: false,
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
      home: const HomeScaffold(),
    );
  }
}

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});

  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<_TransactionsTabState> _transactionsTabKey =
      GlobalKey<_TransactionsTabState>();
  final GlobalKey<_AccountsTabState> _accountsTabKey =
      GlobalKey<_AccountsTabState>();
  final GlobalKey<_StatsTabState> _statsTabKey = GlobalKey<_StatsTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {});
    }
    if (_tabController.index == 0) {
      _transactionsTabKey.currentState?.refreshData();
    } else if (_tabController.index == 2) {
      _statsTabKey.currentState?.refreshData();
    }
  }

  bool get _isAccountsTab => _tabController.index == 1;
  bool get _isTransactionsTab => _tabController.index == 0;

  Future<void> _refreshStats() async {
    final state = _statsTabKey.currentState;
    if (state != null) {
      await state.refreshData();
    }
  }

  void _handleAccountsChanged() {
    _accountsTabKey.currentState?.refreshAccounts();
    _refreshStats();
  }

  Widget? _buildFab() {
    if (_isTransactionsTab) {
      return FloatingActionButton(
        onPressed: () =>
            _transactionsTabKey.currentState?.createTransaction(),
        tooltip: 'Add transaction',
        child: const Icon(Icons.playlist_add),
      );
    }
    if (_isAccountsTab) {
      return FloatingActionButton(
        onPressed: () => _accountsTabKey.currentState?.createAccount(),
        tooltip: 'Add account',
        child: const Icon(Icons.add),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Image.asset('assets/icon.png'),
        ),
        title: const Text('fin'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Tab>[
            Tab(
              icon: Icon(Icons.receipt_long_outlined),
              text: 'Transactions',
            ),
            Tab(
              icon: Icon(Icons.account_balance_wallet_outlined),
              text: 'Accounts',
            ),
            Tab(
              icon: Icon(Icons.insights_outlined),
              text: 'Stats',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          TransactionsTab(
            key: _transactionsTabKey,
            onAccountsChanged: _handleAccountsChanged,
          ),
            AccountsTab(
              key: _accountsTabKey,
              onAccountsChanged: _handleAccountsChanged,
            ),
          StatsTab(key: _statsTabKey),
        ],
      ),
      floatingActionButton: _buildFab(),
    );
  }
}

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key, this.onAccountsChanged});

  final VoidCallback? onAccountsChanged;

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  late final AccountsController _controller;
  late final CurrencyRatesService _ratesService;
  bool _isTotalLoading = true;
  double? _totalEur;
  String? _totalError;
  int _calculationGeneration = 0;
  Map<String, double>? _cachedRates;

  @override
  void initState() {
    super.initState();
    _ratesService = CurrencyRatesService();
    _controller = AccountsController(AccountDatabase.instance)
      ..addListener(_handleControllerChange);
    _controller.loadAccounts();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    _controller.dispose();
    _ratesService.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (!mounted) {
      return;
    }
    final isLoading = _controller.isLoading;
    setState(() {
      if (isLoading) {
        _isTotalLoading = true;
        _totalError = null;
      }
    });
    if (!isLoading) {
      _calculateTotal();
    }
  }

  Future<void> createAccount() => _createAccount();
  Future<void> refreshAccounts() async {
    await _controller.loadAccounts();
  }

  void _openAccountUpdates(Account account) {
    final id = account.id;
    if (id == null) {
      return;
    }
    Navigator.of(context)
        .push<void>(
      MaterialPageRoute<void>(
        builder: (context) => AccountUpdatesPage(account: account),
      ),
    ).then((_) {
      refreshAccounts();
      widget.onAccountsChanged?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: _buildBody());
  }

  Widget _buildBody() {
    if (_controller.isLoading && _controller.accounts.isEmpty) {
      return Column(
        children: <Widget>[
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          ),
          const Divider(height: 1),
          _buildTotalSummary(context),
        ],
      );
    }

    if (_controller.accounts.isEmpty) {
      return Column(
        children: <Widget>[
          const Expanded(
            child: Center(
              child: Text('No accounts yet. Tap + to create one.'),
            ),
          ),
          const Divider(height: 1),
          _buildTotalSummary(context),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: _controller.accounts.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final account = _controller.accounts[index];
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                title: Text(account.name),
                subtitle: Text(account.currency.toUpperCase()),
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    account.currency.substring(0, 1),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                trailing: _buildAccountTrailing(account),
                onTap: () => _editAccount(account),
              );
            },
          ),
        ),
        const Divider(height: 1),
        _buildTotalSummary(context),
      ],
    );
  }

  Future<void> _calculateTotal() async {
    final accounts = List<Account>.from(_controller.accounts);
    final int generation = ++_calculationGeneration;
    debugPrint(
      'AccountsTab: calculating EUR total for ${accounts.length} accounts '
      '(generation $generation)',
    );

    if (accounts.isEmpty) {
      if (!mounted || generation != _calculationGeneration) {
        return;
      }
      setState(() {
        _isTotalLoading = false;
        _totalEur = 0;
        _totalError = null;
      });
      debugPrint('AccountsTab: no accounts available, total defaults to 0.');
      return;
    }

    setState(() {
      _isTotalLoading = true;
      _totalError = null;
    });

    try {
      final rates = await _ratesService.fetchRates();
      _cachedRates = rates;
      if (!mounted || generation != _calculationGeneration) {
        return;
      }

      var total = 0.0;

      for (final Account account in accounts) {
        final currency = account.currency.toUpperCase();
        if (currency == 'EUR') {
          total += account.balance;
          continue;
        }

        final rate = rates[currency];
        if (rate == null || rate == 0) {
          debugPrint(
            'AccountsTab: missing or zero rate for $currency, treating as 0.',
          );
          continue;
        }

        total += account.balance / rate;
        debugPrint(
          'AccountsTab: converted ${account.balance} $currency -> '
          '${(account.balance / rate).toStringAsFixed(2)} EUR (rate $rate)',
        );
      }

      setState(() {
        _isTotalLoading = false;
        _totalEur = total;
        _totalError = null;
      });
      debugPrint(
        'AccountsTab: total calculation complete. EUR total = '
        '${total.toStringAsFixed(2)}',
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _calculationGeneration) {
        return;
      }
      setState(() {
        _isTotalLoading = false;
        _totalEur = null;
        _totalError = 'Could not refresh exchange rates.';
      });
      _cachedRates = null;
      debugPrint(
        'AccountsTab: error while refreshing exchange rates: $error\n'
        '$stackTrace',
      );
    }
  }

  Widget _buildTotalSummary(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget content;
    if (_isTotalLoading) {
      content = Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Calculating total...'),
          ),
        ],
      );
    } else if (_totalError != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            color: colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _totalError!,
              style:
                  textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            ),
          ),
        ],
      );
    } else if (_totalEur != null) {
      content = Text(
        'Total: ${_totalEur!.toStringAsFixed(2)} EUR',
        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      );
    } else {
      content = const Text('Total unavailable.');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: content,
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
    widget.onAccountsChanged?.call();
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
      widget.onAccountsChanged?.call();
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
      widget.onAccountsChanged?.call();
    }
  }

  Widget _buildAccountTrailing(Account account) {
    final theme = Theme.of(context);
    final currency = account.currency.toUpperCase();
    final precision = suggestPrecision(currency);
    final nativeText =
        '${account.balance.toStringAsFixed(precision)} ${account.currency}';

    final rates = _cachedRates;
    Widget secondaryDisplay;
    if (rates != null) {
      final eurValue = _convertToEur(account.balance, currency, rates);
      if (eurValue != null) {
        secondaryDisplay = Text(
          '€${eurValue.toStringAsFixed(2)}',
          style: theme.textTheme.titleMedium,
        );
      } else {
        secondaryDisplay = Tooltip(
          message: 'Missing exchange rate for $currency',
          child: Icon(
            Icons.error_outline,
            color: theme.colorScheme.error,
            size: 18,
          ),
        );
      }
    } else {
      secondaryDisplay = Tooltip(
        message: 'Exchange rates not loaded yet',
        child: Icon(
          Icons.error_outline,
          color: theme.colorScheme.error,
          size: 18,
        ),
      );
    }

    final secondary = SizedBox(
      width: 120,
      child: Align(
        alignment: Alignment.centerRight,
        child: secondaryDisplay,
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          nativeText,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(width: 10),
        secondary,
        const SizedBox(width: 30),
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Account updates',
          onPressed: () => _openAccountUpdates(account),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete account',
          onPressed: () => _confirmDelete(account),
        ),
      ],
    );
  }

  double? _convertToEur(
    double amount,
    String currency,
    Map<String, double> rates,
  ) {
    final upper = currency.toUpperCase();
    if (upper == 'EUR') {
      return amount;
    }
    final rate = rates[upper];
    if (rate == null || rate == 0) {
      return null;
    }
    return amount / rate;
  }
}

class TransactionsTab extends StatefulWidget {
  const TransactionsTab({super.key, this.onAccountsChanged});

  final VoidCallback? onAccountsChanged;

  @override
  State<TransactionsTab> createState() => _TransactionsTabState();
}

class AccountUpdatesPage extends StatefulWidget {
  const AccountUpdatesPage({super.key, required this.account});

  final Account account;

  @override
  State<AccountUpdatesPage> createState() => _AccountUpdatesPageState();
}

class _AccountUpdatesPageState extends State<AccountUpdatesPage> {
  late final AccountUpdatesController _controller;

  @override
  void initState() {
    super.initState();
    final id = widget.account.id;
    assert(id != null, 'Account must have an id to view updates.');
    _controller = AccountUpdatesController(AccountDatabase.instance, id!)
      ..addListener(_handleControllerChange);
    _controller.loadUpdates();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChange)
      ..dispose();
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
        title: Text('Updates • ${widget.account.name}'),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _createUpdate,
        tooltip: 'Add update',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.isLoading && _controller.updates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.updates.isEmpty) {
      return const Center(
        child: Text('No updates recorded for this account.'),
      );
    }

    final updates = _controller.updates;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      itemCount: updates.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final update = updates[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          title: Text(_formatUpdateTimestamp(update.updatedAt)),
          subtitle: Text(
            'Previous: ${update.previousBalance.toStringAsFixed(
                  suggestPrecision(widget.account.currency.toUpperCase()),
                )} ${widget.account.currency}\n'
            'New: ${update.newBalance.toStringAsFixed(
                  suggestPrecision(widget.account.currency.toUpperCase()),
                )} ${widget.account.currency}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit update',
                onPressed: () => _editUpdate(update),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete update',
                onPressed: () => _deleteUpdate(update),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _createUpdate() async {
    final result = await _showUpdateDialog();
    if (result != null) {
      await _controller.addUpdate(result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account update added.')),
      );
    }
  }

  Future<void> _editUpdate(AccountUpdate update) async {
    final result = await _showUpdateDialog(existing: update);
    if (result != null) {
      await _controller.updateUpdate(result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account update saved.')),
      );
    }
  }

  Future<void> _deleteUpdate(AccountUpdate update) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete update?'),
          content: const Text('This will remove the selected account update.'),
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
      await _controller.deleteUpdate(update);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account update deleted.')),
      );
    }
  }

  Future<AccountUpdate?> _showUpdateDialog({AccountUpdate? existing}) async {
    final precision =
        suggestPrecision(widget.account.currency.toUpperCase());
    final previousController = TextEditingController(
      text: existing != null
          ? existing.previousBalance.toStringAsFixed(precision)
          : widget.account.balance.toStringAsFixed(precision),
    );
    final newController = TextEditingController(
      text: existing != null
          ? existing.newBalance.toStringAsFixed(precision)
          : widget.account.balance.toStringAsFixed(precision),
    );
    DateTime selected = existing?.updatedAt ?? DateTime.now();
    String? error;

    return showDialog<AccountUpdate>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> pickDateTime() async {
              final date = await showDatePicker(
                context: context,
                initialDate: selected,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (date == null) {
                return;
              }
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(selected),
              );
              final merged = DateTime(
                date.year,
                date.month,
                date.day,
                time?.hour ?? selected.hour,
                time?.minute ?? selected.minute,
              );
              setState(() {
                selected = merged;
              });
            }

            void submit() {
              final previous = double.tryParse(previousController.text.trim());
              final next = double.tryParse(newController.text.trim());
              if (previous == null || next == null) {
                setState(() {
                  error = 'Balances must be numeric.';
                });
                return;
              }
              final update = AccountUpdate(
                id: existing?.id,
                accountId: widget.account.id!,
                previousBalance: previous,
                newBalance: next,
                updatedAt: selected,
              );
              Navigator.of(context).pop(update);
            }

            return AlertDialog(
              title: Text(existing != null ? 'Edit update' : 'Add update'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: previousController,
                    decoration: const InputDecoration(labelText: 'Previous balance'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newController,
                    decoration: const InputDecoration(labelText: 'New balance'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        _formatUpdateTimestamp(selected),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton(
                        onPressed: pickDateTime,
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  if (error != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      error!,
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
                  onPressed: submit,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatUpdateTimestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = time.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}


class _TransactionsTabState extends State<TransactionsTab> {
  late final TransactionsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TransactionsController(AccountDatabase.instance)
      ..addListener(_handleControllerChange);
    _controller.load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChange)
      ..dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> refreshData() => _controller.load();

  Future<void> createTransaction() async {
    await refreshData();
    if (_controller.accountsById.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add an account before creating transactions.'),
        ),
      );
      return;
    }

    final record = await showDialog<TransactionRecord>(
      context: context,
      builder: (context) => _TransactionDialog(
        accounts: _controller.accounts,
        mostRecent: _controller.mostRecentTransaction,
        currencies: _currencyOptions(_controller.mostRecentTransaction),
      ),
    );
    if (record != null) {
      await _controller.addTransaction(record);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction saved.')),
      );
      widget.onAccountsChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: _buildBody());
  }

  Widget _buildBody() {
    if (_controller.isLoading && _controller.transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.transactions.isEmpty) {
      final hasAccounts = _controller.accountsById.isNotEmpty;
      return Center(
        child: Text(
          hasAccounts
              ? 'No transactions yet. Tap + to add one.'
              : 'Add an account before creating transactions.',
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _controller.transactions.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) {
        final transaction = _controller.transactions[index];
        final account = _controller.accountsById[transaction.accountId];
        final accountName = account?.name ?? 'Account ${transaction.accountId}';
        return ListTile(
          title: Text(transaction.title),
          subtitle: Text('$accountName • ${_formatDate(transaction.createdAt)}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${transaction.amount.toStringAsFixed(
                      suggestPrecision(transaction.currency.toUpperCase()),
                    )} ${transaction.currency}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete transaction',
                onPressed: () => _confirmDelete(transaction),
              ),
            ],
          ),
          onTap: () => _editTransaction(transaction),
        );
      },
    );
  }

  Future<void> _editTransaction(TransactionRecord transaction) async {
    final updated = await showDialog<TransactionRecord>(
      context: context,
      builder: (context) => _TransactionDialog(
        accounts: _controller.accounts,
        transaction: transaction,
        mostRecent: _controller.mostRecentTransaction,
        currencies: _currencyOptions(transaction),
      ),
    );
    if (updated != null) {
      await _controller.updateTransaction(updated);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction updated.')),
      );
      widget.onAccountsChanged?.call();
    }
  }

  Future<void> _confirmDelete(TransactionRecord transaction) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete transaction?'),
          content: Text('This will remove "${transaction.title}".'),
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
      await _controller.deleteTransaction(transaction);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${transaction.title}" deleted.')),
      );
      widget.onAccountsChanged?.call();
    }
  }

  String _formatDate(DateTime date) {
    final twoDigits = (int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
  }

  List<String> _currencyOptions([TransactionRecord? seed]) {
    final currencies = <String>{
      for (final account in _controller.accounts)
        account.currency.toUpperCase(),
    };
    final fromTransaction = seed ?? _controller.mostRecentTransaction;
    if (fromTransaction != null) {
      currencies.add(fromTransaction.currency.toUpperCase());
    }
    final options = currencies.toList()..sort();
    if (options.isEmpty) {
      options.add('EUR');
    }
    return options;
  }
}

class StatsTab extends StatefulWidget {
  const StatsTab({super.key});

  @override
  State<StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<StatsTab> {
  late final StatsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = StatsController(AccountDatabase.instance)
      ..addListener(_handleControllerChange);
    _controller.load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChange)
      ..dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> refreshData() async {
    if (_controller.isLoading) {
      return;
    }
    await _controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: _buildBody());
  }

  Widget _buildBody() {
    if (_controller.isLoading && _controller.points.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.points.isEmpty) {
      return const Center(child: Text('No balance history yet.'));
    }

    final points = _controller.points;
    final latest = points.last;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Total balance over time',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _LineChart(
              points: points,
              lineColor: colorScheme.primary,
              fillColor: colorScheme.primary.withOpacity(0.18),
              axisColor: colorScheme.outlineVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Latest total: ${latest.total.toStringAsFixed(2)} EUR\nUpdated: ${_formatTimestamp(latest.time)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.points,
    required this.lineColor,
    required this.fillColor,
    required this.axisColor,
  });

  final List<StatsPoint> points;
  final Color lineColor;
  final Color fillColor;
  final Color axisColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _LineChartPainter(
            points: points,
            lineColor: lineColor,
            fillColor: fillColor,
            axisColor: axisColor,
          ),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
    required this.axisColor,
  });

  final List<StatsPoint> points;
  final Color lineColor;
  final Color fillColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) {
      return;
    }

    final times = points
        .map((point) => point.time.millisecondsSinceEpoch)
        .toList(growable: false);
    final values = points.map((point) => point.total).toList(growable: false);

    int minTime = times.first;
    int maxTime = times.first;
    double minValue = values.first;
    double maxValue = values.first;

    for (final time in times) {
      if (time < minTime) minTime = time;
      if (time > maxTime) maxTime = time;
    }
    for (final value in values) {
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }

    double timeRange = (maxTime - minTime).abs().toDouble();
    if (timeRange == 0) {
      timeRange = 1;
    }
    double valueRange = (maxValue - minValue).abs();
    if (valueRange < 0.0001) {
      valueRange = 0.0001;
    }

    final path = Path();
    final offsets = <Offset>[];

    for (var i = 0; i < points.length; i++) {
      double position =
          (times[i] - minTime).toDouble() / timeRange;
      if (position.isNaN) {
        position = 0;
      }
      if (position < 0) {
        position = 0;
      } else if (position > 1) {
        position = 1;
      }
      double valueRatio = (values[i] - minValue) / valueRange;
      if (valueRatio.isNaN) {
        valueRatio = 0;
      }
      if (valueRatio < 0) {
        valueRatio = 0;
      } else if (valueRatio > 1) {
        valueRatio = 1;
      }
      final double dx = position * size.width;
      final double dy = size.height - valueRatio * size.height;
      final offset = Offset(dx, dy);
      offsets.add(offset);
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );

    if (offsets.length > 1) {
      final fillPath = Path.from(path)
        ..lineTo(offsets.last.dx, size.height)
        ..lineTo(offsets.first.dx, size.height)
        ..close();

      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (offsets.length > 1) {
      canvas.drawPath(path, linePaint);
    }

    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    for (final offset in offsets) {
      canvas.drawCircle(offset, 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.axisColor != axisColor;
  }
}

class _TransactionDialog extends StatefulWidget {
  const _TransactionDialog({
    required this.accounts,
    required this.currencies,
    this.transaction,
    this.mostRecent,
  });

  final List<Account> accounts;
  final List<String> currencies;
  final TransactionRecord? transaction;
  final TransactionRecord? mostRecent;

  bool get isEditing => transaction != null;

  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final DateTime _createdAt;
  String? _selectedCurrency;
  int? _selectedAccountId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.transaction;
    Account? defaultAccount;
    if (existing != null) {
      defaultAccount = _findAccount(widget.accounts, existing.accountId);
    } else if (widget.mostRecent != null) {
      defaultAccount = _findAccount(widget.accounts, widget.mostRecent!.accountId);
    }
    defaultAccount ??=
        widget.accounts.isNotEmpty ? widget.accounts.first : null;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _amountController = TextEditingController(
      text: existing != null
          ? existing.amount
              .toStringAsFixed(suggestPrecision(existing.currency.toUpperCase()))
          : '',
    );
    _selectedAccountId = existing?.accountId ?? defaultAccount?.id;
    _selectedCurrency = _resolveInitialCurrency(
      existing?.currency,
      widget.mostRecent?.currency,
      defaultAccount?.currency,
    );
    _createdAt = existing?.createdAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isEditing ? 'Edit transaction' : 'Add transaction';

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: '0.00',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCurrency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: _buildCurrencyItems(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedCurrency = value;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _selectedAccountId,
              decoration: const InputDecoration(labelText: 'Account'),
              items: _buildAccountItems(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedAccountId = value;
                  final account = _findAccountById(value);
                  if (!widget.isEditing && account != null) {
                    _selectedCurrency = account.currency.toUpperCase();
                  }
                });
              },
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
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

  List<DropdownMenuItem<int>> _buildAccountItems() {
    final items = widget.accounts
        .where((account) => account.id != null)
        .map(
          (account) => DropdownMenuItem<int>(
            value: account.id,
            child: Text(account.name),
          ),
        )
        .toList();

    final selectedId = _selectedAccountId;
    final hasSelection = selectedId == null
        ? true
        : items.any((item) => item.value == selectedId);
    if (selectedId != null && !hasSelection) {
      items.insert(
        0,
        DropdownMenuItem<int>(
          value: selectedId,
          child: Text('Account $selectedId (missing)'),
        ),
      );
    }
    return items;
  }

  Account? _findAccountById(int id) {
    for (final account in widget.accounts) {
      if (account.id == id) {
        return account;
      }
    }
    return null;
  }

  Account? _findAccount(List<Account> accounts, int? id) {
    if (id == null) {
      return null;
    }
    for (final account in accounts) {
      if (account.id == id) {
        return account;
      }
    }
    return null;
  }

  List<DropdownMenuItem<String>> _buildCurrencyItems() {
    final items = widget.currencies
        .map(
          (currency) => DropdownMenuItem<String>(
            value: currency,
            child: Text(currency),
          ),
        )
        .toList();
    final selected = _selectedCurrency;
    if (selected != null && !items.any((item) => item.value == selected)) {
      items.insert(
        0,
        DropdownMenuItem<String>(
          value: selected,
          child: Text('$selected (missing)'),
        ),
      );
    }
    return items;
  }

  String? _resolveInitialCurrency(
    String? existing,
    String? mostRecent,
    String? accountCurrency,
  ) {
    final fallback = widget.currencies.isNotEmpty ? widget.currencies.first : null;
    return (existing ?? mostRecent ?? accountCurrency ?? fallback ?? 'EUR')
        .toUpperCase();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _setError('Title cannot be empty.');
      return;
    }

    final parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null) {
      _setError('Amount must be a number.');
      return;
    }

    final currency = _selectedCurrency;
    if (currency == null || currency.isEmpty) {
      _setError('Currency cannot be empty.');
      return;
    }

    final accountId = _selectedAccountId;
    if (accountId == null) {
      _setError('Select an account.');
      return;
    }

    final existing = widget.transaction;
    final createdAt = _createdAt;

    final result = existing?.copyWith(
          title: title,
          createdAt: createdAt,
          amount: parsedAmount,
          currency: currency,
          accountId: accountId,
        ) ??
        TransactionRecord(
          title: title,
          createdAt: createdAt,
          amount: parsedAmount,
          currency: currency,
          accountId: accountId,
        );
    Navigator.of(context).pop(result);
  }

  void _setError(String message) {
    setState(() {
      _error = message;
    });
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
    _balanceController = TextEditingController(
      text: widget.account.balance.toStringAsFixed(2),
    );
    _currencyController = TextEditingController(text: widget.account.currency);
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
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _balanceController,
            decoration: const InputDecoration(
              labelText: 'Balance',
              hintText: '0.00',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currencyController,
            decoration: const InputDecoration(
              labelText: 'Currency',
              hintText: 'EUR',
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: 8,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
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

    final parsedBalance = double.tryParse(_balanceController.text.trim());
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
