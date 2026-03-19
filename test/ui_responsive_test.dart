import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ai/src/core/theme/app_theme.dart';
import 'package:forge_ai/src/core/theme/forge_palette.dart';
import 'package:forge_ai/src/features/account/presentation/account_settings_screen.dart';
import 'package:forge_ai/src/features/account/presentation/delete_account_screen.dart';
import 'package:forge_ai/src/features/activity/activity_timeline_screen.dart';
import 'package:forge_ai/src/features/ask/ask_screen.dart';
import 'package:forge_ai/src/features/auth/application/auth_controller.dart';
import 'package:forge_ai/src/features/auth/domain/auth_account.dart';
import 'package:forge_ai/src/features/auth/domain/auth_failure.dart';
import 'package:forge_ai/src/features/auth/domain/auth_provider_kind.dart';
import 'package:forge_ai/src/features/auth/domain/auth_reauth_request.dart';
import 'package:forge_ai/src/features/auth/domain/auth_repository.dart';
import 'package:forge_ai/src/features/auth/presentation/auth_entry_screen.dart';
import 'package:forge_ai/src/features/auth/presentation/create_account_screen.dart';
import 'package:forge_ai/src/features/billing/data/mock_forge_billing_service.dart';
import 'package:forge_ai/src/features/billing/presentation/paywall_screen.dart';
import 'package:forge_ai/src/features/billing/presentation/token_packs_screen.dart';
import 'package:forge_ai/src/features/checks/checks_dashboard_screen.dart';
import 'package:forge_ai/src/features/dashboard/dashboard_screen.dart';
import 'package:forge_ai/src/features/diff/diff_review_screen.dart';
import 'package:forge_ai/src/features/editor/editor_workflow_screen.dart';
import 'package:forge_ai/src/features/git/git_workflow_screen.dart';
import 'package:forge_ai/src/features/legal/legal_document_screen.dart';
import 'package:forge_ai/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:forge_ai/src/features/repos/account_hub_screen.dart';
import 'package:forge_ai/src/features/repos/new_ai_project_screen.dart';
import 'package:forge_ai/src/features/repos/repositories_screen.dart';
import 'package:forge_ai/src/features/repos/repository_connection_screen.dart';
import 'package:forge_ai/src/features/settings/settings_screen.dart';
import 'package:forge_ai/src/features/wallet/wallet_screen.dart';
import 'package:forge_ai/src/features/workspace/application/forge_workspace_controller.dart';
import 'package:forge_ai/src/features/workspace/domain/forge_workspace_entities.dart';
import 'package:forge_ai/src/features/workspace/domain/forge_workspace_state.dart';
import 'package:forge_ai/src/shared/forge_models.dart';

