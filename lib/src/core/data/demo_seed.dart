import '../models/forge_models.dart';

const demoRepositories = <ConnectedRepository>[
  ConnectedRepository(
    id: 'repo-forge',
    owner: 'forgeai',
    name: 'mobile-app',
    provider: GitProviderKind.github,
    defaultBranch: 'main',
    headBranch: 'fix/mobile-crash-report',
    description:
        'Flutter client for mobile-first repository review and AI edits.',
    lastActivityLabel: 'Opened 12m ago',
    isPrivate: true,
    pendingReviews: 3,
    pendingChecks: 1,
  ),
  ConnectedRepository(
    id: 'repo-api',
    owner: 'forgeai',
    name: 'backend-contracts',
    provider: GitProviderKind.gitlab,
    defaultBranch: 'main',
    headBranch: 'feature/token-ledger',
    description: 'Cloud Functions and shared provider contracts.',
    lastActivityLabel: 'Checks passed 1h ago',
    isPrivate: true,
    pendingReviews: 1,
    pendingChecks: 0,
  ),
];

const demoOpenFile = CodeFile(
  path: 'lib/src/features/editor/presentation/editor_screen.dart',
  language: 'dart',
  lastUpdatedLabel: 'Saved 5m ago',
  changeCount: 18,
  content: '''
class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(selectedRepositoryProvider);
    final draft = ref.watch(editorDraftProvider);

    return MobileCodeEditor(
      repositoryName: repo?.fullName ?? 'Select a repository',
      initialValue: draft,
      onSave: (value) => ref.read(editorDraftProvider.notifier).state = value,
      onRequestAi: () => ref.read(aiComposerControllerProvider.notifier).open(),
    );
  }
}
''',
);

const demoDiff = <ReviewLine>[
  ReviewLine(
    kind: ReviewLineKind.unchanged,
    oldLineNumber: 1,
    newLineNumber: 1,
    content: 'class EditorScreen extends ConsumerWidget {',
  ),
  ReviewLine(
    kind: ReviewLineKind.unchanged,
    oldLineNumber: 2,
    newLineNumber: 2,
    content: '  const EditorScreen({super.key});',
  ),
  ReviewLine(
    kind: ReviewLineKind.removed,
    oldLineNumber: 8,
    content: "    return const SizedBox.shrink();",
  ),
  ReviewLine(
    kind: ReviewLineKind.added,
    newLineNumber: 8,
    content: '    return MobileCodeEditor(',
  ),
  ReviewLine(
    kind: ReviewLineKind.added,
    newLineNumber: 9,
    content: "      repositoryName: repo?.fullName ?? 'Select a repository',",
  ),
  ReviewLine(
    kind: ReviewLineKind.added,
    newLineNumber: 10,
    content:
        '      onRequestAi: () => ref.read(aiComposerControllerProvider.notifier).open(),',
  ),
  ReviewLine(kind: ReviewLineKind.added, newLineNumber: 11, content: '    );'),
];

const demoChecks = <CheckRun>[
  CheckRun(
    id: 'check-tests',
    name: 'Mobile smoke tests',
    type: CheckRunType.tests,
    status: CheckRunStatus.running,
    branch: 'fix/mobile-crash-report',
    summary: '12 of 18 suites finished. Waiting on iOS simulator shard.',
    startedAtLabel: 'Started 4m ago',
    recentLogs: [
      'flutter test integration_test/repo_review_test.dart',
      'PASS widgets render diff approval step',
      'PASS repository connection banner',
      'RUNNING iOS smoke suite',
    ],
  ),
  CheckRun(
    id: 'check-lint',
    name: 'Static analysis',
    type: CheckRunType.lint,
    status: CheckRunStatus.passed,
    branch: 'feature/token-ledger',
    summary:
        'Analyzer clean. No prohibited command execution surfaces detected.',
    startedAtLabel: 'Completed 22m ago',
    recentLogs: ['flutter analyze', '0 issues found'],
  ),
];

const demoWallet = TokenWallet(
  balance: 12840,
  monthlyLimit: 50000,
  monthlyUsed: 21860,
  pendingReservation: 960,
);

const demoLedger = <TokenLedgerEntry>[
  TokenLedgerEntry(
    id: 'ledger-1',
    label: 'AI patch proposal',
    detail: 'OpenAI fix for repository sync state handling',
    delta: -320,
    timestampLabel: '9m ago',
  ),
  TokenLedgerEntry(
    id: 'ledger-2',
    label: 'Checks result summary',
    detail: 'Gemini summarization of failing Android workflow logs',
    delta: -120,
    timestampLabel: '37m ago',
  ),
  TokenLedgerEntry(
    id: 'ledger-3',
    label: 'Top-up',
    detail: 'Monthly team allocation',
    delta: 10000,
    timestampLabel: '2d ago',
  ),
];

const demoActivity = <ActivityRecord>[
  ActivityRecord(
    id: 'activity-1',
    kind: ActivityKind.commit,
    title: 'Prepared branch for mobile bug fix',
    description:
        'Created `fix/mobile-crash-report` and staged reviewed changes.',
    timestampLabel: '11m ago',
  ),
  ActivityRecord(
    id: 'activity-2',
    kind: ActivityKind.ai,
    title: 'AI change approved',
    description: 'Accepted 7-line patch after diff review.',
    timestampLabel: '13m ago',
  ),
  ActivityRecord(
    id: 'activity-3',
    kind: ActivityKind.checks,
    title: 'Triggered workflow',
    description: 'Ran GitHub Actions smoke tests from mobile checks panel.',
    timestampLabel: '16m ago',
  ),
  ActivityRecord(
    id: 'activity-4',
    kind: ActivityKind.security,
    title: 'Deletion protection enabled',
    description: 'Re-authentication required before account deletion.',
    timestampLabel: 'Today',
  ),
];

const demoAiPresets = <AiTaskPreset>[
  AiTaskPreset(
    id: 'ai-bugfix',
    title: 'Fix a mobile-visible bug',
    description: 'Generate a small, reviewable patch with a commit-ready diff.',
    provider: AiProviderKind.openai,
    estimatedTokens: 450,
  ),
  AiTaskPreset(
    id: 'ai-refactor',
    title: 'Refactor selected file',
    description:
        'Reorganize code without changing behavior or adding unsafe actions.',
    provider: AiProviderKind.anthropic,
    estimatedTokens: 720,
  ),
  AiTaskPreset(
    id: 'ai-explain',
    title: 'Explain failing check',
    description: 'Summarize logs into user-facing next steps.',
    provider: AiProviderKind.gemini,
    estimatedTokens: 180,
  ),
];

const demoGitActionDraft = GitActionDraft(
  branchName: 'fix/mobile-crash-report',
  commitMessage: 'Fix repository sync card loading state',
  pullRequestTitle: 'Fix repository sync card loading state',
  pullRequestDescription:
      'This patch improves the repository sync card state handling on mobile and keeps all changes reviewable before merge.',
);
