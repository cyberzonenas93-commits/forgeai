export interface RepoExecutionContextFile {
  path: string;
  summary: string;
  reasons: string[];
  content: string;
}

export interface RepoExecutionContextPayload {
  repoOverview?: string;
  architectureOverview?: string;
  architectureZoneOverview?: string;
  moduleOverview?: string;
  moduleIndex?: string;
  focusedModuleDetails?: string;
  runMemorySummary?: string;
  repoSizeClass?: string;
  contextStrategy?: string;
  repoStructure: string;
  globalContextFiles?: RepoExecutionContextFile[];
  relevantFiles: RepoExecutionContextFile[];
  dependencyFiles: RepoExecutionContextFile[];
  currentFilePath?: string | null;
  userPrompt: string;
  deepMode: boolean;
}

export interface RepoExecutionPlannerCandidate {
  path: string;
  summary: string;
  reasons: string[];
}

export interface RepoExecutionPlannerPayload {
  repoOverview: string;
  architectureOverview?: string;
  architectureZoneOverview?: string;
  moduleOverview?: string;
  moduleIndex?: string;
  focusedModuleDetails?: string;
  runMemorySummary?: string;
  repoSizeClass?: string;
  contextStrategy?: string;
  repoStructure: string;
  candidateFiles: RepoExecutionPlannerCandidate[];
  currentFilePath?: string | null;
  userPrompt: string;
  deepMode: boolean;
}

export interface ParsedRepoExecutionPlan {
  summary: string;
  primaryPaths: string[];
  readOnlyPaths: string[];
  additionalPathHints: string[];
  focusModules: string[];
  architectureNotes: string[];
  unresolvedQuestions: string[];
  needsBroadContext: boolean;
}

export interface ParsedRepoExecutionEdit {
  path: string;
  beforeContent: string;
  afterContent: string;
}

function truncate(value: string, maxChars: number) {
  if (value.length <= maxChars) {
    return value;
  }
  return `${value.slice(0, maxChars - 1)}...`;
}

function normalizeBlock(value: string) {
  return value.replace(/\r\n/g, '\n');
}

export function buildRepoExecutionSystemPrompt() {
  return [
    'You are CodeCatalystAI acting as a senior software engineer inside a real repository.',
    'Do not explain your work. Do not give steps, notes, or commentary.',
    'You must return only structured file rewrites using this exact repeated format:',
    'FILE: path/to/file',
    '',
    '--- BEFORE ---',
    '(full previous file content, or empty for a new file)',
    '',
    '--- AFTER ---',
    '(full new file content, or empty only if you are intentionally deleting the file)',
    '',
    'Rules:',
    '- Output only files you want changed.',
    '- Keep paths relative to repo root.',
    '- Preserve unchanged files by omitting them.',
    '- Use the layered repository context, module summaries, and run memory to stay architecturally consistent across the whole repo.',
    '- Treat the module index and focused-module details as real repo structure, not as optional fluff.',
    '- Prefer the smallest safe set of files, but do not artificially avoid ripple edits when architecture requires them.',
    '- Do not invent dependencies that are not already present unless the request clearly needs a new file.',
    '- Return no markdown fences.',
    '- Return no prose before, between, or after file blocks.',
  ].join('\n');
}

export function buildRepoExecutionPlanningSystemPrompt() {
  return [
    'You are CodeCatalystAI planning repository context for an autonomous coding run.',
    'You are not writing code yet.',
    'Return only valid JSON with these keys:',
    '- summary: short string',
    '- primaryPaths: array of repo-relative file paths the model should be allowed to edit',
    '- readOnlyPaths: array of repo-relative file paths that should be loaded as read-only supporting context',
    '- additionalPathHints: array of short search terms or path fragments that would help expand repo context',
    '- focusModules: array of module IDs from the repo knowledge map',
    '- architectureNotes: array of short architecture conclusions to remember',
    '- unresolvedQuestions: array of short unknowns that still matter',
    '- needsBroadContext: boolean',
    'Rules:',
    '- Prefer the smallest safe edit set, but if the request clearly spans architecture, include multiple files.',
    '- Use readOnlyPaths for config, entrypoints, and neighboring modules that explain architecture.',
    '- Use architecture zones, module relationships, and focused-module details to reason beyond the first obvious files.',
    '- If the repo is small enough to reason over broadly, set needsBroadContext to true.',
    '- Do not include paths that are not in the repository tree.',
    '- Return no markdown fences and no prose outside the JSON object.',
  ].join('\n');
}

