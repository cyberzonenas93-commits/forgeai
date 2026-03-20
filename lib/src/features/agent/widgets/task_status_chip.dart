import 'package:flutter/material.dart';

import '../../../shared/widgets/forge_widgets.dart';
import '../../workspace/domain/forge_agent_entities.dart';
import '../agent_ui_utils.dart';

class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({
    super.key,
    required this.task,
    this.compact = false,
  });

  final ForgeAgentTask task;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ForgePill(
      label: formatAgentStatusLabel(task),
      icon: agentStatusIcon(task),
      color: agentStatusColor(task),
    );
  }
}
