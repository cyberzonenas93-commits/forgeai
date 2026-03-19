import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/observability/forge_telemetry.dart';
import '../../../shared/forge_models.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../data/forge_workspace_repository.dart';
import '../domain/forge_workspace_entities.dart';
import '../domain/forge_workspace_state.dart';

class ForgeWorkspaceController extends ValueNotifier<ForgeWorkspaceState> {
  ForgeWorkspaceController({
    required ForgeWorkspaceRepository repository,
    required AuthController authController,
    ForgeTelemetry? telemetry,
  }) : _repository = repository,
       _authController = authController,
       _telemetry = telemetry ?? ForgeTelemetry.instance,
       super(ForgeWorkspaceState.empty) {
    _authController.addListener(_handleAuthChanged);
    _handleAuthChanged();
  }

  ForgeWorkspaceController.preview({required AuthController authController})
    : _repository = null,
      _authController = authController,
      _telemetry = ForgeTelemetry.instance,
      super(ForgeWorkspaceState.empty);

  final ForgeWorkspaceRepository? _repository;
  final AuthController _authController;
  final ForgeTelemetry _telemetry;

  StreamSubscription<List<ForgeRepository>>? _repositoriesSubscription;
  StreamSubscription<List<ForgeConnection>>? _connectionsSubscription;
  StreamSubscription<List<ForgeActivityEntry>>? _activitiesSubscription;
  StreamSubscription<List<ForgeCheckRun>>? _checksSubscription;
  StreamSubscription<ForgeNotificationPreferences>?
      _notificationPreferencesSubscription;
  StreamSubscription<ForgeTokenWallet>? _walletSubscription;
  StreamSubscription<List<ForgeTokenLog>>? _tokenLogsSubscription;
  StreamSubscription<List<ForgeFileNode>>? _filesSubscription;
  StreamSubscription<List<ForgePromptThread>>? _promptThreadsSubscription;
  Timer? _repositoryAutoSyncTimer;
  bool _isAutoSyncingRepositories = false;

  String? _boundOwnerId;
  bool _hasLoadedPromptThreads = false;
  int _promptRequestNonce = 0;
  int? _activePromptRequestId;
  final Set<int> _cancelledPromptRequestIds = <int>{};
  static const Duration _repositoryAutoSyncInterval = Duration(minutes: 1);


  String _newPromptId() => DateTime.now().microsecondsSinceEpoch.toString();

  ForgePromptThread? get currentPromptThread {
    final id = value.selectedPromptThreadId;
    if (id == null) return null;
    for (final t in value.promptThreads) {
      if (t.id == id) return t;
    }
    return null;
  }

  ForgeRepository? _findRepositoryById(String? repoId) {
    if (repoId == null) return null;
    for (final repo in value.repositories) {
      if (repo.id == repoId) return repo;
    }
    return null;
  }

  ForgePromptThread? _findPromptThreadById(String? threadId) {
    if (threadId == null) return null;
    for (final thread in value.promptThreads) {
      if (thread.id == threadId) return thread;
    }
    return null;
  }

  Future<void> _persistPromptThread(ForgePromptThread thread) async {
    final repository = _repository;
    final ownerId = _boundOwnerId;
    if (repository == null || ownerId == null) {
      return;
    }
    await repository.savePromptThread(ownerId: ownerId, thread: thread);
  }

  void _ensurePromptThread({String? preferredRepoId}) {
    if (value.promptThreads.isNotEmpty && value.selectedPromptThreadId != null) {
      return;
    }
    final thread = ForgePromptThread(
      id: _newPromptId(),
      title: 'Thread 1',
      repoId: preferredRepoId ?? value.selectedRepository?.id,
      messages: const <ForgePromptMessage>[],
      updatedAt: DateTime.now(),
    );
    value = value.copyWith(
      promptThreads: <ForgePromptThread>[thread],
      selectedPromptThreadId: thread.id,
    );
    unawaited(_persistPromptThread(thread));
  }

  Future<void> createPromptThread({String? title, String? repoId}) async {
    final nextIndex = value.promptThreads.length + 1;
    final thread = ForgePromptThread(
      id: _newPromptId(),
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'Thread $nextIndex',
      repoId: repoId ?? value.selectedRepository?.id,
      messages: const <ForgePromptMessage>[],
      updatedAt: DateTime.now(),
    );
    final next = <ForgePromptThread>[thread, ...value.promptThreads];
    value = value.copyWith(
      promptThreads: next,
      selectedPromptThreadId: thread.id,
    );
    await _persistPromptThread(thread);
    final selectedRepo = _findRepositoryById(thread.repoId);
    if (selectedRepo != null) {
      await selectRepository(selectedRepo);
    }
  }

