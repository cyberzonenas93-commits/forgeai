import type { RepoIndexEntry, RepoIndexFileInput, RankedRepoIndexEntry } from './repo_index_service';
import { semanticSearch } from './vector_store';

export interface RepoContextOrchestratorSnapshot {
  selectedFiles: string[];
  dependencyFiles: string[];
  inspectedFiles: string[];
  globalContextFiles: string[];
  repoOverview?: string;
  architectureOverview?: string;
  moduleOverview?: string;
  repoSizeClass?: string;
  contextStrategy?: string;
  executionMemorySummary?: string;
  planningSummary?: string;
}

export function buildContextOrchestratorSnapshot(params: {
  fileMap: Map<string, RepoIndexFileInput>;
  selectedEntries: RankedRepoIndexEntry[];
  dependencyEntries: RepoIndexEntry[];
  globalContextEntries: RepoIndexEntry[];
  inspectedPaths: string[];
  repoOverview?: string;
  architectureOverview?: string;
  moduleOverview?: string;
  repoSizeClass?: string;
  contextStrategy?: string;
  executionMemorySummary?: string;
  planningSummary?: string;
}) {
  return {
    selectedFiles: params.selectedEntries.map(entry => entry.path),
    dependencyFiles: params.dependencyEntries.map(entry => entry.path),
    inspectedFiles: params.inspectedPaths,
    globalContextFiles: params.globalContextEntries.map(entry => entry.path),
    repoOverview: params.repoOverview,
    architectureOverview: params.architectureOverview,
    moduleOverview: params.moduleOverview,
    repoSizeClass: params.repoSizeClass,
    contextStrategy: params.contextStrategy,
    executionMemorySummary: params.executionMemorySummary,
    planningSummary: params.planningSummary,
  } satisfies RepoContextOrchestratorSnapshot;
}

// ---------------------------------------------------------------------------
// Semantic context augmentation
// ---------------------------------------------------------------------------

/**
 * Weight applied to the semantic similarity score when merging with the
 * existing syntactic relevance score.
 *   finalScore = semanticWeight * semanticScore + (1 - semanticWeight) * syntacticScore
 */
const SEMANTIC_WEIGHT = 0.7;
const SYNTACTIC_WEIGHT = 1 - SEMANTIC_WEIGHT;

export interface SemanticContextResult {
  /** Ranked entries after merging semantic + syntactic scores. */
  mergedEntries: RankedRepoIndexEntry[];
  /** Paths selected purely via semantic similarity that were not in the
   *  original syntactic set — useful for logging / debugging. */
  semanticOnlyPaths: string[];
  /** Whether the semantic search succeeded or fell back to syntactic only. */
  semanticUsed: boolean;
}

/**
 * Augment an existing syntactic ranking with semantic vector search results.
 *
 * Algorithm:
 *  1. Run `semanticSearch()` for the task prompt against stored embeddings.
 *  2. Normalise both score sets to [0, 1].
 *  3. Merge: finalScore = 0.7 * semanticScore + 0.3 * syntacticScore
 *  4. Re-sort merged list descending by finalScore.
 *  5. Append semantic-only files (not in original syntactic set) at their
 *     merged score positions.
 *
 * Falls back transparently to the original `syntacticEntries` if:
 *  - OpenAI key is absent
 *  - No embeddings are stored for the repo
 *  - The semantic call throws
 *
 * @param params.prompt         The user task prompt to embed.
 * @param params.repoId         Firestore repository document ID.
 * @param params.syntacticEntries  The ranked entries from the existing
 *                              syntactic context selection pipeline.
 * @param params.fileMap        Map of all known repo files (for lookup).
 * @param params.topK           How many semantic candidates to request.
 *                              Defaults to 2× the syntactic entry count,
 *                              capped at 60.
 */
