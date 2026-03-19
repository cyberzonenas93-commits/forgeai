export interface RepoExecutionContextFile {
  path: string;
  summary: string;
  reasons: string[];
  content: string;
}

export interface RepoExecutionContextPayload {
  repoStructure: string;
  relevantFiles: RepoExecutionContextFile[];
  dependencyFiles: RepoExecutionContextFile[];
  currentFilePath?: string | null;
  userPrompt: string;
  deepMode: boolean;
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
    '- Prefer the smallest safe set of files.',
    '- Do not invent dependencies that are not already present unless the request clearly needs a new file.',
    '- Return no markdown fences.',
    '- Return no prose before, between, or after file blocks.',
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
    context.currentFilePath ? `CURRENT FILE: ${context.currentFilePath}` : 'CURRENT FILE: (none)',
    '',
    'REPOSITORY STRUCTURE:',
    context.repoStructure || '(no files indexed)',
    '',
    formatContextFiles('RELEVANT FILES', context.relevantFiles),
    '',
    formatContextFiles('DEPENDENCY FILES', context.dependencyFiles),
    '',
    'Only modify files listed in RELEVANT FILES. Treat DEPENDENCY FILES as read-only context.',
    '',
    'Produce the final changed files now.',
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
