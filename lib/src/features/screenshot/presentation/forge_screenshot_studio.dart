import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/branding/app_branding.dart';
import '../../../shared/forge_models.dart';
import '../../../shared/widgets/forge_widgets.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/domain/auth_provider_kind.dart';
import '../../auth/domain/auth_reauth_request.dart';
import '../../auth/domain/auth_repository.dart';
import '../../auth/presentation/auth_entry_screen.dart';
import '../../checks/checks_dashboard_screen.dart';
import '../../dashboard/dashboard_screen.dart';
import '../../diff/diff_review_screen.dart';
import '../../editor/editor_workflow_screen.dart';
import '../../repos/repositories_screen.dart';
import '../../settings/settings_screen.dart';
import '../../wallet/wallet_screen.dart';
import '../../workspace/application/forge_workspace_controller.dart';
import '../../workspace/domain/forge_workspace_entities.dart';
import '../../workspace/domain/forge_workspace_state.dart';

class ForgeScreenshotStudio extends StatefulWidget {
  const ForgeScreenshotStudio({super.key, required this.scene});

  final String scene;

  @override
  State<ForgeScreenshotStudio> createState() => _ForgeScreenshotStudioState();
}

class _ForgeScreenshotStudioState extends State<ForgeScreenshotStudio> {
  late final AuthController _signedOutController = AuthController(
    repository: _PreviewAuthRepository(account: null),
  );
  late final AuthController _signedInController = AuthController(
    repository: _PreviewAuthRepository(account: _previewAccount),
  );
  late final ForgeWorkspaceController _workspaceController =
      ForgeWorkspaceController.preview(authController: _signedInController)
        ..value = _previewWorkspaceState();

  static final AuthAccount _previewAccount = AuthAccount(
    id: 'preview-forge-user',
    email: 'launch@forgeai.dev',
    displayName: '$kAppDisplayName Beta',
    provider: AuthProviderKind.github,
    createdAt: DateTime(2026, 3, 18, 9),
    providerLinkedAt: DateTime(2026, 3, 18, 9),
    emailVerified: true,
    linkedProviders: const {
      AuthProviderKind.github,
      AuthProviderKind.google,
      AuthProviderKind.apple,
    },
  );

