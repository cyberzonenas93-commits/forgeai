import { FieldValue, type Firestore } from 'firebase-admin/firestore';

import {
  serializeRepoExecutionRunMemory,
  type RepoExecutionRunMemory,
} from './repo_knowledge_map';

export async function persistExecutionMemorySnapshot(params: {
  db: Firestore;
  ownerId: string;
  taskId: string;
  repoId: string;
  phase: string;
  summary: string;
  memory: RepoExecutionRunMemory | null | undefined;
}) {
  if (!params.memory) {
    return;
  }
  await params.db
    .collection('users')
    .doc(params.ownerId)
    .collection('agentTasks')
    .doc(params.taskId)
    .collection('runtime')
    .doc('executionMemory')
    .set(
      {
        repoId: params.repoId,
        phase: params.phase,
        summary: params.summary,
        memory: serializeRepoExecutionRunMemory(params.memory),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

export async function loadExecutionMemorySnapshot(params: {
  db: Firestore;
  ownerId: string;
  taskId: string;
}) {
  const snapshot = await params.db
    .collection('users')
    .doc(params.ownerId)
    .collection('agentTasks')
    .doc(params.taskId)
    .collection('runtime')
    .doc('executionMemory')
    .get();
  if (!snapshot.exists) {
    return null;
  }
  const data = snapshot.data() as { memory?: unknown } | undefined;
  return data?.memory ?? null;
}
