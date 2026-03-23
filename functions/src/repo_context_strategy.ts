import type { RepoIndexEntry, RankedRepoIndexEntry } from './repo_index_service';
import {
  buildRepoContextBudget,
  type RepoExecutionRunMemory,
} from './repo_knowledge_map';

export interface RepoContextExpansionPlan {
  additionalPaths: string[];
  directoryPrefixes: string[];
  promotePaths: string[];
  readOnlyPaths: string[];
  focus: string[];
  focusModules: string[];
  architectureFindings: string[];
  uncertainties: string[];
  done: boolean;
  rationale: string;
}

export interface RepoDirectorySummary {
  path: string;
  fileCount: number;
  languages: string[];
  keyFiles: string[];
}

export interface RepoContextManifest {
  totalFiles: number;
  indexedFiles: number;
  truncated: boolean;
  approxTokens: number;
  sizeClass: string;
  contextStrategy: string;
  wholeRepoEligible: boolean;
  wholeRepoReason: string;
  keyFiles: string[];
  topDirectories: RepoDirectorySummary[];
  languageBreakdown: Array<{ language: string; count: number }>;
  tree: string;
  overview: string;
}

const GENERATED_SEGMENTS = [
  '/.dart_tool/',
  '/build/',
  '/dist/',
  '/coverage/',
  '/Pods/',
  '/DerivedData/',
  '/node_modules/',
  '/ios/build/',
  '/android/build/',
];

function truncate(value: string, maxChars: number) {
  if (value.length <= maxChars) {
    return value;
  }
  return `${value.slice(0, maxChars - 1)}...`;
}

function dedupe(values: string[], limit: number) {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of values) {
    const value = raw.trim();
    if (!value) {
      continue;
    }
    const key = value.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(value);
    if (out.length >= limit) {
      break;
    }
  }
  return out;
}

function normalizeRepoPath(raw: string) {
  return raw.trim().replace(/\\/g, '/').replace(/^\/+/u, '');
}

function normalizeDirectoryPrefix(raw: string) {
  const normalized = normalizeRepoPath(raw).replace(/\/+$/u, '');
  return normalized;
}

function directoryOf(path: string) {
  const normalized = normalizeRepoPath(path);
  const parts = normalized.split('/').filter(Boolean);
  if (parts.length <= 1) {
    return '';
  }
  return parts.slice(0, -1).join('/');
}

function fileNameOf(path: string) {
  const normalized = normalizeRepoPath(path);
  const parts = normalized.split('/').filter(Boolean);
  return parts.length === 0 ? normalized : parts[parts.length - 1];
}

function isGeneratedPath(path: string) {
  const normalized = `/${normalizeRepoPath(path)}`;
  return GENERATED_SEGMENTS.some(segment => normalized.includes(segment));
}

function isProbablyRepoShapingFile(path: string) {
  const normalized = normalizeRepoPath(path).toLowerCase();
  return (
    normalized === 'readme.md' ||
    normalized === 'package.json' ||
    normalized === 'package-lock.json' ||
    normalized === 'pubspec.yaml' ||
    normalized === 'firebase.json' ||
    normalized === 'firestore.rules' ||
    normalized === 'analysis_options.yaml' ||
    normalized === 'functions/package.json' ||
    normalized === 'functions/tsconfig.json' ||
    normalized === 'functions/src/index.ts' ||
    normalized === 'lib/main.dart' ||
    normalized === 'lib/src/app.dart' ||
    normalized.startsWith('.github/workflows/') ||
    normalized.startsWith('docs/')
  );
}

function topLevelDirectory(path: string) {
  const normalized = normalizeRepoPath(path);
  const parts = normalized.split('/').filter(Boolean);
  return parts.length > 1 ? parts[0] : '(root)';
}

