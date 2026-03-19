import 'package:flutter/material.dart';

import '../../shared/widgets/forge_widgets.dart';
import '../workspace/application/forge_workspace_controller.dart';
import '../workspace/domain/forge_workspace_entities.dart';

class RepositoryConnectionScreen extends StatefulWidget {
  const RepositoryConnectionScreen({super.key, required this.controller});

  final ForgeWorkspaceController controller;

  @override
  State<RepositoryConnectionScreen> createState() =>
      _RepositoryConnectionScreenState();
}

class _RepositoryConnectionScreenState
    extends State<RepositoryConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _repositoryController = TextEditingController();
  final _branchController = TextEditingController(text: 'main');
  final _tokenController = TextEditingController();
  final _apiBaseController = TextEditingController();
  String _provider = 'github';
  bool _isLoadingRepositories = false;
  String? _repositoryLoadError;
  List<ForgeAvailableRepository> _availableRepositories =
      const <ForgeAvailableRepository>[];

  @override
  void initState() {
    super.initState();
    _loadAvailableRepositories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _repositoryController.dispose();
    _branchController.dispose();
    _tokenController.dispose();
    _apiBaseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.controller,
      builder: (context, state, _) {
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
                        title: 'Connect repository',
                        subtitle:
                            'Authorize GitHub or GitLab access for repository browsing, review-based commits, and CI actions.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ChoiceChip(
                            label: const Text('GitHub'),
                            selected: _provider == 'github',
                            onSelected: (_) => _setProvider('github'),
                          ),
                          ChoiceChip(
                            label: const Text('GitLab'),
                            selected: _provider == 'gitlab',
                            onSelected: (_) => _setProvider('gitlab'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _provider == 'github'
                            ? 'Use `owner/repository` for GitHub. If you signed in with GitHub, ForgeAI can reuse that OAuth access automatically. You can still paste a token to override it.'
                            : 'Use `group/project` for GitLab. An access token lets ForgeAI sync the real file tree and create Git actions through provider APIs.',
                        style: Theme.of(context).textTheme.bodySmall,
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
                          'Manual connect',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _repositoryController,
                          decoration: InputDecoration(
                            labelText: _provider == 'github'
                                ? 'owner/repository'
                                : 'group/project',
                          ),
                          validator: (value) {
                            final trimmed = (value ?? '').trim();
                            return trimmed.contains('/')
                                ? null
                                : 'Enter a repository slug like owner/repo.';
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _branchController,
                          decoration: const InputDecoration(
                            labelText: 'Default branch',
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Enter the default branch.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _tokenController,
                          decoration: InputDecoration(
                            labelText: 'Access token',
                            hintText: _provider == 'github'
                                ? 'Optional if you signed in with GitHub'
                                : 'Optional, but required for live sync',
                          ),
                          obscureText: true,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _apiBaseController,
                          decoration: const InputDecoration(
                            labelText: 'Custom API base URL',
                            hintText: 'Optional for self-hosted GitLab',
                          ),
                        ),
                        const SizedBox(height: 16),
                        ForgePrimaryButton(
                          label: state.isConnectingRepository
                              ? 'Connecting...'
                              : 'Connect repository',
                          icon: Icons.link_rounded,
                          onPressed: state.isConnectingRepository
                              ? null
                              : () => _submit(context),
                          expanded: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ForgePanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _provider == 'github'
                            ? 'Available GitHub repositories'
                            : 'Available GitLab repositories',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _provider == 'github'
                            ? 'Pick one to prefill the form or connect directly using your signed-in GitHub access.'
                            : 'If your GitLab token is available, you can pick a project here instead of typing it manually.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: 'Search repositories',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search_rounded),
                            onPressed: _isLoadingRepositories
                                ? null
                                : _loadAvailableRepositories,
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                        onFieldSubmitted: (_) => _loadAvailableRepositories(),
                      ),
                      const SizedBox(height: 12),
                      if (_isLoadingRepositories)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_repositoryLoadError != null)
                        Text(
                          _repositoryLoadError!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.redAccent),
                        )
                      else if (_availableRepositories.isEmpty)
                        Text(
                          _provider == 'github'
                              ? 'No repositories were returned yet. If you just signed in with GitHub, try refresh. You can still connect by typing `owner/repo` manually below.'
                              : 'No projects were returned yet. Refresh, or connect manually with `group/project`.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '${_availableRepositories.length} repositories • scroll to see all',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _availableRepositories.length,
                            itemBuilder: (context, index) {
                              final repository =
                                  _availableRepositories[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: ForgePanel(
                                  onTap: () =>
                                      _applyRepository(repository),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              repository.fullName,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ForgeSecondaryButton(
                                            label: 'Use',
                                            icon: Icons
                                                .arrow_downward_rounded,
                                            onPressed: () =>
                                                _applyRepository(
                                                    repository),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        repository.description
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true
                                            ? repository.description!
                                            : 'Default branch: ${repository.defaultBranch}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setProvider(String provider) async {
    if (_provider == provider) {
      return;
    }
    setState(() {
      _provider = provider;
      _availableRepositories = const <ForgeAvailableRepository>[];
      _repositoryLoadError = null;
    });
    await _loadAvailableRepositories();
  }

  Future<void> _loadAvailableRepositories() async {
    setState(() {
      _isLoadingRepositories = true;
      _repositoryLoadError = null;
    });
    try {
      final repositories = await widget.controller.listProviderRepositories(
        provider: _provider,
        query: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        apiBaseUrl: _apiBaseController.text.trim().isEmpty
            ? null
            : _apiBaseController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _availableRepositories = repositories;
        _isLoadingRepositories = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _repositoryLoadError = error.toString();
        _isLoadingRepositories = false;
      });
    }
  }

  void _applyRepository(ForgeAvailableRepository repository) {
    setState(() {
      _repositoryController.text = repository.fullName;
      _branchController.text = repository.defaultBranch;
    });
  }

  Future<void> _submit(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    try {
      await widget.controller.connectRepository(
        ForgeConnectRepositoryDraft(
          provider: _provider,
          repository: _repositoryController.text.trim(),
          defaultBranch: _branchController.text.trim(),
          accessToken: _tokenController.text.trim().isEmpty
              ? null
              : _tokenController.text.trim(),
          apiBaseUrl: _apiBaseController.text.trim().isEmpty
              ? null
              : _apiBaseController.text.trim(),
        ),
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Repository connected.')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}
