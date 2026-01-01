import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/product_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/picking_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'widgets/global_data_sync.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().init();
  WakelockPlus.enable(); // Global wakelock
  runApp(const InventorApp());
}

class InventorApp extends StatelessWidget {
  const InventorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<AuthProvider, ProductProvider>(
          create: (_) => ProductProvider(),
          update: (_, auth, prod) => prod!..updateAuth(auth),
        ),
        ChangeNotifierProxyProvider<AuthProvider, PickingProvider>(
          create: (_) => PickingProvider(),
          update: (_, auth, picking) => picking!..updateAuth(auth),
        ),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Smart Inventory',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('vi', 'VN'), Locale('en', 'US')],
            builder: (context, child) {
              WakelockPlus.enable(); // Re-enforce global wakelock to prevent sleep everywhere
              return GlobalDataSync(
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(settings.zoomLevel)),
                  child: child!,
                ),
              );
            },
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
