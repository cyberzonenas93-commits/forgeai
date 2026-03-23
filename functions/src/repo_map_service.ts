import { FieldValue, type Firestore } from 'firebase-admin/firestore';

import { serializeRepoKnowledgeMap, type RepoKnowledgeMap } from './repo_knowledge_map';

export async function persistRepoMapSnapshot(params: {
  db: Firestore;
  repoId: string;
  map: RepoKnowledgeMap;
}) {
  await params.db
    .collection('repositories')
    .doc(params.repoId)
    .collection('contextMaps')
    .doc('current')
    .set(
      {
        ...serializeRepoKnowledgeMap(params.map),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  await params.db.collection('repositories').doc(params.repoId).set(
    {
      contextSizeClass: params.map.sizeClass,
      contextStrategy: params.map.budget.strategyLabel,
      contextExactWholeRepoEligible: params.map.budget.exactWholeRepoEligible,
      contextMapUpdatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}