function importanceScore(path: string) {
  const normalized = normalizeRepoPath(path).toLowerCase();
  let score = 0;
  if (
    normalized === 'readme.md' ||
    normalized === 'pubspec.yaml' ||
    normalized === 'package.json' ||
    normalized === 'firebase.json' ||
    normalized === 'firestore.rules' ||
    normalized === 'analysis_options.yaml'
  ) {
    score += 30;
  }
  if (normalized.endsWith('/main.dart') || normalized.endsWith('/main.ts')) {
    score += 18;
  }
  if (normalized.includes('/app.') || normalized.endsWith('/app.dart') || normalized.endsWith('/app.ts')) {
    score += 14;
  }
  if (normalized.includes('/shell/') || normalized.includes('/routes/') || normalized.includes('/navigation/')) {
    score += 10;
  }
  if (normalized.includes('/feature') || normalized.includes('/features/')) {
    score += 8;
  }
  if (normalized.includes('/service') || normalized.includes('/repository') || normalized.includes('/controller')) {
    score += 6;
  }
  if (normalized.endsWith('.md')) {
    score += 2;
  }
  return score;
}

function summarizeLanguages(entries: RepoIndexEntry[]) {
  const counts = new Map<string, number>();
  for (const entry of entries) {
    const key = entry.language.trim() || 'Text';
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 10)
    .map(([language, count]) => `${language}:${count}`)
    .join(', ');
}

function summarizeDirectories(entries: RepoIndexEntry[]) {
  const counts = new Map<string, number>();
  for (const entry of entries) {
    const key = topLevelDirectory(entry.path);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 14)
    .map(([directory, count]) => `${directory}:${count}`)
    .join(', ');
}

function buildImportantFileList(entries: RepoIndexEntry[]) {
  return [...entries]
    .sort((a, b) => importanceScore(b.path) - importanceScore(a.path) || a.path.localeCompare(b.path))
    .filter(entry => importanceScore(entry.path) > 0)
    .slice(0, 18)
    .map(entry => entry.path);
}

function buildTree(entries: RepoIndexEntry[], maxLines: number) {
  return entries
    .map(entry => entry.path)
    .sort((a, b) => a.localeCompare(b))
    .slice(0, maxLines)
    .join('\n');
}

export function pickGlobalContextPaths(entries: RepoIndexEntry[], limit: number) {
  const filtered = entries.filter(entry => !isGeneratedPath(entry.path));
  const important = filtered
    .filter(entry => isProbablyRepoShapingFile(entry.path))
    .sort((a, b) => a.path.localeCompare(b.path))
    .map(entry => entry.path);
  const rootConfigs = filtered
    .filter(entry => !entry.directory && !important.includes(entry.path))
    .sort((a, b) => a.path.localeCompare(b.path))
    .map(entry => entry.path);
  const applicationRoots = filtered
    .filter(
      entry =>
        !important.includes(entry.path) &&
        !rootConfigs.includes(entry.path) &&
        (entry.path.startsWith('lib/src/') ||
          entry.path.startsWith('lib/') ||
          entry.path.startsWith('functions/src/')),
    )
    .sort((a, b) => a.path.localeCompare(b.path))
    .map(entry => entry.path);
  return dedupe([...important, ...rootConfigs, ...applicationRoots], limit);
}

