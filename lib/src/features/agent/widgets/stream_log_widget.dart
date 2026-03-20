import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// A single real-time log entry streamed from the backend.
class AgentStreamLogEntry {
  const AgentStreamLogEntry({
    required this.timestampMs,
    required this.type,
    required this.content,
  });

  factory AgentStreamLogEntry.fromMap(Map<String, dynamic> map) {
    return AgentStreamLogEntry(
      timestampMs:
          map['timestampMs'] is int ? map['timestampMs'] as int : DateTime.now().millisecondsSinceEpoch,
      type: map['type'] is String ? map['type'] as String : 'info',
      content: map['content'] is String ? map['content'] as String : '',
    );
  }

  final int timestampMs;

  /// One of: 'stdout', 'stderr', 'info', 'error'
  final String type;
  final String content;
}

/// Terminal-style panel that subscribes to the `streamLog` array on an agent
/// task Firestore document and renders new entries in real time.
///
/// Usage:
/// ```dart
/// StreamLogWidget(ownerId: uid, taskId: taskId)
/// ```
class StreamLogWidget extends StatefulWidget {
  const StreamLogWidget({
    super.key,
    required this.ownerId,
    required this.taskId,
    this.maxVisibleLines = 300,
  });

  final String ownerId;
  final String taskId;
  final int maxVisibleLines;

  @override
  State<StreamLogWidget> createState() => _StreamLogWidgetState();
}

class _StreamLogWidgetState extends State<StreamLogWidget> {
  final ScrollController _scroll = ScrollController();
  List<AgentStreamLogEntry> _entries = const [];

  Stream<List<AgentStreamLogEntry>> _buildStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.ownerId)
        .collection('agentTasks')
        .doc(widget.taskId)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data == null) return const <AgentStreamLogEntry>[];
      final raw = data['streamLog'];
      if (raw is! List) return const <AgentStreamLogEntry>[];
      return raw
          .whereType<Map>()
          .map((e) => AgentStreamLogEntry.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AgentStreamLogEntry>>(
      stream: _buildStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _entries.isEmpty) {
          return const SizedBox(
            height: 56,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final entries = snapshot.data ?? _entries;
        if (entries.length > _entries.length) {
          _entries = entries;
          _scrollToBottom();
        } else {
          _entries = entries;
        }

        if (_entries.isEmpty) {
          return const SizedBox.shrink();
        }

        final visible = _entries.length > widget.maxVisibleLines
            ? _entries.sublist(_entries.length - widget.maxVisibleLines)
            : _entries;

        return Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                _TerminalHeader(entryCount: _entries.length),
                Flexible(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final entry = visible[index];
                      return _LogLine(entry: entry);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({required this.entryCount});
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF161B22),
        border: Border(bottom: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 14, color: Color(0xFF8B949E)),
          const SizedBox(width: 6),
          const Text(
            'Live output',
            style: TextStyle(
              color: Color(0xFF8B949E),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            '$entryCount lines',
            style: const TextStyle(color: Color(0xFF484F58), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});
  final AgentStreamLogEntry entry;

  Color get _textColor => switch (entry.type) {
    'stderr' => const Color(0xFFF85149),
    'error' => const Color(0xFFF85149),
    'info' => const Color(0xFF58A6FF),
    _ => const Color(0xFFE6EDF3),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        entry.content,
        style: TextStyle(
          color: _textColor,
          fontSize: 11.5,
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }
}
