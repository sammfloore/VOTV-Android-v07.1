import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/platform_service.dart';
import 'state/app_state.dart';
import 'widgets/brand_logo.dart';

class AvoTvApp extends StatefulWidget {
  const AvoTvApp({super.key});

  @override
  State<AvoTvApp> createState() => _AvoTvAppState();
}

class _AvoTvAppState extends State<AvoTvApp> with WidgetsBindingObserver {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PlatformService.setPlaybackStateChangedHandler(
      _state.reloadPlaybackActivity,
    );
    _state.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _state.reloadPlaybackActivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PlatformService.setPlaybackStateChangedHandler(null);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AVO TV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          if (!_state.ready) return _StartupScreen(message: _state.bootMessage);
          if (!_state.signedIn) return LoginScreen(state: _state);
          return MainShell(state: _state);
        },
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AvoTvLogo(size: 112, showName: false),
              const SizedBox(height: 20),
              const Text(
                'AVO TV',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 22),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
