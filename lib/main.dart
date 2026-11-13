import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'services/statement_file_picker_options.dart';

import 'package:excel_community/excel_community.dart' hide Border;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import 'services/spending_target_store.dart';
import 'services/spending_target_service.dart';
import 'widgets/spending_targets_screen.dart';
import 'models/transaction.dart';
import 'models/statement_source.dart';
import 'services/google_sheet_statement_service.dart';
import 'widgets/google_sheet_import_dialog.dart';
import 'models/financial_baseline.dart';
import 'models/expense_category.dart';
import 'services/daily_reminder_service.dart';
import 'services/financial_baseline_sheets_sync_service.dart';
import 'services/financial_baseline_store.dart';
import 'services/expense_category_store.dart';
import 'services/expense_category_sheets_sync_service.dart';
import 'services/google_drive_permission_service.dart';
import 'services/google_sign_in_configuration.dart';
import 'services/google_sheets_service.dart';
import 'services/local_transaction_store.dart';
import 'services/merchant_classification_store.dart';
import 'widgets/merchant_baseline_panel.dart';
import 'services/monthly_rollover_service.dart';
import 'services/budget_comparison.dart';
import 'services/spending_insights_service.dart';
import 'services/statement_file_reader.dart';
import 'services/statement_document_picker.dart';
import 'services/suggested_budget_service.dart';
import 'services/transaction_filter.dart';
import 'services/worker_csv_sync_service.dart';
import 'widgets/expense_category_selector.dart';
import 'widgets/expense_category_management_screen.dart';
import 'widgets/daily_reminder_settings_dialog.dart';
import 'widgets/financial_baseline_screen.dart';
import 'widgets/favourite_spending_spots_widget.dart';
import 'widgets/pocket_ledger_web_access.dart';
import 'widgets/feedback_dialog.dart';
import 'widgets/help_screen.dart';
import 'widgets/monthly_budget_card.dart';
import 'widgets/monthly_budget_target_dialog.dart';
import 'widgets/spending_summary_widget.dart';
import 'widgets/suggested_budget_sheet.dart';
import 'widgets/statement_review_dialog.dart';
import 'widgets/statement_import_complete_dialog.dart';
import 'utils/currency_format.dart';
import 'utils/transaction_period_format.dart';

final GoogleSignIn _googleSignIn = createGoogleSignIn();
final GoogleDrivePermissionService _drivePermissionService =
    GoogleDrivePermissionService(_googleSignIn);
final SpendingInsightsService _spendingInsightsService =
    SpendingInsightsService();
final DailyReminderService _dailyReminderService = DailyReminderService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint(details.exceptionAsString());
  };

  runApp(const PocketLedgerApp());
}

class PocketLedgerApp extends StatefulWidget {
  const PocketLedgerApp({super.key, this.googleSignIn});

  final GoogleSignIn? googleSignIn;

  @override
  State<PocketLedgerApp> createState() => _PocketLedgerAppState();
}

class _PocketLedgerAppState extends State<PocketLedgerApp> {
  static const _darkModePreferenceKey = 'dark_mode_enabled';

  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThemePreference());
  }

  Future<void> _loadThemePreference() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (mounted) {
        setState(
          () => _isDarkMode =
              preferences.getBool(_darkModePreferenceKey) ?? false,
        );
      }
    } catch (error) {
      debugPrint('Could not load theme preference: $error');
    }
  }

  Future<void> _setDarkMode(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_darkModePreferenceKey, enabled);
    if (mounted) setState(() => _isDarkMode = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Ledger',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: AuthGate(
        isDarkMode: _isDarkMode,
        onDarkModeChanged: _setDarkMode,
        googleSignIn: widget.googleSignIn,
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1B4D3E),
      primary: isLight ? const Color(0xFF1B4D3E) : const Color(0xFF9DD7C2),
      brightness: brightness,
      surface: isLight ? const Color(0xFFF7F9F8) : null,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
    );
  }
}

class AuthGate extends StatefulWidget {
  final GoogleSignIn? googleSignIn;
  final bool isDarkMode;
  final Future<void> Function(bool) onDarkModeChanged;

