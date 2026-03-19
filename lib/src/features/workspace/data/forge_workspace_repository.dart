// ignore_for_file: use_null_aware_elements, prefer_initializing_formals

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/branding/app_branding.dart';
import '../../../shared/forge_models.dart';
import '../../auth/domain/auth_account.dart';
import '../../auth/domain/auth_provider_kind.dart';
import '../domain/forge_workspace_entities.dart';

class ForgeWorkspaceRepository {
  ForgeWorkspaceRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<void> ensureBootstrap(AuthAccount account) async {
    final userRef = _firestore.collection('users').doc(account.id);
    final connectionRef = userRef.collection('connections');
    final notificationPreferencesRef = userRef
        .collection('notificationPreferences')
        .doc('default');

    await userRef.set({
      'displayName': account.displayName,
      'email': account.email,
      'photoUrl': account.avatarUrl,
      'authProviders': account.linkedProviders
          .map((item) => item.name)
          .toList(),
      'isGuest': account.isGuest,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final existingConnections = await connectionRef.limit(1).get();
    if (existingConnections.docs.isEmpty && account.provider.name != 'guest') {
      await connectionRef.doc(account.provider.name).set({
        'provider': account.provider.name,
        'account': account.email,
        'scopeSummary': '${account.provider.label} identity sign-in',
        'status': 'connected',
        'lastChecked': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // Wallet is created and updated by the backend (syncUserProfile / updateWalletState).
    // Only the allowlisted email gets unlimited; others use paywall/subscription.

    await notificationPreferencesRef.set({
      ...ForgeNotificationPreferences.defaults.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<ForgeRepository>> watchRepositories(String ownerId) {
    return _firestore
        .collection('repositories')
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => _forgeRepositoryFromDoc(doc))
              .toList();
          items.sort((a, b) => a.repoLabel.compareTo(b.repoLabel));
          return items;
        });
  }

  Stream<List<ForgeConnection>> watchConnections(String ownerId) {
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('connections')
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => _forgeConnectionFromDoc(doc))
              .toList();
          items.sort((a, b) => a.providerLabel.compareTo(b.providerLabel));
          return items;
        });
  }

  Stream<ForgeNotificationPreferences> watchNotificationPreferences(
    String ownerId,
  ) {
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('notificationPreferences')
        .doc('default')
        .snapshots()
        .map((doc) => ForgeNotificationPreferences.fromMap(doc.data()));
  }

  Future<void> saveNotificationPreferences({
    required String ownerId,
    required ForgeNotificationPreferences preferences,
  }) {
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('notificationPreferences')
        .doc('default')
        .set({
          ...preferences.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> upsertPushDevice({
    required String ownerId,
    required String token,
    required String platform,
    required ForgePushPermissionStatus permissionStatus,
  }) {
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('devices')
        .doc(_safeDocId(token))
        .set({
          'token': token,
          'platform': platform,
          'permissionStatus': permissionStatus.name,
          'lastSeenAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> removePushDevice({
    required String ownerId,
    required String token,
  }) {
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('devices')
        .doc(_safeDocId(token))
        .delete();
  }

  Stream<List<ForgeActivityEntry>> watchActivities(String ownerId) {
    return _firestore
        .collection('activity')
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.toList()
            ..sort((a, b) {
              final aTime = _asDateTime(a.data()['createdAt']);
              final bTime = _asDateTime(b.data()['createdAt']);
              if (aTime == null && bTime == null) {
                return 0;
              }
              if (aTime == null) {
                return 1;
              }
              if (bTime == null) {
                return -1;
              }
              return bTime.compareTo(aTime);
            });
          return docs.map((doc) => _forgeActivityFromDoc(doc)).toList();
        });
  }

  Stream<List<ForgeCheckRun>> watchChecks(String ownerId) {
    return _firestore
        .collection('checksRuns')
        .where('ownerId', isEqualTo: ownerId)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs.map(_forgeCheckFromDoc).toList();
          items.sort((a, b) => b.progress.compareTo(a.progress));
          return items;
        });
  }

  /// Wallet state is owned by the backend. Only the allowlisted user
  /// (e.g. cyberzonenas93@gmail.com) gets unlimited; others use paywall/subscription.
  Stream<ForgeTokenWallet> watchWallet(String ownerId) {
    return _firestore.collection('wallets').doc(ownerId).snapshots().map((doc) {
      final data = doc.data() ?? const <String, dynamic>{};
      return ForgeTokenWallet(
        planName: (data['planName'] as String?) ?? 'Free',
        balance: _asDouble(data['balance']),
        monthlyAllowance: _asDouble(data['monthlyAllowance']) == 0
            ? _asDouble(data['monthlyLimit'])
            : _asDouble(data['monthlyAllowance']),
        spentThisWeek: _asDouble(data['spentThisWeek']) == 0
            ? _asDouble(data['monthlyUsed'])
            : _asDouble(data['spentThisWeek']),
        nextReset: (data['nextReset'] as String?) ?? 'Mon, 09:00',
        currencySymbol:
            (data['currencySymbol'] as String?) ??
            (data['currency'] as String?) ??
            'tokens',
      );
    });
  }

  Stream<List<ForgeTokenLog>> watchTokenLogs(String ownerId) {
    return _firestore
        .collection('wallets')
        .doc(ownerId)
        .collection('usage')
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.toList()
            ..sort((a, b) {
              final aTime = _asDateTime(a.data()['createdAt']);
              final bTime = _asDateTime(b.data()['createdAt']);
              if (aTime == null && bTime == null) {
                return 0;
              }
              if (aTime == null) {
                return 1;
              }
              if (bTime == null) {
                return -1;
              }
              return bTime.compareTo(aTime);
            });
          return docs.map(_forgeTokenLogFromDoc).toList();
        });
  }