void main() {
  testWidgets('core screens render cleanly across compact mobile widths', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const widths = <double>[320, 375, 430];

    for (final width in widths) {
      final harness = _UiHarness.create();

      final screens = <MapEntry<String, Widget>>[
        MapEntry<String, Widget>(
          'AuthEntryScreen',
          AuthEntryScreen(controller: harness.unsignedAuthController),
        ),
        MapEntry<String, Widget>(
          'CreateAccountScreen',
          CreateAccountScreen(controller: harness.unsignedAuthController),
        ),
        MapEntry<String, Widget>(
          'OnboardingScreen',
          OnboardingScreen(onComplete: () {}),
        ),
        MapEntry<String, Widget>(
          'DashboardScreen',
          DashboardScreen(
            controller: harness.workspaceController,
            account: harness.account,
            authController: harness.signedInAuthController,
            onOpenRepository: () {},
            onOpenHub: () {},
            onOpenPrompt: () {},
            onOpenCodeEditor: () {},
            onOpenChecks: () {},
            onOpenWallet: () {},
            onOpenActivity: () {},
          ),
        ),
        MapEntry<String, Widget>(
          'RepositoriesScreen',
          RepositoriesScreen(
            controller: harness.workspaceController,
            account: harness.account,
            authController: harness.signedInAuthController,
            onOpenFile: (_) {},
          ),
        ),
        MapEntry<String, Widget>(
          'AccountHubScreen',
          AccountHubScreen(
            controller: harness.workspaceController,
            account: harness.account,
            authController: harness.signedInAuthController,
            onSwitchToRepoTab: () {},
            onSwitchToAskTab: () {},
          ),
        ),
        MapEntry<String, Widget>(
          'AskScreen',
          AskScreen(controller: harness.workspaceController),
        ),
        MapEntry<String, Widget>(
          'EditorWorkflowScreen',
          EditorWorkflowScreen(
            controller: harness.workspaceController,
            onSwitchToRepoTab: () {},
          ),
        ),
        MapEntry<String, Widget>(
          'DiffReviewScreen',
          DiffReviewScreen(controller: harness.workspaceController),
        ),
        MapEntry<String, Widget>(
          'ChecksDashboardScreen',
          ChecksDashboardScreen(controller: harness.workspaceController),
        ),
        MapEntry<String, Widget>(
          'WalletScreen',
          WalletScreen(
            controller: harness.workspaceController,
            onUpgrade: () {},
            onGetTokens: () {},
          ),
        ),
        MapEntry<String, Widget>(
          'SettingsScreen',
          SettingsScreen(
            controller: harness.signedInAuthController,
            account: harness.account,
            workspaceController: harness.workspaceController,
            onOpenWallet: () {},
            onOpenAccount: () {},
          ),
        ),
        MapEntry<String, Widget>(
          'RepositoryConnectionScreen',
          RepositoryConnectionScreen(controller: harness.workspaceController),
        ),
        MapEntry<String, Widget>(
          'NewAiProjectScreen',
          NewAiProjectScreen(controller: harness.workspaceController),
        ),
        MapEntry<String, Widget>(
          'GitWorkflowScreen',
          GitWorkflowScreen(controller: harness.workspaceController),
        ),
        MapEntry<String, Widget>(
          'ActivityTimelineScreen',
          ActivityTimelineScreen(controller: harness.workspaceController),
        ),
        MapEntry<String, Widget>(
          'PaywallScreen',
          PaywallScreen(
            billingService: MockForgeBillingService(),
            onUpgrade: (_) {},
            onRestore: () {},
          ),
        ),
        MapEntry<String, Widget>(
          'TokenPacksScreen',
          TokenPacksScreen(billingService: MockForgeBillingService()),
        ),
        MapEntry<String, Widget>(
          'AccountSettingsScreen',
          AccountSettingsScreen(controller: harness.signedInAuthController),
        ),
        MapEntry<String, Widget>(
          'DeleteAccountScreen',
          DeleteAccountScreen(controller: harness.signedInAuthController),
        ),
        MapEntry<String, Widget>(
          'LegalDocumentScreen',
          const LegalDocumentScreen(
            title: 'Privacy Policy',
            assetPath: 'assets/legal/privacy_policy.md',
          ),
        ),
      ];

      for (final screen in screens) {
        await _pumpMobileScreen(
          tester,
          width: width,
          child: _wrapWithApp(screen.value),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.key} threw during initial render at width $width',
        );

        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          await tester.drag(scrollables.first, const Offset(0, -300));
          await tester.pump(const Duration(milliseconds: 150));
          expect(
            tester.takeException(),
            isNull,
            reason: '${screen.key} threw while scrolling at width $width',
          );
        }
      }

      harness.dispose();
    }
  });
}

Widget _wrapWithApp(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ForgeAiTheme.dark(),
    home: child,
  );
}