export function expandRepoContextPaths(params: {
  entries: RepoIndexEntry[];
  seedPaths: string[];
  currentFilePath?: string | null;
  maxAdditional: number;
}) {
  const filtered = params.entries.filter(entry => !isGeneratedPath(entry.path));
  const seedSet = new Set(params.seedPaths.map(value => normalizeRepoPath(value).toLowerCase()));
  const seedDirectories = params.seedPaths
    .map(directoryOf)
    .filter(Boolean)
    .map(value => value.toLowerCase());
  const seedFileNames = params.seedPaths
    .map(fileNameOf)
    .map(value => value.toLowerCase());
  const currentDirectory = params.currentFilePath ? directoryOf(params.currentFilePath).toLowerCase() : '';

  const scored = filtered
    .filter(entry => !seedSet.has(entry.path.toLowerCase()))
    .map(entry => {
      let score = 0;
      const directory = entry.directory.toLowerCase();
      if (currentDirectory && directory === currentDirectory) {
        score += 16;
      }
      if (seedDirectories.some(value => value && directory === value)) {
        score += 14;
      }
      if (
        seedDirectories.some(
          value =>
            value &&
            directory &&
            (directory.startsWith(`${value}/`) || value.startsWith(`${directory}/`)),
        )
      ) {
        score += 8;
      }
      if (
        entry.imports.some(
          value =>
            seedFileNames.some(name => value.toLowerCase().includes(name)) ||
            params.seedPaths.some(path => value.toLowerCase().includes(path.toLowerCase())),
        )
      ) {
        score += 12;
      }
      if (
        entry.fileName.toLowerCase().includes('service') ||
        entry.fileName.toLowerCase().includes('repository')
      ) {
        score += 2;
      }
      return { path: entry.path, score };
    })
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));

  return dedupe(scored.map(item => item.path), params.maxAdditional);
}

export function buildRepoContextManifest(params: {
  entries: RepoIndexEntry[];
  deepMode: boolean;
  maxTreeLines?: number;
  wholeRepoFileLimit?: number;
  wholeRepoTokenLimit?: number;
}) {
  const filtered = params.entries.filter(entry => !isGeneratedPath(entry.path));
  const totalFiles = filtered.length;
  const indexedFiles = filtered.filter(entry => entry.hasContent).length;
  const approxTokens = filtered.reduce((sum, entry) => sum + entry.approxTokens, 0);
  const budget = buildRepoContextBudget({
    totalFiles,
    approxTokens,
    deepMode: params.deepMode,
  });
  const wholeRepoFileLimit = params.wholeRepoFileLimit ?? budget.exactEditableBudget;
  const wholeRepoTokenLimit = params.wholeRepoTokenLimit ?? (budget.exactWholeRepoEligible ? (params.deepMode ? 140_000 : 90_000) : 36_000);
  const wholeRepoEligible =
    budget.exactWholeRepoEligible &&
    totalFiles > 0 &&
    totalFiles <= wholeRepoFileLimit &&
    approxTokens <= wholeRepoTokenLimit;
  const wholeRepoReason = wholeRepoEligible
    ? `The repository is small enough to inline most of the codebase (${totalFiles} files, ~${approxTokens} tokens).`
    : `The repository falls into the ${budget.sizeClass} repo class (${totalFiles} files, ~${approxTokens} tokens), so the agent should use the ${budget.strategyLabel} strategy with dynamic file loading and layered summaries.`;

  const languageCounts = new Map<string, number>();
  const directoryMap = new Map<string, { fileCount: number; languages: string[]; keyFiles: string[] }>();
  for (const entry of filtered) {
    languageCounts.set(entry.language, (languageCounts.get(entry.language) ?? 0) + 1);
    const directory = entry.directory || '(root)';
    const record = directoryMap.get(directory) ?? {
      fileCount: 0,
      languages: [],
      keyFiles: [],
    };
    record.fileCount += 1;
    record.languages.push(entry.language);
    if (isProbablyRepoShapingFile(entry.path) || record.keyFiles.length < 2) {
      record.keyFiles.push(entry.path);
    }
    directoryMap.set(directory, record);
  }

  const languageBreakdown = Array.from(languageCounts.entries())
    .map(([language, count]) => ({ language, count }))
    .sort((a, b) => b.count - a.count || a.language.localeCompare(b.language))
    .slice(0, 8);

  const topDirectories = Array.from(directoryMap.entries())
    .map(([path, record]) => ({
      path,
      fileCount: record.fileCount,
      languages: dedupe(record.languages, 4),
      keyFiles: dedupe(record.keyFiles, 3),
    }))
    .sort((a, b) => b.fileCount - a.fileCount || a.path.localeCompare(b.path))
    .slice(0, params.deepMode ? 14 : 8);

  const keyFiles = pickGlobalContextPaths(filtered, params.deepMode ? 14 : 8);
  const maxTreeLines = params.maxTreeLines ?? (params.deepMode ? 720 : 420);
  const tree = buildTree(filtered, maxTreeLines);
  const overview = [
    `Repo size: ${totalFiles} indexed files (${indexedFiles} with cached body text).`,
    languageBreakdown.length > 0
      ? `Primary languages: ${languageBreakdown
          .slice(0, 4)
          .map(item => `${item.language} (${item.count})`)
          .join(', ')}.`
      : 'Primary languages: unknown.',
    keyFiles.length > 0 ? `Key repo-shaping files: ${keyFiles.slice(0, 6).join(', ')}.` : '',
    wholeRepoReason,
  ]
    .filter(Boolean)
    .join(' ');

  return {
    totalFiles,
    indexedFiles,
    truncated: totalFiles > maxTreeLines,
    approxTokens,
    sizeClass: budget.sizeClass,
    contextStrategy: budget.strategyLabel,
    wholeRepoEligible,
    wholeRepoReason,
    keyFiles,
    topDirectories,
    languageBreakdown,
    tree,
    overview,
  } satisfies RepoContextManifest;
}