  Stream<List<ForgeFileNode>> watchFiles({
    required String repoId,
    String? selectedPath,
  }) {
    return _firestore
        .collection('repositories')
        .doc(repoId)
        .collection('files')
        .snapshots()
        .map((snapshot) => _buildFileTree(snapshot.docs, selectedPath));
  }

  Stream<List<ForgePromptThread>> watchPromptThreads(String ownerId) {
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('promptThreads')
        .snapshots()
        .map((snapshot) {
          final docs = snapshot.docs.toList()
            ..sort((a, b) {
              final aTime = _asDateTime(a.data()['updatedAt']);
              final bTime = _asDateTime(b.data()['updatedAt']);
              if (aTime == null && bTime == null) {
                return a.id.compareTo(b.id);
              }
              if (aTime == null) {
                return 1;
              }
              if (bTime == null) {
                return -1;
              }
              return bTime.compareTo(aTime);
            });
          return docs.map(_forgePromptThreadFromDoc).toList();
        });
  }

  Future<void> savePromptThread({
    required String ownerId,
    required ForgePromptThread thread,
  }) {
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('promptThreads')
        .doc(thread.id)
        .set({
          'title': thread.title,
          'repoId': thread.repoId,
          'updatedAt': Timestamp.fromDate(thread.updatedAt),
          'messages': thread.messages
              .map(
                (message) => {
                  'id': message.id,
                  'role': message.role,
                  'text': message.text,
                  'createdAt': Timestamp.fromDate(message.createdAt),
                },
              )
              .toList(),
        }, SetOptions(merge: true));
  }

  Future<ForgeFileDocument?> loadFile({
    required String repoId,
    required String filePath,
  }) async {
    final fileRef = _fileRef(repoId, filePath);
    final existing = await fileRef.get();
    if (!existing.exists ||
        (existing.data()?['content'] as String?)?.isEmpty != false) {
      try {
        final callable = _functions.httpsCallable('loadRepositoryFile');
        await callable.call({'repoId': repoId, 'filePath': filePath});
      } on FirebaseFunctionsException {
        // Fall back to cached content below.
      }
    }

    final snapshot = await fileRef.get();
    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data() ?? const <String, dynamic>{};
    return ForgeFileDocument(
      repoId: repoId,
      path: (data['path'] as String?) ?? filePath,
      language: (data['language'] as String?) ?? _languageFromPath(filePath),
      content: (data['content'] as String?) ?? '',
      originalContent:
          (data['baseContent'] as String?) ??
          (data['content'] as String?) ??
          '',
      updatedAt: _asDateTime(data['updatedAt']),
      sha: data['sha'] as String?,
    );
  }