function formatContextFiles(title: string, files: RepoExecutionContextFile[]) {
  if (files.length === 0) {
    return `${title}:\n(none)`;
  }
  const body = files
    .map(file => {
      const reasons = file.reasons.length > 0 ? `reasons=${file.reasons.join(', ')}` : 'reasons=selected';
      return [
        `PATH: ${file.path}`,
        `SUMMARY: ${file.summary}`,
        `META: ${reasons}`,
        'CONTENT:',
        file.content,
      ].join('\n');
    })
    .join('\n\n');
  return `${title}:\n${body}`;
}

export function buildRepoExecutionUserPrompt(context: RepoExecutionContextPayload) {
  return [
    `USER REQUEST:\n${context.userPrompt}`,
    '',
    `MODE: ${context.deepMode ? 'deep' : 'normal'}`,
    context.repoSizeClass ? `REPO SIZE CLASS: ${context.repoSizeClass}` : 'REPO SIZE CLASS: (unknown)',
    context.contextStrategy ? `CONTEXT STRATEGY: ${context.contextStrategy}` : 'CONTEXT STRATEGY: (unknown)',
    context.currentFilePath ? `CURRENT FILE: ${context.currentFilePath}` : 'CURRENT FILE: (none)',
    '',
    'REPOSITORY OVERVIEW:',
    context.repoOverview || '(no repo overview available)',
    '',
    'ARCHITECTURE OVERVIEW:',
    context.architectureOverview || '(none)',
    '',
    'ARCHITECTURE ZONES:',
    context.architectureZoneOverview || '(none)',
    '',
    'MODULE OVERVIEW:',
    context.moduleOverview || '(none)',
    '',
    'MODULE INDEX:',
    context.moduleIndex || '(none)',
    '',
    'FOCUSED MODULE DETAILS:',
    context.focusedModuleDetails || '(none)',
    '',
    'RUN MEMORY:',
    context.runMemorySummary || '(none)',
    '',
    'REPOSITORY STRUCTURE:',
    context.repoStructure || '(no files indexed)',
    '',
    formatContextFiles('GLOBAL CONTEXT FILES', context.globalContextFiles ?? []),
    '',
    formatContextFiles('RELEVANT FILES', context.relevantFiles),
    '',
    formatContextFiles('DEPENDENCY FILES', context.dependencyFiles),
    '',
    'Only modify files listed in RELEVANT FILES. Treat GLOBAL CONTEXT FILES and DEPENDENCY FILES as read-only context.',
    '',
    'Produce the final changed files now.',
  ].join('\n');
}

function formatPlanningCandidates(files: RepoExecutionPlannerCandidate[]) {
  if (files.length === 0) {
    return '(none)';
  }
  return files
    .map(file => {
      const reasons = file.reasons.length > 0 ? file.reasons.join(', ') : 'selected';
      return `PATH: ${file.path}\nSUMMARY: ${file.summary}\nREASONS: ${reasons}`;
    })
    .join('\n\n');
}

export function buildRepoExecutionPlanningUserPrompt(context: RepoExecutionPlannerPayload) {
  return [
    `USER REQUEST:\n${context.userPrompt}`,
    '',
    `MODE: ${context.deepMode ? 'deep' : 'normal'}`,
    context.repoSizeClass ? `REPO SIZE CLASS: ${context.repoSizeClass}` : 'REPO SIZE CLASS: (unknown)',
    context.contextStrategy ? `CONTEXT STRATEGY: ${context.contextStrategy}` : 'CONTEXT STRATEGY: (unknown)',
    context.currentFilePath ? `CURRENT FILE: ${context.currentFilePath}` : 'CURRENT FILE: (none)',
    '',
    'REPOSITORY OVERVIEW:',
    context.repoOverview || '(no repo overview available)',
    '',
    'ARCHITECTURE OVERVIEW:',
    context.architectureOverview || '(none)',
    '',
    'ARCHITECTURE ZONES:',
    context.architectureZoneOverview || '(none)',
    '',
    'MODULE OVERVIEW:',
    context.moduleOverview || '(none)',
    '',
    'MODULE INDEX:',
    context.moduleIndex || '(none)',
    '',
    'FOCUSED MODULE DETAILS:',
    context.focusedModuleDetails || '(none)',
    '',
    'RUN MEMORY:',
    context.runMemorySummary || '(none)',
    '',
    'REPOSITORY STRUCTURE:',
    context.repoStructure || '(no files indexed)',
    '',
    'TOP CANDIDATE FILES:',
    formatPlanningCandidates(context.candidateFiles),
    '',
    'Choose the best edit scope now.',
  ].join('\n');
}

