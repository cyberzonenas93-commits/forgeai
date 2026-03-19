import 'package:flutter/material.dart';

import '../data/onboarding_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/forge_palette.dart';
import 'onboarding_screen.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  Future<OnboardingStorage>? _storageFuture;
  OnboardingStorage? _storage;
  bool? _completed;

  @override
  void initState() {
    super.initState();
    _storageFuture = OnboardingStorage.create();
    _storageFuture!.then((storage) {
      if (!mounted) return;
      setState(() {
        _storage = storage;
        _completed = storage.hasCompletedOnboarding;
      });
    });
  }

  Future<void> _completeOnboarding() async {
    await _storage?.setOnboardingCompleted(true);
    if (!mounted) return;
    setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_completed == true) {
      return widget.child;
    }
    if (_completed == false && _storage != null) {
      return OnboardingScreen(onComplete: _completeOnboarding);
    }
    return _OnboardingLoading();
  }
}

class _OnboardingLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: ForgeAiTheme.backgroundGradient,
      ),
      child: const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ForgePalette.glowAccent,
            ),
          ),
        ),
      ),
    );
  }
}