  Future<void> saveFile({
    required String ownerId,
    required ForgeFileDocument document,
  }) async {
    final fileRef = _fileRef(document.repoId, document.path);
    await fileRef.set({
      'path': document.path,
      'language': document.language,
      'content': document.content,
      'baseContent': document.originalContent,
      'sha': document.sha,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _writeActivity(
      ownerId: ownerId,
      kind: 'repo',
      message: 'Saved ${document.path} draft changes.',
      accent: 'repo',
    );
  }

  Future<void> createFileDraft({
    required String ownerId,
    required String repoId,
    required String filePath,
    String content = '',
  }) async {
    final normalizedPath = _normalizeRepoPath(filePath);
    final fileRef = _fileRef(repoId, normalizedPath);
    await fileRef.set({
      'path': normalizedPath,
      'language': _languageFromPath(normalizedPath),
      'content': content,
      'baseContent': content,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeActivity(
      ownerId: ownerId,
      kind: 'repo',
      message: 'Created $normalizedPath.',
      accent: 'repo',
    );
  }

  Future<void> createFolderDraft({
    required String ownerId,
    required String repoId,
    required String folderPath,
  }) async {
    final normalizedFolder = _normalizeRepoPath(folderPath, isFolder: true);
    final markerPath = '$normalizedFolder.keep';
    final markerRef = _fileRef(repoId, markerPath);
    await markerRef.set({
      'path': markerPath,
      'language': 'Text',
      'content': '',
      'baseContent': '',
      'updatedAt': FieldValue.serverTimestamp(),
      'isFolderMarker': true,
    }, SetOptions(merge: true));
    await _writeActivity(
      ownerId: ownerId,
      kind: 'repo',
      message: 'Created folder $normalizedFolder.',
      accent: 'repo',
    );
  }

  Future<void> renamePath({
    required String ownerId,
    required String repoId,
    required String oldPath,
    required String newPath,
    required bool isFolder,
  }) async {
    final oldNormalized = _normalizeRepoPath(oldPath, isFolder: isFolder);
    final newNormalized = _normalizeRepoPath(newPath, isFolder: isFolder);
    if (oldNormalized == newNormalized) {
      return;
    }
    final filesRef = _firestore
        .collection('repositories')
        .doc(repoId)
        .collection('files');
    final snapshot = await filesRef.get();
    final batch = _firestore.batch();
    var changed = 0;
    for (final doc in snapshot.docs) {
      final path = (doc.data()['path'] as String?) ?? '';
      final matches = isFolder
          ? path.startsWith(oldNormalized)
          : path == oldNormalized;
      if (!matches) {
        continue;
      }
      final nextPath = isFolder
          ? '$newNormalized${path.substring(oldNormalized.length)}'
          : newNormalized;
      final nextRef = filesRef.doc(_safeDocId(nextPath));
      final payload = <String, dynamic>{...doc.data()};
      payload['path'] = nextPath;
      payload['updatedAt'] = FieldValue.serverTimestamp();
      batch.set(nextRef, payload, SetOptions(merge: true));
      if (nextRef.path != doc.reference.path) {
        batch.delete(doc.reference);
      }
      changed += 1;
    }
    if (changed == 0) {
      return;
    }
    await batch.commit();
    await _writeActivity(
      ownerId: ownerId,
      kind: 'repo',
      message:
          'Renamed ${isFolder ? 'folder' : 'file'} $oldNormalized to $newNormalized.',
      accent: 'repo',
    );
  }

  Future<void> deletePath({
    required String ownerId,
    required String repoId,
    required String path,
    required bool isFolder,
  }) async {
    final normalized = _normalizeRepoPath(path, isFolder: isFolder);
    final filesRef = _firestore
        .collection('repositories')
        .doc(repoId)
        .collection('files');
    final snapshot = await filesRef.get();
    final batch = _firestore.batch();
    var deleted = 0;
    for (final doc in snapshot.docs) {
      final filePath = (doc.data()['path'] as String?) ?? '';
      final matches = isFolder
          ? filePath.startsWith(normalized)
          : filePath == normalized;
      if (!matches) {
        continue;
      }
      batch.delete(doc.reference);
      deleted += 1;
    }
    if (deleted == 0) {
      return;
    }
    await batch.commit();
    await _writeActivity(
      ownerId: ownerId,
      kind: 'repo',
      message: 'Deleted ${isFolder ? 'folder' : 'file'} $normalized.',
      accent: 'repo',
    );
  }

  Future<ForgeChangeRequest> runAiAction({
    required String ownerId,
    required String repoId,
    required String filePath,
    required ForgeAiProvider provider,
    required String prompt,
  }) async {
    final callable = _functions.httpsCallable('suggestChange');
    final result = await callable.call({
      'repoId': repoId,
      'filePath': filePath,
      'provider': provider.name,
      'prompt': prompt,
      'changeKind': 'ai',
    });

    final payload = Map<String, dynamic>.from(
      (result.data as Map<Object?, Object?>).map(
        (key, value) => MapEntry('$key', value),
      ),
    );
    final changeRequestId = payload['changeRequestId'] as String?;
    if (changeRequestId == null) {
      throw StateError('AI result did not include a change request id.');
    }
    final changeRequest = await loadChangeRequest(changeRequestId);
    if (changeRequest != null) {
      return changeRequest;
    }
    throw StateError('Unable to load generated change request.');
  }

  Future<ForgeChangeRequest?> loadChangeRequest(String changeRequestId) async {
    final snapshot = await _firestore
        .collection('changeRequests')
        .doc(changeRequestId)
        .get();
    if (!snapshot.exists) {
      return null;
    }
    return _forgeChangeRequestFromDoc(snapshot);
  }

  Future<void> approveChangeRequest({
    required String ownerId,
    required ForgeChangeRequest changeRequest,
    required ForgeFileDocument currentDocument,
  }) async {
    await _fileRef(changeRequest.repoId, changeRequest.filePath).set({
      'path': currentDocument.path,
      'language': currentDocument.language,
      'content': changeRequest.afterContent,
      'baseContent': currentDocument.originalContent,
      'sha': currentDocument.sha,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore.collection('changeRequests').doc(changeRequest.id).set({
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _writeActivity(
      ownerId: ownerId,
      kind: 'ai',
      message: 'Approved AI change for ${changeRequest.filePath}.',
      accent: 'ai',
    );
  }

  Future<void> rejectChangeRequest({
    required String ownerId,
    required ForgeChangeRequest changeRequest,
  }) async {
    await _firestore.collection('changeRequests').doc(changeRequest.id).set({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _writeActivity(
      ownerId: ownerId,
      kind: 'ai',
      message: 'Rejected AI change for ${changeRequest.filePath}.',
      accent: 'ai',
    );
  }

  Future<void> connectRepository({
    required String ownerId,
    required ForgeConnectRepositoryDraft draft,
  }) async {
    final callable = _functions.httpsCallable('connectRepository');
    await callable.call({
      'provider': draft.provider,
      'repository': draft.repository,
      'defaultBranch': draft.defaultBranch,
      if ((draft.accessToken ?? '').trim().isNotEmpty)
        'accessToken': draft.accessToken!.trim(),
      if ((draft.apiBaseUrl ?? '').trim().isNotEmpty)
        'apiBaseUrl': draft.apiBaseUrl!.trim(),
    });

    await _firestore
        .collection('users')
        .doc(ownerId)
        .collection('connections')
        .doc(draft.provider)
        .set({
          'provider': draft.provider,
          'account': draft.repository.split('/').first,
          'scopeSummary':
              'Repos, pull requests, commits, and checks',
          'status': 'connected',
          'lastChecked': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    await _writeActivity(
      ownerId: ownerId,
      kind: 'repo',
      message: 'Connected ${draft.repository} (${draft.provider}).',
      accent: 'repo',
    );
  }

  Future<ForgeCreateAiProjectResult> createProjectRepository({
    required String ownerId,
    required String provider,
    required String repoName,
    required String idea,
    String? stackHint,
    bool isPrivate = true,
    String? namespace,
    String? accessToken,
    String? apiBaseUrl,
  }) async {
    final callable = _functions.httpsCallable('createProjectRepository');
    final result = await callable.call(<String, dynamic>{
      'provider': provider,
      'repoName': repoName.trim(),
      'idea': idea.trim(),
      if (stackHint != null && stackHint.trim().isNotEmpty)
        'stackHint': stackHint.trim(),
      'isPrivate': isPrivate,
      if (namespace != null && namespace.trim().isNotEmpty)
        'namespace': namespace.trim(),
      if (accessToken != null && accessToken.trim().isNotEmpty)
        'accessToken': accessToken.trim(),
      if (apiBaseUrl != null && apiBaseUrl.trim().isNotEmpty)
        'apiBaseUrl': apiBaseUrl.trim(),
    });
    final raw = result.data;
    if (raw is! Map) {
      throw const FormatException('createProjectRepository: invalid response');
    }
    final parsed = ForgeCreateAiProjectResult.fromCallableData(
      Map<Object?, Object?>.from(raw),
    );

    final slash = parsed.fullName.indexOf('/');
    if (slash > 0) {
      final account = parsed.fullName.substring(0, slash);
      await _firestore
          .collection('users')
          .doc(ownerId)
          .collection('connections')
          .doc(provider)
          .set({
            'provider': provider,
            'account': account,
            'scopeSummary':
                'Repos, pull requests, commits, and checks',
            'status': 'connected',
            'lastChecked': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }

    await _writeActivity(
      ownerId: ownerId,
      kind: 'repo',
      message:
          'Created ${parsed.fullName} with AI scaffold (${parsed.fileCount} files).',
      accent: 'repo',
    );
    return parsed;
  }

  Future<List<ForgeAvailableRepository>> listProviderRepositories({
    required String provider,
    String? query,
    String? apiBaseUrl,
  }) async {
    final callable = _functions.httpsCallable('listProviderRepositories');
    final result = await callable.call({
      'provider': provider,
      if ((query ?? '').trim().isNotEmpty) 'query': query!.trim(),
      if ((apiBaseUrl ?? '').trim().isNotEmpty)
        'apiBaseUrl': apiBaseUrl!.trim(),
    });

    final data = result.data;
    if (data is! Map) {
      return const <ForgeAvailableRepository>[];
    }
    final rawRepositories = data['repositories'];
    if (rawRepositories is! List) {
      return const <ForgeAvailableRepository>[];
    }
    return rawRepositories
        .whereType<Map>()
        .map((item) {
          final owner = (item['owner'] as String?)?.trim() ?? '';
          final name = (item['name'] as String?)?.trim() ?? '';
          final fullNameRaw =
              (item['fullName'] as String?)?.trim() ??
              (item['full_name'] as String?)?.trim() ??
              (owner.isNotEmpty && name.isNotEmpty ? '$owner/$name' : '');
          final fullName = fullNameRaw.isNotEmpty
              ? fullNameRaw
              : (owner.isNotEmpty && name.isNotEmpty ? '$owner/$name' : '');
          return ForgeAvailableRepository(
            provider: (item['provider'] as String?) ?? provider,
            owner: owner,
            name: name,
            fullName: fullName,
            defaultBranch:
                (item['defaultBranch'] as String?)?.trim() ??
                (item['default_branch'] as String?)?.trim() ??
                'main',
            description: (item['description'] as String?)?.trim(),
            htmlUrl:
                (item['htmlUrl'] as String?)?.trim() ??
                (item['html_url'] as String?)?.trim(),
            isPrivate:
                item['isPrivate'] as bool? ??
                item['is_private'] as bool? ??
                true,
          );
        })
        .where(
          (item) =>
              item.fullName.isNotEmpty ||
              (item.owner.isNotEmpty && item.name.isNotEmpty),
        )
        .toList();
  }

  Future<void> syncRepository(String repoId) async {
    final callable = _functions.httpsCallable('syncRepository');
    await callable.call({'repoId': repoId});
  }

  Future<ForgeAskRepoResult> askRepo({
    String? repoId,
    required String prompt,
    String provider = 'openai',
    List<ForgePromptMessage> history = const <ForgePromptMessage>[],
    List<ForgePromptMediaAttachment> media =
        const <ForgePromptMediaAttachment>[],
    bool dangerMode = false,
  }) async {
    final callable = _functions.httpsCallable('askRepo');
    final result = await callable.call<Map<Object?, Object?>>({
      if (repoId != null && repoId.isNotEmpty) 'repoId': repoId,
      'prompt': prompt,
      'provider': provider,
      if (history.isNotEmpty)
        'history': history
            .map((message) => {'role': message.role, 'text': message.text})
            .toList(),
      if (media.isNotEmpty)
        'media': media
            .map(
              (m) => {
                'fileName': m.fileName,
                'mimeType': m.mimeType,
                'dataBase64': m.dataBase64,
              },
            )
            .toList(),
      'dangerMode': dangerMode,
    });
    final data = result.data;
    final reply = data['reply'];
    final trace = data['trace'];
    final inspectedFiles = <String>[];
    final plannedEdits = <ForgePromptPlannedEdit>[];
    final appliedEdits = <ForgePromptAppliedEdit>[];
    if (trace is Map<Object?, Object?>) {
      final traceMap = trace.map((key, value) => MapEntry('$key', value));
      final inspectedRaw = traceMap['inspectedFiles'];
      if (inspectedRaw is List) {
        for (final item in inspectedRaw) {
          if (item is String && item.trim().isNotEmpty) {
            inspectedFiles.add(item.trim());
          }
        }
      }
      final editsRaw = traceMap['plannedEdits'];
      if (editsRaw is List) {
        for (final item in editsRaw) {
          if (item is Map) {
            final map = item.map((key, value) => MapEntry('$key', value));
            final path = (map['path'] as String?)?.trim() ?? '';
            final action = (map['action'] as String?)?.trim() ?? 'modify';
            final rationale = (map['rationale'] as String?)?.trim() ?? '';
            if (path.isEmpty) {
              continue;
            }
            plannedEdits.add(
              ForgePromptPlannedEdit(
                path: path,
                action: action,
                rationale: rationale,
              ),
            );
          }
        }
      }
      final appliedRaw = traceMap['appliedEdits'];
      if (appliedRaw is List) {
        for (final item in appliedRaw) {
          if (item is Map) {
            final map = item.map((key, value) => MapEntry('$key', value));
            final path = (map['path'] as String?)?.trim() ?? '';
            final action = (map['action'] as String?)?.trim() ?? '';
            if (path.isEmpty) {
              continue;
            }
            appliedEdits.add(
              ForgePromptAppliedEdit(path: path, action: action),
            );
          }
        }
      }
    }
    return ForgeAskRepoResult(
      reply: reply is String ? reply : '',
      inspectedFiles: inspectedFiles,
      plannedEdits: plannedEdits,
      appliedEdits: appliedEdits,
    );
  }

  Future<void> submitGitAction({
    required String repoId,
    required String provider,
    required ForgeGitActionType actionType,
    List<Map<String, String?>> fileChanges = const <Map<String, String?>>[],
    String? branchName,
    String? commitMessage,
    String? pullRequestTitle,
    String? pullRequestDescription,
    String? mergeMethod,
  }) async {
    final callable = _functions.httpsCallable('submitGitAction');
    await callable.call({
      'repoId': repoId,
      'provider': provider,
      'actionType': _gitActionName(actionType),
      'confirmed': true,
      if (fileChanges.isNotEmpty) 'fileChanges': fileChanges,
      if (branchName != null) 'branchName': branchName,
      if (commitMessage != null) 'commitMessage': commitMessage,
      if (pullRequestTitle != null) 'prTitle': pullRequestTitle,
      if (pullRequestDescription != null)
        'prDescription': pullRequestDescription,
      if (mergeMethod != null) 'mergeMethod': mergeMethod,
    });
  }

  Future<List<ForgeRepoWorkflow>> listRepoWorkflows(String repoId) async {
    final callable = _functions.httpsCallable('listRepoWorkflows');
    final result = await callable.call<Map<String, dynamic>>({
      'repoId': repoId,
    });
    final data = result.data;
    final list = data['workflows'] as List<dynamic>? ?? const [];
    return list
        .map((e) {
          final m = e as Map<String, dynamic>?;
          if (m == null) return null;
          final path = m['path'] as String?;
          if (path == null) return null;
          return ForgeRepoWorkflow(
            id: m['id'] ?? path,
            name: m['name'] as String? ?? path,
            path: path,
          );
        })
        .whereType<ForgeRepoWorkflow>()
        .toList();
  }

  Future<Map<String, dynamic>> submitCheckAction({
    required String repoId,
    required String provider,
    required ForgeCheckActionType actionType,
    required String workflowName,
  }) async {
    final callable = _functions.httpsCallable('submitCheckAction');
    final result = await callable.call({
      'repoId': repoId,
      'provider': provider,
      'actionType': _checkActionName(actionType),
      'workflowName': workflowName,
      'confirmed': true,
    });
    final data = result.data;
    if (data is Map) {
      return data.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  Future<void> reserveTokens({
    required String repoId,
    required String actionType,
    required int amount,
    required int costPreview,
    required String provider,
  }) async {
    final callable = _functions.httpsCallable('reserveTokens');
    await callable.call({
      'repoId': repoId,
      'actionType': actionType,
      'amount': amount,
      'costPreview': costPreview,
      'provider': provider,
    });
  }

  Future<void> releaseTokens({
    required String repoId,
    required String provider,
    required int amount,
    required int costPreview,
    String actionType = 'release',
    String? reason,
  }) async {
    final callable = _functions.httpsCallable('releaseTokens');
    await callable.call({
      'repoId': repoId,
      'amount': amount,
      'provider': provider,
      'costPreview': costPreview,
      'actionType': actionType,
      if (reason != null) 'reason': reason,
    });
  }

  Future<void> captureTokens({
    required String repoId,
    required String provider,
    required int amount,
    required int costPreview,
    String actionType = 'capture',
    String? reason,
  }) async {
    final callable = _functions.httpsCallable('captureTokens');
    await callable.call({
      'repoId': repoId,
      'amount': amount,
      'provider': provider,
      'costPreview': costPreview,
      'actionType': actionType,
      if (reason != null) 'reason': reason,
    });
  }

  Future<void> _writeActivity({
    required String ownerId,
    required String kind,
    required String message,
    required String accent,
  }) {
    return _firestore.collection('activity').add({
      'ownerId': ownerId,
      'kind': kind,
      'subjectId': accent,
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  DocumentReference<Map<String, dynamic>> _fileRef(String repoId, String path) {
    return _firestore
        .collection('repositories')
        .doc(repoId)
        .collection('files')
        .doc(_safeDocId(path));
  }

  ForgeRepository _forgeRepositoryFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final fullName = (data['fullName'] as String?) ?? 'unknown/repository';
    final segments = fullName.split('/');
    final owner = segments.isNotEmpty ? segments.first : 'unknown';
    final name = segments.length > 1 ? segments.sublist(1).join('/') : fullName;
    final lastSync = _asDateTime(data['lastSyncedAt']);
    final branchesRaw = data['branches'];
    final branchesList = branchesRaw is List
        ? (branchesRaw).map((e) => e is String ? e : e.toString()).toList()
        : <String>[];
    return ForgeRepository(
      id: doc.id,
      name: name,
      owner: owner,
      provider: ForgeProvider.github,
      language: (data['language'] as String?) ?? 'Mixed',
      description:
          (data['description'] as String?) ??
          'Connected repository ready for mobile review.',
      defaultBranch: (data['defaultBranch'] as String?) ?? 'main',
      status: (data['syncStatus'] as String?) ?? 'Connected',
      openPullRequests: (data['openPullRequests'] as num?)?.toInt() ?? 0,
      openMergeRequests: (data['openMergeRequests'] as num?)?.toInt() ?? 0,
      changedFiles:
          (data['changedFiles'] as num?)?.toInt() ??
          (data['filesCount'] as num?)?.toInt() ??
          0,
      lastSynced: lastSync == null
          ? const Duration(minutes: 0)
          : DateTime.now().difference(lastSync),
      stars: (data['stars'] as num?)?.toInt() ?? 0,
      isProtected: (data['isProtected'] as bool?) ?? false,
      branches: branchesList,
      htmlUrl: (data['htmlUrl'] as String?)?.trim(),
    );
  }

  ForgeConnection _forgeConnectionFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ForgeConnection(
      provider: ForgeProvider.github,
      account: (data['account'] as String?) ?? doc.id,
      scopeSummary:
          (data['scopeSummary'] as String?) ??
          'Repository metadata, diffs, commits, pull requests, and checks',
      status: _connectionStatusFromString(data['status'] as String?),
      lastChecked: _formatTimestamp(_asDateTime(data['lastChecked'])),
    );
  }

  ForgeActivityEntry _forgeActivityFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final timestamp = _asDateTime(data['createdAt']) ?? DateTime.now();
    final kind = (data['kind'] as String?) ?? 'repo';
    final config = _activityStyle(kind);
    return ForgeActivityEntry(
      title: config.$1,
      subtitle: (data['message'] as String?) ?? 'Workspace activity updated.',
      timestamp: _formatTimestamp(timestamp),
      icon: config.$2,
      accent: config.$3,
    );
  }

  ForgeCheckRun _forgeCheckFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final status = _checkStatusFromString(data['status'] as String?);
    final startedAt = _asDateTime(data['createdAt']);
    return ForgeCheckRun(
      name: (data['workflowName'] as String?) ?? 'CI workflow',
      status: status,
      summary:
          (data['summary'] as String?) ??
          'Queued from $kAppDisplayName for explicit CI execution.',
      duration: _formatTimestamp(startedAt),
      logsAvailable:
          ((data['logs'] as List<dynamic>?)?.isNotEmpty ?? false) ||
          (data['logsUrl'] as String?) != null,
      progress: switch (status) {
        ForgeCheckStatus.queued => 0.12,
        ForgeCheckStatus.running => 0.65,
        ForgeCheckStatus.passed => 1,
        ForgeCheckStatus.failed => 1,
      },
      logsUrl: data['logsUrl'] as String?,
    );
  }

  ForgeTokenLog _forgeTokenLogFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ForgeTokenLog(
      action: (data['actionType'] as String?) ?? 'AI action',
      cost: '${(data['amount'] as num?)?.toInt() ?? 0}',
      repo: (data['repoId'] as String?) ?? 'Workspace',
      timestamp: _formatTimestamp(_asDateTime(data['createdAt'])),
    );
  }

  ForgeChangeRequest _forgeChangeRequestFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final beforeContent =
        (data['beforeContent'] as String?) ?? (data['before'] as String?) ?? '';
    final afterContent =
        (data['afterContent'] as String?) ?? (data['after'] as String?) ?? '';
    final diffPayload =
        (data['diffLines'] as List<dynamic>? ?? const <dynamic>[])
            .map(
              (line) => ForgeDiffLine(
                prefix:
                    (line as Map<String, dynamic>)['prefix'] as String? ?? '+',
                line: line['line'] as String? ?? '',
                isAddition: (line['isAddition'] as bool?) ?? true,
              ),
            )
            .toList();
    return ForgeChangeRequest(
      id: doc.id,
      repoId: (data['repoId'] as String?) ?? '',
      filePath: (data['filePath'] as String?) ?? '',
      provider: _aiProviderFromString(data['provider'] as String?),
      prompt: (data['prompt'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'draft',
      summary:
          (data['summary'] as String?) ??
          'Review the proposed code changes before committing.',
      beforeContent: beforeContent,
      afterContent: afterContent,
      diffLines: diffPayload.isNotEmpty
          ? diffPayload
          : _buildFallbackDiffLines(beforeContent, afterContent),
      estimatedTokens: (data['estimatedTokens'] as num?)?.toInt() ?? 0,
    );
  }

  ForgePromptThread _forgePromptThreadFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final messagesRaw = data['messages'] as List<dynamic>? ?? const <dynamic>[];
    final messages = messagesRaw.map((item) {
      final map = item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item as Map);
      return ForgePromptMessage(
        id: (map['id'] as String?) ?? '${doc.id}-${messagesRaw.indexOf(item)}',
        role: (map['role'] as String?) ?? 'assistant',
        text: (map['text'] as String?) ?? '',
        createdAt: _asDateTime(map['createdAt']) ?? DateTime.now(),
      );
    }).toList();
    return ForgePromptThread(
      id: doc.id,
      title: (data['title'] as String?) ?? 'Thread',
      repoId: data['repoId'] as String?,
      messages: messages,
      updatedAt: _asDateTime(data['updatedAt']) ?? DateTime.now(),
    );
  }

  List<ForgeFileNode> _buildFileTree(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String? selectedPath,
  ) {
    final root = <String, _MutableFolder>{};
    for (final doc in docs) {
      final data = doc.data();
      final path = (data['path'] as String?) ?? Uri.decodeComponent(doc.id);
      final parts = path.split('/');
      var folders = root;
      var folderPrefix = '';
      for (var index = 0; index < parts.length; index++) {
        final segment = parts[index];
        final isLeaf = index == parts.length - 1;
        if (isLeaf) {
          if (segment == '.keep') {
            break;
          }
          folders.putIfAbsent(
            segment,
            () => _MutableFolder.file(
              ForgeFileNode(
                name: segment,
                path: path,
                language:
                    (data['language'] as String?) ?? _languageFromPath(path),
                sizeLabel:
                    '${((data['content'] as String?) ?? '').length.clamp(0, 99999)} chars',
                changeLabel:
                    ((data['content'] as String?) ?? '') ==
                        ((data['baseContent'] as String?) ?? '')
                    ? 'Saved'
                    : 'Draft',
                isSelected: selectedPath == path,
              ),
            ),
          );
        } else {
          final nextFolderPath = folderPrefix.isEmpty
              ? '$segment/'
              : '$folderPrefix$segment/';
          final folder = folders.putIfAbsent(
            segment,
            () => _MutableFolder.folder(segment, nextFolderPath),
          );
          folderPrefix = nextFolderPath;
          folders = folder.children;
        }
      }
    }

    return root.values.map((item) => item.toNode()).toList()..sort((a, b) {
      if (a.isFolder != b.isFolder) {
        return a.isFolder ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
  }

  DateTime? _asDateTime(Object? raw) {
    if (raw is Timestamp) {
      return raw.toDate();
    }
    return null;
  }

  double _asDouble(Object? value) {
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    return 0;
  }

  String _formatTimestamp(DateTime? dateTime) {
    if (dateTime == null) {
      return 'just now';
    }
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }
    return DateFormat('MMM d, HH:mm').format(dateTime);
  }

  ForgeConnectionStatus _connectionStatusFromString(String? value) {
    return switch (value) {
      'pending' => ForgeConnectionStatus.pending,
      'disconnected' => ForgeConnectionStatus.disconnected,
      _ => ForgeConnectionStatus.connected,
    };
  }

  ForgeCheckStatus _checkStatusFromString(String? value) {
    return switch (value) {
      'running' => ForgeCheckStatus.running,
      'passed' => ForgeCheckStatus.passed,
      'failed' => ForgeCheckStatus.failed,
      _ => ForgeCheckStatus.queued,
    };
  }

  ForgeAiProvider _aiProviderFromString(String? value) {
    return switch (value) {
      'anthropic' => ForgeAiProvider.anthropic,
      'gemini' => ForgeAiProvider.gemini,
      _ => ForgeAiProvider.openai,
    };
  }

  (String, IconData, Color) _activityStyle(String kind) {
    switch (kind) {
      case 'ai':
      case 'ai_suggestion':
        return (
          'AI change',
          Icons.auto_awesome_rounded,
          const Color(0xFF60A5FA),
        );
      case 'git_action':
      case 'commit':
        return (
          'Git action',
          Icons.call_split_rounded,
          const Color(0xFFF59E0B),
        );
      case 'check_action':
      case 'checks':
        return ('Checks', Icons.rule_folder_rounded, const Color(0xFF22C55E));
      case 'token_reserve':
      case 'token_capture':
      case 'wallet':
        return (
          'Token usage',
          Icons.account_balance_wallet_rounded,
          const Color(0xFFE879F9),
        );
      default:
        return (
          'Repository',
          Icons.folder_copy_rounded,
          const Color(0xFF94A3B8),
        );
    }
  }

  String _gitActionName(ForgeGitActionType actionType) {
    return switch (actionType) {
      ForgeGitActionType.createBranch => 'create_branch',
      ForgeGitActionType.commit => 'commit',
      ForgeGitActionType.openPullRequest => 'open_pr',
      ForgeGitActionType.mergePullRequest => 'merge_pr',
    };
  }

  String _checkActionName(ForgeCheckActionType actionType) {
    return switch (actionType) {
      ForgeCheckActionType.runTests => 'run_tests',
      ForgeCheckActionType.runLint => 'run_lint',
      ForgeCheckActionType.buildProject => 'build_project',
    };
  }

  String _languageFromPath(String path) {
    final extension = path.split('.').last.toLowerCase();
    return switch (extension) {
      'dart' => 'Dart',
      'ts' || 'tsx' => 'TypeScript',
      'js' || 'jsx' => 'JavaScript',
      'yml' || 'yaml' => 'YAML',
      'md' => 'Markdown',
      'json' => 'JSON',
      'swift' => 'Swift',
      _ => 'Text',
    };
  }

  String _safeDocId(String value) {
    return Uri.encodeComponent(value).replaceAll('.', '%2E');
  }

  String _normalizeRepoPath(String input, {bool isFolder = false}) {
    final trimmed = input.trim().replaceAll('\\', '/');
    final parts = trimmed
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != '.')
        .toList();
    if (parts.any((part) => part == '..')) {
      throw ArgumentError('Path cannot contain "..".');
    }
    final joined = parts.join('/');
    if (joined.isEmpty) {
      throw ArgumentError('Path cannot be empty.');
    }
    if (isFolder) {
      return joined.endsWith('/') ? joined : '$joined/';
    }
    return joined;
  }

  List<ForgeDiffLine> _buildFallbackDiffLines(
    String beforeContent,
    String afterContent,
  ) {
    if (beforeContent == afterContent) {
      return const <ForgeDiffLine>[];
    }

    final beforeLines = beforeContent.split('\n');
    final afterLines = afterContent.split('\n');
    return <ForgeDiffLine>[
      ...beforeLines.map(
        (line) => ForgeDiffLine(prefix: '-', line: line, isAddition: false),
      ),
      ...afterLines.map(
        (line) => ForgeDiffLine(prefix: '+', line: line, isAddition: true),
      ),
    ];
  }
}

class _MutableFolder {
  _MutableFolder.folder(this.name, this.path) : node = null;

  _MutableFolder.file(ForgeFileNode node)
    : name = node.name,
      path = node.path,
      node = node;

  final String name;
  final String path;
  final ForgeFileNode? node;
  final Map<String, _MutableFolder> children = <String, _MutableFolder>{};

  ForgeFileNode toNode() {
    if (node != null) {
      return node!;
    }
    final childNodes = children.values.map((item) => item.toNode()).toList()
      ..sort((a, b) {
        if (a.isFolder != b.isFolder) {
          return a.isFolder ? -1 : 1;
        }
        return a.name.compareTo(b.name);
      });
    return ForgeFileNode(
      name: name,
      path: path,
      language: 'Folder',
      sizeLabel: '${childNodes.length} items',
      changeLabel: '',
      children: childNodes,
      isFolder: true,
      isSelected: childNodes.any((item) => item.isSelected),
    );
  }
}
