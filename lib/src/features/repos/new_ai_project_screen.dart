import 'package:flutter/material.dart';

import '../../core/branding/app_branding.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_state.dart';

/// Creates a new remote repository and seeds it with AI-generated starter files.
class NewAiProjectScreen extends StatefulWidget {
  const NewAiProjectScreen({super.key, required this.controller});

  final ForgeWorkspaceController controller;

  @override
  State<NewAiProjectScreen> createState() => _NewAiProjectScreenState();
}

class _NewAiProjectScreenState extends State<NewAiProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repoController = TextEditingController();
  final _ideaController = TextEditingController();
  final _stackController = TextEditingController();
  final _namespaceController = TextEditingController();
  final _tokenController = TextEditingController();
  final _apiBaseController = TextEditingController();
  bool _private = true;
  bool _busy = false;

  @override
  void dispose() {
    _repoController.dispose();
    _ideaController.dispose();
    _stackController.dispose();
    _namespaceController.dispose();
    _tokenController.dispose();
    _apiBaseController.dispose();
    super.dispose();
  }

  String? _validateRepoSlug(String? value) {
    final t = (value ?? '').trim().toLowerCase();
    if (t.isEmpty) return 'Enter a repository name (slug).';
    if (t.startsWith('.') || t.startsWith('-')) {
      return 'Name cannot start with . or -';
    }
    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(t)) {
      return 'Use lowercase letters, numbers, dots, and hyphens only.';
    }
    return null;
  }

  Future<void> _submit(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final repoSlug = _repoController.text.trim().toLowerCase();
      final ideaText = _ideaController.text.trim();
      final fallbackIdea = _stackController.text.trim().isEmpty
          ? 'Generate a clean starter repository scaffold for "$repoSlug" with sensible defaults and docs.'
          : 'Generate a clean starter repository scaffold for "$repoSlug" using ${_stackController.text.trim()} and include sensible defaults and docs.';
      final result = await widget.controller.createProjectWithAi(
        provider: 'github',
        repoName: repoSlug,
        idea: ideaText.isEmpty ? fallbackIdea : ideaText,
        stackHint: _stackController.text.trim().isEmpty
            ? null
            : _stackController.text.trim(),
        isPrivate: _private,
        namespace: _namespaceController.text.trim().isEmpty
            ? null
            : _namespaceController.text.trim(),
        accessToken: _tokenController.text.trim().isEmpty
            ? null
            : _tokenController.text.trim(),
        apiBaseUrl: _apiBaseController.text.trim().isEmpty
            ? null
            : _apiBaseController.text.trim(),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created ${result.fullName} with ${result.fileCount} starter files.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(forgeUserFriendlyMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ForgeWorkspaceState>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        final combinedBusy = _busy || state.isConnectingRepository;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              children: [
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ForgeSectionHeader(
                        title: 'New project with AI',
                        subtitle:
                            '$kAppDisplayName creates a new GitHub repository and commits an AI-generated starter scaffold. Uses your token wallet like other AI actions.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ForgePanel(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Project',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _repoController,
                          decoration: const InputDecoration(
                            labelText: 'Repository name (slug)',
                            hintText: 'e.g. my-flutter-habit-app',
                          ),
                          validator: _validateRepoSlug,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _namespaceController,
                          decoration: const InputDecoration(
                            labelText: 'GitHub organization (optional)',
                            hintText: 'Leave empty for your personal account',
                          ),
                          autocorrect: false,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Private repository'),
                          value: _private,
                          onChanged: combinedBusy
                              ? null
                              : (v) => setState(() => _private = v),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ideaController,
                          decoration: const InputDecoration(
                            labelText: 'What are you building? (optional)',
                            hintText:
                                'e.g. A Flutter app that tracks daily habits with local storage',
                            alignLabelWithHint: true,
                          ),
                          maxLines: 5,
                          minLines: 3,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _stackController,
                          decoration: const InputDecoration(
                            labelText: 'Preferred stack (optional)',
                            hintText: 'e.g. Flutter, Node + TypeScript, Python CLI',
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Provider access',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'If you signed in with GitHub, access is usually automatic. Paste a token with repo scope if needed.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _tokenController,
                          decoration: const InputDecoration(
                            labelText: 'Access token (optional)',
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _apiBaseController,
                          decoration: const InputDecoration(
                            labelText: 'Custom API base URL',
                            hintText: 'Optional for GitHub Enterprise',
                          ),
                        ),
                        const SizedBox(height: 24),
                        ForgePrimaryButton(
                          label: combinedBusy
                              ? 'Creating repository…'
                              : 'Create repository & scaffold',
                          icon: Icons.auto_awesome_rounded,
                          onPressed: combinedBusy
                              ? null
                              : () => _submit(context),
                          expanded: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