export function formatRepoContextManifest(manifest: RepoContextManifest) {
  const directories = manifest.topDirectories
    .map(
      item =>
        `${item.path}: ${item.fileCount} files (${item.languages.join(', ') || 'unknown'}) [${item.keyFiles.join(', ')}]`,
    )
    .join('\n');
  return [
    manifest.overview,
    '',
    `Repo size class: ${manifest.sizeClass}.`,
    `Context strategy: ${manifest.contextStrategy}.`,
    `Whole repo inline eligible: ${manifest.wholeRepoEligible ? 'yes' : 'no'}.`,
    `Whole repo strategy: ${manifest.wholeRepoReason}`,
    manifest.keyFiles.length > 0 ? `Key files: ${manifest.keyFiles.join(', ')}` : 'Key files: (none)',
    manifest.languageBreakdown.length > 0
      ? `Languages: ${manifest.languageBreakdown.map(item => `${item.language}:${item.count}`).join(', ')}`
      : 'Languages: (none)',
    directories ? `Top directories:\n${directories}` : 'Top directories: (none)',
  ].join('\n');
}

export function buildRepoGlobalOverview(params: {
  entries: RepoIndexEntry[];
  ranked: RankedRepoIndexEntry[];
  prompt: string;
  currentFilePath?: string | null;
  deepMode: boolean;
  selectedPaths?: string[];
  inspectedPaths?: string[];
}) {
  const importantFiles = buildImportantFileList(params.entries);
  const rankedSummary = params.ranked
    .slice(0, params.deepMode ? 48 : 24)
    .map(
      entry =>
        `- ${entry.path} (score=${entry.score}; reasons=${entry.reasons.join(', ') || 'none'}) :: ${entry.summary}`,
    )
    .join('\n');

  return truncate(
    [
      `PROMPT: ${params.prompt}`,
      `MODE: ${params.deepMode ? 'deep' : 'normal'}`,
      params.currentFilePath ? `CURRENT_FILE: ${params.currentFilePath}` : 'CURRENT_FILE: (none)',
      `TOTAL_FILES: ${params.entries.length}`,
      `LANGUAGES: ${summarizeLanguages(params.entries) || '(none)'}`,
      `TOP_LEVEL_DIRECTORIES: ${summarizeDirectories(params.entries) || '(none)'}`,
      `ALREADY_SELECTED: ${dedupe(params.selectedPaths ?? [], 40).join(', ') || '(none)'}`,
      `ALREADY_INSPECTED: ${dedupe(params.inspectedPaths ?? [], 60).join(', ') || '(none)'}`,
      `IMPORTANT_FILES: ${importantFiles.join(', ') || '(none)'}`,
      'HIGH_SIGNAL_CANDIDATES:',
      rankedSummary || '(none)',
    ].join('\n'),
    28_000,
  );
}

