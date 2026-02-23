import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/cache/cache_manager.dart';
import 'core/constants/app_theme.dart';
import 'core/utils/i18n.dart';
import 'presentation/providers/locale_provider.dart';
import 'presentation/providers/server_provider.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/initialization_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize CacheManager
  final cacheManager = CacheManager();
  await cacheManager.init();

  runApp(RISEApp(cacheManager: cacheManager));
}

class RISEApp extends StatefulWidget {
  final CacheManager cacheManager;

  const RISEApp({super.key, required this.cacheManager});

  @override
  State<RISEApp> createState() => _RISEAppState();
}

class _RISEAppState extends State<RISEApp> {
  bool _isInitialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initializeCache();
  }

  Future<void> _initializeCache() async {
    try {
      // Initialize the cache - this will download files on first launch
      await widget.cacheManager.initialize().last;
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        // Start auto-update timer (every 6 hours)
        widget.cacheManager.startAutoUpdate();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    widget.cacheManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show initialization screen if not ready
    if (!_isInitialized) {
      if (_initError != null) {
        return MaterialApp(
          title: 'RISE Bare',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red[400],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to initialize',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _initError!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initError = null;
                          _isInitialized = false;
                        });
                        _initializeCache();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return MaterialApp(
        title: 'RISE Bare',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: InitializationScreen(
          progressStream: widget.cacheManager.initialize(),
          onComplete: () {
            setState(() {
              _isInitialized = true;
            });
            widget.cacheManager.startAutoUpdate();
          },
          onError: (error) {
            setState(() {
              _initError = error;
            });
          },
        ),
      );
    }

    // App is ready - show main content
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(
          create: (_) => ServerProvider()..init(),
        ),
        Provider<CacheManager>.value(value: widget.cacheManager),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, localeProvider, _) {
          return MaterialApp(
            title: 'RISE Bare',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.system,
            locale: localeProvider.locale,
            supportedLocales: AppLocales.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
