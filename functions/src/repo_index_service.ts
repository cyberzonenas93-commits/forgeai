import { createHash } from 'node:crypto';

import {
  generateFileSummary,
  type FileSummaryResult,
} from './file_summary_generator';

export interface RepoIndexFileInput {
  path: string;
  type?: string | null;
  language?: string | null;
  content?: string | null;
  contentPreview?: string | null;
  sha?: string | null;
}

export interface RepoIndexEntry extends FileSummaryResult {
  path: string;
  type: string;
  language: string;
  extension: string;
  directory: string;
  fileName: string;
  hasContent: boolean;
  approxTokens: number;
  contentPreview: string;
  contentHash: string;
}

export interface RankedRepoIndexEntry extends RepoIndexEntry {
  score: number;
  reasons: string[];
}

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

function tokenize(value: string) {
  return value
    .toLowerCase()
    .split(/[^a-z0-9_./-]+/)
    .map(part => part.trim())
    .filter(part => part.length >= 3);
}

function pathMeta(path: string) {
  const normalized = path.replace(/\\/g, '/');
  const parts = normalized.split('/').filter(Boolean);
  const fileName = parts.length > 0 ? parts[parts.length - 1] : normalized;
  const dotIndex = fileName.lastIndexOf('.');
  const extension = dotIndex >= 0 ? fileName.slice(dotIndex + 1).toLowerCase() : '';
  const directory = parts.length > 1 ? parts.slice(0, -1).join('/') : '';
  return { fileName, extension, directory };
}

function approxTokens(value: string) {
  return Math.max(1, Math.ceil(value.length / 4));
}

function scoreEntry(
  promptTokens: string[],
  entry: RepoIndexEntry,
  currentFilePath: string | null,
) {
  let score = 0;
  const reasons: string[] = [];
  const haystacks = [
    entry.path.toLowerCase(),
    entry.summary.toLowerCase(),
    entry.embeddingText.toLowerCase(),
    entry.imports.join(' ').toLowerCase(),
    entry.symbolHints.join(' ').toLowerCase(),
  ];

  for (const token of promptTokens) {
    if (entry.path.toLowerCase().includes(token)) {
      score += 18;
      reasons.push(`path:${token}`);
      continue;
    }
    if (entry.fileName.toLowerCase().includes(token)) {
      score += 14;
      reasons.push(`name:${token}`);
      continue;
    }
    if (entry.keywords.some(keyword => keyword.toLowerCase().includes(token))) {
      score += 10;
      reasons.push(`keyword:${token}`);
      continue;
    }
    if (haystacks.some(value => value.includes(token))) {
      score += 6;
      reasons.push(`context:${token}`);
    }
  }

  if (currentFilePath) {
    const currentDirectory = pathMeta(currentFilePath).directory;
    if (currentDirectory && entry.directory === currentDirectory) {
      score += 12;
      reasons.push('same_directory');
    } else if (
      currentDirectory &&
      entry.directory &&
      (entry.directory.startsWith(currentDirectory) ||
        currentDirectory.startsWith(entry.directory))
    ) {
      score += 6;
      reasons.push('nearby_directory');
    }
  }

  if (
    currentFilePath &&
    entry.imports.some(value => value.toLowerCase().includes(pathMeta(currentFilePath).fileName.toLowerCase()))
  ) {
    score += 8;
    reasons.push('references_current_file');
  }

  if (!entry.hasContent) {
    score -= 3;
    reasons.push('metadata_only');
  }
  if (entry.path.includes('/build/') || entry.path.includes('/.dart_tool/')) {
    score -= 20;
    reasons.push('generated_path');
  }
  return {
    score,
    reasons: dedupe(reasons, 10),
  };
}

export function buildRepoIndexEntries(files: RepoIndexFileInput[]) {
  return files.map<RepoIndexEntry>(file => {
    const { fileName, extension, directory } = pathMeta(file.path);
    const content = file.content ?? '';
    const contentPreview = truncate(file.contentPreview ?? content, 1600);
    const summary = generateFileSummary({
      path: file.path,
      language: file.language,
      content,
      contentPreview,
      type: file.type,
    });
    return {
      path: file.path,
      type: file.type ?? 'blob',
      language: file.language ?? 'Text',
      extension,
      directory,
      fileName,
      hasContent: content.trim().length > 0,
      approxTokens: approxTokens(content || contentPreview || file.path),
      contentPreview,
      contentHash: file.sha?.trim()
        ? file.sha.trim()
        : createHash('sha1').update(`${file.path}\n${contentPreview}`).digest('hex'),
      ...summary,
    };
  });
}

export function rankRepoIndexEntries(params: {
  prompt: string;
  currentFilePath?: string | null;
  entries: RepoIndexEntry[];
  deepMode?: boolean;
}) {
  const promptTokens = dedupe(tokenize(params.prompt), params.deepMode ? 28 : 18);
  return params.entries
    .map<RankedRepoIndexEntry>(entry => {
      const scored = scoreEntry(promptTokens, entry, params.currentFilePath ?? null);
      return {
        ...entry,
        score: scored.score,
        reasons: scored.reasons,
      };
    })
    .sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));
}

export function pickDependencyCandidates(
  entries: RepoIndexEntry[],
  selectedPaths: string[],
  limit: number,
) {
  const selectedSet = new Set(selectedPaths.map(value => value.toLowerCase()));
  const selectedFileNames = selectedPaths.map(value => pathMeta(value).fileName.toLowerCase());
  const matches = entries
    .filter(entry => !selectedSet.has(entry.path.toLowerCase()))
    .map(entry => {
      let score = 0;
      if (selectedPaths.some(path => entry.directory && path.startsWith(`${entry.directory}/`))) {
        score += 6;
      }
      if (
        entry.imports.some(
          value =>
            selectedFileNames.some(name => value.toLowerCase().includes(name)) ||
            selectedPaths.some(path => value.toLowerCase().includes(path.toLowerCase())),
        )
      ) {
        score += 12;
      }
      if (entry.fileName.toLowerCase().includes('service') || entry.fileName.toLowerCase().includes('repository')) {
        score += 2;
      }
      return { path: entry.path, score };
    })
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score || a.path.localeCompare(b.path));
  return dedupe(matches.map(item => item.path), limit);
}

export function buildRepoStructure(paths: string[], maxLines = 180) {
  const sorted = [...paths].sort((a, b) => a.localeCompare(b));
  return truncate(sorted.slice(0, maxLines).join('\n'), 18_000);
}

export function buildIndexEntryStoragePayload(entry: RepoIndexEntry) {
  return {
    path: entry.path,
    type: entry.type,
    language: entry.language,
    extension: entry.extension,
    directory: entry.directory,
    fileName: entry.fileName,
    summary: entry.summary,
    keywords: entry.keywords,
    imports: entry.imports,
    symbolHints: entry.symbolHints,
    embeddingText: entry.embeddingText,
    contentPreview: entry.contentPreview,
    contentHash: entry.contentHash,
    approxTokens: entry.approxTokens,
    hasContent: entry.hasContent,
    embeddingStatus: 'not_generated',
  };
}