export function buildRepoContextPlannerSystemPrompt() {
  return [
    'You are planning repository exploration for a coding agent.',
    'You are not editing files yet.',
    'Return only valid JSON with keys additionalPaths, directoryPrefixes, promotePaths, readOnlyPaths, focus, focusModules, architectureFindings, uncertainties, done, rationale.',
    'Rules:',
    '- Prefer exact repo-relative paths from the candidate list when possible.',
    '- Use directoryPrefixes only when you need a broader neighborhood, such as lib/src/features/auth.',
    '- promotePaths should contain the files that must stay in the final editable context.',
    '- readOnlyPaths should contain files that should be hydrated for architecture context only.',
    '- focusModules should contain module IDs already present in the repo knowledge map.',
    '- Use architecture zones, module relationships, and dependencies to widen context when the request crosses subsystem boundaries.',
    '- architectureFindings should record short conclusions about repo structure that the run should remember.',
    '- uncertainties should record what still needs more repo inspection.',
    '- Keep the result compact and high-signal.',
    '- Return no markdown fences and no prose outside the JSON object.',
  ].join('\n');
}

export function buildRepoContextPlannerUserPrompt(params: {
  prompt: string;
  repoOverview: string;
  repoStructure: string;
  architectureOverview?: string;
  architectureZoneOverview?: string;
  moduleOverview?: string;
  moduleIndex?: string;
  focusedModuleDetails?: string;
  currentFilePath?: string | null;
  selectedPaths: string[];
  inspectedPaths: string[];
  candidateEntries: RankedRepoIndexEntry[];
  runMemory?: RepoExecutionRunMemory | null;
  deepMode: boolean;
}) {
  const candidates = params.candidateEntries
    .slice(0, params.deepMode ? 96 : 48)
    .map(
      entry =>
        `PATH: ${entry.path}\nSCORE: ${entry.score}\nREASONS: ${entry.reasons.join(', ') || 'none'}\nSUMMARY: ${entry.summary}`,
    )
    .join('\n\n');

  return [
    `USER_REQUEST:\n${params.prompt}`,
    '',
    params.currentFilePath ? `CURRENT_FILE: ${params.currentFilePath}` : 'CURRENT_FILE: (none)',
    `MODE: ${params.deepMode ? 'deep' : 'normal'}`,
    '',
    'REPOSITORY_OVERVIEW:',
    params.repoOverview,
    '',
    'REPOSITORY_STRUCTURE:',
    params.repoStructure || '(none)',
    '',
    'ARCHITECTURE_OVERVIEW:',
    params.architectureOverview || '(none)',
    '',
    'ARCHITECTURE_ZONES:',
    params.architectureZoneOverview || '(none)',
    '',
    'MODULE_OVERVIEW:',
    params.moduleOverview || '(none)',
    '',
    'MODULE_INDEX:',
    params.moduleIndex || '(none)',
    '',
    'FOCUSED_MODULE_DETAILS:',
    params.focusedModuleDetails || '(none)',
    '',
    `CURRENT_SELECTION: ${params.selectedPaths.join(', ') || '(none)'}`,
    `CURRENT_INSPECTION_SET: ${params.inspectedPaths.join(', ') || '(none)'}`,
    '',
    'RUN_MEMORY:',
    params.runMemory
      ? [
          `FOCUSED_MODULES: ${params.runMemory.focusedModules.join(', ') || '(none)'}`,
          `EDITABLE_PATHS: ${params.runMemory.editablePaths.join(', ') || '(none)'}`,
          `READ_ONLY_PATHS: ${params.runMemory.readOnlyPaths.join(', ') || '(none)'}`,
          `ARCHITECTURE_CONCLUSIONS: ${params.runMemory.architectureConclusions.join(' | ') || '(none)'}`,
          `UNRESOLVED_QUESTIONS: ${params.runMemory.unresolvedQuestions.join(' | ') || '(none)'}`,
        ].join('\n')
      : '(none)',
    '',
    'CANDIDATE_FILES:',
    candidates || '(none)',
    '',
    `Pick at most ${params.deepMode ? 28 : 16} additional paths and at most ${params.deepMode ? 8 : 4} directory prefixes.`,
    'If the current context is already sufficient, set done=true and leave additionalPaths empty.',
    ].join('\n');
}