  const AuthGate({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
    this.googleSignIn,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  GoogleSignIn get _signIn => widget.googleSignIn ?? _googleSignIn;
  GoogleSignInAccount? _currentUser;
  bool _isLoading = true;
  late final StreamSubscription<GoogleSignInAccount?> _userSubscription;

  @override
  void initState() {
    super.initState();

    _userSubscription = _signIn.onCurrentUserChanged.listen((account) {
      if (!mounted) return;

      setState(() {
        _currentUser = account;
        _isLoading = false;
      });
    });

    unawaited(_restoreSignedInUser());
  }

  Future<void> _restoreSignedInUser() async {
    try {
      final account = await _signIn.signInSilently(suppressErrors: false);
      if (mounted) setState(() => _currentUser = account);
    } catch (error) {
      // Expired credentials or an unavailable native sign-in SDK must not
      // strand the user on the startup spinner. Manual sign-in can retry.
      debugPrint('Could not restore Google sign-in: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    unawaited(_userSubscription.cancel());
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    try {
      setState(() => _isLoading = true);
      await _signIn.signIn();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Sign in failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/app_icon_foreground.png',
                key: const ValueKey('loading-logo'),
                width: 72,
                height: 72,
              ),
              const SizedBox(height: 6),
              Text(
                'Pocket Ledger',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const _BrandTagline(textAlign: TextAlign.center, fontSize: 14),
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    if (_currentUser == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B4D3E).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 64,
                    color: Color(0xFF1B4D3E),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Pocket Ledger',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const _BrandTagline(textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text(
                  'Track expenses privately in your personal Google Drive',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 48),
                ElevatedButton.icon(
                  onPressed: _handleSignIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B4D3E),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DashboardScreen(
      key: ValueKey(_currentUser!.email),
      account: _currentUser!,
      isDarkMode: widget.isDarkMode,
      onDarkModeChanged: widget.onDarkModeChanged,
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final GoogleSignInAccount account;
  final bool isDarkMode;
  final Future<void> Function(bool) onDarkModeChanged;

  const DashboardScreen({
    super.key,
    required this.account,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final WorkerCsvSyncService _workerCsvSyncService = WorkerCsvSyncService(
    http.Client(),
  );
  late final LocalTransactionStore _localTransactionStore;
  late final FinancialBaselineStore _financialBaselineStore;
  late final SpendingTargetStore _spendingTargetStore;
  bool _targetHistoryComplete = false;
  late final ExpenseCategoryStore _expenseCategoryStore;

  String _currency = '\$';
  String _selectedCategory = 'Food / Household';
  String? _selectedCategoryId;
  List<ExpenseCategory> _expenseCategories = [];
  List<ExpenseCategoryMapping> _categoryMappings = [];
  ExpenseType _selectedExpenseType = ExpenseType.unknown;
  bool _manualCategoryEdited = false;
  DateTime _selectedExpenseDate = DateUtils.dateOnly(DateTime.now());

  bool _isSaving = false;
  bool _isWorkerSyncing = false;
  String? _workerSyncStatus;
  // True until the first Google Sheets sync finishes (or is blocked), so the
  // dashboard shows progress instead of looking like "$0".
  bool _isInitialSync = true;
  // True when the browser restored the account but gave us no usable access
  // token, so the user must grant Drive/Sheets access once.
  bool _needsDriveAccess = false;
  double? _monthlyTarget;
  double? _previousMonthBudget;
  DateTime _heroMonth = monthStart(DateTime.now());
  // Budget recorded for _heroMonth when it is a past month.
  double? _heroMonthBudget;
  final SuggestedBudgetService _suggestedBudgetService =
      SuggestedBudgetService();
  bool _dailyReminderEnabled = false;
  TimeOfDay _dailyReminderTime = const TimeOfDay(hour: 20, minute: 30);
  String? _spreadsheetId;
  String? _workerSpreadsheetId;
  List<Transaction> _transactions = [];
  late final MerchantClassificationStore _merchantStore =
      MerchantClassificationStore(widget.account.email);
  List<FinancialBaselineMapping> _baselineMappings = [];
  int _selectedTab = 0;
  Timer? _calendarRefreshTimer;
  final FinancialBaselineSheetsSyncService _baselineSheetsSyncService =
      FinancialBaselineSheetsSyncService();
  final ExpenseCategorySheetsSyncService _expenseCategorySheetsSyncService =
      ExpenseCategorySheetsSyncService();
  final GoogleSheetsService _googleSheetsService = GoogleSheetsService();

  String get _workerSpreadsheetPreferenceKey =>
      'worker_spreadsheet_id_${widget.account.email.toLowerCase()}';

  double _calculateCategoryTypeCategorySpend(
    String category,
    String period,
    ExpenseType expenseType, {
    DateTime? targetMonth,
  }) {
    final activeMonth = targetMonth ?? _heroMonth;
    final now = DateTime.now();
    return _transactions
        .where((transaction) {
          final date = transaction.date;
          final isInPeriod = switch (period) {
            'today' =>
              date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day,
            'month' =>
              date.year == activeMonth.year && date.month == activeMonth.month,
            'year' => date.year == activeMonth.year,
            _ => false,
          };
          return isInPeriod &&
              transaction.category == category &&
              transaction.expenseType == expenseType;
        })
        .fold<double>(0, (total, transaction) => total + transaction.amount);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleCalendarRefresh();
    _localTransactionStore = LocalTransactionStore(
      accountKey: widget.account.email,
    );
    _financialBaselineStore = FinancialBaselineStore(
      accountKey: widget.account.email,
    );
    _expenseCategoryStore = ExpenseCategoryStore(
      accountKey: widget.account.email,
    );
    _spendingTargetStore = SpendingTargetStore(
      accountKey: widget.account.email,
    );
    _loadCurrencyAndInitDrive();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _refreshPreviousMonthBudget();
      _scheduleCalendarRefresh();
    }
  }

  void _scheduleCalendarRefresh() {
    _calendarRefreshTimer?.cancel();
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _calendarRefreshTimer = Timer(
      nextDay.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(() {});
        _refreshPreviousMonthBudget();
        _scheduleCalendarRefresh();
      },
    );
  }

  void _selectHeroMonth(DateTime month) {
    setState(() {
      _heroMonth = month;
      _heroMonthBudget = null;
    });
    unawaited(_loadHeroMonthBudget());
  }

  Future<void> _loadHeroMonthBudget() async {
    final month = _heroMonth;
    try {
      final budget = await MonthlyBudgetSnapshotStore().budgetForMonth(month);
      // Ignore the result if the user has moved to another month meanwhile.
      if (!mounted || !isSameMonth(month, _heroMonth)) return;
      setState(() => _heroMonthBudget = budget);
    } catch (error) {
      if (!mounted || !isSameMonth(month, _heroMonth)) return;
      setState(() => _heroMonthBudget = null);
      _showMessage('Could not load the budget for that month: $error');
    }
  }

  Future<void> _refreshPreviousMonthBudget() async {
    try {
      final previousMonthBudget = await MonthlyBudgetSnapshotStore().initialize(
        currentBudget: _monthlyTarget,
      );
      if (mounted) {
        setState(() => _previousMonthBudget = previousMonthBudget);
        unawaited(_loadHeroMonthBudget());
      }
    } catch (error) {
      _showMessage('Could not update monthly budget history: $error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _calendarRefreshTimer?.cancel();
    _amountController.dispose();
    _descController.dispose();
    _workerCsvSyncService.close();
    super.dispose();
  }

  Future<void> _loadCurrencyAndInitDrive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCurrency = prefs.getString('currency_symbol');
      final savedMonthlyTarget = prefs.getDouble('monthly_target');
      final previousMonthBudget = await MonthlyBudgetSnapshotStore().initialize(
        currentBudget: savedMonthlyTarget,
      );
      final reminderEnabled = prefs.getBool('daily_reminder_enabled') ?? false;
      final reminderHour = prefs.getInt('daily_reminder_hour') ?? 20;
      final reminderMinute = prefs.getInt('daily_reminder_minute') ?? 30;
      final workerSpreadsheetId = prefs.getString(
        _workerSpreadsheetPreferenceKey,
      );
      await _merchantStore.load();
      final cachedTransactions = await _localTransactionStore.loadCached();
      final baselineMappings = await _financialBaselineStore.loadMappings();
      await _spendingTargetStore.load();
      final categoryData = await _expenseCategoryStore.load();
      final savedCategories =
          categoryData['categories'] as List<ExpenseCategory>;
      final categoryMappings =
          categoryData['mappings'] as List<ExpenseCategoryMapping>;

      if (savedCurrency == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showCurrencyPicker();
        });
      }

      if (mounted) {
        setState(() {
          if (savedCurrency != null) _currency = savedCurrency;
          _monthlyTarget = savedMonthlyTarget;
          _previousMonthBudget = previousMonthBudget;
          _dailyReminderEnabled = reminderEnabled;
          _dailyReminderTime = TimeOfDay(
            hour: reminderHour,
            minute: reminderMinute,
          );
          _workerSpreadsheetId = workerSpreadsheetId;
          _transactions = cachedTransactions
              .map(_merchantStore.index.apply)
              .map(tagInternalTransfer)
              .toList(growable: false);
          _baselineMappings = baselineMappings;
          _expenseCategories = savedCategories;
          _categoryMappings = categoryMappings;
        });
        unawaited(_loadHeroMonthBudget());
      }

      // Retire scan reminders without changing normal expense reminders.
      for (final key
          in prefs
              .getKeys()
              .where((k) => k.startsWith('email_review_reminder_'))
              .toList()) {
        await prefs.remove(key);
      }
      if (!kIsWeb) {
        try {
          await _dailyReminderService.cancelRetiredEmailReminder();
        } catch (_) {
          /* Retry cancellation on the next app launch. */
        }
      }
      if (reminderEnabled && !kIsWeb) {
        try {
          await _dailyReminderService.scheduleDaily(
            TimeOfDay(hour: reminderHour, minute: reminderMinute),
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not restore daily reminder: $error'),
              ),
            );
          }
        }
      }

      await _initSpreadsheet();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not initialize expenses: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isInitialSync = false);
    }
  }

  /// Web sign-in can restore the account a moment before an access token is
  /// available. Give it a short chance to arrive before asking the user.
  Future<bool> _waitForGoogleAccess() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (await _googleSignIn.authenticatedClient() != null) return true;
      } catch (error) {
        debugPrint('Waiting for Google access: $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  void _markDriveAccessNeeded() {
    if (mounted) setState(() => _needsDriveAccess = true);
  }

  /// Tapped from the "Connect Google Drive" banner (a user gesture, which
  /// browsers require before showing the Google permission popup).
  Future<void> _connectGoogleDrive() async {
    try {
      final granted = await _drivePermissionService.ensureDriveWritePermission(
        context,
      );
      if (!granted) return;
      if (mounted) setState(() => _isInitialSync = true);
      await _initSpreadsheet();
    } catch (error) {
      _showMessage('Could not connect to Google Drive: $error');
    } finally {
      if (mounted) setState(() => _isInitialSync = false);
    }
  }

  Map<String, Object?> get _categoryConfiguration => {
    'categories': withHomeMaintenance(_expenseCategories)
        .map((c) => c.toJson())
        .toList(),
    'mappings': _categoryMappings.map((m) => m.toJson()).toList(),
  };

  String? _categoryIdForName(String name) {
    final existing = withHomeMaintenance(_expenseCategories)
        .where((c) => c.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (existing != null) return existing.id;
    for (final entry in defaultExpenseParents.entries) {
      if (entry.value.toLowerCase() == name.toLowerCase()) return entry.key;
    }
    return null;
  }

  List<ExpenseCategory> get _activeExpenseCategories {
    final active = <ExpenseCategory>[];
    for (final entry in defaultExpenseParents.entries) {
      final children =
          _expenseCategories
              .where(
                (category) =>
                    category.parentId == entry.key &&
                    category.active &&
                    !category.archived,
              )
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      if (children.isNotEmpty) {
        active.addAll(children);
      } else {
        active.add(
          ExpenseCategory(
            id: entry.key,
            parentId: entry.key,
            name: entry.value,
          ),
        );
      }
    }
    return withHomeMaintenance(active);
  }

  Future<void> _saveExpenseCategories(List<ExpenseCategory> categories) async {
    final oldById = {
      for (final category in _expenseCategories) category.id: category,
    };
    final newById = {for (final category in categories) category.id: category};
    final renamedTransactions = <Transaction>[];
    final updatedTransactions = _transactions.map((transaction) {
      final oldCategory = transaction.categoryId == null
          ? null
          : oldById[transaction.categoryId];
      final newCategory = transaction.categoryId == null
          ? null
          : newById[transaction.categoryId];
      if (newCategory != null &&
          !newCategory.archived &&
          transaction.category != newCategory.name) {
        final renamed = transaction.copyWith(category: newCategory.name);
        renamedTransactions.add(renamed);
        return renamed;
      }
      if (oldCategory != null &&
          newCategory == null &&
          transaction.category == oldCategory.name) {
        return transaction;
      }
      return transaction;
    }).toList();
    final masterRenames = <Map<String, dynamic>>[];
    for (final record in _merchantStore.records.values) {
      final category = newById[record['categoryId']];
      if (category != null &&
          !category.archived &&
          record['category'] != category.name) {
        masterRenames.add({...record, 'category': category.name});
      }
    }
    if (masterRenames.isNotEmpty) await _merchantStore.save(masterRenames);
    await _expenseCategoryStore.save(
      categories: categories,
      mappings: _categoryMappings,
    );
    for (final transaction in renamedTransactions) {
      await _localTransactionStore.upsertPending(transaction);
    }
    await _localTransactionStore.saveCached(updatedTransactions);
    if (!mounted) return;
    setState(() {
      _expenseCategories = categories;
      _transactions = updatedTransactions;
      if (!_activeExpenseCategories.any(
        (c) => c.name == _selectedCategory || c.id == _selectedCategoryId,
      )) {
        final fallback = _activeExpenseCategories.first;
        _selectedCategory = fallback.name;
        _selectedCategoryId = fallback.id;
      }
    });
    try {
      await _syncExpenseCategories(preferLocal: true);
      if (renamedTransactions.isNotEmpty) await _fetchData();
      _showMessage('Expense categories saved and synced.');
    } catch (error) {
      _showMessage(
        'Categories saved on this device. Could not sync to Sheets: $error',
      );
    }
  }

  Future<void> _saveExpenseMappings(
    List<ExpenseCategoryMapping> mappings,
  ) async {
    _categoryMappings = mappings;
    await _expenseCategoryStore.save(
      categories: _expenseCategories,
      mappings: mappings,
    );
    try {
      await _syncExpenseCategories(preferLocal: true);
      _showMessage('Import category rules saved and synced.');
    } catch (error) {
      _showMessage(
        'Rules saved on this device. Could not sync them to Sheets: $error',
      );
    }
  }

  Future<void> _showCategorySetupPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final key =
        'expense_category_setup_done_${widget.account.email.toLowerCase()}';
    if (prefs.getBool(key) == true || !mounted) return;
    final customize = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customize your expense categories'),
        content: const Text(
          'Choose the subcategories you use now. You can skip this and start recording expenses with the six main categories. Categories can be changed later in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue with defaults'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Customize'),
          ),
        ],
      ),
    );
    await prefs.setBool(key, true);
    if (customize == true && mounted) await _openExpenseCategorySettings();
  }

  Future<void> _openExpenseCategorySettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ExpenseCategoryManagementScreen(
          categories: withHomeMaintenance(_expenseCategories),
          onChanged: (categories) =>
              unawaited(_saveExpenseCategories(categories)),
        ),
      ),
    );
  }

  void _showCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final currencies = [
          {'symbol': '\$', 'label': 'USD / CAD / AUD (\$)'},
          {'symbol': '₹', 'label': 'INR (₹)'},
          {'symbol': 'RM', 'label': 'MYR (RM)'},
          {'symbol': '€', 'label': 'EUR (€)'},
          {'symbol': '£', 'label': 'GBP (£)'},
        ];

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome to Pocket Ledger!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Please choose your primary currency:'),
              const SizedBox(height: 16),
              ...currencies.map(
                (c) => ListTile(
                  leading: Text(
                    c['symbol']!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  title: Text(c['label']!),
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('currency_symbol', c['symbol']!);
                    if (!mounted) return;
                    setState(() => _currency = c['symbol']!);
                    navigator.pop();
                    unawaited(_showCategorySetupPrompt());
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _initSpreadsheet() async {
    try {
      var client = await _googleSignIn.authenticatedClient();
      if (client == null && await _waitForGoogleAccess()) {
        client = await _googleSignIn.authenticatedClient();
      }
      if (client == null) {
        // Previously this returned silently, leaving every number at 0.
        _markDriveAccessNeeded();
        return;
      }
      if (mounted && _needsDriveAccess) {
        setState(() => _needsDriveAccess = false);
      }

      final driveApi = drive.DriveApi(client);
      final sheetsApi = sheets.SheetsApi(client);

      final fileList = await driveApi.files.list(
        q: "name = 'Expense Tracker DB' and mimeType = 'application/vnd.google-apps.spreadsheet' and trashed = false",
      );

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        _spreadsheetId = fileList.files!.first.id;
      } else {
        final newSheet = sheets.Spreadsheet(
          properties: sheets.SpreadsheetProperties(title: 'Expense Tracker DB'),
        );
        final created = await sheetsApi.spreadsheets.create(newSheet);
        _spreadsheetId = created.spreadsheetId;

        final headerValues = [GoogleSheetsService.transactionHeaders];
        final valueRange = sheets.ValueRange(values: headerValues);
        await sheetsApi.spreadsheets.values.append(
          valueRange,
          _spreadsheetId!,
          'Sheet1!A1',
          valueInputOption: 'USER_ENTERED',
        );
      }
      await _fetchData();
      await _syncExpenseCategories(preferLocal: false);
      try {
        await _syncBaselineMappings(sheetsApi);
        await _syncSpendingTargets(sheetsApi);
      } catch (error) {
        _showMessage('Could not sync baseline metadata: $error');
      }
    } catch (e) {
      debugPrint("Spreadsheet setup error: $e");
      rethrow;
    }
  }

  Future<void> _fetchData() async {
    if (_spreadsheetId == null) {
      try {
        await _initSpreadsheet();
      } catch (error) {
        _showMessage('Could not connect to the expense spreadsheet: $error');
      }
      return;
    }
    try {
      var client = await _googleSignIn.authenticatedClient();
      if (client == null && await _waitForGoogleAccess()) {
        client = await _googleSignIn.authenticatedClient();
      }
      if (client == null) {
        _markDriveAccessNeeded();
        return;
      }

      final sheetsApi = sheets.SheetsApi(client);
      final transactions = await _readSheetTransactions(sheetsApi);
      var hasSyncedChanges = false;
      final pending = (await _localTransactionStore.loadPending())
          .map(tagInternalTransfer)
          .toList(growable: false);
      final remoteIds = transactions
          .map((transaction) => transaction.id)
          .whereType<String>()
          .toSet();
      final remainingPending = <Transaction>[];
      final pendingAppends = <Transaction>[];
      final pendingUpdates = <Transaction>[];
      for (final transaction in pending) {
        if (transaction.sheetRow == null &&
            transaction.id != null &&
            remoteIds.contains(transaction.id)) {
          hasSyncedChanges = true;
          continue;
        }
        // Already lived in the sheet (has a row number) but its ID is gone:
        // the row was deleted in Google Sheets. Drop the stale local copy
        // instead of writing it into whatever row now sits at that number.
        if (transaction.sheetRow != null &&
            transaction.id != null &&
            !remoteIds.contains(transaction.id)) {
          debugPrint(
            'Dropping locally cached row deleted in Sheets: '
            '${transaction.id}',
          );
          continue;
        }
        if (transaction.sheetRow == null) {
          pendingAppends.add(transaction);
          continue;
        }
        pendingUpdates.add(transaction);
      }
      if (pendingAppends.isNotEmpty) {
        try {
          await _writeTransactions(sheetsApi, pendingAppends);
          hasSyncedChanges = true;
        } catch (error) {
          debugPrint('Could not sync pending expenses: $error');
          remainingPending.addAll(pendingAppends);
        }
      }
      for (final transaction in pendingUpdates) {
        try {
          await _writeTransaction(sheetsApi, transaction);
          hasSyncedChanges = true;
        } catch (error) {
          debugPrint('Could not sync expense ${transaction.id}: $error');
          remainingPending.add(transaction);
        }
      }
      await _localTransactionStore.savePending(remainingPending);
      final refreshedTransactions = hasSyncedChanges
          ? await _readSheetTransactions(sheetsApi)
          : transactions;
      final mergedTransactions = [...refreshedTransactions];
      for (final localTransaction in remainingPending) {
        // Match by ID. Row numbers shift when rows are deleted, so only fall
        // back to them for items that have no ID.
        final index = localTransaction.id != null
            ? mergedTransactions.indexWhere(
                (saved) => saved.id == localTransaction.id,
              )
            : mergedTransactions.indexWhere(
                (saved) =>
                    localTransaction.sheetRow != null &&
                    saved.sheetRow == localTransaction.sheetRow,
              );
        if (index < 0 && localTransaction.sheetRow != null) continue;
        if (index < 0) {
          mergedTransactions.add(localTransaction);
        } else {
          mergedTransactions[index] = localTransaction;
        }
      }
      try {
        await _merchantStore.synchronize(
          sheetsApi,
          _spreadsheetId!,
          refreshedTransactions,
        );
      } catch (error) {
        _showMessage(
          'Merchant classifications saved locally; sync will retry: $error',
        );
      }
      final effectiveTransactions = mergedTransactions
          .map(_merchantStore.index.apply)
          .toList(growable: false);
      await _localTransactionStore.saveCached(effectiveTransactions);
      if (!mounted) return;
      setState(() {
        _transactions = effectiveTransactions;
        _targetHistoryComplete = true;
      });
      if (_spendingTargetStore.hasPending) {
        try {
          await _syncSpendingTargets(sheetsApi);
        } catch (_) {
          /* Durable target outbox retries later. */
        }
      }
      if (remainingPending.isNotEmpty) {
        _showMessage(
          '${remainingPending.length} expense change(s) still waiting to sync.',
        );
      }
    } catch (error) {
      debugPrint('Fetch or sync error: $error');
      _showMessage('Could not refresh expenses: $error');
    }
  }

  Future<List<Transaction>> _readSheetTransactions(
    sheets.SheetsApi sheetsApi, {
    String? spreadsheetId,
  }) async {
    final targetId = spreadsheetId ?? _spreadsheetId!;
    await _googleSheetsService.validateSheetHeaders(
      sheetsApi: sheetsApi,
      spreadsheetId: targetId,
      range: 'Sheet1!A1:G1',
      expected: GoogleSheetsService.transactionHeaders,
      acceptedAlternatives: const {
        2: {'Type'},
      },
      canonicalizationRanges: const {2: 'Sheet1!C1'},
      allowMissingTrailingHeaders: true,
      trailingHeaderCellRanges: const {
        4: 'Sheet1!E1',
        5: 'Sheet1!F1',
        6: 'Sheet1!G1',
      },
    );
    final response = await sheetsApi.spreadsheets.values.get(
      targetId,
      'Sheet1!A1:G',
    );
    final transactions = <Transaction>[];
    final allRows = response.values ?? const <List<Object?>>[];
    final rows = allRows.length > 1
        ? allRows.skip(1).toList(growable: false)
        : const <List<Object?>>[];
    final identifiers = <List<Object?>>[];
    final categoryIdentifiers = <List<Object?>>[];
    var needsIdMigration = false;
    var needsCategoryIdMigration = false;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final transaction = Transaction.tryParseSheetRow(row);
      final existingId = row.length > 5 && row[5].toString().trim().isNotEmpty
          ? row[5].toString().trim()
          : null;
      final categoryId = row.length > 6 && row[6].toString().trim().isNotEmpty
          ? row[6].toString().trim()
          : transaction == null
          ? null
          : _categoryIdForName(transaction.category);
      final id = transaction == null
          ? existingId ?? ''
          : existingId ?? Transaction.createId();
      identifiers.add([id]);
      categoryIdentifiers.add([categoryId ?? '']);
      if (transaction != null &&
          categoryId != null &&
          (row.length <= 6 || row[6].toString().trim().isEmpty))
        needsCategoryIdMigration = true;
      if (transaction != null && existingId == null) {
        needsIdMigration = true;
      }

      if (transaction != null) {
        final taggedTransaction = tagInternalTransfer(transaction);
        transactions.add(
          Transaction(
            date: taggedTransaction.date,
            amount: taggedTransaction.amount,
            category: taggedTransaction.category,
            description: taggedTransaction.description,
            expenseType: taggedTransaction.expenseType,
            originalExpenseType: taggedTransaction.originalExpenseType,
            baselineGroup: taggedTransaction.baselineGroup,
            id: id,
            sheetRow: index + 2,
            categoryId: categoryId,
          ),
        );
      }
    }
    if (needsIdMigration) {
      await sheetsApi.spreadsheets.values.update(
        sheets.ValueRange(values: identifiers),
        targetId,
        'Sheet1!F2:F${rows.length + 1}',
        valueInputOption: 'RAW',
      );
    }
    if (needsCategoryIdMigration) {
      await sheetsApi.spreadsheets.values.update(
        sheets.ValueRange(values: categoryIdentifiers),
        targetId,
        'Sheet1!G2:G${rows.length + 1}',
        valueInputOption: 'RAW',
      );
    }
    return transactions;
  }

  Future<void> _syncExpenseCategories({required bool preferLocal}) async {
    final client = await _googleSignIn.authenticatedClient();
    final spreadsheetId = _spreadsheetId;
    if (client == null || spreadsheetId == null) return;
    final result = await _expenseCategorySheetsSyncService.sync(
      sheetsApi: sheets.SheetsApi(client),
      spreadsheetId: spreadsheetId,
      categories: _expenseCategories,
      mappings: _categoryMappings,
      preferLocal: preferLocal,
    );
    final categories = result['categories'] as List<ExpenseCategory>;
    final mappings = result['mappings'] as List<ExpenseCategoryMapping>;
    await _expenseCategoryStore.save(
      categories: categories,
      mappings: mappings,
    );
    if (mounted)
      setState(() {
        _expenseCategories = categories;
        _categoryMappings = mappings;
      });
  }

  Future<void> _syncBaselineMappings(sheets.SheetsApi sheetsApi) async {
    final spreadsheetId = _spreadsheetId;
    if (spreadsheetId == null || spreadsheetId.isEmpty) {
      throw StateError('Could not resolve the Expense Tracker DB spreadsheet.');
    }
    final pending = await _financialBaselineStore.loadPendingSync();
    if (pending != null) {
      await _baselineSheetsSyncService.syncChanges(
        sheetsApi: sheetsApi,
        spreadsheetId: spreadsheetId,
        mappings: pending.upserts,
        removedMerchants: pending.removals,
      );
      await _financialBaselineStore.clearPendingSync();
    }

    final remoteMappings = await _baselineSheetsSyncService.loadMappings(
      sheetsApi: sheetsApi,
      spreadsheetId: spreadsheetId,
    );
    String key(FinancialBaselineMapping mapping) => mapping.merchantFingerprint
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    final merged = <String, FinancialBaselineMapping>{
      for (final mapping in remoteMappings) key(mapping): mapping,
    };
    final missingLocally = <FinancialBaselineMapping>[];
    for (final mapping in _baselineMappings) {
      if (!merged.containsKey(key(mapping))) {
        merged[key(mapping)] = mapping;
        missingLocally.add(mapping);
      }
    }
    final refreshed = merged.values.toList(growable: false);
    await _financialBaselineStore.saveMappings(refreshed);
    if (mounted) setState(() => _baselineMappings = refreshed);
    if (missingLocally.isNotEmpty) {
      await _baselineSheetsSyncService.syncChanges(
        sheetsApi: sheetsApi,
        spreadsheetId: spreadsheetId,
        mappings: missingLocally,
      );
    }
  }

  Future<String?> _saveBaselineMappings(
    List<FinancialBaselineMapping> mappings,
  ) async {
    final oldByKey = {
      for (final mapping in _baselineMappings)
        mapping.merchantFingerprint.trim().toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        ): mapping,
    };
    final newByKey = {
      for (final mapping in mappings)
        mapping.merchantFingerprint.trim().toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        ): mapping,
    };
    final changedKeys = {
      ...oldByKey.keys,
      ...newByKey.keys,
    }.where((key) => oldByKey[key]?.group != newByKey[key]?.group).toSet();
    final batch = FinancialBaselineSyncBatch(
      upserts: [
        for (final key in changedKeys)
          if (newByKey[key] != null) newByKey[key]!,
      ],
      removals: [
        for (final key in changedKeys)
          if (newByKey[key] == null) oldByKey[key]!.merchantFingerprint,
      ],
    );
    if (batch.upserts.isEmpty && batch.removals.isEmpty) {
      return 'No baseline changes to save.';
    }
    await _financialBaselineStore.savePendingSync(batch);
    final queued = (await _financialBaselineStore.loadPendingSync())!;
    await _financialBaselineStore.saveMappings(mappings);
    if (mounted) setState(() => _baselineMappings = List.of(mappings));

    final spreadsheetId = _spreadsheetId;
    if (spreadsheetId == null || spreadsheetId.isEmpty) {
      return 'Saved locally, awaiting Google Sheets sync.';
    }
    try {
      var client = await _googleSignIn.authenticatedClient();
      if (client == null && await _waitForGoogleAccess()) {
        client = await _googleSignIn.authenticatedClient();
      }
      if (client == null) {
        return 'Saved locally, awaiting Google Sheets sync.';
      }
      await _baselineSheetsSyncService.syncChanges(
        sheetsApi: sheets.SheetsApi(client),
        spreadsheetId: spreadsheetId,
        mappings: queued.upserts,
        removedMerchants: queued.removals,
      );
      await _financialBaselineStore.clearPendingSync();
      return 'Changes saved and synced to the Expense Tracker DB.';
    } catch (error) {
      return 'Saved locally, awaiting sync. Sync failed: $error';
    }
  }

  Future<void> _syncSpendingTargets(sheets.SheetsApi api) async {
    final id = _spreadsheetId;
    if (id == null) return;
    await _spendingTargetStore.synchronize(
      (pending) => SpendingTargetSheetsSyncService().exchange(
        api: api,
        spreadsheetId: id,
        pending: pending,
      ),
    );
  }

  Future<String> _saveSpendingTargets() async {
    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null || _spreadsheetId == null) {
        return 'Targets saved on this device, awaiting sync.';
      }
      await _syncSpendingTargets(sheets.SheetsApi(client));
      return 'Spending targets saved and synced.';
    } catch (_) {
      return 'Targets saved on this device, awaiting sync.';
    }
  }

  Future<void> _openSpendingTargets() async {
    if (!mounted) return;
    unawaited(_saveSpendingTargets());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpendingTargetsScreen(
          store: _spendingTargetStore,
          transactions: List.of(_transactions),
          mappings: List.of(_baselineMappings),
          categories: List.of(_expenseCategories),
          currencySymbol: _currency,
          onSaved: _saveSpendingTargets,
          historyComplete: _targetHistoryComplete,
        ),
      ),
    );
  }

  bool _showRemainingClassification = false;
  bool _reviewUnknownOnly = false;
  int _classificationEntry = 0;
  void _reviewRemainingClassification() {
    final dashboard = ModalRoute.of(context);
    if (dashboard != null) {
      Navigator.of(context).popUntil((route) => route == dashboard);
    }
    setState(() {
      _selectedTab = 2;
      _showRemainingClassification = true;
      _reviewUnknownOnly = true;
      _classificationEntry++;
    });
  }

  Widget _merchantPanel() => MerchantBaselinePanel(
    key: ValueKey('merchant-panel-$_classificationEntry'),
    showRemainingInitially: _showRemainingClassification,
    reviewUnknownInitially: _reviewUnknownOnly,
    transactions: _transactions,
    categories: _activeExpenseCategories,
    legacyMappings: _baselineMappings,
    store: _merchantStore,
    currencySymbol: _currency,
    historyComplete: _targetHistoryComplete,
    onSaved: _saveMerchantClassifications,
  );

  Future<String> _saveMerchantClassifications(
    List<Map<String, dynamic>> changes,
  ) async {
    await _merchantStore.save(changes);
    final updated = _transactions
        .map(_merchantStore.index.apply)
        .toList(growable: false);
    await _localTransactionStore.saveCached(updated);
    if (mounted) setState(() => _transactions = updated);
    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null || _spreadsheetId == null)
        return 'Saved on this device. Google Sheets sync is pending.';
      final api = sheets.SheetsApi(client);
      final raw = await _readSheetTransactions(api);
      final status = await _merchantStore.synchronize(
        api,
        _spreadsheetId!,
        raw,
      );
      final effective = raw
          .map(_merchantStore.index.apply)
          .toList(growable: false);
      await _localTransactionStore.saveCached(effective);
      if (mounted)
        setState(() {
          _transactions = effective;
          _targetHistoryComplete = true;
        });
      return status;
    } catch (e) {
      return 'Saved on this device. Google Sheets sync will retry: $e';
    }
  }

  void _openInsight(String title, Widget child) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  Future<void> _openFinancialBaselineDetails() async {
    unawaited(_saveSpendingTargets());
    final draft = await _financialBaselineStore.loadDraft();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FinancialBaselineScreen(
          transactions: List.unmodifiable(_transactions),
          initialMappings: List.unmodifiable(_baselineMappings),
          categories: List.unmodifiable(_expenseCategories),
          currencySymbol: _currency,
          onMappingsSaved: _saveBaselineMappings,
          targetStore: _spendingTargetStore,
          onTargetsSaved: _saveSpendingTargets,
          historyComplete: _targetHistoryComplete,
          initialDraft: draft,
          insightsOnly: true,
          onDraftChanged: _financialBaselineStore.saveDraft,
          onDraftCleared: _financialBaselineStore.clearDraft,
        ),
      ),
    );
  }

  Future<void> _writeTransaction(
    sheets.SheetsApi sheetsApi,
    Transaction transaction,
  ) async {
    final row = transaction.sheetRow;
    if (row == null) {
      throw StateError('Cannot update an expense without a Google Sheet row.');
    }
    final taggedTransaction = tagInternalTransfer(transaction);
    await sheetsApi.spreadsheets.values.update(
      sheets.ValueRange(
        values: [
          [
            taggedTransaction.dateOnlyIsoString,
            taggedTransaction.amount.toString(),
            taggedTransaction.category,
            taggedTransaction.description,
            taggedTransaction.expenseTypeStorageValue,
            taggedTransaction.id ?? '',
            taggedTransaction.categoryId ??
                _categoryIdForName(taggedTransaction.category),
          ],
        ],
      ),
      _spreadsheetId!,
      'Sheet1!A$row:G$row',
      valueInputOption: 'USER_ENTERED',
    );
  }

  Future<void> _writeTransactions(
    sheets.SheetsApi sheetsApi,
    Iterable<Transaction> transactions,
  ) async {
    final values = transactions
        .map((source) {
          final transaction = tagInternalTransfer(source);
          return [
            transaction.dateOnlyIsoString,
            transaction.amount.toString(),
            transaction.category,
            transaction.description,
            transaction.expenseTypeStorageValue,
            transaction.id ?? '',
            transaction.categoryId ?? _categoryIdForName(transaction.category),
          ];
        })
        .toList(growable: false);
    await _googleSheetsService.appendRows(
      sheetsApi: sheetsApi,
      spreadsheetId: _spreadsheetId!,
      range: 'Sheet1!A1',
      rows: values,
      valueInputOption: 'USER_ENTERED',
    );
  }

  Transaction _classifyManual(Transaction t) {
    final effective = _merchantStore.index.apply(t);
    return _manualCategoryEdited
        ? effective.copyWith(category: t.category, categoryId: t.categoryId)
        : effective;
  }

  List<Widget> _manualTargetAwareness() {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || !amount.isFinite || amount <= 0) return [];
    final proposed = _classifyManual(
      Transaction(
        date: _selectedExpenseDate,
        amount: amount,
        category: _selectedCategory,
        categoryId:
            _selectedCategoryId ?? _categoryIdForName(_selectedCategory),
        description: _descController.text.trim(),
      ),
    );
    final awareness = SpendingTargetService().preview(
      proposed: proposed,
      targets: _spendingTargetStore.targets,
      transactions: _transactions,
      mappings: _baselineMappings,
      categories: _expenseCategories,
    );
    String money(double n) => formatFullCurrency(n, _currency);
    return [
      for (final a in awareness.where((a) => a.after.progress >= .8))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            a.crossed100
                ? (a.after.remaining < 0
                      ? 'This expense would bring your ${a.after.target.name} spending to ${money(a.after.actual)}, which is ${money(-a.after.remaining)} above your ${money(a.after.target.monthlyAmount)} monthly target.'
                      : 'This expense would reach your ${money(a.after.target.monthlyAmount)} monthly ${a.after.target.name} target.')
                : a.crossed80
                ? "You're approaching your monthly spending target. ${money(a.after.actual)} of your ${money(a.after.target.monthlyAmount)} ${a.after.target.name} target would be used after this expense."
                : '${a.after.target.name}: ${money(a.after.actual)} of ${money(a.after.target.monthlyAmount)} used after this expense.',
            style: a.prominent
                ? Theme.of(context).textTheme.bodyMedium
                : Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (awareness.isNotEmpty && !_targetHistoryComplete)
        const Text(
          'Based on locally available transactions; usage may be incomplete.',
        ),
    ];
  }

  Future<void> _showImportTargetSummary(List<TargetAwareness> changes) async {
    if (changes.isEmpty || !mounted) return;
    final count = changes.map((a) => a.after.target.scopeKey).toSet().length;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spending Targets Update'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your imported transactions affected $count spending target${count == 1 ? '' : 's'}.',
                ),
                for (final a in changes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${MaterialLocalizations.of(ctx).formatMonthYear(a.after.month)} · ${a.after.target.name} — ${a.after.label}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open Spending Targets'),
          ),
        ],
      ),
    );
    if (open == true && mounted) await _openSpendingTargets();
  }

  Future<void> _saveExpense() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      _showMessage('Enter an amount before saving.');
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || !amount.isFinite || amount <= 0) {
      _showMessage('Enter a valid amount greater than zero.');
      return;
    }

    setState(() => _isSaving = true);

    var isLocallyQueued = false;
    try {
      final description = _descController.text.trim().isEmpty
          ? 'General'
          : _descController.text.trim();
      final transaction = _classifyManual(
        Transaction(
          date: _selectedExpenseDate,
          amount: amount,
          category: _selectedCategory,
          description: description,
          expenseType: _selectedExpenseType,
          id: Transaction.createId(),
          categoryId:
              _selectedCategoryId ?? _categoryIdForName(_selectedCategory),
        ),
      );
      if (_manualCategoryEdited) {
        await _merchantStore.save([
          {
            'id': 't:${transaction.id}',
            'kind': 'transaction',
            'transactionId': transaction.id,
            'category': transaction.category,
            'categoryId': transaction.categoryId,
          },
        ]);
      }
      await _localTransactionStore.upsertPending(transaction);
      isLocallyQueued = true;
      final updatedTransactions = [..._transactions, transaction];
      if (mounted) setState(() => _transactions = updatedTransactions);
      await _localTransactionStore.saveCached(updatedTransactions);
      _manualCategoryEdited = false;
      _amountController.clear();
      _descController.clear();
      if (!mounted) return;
      setState(() {
        _selectedExpenseDate = DateUtils.dateOnly(DateTime.now());
      });
      if (_spreadsheetId != null &&
          await _drivePermissionService.ensureDriveWritePermission(context)) {
        await _fetchData();
      } else {
        _showMessage('Expense saved on this device. It will sync when online.');
      }
    } catch (e) {
      _showMessage(
        isLocallyQueued
            ? 'Expense is saved on this device and will sync later. Sync error: $e'
            : 'Could not save expense locally: $e',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selectExpenseDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final initialDate = _selectedExpenseDate.isAfter(today)
        ? today
        : _selectedExpenseDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (date != null && mounted) {
      setState(() => _selectedExpenseDate = DateUtils.dateOnly(date));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String> _getTargetSpreadsheetId() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) throw StateError('Pocket Ledger is no longer open.');
    final savedId =
        _workerSpreadsheetId ??
        preferences.getString(_workerSpreadsheetPreferenceKey);
    if (savedId != null && savedId.isNotEmpty) return savedId;

    if (_spreadsheetId == null || _spreadsheetId!.isEmpty) {
      await _initSpreadsheet();
    }
    final spreadsheetId = _spreadsheetId;
    if (spreadsheetId == null || spreadsheetId.isEmpty) {
      throw StateError('Could not resolve the Expense Tracker DB spreadsheet.');
    }

    await preferences.setString(_workerSpreadsheetPreferenceKey, spreadsheetId);
    if (mounted) setState(() => _workerSpreadsheetId = spreadsheetId);
    return spreadsheetId;
  }

  Future<void> _rememberWorkerSpreadsheetId(String spreadsheetId) async {
    if (spreadsheetId.isEmpty) {
      throw StateError('Cloudflare did not return a valid spreadsheet ID.');
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_workerSpreadsheetPreferenceKey, spreadsheetId);
    if (mounted) setState(() => _workerSpreadsheetId = spreadsheetId);
  }

  Future<void> _classifyImportedMerchants(String spreadsheetId) async {
    if (spreadsheetId == _spreadsheetId) {
      setState(() {
        _selectedTab = 2;
        _showRemainingClassification = true;
        _reviewUnknownOnly = false;
        _classificationEntry++;
      });
      return;
    }
    try {
      final client = await _googleSignIn.authenticatedClient();
      if (client == null)
        throw StateError('Sign in again to classify this statement.');
      final api = sheets.SheetsApi(client);
      final raw = await _readSheetTransactions(
        api,
        spreadsheetId: spreadsheetId,
      );
      await _merchantStore.synchronize(api, spreadsheetId, raw);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Financial Baseline')),
            body: SingleChildScrollView(
              child: MerchantBaselinePanel(
                transactions: raw,
                categories: _activeExpenseCategories,
                legacyMappings: _baselineMappings,
                store: _merchantStore,
                currencySymbol: _currency,
                historyComplete: true,
                showRemainingInitially: true,
                onSaved: (changes) async {
                  await _merchantStore.save(changes);
                  final fresh = await _readSheetTransactions(
                    api,
                    spreadsheetId: spreadsheetId,
                  );
                  return _merchantStore.synchronize(api, spreadsheetId, fresh);
                },
              ),
            ),
          ),
        ),
      );
    } catch (error) {
      _showMessage(
        'Expenses are imported. Could not open classification: $error',
      );
    }
  }

  Future<PreparedStatement?> _pickStatementFile() async {
    late final String fileName;
    late final List<int> bytes;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      setState(() => _workerSyncStatus = 'Selecting and reading statement...');
      final document = await const StatementDocumentPicker().pick();
      if (!mounted || document == null) return null;
      fileName = document.name;
      bytes = document.bytes;
    } else {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose a statement file',
        // Cloud providers may expose spreadsheets using provider-specific
        // MIME types, so validate supported formats after selection instead.
        type: FileType.any,
        webOptions: statementFilePickerWebOptions(),
        onFileLoading: (status) {
          if (!mounted) return;
          setState(() {
            _workerSyncStatus = status == FilePickerStatus.picking
                ? 'Selecting statement file...'
                : 'Reading statement file...';
          });
        },
      );
      debugPrint('[import] picked: ${file?.name} ext=${file?.extension}');
      if (!mounted) return null;
      if (file == null) {
        return null;
      }

      setState(() => _workerSyncStatus = 'Reading ${file.name}...');
      fileName = file.name;
      try {
        bytes = await readPickedStatementFile(file);
      } catch (error) {
        if (mounted) {
          _showMessage(
            'Could not download "${file.name}" from the selected location. '
            'Try selecting it again or downloading it locally. $error',
          );
        }
        return null;
      }
    }
    if (!mounted) return null;
    debugPrint('[import] read ${bytes.length} bytes');
    setState(() => _workerSyncStatus = 'Preparing statement...');
    if (bytes.isEmpty) {
      _showMessage('Could not read the selected file. Please try again.');
      return null;
    }

    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'gsheet') {
      final id = spreadsheetIdFromShortcut(bytes);
      return _readGoogleSheetStatement(sourceId: id, sourceName: fileName);
    }
    var csv = '';
    String? worksheetNote;
    if (extension == 'csv') {
      csv = utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', '');
      if (csv.trim().isEmpty) {
        _showMessage('The selected CSV file contains no readable data.');
        return null;
      }
    } else if (extension == 'xlsx' || extension == 'xls') {
      final workbook = Excel.decodeBytes(bytes);
      final sheetNames = workbook.tables.keys.toList();
      if (sheetNames.isEmpty) {
        _showMessage('This Excel file has no readable worksheets.');
        return null;
      }
      final primarySheetName = sheetNames.first;
      final primarySheet = workbook.tables[primarySheetName];
      if (primarySheet == null) {
        _showMessage('Could not read the first worksheet in this Excel file.');
        return null;
      }

      final rows = primarySheet.rows
          .map((row) => row.map((cell) => cell?.displayText ?? '').toList())
          .where((row) => row.any((value) => value.trim().isNotEmpty))
          .map((row) {
            while (row.isNotEmpty && row.last.trim().isEmpty) {
              row.removeLast();
            }
            return row;
          })
          .toList();
      if (rows.isEmpty) {
        _showMessage(
          'The first worksheet in this Excel file has no readable data.',
        );
        return null;
      }
      if (rows.length < 2) {
        _showMessage(
          'The first worksheet contains headers but no transaction rows.',
        );
        return null;
      }
      csv = buildCsvFromRows(rows);
      if (sheetNames.length > 1) {
        worksheetNote =
            ' Used the first worksheet, "$primarySheetName"; '
            '${sheetNames.length} worksheets were found.';
      }
    } else {
      _showMessage(
        'Choose a CSV, XLSX, XLS, or Google Sheets (.gsheet) statement.',
      );
      return null;
    }

    return PreparedStatement(
      name: fileName,
      csv: csv,
      worksheetNote: worksheetNote,
    );
  }

  Future<PreparedStatement?> _readGoogleSheetStatement({
    required String sourceId,
    required String sourceName,
  }) async {
    final client = await _googleSignIn.authenticatedClient();
    if (!mounted) {
      client?.close();
      return null;
    }
    if (client == null) {
      _showMessage('Reconnect your Google account, then try again.');
      return null;
    }
    try {
      final service = GoogleSheetStatementService(sheets.SheetsApi(client));
      return await showDialog<PreparedStatement>(
        context: context,
        barrierDismissible: false,
        builder: (_) => GoogleSheetImportDialog(
          initialSource: sourceId,
          sourceName: sourceName,
          loadWorkbook: service.loadWorkbook,
          readWorksheet: service.readWorksheet,
        ),
      );
    } finally {
      client.close();
    }
  }

  Future<void> _uploadStatementToWorker() async {
    if (_isWorkerSyncing) return;

    setState(() {
      _isWorkerSyncing = true;
      _workerSyncStatus = 'Selecting statement...';
    });
    try {
      final statement = await _pickStatementFile();
      if (!mounted || statement == null) return;
      final csv = statement.csv;
      final worksheetNote = statement.worksheetNote;

      setState(() => _workerSyncStatus = 'Checking Google Drive access...');
      final hasPermission = await _drivePermissionService
          .ensureDriveWritePermission(context);
      if (!hasPermission) {
        _showMessage(
          'Google Drive access was not granted. The statement was not imported; try again after connecting Drive.',
        );
        return;
      }

      setState(() => _workerSyncStatus = 'Looking up your spreadsheet...');
      final spreadsheetId = await _getTargetSpreadsheetId();
      if (!mounted) return;
      debugPrint(
        '[import] target spreadsheet: $spreadsheetId '
        '(main sheet: $_spreadsheetId, saved worker sheet: $_workerSpreadsheetId)',
      );

      final authentication = await widget.account.authentication;
      final accessToken = authentication.accessToken;
      if (accessToken == null || accessToken.trim().isEmpty) {
        throw StateError(
          'Google did not provide an access token. Reconnect Google Drive '
          'and try again.',
        );
      }

      setState(() => _workerSyncStatus = 'Analyzing statement...');
      debugPrint('[import] calling worker previewCsv');
      final workerPreview = await _workerCsvSyncService.previewCsv(
        requireMerchantReview: true,
        accessToken: accessToken,
        spreadsheetId: spreadsheetId,
        csv: csv,
        categoryConfig: _categoryConfiguration,
      );
      if (!mounted) return;
      final preview = workerPreview;
      final targetSpreadsheetId = preview.spreadsheetId;
      final spreadsheetCreated = preview.spreadsheetCreated;
      await _rememberWorkerSpreadsheetId(targetSpreadsheetId);
      if (!mounted) return;
      if (preview.rows.isEmpty) {
        _showMessage(
          '${spreadsheetCreated ? 'A replacement spreadsheet was created. ' : ''}'
          'No expense transactions were found in ${statement.name}. Nothing was imported.',
        );
        return;
      }

      final reviewedRows = await showDialog<List<WorkerExpensePreview>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatementReviewDialog(
          fileName: statement.name,
          preview: preview,
          currencySymbol: _currency,
          categories: _activeExpenseCategories,
        ),
      );
      if (!mounted || reviewedRows == null || reviewedRows.isEmpty) return;

      final remembered = reviewedRows
          .where((row) => row.rememberMapping && row.categoryId != null)
          .map(
            (row) => ExpenseCategoryMapping(
              keyword: row.description,
              categoryId: row.categoryId!,
              matchType: 'exact',
            ),
          )
          .toList();
      if (remembered.isNotEmpty) {
        final combined = [..._categoryMappings];
        for (final mapping in remembered) {
          combined.removeWhere(
            (item) =>
                item.keyword.toLowerCase() == mapping.keyword.toLowerCase(),
          );
          combined.add(mapping);
        }
        await _saveExpenseMappings(combined);
      }

      // Snapshot the committed ledger, independently of a possibly stale cache.
      sheets.SheetsApi? targetApi;
      final monitorsLedger =
          targetSpreadsheetId == _spreadsheetId &&
          _spendingTargetStore.targets.isNotEmpty;
      List<Transaction>? beforeTargetImport;
      if (monitorsLedger) {
        try {
          final monitorClient = await _googleSignIn.authenticatedClient();
          if (monitorClient != null) {
            targetApi = sheets.SheetsApi(monitorClient);
            beforeTargetImport = (await _readSheetTransactions(targetApi))
                .map(_merchantStore.index.apply)
                .toList();
          }
        } catch (_) {
          /* Import remains available if monitoring cannot refresh. */
        }
      }
      final importResponse = await _workerCsvSyncService.syncCsv(
        accessToken: accessToken,
        spreadsheetId: targetSpreadsheetId,
        csv: buildReviewedExpenseCsv(reviewedRows),
        allowDuplicates: false,
        categoryConfig: _categoryConfiguration,
      );
      final result = jsonDecode(importResponse.body) as Map<String, dynamic>;
      final importCreatedSpreadsheet = result['spreadsheetCreated'] == true;
      await _rememberWorkerSpreadsheetId(
        result['spreadsheetId']?.toString() ?? targetSpreadsheetId,
      );
      final importedCount = result['appended'] as int? ?? reviewedRows.length;
      final skippedDuplicates = result['skipped'] as int? ?? 0;
      final duplicateNote = skippedDuplicates == 0
          ? ''
          : ' $skippedDuplicates duplicate(s) were skipped.';
      final updatedCount = result['updated'] as int? ?? 0;
      final outcome = [
        if (importedCount > 0)
          'Imported $importedCount transaction(s) from ${statement.name}.',
        if (updatedCount > 0)
          'Updated classifications on $updatedCount existing transaction(s).',
        if (importedCount == 0 && updatedCount == 0)
          'No new or changed transactions were imported from ${statement.name}.',
      ].join(' ');
      _showMessage(
        '$outcome'
        '$duplicateNote$worksheetNote'
        '${spreadsheetCreated || importCreatedSpreadsheet ? ' A replacement spreadsheet was created.' : ''}',
      );
      if (targetSpreadsheetId == _spreadsheetId) {
        List<TargetAwareness> changes = [];
        if (beforeTargetImport != null &&
            (importedCount > 0 || updatedCount > 0)) {
          try {
            final committed = (await _readSheetTransactions(targetApi!))
                .map(_merchantStore.index.apply)
                .toList();
            String key(DateTime date, double amount, String description) =>
                '${date.year}-${date.month}-${date.day}|${amount.toStringAsFixed(2)}|${description.trim().toLowerCase()}';
            final reviewedKeys = {
              for (final row in reviewedRows)
                key(DateTime.parse(row.date), row.amount, row.description),
            };
            // Ignore unrelated concurrent edits. Use committed, deduplicated rows,
            // never the preview amounts, to evaluate the reviewed import scopes.
            final afterForImport = [
              ...beforeTargetImport.where(
                (t) => !reviewedKeys.contains(
                  key(t.date, t.amount, t.description),
                ),
              ),
              ...committed.where(
                (t) =>
                    reviewedKeys.contains(key(t.date, t.amount, t.description)),
              ),
            ];
            changes = SpendingTargetService().importChanges(
              targets: _spendingTargetStore.targets,
              before: beforeTargetImport,
              after: afterForImport,
              mappings: _baselineMappings,
              categories: _expenseCategories,
              now: DateTime.now(),
            );
          } catch (_) {
            /* No claims about target usage when refresh fails. */
          }
        }
        await _fetchData();
        await _showImportTargetSummary(changes);
      }
      if (mounted && (importedCount > 0 || updatedCount > 0)) {
        final classify = await showDialog<bool>(
          context: context,
          builder: (_) =>
              StatementImportCompleteDialog(summary: '$outcome$duplicateNote'),
        );
        if (classify == true && mounted)
          await _classifyImportedMerchants(targetSpreadsheetId);
      }
    } catch (error, stackTrace) {
      debugPrint('[import] FAILED: $error\n$stackTrace');
      if (mounted) _showMessage('Could not upload statement: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isWorkerSyncing = false;
          _workerSyncStatus = null;
        });
      }
    }
  }

  Future<void> _toggleDarkMode(bool enabled) async {
    try {
      await widget.onDarkModeChanged(enabled);
    } catch (error) {
      _showMessage('Could not save theme preference: $error');
    }
  }

  Future<void> _showMonthlyTargetDialog() async {
    final suggestion = _suggestedBudgetService.suggest(
      transactions: _transactions,
    );
    final target = await showDialog<double>(
      context: context,
      builder: (_) => MonthlyBudgetTargetDialog(
        currencySymbol: _currency,
        initialTarget: _monthlyTarget,
        onReviewUnclassified: _reviewRemainingClassification,
        suggestion: suggestion,
        unknownCount: _transactions
            .where(
              (t) =>
                  t.expenseType == ExpenseType.unknown &&
                  !isTransferTransaction(t),
            )
            .length,
      ),
    );

    if (target == null || !mounted) return;
    await _saveMonthlyTarget(target);
  }

  Future<void> _showSuggestedBudget() async {
    final suggestion = _suggestedBudgetService.suggest(
      transactions: _transactions,
    );
    if (suggestion == null) return;
    final applied = await showSuggestedBudgetSheet(
      context: context,
      suggestion: suggestion,
      onReviewUnclassified: _reviewRemainingClassification,
      currencySymbol: _currency,
    );
    if (applied == null || !mounted) return;
    await _saveMonthlyTarget(applied);
  }

  Future<void> _saveMonthlyTarget(double target) async {
    try {
      await MonthlyBudgetSnapshotStore().saveCurrentMonthBudget(budget: target);
      if (mounted) setState(() => _monthlyTarget = target);
    } catch (error) {
      _showMessage('Could not save monthly target: $error');
    }
  }

  Future<void> _showDailyReminderSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => DailyReminderSettingsDialog(
        enabled: _dailyReminderEnabled,
        time: _dailyReminderTime,
        onEnabledChanged: _setDailyReminderEnabled,
        onTimeChanged: _setDailyReminderTime,
      ),
    );
  }

  Future<bool> _setDailyReminderEnabled(bool enabled) async {
    if (enabled && !await _dailyReminderService.requestPermission()) {
      return false;
    }

    final preferences = await SharedPreferences.getInstance();
    try {
      if (enabled) {
        await _dailyReminderService.scheduleDaily(_dailyReminderTime);
      } else {
        await _dailyReminderService.cancelDaily();
      }
      await preferences.setBool('daily_reminder_enabled', enabled);
    } catch (error) {
      if (enabled) {
        await _dailyReminderService.cancelDaily();
      } else if (_dailyReminderEnabled) {
        await _dailyReminderService.scheduleDaily(_dailyReminderTime);
      }
      rethrow;
    }

    if (mounted) setState(() => _dailyReminderEnabled = enabled);
    return true;
  }

  Future<void> _setDailyReminderTime(TimeOfDay time) async {
    final preferences = await SharedPreferences.getInstance();
    if (_dailyReminderEnabled) {
      await _dailyReminderService.scheduleDaily(time);
    }
    await preferences.setInt('daily_reminder_hour', time.hour);
    await preferences.setInt('daily_reminder_minute', time.minute);
    if (mounted) setState(() => _dailyReminderTime = time);
  }

  double _calculateTotal(
    String period, {
    ExpenseType? expenseType,
    DateTime? targetMonth,
  }) {
    final activeMonth = targetMonth ?? _heroMonth;
    final now = DateTime.now();
    double total = 0.0;

    if (_transactions.isEmpty) {
      return 0.0;
    }

    for (final transaction in _transactions) {
      if (isTransferTransaction(transaction)) continue;
      if (expenseType != null && transaction.expenseType != expenseType) {
        continue;
      }
      final date = transaction.date;
      if (period == 'today' &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        total += transaction.amount;
      } else if (period == 'month' &&
          date.year == activeMonth.year &&
          date.month == activeMonth.month) {
        total += transaction.amount;
      } else if (period == 'year' && date.year == activeMonth.year) {
        total += transaction.amount;
      }
    }
    return total;
  }

  int _calculateTodayExpenseCount({DateTime? now}) {
    return countTransactionsOnDate(_transactions, now ?? DateTime.now());
  }

  Future<void> _reviewMonthUnclassified() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) {
          final remaining =
              _transactions
                  .where(
                    (t) =>
                        t.date.year == _heroMonth.year &&
                        t.date.month == _heroMonth.month &&
                        !isTransferTransaction(t) &&
                        t.expenseType == ExpenseType.unknown,
                  )
                  .toList()
                ..sort((a, b) => b.amount.compareTo(a.amount));
          return AlertDialog(
            title: const Text('Review unclassified expenses'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: remaining.isEmpty
                  ? const Center(
                      child: Text('All expense types are classified.'),
                    )
                  : ListView.builder(
                      itemCount: remaining.length,
                      itemBuilder: (_, i) {
                        final t = remaining[i];
                        return ListTile(
                          title: Text(
                            t.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${_formatDate(t.date)} · ${formatFullCurrency(t.amount, _currency)}',
                          ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () async {
                            await _editTransaction(t);
                            if (dialogContext.mounted) refresh(() {});
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editTransaction(Transaction selected) async {
    final editedTransaction = await showDialog<Transaction>(
      context: context,
      builder: (context) => _ExpenseEditDialog(transaction: selected),
    );
    if (editedTransaction == null || !mounted) return;
    var edited = tagInternalTransfer(
      editedTransaction.copyWith(
        categoryId: _categoryIdForName(editedTransaction.category),
      ),
    );

    var isLocallyQueued = false;
    try {
      if (edited.id != null &&
          (edited.category != selected.category ||
              edited.categoryId != selected.categoryId ||
              edited.expenseType != selected.expenseType)) {
        final old = _merchantStore.records['t:${edited.id}'];
        await _merchantStore.save([
          {
            ...?(old?['deleted'] == true ? null : old),
            'id': 't:${edited.id}',
            'kind': 'transaction',
            'transactionId': edited.id,
            'expenseType': edited.expenseType.sheetValue,
            'category': edited.category,
            'categoryId': edited.categoryId,
            'deleted': false,
          },
        ]);
      }
      edited = _merchantStore.index.apply(edited);
      await _localTransactionStore.upsertPending(edited);
      isLocallyQueued = true;
      final updated = _transactions
          .map((transaction) {
            final matches = edited.id != null
                ? transaction.id == edited.id
                : transaction.sheetRow == edited.sheetRow;
            return matches ? edited : transaction;
          })
          .toList(growable: false);
      if (mounted) setState(() => _transactions = updated);
      await _localTransactionStore.saveCached(updated);
      if (!mounted) return;
      if (_spreadsheetId != null &&
          await _drivePermissionService.ensureDriveWritePermission(context)) {
        await _fetchData();
      } else {
        _showMessage('Changes saved on this device. They will sync later.');
      }
    } catch (error) {
      _showMessage(
        isLocallyQueued
            ? 'Changes are saved locally and will sync later: $error'
            : 'Could not save changes locally: $error',
      );
    }
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  double _calculateCategorySpend(
    String category,
    String period, {
    bool includeOccasional = false,
  }) {
    final now = DateTime.now();
    return _transactions
        .where((transaction) {
          final date = transaction.date;
          final isInPeriod = switch (period) {
            'today' =>
              date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day,
            'month' => date.year == now.year && date.month == now.month,
            'year' => date.year == now.year,
            _ => false,
          };
          return isInPeriod &&
              !isTransferTransaction(transaction) &&
              transaction.category == category &&
              (includeOccasional ||
                  transaction.expenseType == ExpenseType.regular);
        })
        .fold<double>(0, (total, transaction) => total + transaction.amount);
  }

  void _showCategoryBreakdown(
    String title,
    String period, {
    DateTime? targetMonth,
  }) {
    final activeMonth = targetMonth ?? _heroMonth;
    final now = DateTime.now();
    final sheetTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9DD7C2),
        primary: const Color(0xFF9DD7C2),
        surface: const Color(0xFF121715),
        brightness: Brightness.dark,
      ),
    );
    bool inPeriod(Transaction transaction) {
      final date = transaction.date;
      return switch (period) {
        'today' =>
          date.year == now.year &&
              date.month == now.month &&
              date.day == now.day,
        'month' =>
          date.year == activeMonth.year && date.month == activeMonth.month,
        'year' => date.year == activeMonth.year,
        _ => false,
      };
    }

    String parentLabel(Transaction transaction) {
      final category =
          _expenseCategories
              .where((item) => item.id == transaction.categoryId)
              .firstOrNull ??
          _expenseCategories
              .where(
                (item) =>
                    item.name.toLowerCase() ==
                    transaction.category.toLowerCase(),
              )
              .firstOrNull;
      if (category != null) return category.parentName;
      for (final entry in defaultExpenseParents.entries) {
        if (entry.value.toLowerCase() == transaction.category.toLowerCase())
          return entry.value;
      }
      return transaction.category;
    }

    Map<String, List<Transaction>> transactionsByParent(
      Iterable<Transaction> transactions,
    ) {
      final grouped = <String, List<Transaction>>{};
      for (final transaction in transactions) {
        grouped
            .putIfAbsent(parentLabel(transaction), () => [])
            .add(transaction);
      }
      return grouped;
    }

    Map<String, double> categoryTotals(Iterable<Transaction> transactions) {
      final grouped = transactionsByParent(transactions);
      return {
        for (final entry in grouped.entries)
          entry.key: entry.value.fold<double>(
            0,
            (sum, transaction) => sum + transaction.amount,
          ),
      };
    }

    final periodTransactions = _transactions
        .where(
          (transaction) =>
              inPeriod(transaction) && !isTransferTransaction(transaction),
        )
        .toList();
    final parentTransactionGroups = transactionsByParent(periodTransactions);
    final sortedEntries = categoryTotals(periodTransactions).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sortedEntries.isNotEmpty ? sortedEntries.first.value : 1.0;
    final regularTransactions = periodTransactions.where(
      (transaction) => transaction.expenseType == ExpenseType.regular,
    );
    final occasionalTransactions = periodTransactions.where(
      (transaction) =>
          transaction.expenseType == ExpenseType.plannedOccasional ||
          transaction.expenseType == ExpenseType.unexpectedOccasional,
    );
    final regularTotal = regularTransactions.fold<double>(
      0,
      (total, transaction) => total + transaction.amount,
    );
    final occasionalTotal = occasionalTransactions.fold<double>(
      0,
      (total, transaction) => total + transaction.amount,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: sheetTheme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Theme(
        data: sheetTheme,
        child: Builder(
          builder: (ctx) {
            final theme = Theme.of(ctx);
            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$title Spending Breakdown',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close breakdown',
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _BreakdownMetricChip(
                          label: 'Actual',
                          amount: _calculateTotal(
                            period,
                            targetMonth: activeMonth,
                          ),
                          currencySymbol: _currency,
                          onTap: () => _showFilteredCategoryBreakdown(
                            title,
                            'Actual',
                            periodTransactions,
                          ),
                        ),
                        _BreakdownMetricChip(
                          label: 'Regular',
                          amount: regularTotal,
                          currencySymbol: _currency,
                          onTap: () => _showFilteredCategoryBreakdown(
                            title,
                            'Regular',
                            regularTransactions.toList(),
                          ),
                        ),
                        if (periodTransactions.any(
                          (t) => t.expenseType == ExpenseType.unknown,
                        ))
                          _BreakdownMetricChip(
                            label: 'Unknown',
                            amount: periodTransactions
                                .where(
                                  (t) => t.expenseType == ExpenseType.unknown,
                                )
                                .fold<double>(0, (sum, t) => sum + t.amount),
                            currencySymbol: _currency,
                            onTap: () => _showFilteredCategoryBreakdown(
                              title,
                              'Unknown',
                              periodTransactions
                                  .where(
                                    (t) => t.expenseType == ExpenseType.unknown,
                                  )
                                  .toList(),
                            ),
                          ),
                        _BreakdownMetricChip(
                          label: 'Occasional',
                          amount: occasionalTotal,
                          currencySymbol: _currency,
                          onTap: () => _showFilteredCategoryBreakdown(
                            title,
                            'Occasional',
                            occasionalTransactions.toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (sortedEntries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('No expenses recorded for this period.'),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView(
                          shrinkWrap: true,
                          children: sortedEntries.map((entry) {
                            final percentage = maxVal > 0
                                ? entry.value / maxVal
                                : 0.0;
                            return _BreakdownCategoryRow(
                              category: entry.key,
                              amount: entry.value,
                              percentage: percentage,
                              currencySymbol: _currency,
                              onTap: () => _showTransactionBreakdown(
                                title,
                                'Actual',
                                entry.key,
                                parentTransactionGroups[entry.key] ??
                                    const <Transaction>[],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showFilteredCategoryBreakdown(
    String title,
    String filter,
    List<Transaction> transactions,
  ) {
    final categoryGroups = <String, List<Transaction>>{};
    for (final transaction in transactions) {
      categoryGroups
          .putIfAbsent(transaction.category, () => [])
          .add(transaction);
    }
    final totals = {
      for (final entry in categoryGroups.entries)
        entry.key: entry.value.fold<double>(
          0,
          (sum, transaction) => sum + transaction.amount,
        ),
    };
    final sortedEntries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sortedEntries.isEmpty ? 1.0 : sortedEntries.first.value;
    final sheetTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9DD7C2),
        primary: const Color(0xFF9DD7C2),
        surface: const Color(0xFF121715),
        brightness: Brightness.dark,
      ),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: sheetTheme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Theme(
        data: sheetTheme,
        child: SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$title · $filter Spending',
                        style: Theme.of(ctx).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close breakdown',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (sortedEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No expenses recorded for this period.'),
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      children: sortedEntries.map((entry) {
                        final percentage = maxVal > 0
                            ? entry.value / maxVal
                            : 0.0;
                        return _BreakdownCategoryRow(
                          category: entry.key,
                          amount: entry.value,
                          percentage: percentage,
                          currencySymbol: _currency,
                          onTap: () => _showTransactionBreakdown(
                            title,
                            filter,
                            entry.key,
                            categoryGroups[entry.key]!,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTransactionBreakdown(
    String title,
    String filter,
    String category,
    List<Transaction> transactions,
  ) {
    // Callers pass the exact bucket behind the selected bar. Parent buckets
    // can contain several subcategories, so filtering by the display label
    // here would discard their transactions.
    final categoryTransactions = transactions.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final sheetTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9DD7C2),
        primary: const Color(0xFF9DD7C2),
        surface: const Color(0xFF121715),
        brightness: Brightness.dark,
      ),
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: sheetTheme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Theme(
        data: sheetTheme,
        child: SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$category · $filter',
                        style: Theme.of(ctx).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close transactions',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '$title transactions',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: categoryTransactions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final transaction = categoryTransactions[index];
                      final note = transaction.description.trim();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    note.isEmpty ? 'No note' : note,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    MaterialLocalizations.of(context)
                                        .formatMediumDate(transaction.date),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              formatFullCurrency(transaction.amount, _currency),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthlyRolloverRecap = _selectedTab == 0
        ? MonthlyRolloverRecap.calculate(
            transactions: _transactions,
            monthlyBudget: _previousMonthBudget,
          )
        : null;
    final insightMessage = _selectedTab == 2
        ? _spendingInsightsService.getSpendingInsight(
            history: _transactions,
            category: _selectedCategory,
            currentSpend: _calculateCategorySpend(_selectedCategory, 'month'),
            currentActualSpend: _calculateCategorySpend(
              _selectedCategory,
              'month',
              includeOccasional: true,
            ),
            currentPlannedOccasionalSpend: _calculateCategoryTypeCategorySpend(
              _selectedCategory,
              'month',
              ExpenseType.plannedOccasional,
            ),
            currentUnexpectedOccasionalSpend:
                _calculateCategoryTypeCategorySpend(
                  _selectedCategory,
                  'month',
                  ExpenseType.unexpectedOccasional,
                ),
          )
        : null;
    final todayExpenseCount = _selectedTab == 0
        ? _calculateTodayExpenseCount()
        : 0;
    final monthSpending = BudgetSpending.fromTransactions(
      _transactions.where(
        (t) =>
            t.date.year == _heroMonth.year && t.date.month == _heroMonth.month,
      ),
    );
    final monthBudget = isSameMonth(_heroMonth, DateTime.now())
        ? _monthlyTarget
        : _heroMonthBudget;
    final monthOutcome = monthBudget == null
        ? null
        : monthSpending.outcome(monthBudget);
    final monthSubtitle = monthBudget == null
        ? 'Actual spending'
        : monthOutcome == BudgetOutcome.over
        ? 'Over budget'
        : monthOutcome == BudgetOutcome.exact
        ? 'Exactly on budget'
        : 'Within budget';

    // Responsive layout: one column on phones / narrow windows, two columns
    // (dashboard + trends | add-expense form) on wide web or desktop windows.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 960;
    final maxContentWidth = _selectedTab == 2 && isWide
        ? 1240.0
        : isWide
        ? 880.0
        : 640.0;

    final dashboardWidgets = _selectedTab != 0
        ? <Widget>[]
        : <Widget>[
            if (_needsDriveAccess)
              _DriveAccessBanner(onConnect: _connectGoogleDrive)
            else if (_isInitialSync && _transactions.isEmpty) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Container(
              key: const ValueKey('home-spending-summary'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: .3),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 116),
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        key: const ValueKey('home-month-summary'),
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatMonthHeading(
                                _heroMonth,
                                now: DateTime.now(),
                              ),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatWholeCurrency(
                                monthSpending.total,
                                _currency,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          monthSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        children: [
                          MonthlyBudgetCard(
                            spending: monthSpending,

                            onReviewUnclassified: _reviewMonthUnclassified,
                            currentSpent: _calculateTotal(
                              'month',
                              targetMonth: _heroMonth,
                            ),
                            regularSpent: _calculateTotal(
                              'month',
                              expenseType: ExpenseType.regular,
                              targetMonth: _heroMonth,
                            ),
                            plannedOccasionalSpent: _calculateTotal(
                              'month',
                              expenseType: ExpenseType.plannedOccasional,
                              targetMonth: _heroMonth,
                            ),
                            unexpectedOccasionalSpent: _calculateTotal(
                              'month',
                              expenseType: ExpenseType.unexpectedOccasional,
                              targetMonth: _heroMonth,
                            ),
                            currencySymbol: _currency,
                            monthlyTarget:
                                isSameMonth(_heroMonth, DateTime.now())
                                ? _monthlyTarget
                                : _heroMonthBudget,
                            rolloverRecap: monthlyRolloverRecap,
                            selectedMonth: _heroMonth,
                            availableMonths: availableLedgerMonths(
                              _transactions,
                            ),
                            onMonthSelected: _selectHeroMonth,
                            onCalendarPressed: () => _showCategoryBreakdown(
                              // Same call shape the card uses for its own heading.
                              formatMonthHeading(
                                _heroMonth,
                                now: DateTime.now(),
                              ),
                              'month',
                              targetMonth: _heroMonth,
                            ),
                            onSetTargetPressed: _showMonthlyTargetDialog,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: isWide ? 10 : 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showCategoryBreakdown('Today', 'today'),
                          child: SizedBox(
                            height: screenWidth < 360 ? 132 : 116,
                            child: _SummaryCard(
                              title: 'TODAY',
                              amount: formatWholeCurrency(
                                _calculateTotal('today'),
                                _currency,
                              ),
                              subtitle: formatExpenseCount(todayExpenseCount),
                              icon: Icons.calendar_today,
                              matchPanels: isWide,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isWide ? 16 : 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showCategoryBreakdown(
                            'This Year',
                            'year',
                            targetMonth: monthStart(DateTime.now()),
                          ),
                          child: SizedBox(
                            height: screenWidth < 360 ? 132 : 116,
                            child: _SummaryCard(
                              title: 'THIS YEAR',
                              amount: formatWholeCurrency(
                                _calculateTotal(
                                  'year',
                                  targetMonth: monthStart(DateTime.now()),
                                ),
                                _currency,
                              ),
                              subtitle: 'Total actual spending',
                              icon: Icons.show_chart,
                              matchPanels: isWide,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ];

    final entryWidgets = _selectedTab != 0
        ? <Widget>[]
        : <Widget>[
            const Text(
              'Add New Expense',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            const _BrandTagline(textAlign: TextAlign.start),
            const SizedBox(height: 18),
            ExpenseCategorySelector(
              selectedCategory: _selectedCategory,
              categories: _activeExpenseCategories,
              transactions: _transactions,
              onCategorySelected: (category) {
                final selected = _activeExpenseCategories
                    .where((item) => item.name == category)
                    .firstOrNull;
                setState(() {
                  _selectedCategory = category;
                  _selectedCategoryId = selected?.id;
                  _manualCategoryEdited = true;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ExpenseType>(
              isExpanded: true,
              initialValue: _selectedExpenseType,
              decoration: InputDecoration(
                labelText: 'Expense type',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: ExpenseType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.sheetValue),
                    ),
                  )
                  .toList(),
              onChanged: (type) {
                if (type != null) {
                  setState(() => _selectedExpenseType = type);
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                prefixText: '$_currency ',
                labelText: 'Amount',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              onChanged: (_) => setState(() {
                if (!_manualCategoryEdited) {
                  final rule = _merchantStore.index.merchantFor(
                    _descController.text,
                  );
                  if (rule?['category'] != null &&
                      _activeExpenseCategories.any(
                        (c) => c.id == rule?['categoryId'],
                      )) {
                    _selectedCategory = rule!['category'] as String;
                    _selectedCategoryId = rule['categoryId'] as String;
                  }
                }
              }),
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _selectExpenseDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  'Expense date · '
                  '${MaterialLocalizations.of(context).formatMediumDate(_selectedExpenseDate)}',
                ),
              ),
            ),
            ..._manualTargetAwareness(),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveExpense,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_isSaving ? 'Saving...' : 'Save Expense'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4D3E),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ];

    final sortedTransactions = _selectedTab < 2
        ? ([..._transactions]..sort((a, b) => b.date.compareTo(a.date)))
        : <Transaction>[];
    final recentTransactions = sortedTransactions.take(5);

    Widget scrollablePage(List<Widget> children) => RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    );

    final Widget selectedPage;
    switch (_selectedTab) {
      case 0:
        selectedPage = scrollablePage([
          ...dashboardWidgets,
          const SizedBox(height: 24),
          ...entryWidgets,
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Recent Expenses',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedTab = 1),
                child: const Text('View all'),
              ),
            ],
          ),
          if (recentTransactions.isEmpty)
            const Text('No expenses recorded yet.')
          else
            ...recentTransactions.map(
              (transaction) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(
                  transaction.description.isEmpty
                      ? transaction.category
                      : transaction.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(transaction.category),
                trailing: Text(
                  formatFullCurrency(transaction.amount, _currency),
                ),
                onTap: () => _editTransaction(transaction),
              ),
            ),
        ]);
        break;
      case 1:
        selectedPage = RefreshIndicator(
          onRefresh: _fetchData,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: sortedTransactions.isEmpty
                    ? 3
                    : 2 + sortedTransactions.length,
                itemBuilder: (context, index) {
                  switch (index) {
                    case 0:
                      return Container(
                        key: const ValueKey('expenses-import-panel'),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                              key: const ValueKey(
                                'import_reconcile_statements_button',
                              ),
                              onPressed: _isWorkerSyncing
                                  ? null
                                  : _uploadStatementToWorker,
                              icon: _isWorkerSyncing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.sync_alt),
                              label: Text(
                                _isWorkerSyncing
                                    ? _workerSyncStatus ??
                                          'Preparing statement...'
                                    : 'Import Statements',
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 52),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: const StadiumBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'CSV, Excel & Google Sheets · Duplicates checked\n'
                              'You can review/edit before import.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      );
                    case 1:
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${_transactions.length} ${_transactions.length == 1 ? 'transaction' : 'transactions'}',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      );
                    case 2 when sortedTransactions.isEmpty:
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('No expenses recorded yet.'),
                      );
                    default:
                      final transaction = sortedTransactions[index - 2];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(
                          transaction.description.isEmpty
                              ? transaction.category
                              : transaction.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${transaction.category} · ${_formatDate(transaction.date)}',
                        ),
                        trailing: Text(
                          formatFullCurrency(transaction.amount, _currency),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () => _editTransaction(transaction),
                      );
                  }
                },
              ),
            ),
          ),
        );
        break;
      case 2:
        final shortcuts = <({String label, IconData icon, VoidCallback onTap})>[
          (
            label: 'Spending trends',
            icon: Icons.trending_up,
            onTap: () => _openInsight(
              'Spending trends',
              Column(
                children: [
                  SpendingSummaryWidget(
                    transactions: _transactions,
                    currencySymbol: _currency,
                  ),
                  if (insightMessage != null)
                    _SpendingInsightCard(message: insightMessage),
                ],
              ),
            ),
          ),
          (
            label: 'Spending spots',
            icon: Icons.storefront_outlined,
            onTap: () => _openInsight(
              'Favourite spending spots',
              FavouriteSpendingSpotsWidget(
                transactions: _transactions,
                currencySymbol: _currency,
              ),
            ),
          ),
          (
            label: 'Savings insights',
            icon: Icons.insights_outlined,
            onTap: _openFinancialBaselineDetails,
          ),
          (
            label: 'Suggested budget',
            icon: Icons.calculate_outlined,
            onTap: _showSuggestedBudget,
          ),
          (
            label: 'Spending targets',
            icon: Icons.flag_outlined,
            onTap: _openSpendingTargets,
          ),
        ];
        selectedPage = scrollablePage([
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 650 ? 5 : 3;
              final itemWidth =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                key: const ValueKey('insight-shortcuts'),
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final shortcut in shortcuts)
                    SizedBox(
                      width: itemWidth,
                      child: OutlinedButton(
                        onPressed: shortcut.onTap,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(shortcut.icon, size: 26),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 34,
                              child: Center(
                                child: Text(
                                  shortcut.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          _merchantPanel(),
        ]);
        break;
      default:
        selectedPage = scrollablePage([
          const Text(
            'Settings',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Expense categories'),
                  subtitle: const Text('Customize subcategories and mappings'),
                  onTap: _openExpenseCategorySettings,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.attach_money),
                  title: const Text('Currency'),
                  subtitle: Text(_currency),
                  onTap: _showCurrencyPicker,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark mode'),
                  value: widget.isDarkMode,
                  onChanged: _toggleDarkMode,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & how it works'),
                  subtitle: const Text('Getting started, budgets and insights'),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const HelpScreen()),
                  ),
                ),
                if (!kIsWeb) ...[
                  const Divider(height: 1),
                  PocketLedgerWebSettingsTile(store: _merchantStore),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Daily reminder'),
                    subtitle: Text(_dailyReminderEnabled ? 'On' : 'Off'),
                    onTap: _showDailyReminderSettings,
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.feedback_outlined),
                  title: const Text('Submit feedback or request a feature'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => const FeedbackDialog(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: () => _googleSignIn.disconnect(),
                ),
              ],
            ),
          ),
        ]);
    }
    const tabTitles = ['Pocket Ledger', 'Expenses', 'Insights', 'Settings'];
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: _selectedTab == 2
                ? 'Insights help'
                : 'Help & how it works',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => HelpScreen(insightsOnly: _selectedTab == 2),
              ),
            ),
          ),
        ],
        title: _selectedTab == 0
            ? Row(
                children: [
                  Container(
                    key: const ValueKey('home-brand-logo'),
                    width: 36,
                    height: 36,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8E6),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Image.asset(
                      'assets/images/app_icon_foreground.png',
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'Pocket Ledger',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              )
            : Text(
                tabTitles[_selectedTab],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
      ),
      body: selectedPage,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() {
          _selectedTab = index;
          if (_showRemainingClassification) {
            _showRemainingClassification = false;
            _reviewUnknownOnly = false;
            _classificationEntry++;
          }
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _BreakdownMetricChip extends StatelessWidget {
  const _BreakdownMetricChip({
    required this.label,
    required this.amount,
    required this.currencySymbol,
    required this.onTap,
  });

  final String label;
  final double amount;
  final String currencySymbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ActionChip(
      onPressed: onTap,
      backgroundColor: colorScheme.surfaceContainerHighest,
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 136),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              formatFullCurrency(amount, currencySymbol),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCategoryRow extends StatelessWidget {
  const _BreakdownCategoryRow({
    required this.category,
    required this.amount,
    required this.percentage,
    required this.currencySymbol,
    required this.onTap,
  });

  final String category;
  final double amount;
  final double percentage;
  final String currencySymbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatFullCurrency(amount, currencySymbol),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: percentage,
                minHeight: 10,
                borderRadius: BorderRadius.circular(8),
                color: colorScheme.primary,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandTagline extends StatelessWidget {
  const _BrandTagline({required this.textAlign, this.fontSize = 12});

  final TextAlign textAlign;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Manual logging → Mindful spending',
      textAlign: textAlign,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: fontSize,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final IconData icon;

  /// When true (wide layouts) the tile uses the same card style as the
  /// neighbouring panels while keeping the summary content compact.
  final bool matchPanels;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.icon,
    this.matchPanels = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 18, color: colorScheme.primary),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );

    if (matchPanels) {
      return Card(
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerLow,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.all(12), child: content),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: content,
    );
  }
}

class _DriveAccessBanner extends StatelessWidget {
  const _DriveAccessBanner({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('drive-access-banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Connect Google Drive to load your expenses. '
              'Your numbers appear once it is connected.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: onConnect, child: const Text('Connect')),
        ],
      ),
    );
  }
}

class _SpendingInsightCard extends StatelessWidget {
  const _SpendingInsightCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.insights, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _ExpenseEditDialog extends StatefulWidget {
  const _ExpenseEditDialog({required this.transaction});

  final Transaction transaction;

  @override
  State<_ExpenseEditDialog> createState() => _ExpenseEditDialogState();
}

class _ExpenseEditDialogState extends State<_ExpenseEditDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late String _category;
  late ExpenseType _expenseType;
  bool _expenseTypeEdited = false;
  late DateTime _date;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.transaction.amount.toString(),
    );
    _descriptionController = TextEditingController(
      text: widget.transaction.description,
    );
    _category = widget.transaction.category;
    _expenseType = widget.transaction.expenseType;
    _date = widget.transaction.date;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  void _save() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || !amount.isFinite || amount <= 0) {
      setState(() => _validationError = 'Enter an amount greater than zero.');
      return;
    }
    Navigator.pop(
      context,
      widget.transaction.copyWith(
        amount: amount,
        category: _category,
        description: _descriptionController.text.trim(),
        expenseType: _expenseTypeEdited ? _expenseType : null,
        date: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit expense'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                errorText: _validationError,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                if (!expenseCategoryOptions.any(
                  (category) => category.name == _category,
                ))
                  DropdownMenuItem(value: _category, child: Text(_category)),
                ...expenseCategoryOptions.map(
                  (category) => DropdownMenuItem(
                    value: category.name,
                    child: Text(category.name),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ExpenseType>(
              isExpanded: true,
              initialValue: _expenseType,
              decoration: const InputDecoration(labelText: 'Expense type'),
              items: ExpenseType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.sheetValue),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null)
                  setState(() {
                    _expenseType = value;
                    _expenseTypeEdited = true;
                  });
              },
            ),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _selectDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  '${_date.year.toString().padLeft(4, '0')}-'
                  '${_date.month.toString().padLeft(2, '0')}-'
                  '${_date.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save changes')),
      ],
    );
  }
}