  @override
  void dispose() {
    _workspaceController.dispose();
    _signedInController.dispose();
    _signedOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.scene.trim().toLowerCase()) {
      case 'auth':
        return AuthEntryScreen(controller: _signedOutController);
      case 'dashboard':
        return DashboardScreen(controller: _workspaceController);
      case 'repo':
        return RepositoriesScreen(controller: _workspaceController);
      case 'editor':
        return EditorWorkflowScreen(controller: _workspaceController);
      case 'diff':
        return DiffReviewScreen(controller: _workspaceController);
      case 'checks':
        return ChecksDashboardScreen(controller: _workspaceController);
      case 'wallet':
        return WalletScreen(controller: _workspaceController);
      case 'settings':
        return SettingsScreen(
          controller: _signedInController,
          account: _previewAccount,
          workspaceController: _workspaceController,
        );
      default:
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: ForgeScreen(
            child: ListView(
              children: const [
                ForgePanel(
                  highlight: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ForgeSectionHeader(
                        title: 'Screenshot Studio',
                        subtitle:
                            'Use --dart-define=FORGEAI_SCREENSHOT_SCENE=<scene> with one of: auth, dashboard, repo, editor, diff, checks, wallet, settings.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  ForgeWorkspaceState _previewWorkspaceState() {
    const repo = ForgeRepository(
      id: 'repo_mobile_app',
      name: 'mobile-app',
      owner: 'forgeai',
      provider: ForgeProvider.github,
      language: 'Flutter',
      description: 'Premium mobile client for AI-assisted repository review.',
      defaultBranch: 'main',
      status: 'Healthy',
      openPullRequests: 4,
      openMergeRequests: 0,
      changedFiles: 3,
      lastSynced: Duration(minutes: 8),
      stars: 182,
      isProtected: true,
      htmlUrl: 'https://github.com/forgeai/mobile-app',
    );

    const selectedFile = ForgeFileNode(
      name: 'forge_workspace_repository.dart',
      path: 'lib/src/features/workspace/data/forge_workspace_repository.dart',
      language: 'Dart',
      sizeLabel: '12 KB',
      changeLabel: '3 changes',
      isSelected: true,
    );

    const files = <ForgeFileNode>[
      ForgeFileNode(
        name: 'lib',
        path: 'lib',
        language: 'Folder',
        sizeLabel: '4 items',
        changeLabel: '',
        isFolder: true,
        children: [
          ForgeFileNode(
            name: 'src',
            path: 'lib/src',
            language: 'Folder',
            sizeLabel: '3 items',
            changeLabel: '',
            isFolder: true,
            isSelected: true,
            children: [
              ForgeFileNode(
                name: 'features',
                path: 'lib/src/features',
                language: 'Folder',
                sizeLabel: '2 items',
                changeLabel: '',
                isFolder: true,
                isSelected: true,
                children: [
                  ForgeFileNode(
                    name: 'workspace',
                    path: 'lib/src/features/workspace',
                    language: 'Folder',
                    sizeLabel: '1 item',
                    changeLabel: '',
                    isFolder: true,
                    isSelected: true,
                    children: [selectedFile],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      ForgeFileNode(
        name: 'README.md',
        path: 'README.md',
        language: 'Markdown',
        sizeLabel: '4 KB',
        changeLabel: '',
      ),
    ];

    const beforeContent = '''
Future<void> refreshSelectedRepository() async {
  final selectedRepository = value.selectedRepository;
  if (selectedRepository == null) {
    return;
  }
  await _repository!.syncRepository(selectedRepository.id);
}
''';

    const afterContent = '''
Future<void> refreshSelectedRepository() async {
  final selectedRepository = value.selectedRepository;
  if (selectedRepository == null) {
    return;
  }
  value = value.copyWith(isSyncing: true, clearError: true);
  await _repository!.syncRepository(selectedRepository.id);
  value = value.copyWith(isSyncing: false);
}
''';

    return ForgeWorkspaceState(
      repositories: const [repo],
      connections: const [
        ForgeConnection(
          provider: ForgeProvider.github,
          account: 'forgeai-mobile',
          scopeSummary: 'repo, workflow, pull_request',
          status: ForgeConnectionStatus.connected,
          lastChecked: '2m ago',
        ),
      ],
      files: files,
      activities: const [
        ForgeActivityEntry(
          title: 'Approved AI patch',
          subtitle: 'Repository sync state now logs failures before retry.',
          timestamp: '11m ago',
          icon: Icons.auto_awesome_rounded,
          accent: Color(0xFF60A5FA),
        ),
        ForgeActivityEntry(
          title: 'Queued mobile smoke tests',
          subtitle: 'GitHub Actions run requested for beta/smoke/launch-pass.',
          timestamp: '24m ago',
          icon: Icons.rule_folder_rounded,
          accent: Color(0xFF22C55E),
        ),
      ],
      checks: const [
        ForgeCheckRun(
          name: 'Mobile smoke tests',
          status: ForgeCheckStatus.running,
          summary: '14 of 19 jobs completed',
          duration: '4m 12s',
          logsAvailable: true,
          progress: 0.74,
        ),
        ForgeCheckRun(
          name: 'Static analysis',
          status: ForgeCheckStatus.passed,
          summary: 'Analyzer clean',
          duration: '58s',
          logsAvailable: true,
          progress: 1,
        ),
      ],
      tokenLogs: const [
        ForgeTokenLog(
          action: 'AI suggestion',
          cost: '80',
          repo: 'forgeai/mobile-app',
          timestamp: '9m ago',
        ),
        ForgeTokenLog(
          action: 'Run tests',
          cost: '30',
          repo: 'forgeai/mobile-app',
          timestamp: '24m ago',
        ),
      ],
      wallet: const ForgeTokenWallet(
        planName: 'Beta Pro',
        balance: 18240,
        monthlyAllowance: 50000,
        spentThisWeek: 1180,
        nextReset: 'Monday 09:00',
        currencySymbol: 'tokens',
      ),
      selectedRepository: repo,
      selectedBranch: 'beta/release-readiness',
      selectedFile: selectedFile,
      currentDocument: const ForgeFileDocument(
        repoId: 'repo_mobile_app',
        path: 'lib/src/features/workspace/data/forge_workspace_repository.dart',
        language: 'Dart',
        content: afterContent,
        originalContent: beforeContent,
        updatedAt: null,
        sha: 'preview-sha',
      ),
      currentChangeRequest: const ForgeChangeRequest(
        id: 'preview-change-request',
        repoId: 'repo_mobile_app',
        filePath:
            'lib/src/features/workspace/data/forge_workspace_repository.dart',
        provider: ForgeAiProvider.openai,
        prompt: 'Add visible syncing state before repository refresh.',
        status: 'draft',
        summary:
            'Stages a small UI-safe loading update around repository sync.',
        beforeContent: beforeContent,
        afterContent: afterContent,
        diffLines: [
          ForgeDiffLine(
            prefix: '-',
            line: '  await _repository!.syncRepository(selectedRepository.id);',
            isAddition: false,
          ),
          ForgeDiffLine(
            prefix: '+',
            line:
                '  value = value.copyWith(isSyncing: true, clearError: true);',
            isAddition: true,
          ),
          ForgeDiffLine(
            prefix: '+',
            line: '  await _repository!.syncRepository(selectedRepository.id);',
            isAddition: true,
          ),
          ForgeDiffLine(
            prefix: '+',
            line: '  value = value.copyWith(isSyncing: false);',
            isAddition: true,
          ),
        ],
        estimatedTokens: 80,
      ),
    );
  }
}

class _PreviewAuthRepository implements AuthRepository {
  _PreviewAuthRepository({required AuthAccount? account}) : _account = account;

  final StreamController<AuthAccount?> _controller =
      StreamController<AuthAccount?>.broadcast();
  AuthAccount? _account;

  @override
  Stream<AuthAccount?> watchCurrentAccount() async* {
    yield _account;
    yield* _controller.stream;
  }

  @override
  Future<AuthAccount?> bootstrap() async => _account;

  @override
  Future<AuthAccount> continueAsGuest() async => _requireAccount();

  @override
  Future<AuthAccount> signInWithEmail({
    required String email,
    required String password,
  }) async => _requireAccount();

  @override
  Future<AuthAccount> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async => _requireAccount();

  @override
  Future<AuthAccount> signInWithProvider(AuthProviderKind provider) async =>
      _requireAccount();

  @override
  Future<AuthAccount> reauthenticate(AuthReauthRequest request) async =>
      _requireAccount();

  @override
  Future<void> signOut() async {
    _account = null;
    if (!_controller.isClosed) {
      _controller.add(null);
    }
  }

  @override
  Future<void> deleteCurrentAccount({
    required String confirmationPhrase,
  }) async {
    if (confirmationPhrase.trim().toUpperCase() != 'DELETE') {
      throw StateError('Preview deletion requires DELETE.');
    }
    await signOut();
  }

  AuthAccount _requireAccount() {
    final account = _account;
    if (account == null) {
      throw StateError('No preview account configured.');
    }
    return account;
  }
}
