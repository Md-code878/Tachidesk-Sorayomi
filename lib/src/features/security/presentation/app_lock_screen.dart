import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../constants/db_keys.dart';
import '../../../utils/mixin/shared_preferences_client_mixin.dart';

part 'app_lock_screen.g.dart';

@riverpod
class AppLockToggle extends _$AppLockToggle
    with SharedPreferenceClientMixin<bool> {
  @override
  bool? build() => initialize(
        DBKeys.appLockToggle,
      );
}

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> with WidgetsBindingObserver {
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;
  final LocalAuthentication auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final isLocked = ref.read(appLockToggleProvider) ?? false;
      if (Platform.isAndroid && isLocked && !_isAuthenticated && !_isAuthenticating) {
        _checkAuth();
      }
    } else if (state == AppLifecycleState.paused) {
      final isLocked = ref.read(appLockToggleProvider) ?? false;
      if (Platform.isAndroid && isLocked) {
        setState(() {
          _isAuthenticated = false;
        });
      }
    }
  }

  Future<void> _checkAuth() async {
    if (_isAuthenticating) return;

    final isLocked = ref.read(appLockToggleProvider) ?? false;
    if (!Platform.isAndroid || !isLocked) {
      setState(() {
        _isAuthenticated = true;
      });
      return;
    }

    _isAuthenticating = true;
    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to show app',
        options: const AuthenticationOptions(useErrorDialogs: false),
      );
      setState(() {
        _isAuthenticated = didAuthenticate;
      });
    } catch (e) {
      setState(() {
        _isAuthenticated = false;
      });
    } finally {
      _isAuthenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isAuthenticated && Platform.isAndroid && (ref.watch(appLockToggleProvider) ?? false))
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_rounded, size: 100),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _checkAuth,
                      child: const Text('Unlock'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