function parseJsonObject(responseText: string) {
  const trimmed = responseText.trim();
  if (!trimmed) {
    return null;
  }
  try {
    return JSON.parse(trimmed) as Record<string, unknown>;
  } catch {
    const match = trimmed.match(/\{[\s\S]*\}/);
    if (!match) {
      return null;
    }
    try {
      return JSON.parse(match[0]) as Record<string, unknown>;
    } catch {
      return null;
    }
  }
}

export function parseRepoContextExpansionPlan(responseText: string): RepoContextExpansionPlan {
  const parsed = parseJsonObject(responseText);
  if (!parsed) {
    return {
      additionalPaths: [],
      directoryPrefixes: [],
      promotePaths: [],
      readOnlyPaths: [],
      focus: [],
      focusModules: [],
      architectureFindings: [],
      uncertainties: [],
      done: false,
      rationale: 'Planner response was not valid JSON.',
    };
  }
  const additionalPaths = Array.isArray(parsed.additionalPaths)
    ? parsed.additionalPaths
        .filter((value): value is string => typeof value === 'string')
        .map(value => normalizeRepoPath(value))
        .filter(value => value.length > 0 && !value.includes('..'))
    : [];
  const directoryPrefixes = Array.isArray(parsed.directoryPrefixes)
    ? parsed.directoryPrefixes
        .filter((value): value is string => typeof value === 'string')
        .map(value => normalizeDirectoryPrefix(value))
        .filter(value => value.length > 0 && !value.includes('..'))
    : [];
  const promotePaths = Array.isArray(parsed.promotePaths)
    ? parsed.promotePaths
        .filter((value): value is string => typeof value === 'string')
        .map(value => normalizeRepoPath(value))
        .filter(value => value.length > 0 && !value.includes('..'))
    : [];
  const readOnlyPaths = Array.isArray(parsed.readOnlyPaths)
    ? parsed.readOnlyPaths
        .filter((value): value is string => typeof value === 'string')
        .map(value => normalizeRepoPath(value))
        .filter(value => value.length > 0 && !value.includes('..'))
    : [];
  const focus = Array.isArray(parsed.focus)
    ? parsed.focus.filter((value): value is string => typeof value === 'string').map(value => value.trim())
    : [];
  const focusModules = Array.isArray(parsed.focusModules)
    ? parsed.focusModules
        .filter((value): value is string => typeof value === 'string')
        .map(value => value.trim())
    : [];
  const architectureFindings = Array.isArray(parsed.architectureFindings)
    ? parsed.architectureFindings
        .filter((value): value is string => typeof value === 'string')
        .map(value => truncate(value.trim(), 220))
    : [];
  const uncertainties = Array.isArray(parsed.uncertainties)
    ? parsed.uncertainties
        .filter((value): value is string => typeof value === 'string')
        .map(value => truncate(value.trim(), 220))
    : [];
  return {
    additionalPaths: dedupe(additionalPaths, 24),
    directoryPrefixes: dedupe(directoryPrefixes, 12),
    promotePaths: dedupe(promotePaths, 24),
    readOnlyPaths: dedupe(readOnlyPaths, 24),
    focus: dedupe(focus, 8),
    focusModules: dedupe(focusModules, 12),
    architectureFindings: dedupe(architectureFindings, 12),
    uncertainties: dedupe(uncertainties, 12),
    done: parsed.done === true,
    rationale: typeof parsed.rationale === 'string' ? truncate(parsed.rationale.trim(), 400) : '',
  };
}
