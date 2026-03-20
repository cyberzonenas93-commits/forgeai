import { createHash } from 'node:crypto';

import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';

import { lookupProviderToken } from './runtime';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface EmbeddingFileInput {
  path: string;
  content: string;
}

export interface ScoredFile {
  path: string;
  score: number;
  contentHash: string;
}

interface StoredEmbeddingDoc {
  path: string;
  contentHash: string;
  embedding: number[];
  indexedAt: Timestamp;
  model: string;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const EMBEDDING_MODEL = 'text-embedding-3-small';
// OpenAI text-embedding-3-small produces 1536-dim vectors.
const EMBEDDING_DIMENSIONS = 1536;
// Maximum characters to embed per file (≈ 12 000 tokens at ~4 chars/token).
const MAX_FILE_CHARS = 48_000;
// Maximum files per batch call to the embeddings API.
const EMBED_BATCH_SIZE = 96;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function contentHash(content: string): string {
  return createHash('sha256').update(content).digest('hex').slice(0, 32);
}

/**
 * Cosine similarity between two equal-length vectors.
 * Returns a value in [-1, 1]; higher is more similar.
 */
function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) return 0;
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i]! * b[i]!;
    normA += a[i]! * a[i]!;
    normB += b[i]! * b[i]!;
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  return denom === 0 ? 0 : dot / denom;
}

function truncateContent(content: string): string {
  if (content.length <= MAX_FILE_CHARS) return content;
  // Keep first 75% + last 25% to retain both header and tail context.
  const head = Math.floor(MAX_FILE_CHARS * 0.75);
  const tail = MAX_FILE_CHARS - head;
  return `${content.slice(0, head)}\n...[truncated]...\n${content.slice(content.length - tail)}`;
}

// ---------------------------------------------------------------------------
// OpenAI Embeddings API
// ---------------------------------------------------------------------------

interface EmbeddingApiResponse {
  data: Array<{ embedding: number[]; index: number }>;
  usage: { prompt_tokens: number; total_tokens: number };
}

async function callEmbeddingsApi(inputs: string[]): Promise<number[][]> {
  const tokenResult = lookupProviderToken('openai');
  if (!tokenResult) {
    throw new Error('OpenAI API key is not configured; cannot generate embeddings.');
  }

  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${tokenResult.token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: EMBEDDING_MODEL,
      input: inputs,
      dimensions: EMBEDDING_DIMENSIONS,
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(`OpenAI embeddings API error ${response.status}: ${body.slice(0, 400)}`);
  }

  const json = (await response.json()) as EmbeddingApiResponse;
  // Sort by index to ensure order matches the input array.
  return json.data
    .slice()
    .sort((a, b) => a.index - b.index)
    .map(item => item.embedding);
}

// ---------------------------------------------------------------------------
// Firestore helpers
// ---------------------------------------------------------------------------

function embeddingDocRef(repoId: string, fileHash: string) {
  return getFirestore()
    .collection('repositories')
    .doc(repoId)
    .collection('embeddings')
    .doc(fileHash);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Embed and store a list of files for a given repo.
 *
 * Skips files whose content hash already has a stored embedding, so this is
 * safe to call repeatedly — only changed/new files are re-embedded.
 *
 * Returns the number of files that were actually (re-)embedded.
 */
export async function indexFileEmbeddings(
  repoId: string,
  files: EmbeddingFileInput[],
): Promise<{ indexed: number; skipped: number }> {
  if (files.length === 0) return { indexed: 0, skipped: 0 };

  const db = getFirestore();

  // 1. Build hash map and determine which files need embedding.
  const fileMap = new Map<string, EmbeddingFileInput & { hash: string }>();
  for (const file of files) {
    const hash = contentHash(file.content);
    if (!fileMap.has(hash)) {
      fileMap.set(hash, { ...file, hash });
    }
  }

  // 2. Batch-read existing embeddings to skip already-indexed hashes.
  const hashes = Array.from(fileMap.keys());
  const existingRefs = hashes.map(h => embeddingDocRef(repoId, h));
  // Firestore getAll is limited to 500 docs; chunk if needed.
  const BATCH_READ = 500;
  const existing = new Set<string>();
  for (let i = 0; i < existingRefs.length; i += BATCH_READ) {
    const chunk = existingRefs.slice(i, i + BATCH_READ);
    const snapshots = await db.getAll(...chunk);
    for (const snap of snapshots) {
      if (snap.exists) existing.add(snap.id);
    }
  }

  const toEmbed = hashes
    .filter(h => !existing.has(h))
    .map(h => fileMap.get(h)!);

  if (toEmbed.length === 0) {
    return { indexed: 0, skipped: hashes.length };
  }

  // 3. Generate embeddings in batches.
  let indexed = 0;
  for (let i = 0; i < toEmbed.length; i += EMBED_BATCH_SIZE) {
    const batch = toEmbed.slice(i, i + EMBED_BATCH_SIZE);
    const inputs = batch.map(f => truncateContent(f.content));
    const embeddings = await callEmbeddingsApi(inputs);

    // 4. Persist to Firestore.
    const writeBatch = db.batch();
    for (let j = 0; j < batch.length; j++) {
      const file = batch[j]!;
      const embedding = embeddings[j];
      if (!embedding) continue;
      const doc: StoredEmbeddingDoc = {
        path: file.path,
        contentHash: file.hash,
        embedding,
        indexedAt: Timestamp.now(),
        model: EMBEDDING_MODEL,
      };
      writeBatch.set(embeddingDocRef(repoId, file.hash), doc);
    }
    await writeBatch.commit();
    indexed += batch.length;
  }

  return { indexed, skipped: existing.size };
}

/**
 * Embed the query string and return the top-K most semantically similar
 * files from the stored embeddings for `repoId`.
 *
 * Throws if OpenAI key is missing; returns [] if no embeddings are stored.
 */
export async function semanticSearch(
  query: string,
  repoId: string,
  topK: number,
): Promise<ScoredFile[]> {
  if (!query.trim() || topK <= 0) return [];

  const db = getFirestore();

  // 1. Fetch all stored embeddings for this repo.
  const embSnap = await db
    .collection('repositories')
    .doc(repoId)
    .collection('embeddings')
    .get();

  if (embSnap.empty) return [];

  // 2. Embed the query.
  const [queryEmbedding] = await callEmbeddingsApi([query.slice(0, MAX_FILE_CHARS)]);
  if (!queryEmbedding) return [];

  // 3. Score all stored embeddings.
  const scored: ScoredFile[] = [];
  for (const doc of embSnap.docs) {
    const data = doc.data() as Partial<StoredEmbeddingDoc>;
    const embedding = data.embedding;
    if (!Array.isArray(embedding) || embedding.length === 0) continue;
    const score = cosineSimilarity(queryEmbedding, embedding);
    scored.push({
      path: data.path ?? doc.id,
      score,
      contentHash: data.contentHash ?? doc.id,
    });
  }

  // 4. Return top-K by descending score.
  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, topK);
}

/**
 * Mark the repo document as embeddings-indexed.
 * Updates `embeddingsIndexed` and `embeddingsLastUpdated`.
 */
export async function markRepoEmbeddingsIndexed(repoId: string): Promise<void> {
  await getFirestore()
    .collection('repositories')
    .doc(repoId)
    .set(
      {
        embeddingsIndexed: true,
        embeddingsLastUpdated: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}