  Future<void> selectPromptThread(String threadId) async {
    value = value.copyWith(selectedPromptThreadId: threadId);
    ForgePromptThread? thread;
    for (final t in value.promptThreads) {
      if (t.id == threadId) {
        thread = t;
        break;
      }
    }
    if (thread?.repoId == null) return;
    final repo = _findRepositoryById(thread!.repoId);
    if (repo != null && value.selectedRepository?.id != repo.id) {
      await selectRepository(repo);
    }
  }

  Future<void> renamePromptThread({
    required String threadId,
    required String title,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final next = value.promptThreads.map((t) {
      if (t.id != threadId) return t;
      return t.copyWith(
        title: trimmed,
        updatedAt: DateTime.now(),
      );
    }).toList();
    value = value.copyWith(promptThreads: next);
    final updated = _findPromptThreadById(threadId);
    if (updated != null) {
      await _persistPromptThread(updated);
    }
  }

  Future<void> setPromptThreadRepo(String threadId, String? repoId) async {
    final next = value.promptThreads
        .map((t) => t.id == threadId
            ? t.copyWith(repoId: repoId, clearRepoId: repoId == null, updatedAt: DateTime.now())
            : t)
        .toList();
    value = value.copyWith(promptThreads: next);
    final updated = _findPromptThreadById(threadId);
    if (updated != null) {
      await _persistPromptThread(updated);
    }
    if (repoId == null) return;
    final repo = _findRepositoryById(repoId);
    if (repo != null && value.selectedRepository?.id != repo.id) {
      await selectRepository(repo);
    }
  }


  void setPromptDangerMode(bool enabled) {
    value = value.copyWith(promptDangerMode: enabled);
  }

  void addPromptAssistantMessage(String text) {
    final thread = currentPromptThread;
    if (thread == null || text.trim().isEmpty) return;
    final msg = ForgePromptMessage(
      id: _newPromptId(),
      role: 'assistant',
      text: text.trim(),
      createdAt: DateTime.now(),
    );
    final next = value.promptThreads.map((t) {
      if (t.id != thread.id) return t;
      return t.copyWith(messages: [...t.messages, msg], updatedAt: DateTime.now());
    }).toList();
    value = value.copyWith(promptThreads: next);
    final updated = _findPromptThreadById(thread.id);
    if (updated != null) {
      unawaited(_persistPromptThread(updated));
    }
  }

  void _updatePromptProgress(
    String threadId,
    String status, {
    bool reset = false,
  }) {
    final previous = reset ? const <String>[] : value.promptStatusSteps;
    final nextSteps = previous.isNotEmpty && previous.last == status
        ? previous
        : <String>[...previous, status];
    value = value.copyWith(
      isPromptLoading: true,
      promptStatusThreadId: threadId,
      promptStatusText: status,
      promptStatusSteps: nextSteps,
    );
  }

  void cancelPromptRun() {
    final requestId = _activePromptRequestId;
    final thread = currentPromptThread;
    if (requestId == null || thread == null || !value.isPromptLoading) {
      return;
    }
    _cancelledPromptRequestIds.add(requestId);
    _activePromptRequestId = null;

    final stopMessage = ForgePromptMessage(
      id: _newPromptId(),
      role: 'assistant',
      text: 'Prompt stopped. Any late response from the previous run will be ignored.',
      createdAt: DateTime.now(),
    );
    final next = value.promptThreads.map((t) {
      if (t.id != thread.id) return t;
      return t.copyWith(
        messages: [...t.messages, stopMessage],
        updatedAt: DateTime.now(),
      );
    }).toList();

    value = value.copyWith(
      promptThreads: next,
      isPromptLoading: false,
      clearPromptStatus: true,
    );
    final updated = _findPromptThreadById(thread.id);
    if (updated != null) {
      unawaited(_persistPromptThread(updated));
    }
  }

  Future<String> sendPromptMessage(
    String prompt, {
    List<ForgePromptMediaAttachment> media = const <ForgePromptMediaAttachment>[],
  }) async {
    final repo = _repository;
    if (repo == null) return '';
    _ensurePromptThread(preferredRepoId: value.selectedRepository?.id);
    final thread = currentPromptThread;
    if (thread == null) return '';
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return '';
    final requestId = ++_promptRequestNonce;
    _activePromptRequestId = requestId;
    final history = thread.messages.length > 12
        ? thread.messages.sublist(thread.messages.length - 12)
        : List<ForgePromptMessage>.from(thread.messages);

    final userMsg = ForgePromptMessage(
      id: _newPromptId(),
      role: 'user',
      text: trimmed,
      createdAt: DateTime.now(),
    );

    value = value.copyWith(
      isPromptLoading: true,
      clearError: true,
      promptStatusThreadId: thread.id,
      promptStatusText: 'Preparing prompt',
      promptStatusSteps: const <String>[
        'Prompt received',
        'Preparing prompt',
      ],
      promptThreads: value.promptThreads.map((t) {
        if (t.id != thread.id) return t;
        final autoTitle = (t.title.startsWith('Thread ') && t.messages.isEmpty)
            ? (trimmed.length > 36 ? '${trimmed.substring(0, 36)}...' : trimmed)
            : t.title;
        return t.copyWith(
          title: autoTitle,
          messages: [...t.messages, userMsg],
          updatedAt: DateTime.now(),
        );
      }).toList(),
    );
    final updatedAfterUserMessage = _findPromptThreadById(thread.id);
    if (updatedAfterUserMessage != null) {
      unawaited(_persistPromptThread(updatedAfterUserMessage));
    }

    try {
      _updatePromptProgress(thread.id, 'Gathering repository context');
      _updatePromptProgress(thread.id, 'Sending request to OpenAI');
      final reply = await repo.askRepo(
        repoId: thread.repoId,
        prompt: trimmed,
        provider: 'openai',
        history: history,
        media: media,
        dangerMode: value.promptDangerMode,
      );
      if (_cancelledPromptRequestIds.remove(requestId)) {
        return '';
      }
      if (_activePromptRequestId != requestId) {
        return '';
      }
      _updatePromptProgress(thread.id, 'Finalizing response');
      final assistantMsg = ForgePromptMessage(
        id: _newPromptId(),
        role: 'assistant',
        text: reply.isEmpty ? 'No response.' : reply,
        createdAt: DateTime.now(),
      );
      value = value.copyWith(
        isPromptLoading: false,
        clearPromptStatus: true,
        promptThreads: value.promptThreads.map((t) {
          if (t.id != thread.id) return t;
          return t.copyWith(
            messages: [...t.messages, assistantMsg],
            updatedAt: DateTime.now(),
          );
        }).toList(),
      );
      final updatedAfterAssistantMessage = _findPromptThreadById(thread.id);
      if (updatedAfterAssistantMessage != null) {
        await _persistPromptThread(updatedAfterAssistantMessage);
      }
      _activePromptRequestId = null;
      return assistantMsg.text;
    } catch (error) {
      if (_cancelledPromptRequestIds.remove(requestId)) {
        return '';
      }
      _activePromptRequestId = null;
      value = value.copyWith(
        isPromptLoading: false,
        clearPromptStatus: true,
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }

  static const String _runAppWorkflowTemplate = r'''name: Run App + Capture Logs

on:
  workflow_dispatch:
    inputs:
      platform:
        description: "Target platform (android/ios/web)"
        required: false
        default: "android"

jobs:
  run-app:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Replace this with your stack setup (Flutter, Node, etc.)
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: |
          if [ -f package-lock.json ]; then npm ci; elif [ -f package.json ]; then npm install; fi

      # Replace this with your app run command.
      # Example: npm run test:e2e or flutter test integration_test
      - name: Run app / tests and capture logs
        run: |
          mkdir -p artifacts
          echo "Running app workflow on platform=${{ github.event.inputs.platform }}" | tee artifacts/run.log
          # Example command (replace): npm run test:e2e 2>&1 | tee -a artifacts/run.log
          echo "TODO: replace with actual run command" | tee -a artifacts/run.log

      # Save screenshots into artifacts/screenshots in your run command.
      - name: Upload logs and screenshots
        uses: actions/upload-artifact@v4
        with:
          name: app-run-artifacts-${{ github.run_number }}
          path: |
            artifacts/**
''';

  void _handleAuthChanged() {
    if (_repository == null) {
      return;
    }
    final authState = _authController.value;
    final ownerId = authState.account?.id;
    if (ownerId == _boundOwnerId) {
      return;
    }
    unawaited(_bindToAccount(authState));
  }

  Future<void> _bindToAccount(AuthState authState) async {
    await _cancelSubscriptions();
    _boundOwnerId = authState.account?.id;
    _hasLoadedPromptThreads = false;

    if (authState.account == null) {
      value = ForgeWorkspaceState.empty;
      return;
    }

    value = value.copyWith(isBootstrapping: true, clearError: true);
    try {
      final repository = _repository;
      if (repository == null) {
        value = value.copyWith(isBootstrapping: false);
        return;
      }
      await repository.ensureBootstrap(authState.account!);

      _promptThreadsSubscription = repository
          .watchPromptThreads(authState.account!.id)
          .listen((promptThreads) async {
            _hasLoadedPromptThreads = true;
            if (promptThreads.isEmpty) {
              _ensurePromptThread(preferredRepoId: value.selectedRepository?.id);
              return;
            }
            final selectedId = promptThreads.any(
                  (thread) => thread.id == value.selectedPromptThreadId,
                )
                ? value.selectedPromptThreadId
                : (promptThreads.isNotEmpty ? promptThreads.first.id : null);
            value = value.copyWith(
              promptThreads: promptThreads,
              selectedPromptThreadId: selectedId,
              clearSelectedPromptThread: promptThreads.isEmpty,
            );
            final selectedThread = _findPromptThreadById(selectedId);
            final selectedRepo = _findRepositoryById(selectedThread?.repoId);
            if (selectedRepo != null &&
                value.selectedRepository?.id != selectedRepo.id) {
              await selectRepository(selectedRepo);
            }
          });

      _connectionsSubscription = repository
          .watchConnections(authState.account!.id)
          .listen((connections) {
            value = value.copyWith(connections: connections);
          });

      _activitiesSubscription = repository
          .watchActivities(authState.account!.id)
          .listen((activities) {
            value = value.copyWith(activities: activities);
          });

      _checksSubscription = repository
          .watchChecks(authState.account!.id)
          .listen((checks) {
            value = value.copyWith(checks: checks);
          });

      _notificationPreferencesSubscription = repository
          .watchNotificationPreferences(authState.account!.id)
          .listen((notificationPreferences) {
            value = value.copyWith(
              notificationPreferences: notificationPreferences,
            );
          });

      _walletSubscription = repository
          .watchWallet(authState.account!.id)
          .listen((wallet) {
            value = value.copyWith(wallet: wallet);
          });

      _tokenLogsSubscription = repository
          .watchTokenLogs(authState.account!.id)
          .listen((tokenLogs) {
            value = value.copyWith(tokenLogs: tokenLogs);
          });

      _repositoriesSubscription = repository
          .watchRepositories(authState.account!.id)
          .listen((repositories) async {
            final nextSelected =
                _resolveSelectedRepository(repositories) ??
                (repositories.isNotEmpty ? repositories.first : null);
            value = value.copyWith(
              repositories: repositories,
              selectedRepository: nextSelected,
              selectedBranch: nextSelected?.defaultBranch,
              clearRepository: nextSelected == null,
              clearSelectedBranch: nextSelected == null,
              repoWorkflows: const [],
            );
            if (_hasLoadedPromptThreads) {
              _ensurePromptThread(preferredRepoId: nextSelected?.id);
            }
            _scheduleRepositoryAutoSync(repositories);
            await _bindFiles();
          });

      value = value.copyWith(isBootstrapping: false, clearError: true);
    } catch (error) {
      value = value.copyWith(
        isBootstrapping: false,
        errorMessage: error.toString(),
      );
    }
  }

  ForgeRepository? _resolveSelectedRepository(
    List<ForgeRepository> repositories,
  ) {
    final current = value.selectedRepository;
    if (current == null) {
      return null;
    }
    for (final repository in repositories) {
      if (repository.id == current.id) {
        return repository;
      }
    }
    return null;
  }

  Future<void> _bindFiles() async {
    await _filesSubscription?.cancel();
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      value = value.copyWith(
        files: const <ForgeFileNode>[],
        clearSelectedFile: true,
      );
      return;
    }

    final selectedPath = value.selectedFile?.path;
    _filesSubscription = _repository!
        .watchFiles(repoId: selectedRepository.id, selectedPath: selectedPath)
        .listen((files) {
          value = value.copyWith(files: files);
        });
  }

  void _scheduleRepositoryAutoSync(List<ForgeRepository> repositories) {
    if (repositories.isEmpty) {
      _repositoryAutoSyncTimer?.cancel();
      _repositoryAutoSyncTimer = null;
      return;
    }
    if (_repository == null || _boundOwnerId == null) {
      return;
    }
    if (_repositoryAutoSyncTimer != null) {
      return;
    }
    _repositoryAutoSyncTimer = Timer.periodic(
      _repositoryAutoSyncInterval,
      (_) => unawaited(_autoSyncRepositoryMetadata()),
    );
    unawaited(_autoSyncRepositoryMetadata());
  }

  Future<void> _autoSyncRepositoryMetadata() async {
    if (_repository == null || _boundOwnerId == null || _isAutoSyncingRepositories) {
      return;
    }
    final repositories = List<ForgeRepository>.from(value.repositories);
    if (repositories.isEmpty) {
      return;
    }
    _isAutoSyncingRepositories = true;
    try {
      for (final repository in repositories) {
        try {
          await _repository.syncRepository(repository.id);
        } catch (_) {
          // Keep background metadata refresh best-effort.
        }
      }
    } finally {
      _isAutoSyncingRepositories = false;
    }
  }

  Future<void> refreshSelectedRepository() async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      return;
    }
    value = value.copyWith(isSyncing: true, clearError: true);
    try {
      await _repository!.syncRepository(selectedRepository.id);
      value = value.copyWith(isSyncing: false);
      unawaited(
        _telemetry.logEvent(
          'forge_repo_sync',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(isSyncing: false, errorMessage: error.toString());
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_refresh_repository',
        ),
      );
      rethrow;
    }
  }

