import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/observability/forge_telemetry.dart';
import '../../../shared/forge_models.dart';
import '../../../shared/forge_user_friendly_error.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../data/forge_workspace_repository.dart';
import '../domain/forge_agent_entities.dart';
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
  StreamSubscription<List<ForgeAgentTask>>? _agentTasksSubscription;
  StreamSubscription<List<ForgeAgentTaskEvent>>? _agentTaskEventsSubscription;
  Timer? _repositoryAutoSyncTimer;
  bool _isAutoSyncingRepositories = false;

  String? _boundOwnerId;

  /// The authenticated user's ID, or null if not signed in.
  String? get currentOwnerId => _boundOwnerId;

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

  ForgeAgentTask? _findAgentTaskById(String? taskId) {
    if (taskId == null) {
      return null;
    }
    for (final task in value.agentTasks) {
      if (task.id == taskId) {
        return task;
      }
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

  Future<void> _bindAgentTaskEvents() async {
    await _agentTaskEventsSubscription?.cancel();
    final repository = _repository;
    final ownerId = _boundOwnerId;
    final selectedTaskId = value.selectedAgentTaskId;
    if (repository == null || ownerId == null || selectedTaskId == null) {
      value = value.copyWith(agentTaskEvents: const <ForgeAgentTaskEvent>[]);
      return;
    }
    _agentTaskEventsSubscription = repository
        .watchAgentTaskEvents(ownerId: ownerId, taskId: selectedTaskId)
        .listen((events) {
          value = value.copyWith(agentTaskEvents: events);
        });
  }

  Future<void> _syncSelectedAgentTaskExecution() async {
    final repository = _repository;
    final selectedTask = value.selectedAgentTask;
    if (repository == null || selectedTask?.sessionId == null) {
      if (value.currentExecutionSession != null) {
        value = value.copyWith(clearCurrentExecutionSession: true);
      }
      return;
    }
    final task = selectedTask!;
    final current = value.currentExecutionSession;
    if (current != null && current.id == task.sessionId) {
      return;
    }
    try {
      final session = await repository.loadExecutionSession(
        repoId: task.repoId,
        sessionId: task.sessionId!,
      );
      if (session != null &&
          value.selectedAgentTaskId == task.id &&
          value.selectedAgentTask?.sessionId == task.sessionId) {
        value = value.copyWith(currentExecutionSession: session);
      }
    } catch (_) {
      // Keep task streaming resilient if the execution session loads late.
    }
  }

  /// Ensures there is a selected prompt thread (e.g. before quick Git commands).
  void ensurePromptThreadReady() {
    _ensurePromptThread(preferredRepoId: value.selectedRepository?.id);
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

  Future<void> clearPromptThreadMessages({String? threadId}) async {
    final targetId = threadId ?? value.selectedPromptThreadId;
    if (targetId == null) return;
    final now = DateTime.now();
    final next = value.promptThreads.map((t) {
      if (t.id != targetId) return t;
      if (t.messages.isEmpty) return t;
      return t.copyWith(
        messages: const <ForgePromptMessage>[],
        updatedAt: now,
      );
    }).toList();
    value = value.copyWith(
      promptThreads: next,
      isPromptLoading: false,
      clearPromptStatus: value.promptStatusThreadId == targetId,
    );
    final updated = _findPromptThreadById(targetId);
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

  void setRepoExecutionDeepMode(bool enabled) {
    value = value.copyWith(repoExecutionDeepMode: enabled);
  }

  void setAgentTrustLevel(AgentTrustLevel trustLevel) {
    value = value.copyWith(agentTrustLevel: trustLevel);
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

  /// Adds a user bubble (e.g. before running a quick Git / workflow command).
  void addPromptUserMessage(String text) {
    final thread = currentPromptThread;
    if (thread == null || text.trim().isEmpty) return;
    final msg = ForgePromptMessage(
      id: _newPromptId(),
      role: 'user',
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
      final repoId =
          thread.repoId ??
          value.selectedRepository?.id ??
          (value.repositories.length == 1 ? value.repositories.first.id : null);
      if (repoId == null) {
        throw StateError(
          'Select a repository before running repo-aware code execution.',
        );
      }
      _updatePromptProgress(thread.id, 'Queueing agent task');
      _updatePromptProgress(thread.id, 'Waiting for workspace lock');
      final taskId = await enqueueAgentTask(
        repoId: repoId,
        prompt: trimmed,
        currentFilePath: value.currentDocument?.path,
      );
      await _bindAgentTaskEvents();
      await _syncSelectedAgentTaskExecution();
      final reply =
          'Queued a live repo work item. The agent will map the repo, expand context, generate edits, validate, repair if needed, and then pause for your approval.';
      if (_cancelledPromptRequestIds.remove(requestId)) {
        return '';
      }
      if (_activePromptRequestId != requestId) {
        return '';
      }
      _updatePromptProgress(thread.id, 'Agent task running');
      final trace = ForgePromptAgentTrace(
        threadId: thread.id,
        recordedAt: DateTime.now(),
        steps: const <String>[
          'Prompt received',
          'Queued live agent work item',
          'Waiting for repo inspection, edit generation, validation, and approval',
        ],
        inspectedFiles: const <String>[],
        proposedEditFiles: const <String>[],
        plannedEdits: const <ForgePromptPlannedEdit>[],
        summary:
            'Prompt now hands off to the durable agent runtime instead of the old one-shot diff path.',
      );
      final assistantMsg = ForgePromptMessage(
        id: _newPromptId(),
        role: 'assistant',
        text: reply.isEmpty ? 'No response.' : reply,
        createdAt: DateTime.now(),
      );
      value = value.copyWith(
        isPromptLoading: false,
        clearPromptStatus: true,
        selectedAgentTaskId: taskId,
        promptLastAgentTrace: trace,
        clearCurrentExecutionSession: true,
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
        errorMessage: forgeUserFriendlyMessage(error),
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

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Setup Flutter
        if: ${{ hashFiles('pubspec.yaml') != '' }}
        uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install Node dependencies
        if: ${{ hashFiles('package.json') != '' }}
        run: |
          if [ -f package-lock.json ]; then npm ci; elif [ -f package.json ]; then npm install; fi

      - name: Run app / tests and capture logs
        shell: bash
        run: |
          set -eo pipefail
          mkdir -p artifacts
          mkdir -p artifacts/screenshots
          echo "Running app workflow on platform=${{ github.event.inputs.platform }}" | tee artifacts/run.log

          if [ -f pubspec.yaml ]; then
            flutter pub get 2>&1 | tee -a artifacts/run.log
            case "${{ github.event.inputs.platform }}" in
              web)
                flutter test 2>&1 | tee -a artifacts/run.log
                flutter build web 2>&1 | tee -a artifacts/run.log
                ;;
              android)
                flutter test 2>&1 | tee -a artifacts/run.log
                flutter build apk --debug 2>&1 | tee -a artifacts/run.log
                ;;
              ios)
                echo "iOS builds require a macOS runner; running Flutter tests on Ubuntu instead." | tee -a artifacts/run.log
                flutter test 2>&1 | tee -a artifacts/run.log
                ;;
              *)
                flutter test 2>&1 | tee -a artifacts/run.log
                ;;
            esac
            exit 0
          fi

          if [ -f package.json ]; then
            if npm run | grep -q " test"; then
              npm test 2>&1 | tee -a artifacts/run.log
            elif npm run | grep -q " build"; then
              npm run build 2>&1 | tee -a artifacts/run.log
            else
              echo "No supported npm script found. Add a test or build script for this workflow." | tee -a artifacts/run.log
              exit 1
            fi
            exit 0
          fi

          echo "No supported app stack detected. Commit a project-specific run command to .github/workflows/run-app.yml." | tee -a artifacts/run.log
          exit 1

      # Save screenshots into artifacts/screenshots in your run command.
      - name: Upload logs and screenshots
        uses: actions/upload-artifact@v4
        with:
          name: app-run-artifacts-${{ github.run_number }}
          path: |
            artifacts/**
''';

  static const String _deployFunctionsWorkflowTemplate = r'''name: Deploy Firebase Functions

on:
  workflow_dispatch:

jobs:
  deploy-functions:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        working-directory: functions
        run: |
          if [ -f package-lock.json ]; then npm ci; elif [ -f package.json ]; then npm install; fi

      - name: Install Firebase CLI
        run: npm install -g firebase-tools

      # Repo Settings → Secrets and variables → Actions:
      # - FIREBASE_TOKEN (easy): firebase login:ci
      # - FIREBASE_SERVICE_ACCOUNT (recommended): JSON for a deploy-capable service account
      # Optional: FIREBASE_PROJECT_ID (if omitted, Firebase CLI resolves from repo config)
      - name: Configure Firebase auth
        shell: bash
        run: |
          set -euo pipefail
          if [ -n "${FIREBASE_SERVICE_ACCOUNT:-}" ]; then
            SA_KEY_FILE="$RUNNER_TEMP/firebase-sa.json"
            printf '%s' "$FIREBASE_SERVICE_ACCOUNT" > "$SA_KEY_FILE"
            echo "GOOGLE_APPLICATION_CREDENTIALS=$SA_KEY_FILE" >> "$GITHUB_ENV"
            echo "FIREBASE_AUTH_MODE=service_account" >> "$GITHUB_ENV"
            exit 0
          fi
          if [ -n "${FIREBASE_TOKEN:-}" ]; then
            echo "FIREBASE_AUTH_MODE=token" >> "$GITHUB_ENV"
            exit 0
          fi
          echo "::error::Missing Firebase deploy auth. Add FIREBASE_TOKEN or FIREBASE_SERVICE_ACCOUNT in GitHub Actions secrets."
          exit 1

      - name: Deploy functions
        working-directory: .
        shell: bash
        run: |
          set -euo pipefail
          PROJECT_FLAG=""
          if [ -n "${FIREBASE_PROJECT_ID:-}" ]; then
            PROJECT_FLAG="--project $FIREBASE_PROJECT_ID"
          fi
          if [ "${FIREBASE_AUTH_MODE:-}" = "token" ]; then
            firebase deploy --only functions --non-interactive --token "$FIREBASE_TOKEN" $PROJECT_FLAG
          else
            firebase deploy --only functions --non-interactive $PROJECT_FLAG
          fi
        env:
          FIREBASE_TOKEN: ${{ secrets.FIREBASE_TOKEN }}
          FIREBASE_SERVICE_ACCOUNT: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          FIREBASE_PROJECT_ID: ${{ secrets.FIREBASE_PROJECT_ID }}
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

      _agentTasksSubscription = repository
          .watchAgentTasks(authState.account!.id)
          .listen((agentTasks) async {
            final preferredTaskId = agentTasks.any(
                  (task) => task.id == value.selectedAgentTaskId,
                )
                ? value.selectedAgentTaskId
                : (() {
                    for (final task in agentTasks) {
                      if (task.isActive) {
                        return task.id;
                      }
                    }
                    return agentTasks.isNotEmpty ? agentTasks.first.id : null;
                  }());
            value = value.copyWith(
              agentTasks: agentTasks,
              selectedAgentTaskId: preferredTaskId,
              clearSelectedAgentTask: agentTasks.isEmpty,
            );
            await _bindAgentTaskEvents();
            await _syncSelectedAgentTaskExecution();
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
        errorMessage: forgeUserFriendlyMessage(error),
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
      value = value.copyWith(
        isSyncing: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
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
        errorMessage: forgeUserFriendlyMessage(error),
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

  /// Selects a repository once it appears in the workspace stream (e.g. after create-on-remote).
  Future<void> selectRepositoryById(String repoId) async {
    if (repoId.isEmpty) return;
    for (var attempt = 0; attempt < 50; attempt++) {
      for (final r in value.repositories) {
        if (r.id == repoId) {
          await selectRepository(r);
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    throw StateError(
      'Repository $repoId did not appear in the workspace. Pull to refresh or open Repositories.',
    );
  }

  Future<ForgeCreateAiProjectResult> createProjectWithAi({
    required String provider,
    required String repoName,
    required String idea,
    String? stackHint,
    bool isPrivate = true,
    String? namespace,
    String? accessToken,
    String? apiBaseUrl,
  }) async {
    final ownerId = _requireOwnerId();
    value = value.copyWith(isConnectingRepository: true, clearError: true);
    try {
      final result = await _repository!.createProjectRepository(
        ownerId: ownerId,
        provider: provider,
        repoName: repoName,
        idea: idea,
        stackHint: stackHint,
        isPrivate: isPrivate,
        namespace: namespace,
        accessToken: accessToken,
        apiBaseUrl: apiBaseUrl,
      );
      value = value.copyWith(isConnectingRepository: false);
      await selectRepositoryById(result.repoId);
      unawaited(
        _telemetry.logEvent(
          'forge_create_ai_project',
          parameters: <String, Object?>{
            'provider': provider,
            'file_count': result.fileCount,
          },
        ),
      );
      return result;
    } catch (error) {
      value = value.copyWith(
        isConnectingRepository: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_create_ai_project',
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
    final matchingTask = value.agentTasks
        .where((task) => task.repoId == repository.id)
        .fold<ForgeAgentTask?>(
          null,
          (latest, task) {
            if (latest == null) {
              return task;
            }
            if (task.isActive && !latest.isActive) {
              return task;
            }
            if (task.createdAt.isAfter(latest.createdAt)) {
              return task;
            }
            return latest;
          },
        );
    value = value.copyWith(
      selectedRepository: repository,
      selectedBranch: repository.defaultBranch,
      selectedPromptThreadId:
          matchingThread?.id ?? value.selectedPromptThreadId,
      selectedAgentTaskId: matchingTask?.id ?? value.selectedAgentTaskId,
      clearSelectedFile: true,
      clearCurrentDocument: true,
      clearCurrentExecutionSession: true,
    );
    await _bindFiles();
    await _bindAgentTaskEvents();
    await _syncSelectedAgentTaskExecution();
  }

  Future<void> selectBranch(String branch) async {
    value = value.copyWith(selectedBranch: branch);
  }

  Future<void> selectAgentTask(String taskId) async {
    if (taskId == value.selectedAgentTaskId) {
      return;
    }
    final task = _findAgentTaskById(taskId);
    final repo = _findRepositoryById(task?.repoId);
    if (repo != null && value.selectedRepository?.id != repo.id) {
      value = value.copyWith(
        selectedRepository: repo,
        selectedBranch: repo.defaultBranch,
        clearSelectedFile: true,
        clearCurrentDocument: true,
        clearCurrentExecutionSession: true,
      );
      await _bindFiles();
    }
    value = value.copyWith(selectedAgentTaskId: taskId);
    await _bindAgentTaskEvents();
    await _syncSelectedAgentTaskExecution();
  }

  Future<String> enqueueAgentTask({
    required String prompt,
    String? repoId,
    String? currentFilePath,
    ForgeAiProvider? provider,
  }) async {
    final repository = _repository;
    final ownerId =
        _boundOwnerId ?? FirebaseAuth.instance.currentUser?.uid;
    if (repository == null || ownerId == null) {
      throw StateError('Agent mode is unavailable until the workspace is ready.');
    }
    final targetRepoId =
        repoId ??
        value.selectedRepository?.id ??
        (value.repositories.length == 1 ? value.repositories.first.id : null);
    if (targetRepoId == null) {
      throw StateError('Select a repository before starting an agent task.');
    }
    value = value.copyWith(isSubmittingAgentTask: true, clearError: true);
    try {
      // Force a fresh ID token before the callable to guard against stale tokens
      // on iOS where cloud_functions does not auto-refresh expired tokens.
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final taskId = await repository.enqueueAgentTask(
        repoId: targetRepoId,
        prompt: prompt.trim(),
        currentFilePath: currentFilePath ?? value.currentDocument?.path,
        deepMode: value.repoExecutionDeepMode,
        threadId: value.selectedPromptThreadId,
        provider: provider?.name,
        trustLevel: value.agentTrustLevel.backendValue,
      );
      value = value.copyWith(
        isSubmittingAgentTask: false,
        selectedAgentTaskId: taskId,
      );
      await _bindAgentTaskEvents();
      await _syncSelectedAgentTaskExecution();
      unawaited(
        _telemetry.logEvent(
          'forge_agent_task_enqueued',
          parameters: <String, Object?>{
            'repo_id': targetRepoId,
            'deep_mode': value.repoExecutionDeepMode,
          },
        ),
      );
      return taskId;
    } catch (error) {
      value = value.copyWith(
        isSubmittingAgentTask: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_enqueue_agent_task',
        ),
      );
      rethrow;
    }
  }

  Future<void> cancelAgentTask({String? taskId}) async {
    final repository = _repository;
    final targetTask =
        _findAgentTaskById(taskId ?? value.selectedAgentTaskId) ??
        value.selectedAgentTask;
    if (repository == null || targetTask == null) {
      return;
    }
    value = value.copyWith(isResolvingAgentTask: true, clearError: true);
    try {
      await repository.cancelAgentTask(targetTask.id);
      value = value.copyWith(
        isResolvingAgentTask: false,
        clearCurrentExecutionSession: targetTask.sessionId != null,
      );
    } catch (error) {
      value = value.copyWith(
        isResolvingAgentTask: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_cancel_agent_task',
        ),
      );
      rethrow;
    }
  }

  Future<void> pauseAgentTask({String? taskId}) async {
    final repository = _repository;
    final targetTask =
        _findAgentTaskById(taskId ?? value.selectedAgentTaskId) ??
        value.selectedAgentTask;
    if (repository == null || targetTask == null) {
      return;
    }
    value = value.copyWith(isResolvingAgentTask: true, clearError: true);
    try {
      await repository.pauseAgentTask(targetTask.id);
      value = value.copyWith(isResolvingAgentTask: false);
    } catch (error) {
      value = value.copyWith(
        isResolvingAgentTask: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_pause_agent_task',
        ),
      );
      rethrow;
    }
  }

  Future<void> resolveAgentTaskApproval({
    String? taskId,
    required bool approved,
  }) async {
    final repository = _repository;
    final targetTask =
        _findAgentTaskById(taskId ?? value.selectedAgentTaskId) ??
        value.selectedAgentTask;
    if (repository == null || targetTask == null) {
      return;
    }
    value = value.copyWith(isResolvingAgentTask: true, clearError: true);
    try {
      await repository.resolveAgentTaskApproval(
        taskId: targetTask.id,
        approved: approved,
      );
      value = value.copyWith(
        isResolvingAgentTask: false,
        clearCurrentExecutionSession: !approved &&
            targetTask.pendingApproval?.type ==
                ForgeAgentTaskApprovalType.applyChanges,
      );
      unawaited(
        _telemetry.logEvent(
          'forge_agent_task_approval_resolved',
          parameters: <String, Object?>{
            'approved': approved,
            'task_id': targetTask.id,
            'approval_type': targetTask.pendingApproval?.type.name,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isResolvingAgentTask: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_resolve_agent_task_approval',
        ),
      );
      rethrow;
    }
  }

  Future<void> openFile(ForgeFileNode file) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      return;
    }
    value = value.copyWith(
      selectedFile: file,
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
      value = value.copyWith(errorMessage: forgeUserFriendlyMessage(error));
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
        errorMessage: forgeUserFriendlyMessage(error),
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

  Future<void> createFile({required String path}) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null || _repository == null) {
      return;
    }
    final ownerId = _requireOwnerId();
    try {
      await _repository.createFileDraft(
        ownerId: ownerId,
        repoId: selectedRepository.id,
        filePath: path,
      );
      await openFile(
        ForgeFileNode(
          name: path.split('/').last,
          path: path,
          language: 'Text',
          sizeLabel: '0 chars',
          changeLabel: 'Saved',
        ),
      );
    } catch (error) {
      value = value.copyWith(errorMessage: forgeUserFriendlyMessage(error));
      rethrow;
    }
  }

  Future<void> createFolder({required String path}) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null || _repository == null) {
      return;
    }
    try {
      await _repository.createFolderDraft(
        ownerId: _requireOwnerId(),
        repoId: selectedRepository.id,
        folderPath: path,
      );
    } catch (error) {
      value = value.copyWith(errorMessage: forgeUserFriendlyMessage(error));
      rethrow;
    }
  }

  Future<void> renameNode({
    required ForgeFileNode node,
    required String newNameOrPath,
  }) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null || _repository == null) {
      return;
    }
    final oldPath = node.path;
    final newPath = _buildRenamedPath(oldPath, newNameOrPath, node.isFolder);
    if (oldPath == newPath) {
      return;
    }
    await _repository.renamePath(
      ownerId: _requireOwnerId(),
      repoId: selectedRepository.id,
      oldPath: oldPath,
      newPath: newPath,
      isFolder: node.isFolder,
    );
    final current = value.currentDocument;
    if (current == null) {
      return;
    }
    if (!node.isFolder && current.path == oldPath) {
      value = value.copyWith(
        currentDocument: current.copyWith(path: newPath),
      );
      return;
    }
    if (node.isFolder && current.path.startsWith(oldPath)) {
      final nextPath = '$newPath${current.path.substring(oldPath.length)}';
      value = value.copyWith(
        currentDocument: current.copyWith(path: nextPath),
      );
    }
  }

  Future<void> deleteNode(ForgeFileNode node) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null || _repository == null) {
      return;
    }
    await _repository.deletePath(
      ownerId: _requireOwnerId(),
      repoId: selectedRepository.id,
      path: node.path,
      isFolder: node.isFolder,
    );
    final current = value.currentDocument;
    if (current == null) {
      return;
    }
    final shouldClear = !node.isFolder
        ? current.path == node.path
        : current.path.startsWith(node.path);
    if (shouldClear) {
      value = value.copyWith(
        clearCurrentDocument: true,
        clearSelectedFile: true,
        clearCurrentExecutionSession: true,
      );
    }
  }

  String _buildRenamedPath(String oldPath, String nextName, bool isFolder) {
    final normalizedName = nextName.trim().replaceAll('\\', '/');
    if (normalizedName.isEmpty) {
      throw ArgumentError('Name cannot be empty.');
    }
    if (normalizedName.contains('..')) {
      throw ArgumentError('Path cannot contain "..".');
    }
    if (normalizedName.contains('/')) {
      if (isFolder) {
        return normalizedName.endsWith('/') ? normalizedName : '$normalizedName/';
      }
      return normalizedName;
    }
    final parts = oldPath.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      throw ArgumentError('Invalid path.');
    }
    parts[parts.length - 1] = normalizedName;
    final joined = parts.join('/');
    if (isFolder) {
      return '$joined/';
    }
    return joined;
  }

  Future<void> runAiAction({
    required String prompt,
    ForgeAiProvider? provider,
  }) async {
    final selectedRepository = value.selectedRepository;
    if (selectedRepository == null) {
      return;
    }
    value = value.copyWith(isRunningAi: true, clearError: true);
    try {
      final taskId = await _repository!.enqueueAgentTask(
        repoId: selectedRepository.id,
        prompt: prompt,
        currentFilePath: value.currentDocument?.path,
        deepMode: value.repoExecutionDeepMode,
        threadId: value.selectedPromptThreadId,
        provider: provider?.name,
      );
      value = value.copyWith(
        isRunningAi: false,
        selectedAgentTaskId: taskId,
      );
      await _bindAgentTaskEvents();
      await _syncSelectedAgentTaskExecution();
      unawaited(
        _telemetry.logEvent(
          'forge_agent_task_started_from_editor',
          parameters: <String, Object?>{
            'provider': provider?.name ?? 'auto',
            'provider_routed': provider?.name ?? 'auto',
            'repo_id': selectedRepository.id,
            'mode': value.repoExecutionDeepMode ? 'deep' : 'normal',
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isRunningAi: false,
        errorMessage: forgeUserFriendlyMessage(error),
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

  Future<void> approveCurrentExecution() async {
    final agentTask = value.selectedAgentTask;
    if (agentTask != null &&
        agentTask.status == ForgeAgentTaskStatus.waitingForInput &&
        agentTask.pendingApproval?.type ==
            ForgeAgentTaskApprovalType.applyChanges) {
      await resolveAgentTaskApproval(approved: true, taskId: agentTask.id);
      return;
    }
    final session = value.currentExecutionSession;
    final currentDocument = value.currentDocument;
    if (session == null) {
      return;
    }
    value = value.copyWith(isSavingFile: true, clearError: true);
    try {
      await _repository!.applyRepoExecution(
        repoId: session.repoId,
        sessionId: session.id,
      );
      ForgeRepoExecutionFileChange? currentEdit;
      if (currentDocument != null) {
        for (final edit in session.edits) {
          if (edit.path == currentDocument.path) {
            currentEdit = edit;
            break;
          }
        }
      }
      value = value.copyWith(
        isSavingFile: false,
        currentDocument: currentEdit == null
            ? currentDocument
            : (currentEdit.action == 'delete'
                  ? null
                  : currentDocument?.copyWith(
                      content: currentEdit.afterContent,
                      originalContent: currentEdit.beforeContent,
                      updatedAt: DateTime.now(),
                    )),
        clearSelectedFile:
            currentEdit != null && currentEdit.action == 'delete',
        clearCurrentExecutionSession: true,
      );
      final trace = value.promptLastAgentTrace;
      if (trace != null) {
        value = value.copyWith(
          promptLastAgentTrace: ForgePromptAgentTrace(
            threadId: trace.threadId,
            recordedAt: DateTime.now(),
            steps: trace.steps,
            inspectedFiles: trace.inspectedFiles,
            proposedEditFiles: trace.proposedEditFiles,
            plannedEdits: trace.plannedEdits,
            appliedEdits: session.edits
                .map(
                  (edit) => ForgePromptAppliedEdit(
                    path: edit.path,
                    action: edit.action,
                  ),
                )
                .toList(),
            summary: trace.summary,
          ),
        );
      }
      unawaited(
        _telemetry.logEvent(
          'forge_repo_execution_applied',
          parameters: <String, Object?>{
            'estimated_tokens': session.estimatedTokens,
            'edit_count': session.edits.length,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isSavingFile: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_approve_execution',
        ),
      );
      rethrow;
    }
  }

  Future<void> rejectCurrentExecution() async {
    final agentTask = value.selectedAgentTask;
    if (agentTask != null &&
        agentTask.status == ForgeAgentTaskStatus.waitingForInput &&
        agentTask.pendingApproval?.type ==
            ForgeAgentTaskApprovalType.applyChanges) {
      await resolveAgentTaskApproval(approved: false, taskId: agentTask.id);
      return;
    }
    final session = value.currentExecutionSession;
    if (session == null) {
      return;
    }
    value = value.copyWith(clearCurrentExecutionSession: true);
    unawaited(
      _telemetry.logEvent(
        'forge_repo_execution_rejected',
        parameters: <String, Object?>{
          'estimated_tokens': session.estimatedTokens,
          'edit_count': session.edits.length,
        },
      ),
    );
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
        fileChanges: const <Map<String, String?>>[],
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
        errorMessage: forgeUserFriendlyMessage(error),
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

  static String _pickRunAppWorkflowPath(List<ForgeRepoWorkflow> workflows) {
    if (workflows.isEmpty) return 'run-app.yml';
    for (final workflow in workflows) {
      final name = workflow.name.toLowerCase();
      final path = workflow.path.toLowerCase();
      final isRunApp = name.contains('run-app') ||
          path.contains('run-app') ||
          (name.contains('run') && name.contains('app')) ||
          (path.contains('run') && path.contains('app'));
      if (isRunApp) {
        return workflow.path;
      }
    }
    return 'run-app.yml';
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
      final String friendly = forgeErrorLooksLikeMissingGithubWorkflow(error)
          ? 'No workflow found in this repo. Add a file at .github/workflows/ci.yml with "on: workflow_dispatch:" to run checks from the app.'
          : forgeUserFriendlyMessage(error);
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


  /// Dispatches a GitHub Actions workflow that deploys Firebase Cloud Functions.
  Future<String?> runDeployFunctionsWorkflow({
    String workflowName = 'deploy-functions.yml',
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
          'forge_deploy_functions_workflow_submitted',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
            'workflow': workflowName,
          },
        ),
      );
      return logsUrl;
    } catch (error) {
      final friendly = forgeErrorLooksLikeMissingGithubWorkflow(error)
          ? 'No deploy workflow found. Add .github/workflows/deploy-functions.yml with workflow_dispatch, then retry the deploy run.'
          : forgeUserFriendlyMessage(error);
      value = value.copyWith(
        isRunningCheck: false,
        errorMessage: friendly,
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_deploy_functions_workflow',
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
      var resolvedWorkflowName = workflowName;
      if (resolvedWorkflowName.trim().isEmpty ||
          resolvedWorkflowName.trim() == 'run-app.yml') {
        var workflows = value.repoWorkflows;
        if (workflows.isEmpty) {
          await loadRepoWorkflows();
          workflows = value.repoWorkflows;
        }
        resolvedWorkflowName = _pickRunAppWorkflowPath(workflows);
      }
      final result = await _repository!.submitCheckAction(
        repoId: selectedRepository.id,
        provider: selectedRepository.providerLabel.toLowerCase(),
        actionType: ForgeCheckActionType.buildProject,
        workflowName: resolvedWorkflowName,
      );
      value = value.copyWith(isRunningCheck: false);
      await loadRepoWorkflows();
      final logsUrl = result['logsUrl'] as String?;
      unawaited(
        _telemetry.logEvent(
          'forge_run_app_workflow_submitted',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
            'workflow': resolvedWorkflowName,
          },
        ),
      );
      return logsUrl;
    } catch (error) {
      final friendly = forgeErrorLooksLikeMissingGithubWorkflow(error)
          ? 'No app-run workflow found. Add .github/workflows/run-app.yml with workflow_dispatch and screenshot/log artifact upload.'
          : forgeUserFriendlyMessage(error);
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

  Future<void> installDeployFunctionsWorkflowViaGit({
    required String branchName,
    String commitMessage = 'chore: add deploy-functions workflow',
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
            'path': '.github/workflows/deploy-functions.yml',
            'content': _deployFunctionsWorkflowTemplate,
          },
        ],
        branchName: branchName,
        commitMessage: commitMessage,
      );
      value = value.copyWith(isSubmittingGitAction: false);
      unawaited(
        _telemetry.logEvent(
          'forge_install_deploy_functions_workflow',
          parameters: <String, Object?>{
            'provider': selectedRepository.provider.name,
            'branch': branchName,
          },
        ),
      );
    } catch (error) {
      value = value.copyWith(
        isSubmittingGitAction: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
      unawaited(
        _telemetry.recordError(
          error,
          StackTrace.current,
          reason: 'workspace_install_deploy_functions_workflow',
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
        errorMessage: forgeUserFriendlyMessage(error),
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
    await _agentTasksSubscription?.cancel();
    await _agentTaskEventsSubscription?.cancel();
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChanged);
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}
