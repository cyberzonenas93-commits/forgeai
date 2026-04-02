import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/forge_models.dart';
import '../../services/ai_copilot_service.dart';

// VibeRadar palette
const _kInk = Color(0xFF080914);
const _kPanel = Color(0xFF111425);
const _kRaised = Color(0xFF171B31);
const _kEdge = Color(0xFF252B48);
const _kCyan = Color(0xFF3AD7FF);
const _kText = Color(0xFFF0F4FF);
const _kMuted = Color(0xFF5C6A8A);

/// AI Copilot chat screen.
///
/// Supports Anthropic (Claude) and OpenAI (GPT) providers. The active provider
/// and API keys are managed by [AiCopilotService] and persisted across restarts.
class AiCopilotScreen extends StatefulWidget {
  const AiCopilotScreen({super.key});

  @override
  State<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends State<AiCopilotScreen> {
  final _service = AiCopilotService.instance;
  final _promptController = TextEditingController();
  bool _initialising = true;
  bool _submitting = false;
  final List<_CopilotMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _service.init();
    if (mounted) setState(() => _initialising = false);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _changeProvider(AiProviderKind provider) async {
    await _service.updateSelectedProvider(provider);
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _submitting) return;

    setState(() {
      _messages.add(_CopilotMessage(role: _Role.user, text: prompt));
      _submitting = true;
    });
    _promptController.clear();

    try {
      final history = _messages
          .map((m) => {
                'role': m.role == _Role.user ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList();
      final reply = await _service.sendMessage(history);
      if (mounted) {
        setState(() {
          _messages.add(_CopilotMessage(role: _Role.assistant, text: reply));
          _submitting = false;
        });
      }
    } on AiCopilotException catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            _CopilotMessage(role: _Role.assistant, text: '⚠️ ${e.message}'),
          );
          _submitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add(const _CopilotMessage(
            role: _Role.assistant,
            text: '⚠️ An unexpected error occurred. Check your connection and try again.',
          ));
          _submitting = false;
        });
      }
    }
  }

  Future<void> _updateKey(String newKey) async {
    if (_service.selectedProvider == AiProviderKind.anthropic) {
      await _service.updateAnthropicApiKey(newKey);
    } else {
      await _service.updateOpenAiApiKey(newKey);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_initialising) {
      return const Scaffold(
        backgroundColor: _kInk,
        body: Center(
          child: CircularProgressIndicator(color: _kCyan, strokeWidth: 2),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kInk,
      appBar: AppBar(
        backgroundColor: _kPanel,
        elevation: 0,
        title: Text(
          'AI Copilot',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _kText,
          ),
        ),
        actions: [
          if (!_service.hasApiKey)
            TextButton.icon(
              onPressed: () => _showKeyDialog(context),
              icon: const Icon(Icons.key_rounded, color: _kCyan, size: 16),
              label: Text(
                'Add Key',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _kCyan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _ProviderSelector(
            selected: _service.selectedProvider,
            onChanged: _changeProvider,
          ),
          if (!_service.hasApiKey)
            _ApiKeyBanner(
              provider: _service.selectedProvider,
              onTap: () => _showKeyDialog(context),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(
                    provider: _service.selectedProvider,
                    onAddKey: _service.hasApiKey
                        ? null
                        : () => _showKeyDialog(context),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) =>
                        _MessageBubble(message: _messages[i]),
                  ),
          ),
          _PromptBar(
            controller: _promptController,
            submitting: _submitting,
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _showKeyDialog(BuildContext context) async {
    final isAnthropic = _service.selectedProvider == AiProviderKind.anthropic;
    final existing = isAnthropic
        ? (_service.anthropicApiKey ?? '')
        : (_service.openAiApiKey ?? '');
    final ctrl = TextEditingController(text: existing);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isAnthropic ? 'Anthropic API Key' : 'OpenAI API Key',
          style: GoogleFonts.spaceGrotesk(
            color: _kText,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          style: const TextStyle(
            color: _kText,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: isAnthropic ? 'sk-ant-...' : 'sk-...',
            hintStyle: const TextStyle(color: _kMuted, fontFamily: 'monospace'),
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
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: _kMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kCyan,
              foregroundColor: _kInk,
            ),
            onPressed: () {
              _updateKey(ctrl.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
}

// ── Provider selector ─────────────────────────────────────────────────────────

class _ProviderSelector extends StatelessWidget {
  const _ProviderSelector({required this.selected, required this.onChanged});

  final AiProviderKind selected;
  final ValueChanged<AiProviderKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: _kPanel,
        border: Border(bottom: BorderSide(color: _kEdge)),
      ),
      child: Row(
        children: [
          Text(
            'Model:',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: _kMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          _ProviderChip(
            label: 'Claude',
            subtitle: 'claude-sonnet-4-5',
            icon: Icons.auto_awesome_rounded,
            selected: selected == AiProviderKind.anthropic,
            onTap: () => onChanged(AiProviderKind.anthropic),
          ),
          const SizedBox(width: 8),
          _ProviderChip(
            label: 'GPT',
            subtitle: 'gpt-4o',
            icon: Icons.psychology_rounded,
            selected: selected == AiProviderKind.openai,
            onTap: () => onChanged(AiProviderKind.openai),
          ),
        ],
      ),
    );
  }
}

class _ProviderChip extends StatelessWidget {
  const _ProviderChip({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _kCyan.withValues(alpha: 0.12) : _kRaised,
          border: Border.all(
            color: selected ? _kCyan : _kEdge,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? _kCyan : _kMuted,
              size: 14,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: selected ? _kCyan : _kText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color:
                        selected ? _kCyan.withValues(alpha: 0.7) : _kMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

enum _Role { user, assistant }

class _CopilotMessage {
  const _CopilotMessage({required this.role, required this.text});
  final _Role role;
  final String text;
}

class _ApiKeyBanner extends StatelessWidget {
  const _ApiKeyBanner({required this.provider, required this.onTap});

  final AiProviderKind provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = switch (provider) {
      AiProviderKind.anthropic => 'Anthropic',
      AiProviderKind.openai => 'OpenAI',
      AiProviderKind.gemini => 'Gemini',
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF1A1030),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.warning_rounded,
              color: Color(0xFF8F6CFF),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No $name API key configured. Tap to add your key.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: _kText.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onAddKey, required this.provider});

  final VoidCallback? onAddKey;
  final AiProviderKind provider;

  @override
  Widget build(BuildContext context) {
    final name = switch (provider) {
      AiProviderKind.anthropic => 'Anthropic',
      AiProviderKind.openai => 'OpenAI',
      AiProviderKind.gemini => 'Gemini',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: _kCyan, size: 44),
          const SizedBox(height: 16),
          Text(
            'Ask AI Copilot anything',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _kText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Get insights on tracks, trends, and market data.',
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _kMuted),
          ),
          if (onAddKey != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _kCyan,
                side: const BorderSide(color: _kEdge),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onAddKey,
              icon: const Icon(Icons.key_rounded, size: 16),
              label: Text(
                'Add $name API Key',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _CopilotMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _Role.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? _kCyan.withValues(alpha: 0.15) : _kPanel,
          border: Border.all(
            color: isUser ? _kCyan.withValues(alpha: 0.3) : _kEdge,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: _kText,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _PromptBar extends StatelessWidget {
  const _PromptBar({
    required this.controller,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: _kPanel,
        border: Border(top: BorderSide(color: _kEdge)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, color: _kText),
              decoration: InputDecoration(
                hintText: 'Ask about a track, artist, or market…',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: _kMuted,
                ),
                filled: true,
                fillColor: _kRaised,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kEdge),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kEdge),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kCyan, width: 1.5),
                ),
              ),
              onSubmitted: (_) => onSubmit(),
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            height: 44,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _kCyan,
                foregroundColor: _kInk,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: submitting ? null : onSubmit,
              child: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kInk,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
