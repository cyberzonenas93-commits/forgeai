import { posix as pathPosix } from 'node:path';

import type { RepoIndexEntry } from './repo_index_service';

export type RepoSizeClass = 'tiny' | 'small' | 'medium' | 'large' | 'huge';

export interface RepoContextBudget {
  sizeClass: RepoSizeClass;
  strategyLabel: string;
  exactWholeRepoEligible: boolean;
  initialModuleSeedLimit: number;
  keyFilesPerModule: number;
  explorationPasses: number;
  explorationBudgetPerPass: number;
  exactEditableBudget: number;
  exactReadOnlyBudget: number;
  plannerCandidateLimit: number;
}

export interface RepoModuleSummary {
  id: string;
  label: string;
  pathPrefix: string;
  fileCount: number;
  approxTokens: number;
  languages: string[];
  keyFiles: string[];
  entryFiles: string[];
  roles: string[];
  imports: string[];
  exports: string[];
  symbols: string[];
  dependencies: string[];
  dependents: string[];
  summary: string;
}

export interface RepoArchitectureZone {
  id: string;
  label: string;
  pathPrefixes: string[];
  keyFiles: string[];
  moduleIds: string[];
  summary: string;
}

export interface RepoKnowledgeMap {
  sizeClass: RepoSizeClass;
  budget: RepoContextBudget;
  totalFiles: number;
  approxTokens: number;
  keyFiles: string[];
  entryPoints: string[];
  topSymbols: string[];
  modules: RepoModuleSummary[];
  architectureZones: RepoArchitectureZone[];
  dependencyGraph: Record<string, string[]>;
  reverseDependencyGraph: Record<string, string[]>;
  pathToModule: Record<string, string>;
  moduleDependencies: Record<string, string[]>;
  repoOverview: string;
  architectureOverview: string;
  architectureZoneOverview: string;
  moduleOverview: string;
  moduleIndex: string;
  summaryLines: string[];
}

export interface RepoExecutionMemoryPass {
  passNumber: number;
  focusModules: string[];
  requestedPaths: string[];
  hydratedPaths: string[];
  promotedPaths: string[];
  readOnlyPaths: string[];
  conclusions: string[];
  uncertainties: string[];
  rationale: string;
  done: boolean;
}

export interface RepoExecutionRunMemory {
  sizeClass: RepoSizeClass;
  contextStrategy: string;
  repoOverview: string;
  architectureOverview: string;
  moduleOverview: string;
  focusedModules: string[];
  exploredPaths: string[];
  hydratedPaths: string[];
  editablePaths: string[];
  readOnlyPaths: string[];
  globalContextPaths: string[];
  architectureConclusions: string[];
  unresolvedQuestions: string[];
  moduleSummaries: Array<{
    id: string;
    summary: string;
    keyFiles: string[];
    dependencies: string[];
    dependents: string[];
  }>;
  passes: RepoExecutionMemoryPass[];
}

const RUN_MEMORY_FOCUSED_MODULE_LIMIT = 48;
const RUN_MEMORY_PATH_LIMIT = 960;
const RUN_MEMORY_EDITABLE_LIMIT = 220;
const RUN_MEMORY_READ_ONLY_LIMIT = 280;
const RUN_MEMORY_GLOBAL_CONTEXT_LIMIT = 160;
const RUN_MEMORY_CONCLUSION_LIMIT = 32;
const RUN_MEMORY_MODULE_SUMMARY_LIMIT = 48;
const RUN_MEMORY_PASS_LIMIT = 12;

function truncate(value: string, maxChars: number) {
  if (value.length <= maxChars) {
    return value;
  }
  return `${value.slice(0, maxChars - 1)}...`;
}