Future<void> _pumpMobileScreen(
  WidgetTester tester, {
  required double width,
  required Widget child,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  await tester.pumpWidget(child);
  await tester.pump(const Duration(milliseconds: 250));
}

class _UiHarness {
  _UiHarness._({
    required this.account,
    required this.signedInAuthController,
    required this.unsignedAuthController,
    required this.workspaceController,
    required this.signedInRepository,
    required this.unsignedRepository,
  });

  final AuthAccount account;
  final AuthController signedInAuthController;
  final AuthController unsignedAuthController;
  final ForgeWorkspaceController workspaceController;
  final _TestAuthRepository signedInRepository;
  final _TestAuthRepository unsignedRepository;

  static _UiHarness create() {
    final account = AuthAccount(
      id: 'tester-1',
      email: 'tester@forgeai.dev',
      displayName: 'Forge Tester',
      provider: AuthProviderKind.emailPassword,
      createdAt: DateTime(2026, 3, 1),
      providerLinkedAt: DateTime(2026, 3, 1),
      lastReauthenticatedAt: DateTime.now(),
      emailVerified: true,
      linkedProviders: const {AuthProviderKind.emailPassword},
    );

    final signedInRepository = _TestAuthRepository(seedAccount: account);
    final unsignedRepository = _TestAuthRepository(seedAccount: null);
    final signedInAuthController = AuthController(
      repository: signedInRepository,
    );
    final unsignedAuthController = AuthController(
      repository: unsignedRepository,
    );
    final workspaceController = ForgeWorkspaceController.preview(
      authController: signedInAuthController,
    );
    workspaceController.value = _sampleWorkspaceState();

    return _UiHarness._(
      account: account,
      signedInAuthController: signedInAuthController,
      unsignedAuthController: unsignedAuthController,
      workspaceController: workspaceController,
      signedInRepository: signedInRepository,
      unsignedRepository: unsignedRepository,
    );
  }

  void dispose() {
    workspaceController.dispose();
    signedInAuthController.dispose();
    unsignedAuthController.dispose();
    signedInRepository.dispose();
    unsignedRepository.dispose();
  }
}

ForgeWorkspaceState _sampleWorkspaceState() {
  const primaryRepo = ForgeRepository(
    id: 'repo-primary',
    name: 'mobile-client-with-an-extremely-long-name-for-small-screen-layouts',
    owner: 'forgeai-labs-platform-team',
    provider: ForgeProvider.github,
    language: 'Dart',
    description:
        'A deliberately long repository description used to verify that cards, metadata, and actions stay readable on narrow mobile screens without clipped text.',
    defaultBranch: 'feature/mobile-ui-cleanup-with-accessibility-improvements',
    status: 'Healthy',
    openPullRequests: 4,
    openMergeRequests: 1,
    changedFiles: 12,
    lastSynced: Duration(minutes: 37),
    stars: 182,
    isProtected: true,
    branches: <String>[
      'main',
      'develop',
      'feature/mobile-ui-cleanup-with-accessibility-improvements',
    ],
    htmlUrl:
        'https://github.com/forgeai-labs-platform-team/mobile-client-with-an-extremely-long-name-for-small-screen-layouts',
  );
  const secondaryRepo = ForgeRepository(
    id: 'repo-secondary',
    name: 'backend-contracts-and-provider-integration-service',
    owner: 'forgeai-labs-platform-team',
    provider: ForgeProvider.github,
    language: 'TypeScript',
    description:
        'Contracts and functions used for sync, prompts, checks, and provider integrations.',
    defaultBranch: 'main',
    status: 'Needs review',
    openPullRequests: 2,
    openMergeRequests: 3,
    changedFiles: 6,
    lastSynced: Duration(hours: 2),
    stars: 94,
    isProtected: false,
    branches: <String>['main', 'release/2026-03'],
    htmlUrl:
        'https://github.com/forgeai-labs-platform-team/backend-contracts-and-provider-integration-service',
  );

  const files = <ForgeFileNode>[
    ForgeFileNode(
      name: 'lib',
      path: 'lib',
      language: 'folder',
      sizeLabel: '',
      changeLabel: '',
      isFolder: true,
      children: <ForgeFileNode>[
        ForgeFileNode(
          name: 'src',
          path: 'lib/src',
          language: 'folder',
          sizeLabel: '',
          changeLabel: '',
          isFolder: true,
          children: <ForgeFileNode>[
            ForgeFileNode(
              name:
                  'presentation_layer_with_a_name_that_used_to_truncate_badly.dart',
              path:
                  'lib/src/presentation/presentation_layer_with_a_name_that_used_to_truncate_badly.dart',
              language: 'dart',
              sizeLabel: '18 KB',
              changeLabel: 'M',
            ),
            ForgeFileNode(
              name: 'widgets',
              path: 'lib/src/widgets',
              language: 'folder',
              sizeLabel: '',
              changeLabel: '',
              isFolder: true,
              children: <ForgeFileNode>[
                ForgeFileNode(
                  name:
                      'repository_card_with_extra_metadata_for_small_screens.dart',
                  path:
                      'lib/src/widgets/repository_card_with_extra_metadata_for_small_screens.dart',
                  language: 'dart',
                  sizeLabel: '9 KB',
                  changeLabel: 'A',
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];

  final promptThread = ForgePromptThread(
    id: 'thread-1',
    title:
        'Refine the mobile repository flow and keep every action readable on small screens',
    repoId: primaryRepo.id,
    updatedAt: DateTime(2026, 3, 19, 11, 30),
    messages: <ForgePromptMessage>[
      ForgePromptMessage(
        id: 'msg-1',
        role: 'user',
        text:
            'Please simplify the repository connection flow and make sure nothing is visually cramped on a small phone.',
        createdAt: DateTime(2026, 3, 19, 11, 0),
      ),
      ForgePromptMessage(
        id: 'msg-2',
        role: 'assistant',
        text:
            'I can help with that. I will keep actions obvious, avoid clipped text, and preserve the review-first workflow.',
        createdAt: DateTime(2026, 3, 19, 11, 1),
      ),
    ],
  );

  final currentDocument = ForgeFileDocument(
    repoId: primaryRepo.id,
    path:
        'lib/src/presentation/presentation_layer_with_a_name_that_used_to_truncate_badly.dart',
    language: 'dart',
    content:
        "class ExampleScreen {\n  const ExampleScreen();\n\n  String buildTitle() => 'Small-screen ready';\n}\n",
    originalContent:
        "class ExampleScreen {\n  const ExampleScreen();\n\n  String buildTitle() => 'Small-screen ready';\n}\n",
    updatedAt: null,
  );

  final changeRequest = ForgeChangeRequest(
    id: 'change-1',
    repoId: primaryRepo.id,
    filePath:
        'lib/src/presentation/presentation_layer_with_a_name_that_used_to_truncate_badly.dart',
    provider: ForgeAiProvider.openai,
    prompt: 'Improve small-screen layout spacing and remove truncated text.',
    status: 'draft',
    summary: 'Adjusts spacing, wrapping, and button grouping for mobile.',
    beforeContent: 'Row(children:[Text("Old title"),Text("Cut off")])',
    afterContent: 'Wrap(children:[Text("Old title"),Text("Visible title")])',
    estimatedTokens: 420,
    diffLines: <ForgeDiffLine>[
      ForgeDiffLine(
        prefix: '-',
        line: 'Row(children:[...])',
        isAddition: false,
      ),
      ForgeDiffLine(
        prefix: '+',
        line: 'Wrap(children:[...])',
        isAddition: true,
      ),
      ForgeDiffLine(
        prefix: '+',
        line: 'Buttons now stack and wrap on small devices.',
        isAddition: true,
      ),
    ],
  );

  return ForgeWorkspaceState(
    repositories: const <ForgeRepository>[primaryRepo, secondaryRepo],
    connections: const <ForgeConnection>[
      ForgeConnection(
        provider: ForgeProvider.github,
        account: 'forgeai-mobile-team',
        scopeSummary: 'repo, workflow',
        status: ForgeConnectionStatus.connected,
        lastChecked: '2m ago',
      ),
      ForgeConnection(
        provider: ForgeProvider.github,
        account: 'forgeai-platform',
        scopeSummary: 'api',
        status: ForgeConnectionStatus.connected,
        lastChecked: '6m ago',
      ),
    ],
    files: files,
    activities: const <ForgeActivityEntry>[
      ForgeActivityEntry(
        title: 'Repository sync completed',
        subtitle:
            'The mobile repository now includes the latest workflow and diff metadata for review.',
        timestamp: '11m ago',
        icon: Icons.sync_rounded,
        accent: ForgePalette.glowAccent,
      ),
      ForgeActivityEntry(
        title: 'AI change prepared for review',
        subtitle:
            'A small-screen layout refinement is ready for approval before commit.',
        timestamp: '9m ago',
        icon: Icons.auto_awesome_rounded,
        accent: ForgePalette.success,
      ),
    ],
    checks: const <ForgeCheckRun>[
      ForgeCheckRun(
        name: 'Mobile UI smoke tests for narrow screens',
        status: ForgeCheckStatus.passed,
        summary:
            'No overflows or clipping detected in common navigation paths.',
        duration: '2m 14s',
        logsAvailable: true,
        progress: 1,
      ),
      ForgeCheckRun(
        name: 'Analyzer',
        status: ForgeCheckStatus.running,
        summary: 'Reviewing UI widgets and theme rules.',
        duration: '48s',
        logsAvailable: false,
        progress: 0.5,
      ),
    ],
    tokenLogs: const <ForgeTokenLog>[
      ForgeTokenLog(
        action: 'Prompt for mobile UI simplification',
        cost: '320',
        repo: 'forgeai/mobile-client',
        timestamp: '12m ago',
      ),
      ForgeTokenLog(
        action: 'AI edit for repository cards',
        cost: '180',
        repo: 'forgeai/mobile-client',
        timestamp: '25m ago',
      ),
    ],
    promptThreads: <ForgePromptThread>[promptThread],
    selectedPromptThreadId: promptThread.id,
    notificationPreferences: const ForgeNotificationPreferences(),
    wallet: const ForgeTokenWallet(
      planName: 'Pro',
      balance: 12480,
      monthlyAllowance: 30000,
      spentThisWeek: 4720,
      nextReset: 'Apr 1',
      currencySymbol: 'tokens',
    ),
    selectedRepository: primaryRepo,
    selectedBranch: primaryRepo.defaultBranch,
    selectedFile: files.first.children.first.children.first,
    currentDocument: currentDocument,
    currentChangeRequest: changeRequest,
  );
}

class _TestAuthRepository implements AuthRepository {
  _TestAuthRepository({required AuthAccount? seedAccount})
    : _currentAccount = seedAccount;

  final StreamController<AuthAccount?> _accountController =
      StreamController<AuthAccount?>.broadcast();
  AuthAccount? _currentAccount;

  @override
  Stream<AuthAccount?> watchCurrentAccount() async* {
    yield _currentAccount;
    yield* _accountController.stream;
  }

  @override
  Future<AuthAccount?> bootstrap() async => _currentAccount;

  @override
  Future<AuthAccount> continueAsGuest() async {
    final account = AuthAccount.guest(id: 'guest-test');
    _setAccount(account);
    return account;
  }

  @override
  Future<AuthAccount> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final account = AuthAccount(
      id: email,
      email: email,
      displayName: 'Forge Tester',
      provider: AuthProviderKind.emailPassword,
      createdAt: DateTime(2026, 3, 1),
      providerLinkedAt: DateTime(2026, 3, 1),
      lastReauthenticatedAt: DateTime.now(),
      emailVerified: true,
      linkedProviders: const {AuthProviderKind.emailPassword},
    );
    _setAccount(account);
    return account;
  }

  @override
  Future<AuthAccount> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return signInWithEmail(email: email, password: password);
  }

  @override
  Future<AuthAccount> signInWithProvider(AuthProviderKind provider) async {
    final account = AuthAccount(
      id: '${provider.name}-user',
      email: '${provider.name}@forgeai.dev',
      displayName: '${provider.label} User',
      provider: provider,
      createdAt: DateTime(2026, 3, 1),
      providerLinkedAt: DateTime(2026, 3, 1),
      lastReauthenticatedAt: DateTime.now(),
      emailVerified: true,
      linkedProviders: {provider},
    );
    _setAccount(account);
    return account;
  }

  @override
  Future<AuthAccount> reauthenticate(AuthReauthRequest request) async {
    final account = _currentAccount;
    if (account == null) {
      throw AuthFailure.accountNotFound();
    }
    return account.copyWith(lastReauthenticatedAt: DateTime.now());
  }

  @override
  Future<void> signOut() async {
    _setAccount(null);
  }

  @override
  Future<void> deleteCurrentAccount({
    required String confirmationPhrase,
  }) async {
    _setAccount(null);
  }

  void dispose() {
    unawaited(_accountController.close());
  }

  void _setAccount(AuthAccount? account) {
    _currentAccount = account;
    if (!_accountController.isClosed) {
      _accountController.add(account);
    }
  }
}
