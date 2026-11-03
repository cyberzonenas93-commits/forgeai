import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/onboarding_storage.dart';

// ── VibeRadar palette ─────────────────────────────────────────────────────────
const _kInk = Color(0xFF080914);
const _kPanel = Color(0xFF111425);
const _kRaised = Color(0xFF171B31);
const _kEdge = Color(0xFF252B48);
const _kCyan = Color(0xFF3AD7FF);
const _kViolet = Color(0xFF8F6CFF);
const _kLime = Color(0xFF9AFFA1);
const _kText = Color(0xFFF0F4FF);
const _kMuted = Color(0xFF5C6A8A);

// ── Root widget ───────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.storage,
    required this.onComplete,
  });

  final OnboardingStorage storage;
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}
class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  // Step 1
  final _apiKeyController = TextEditingController();
  bool _obscureApiKey = true;

  // Step 2
  String? _musicFolderPath;
  bool _pickingFolder = false;

  // Step 3
  static const _kRegionOrder = ['US', 'GB', 'GH', 'NG', 'ZA', 'DE'];
  static const _kRegionFlags = {
    'US': '🇺🇸', 'GB': '🇬🇧', 'GH': '🇬🇭',
    'NG': '🇳🇬', 'ZA': '🇿🇦', 'DE': '🇩🇪',
  };
  static const _kRegionNames = {
    'US': 'United States', 'GB': 'United Kingdom', 'GH': 'Ghana',
    'NG': 'Nigeria',       'ZA': 'South Africa',   'DE': 'Germany',
  };
  final Map<String, bool> _regions = {
    for (final r in _kRegionOrder) r: true,
  };
  bool _saving = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    if (_pickingFolder) return;
    setState(() => _pickingFolder = true);
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select your music library folder',
        lockParentWindow: true,
      );
      if (mounted && path != null) setState(() => _musicFolderPath = path);
    } finally {
      if (mounted) setState(() => _pickingFolder = false);
    }
  }

  Future<void> _complete() async {
    if (_saving) return;
    setState(() => _saving = true);
    final selectedRegions =
        _kRegionOrder.where((r) => _regions[r] == true).join(',');
    await widget.storage.saveVibeRadarOnboarding(
      apiKey: _apiKeyController.text.trim(),
      libraryPath: _musicFolderPath,
      selectedRegions: selectedRegions,
    );
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kInk,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                const SizedBox(height: 40),
                const _VibeRadarWordmark(),
                const SizedBox(height: 28),
                _StepDots(current: _step),
                const SizedBox(height: 28),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 340),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.0, 0.04),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          )),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _buildStep(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _Step1(
          apiKeyController: _apiKeyController,
          obscureApiKey: _obscureApiKey,
          onToggleObscure: () =>
              setState(() => _obscureApiKey = !_obscureApiKey),
          onSkip: () => setState(() => _step = 1),
          onContinue: () => setState(() => _step = 1),
        );
      case 1:
        return _Step2(
          folderPath: _musicFolderPath,
          picking: _pickingFolder,
          onPickFolder: _pickFolder,
          onSkip: () => setState(() => _step = 2),
          onContinue: () => setState(() => _step = 2),
        );
      case 2:
        return _Step3(
          regions: _regions,
          regionOrder: _kRegionOrder,
          regionFlags: _kRegionFlags,
          regionNames: _kRegionNames,
          saving: _saving,
          onToggle: (code, val) => setState(() => _regions[code] = val),
          onGetStarted: _complete,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Shared components ─────────────────────────────────────────────────────────

class _VibeRadarWordmark extends StatelessWidget {
  const _VibeRadarWordmark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Vibe',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: _kText,
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: 'Radar',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: _kCyan,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: active ? _kCyan : _kEdge,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: _kCyan.withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: -2,
                    )
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kEdge),
      ),
      child: child,
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _kCyan,
          foregroundColor: _kInk,
          disabledBackgroundColor: _kEdge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kInk,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _kInk,
                ),
              ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kText,
          side: const BorderSide(color: _kEdge),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: _kText.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

// ── Step 1 — Welcome + OpenAI key ─────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  const _Step1({
    required this.apiKeyController,
    required this.obscureApiKey,
    required this.onToggleObscure,
    required this.onSkip,
    required this.onContinue,
  });

  final TextEditingController apiKeyController;
  final bool obscureApiKey;
  final VoidCallback onToggleObscure;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome to VibeRadar',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kText,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The global music intelligence platform',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: _kMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _kCyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.key_rounded,
                        color: _kCyan,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OpenAI API Key',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _kText,
                            ),
                          ),
                          Text(
                            'Optional — powers AI-driven insights',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: _kMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: apiKeyController,
                  obscureText: obscureApiKey,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kText,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'sk-...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: _kMuted,
                      fontFamily: 'monospace',
                    ),
                    filled: true,
                    fillColor: _kRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kEdge),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kEdge),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _kCyan, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureApiKey
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: _kMuted,
                        size: 18,
                      ),
                      onPressed: onToggleObscure,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: onSkip,
                  child: Text(
                    'Skip for now',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: _kCyan.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(label: 'Continue', onPressed: onContinue),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Step 2 — Music folder ─────────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  const _Step2({
    required this.folderPath,
    required this.picking,
    required this.onPickFolder,
    required this.onSkip,
    required this.onContinue,
  });

  final String? folderPath;
  final bool picking;
  final VoidCallback onPickFolder;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Where's your music?",
            style: GoogleFonts.spaceGrotesk(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kText,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Point VibeRadar at your local library to scan tracks and gather trends.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: _kMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kCyan,
                      side: const BorderSide(color: _kCyan, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: picking ? null : onPickFolder,
                    icon: picking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kCyan,
                            ),
                          )
                        : const Icon(Icons.folder_open_rounded, size: 18),
                    label: Text(
                      picking ? 'Choosing…' : 'Choose Folder',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      folderPath != null
                          ? Icons.check_circle_rounded
                          : Icons.folder_off_rounded,
                      size: 16,
                      color: folderPath != null ? _kLime : _kMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        folderPath ?? 'No folder selected yet',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: folderPath != null ? _kText : _kMuted,
                          fontWeight: folderPath != null
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _OutlineButton(label: 'Skip', onPressed: onSkip),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PrimaryButton(label: 'Continue', onPressed: onContinue),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Step 3 — Regions ──────────────────────────────────────────────────────────

class _Step3 extends StatelessWidget {
  const _Step3({
    required this.regions,
    required this.regionOrder,
    required this.regionFlags,
    required this.regionNames,
    required this.saving,
    required this.onToggle,
    required this.onGetStarted,
  });

  final Map<String, bool> regions;
  final List<String> regionOrder;
  final Map<String, String> regionFlags;
  final Map<String, String> regionNames;
  final bool saving;
  final void Function(String code, bool val) onToggle;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Which markets do you care about?',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: _kText,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select the regions you want to track. You can adjust this later in Settings.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: _kMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _Card(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: regionOrder.map((code) {
                final selected = regions[code] ?? false;
                return InkWell(
                  onTap: () => onToggle(code, !selected),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Text(
                          regionFlags[code] ?? '',
                          style: const TextStyle(fontSize: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                regionNames[code] ?? code,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _kText,
                                ),
                              ),
                              Text(
                                code,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: _kMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Checkbox(
                          value: selected,
                          onChanged: (v) => onToggle(code, v ?? false),
                          activeColor: _kViolet,
                          checkColor: Colors.white,
                          side: const BorderSide(color: _kEdge, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          _PrimaryButton(
            label: 'Get Started',
            onPressed: saving ? null : onGetStarted,
            loading: saving,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