export function buildRepoExecutionRepairPrompt(
  context: RepoExecutionContextPayload,
  invalidOutput: string,
) {
  return [
    buildRepoExecutionUserPrompt(context),
    '',
    'The previous response was invalid because it was not parseable into FILE / BEFORE / AFTER blocks.',
    'Repair it and return a valid response now.',
    '',
    'INVALID RESPONSE TO REPAIR:',
    truncate(invalidOutput, 24_000),
  ].join('\n');
}

function asStringArray(value: unknown) {
  if (!Array.isArray(value)) {
    return [] as string[];
  }
  return value
    .map(item => (typeof item === 'string' ? item.trim() : ''))
    .filter(item => item.length > 0);
}

export function parseRepoExecutionPlanResponse(responseText: string): ParsedRepoExecutionPlan {
  try {
    const parsed = JSON.parse(responseText) as {
      summary?: unknown;
      primaryPaths?: unknown;
      readOnlyPaths?: unknown;
      additionalPathHints?: unknown;
      focusModules?: unknown;
      architectureNotes?: unknown;
      unresolvedQuestions?: unknown;
      needsBroadContext?: unknown;
    };
    return {
      summary: typeof parsed.summary === 'string' ? parsed.summary.trim() : '',
      primaryPaths: asStringArray(parsed.primaryPaths),
      readOnlyPaths: asStringArray(parsed.readOnlyPaths),
      additionalPathHints: asStringArray(parsed.additionalPathHints),
      focusModules: asStringArray(parsed.focusModules),
      architectureNotes: asStringArray(parsed.architectureNotes),
      unresolvedQuestions: asStringArray(parsed.unresolvedQuestions),
      needsBroadContext: parsed.needsBroadContext === true,
    };
  } catch {
    return {
      summary: '',
      primaryPaths: [],
      readOnlyPaths: [],
      additionalPathHints: [],
      focusModules: [],
      architectureNotes: [],
      unresolvedQuestions: [],
      needsBroadContext: false,
    };
  }
}

export function parseRepoExecutionResponse(responseText: string) {
  const normalized = normalizeBlock(responseText).trim();
  if (!normalized) {
    return [] as ParsedRepoExecutionEdit[];
  }

  const fileMatches = [...normalized.matchAll(/^FILE:\s*(.+)$/gm)];
  if (fileMatches.length === 0) {
    return [] as ParsedRepoExecutionEdit[];
  }

  const edits: ParsedRepoExecutionEdit[] = [];
  for (let index = 0; index < fileMatches.length; index += 1) {
    const current = fileMatches[index];
    const next = fileMatches[index + 1];
    const path = (current[1] ?? '').trim();
    if (!path) {
      return [] as ParsedRepoExecutionEdit[];
    }
    const blockStart = current.index ?? 0;
    const contentStart = blockStart + current[0].length;
    const block = normalized.slice(contentStart, next?.index ?? normalized.length).trimStart();
    const beforeMarker = block.indexOf('--- BEFORE ---');
    const afterMarker = block.indexOf('--- AFTER ---');
    if (beforeMarker != 0 || afterMarker < 0 || afterMarker <= beforeMarker) {
      return [] as ParsedRepoExecutionEdit[];
    }
    const beforeContent = block
      .slice('--- BEFORE ---'.length, afterMarker)
      .replace(/^\n/, '')
      .replace(/\n$/, '');
    const afterContent = block
      .slice(afterMarker + '--- AFTER ---'.length)
      .replace(/^\n/, '')
      .replace(/\n$/, '');
    edits.push({
      path,
      beforeContent,
      afterContent,
    });
  }
  return edits;
}

export function summarizeRepoExecution(edits: ParsedRepoExecutionEdit[]) {
  if (edits.length === 0) {
    return 'No file changes were generated.';
  }
  if (edits.length === 1) {
    return `Prepared 1 file change for ${edits[0].path}.`;
  }
  return `Prepared ${edits.length} file changes across ${edits.slice(0, 3).map(edit => edit.path).join(', ')}${edits.length > 3 ? ', and more' : ''}.`;
}