  Future<void> connectRepository(ForgeConnectRepositoryDraft draft) async {
    final ownerId = _requireOwnerId();
    value = value.copyWith(isConnectingRepository: true, clearError: true);
    try {
      await _repository!.connectRepository(ownerId: ownerId, draft: draft);
      value = value.copyWith(isConnectingRepository: false);
      unawaited(
        _telemetry.logEvent(
          'forge_connect_repository',
          parameters: <String, Object?>{
            'provider': draft.provider,
            'repository': draft.repository,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isConnectingRepository: false,
        errorMessage: error.toString(),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_connect_repository',
        ),
      );
      rethrow;
    }
  }

  Future<void> saveNotificationPreferences(
    ForgeNotificationPreferences preferences,
  ) async {
    final repository = _repository;
    final ownerId = _boundOwnerId;
    if (repository == null || ownerId == null) {
      return;
    }
    value = value.copyWith(notificationPreferences: preferences);
    await repository.saveNotificationPreferences(
      ownerId: ownerId,
      preferences: preferences,
    );
  }

  Future<void> setNotificationsEnabled(bool enabled) {
    return saveNotificationPreferences(
      value.notificationPreferences.copyWith(enabled: enabled),
    );
  }

  Future<void> setNotificationCategory({
    required String category,
    required bool enabled,
  }) {
    final current = value.notificationPreferences;
    final next = switch (category) {
      'checks' => current.copyWith(checks: enabled),
      'git' => current.copyWith(git: enabled),
      'repository' => current.copyWith(repository: enabled),
      'ai' => current.copyWith(ai: enabled),
      'provider' => current.copyWith(provider: enabled),
      'wallet' => current.copyWith(wallet: enabled),
      'security' => current.copyWith(security: enabled),
      'digest' => current.copyWith(digest: enabled),
      _ => current,
    };
    return saveNotificationPreferences(next);
  }

  Future<void> registerPushToken({
    required String token,
    required String platform,
    required ForgePushPermissionStatus permissionStatus,
  }) async {
    final repository = _repository;
    final ownerId = _boundOwnerId;
    if (repository == null || ownerId == null) {
      return;
    }
    await repository.upsertPushDevice(
      ownerId: ownerId,
      token: token,
      platform: platform,
      permissionStatus: permissionStatus,
    );
  }

  Future<void> unregisterPushToken(String token) async {
    final repository = _repository;
    final ownerId = _boundOwnerId;
    if (repository == null || ownerId == null) {
      return;
    }
    try {
      await repository.removePushDevice(ownerId: ownerId, token: token);
    } on Exception {
      // Token docs can already be gone after refresh or invalid-token cleanup.
    }
  }

  Future<List<ForgeAvailableRepository>> listProviderRepositories({
    required String provider,
    String? query,
    String? apiBaseUrl,
  }) async {
    final repository = _repository;
    if (repository == null) {
      return const <ForgeAvailableRepository>[];
    }
    return repository.listProviderRepositories(
      provider: provider,
      query: query,
      apiBaseUrl: apiBaseUrl,
    );
  }

  Future<void> selectRepository(ForgeRepository repository) async {
    final matchingThread = value.promptThreads.where((t) => t.repoId == repository.id).fold<ForgePromptThread?>(
      null,
      (latest, thread) => latest == null || thread.updatedAt.isAfter(latest.updatedAt)
          ? thread
          : latest,
    );
    value = value.copyWith(
      selectedRepository: repository,
      selectedBranch: repository.defaultBranch,
      selectedPromptThreadId:
          matchingThread?.id ?? value.selectedPromptThreadId,
      clearSelectedFile: true,
      clearCurrentDocument: true,
      clearCurrentChangeRequest: true,
    );
    await _bindFiles();
  }

  Future<void> selectBranch(String branch) async {
    value = value.copyWith(selectedBranch: branch);
  }

  Future<String> askRepo({
    required String prompt,
    ForgeAiProvider provider = ForgeAiProvider.openai,
  }) async {
    final repo = _repository;
    if (repo == null) return '';
    final repoId = value.selectedRepository?.id;
    // OpenAI-only build.
    return repo.askRepo(
      repoId: repoId,
      prompt: prompt,
      provider: 'openai',
      dangerMode: false,
    );
  }

  Future<void> openFile(ForgeFileNode file) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      return;
    }
    value = value.copyWith(
      selectedFile: file,
      clearCurrentChangeRequest: true,
      clearError: true,
    );
    await _bindFiles();
    try {
      final document = await _repository!.loadFile(
        repoId: selectedRepository.id,
        filePath: file.path,
      );
      if (document == null) {
        value = value.copyWith(
          errorMessage: 'Could not load file content. Sync the repo or check permissions.',
        );
        return;
      }
      value = value.copyWith(currentDocument: document, clearError: true);
      unawaited(
        _telemetry.logEvent(
          'forge_open_file',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
            'path': file.path,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(errorMessage: error.toString());
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_open_file',
        ),
      );
      rethrow;
    }
  }

  void updateDraft(String content) {
    final currentDocument = value.currentDocument;
    if (currentDocument == null) {
      return;
    }
    value = value.copyWith(
      currentDocument: currentDocument.copyWith(content: content),
    );
  }

  Future<void> saveCurrentFile() async {
    final document = value.currentDocument;
    if (document == null) {
      return;
    }
    value = value.copyWith(isSavingFile: true, clearError: true);
    try {
      await _repository!.saveFile(
        ownerId: _requireOwnerId(),
        document: document,
      );
      value = value.copyWith(
        isSavingFile: false,
        currentDocument: document.copyWith(updatedAt: DateTime.now()),
      );
      unawaited(
        _telemetry.logEvent(
          'forge_save_file',
          parameters: <String, Object?>{'path': document.path},
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isSavingFile: false,
        errorMessage: error.toString(),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_save_file',
        ),
      );
      rethrow;
    }
  }

  Future<void> runAiAction({
    required String prompt,
    required ForgeAiProvider provider,
  }) async {
    final selectedRepository = value.selectedRepository;
    final currentDocument = value.currentDocument;
    if (selectedRepository == null || currentDocument == null) {
      return;
    }
    value = value.copyWith(isRunningAi: true, clearError: true);
    try {
      final changeRequest = await _repository!.runAiAction(
        ownerId: _requireOwnerId(),
        repoId: selectedRepository.id,
        filePath: currentDocument.path,
        provider: provider,
        prompt: prompt,
      );
      value = value.copyWith(
        isRunningAi: false,
        currentChangeRequest: changeRequest,
      );
      unawaited(
        _telemetry.logEvent(
          'forge_ai_suggestion_created',
          parameters: <String, Object?>{
            'provider': provider.name,
            'estimated_tokens': changeRequest.estimatedTokens,
            'path': currentDocument.path,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isRunningAi: false,
        errorMessage: error.toString(),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_run_ai',
        ),
      );
      rethrow;
    }
  }

  Future<void> approveCurrentChange() async {
    final changeRequest = value.currentChangeRequest;
    final currentDocument = value.currentDocument;
    if (changeRequest == null || currentDocument == null) {
      return;
    }
    value = value.copyWith(isSavingFile: true, clearError: true);
    try {
      await _repository!.approveChangeRequest(
        ownerId: _requireOwnerId(),
        changeRequest: changeRequest,
        currentDocument: currentDocument,
      );
      value = value.copyWith(
        isSavingFile: false,
        currentDocument: currentDocument.copyWith(
          content: changeRequest.afterContent,
          updatedAt: DateTime.now(),
        ),
        clearCurrentChangeRequest: true,
      );
      unawaited(
        _telemetry.logEvent(
          'forge_ai_change_approved',
          parameters: <String, Object?>{
            'estimated_tokens': changeRequest.estimatedTokens,
            'path': changeRequest.filePath,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isSavingFile: false,
        errorMessage: error.toString(),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_approve_change',
        ),
      );
      rethrow;
    }
  }

  Future<void> rejectCurrentChange() async {
    final changeRequest = value.currentChangeRequest;
    if (changeRequest == null) {
      return;
    }
    value = value.copyWith(isSavingFile: true, clearError: true);
    try {
      await _repository!.rejectChangeRequest(
        ownerId: _requireOwnerId(),
        changeRequest: changeRequest,
      );
      value = value.copyWith(
        isSavingFile: false,
        clearCurrentChangeRequest: true,
      );
      unawaited(
        _telemetry.logEvent(
          'forge_ai_change_rejected',
          parameters: <String, Object?>{
            'estimated_tokens': changeRequest.estimatedTokens,
            'path': changeRequest.filePath,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isSavingFile: false,
        errorMessage: error.toString(),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_reject_change',
        ),
      );
      rethrow;
    }
  }

  Future<void> submitGitAction({
    required ForgeGitActionType actionType,
    required ForgeGitDraft draft,
  }) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      return;
    }
    value = value.copyWith(isSubmittingGitAction: true, clearError: true);
    try {
      if (value.currentDocument?.hasUnsavedChanges ?? false) {
        await saveCurrentFile();
      }
      await _repository!.submitGitAction(
        repoId: selectedRepository.id,
        provider: selectedRepository.providerLabel.toLowerCase(),
        actionType: actionType,
        fileChanges:
            actionType == ForgeGitActionType.commit &&
                value.currentDocument != null
            ? <Map<String, String?>>[
                {
                  'path': value.currentDocument!.path,
                  'content': value.currentDocument!.content,
                  if (value.currentDocument!.sha != null)
                    'sha': value.currentDocument!.sha,
                },
              ]
            : const <Map<String, String?>>[],
        branchName: draft.branchName,
        commitMessage: draft.commitMessage,
        pullRequestTitle: draft.pullRequestTitle,
        pullRequestDescription: draft.pullRequestDescription,
        mergeMethod: draft.mergeMethod,
      );
      value = value.copyWith(isSubmittingGitAction: false);
      unawaited(
        _telemetry.logEvent(
          'forge_git_action_submitted',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
            'action_type': actionType.name,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isSubmittingGitAction: false,
        errorMessage: error.toString(),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_submit_git_action',
        ),
      );
      rethrow;
    }
  }

  Future<void> loadRepoWorkflows() async {
    final repo = value.selectedRepository;
    if (repo == null || _repository == null) return;
    try {
      final workflows = await _repository.listRepoWorkflows(repo.id);
      value = value.copyWith(repoWorkflows: workflows);
    } catch (_) {
      value = value.copyWith(repoWorkflows: const []);
    }
  }

  static String _pickWorkflowPath(
    List<ForgeRepoWorkflow> workflows,
    ForgeCheckActionType actionType,
  ) {
    if (workflows.isEmpty) return 'ci.yml';
    int? matchIndex;
    for (var i = 0; i < workflows.length; i++) {
      final w = workflows[i];
      final name = w.name.toLowerCase();
      final path = w.path.toLowerCase();
      final ok = switch (actionType) {
        ForgeCheckActionType.runTests =>
            name.contains('test') || path.contains('test') || name.contains('ci') || path.contains('ci'),
        ForgeCheckActionType.runLint => name.contains('lint') || path.contains('lint'),
        ForgeCheckActionType.buildProject =>
            name.contains('build') || path.contains('build') || name.contains('ci') || path.contains('ci'),
      };
      if (ok) {
        matchIndex = i;
        break;
      }
    }
    return matchIndex != null ? workflows[matchIndex].path : workflows.first.path;
  }

  Future<void> runCheck(ForgeCheckActionType actionType) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      return;
    }
    value = value.copyWith(isRunningCheck: true, clearError: true);
    try {
      List<ForgeRepoWorkflow> workflows = value.repoWorkflows;
      if (selectedRepository.provider == ForgeProvider.github && workflows.isEmpty) {
        await loadRepoWorkflows();
        workflows = value.repoWorkflows;
      }
      final bool isGitHub = selectedRepository.provider == ForgeProvider.github;
      final String workflowName = isGitHub
          ? (workflows.isEmpty
              ? 'ci.yml'
              : _pickWorkflowPath(workflows, actionType))
          : 'pipeline';
      await _repository!.submitCheckAction(
        repoId: selectedRepository.id,
        provider: selectedRepository.providerLabel.toLowerCase(),
        actionType: actionType,
        workflowName: workflowName,
      );
      value = value.copyWith(isRunningCheck: false);
      unawaited(
        _telemetry.logEvent(
          'forge_check_submitted',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
            'action_type': actionType.name,
          },
        ),
      );
    } catch (error) {
      final String message = error.toString();
      final String friendly = message.contains('404') ||
              message.toLowerCase().contains('not found') ||
              message.contains('workflow')
          ? 'No workflow found in this repo. Add a file at .github/workflows/ci.yml with "on: workflow_dispatch:" to run checks from the app.'
          : message;
      value = value.copyWith(
        isRunningCheck: false,
        errorMessage: friendly,
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_run_check',
        ),
      );
      rethrow;
    }
  }


  Future<String?> runAppWorkflow({
    String workflowName = 'run-app.yml',
  }) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      return null;
    }
    value = value.copyWith(isRunningCheck: true, clearError: true);
    try {
      final result = await _repository!.submitCheckAction(
        repoId: selectedRepository.id,
        provider: selectedRepository.providerLabel.toLowerCase(),
        actionType: ForgeCheckActionType.buildProject,
        workflowName: workflowName,
      );
      value = value.copyWith(isRunningCheck: false);
      await loadRepoWorkflows();
      final logsUrl = result['logsUrl'] as String?;
      unawaited(
        _telemetry.logEvent(
          'forge_run_app_workflow_submitted',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
            'workflow': workflowName,
          },
        ),
      );
      return logsUrl;
    } catch (error) {
      final message = error.toString();
      final friendly = message.contains('404') ||
              message.toLowerCase().contains('not found') ||
              message.contains('workflow')
          ? 'No app-run workflow found. Add .github/workflows/run-app.yml with workflow_dispatch and screenshot/log artifact upload.'
          : message;
      value = value.copyWith(
        isRunningCheck: false,
        errorMessage: friendly,
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_run_app_workflow',
        ),
      );
      rethrow;
    }
  }


  Future<void> installRunAppWorkflowViaGit({
    required String branchName,
    String commitMessage = 'chore: add run-app workflow',
  }) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      return;
    }
    value = value.copyWith(isSubmittingGitAction: true, clearError: true);
    try {
      await _repository!.submitGitAction(
        repoId: selectedRepository.id,
        provider: selectedRepository.providerLabel.toLowerCase(),
        actionType: ForgeGitActionType.commit,
        fileChanges: <Map<String, String?>>[
          {
            'path': '.github/workflows/run-app.yml',
            'content': _runAppWorkflowTemplate,
          },
        ],
        branchName: branchName,
        commitMessage: commitMessage,
      );
      value = value.copyWith(isSubmittingGitAction: false);
      unawaited(
        _telemetry.logEvent(
          'forge_install_run_app_workflow',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
            'branch': branchName,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isSubmittingGitAction: false,
        errorMessage: error.toString(),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_install_run_app_workflow',
        ),
      );
      rethrow;
    }
  }

  String _requireOwnerId() {
    final ownerId = _boundOwnerId;
    if (ownerId == null) {
      throw StateError('A signed-in account is required.');
    }
    return ownerId;
  }

  Future<void> _cancelSubscriptions() async {
    _repositoryAutoSyncTimer?.cancel();
    _repositoryAutoSyncTimer = null;
    await _repositoriesSubscription?.cancel();
    await _connectionsSubscription?.cancel();
    await _activitiesSubscription?.cancel();
    await _checksSubscription?.cancel();
    await _notificationPreferencesSubscription?.cancel();
    await _walletSubscription?.cancel();
    await _tokenLogsSubscription?.cancel();
    await _filesSubscription?.cancel();
    await _promptThreadsSubscription?.cancel();
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChanged);
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}