export async function buildSemanticContext(params: {
  prompt: string;
  repoId: string;
  syntacticEntries: RankedRepoIndexEntry[];
  fileMap: Map<string, RepoIndexFileInput>;
  topK?: number;
}): Promise<SemanticContextResult> {
  const { prompt, repoId, syntacticEntries, fileMap } = params;
  const topK = params.topK ?? Math.min(Math.max(syntacticEntries.length * 2, 20), 60);

  // --- Attempt semantic search -----------------------------------------------
  let semanticHits: Array<{ path: string; score: number }> = [];
  let semanticUsed = false;

  try {
    const rawHits = await semanticSearch(prompt, repoId, topK);
    if (rawHits.length > 0) {
      semanticHits = rawHits;
      semanticUsed = true;
    }
  } catch {
    // Silently fall back to syntactic only — the OpenAI key may not be present
    // in all environments, or the embeddings collection may be empty.
    semanticUsed = false;
  }

  if (!semanticUsed) {
    return {
      mergedEntries: syntacticEntries,
      semanticOnlyPaths: [],
      semanticUsed: false,
    };
  }

  // --- Normalise syntactic scores to [0, 1] ----------------------------------
  const maxSyntacticScore = syntacticEntries.reduce((m, e) => Math.max(m, e.score), 0);
  const syntacticByPath = new Map<string, RankedRepoIndexEntry>();
  for (const entry of syntacticEntries) {
    syntacticByPath.set(entry.path, entry);
  }

  // --- Normalise semantic scores to [0, 1] -----------------------------------
  const maxSemanticScore = semanticHits.reduce((m, h) => Math.max(m, h.score), 0);
  const semanticByPath = new Map<string, number>();
  for (const hit of semanticHits) {
    semanticByPath.set(hit.path, hit.score);
  }

  // --- Build merged scored set -----------------------------------------------
  const allPaths = new Set<string>([
    ...syntacticByPath.keys(),
    ...semanticByPath.keys(),
  ]);

  const merged: RankedRepoIndexEntry[] = [];
  const semanticOnlyPaths: string[] = [];

  for (const path of allPaths) {
    const syntacticEntry = syntacticByPath.get(path);
    const rawSemanticScore = semanticByPath.get(path) ?? 0;

    const normSyntactic =
      maxSyntacticScore > 0 && syntacticEntry
        ? syntacticEntry.score / maxSyntacticScore
        : 0;
    const normSemantic =
      maxSemanticScore > 0 ? rawSemanticScore / maxSemanticScore : 0;

    const combinedScore =
      SEMANTIC_WEIGHT * normSemantic + SYNTACTIC_WEIGHT * normSyntactic;

    if (syntacticEntry) {
      merged.push({
        ...syntacticEntry,
        score: combinedScore,
        reasons: [
          ...syntacticEntry.reasons,
          `semantic-similarity:${normSemantic.toFixed(3)}`,
        ],
      });
    } else {
      // Semantic-only file — must be present in the fileMap to build a stub entry.
      const fileInput = fileMap.get(path);
      if (!fileInput) continue;

      semanticOnlyPaths.push(path);

      const stubEntry: RankedRepoIndexEntry = {
        path,
        type: fileInput.type ?? 'file',
        language: fileInput.language ?? '',
        extension: path.includes('.') ? path.split('.').pop()! : '',
        directory: path.includes('/') ? path.split('/').slice(0, -1).join('/') : '',
        fileName: path.split('/').pop() ?? path,
        hasContent: Boolean(fileInput.content),
        approxTokens: Math.ceil((fileInput.content?.length ?? 0) / 4),
        contentPreview: fileInput.contentPreview ?? fileInput.content?.slice(0, 200) ?? '',
        contentHash: '',
        // FileSummaryResult fields (empty stubs for semantically-discovered files)
        summary: '',
        keywords: [],
        imports: [],
        exports: [],
        symbolHints: [],
        role: '',
        architectureHints: [],
        isEntrypoint: false,
        embeddingText: '',
        // RankedRepoIndexEntry fields
        score: combinedScore,
        reasons: [`semantic-similarity:${normSemantic.toFixed(3)}`],
      };
      merged.push(stubEntry);
    }
  }

  // --- Sort descending by combined score ------------------------------------
  merged.sort((a, b) => b.score - a.score);

  return { mergedEntries: merged, semanticOnlyPaths, semanticUsed: true };
}