function dedupe(values: Array<string | null | undefined>, limit: number) {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of values) {
    if (typeof raw !== 'string') {
      continue;
    }
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

function tokenize(value: string) {
  return value
    .toLowerCase()
    .split(/[^a-z0-9_./-]+/)
    .map(part => part.trim())
    .filter(part => part.length >= 3);
}

function normalizeRepoPath(raw: string) {
  return raw.trim().replace(/\\/g, '/').replace(/^\/+/u, '');
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

function extensionOf(path: string) {
  const fileName = fileNameOf(path);
  const dotIndex = fileName.lastIndexOf('.');
  return dotIndex >= 0 ? fileName.slice(dotIndex + 1).toLowerCase() : '';
}

function importanceScore(entry: RepoIndexEntry) {
  const path = entry.path.toLowerCase();
  let score = 0;
  if (entry.isEntrypoint) {
    score += 24;
  }
  if (path === 'readme.md' || path === 'pubspec.yaml' || path === 'package.json') {
    score += 20;
  }
  if (path.includes('/main.') || path.endsWith('/app.dart') || path.endsWith('/app.ts')) {
    score += 18;
  }
  if (entry.architectureHints.includes('auth')) {
    score += 8;
  }
  if (entry.architectureHints.includes('backend')) {
    score += 8;
  }
  if (entry.architectureHints.includes('navigation')) {
    score += 8;
  }
  if (entry.role.includes('screen') || entry.role.includes('widget')) {
    score += 4;
  }
  if (entry.role.includes('service') || entry.role.includes('repository')) {
    score += 4;
  }
  return score;
}

function zoneIdForPath(path: string) {
  const normalized = normalizeRepoPath(path);
  if (normalized.startsWith('lib/src/features/')) {
    return 'feature_modules';
  }
  if (normalized.startsWith('lib/src/core/')) {
    return 'app_core';
  }
  if (normalized.startsWith('lib/src/shared/')) {
    return 'shared_ui';
  }
  if (normalized.startsWith('functions/src/')) {
    return 'backend_functions';
  }
  if (normalized.startsWith('test/')) {
    return 'tests';
  }
  if (normalized.startsWith('.github/workflows/')) {
    return 'automation';
  }
  if (normalized.startsWith('docs/') || normalized.endsWith('.md')) {
    return 'documentation';
  }
  if (normalized.startsWith('ios/') || normalized.startsWith('android/')) {
    return 'platform_native';
  }
  return 'repo_root';
}

function zoneLabel(zoneId: string) {
  return (
    {
      feature_modules: 'Feature modules',
      app_core: 'App core',
      shared_ui: 'Shared UI',
      backend_functions: 'Backend functions',
      tests: 'Tests',
      automation: 'Automation',
      documentation: 'Documentation',
      platform_native: 'Platform native',
      repo_root: 'Repo root',
    } as Record<string, string>
  )[zoneId] ?? zoneId;
}

function moduleIdForPath(path: string) {
  const normalized = normalizeRepoPath(path);
  const parts = normalized.split('/').filter(Boolean);
  if (parts.length === 0) {
    return '(root)';
  }
  if (normalized.startsWith('lib/src/features/') && parts.length >= 4) {
    return parts.slice(0, 4).join('/');
  }
  if (normalized.startsWith('lib/src/core/') && parts.length >= 4) {
    return parts.slice(0, 4).join('/');
  }
  if (normalized.startsWith('lib/src/shared/') && parts.length >= 3) {
    return parts.slice(0, 3).join('/');
  }
  if (normalized.startsWith('functions/src/') && parts.length >= 3) {
    return parts.slice(0, 3).join('/');
  }
  if (parts.length >= 3) {
    return parts.slice(0, 3).join('/');
  }
  if (parts.length >= 2) {
    return parts.slice(0, 2).join('/');
  }
  return parts[0];
}

function moduleLabel(moduleId: string) {
  return moduleId.replace(/\//g, ' / ');
}

function classifRepoSize(totalFiles: number, approxTokens: number) {
  if (totalFiles <= 24 && approxTokens <= 36_000) {
    return 'tiny' as const;
  }
  if (totalFiles <= 90 && approxTokens <= 140_000) {
    return 'small' as const;
  }
  if (totalFiles <= 260 && approxTokens <= 420_000) {
    return 'medium' as const;
  }
  if (totalFiles <= 1_200 && approxTokens <= 1_800_000) {
    return 'large' as const;
  }
  return 'huge' as const;
}

export function buildRepoContextBudget(params: {
  totalFiles: number;
  approxTokens: number;
  deepMode: boolean;
}) {
  const sizeClass = classifRepoSize(params.totalFiles, params.approxTokens);
  switch (sizeClass) {
    case 'tiny':
      return {
        sizeClass,
        strategyLabel: 'whole_repo_inline',
        exactWholeRepoEligible: true,
        initialModuleSeedLimit: 8,
        keyFilesPerModule: 4,
        explorationPasses: 1,
        explorationBudgetPerPass: params.totalFiles,
        exactEditableBudget: params.totalFiles,
        exactReadOnlyBudget: params.totalFiles,
        plannerCandidateLimit: params.totalFiles,
      } satisfies RepoContextBudget;
    case 'small':
      return {
        sizeClass,
        strategyLabel: params.deepMode ? 'wide_repo_inline' : 'hierarchical_small_repo',
        exactWholeRepoEligible: params.deepMode || params.approxTokens <= 90_000,
        initialModuleSeedLimit: params.deepMode ? 18 : 12,
        keyFilesPerModule: params.deepMode ? 5 : 3,
        explorationPasses: params.deepMode ? 4 : 2,
        explorationBudgetPerPass: params.deepMode ? 48 : 24,
        exactEditableBudget: params.deepMode ? 96 : 36,
        exactReadOnlyBudget: params.deepMode ? 96 : 28,
        plannerCandidateLimit: params.deepMode ? 128 : 56,
      } satisfies RepoContextBudget;
    case 'medium':
      return {
        sizeClass,
        strategyLabel: 'hierarchical_progressive',
        exactWholeRepoEligible: false,
        initialModuleSeedLimit: params.deepMode ? 24 : 14,
        keyFilesPerModule: params.deepMode ? 5 : 3,
        explorationPasses: params.deepMode ? 5 : 3,
        explorationBudgetPerPass: params.deepMode ? 64 : 28,
        exactEditableBudget: params.deepMode ? 88 : 24,
        exactReadOnlyBudget: params.deepMode ? 120 : 36,
        plannerCandidateLimit: params.deepMode ? 180 : 72,
      } satisfies RepoContextBudget;
    case 'large':
      return {
        sizeClass,
        strategyLabel: 'hierarchical_graph_guided',
        exactWholeRepoEligible: false,
        initialModuleSeedLimit: params.deepMode ? 32 : 18,
        keyFilesPerModule: params.deepMode ? 4 : 2,
        explorationPasses: params.deepMode ? 6 : 4,
        explorationBudgetPerPass: params.deepMode ? 72 : 32,
        exactEditableBudget: params.deepMode ? 104 : 28,
        exactReadOnlyBudget: params.deepMode ? 144 : 44,
        plannerCandidateLimit: params.deepMode ? 220 : 84,
      } satisfies RepoContextBudget;
    case 'huge':
    default:
      return {
        sizeClass: 'huge',
        strategyLabel: 'hierarchical_memory_heavy',
        exactWholeRepoEligible: false,
        initialModuleSeedLimit: params.deepMode ? 40 : 20,
        keyFilesPerModule: params.deepMode ? 4 : 2,
        explorationPasses: params.deepMode ? 7 : 4,
        explorationBudgetPerPass: params.deepMode ? 84 : 36,
        exactEditableBudget: params.deepMode ? 120 : 32,
        exactReadOnlyBudget: params.deepMode ? 168 : 48,
        plannerCandidateLimit: params.deepMode ? 280 : 96,
      } satisfies RepoContextBudget;
  }
}

function buildPathLookup(entries: RepoIndexEntry[]) {
  const pathMap = new Map<string, RepoIndexEntry>();
  const suffixMap = new Map<string, string[]>();
  const fileNameMap = new Map<string, string[]>();
  for (const entry of entries) {
    const normalized = normalizeRepoPath(entry.path);
    pathMap.set(normalized.toLowerCase(), entry);
    const suffix = normalized.toLowerCase();
    const existingSuffix = suffixMap.get(suffix) ?? [];
    existingSuffix.push(normalized);
    suffixMap.set(suffix, existingSuffix);
    const fileName = fileNameOf(normalized).toLowerCase();
    const existingFileNames = fileNameMap.get(fileName) ?? [];
    existingFileNames.push(normalized);
    fileNameMap.set(fileName, existingFileNames);
  }
  return { pathMap, suffixMap, fileNameMap };
}

function tryResolvePathCandidate(
  candidate: string,
  pathMap: Map<string, RepoIndexEntry>,
  extensions: string[],
) {
  const normalized = normalizeRepoPath(candidate);
  if (pathMap.has(normalized.toLowerCase())) {
    return normalized;
  }
  if (extensionOf(normalized)) {
    return null;
  }
  for (const extension of extensions) {
    const withExtension = `${normalized}.${extension}`;
    if (pathMap.has(withExtension.toLowerCase())) {
      return withExtension;
    }
  }
  for (const extension of extensions) {
    const nestedIndex = `${normalized}/index.${extension}`;
    if (pathMap.has(nestedIndex.toLowerCase())) {
      return nestedIndex;
    }
  }
  return null;
}

function resolveImportPath(
  fromPath: string,
  rawImport: string,
  pathMap: Map<string, RepoIndexEntry>,
  fileNameMap: Map<string, string[]>,
  extensions: string[],
) {
  const normalizedImport = rawImport.trim();
  if (!normalizedImport) {
    return null;
  }

  if (normalizedImport.startsWith('.')) {
    const resolved = pathPosix.normalize(
      pathPosix.join('/', directoryOf(fromPath), normalizedImport),
    );
    return tryResolvePathCandidate(resolved, pathMap, extensions);
  }

  if (normalizedImport.startsWith('package:')) {
    const withoutPackage = normalizedImport.slice('package:'.length);
    const slashIndex = withoutPackage.indexOf('/');
    const importPath = slashIndex >= 0 ? withoutPackage.slice(slashIndex + 1) : withoutPackage;
    return (
      tryResolvePathCandidate(`lib/${importPath}`, pathMap, extensions) ??
      tryResolvePathCandidate(importPath, pathMap, extensions)
    );
  }

  const direct = tryResolvePathCandidate(normalizedImport, pathMap, extensions);
  if (direct) {
    return direct;
  }

  const bareName = fileNameOf(normalizedImport).toLowerCase();
  const byFileName = fileNameMap.get(bareName) ?? [];
  return byFileName.length === 1 ? byFileName[0] : null;
}

function buildDependencyGraph(entries: RepoIndexEntry[]) {
  const extensions = dedupe(entries.map(entry => extensionOf(entry.path)), 24);
  const { pathMap, fileNameMap } = buildPathLookup(entries);
  const graph = new Map<string, string[]>();
  const reverse = new Map<string, string[]>();
  for (const entry of entries) {
    const targets = dedupe(
      entry.imports
        .map(value => resolveImportPath(entry.path, value, pathMap, fileNameMap, extensions))
        .filter((value): value is string => typeof value === 'string'),
      24,
    );
    graph.set(entry.path, targets);
    for (const target of targets) {
      const existing = reverse.get(target) ?? [];
      existing.push(entry.path);
      reverse.set(target, dedupe(existing, 40));
    }
  }
  return {
    graph: Object.fromEntries(graph.entries()),
    reverse: Object.fromEntries(reverse.entries()),
  };
}

function buildModuleSummaries(entries: RepoIndexEntry[], dependencyGraph: Record<string, string[]>) {
  const pathToModule: Record<string, string> = {};
  const grouped = new Map<string, RepoIndexEntry[]>();
  for (const entry of entries) {
    const moduleId = moduleIdForPath(entry.path);
    pathToModule[entry.path] = moduleId;
    const bucket = grouped.get(moduleId) ?? [];
    bucket.push(entry);
    grouped.set(moduleId, bucket);
  }

  const moduleDependencies = new Map<string, Set<string>>();
  const moduleDependents = new Map<string, Set<string>>();
  for (const [fromPath, targets] of Object.entries(dependencyGraph)) {
    const fromModule = pathToModule[fromPath];
    if (!fromModule) {
      continue;
    }
    for (const target of targets) {
      const toModule = pathToModule[target];
      if (!toModule || toModule === fromModule) {
        continue;
      }
      const dependencies = moduleDependencies.get(fromModule) ?? new Set<string>();
      dependencies.add(toModule);
      moduleDependencies.set(fromModule, dependencies);
      const dependents = moduleDependents.get(toModule) ?? new Set<string>();
      dependents.add(fromModule);
      moduleDependents.set(toModule, dependents);
    }
  }

  const modules = Array.from(grouped.entries())
    .map(([moduleId, files]) => {
      const sortedByImportance = [...files].sort(
        (a, b) => importanceScore(b) - importanceScore(a) || a.path.localeCompare(b.path),
      );
      const keyFiles = dedupe(
        [
          ...sortedByImportance.filter(file => file.isEntrypoint).map(file => file.path),
          ...sortedByImportance.map(file => file.path),
        ],
        6,
      );
      const entryFiles = dedupe(files.filter(file => file.isEntrypoint).map(file => file.path), 4);
      const languages = dedupe(files.map(file => file.language), 4);
      const roles = dedupe(files.map(file => file.role), 4);
      const imports = dedupe(files.flatMap(file => file.imports), 10);
      const exports = dedupe(files.flatMap(file => file.exports), 10);
      const symbols = dedupe(files.flatMap(file => file.symbolHints), 12);
      const dependencies = dedupe(
        [...(moduleDependencies.get(moduleId) ?? new Set<string>())],
        8,
      );
      const dependents = dedupe(
        [...(moduleDependents.get(moduleId) ?? new Set<string>())],
        8,
      );
      const approxTokens = files.reduce((sum, file) => sum + file.approxTokens, 0);
      const summary = truncate(
        [
          `${moduleLabel(moduleId)} contains ${files.length} file${files.length === 1 ? '' : 's'}`,
          languages.length > 0 ? `mostly ${languages.join(', ')}` : '',
          entryFiles.length > 0 ? `with entry files ${entryFiles.join(', ')}` : '',
          dependencies.length > 0 ? `and depends on ${dependencies.join(', ')}` : '',
          symbols.length > 0 ? `while exposing ${symbols.slice(0, 4).join(', ')}` : '',
        ]
          .filter(Boolean)
          .join(' '),
        340,
      );
      return {
        id: moduleId,
        label: moduleLabel(moduleId),
        pathPrefix: moduleId,
        fileCount: files.length,
        approxTokens,
        languages,
        keyFiles,
        entryFiles,
        roles,
        imports,
        exports,
        symbols,
        dependencies,
        dependents,
        summary,
      } satisfies RepoModuleSummary;
    })
    .sort((a, b) => b.fileCount - a.fileCount || a.id.localeCompare(b.id));

  return {
    modules,
    pathToModule,
    moduleDependencies: Object.fromEntries(
      modules.map(module => [module.id, module.dependencies]),
    ),
  };
}

function buildArchitectureZones(modules: RepoModuleSummary[]) {
  const grouped = new Map<string, RepoModuleSummary[]>();
  for (const module of modules) {
    const zoneId = zoneIdForPath(module.pathPrefix);
    const bucket = grouped.get(zoneId) ?? [];
    bucket.push(module);
    grouped.set(zoneId, bucket);
  }

  return Array.from(grouped.entries())
    .map(([zoneId, bucket]) => {
      const keyFiles = dedupe(bucket.flatMap(module => module.keyFiles), 8);
      const pathPrefixes = dedupe(bucket.map(module => module.pathPrefix), 8);
      const moduleIds = bucket.map(module => module.id);
      const summary = truncate(
        `${zoneLabel(zoneId)} contains ${bucket.length} module${bucket.length === 1 ? '' : 's'}: ${moduleIds
          .slice(0, 5)
          .join(', ')}.`,
        280,
      );
      return {
        id: zoneId,
        label: zoneLabel(zoneId),
        pathPrefixes,
        keyFiles,
        moduleIds,
        summary,
      } satisfies RepoArchitectureZone;
    })
    .sort((a, b) => b.moduleIds.length - a.moduleIds.length || a.id.localeCompare(b.id));
}

export function selectMemoryModuleSummaries(params: {
  map: RepoKnowledgeMap;
  focusedModules: string[];
  limit: number;
}) {
  const focusSet = new Set(params.focusedModules.map(value => value.toLowerCase()));
  return params.map.modules
    .map(module => {
      let score = module.fileCount;
      if (focusSet.has(module.id.toLowerCase())) {
        score += 1_000;
      }
      if (module.dependencies.some(value => focusSet.has(value.toLowerCase()))) {
        score += 120;
      }
      if (module.dependents.some(value => focusSet.has(value.toLowerCase()))) {
        score += 120;
      }
      return { module, score };
    })
    .sort((a, b) => b.score - a.score || a.module.id.localeCompare(b.module.id))
    .slice(0, params.limit)
    .map(({ module }) => ({
      id: module.id,
      summary: module.summary,
      keyFiles: module.keyFiles.slice(0, 6),
      dependencies: module.dependencies.slice(0, 8),
      dependents: module.dependents.slice(0, 8),
    }));
}

export function collectRelatedModules(params: {
  map: RepoKnowledgeMap;
  moduleIds: string[];
  limit: number;
}) {
  const queue = dedupe(params.moduleIds.map(value => value.trim()), params.limit);
  const seen = new Set<string>();
  const ordered: string[] = [];
  while (queue.length > 0 && ordered.length < params.limit) {
    const moduleId = queue.shift();
    if (!moduleId) {
      continue;
    }
    const key = moduleId.toLowerCase();
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    const module = params.map.modules.find(item => item.id.toLowerCase() === key);
    if (!module) {
      continue;
    }
    ordered.push(module.id);
    const neighbors = dedupe(
      [...module.dependencies, ...module.dependents],
      params.limit,
    );
    for (const neighbor of neighbors) {
      if (!seen.has(neighbor.toLowerCase())) {
        queue.push(neighbor);
      }
    }
  }
  return ordered;
}

export function formatFocusedModuleDetails(params: {
  map: RepoKnowledgeMap;
  moduleIds: string[];
  limit: number;
}) {
  const wanted = new Set(
    collectRelatedModules({
      map: params.map,
      moduleIds: params.moduleIds,
      limit: params.limit,
    }).map(value => value.toLowerCase()),
  );
  const lines = params.map.modules
    .filter(module => wanted.has(module.id.toLowerCase()))
    .sort((a, b) => a.id.localeCompare(b.id))
    .map(
      module =>
        `- ${module.id}: ${module.summary} ` +
        `Key files: ${module.keyFiles.slice(0, 5).join(', ') || '(none)'}. ` +
        `Dependencies: ${module.dependencies.slice(0, 6).join(', ') || '(none)'}. ` +
        `Dependents: ${module.dependents.slice(0, 6).join(', ') || '(none)'}. ` +
        `Symbols: ${module.symbols.slice(0, 6).join(', ') || '(none)'}.`,
    )
    .join('\n');
  return truncate(lines || '(none)', 18_000);
}

export function buildRepoKnowledgeMap(params: {
  entries: RepoIndexEntry[];
  deepMode: boolean;
}) {
  const totalFiles = params.entries.length;
  const approxTokens = params.entries.reduce((sum, entry) => sum + entry.approxTokens, 0);
  const budget = buildRepoContextBudget({
    totalFiles,
    approxTokens,
    deepMode: params.deepMode,
  });
  const entryPoints = dedupe(
    params.entries
      .filter(entry => entry.isEntrypoint)
      .sort((a, b) => importanceScore(b) - importanceScore(a) || a.path.localeCompare(b.path))
      .map(entry => entry.path),
    18,
  );
  const keyFiles = dedupe(
    [
      ...entryPoints,
      ...params.entries
        .slice()
        .sort((a, b) => importanceScore(b) - importanceScore(a) || a.path.localeCompare(b.path))
        .map(entry => entry.path),
    ],
    24,
  );
  const topSymbols = dedupe(params.entries.flatMap(entry => entry.symbolHints), 28);
  const { graph, reverse } = buildDependencyGraph(params.entries);
  const { modules, pathToModule, moduleDependencies } = buildModuleSummaries(
    params.entries,
    graph,
  );
  const architectureZones = buildArchitectureZones(modules);
  const summaryLines = [
    `Repo size class: ${budget.sizeClass}.`,
    `Context strategy: ${budget.strategyLabel}.`,
    `Indexed ${totalFiles} file${totalFiles === 1 ? '' : 's'} totalling roughly ${approxTokens} tokens.`,
    entryPoints.length > 0 ? `Entrypoints: ${entryPoints.slice(0, 8).join(', ')}.` : 'Entrypoints: none detected.',
    architectureZones.length > 0
      ? `Architecture zones: ${architectureZones
          .slice(0, 5)
          .map(zone => `${zone.label} (${zone.moduleIds.length})`)
          .join(', ')}.`
      : 'Architecture zones: none detected.',
    modules.length > 0
      ? `Key modules: ${modules
          .slice(0, 8)
          .map(module => `${module.id} (${module.fileCount})`)
          .join(', ')}.`
      : 'Key modules: none detected.',
  ];
  const repoOverview = truncate(summaryLines.join(' '), 2_800);
  const architectureZoneOverview = truncate(
    architectureZones
      .map(
        zone =>
          `- ${zone.label}: ${zone.summary} Key files: ${zone.keyFiles.slice(0, 6).join(', ') || '(none)'}.`,
      )
      .join('\n') || '(none)',
    9_000,
  );
  const architectureOverview = truncate(
    architectureZones.map(zone => `- ${zone.summary}`).join('\n') || '(none)',
    8_000,
  );
  const moduleOverview = truncate(
    modules
      .slice(0, params.deepMode ? 36 : 24)
      .map(
        module =>
          `- ${module.id}: ${module.summary} Key files: ${module.keyFiles.slice(0, 5).join(', ') || '(none)'}.`,
      )
      .join('\n') || '(none)',
    18_000,
  );
  const moduleIndex = truncate(
    modules
      .map(
        module =>
          `- ${module.id} :: files=${module.fileCount}, roles=${module.roles.join(', ') || 'unknown'}, ` +
          `deps=${module.dependencies.slice(0, 6).join(', ') || '(none)'}, ` +
          `dependents=${module.dependents.slice(0, 6).join(', ') || '(none)'}`,
      )
      .join('\n') || '(none)',
    24_000,
  );

  return {
    sizeClass: budget.sizeClass,
    budget,
    totalFiles,
    approxTokens,
    keyFiles,
    entryPoints,
    topSymbols,
    modules,
    architectureZones,
    dependencyGraph: graph,
    reverseDependencyGraph: reverse,
    pathToModule,
    moduleDependencies,
    repoOverview,
    architectureOverview,
    architectureZoneOverview,
    moduleOverview,
    moduleIndex,
    summaryLines,
  } satisfies RepoKnowledgeMap;
}

function modulePromptScore(module: RepoModuleSummary, promptTokens: string[]) {
  const haystack = [
    module.id,
    module.summary,
    module.keyFiles.join(' '),
    module.symbols.join(' '),
    module.dependencies.join(' '),
    module.dependents.join(' '),
  ]
    .join(' ')
    .toLowerCase();
  let score = 0;
  for (const token of promptTokens) {
    if (haystack.includes(token)) {
      score += module.id.toLowerCase().includes(token) ? 8 : 4;
    }
  }
  return score;
}

export function findPromptFocusedModules(params: {
  map: RepoKnowledgeMap;
  prompt: string;
  currentFilePath?: string | null;
  limit: number;
}) {
  const promptTokens = dedupe(tokenize(params.prompt), 24);
  const currentModule = params.currentFilePath
    ? params.map.pathToModule[normalizeRepoPath(params.currentFilePath)]
    : null;
  return params.map.modules
    .map(module => {
      let score = modulePromptScore(module, promptTokens);
      if (currentModule && module.id === currentModule) {
        score += 14;
      }
      if (module.dependencies.includes(currentModule ?? '')) {
        score += 6;
      }
      return { moduleId: module.id, score };
    })
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score || a.moduleId.localeCompare(b.moduleId))
    .slice(0, params.limit)
    .map(item => item.moduleId);
}

export function collectModulePaths(params: {
  map: RepoKnowledgeMap;
  entries: RepoIndexEntry[];
  moduleIds: string[];
  limit: number;
}) {
  const moduleSet = new Set(params.moduleIds.map(value => value.toLowerCase()));
  const grouped = params.entries
    .filter(entry => moduleSet.has((params.map.pathToModule[entry.path] ?? '').toLowerCase()))
    .sort((a, b) => importanceScore(b) - importanceScore(a) || a.path.localeCompare(b.path))
    .map(entry => entry.path);
  return dedupe(grouped, params.limit);
}

export function collectRelatedPaths(params: {
  map: RepoKnowledgeMap;
  entries: RepoIndexEntry[];
  seedPaths: string[];
  currentFilePath?: string | null;
  limit: number;
}) {
  const normalizedSeeds = dedupe(params.seedPaths.map(value => normalizeRepoPath(value)), 120);
  const related = <string[]>[];
  const currentModule = params.currentFilePath
    ? params.map.pathToModule[normalizeRepoPath(params.currentFilePath)]
    : null;
  for (const seedPath of normalizedSeeds) {
    related.push(seedPath);
    related.push(...(params.map.dependencyGraph[seedPath] ?? []));
    related.push(...(params.map.reverseDependencyGraph[seedPath] ?? []));
    const moduleId = params.map.pathToModule[seedPath];
    if (moduleId) {
      const module = params.map.modules.find(item => item.id === moduleId);
      related.push(...(module?.keyFiles ?? []));
      related.push(...(module?.dependencies ?? []).flatMap(dependencyId => {
        const dependency = params.map.modules.find(item => item.id === dependencyId);
        return dependency?.keyFiles.slice(0, 2) ?? [];
      }));
    }
  }
  if (currentModule) {
    const module = params.map.modules.find(item => item.id === currentModule);
    related.push(...(module?.keyFiles ?? []));
  }
  return dedupe(related, params.limit);
}

export function buildInitialKnowledgeSeedPaths(params: {
  map: RepoKnowledgeMap;
  entries: RepoIndexEntry[];
  prompt: string;
  currentFilePath?: string | null;
}) {
  const promptFocusedModules = findPromptFocusedModules({
    map: params.map,
    prompt: params.prompt,
    currentFilePath: params.currentFilePath,
    limit: params.map.budget.initialModuleSeedLimit,
  });
  const relatedModules = collectRelatedModules({
    map: params.map,
    moduleIds: promptFocusedModules,
    limit: Math.max(
      params.map.budget.initialModuleSeedLimit,
      Math.ceil(params.map.budget.initialModuleSeedLimit * 1.5),
    ),
  });
  const focusedModules = dedupe(
    [...promptFocusedModules, ...relatedModules],
    Math.max(params.map.budget.initialModuleSeedLimit * 2, 24),
  );
  const modulePaths = collectModulePaths({
    map: params.map,
    entries: params.entries,
    moduleIds: focusedModules,
    limit:
      params.map.budget.initialModuleSeedLimit *
      Math.max(params.map.budget.keyFilesPerModule, 3),
  });
  const seedPaths = dedupe(
    [
      params.currentFilePath ?? null,
      ...params.map.keyFiles,
      ...params.map.entryPoints,
      ...modulePaths,
    ],
    params.map.budget.initialModuleSeedLimit * params.map.budget.keyFilesPerModule + 24,
  );
  return {
    focusedModules,
    seedPaths,
  };
}

export function createRepoExecutionRunMemory(params: {
  map: RepoKnowledgeMap;
  globalContextPaths: string[];
  focusedModules: string[];
  exploredPaths: string[];
  hydratedPaths: string[];
  editablePaths: string[];
  readOnlyPaths: string[];
}) {
  return {
    sizeClass: params.map.sizeClass,
    contextStrategy: params.map.budget.strategyLabel,
    repoOverview: params.map.repoOverview,
    architectureOverview: params.map.architectureOverview,
    moduleOverview: params.map.moduleOverview,
    focusedModules: dedupe(params.focusedModules, RUN_MEMORY_FOCUSED_MODULE_LIMIT),
    exploredPaths: dedupe(params.exploredPaths, RUN_MEMORY_PATH_LIMIT),
    hydratedPaths: dedupe(params.hydratedPaths, RUN_MEMORY_PATH_LIMIT),
    editablePaths: dedupe(params.editablePaths, RUN_MEMORY_EDITABLE_LIMIT),
    readOnlyPaths: dedupe(params.readOnlyPaths, RUN_MEMORY_READ_ONLY_LIMIT),
    globalContextPaths: dedupe(params.globalContextPaths, RUN_MEMORY_GLOBAL_CONTEXT_LIMIT),
    architectureConclusions: params.map.summaryLines.slice(0, RUN_MEMORY_CONCLUSION_LIMIT),
    unresolvedQuestions: [] as string[],
    moduleSummaries: selectMemoryModuleSummaries({
      map: params.map,
      focusedModules: params.focusedModules,
      limit: RUN_MEMORY_MODULE_SUMMARY_LIMIT,
    }),
    passes: [] as RepoExecutionMemoryPass[],
  } satisfies RepoExecutionRunMemory;
}

export function recordRepoExecutionMemoryPass(params: {
  memory: RepoExecutionRunMemory;
  pass: RepoExecutionMemoryPass;
  focusedModules?: string[];
  exploredPaths?: string[];
  hydratedPaths?: string[];
  editablePaths?: string[];
  readOnlyPaths?: string[];
  conclusions?: string[];
  unresolvedQuestions?: string[];
}) {
  return {
    ...params.memory,
    focusedModules: dedupe(
      [...params.memory.focusedModules, ...(params.focusedModules ?? [])],
      RUN_MEMORY_FOCUSED_MODULE_LIMIT,
    ),
    exploredPaths: dedupe(
      [...params.memory.exploredPaths, ...(params.exploredPaths ?? [])],
      RUN_MEMORY_PATH_LIMIT,
    ),
    hydratedPaths: dedupe(
      [...params.memory.hydratedPaths, ...(params.hydratedPaths ?? [])],
      RUN_MEMORY_PATH_LIMIT,
    ),
    editablePaths: dedupe(
      [...params.memory.editablePaths, ...(params.editablePaths ?? [])],
      RUN_MEMORY_EDITABLE_LIMIT,
    ),
    readOnlyPaths: dedupe(
      [...params.memory.readOnlyPaths, ...(params.readOnlyPaths ?? [])],
      RUN_MEMORY_READ_ONLY_LIMIT,
    ),
    architectureConclusions: dedupe(
      [...params.memory.architectureConclusions, ...(params.conclusions ?? []), ...params.pass.conclusions],
      RUN_MEMORY_CONCLUSION_LIMIT,
    ),
    unresolvedQuestions: dedupe(
      [
        ...params.memory.unresolvedQuestions,
        ...(params.unresolvedQuestions ?? []),
        ...params.pass.uncertainties,
      ],
      RUN_MEMORY_CONCLUSION_LIMIT,
    ),
    passes: [...params.memory.passes, params.pass].slice(-RUN_MEMORY_PASS_LIMIT),
  } satisfies RepoExecutionRunMemory;
}

export function formatRepoKnowledgeMap(map: RepoKnowledgeMap) {
  return truncate(
    [
      map.repoOverview,
      '',
      'ARCHITECTURE ZONES:',
      map.architectureZoneOverview,
      '',
      'MODULE SUMMARIES:',
      map.moduleOverview,
      '',
      'MODULE INDEX:',
      map.moduleIndex,
    ].join('\n'),
    128_000,
  );
}

export function formatRepoExecutionRunMemory(memory: RepoExecutionRunMemory) {
  const recentPasses = memory.passes
    .slice(-6)
    .map(
      pass =>
        `- Pass ${pass.passNumber}: ${pass.rationale || 'no rationale'} ` +
        `[modules=${pass.focusModules.join(', ') || 'none'}; hydrated=${pass.hydratedPaths.length}; done=${pass.done ? 'yes' : 'no'}]`,
    )
    .join('\n');
  const trackedModules = memory.moduleSummaries
    .slice(0, 12)
    .map(
      module =>
        `- ${module.id}: ${module.summary} Dependencies: ${module.dependencies.slice(0, 4).join(', ') || '(none)'}.`,
    )
    .join('\n');
  return truncate(
    [
      `RUN STRATEGY: ${memory.contextStrategy}`,
      `REPO SIZE CLASS: ${memory.sizeClass}`,
      `FOCUSED MODULES (${memory.focusedModules.length}): ${memory.focusedModules.slice(0, 18).join(', ') || '(none)'}`,
      `EDITABLE PATH COUNT: ${memory.editablePaths.length}`,
      `READ ONLY PATH COUNT: ${memory.readOnlyPaths.length}`,
      `EXPLORED PATH COUNT: ${memory.exploredPaths.length}`,
      `HYDRATED PATH COUNT: ${memory.hydratedPaths.length}`,
      `GLOBAL CONTEXT PATH COUNT: ${memory.globalContextPaths.length}`,
      'TRACKED MODULES:',
      trackedModules || '(none)',
      `ARCHITECTURE CONCLUSIONS: ${memory.architectureConclusions.join(' | ') || '(none)'}`,
      `UNRESOLVED QUESTIONS: ${memory.unresolvedQuestions.join(' | ') || '(none)'}`,
      'RECENT EXPLORATION PASSES:',
      recentPasses || '(none)',
    ].join('\n'),
    18_000,
  );
}

export function serializeRepoExecutionRunMemory(memory: RepoExecutionRunMemory) {
  return {
    sizeClass: memory.sizeClass,
    contextStrategy: memory.contextStrategy,
    repoOverview: memory.repoOverview,
    architectureOverview: memory.architectureOverview,
    moduleOverview: memory.moduleOverview,
    focusedModules: memory.focusedModules.slice(0, RUN_MEMORY_FOCUSED_MODULE_LIMIT),
    exploredPaths: memory.exploredPaths.slice(0, RUN_MEMORY_PATH_LIMIT),
    hydratedPaths: memory.hydratedPaths.slice(0, RUN_MEMORY_PATH_LIMIT),
    editablePaths: memory.editablePaths.slice(0, RUN_MEMORY_EDITABLE_LIMIT),
    readOnlyPaths: memory.readOnlyPaths.slice(0, RUN_MEMORY_READ_ONLY_LIMIT),
    globalContextPaths: memory.globalContextPaths.slice(0, RUN_MEMORY_GLOBAL_CONTEXT_LIMIT),
    architectureConclusions: memory.architectureConclusions.slice(0, RUN_MEMORY_CONCLUSION_LIMIT),
    unresolvedQuestions: memory.unresolvedQuestions.slice(0, RUN_MEMORY_CONCLUSION_LIMIT),
    moduleSummaries: memory.moduleSummaries.slice(0, RUN_MEMORY_MODULE_SUMMARY_LIMIT),
    passes: memory.passes.slice(-RUN_MEMORY_PASS_LIMIT),
    summary: formatRepoExecutionRunMemory(memory),
  };
}

export function serializeRepoKnowledgeMap(map: RepoKnowledgeMap) {
  return {
    sizeClass: map.sizeClass,
    contextStrategy: map.budget.strategyLabel,
    exactWholeRepoEligible: map.budget.exactWholeRepoEligible,
    totalFiles: map.totalFiles,
    approxTokens: map.approxTokens,
    keyFiles: map.keyFiles.slice(0, 48),
    entryPoints: map.entryPoints.slice(0, 32),
    topSymbols: map.topSymbols.slice(0, 48),
    moduleCount: map.modules.length,
    modules: map.modules.slice(0, 64),
    architectureZones: map.architectureZones.slice(0, 20),
    repoOverview: map.repoOverview,
    architectureOverview: map.architectureOverview,
    architectureZoneOverview: map.architectureZoneOverview,
    moduleOverview: map.moduleOverview,
    moduleIndex: map.moduleIndex,
    summary: formatRepoKnowledgeMap(map),
  };
}
