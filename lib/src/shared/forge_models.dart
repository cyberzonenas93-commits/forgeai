import 'package:flutter/material.dart';

enum ForgeProvider { github }

enum ForgeCheckStatus { queued, running, passed, failed }

enum ForgeConnectionStatus { connected, pending, disconnected }

enum ForgePushPermissionStatus {
  notDetermined,
  denied,
  authorized,
  provisional,
}

enum ForgeNotificationDestination {
  home,
  prompt,
  repo,
  settings,
  wallet,
  activity,
  checks,
}

class ForgeNotificationPreferences {
  const ForgeNotificationPreferences({
    this.enabled = true,
    this.checks = true,
    this.git = true,
    this.repository = true,
    this.ai = true,
    this.provider = true,
    this.wallet = true,
    this.security = true,
    this.digest = true,
  });

  final bool enabled;
  final bool checks;
  final bool git;
  final bool repository;
  final bool ai;
  final bool provider;
  final bool wallet;
  final bool security;
  final bool digest;

  bool get hasAnyCategoryEnabled =>
      checks ||
      git ||
      repository ||
      ai ||
      provider ||
      wallet ||
      security ||
      digest;

  ForgeNotificationPreferences copyWith({
    bool? enabled,
    bool? checks,
    bool? git,
    bool? repository,
    bool? ai,
    bool? provider,
    bool? wallet,
    bool? security,
    bool? digest,
  }) {
    return ForgeNotificationPreferences(
      enabled: enabled ?? this.enabled,
      checks: checks ?? this.checks,
      git: git ?? this.git,
      repository: repository ?? this.repository,
      ai: ai ?? this.ai,
      provider: provider ?? this.provider,
      wallet: wallet ?? this.wallet,
      security: security ?? this.security,
      digest: digest ?? this.digest,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'checks': checks,
      'git': git,
      'repository': repository,
      'ai': ai,
      'provider': provider,
      'wallet': wallet,
      'security': security,
      'digest': digest,
    };
  }

  static ForgeNotificationPreferences fromMap(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    return ForgeNotificationPreferences(
      enabled: source['enabled'] as bool? ?? true,
      checks: source['checks'] as bool? ?? true,
      git: source['git'] as bool? ?? true,
      repository: source['repository'] as bool? ?? true,
      ai: source['ai'] as bool? ?? true,
      provider: source['provider'] as bool? ?? true,
      wallet: source['wallet'] as bool? ?? true,
      security: source['security'] as bool? ?? true,
      digest: source['digest'] as bool? ?? true,
    );
  }

  static const ForgeNotificationPreferences defaults =
      ForgeNotificationPreferences();
}

class ForgePushRoute {
  const ForgePushRoute({
    required this.destination,
    this.type,
    this.repoId,
    this.threadId,
    this.changeRequestId,
    this.title,
    this.body,
  });

  final ForgeNotificationDestination destination;
  final String? type;
  final String? repoId;
  final String? threadId;
  final String? changeRequestId;
  final String? title;
  final String? body;
}

class ForgeRepository {
  const ForgeRepository({
    required this.id,
    required this.name,
    required this.owner,
    required this.provider,
    required this.language,
    required this.description,
    required this.defaultBranch,
    required this.status,
    required this.openPullRequests,
    required this.openMergeRequests,
    required this.changedFiles,
    required this.lastSynced,
    required this.stars,
    required this.isProtected,
    this.branches = const [],
    this.htmlUrl,
  });

  final String id;
  final String name;
  final String owner;
  final ForgeProvider provider;
  final String language;
  final String description;
  final String defaultBranch;
  final String status;
  final int openPullRequests;
  final int openMergeRequests;
  final int changedFiles;
  final Duration lastSynced;
  final int stars;
  final bool isProtected;

  /// Branches from last sync (empty until repo is synced).
  final List<String> branches;
  final String? htmlUrl;

  String get providerLabel => 'GitHub';
  String get repoLabel => '$owner/$name';
  String get canonicalUrl => 'https://github.com/$owner/$name';
  String get shareUrl {
    final candidate = htmlUrl?.trim();
    if (candidate != null && candidate.isNotEmpty) {
      return candidate;
    }
    return canonicalUrl;
  }
}

