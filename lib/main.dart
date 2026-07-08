import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'screens/books_screen.dart';
import 'screens/prompts_screen.dart';
import 'screens/results_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..loadPrefs(),
      child: const BookDashboardApp(),
    ),
  );
}

class BookDashboardApp extends StatelessWidget {
  const BookDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Book Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5C6BC0),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _bootstrapped = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.loadedPrefs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // First run: no server configured yet → go straight to Settings.
    if (!state.api.configured) {
      return const SettingsScreen(firstRun: true);
    }

    if (!_bootstrapped) {
      _bootstrapped = true;
      // Fire-and-forget initial loads.
      Future.microtask(() {
        state.refreshBooks();
        state.refreshPrompts();
        state.refreshModels();
      });
    }

    final screens = const [
      BooksScreen(),
      PromptsScreen(),
      ResultsScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: screens[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Books'),
          NavigationDestination(icon: Icon(Icons.bolt_outlined), label: 'Prompts'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Results'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

/// Small helper used across screens.
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