class ForgeFileNode {
  const ForgeFileNode({
    required this.name,
    required this.path,
    required this.language,
    required this.sizeLabel,
    required this.changeLabel,
    this.children = const [],
    this.isFolder = false,
    this.isSelected = false,
  });

  final String name;
  final String path;
  final String language;
  final String sizeLabel;
  final String changeLabel;
  final List<ForgeFileNode> children;
  final bool isFolder;
  final bool isSelected;

  ForgeFileNode copyWith({bool? isSelected, List<ForgeFileNode>? children}) {
    return ForgeFileNode(
      name: name,
      path: path,
      language: language,
      sizeLabel: sizeLabel,
      changeLabel: changeLabel,
      children: children ?? this.children,
      isFolder: isFolder,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class ForgeActivityEntry {
  const ForgeActivityEntry({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String timestamp;
  final IconData icon;
  final Color accent;
}

class ForgeRepoWorkflow {
  const ForgeRepoWorkflow({
    required this.id,
    required this.name,
    required this.path,
  });

  final Object id;
  final String name;
  final String path;
}

class ForgeCheckRun {
  const ForgeCheckRun({
    this.id,
    required this.name,
    required this.status,
    required this.summary,
    required this.duration,
    required this.logsAvailable,
    required this.progress,
    this.logsUrl,
    this.source,
    this.executionState,
    this.agentTaskId,
    this.workflowCategory,
    this.ref,
    this.logs = const <String>[],
    this.findings = const <String>[],
  });

  final String? id;
  final String name;
  final ForgeCheckStatus status;
  final String summary;
  final String duration;
  final bool logsAvailable;
  final double progress;
  final String? logsUrl;
  final String? source;
  final String? executionState;
  final String? agentTaskId;
  final String? workflowCategory;
  final String? ref;
  final List<String> logs;
  final List<String> findings;
}

class ForgeTokenWallet {
  const ForgeTokenWallet({
    required this.planName,
    required this.balance,
    required this.monthlyAllowance,
    required this.spentThisWeek,
    required this.nextReset,
    required this.currencySymbol,
  });

  final String planName;
  final double balance;
  final double monthlyAllowance;
  final double spentThisWeek;
  final String nextReset;
  final String currencySymbol;
}

class ForgeConnection {
  const ForgeConnection({
    required this.provider,
    required this.account,
    required this.scopeSummary,
    required this.status,
    required this.lastChecked,
  });

  final ForgeProvider provider;
  final String account;
  final String scopeSummary;
  final ForgeConnectionStatus status;
  final String lastChecked;

  String get providerLabel => 'GitHub';
}

class ForgeTokenLog {
  const ForgeTokenLog({
    required this.action,
    required this.cost,
    required this.repo,
    required this.timestamp,
  });

  final String action;
  final String cost;
  final String repo;
  final String timestamp;
}

class ForgeMockData {
  static const repositories = <ForgeRepository>[
    ForgeRepository(
      id: 'repo-mobile-app',
      name: 'mobile-app',
      owner: 'forgeai',
      provider: ForgeProvider.github,
      language: 'Flutter',
      description:
          'Production mobile app with Firebase auth and AI-assisted code review.',
      defaultBranch: 'main',
      status: 'Healthy',
      openPullRequests: 4,
      openMergeRequests: 0,
      changedFiles: 12,
      lastSynced: Duration(minutes: 7),
      stars: 128,
      isProtected: true,
      htmlUrl: 'https://github.com/forgeai/mobile-app',
    ),
    ForgeRepository(
      id: 'repo-docs',
      name: 'docs',
      owner: 'forgeai',
      provider: ForgeProvider.github,
      language: 'Markdown',
      description:
          'Product, setup, and release documentation with review notes.',
      defaultBranch: 'main',
      status: 'Synced',
      openPullRequests: 2,
      openMergeRequests: 0,
      changedFiles: 5,
      lastSynced: Duration(hours: 2),
      stars: 22,
      isProtected: true,
      htmlUrl: 'https://github.com/forgeai/docs',
    ),
  ];

  static const connections = <ForgeConnection>[
    ForgeConnection(
      provider: ForgeProvider.github,
      account: '@forgeai',
      scopeSummary: 'Repos, pull requests, checks, and webhooks',
      status: ForgeConnectionStatus.connected,
      lastChecked: '2 minutes ago',
    ),
  ];

  static const activities = <ForgeActivityEntry>[
    ForgeActivityEntry(
      title: 'AI change approved',
      subtitle: 'Updated checkout flow with safer error handling.',
      timestamp: '8 min ago',
      icon: Icons.verified_rounded,
      accent: Color(0xFF3B8178),
    ),
    ForgeActivityEntry(
      title: 'Pull request opened',
      subtitle: 'feat/mobile-shell on forgeai/mobile-app.',
      timestamp: '42 min ago',
      icon: Icons.call_split_rounded,
      accent: Color(0xFFC88A2D),
    ),
    ForgeActivityEntry(
      title: 'Checks completed',
      subtitle: 'Tests and lint passed on platform-api.',
      timestamp: '1 hr ago',
      icon: Icons.check_circle_rounded,
      accent: Color(0xFF5E6BD6),
    ),
  ];

  static const checks = <ForgeCheckRun>[
    ForgeCheckRun(
      name: 'Flutter tests',
      status: ForgeCheckStatus.passed,
      summary: '124 tests passed across 8 suites.',
      duration: '2m 14s',
      logsAvailable: true,
      progress: 1,
    ),
    ForgeCheckRun(
      name: 'Lint',
      status: ForgeCheckStatus.running,
      summary: 'Checking static analysis and formatting.',
      duration: 'Running',
      logsAvailable: true,
      progress: 0.62,
    ),
    ForgeCheckRun(
      name: 'Build',
      status: ForgeCheckStatus.queued,
      summary: 'Waiting for the current check queue.',
      duration: 'Queued',
      logsAvailable: false,
      progress: 0.12,
    ),
  ];

  static const wallet = ForgeTokenWallet(
    planName: 'Pro mobile review',
    balance: 1280,
    monthlyAllowance: 2000,
    spentThisWeek: 480,
    nextReset: 'Mon, 09:00',
    currencySymbol: 'tokens',
  );

  static const tokenLogs = <ForgeTokenLog>[
    ForgeTokenLog(
      action: 'AI refactor preview',
      cost: '48',
      repo: 'forgeai/mobile-app',
      timestamp: 'Today, 10:42',
    ),
    ForgeTokenLog(
      action: 'Diff explanation',
      cost: '12',
      repo: 'forgeai/docs',
      timestamp: 'Today, 09:18',
    ),
    ForgeTokenLog(
      action: 'Checks summary',
      cost: '8',
      repo: 'forgeai/platform-api',
      timestamp: 'Yesterday',
    ),
  ];

  static const files = <ForgeFileNode>[
    ForgeFileNode(
      name: 'lib',
      path: 'lib/',
      language: 'Folder',
      sizeLabel: '18 files',
      changeLabel: '+4 -2',
      isFolder: true,
      children: [
        ForgeFileNode(
          name: 'main.dart',
          path: 'lib/main.dart',
          language: 'Dart',
          sizeLabel: '3.8 KB',
          changeLabel: '+16 -4',
          isSelected: true,
        ),
        ForgeFileNode(
          name: 'dashboard_screen.dart',
          path: 'lib/src/features/dashboard/dashboard_screen.dart',
          language: 'Dart',
          sizeLabel: '9.1 KB',
          changeLabel: '+52 -8',
        ),
      ],
    ),
    ForgeFileNode(
      name: 'pubspec.yaml',
      path: 'pubspec.yaml',
      language: 'YAML',
      sizeLabel: '2.1 KB',
      changeLabel: '+3 -1',
    ),
    ForgeFileNode(
      name: 'README.md',
      path: 'README.md',
      language: 'Markdown',
      sizeLabel: '12 KB',
      changeLabel: '+8 -0',
    ),
  ];
}
