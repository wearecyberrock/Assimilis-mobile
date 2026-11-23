import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../workstation/features/agent/data/built_in_tools.dart';
import '../../workstation/features/agent/domain/agent_tool.dart';
import '../agent_loop.dart';
import '../links/agent_models.dart';
import '../links/model_gateway.dart';
import '../settings.dart';
import '../tools.dart';

/// A role inside a user-started Team task (Manager, Worker, Checker, Researcher, Operator).
class TeamRole {
  final String id;
  final String name;
  final String summary;
  final String agentKey; // 'a' | 'workstation' | 'phone' | 'hes'
  final String systemPrompt;
  bool enabled;
  String? modelOverride; // optional gateway model id, e.g. 'chatgpt/gpt-6-sol'

  TeamRole({
    required this.id,
    required this.name,
    required this.summary,
    required this.agentKey,
    required this.systemPrompt,
    this.enabled = true,
    this.modelOverride,
  });

  TeamRole copyWith({bool? enabled, String? modelOverride, bool clearOverride = false}) => TeamRole(
        id: id,
        name: name,
        summary: summary,
        agentKey: agentKey,
        systemPrompt: systemPrompt,
        enabled: enabled ?? this.enabled,
        modelOverride: clearOverride ? null : (modelOverride ?? this.modelOverride),
      );
}

/// One visible step in a team task transcript.
class TeamStep {
  final String roleId;
  final String roleName;
  final String kind; // plan | delegate | tool | check | answer | error
  final String summary;
  final String? detail;
  final DateTime at;

  TeamStep({
    required this.roleId,
    required this.roleName,
    required this.kind,
    required this.summary,
    this.detail,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'roleId': roleId,
        'roleName': roleName,
        'kind': kind,
        'summary': summary,
        if (detail != null) 'detail': detail,
        'at': at.toIso8601String(),
      };

  factory TeamStep.fromJson(Map<String, dynamic> m) => TeamStep(
        roleId: '${m['roleId'] ?? ''}',
        roleName: '${m['roleName'] ?? ''}',
        kind: '${m['kind'] ?? 'tool'}',
        summary: '${m['summary'] ?? ''}',
        detail: m['detail']?.toString(),
        at: DateTime.tryParse('${m['at'] ?? ''}') ?? DateTime.now(),
      );
}

/// Record of one user-started Team task.
class TeamTaskRun {
  final String id;
  final String goal;
  String status; // running | done | cancelled | error
  final DateTime startedAt;
  DateTime? finishedAt;
  final List<String> rolesUsed;
  final List<TeamStep> steps;
  String finalAnswer;

  TeamTaskRun({
    required this.id,
    required this.goal,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    required this.rolesUsed,
    required this.steps,
    this.finalAnswer = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'goal': goal,
        'status': status,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        'rolesUsed': rolesUsed,
        'steps': steps.map((s) => s.toJson()).toList(),
        'finalAnswer': finalAnswer,
      };

  factory TeamTaskRun.fromJson(Map<String, dynamic> m) => TeamTaskRun(
        id: '${m['id'] ?? ''}',
        goal: '${m['goal'] ?? ''}',
        status: '${m['status'] ?? 'done'}',
        startedAt: DateTime.tryParse('${m['startedAt'] ?? ''}') ?? DateTime.now(),
        finishedAt: DateTime.tryParse('${m['finishedAt'] ?? ''}'),
        rolesUsed: List<String>.from(m['rolesUsed'] ?? const []),
        steps: [for (final s in (m['steps'] as List? ?? const [])) TeamStep.fromJson(Map<String, dynamic>.from(s as Map))],
        finalAnswer: '${m['finalAnswer'] ?? ''}',
      );
}

/// Coordinates a multi-agent Team task ONLY when the user explicitly starts one.
/// Uses [AgentLoop] with [AgentModels.endpointFor] per role, delegates to specialist roles
/// (Manager, Worker, Researcher, Operator, Checker), hands jobs to Workstation and Phone Agent
/// through their tools, and reaches other Assimilis devices via A2A.
class TeamEngine {
  TeamEngine._();
  static final TeamEngine instance = TeamEngine._();

  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  static List<TeamRole> defaultRoles() => [
        TeamRole(
          id: 'manager',
          name: 'Manager',
          summary: 'Plans the goal, delegates subtasks, hands jobs to Workstation/Phone/A2A, synthesizes.',
          agentKey: 'a',
          systemPrompt: 'You are the Manager of an Assimilis multi-agent team on the user\'s phone. '
              'Break the user\'s goal into clear steps, delegate focused work to available teammates with delegate_to_role, '
              'use workstation_task for file/document/device/coding jobs, phone_task for operating apps on screen, '
              'and list_devices / ask_device when another Assimilis device is better suited. '
              'Before giving your final answer, make sure key facts and actions are verified.',
        ),
        TeamRole(
          id: 'worker',
          name: 'Worker',
          summary: 'Executes analysis, Canvas/HES updates, maths, and Workstation jobs.',
          agentKey: 'workstation',
          systemPrompt: 'You are the Worker on an Assimilis team. Carry out the assigned subtask thoroughly and concisely '
              'using the available tools (HES, Canvas, maths, Agent Reach, Workstation tools). Return concrete results.',
        ),
        TeamRole(
          id: 'checker',
          name: 'Checker',
          summary: 'Independently re-checks outputs, verifies claims/calculations, flags gaps.',
          agentKey: 'a',
          systemPrompt: 'You are the Checker on an Assimilis team. Re-check the draft result against the user\'s goal '
              'and tool evidence. Use tools to double-check calculations, notes, HES state or facts when helpful. '
              'If everything is accurate and complete, start your response with "APPROVED:" followed by a brief verification note. '
              'If anything is missing or wrong, start with "REVISE:" and list the exact fixes required.',
        ),
        TeamRole(
          id: 'researcher',
          name: 'Researcher',
          summary: 'Searches the web (Agent Reach: Exa, Jina, GitHub, Reddit, RSS), Canvas, and VLE.',
          agentKey: 'a',
          enabled: false,
          systemPrompt: 'You are the Researcher on an Assimilis team. Gather accurate, sourced information using web_search, '
              'read_url, github, reddit, rss, canvas_read, and VLE scan tools. Return structured findings with sources.',
        ),
        TeamRole(
          id: 'operator',
          name: 'Phone Operator',
          summary: 'Runs Phone Agent UI actions and coordinates nearby A2A devices.',
          agentKey: 'phone',
          enabled: false,
          systemPrompt: 'You are the Phone Operator on an Assimilis team. Execute Android phone actions via phone_task '
              '(respecting the safety gate) and coordinate nearby Assimilis devices via list_devices / ask_device.',
        ),
      ];

  static Map<String, dynamic> _fn(String name, String desc, Map<String, dynamic> props, [List<String> req = const []]) => {
        'type': 'function',
        'function': {
          'name': name,
          'description': desc,
          'parameters': {'type': 'object', 'properties': props, 'required': req},
        },
      };

  static Map<String, dynamic> _agentToolToSchema(AgentTool t) => {
        'type': 'function',
        'function': {
          'name': t.name,
          'description': t.description,
          'parameters': t.inputSchema,
        },
      };

  /// Starts a Team task on demand. Never runs automatically.
  Future<TeamTaskRun> runTask({
    required String goal,
    required List<TeamRole> roles,
    bool allowWorkstation = true,
    bool allowPhoneAgent = true,
    bool allowA2a = true,
    void Function(TeamStep step)? onStep,
    Future<Endpoint?> Function(TeamRole role)? endpointResolver,
    Future<String> Function(String name, Map<String, dynamic> args)? toolRunner,
    http.Client? client,
  }) async {
    _cancelled = false;
    final active = roles.where((r) => r.enabled).toList();
    final manager = active.firstWhere(
      (r) => r.id == 'manager',
      orElse: () => active.isNotEmpty ? active.first : defaultRoles().first,
    );
    final checker = active.cast<TeamRole?>().firstWhere((r) => r!.id == 'checker', orElse: () => null);
    final teammates = active.where((r) => r.id != manager.id).toList();

    final run = TeamTaskRun(
      id: 'team-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
      goal: goal.trim(),
      status: 'running',
      startedAt: DateTime.now(),
      rolesUsed: active.map((r) => r.name).toList(),
      steps: [],
    );

    void emit(String roleId, String roleName, String kind, String summary, [String? detail]) {
      final step = TeamStep(roleId: roleId, roleName: roleName, kind: kind, summary: summary, detail: detail);
      run.steps.add(step);
      onStep?.call(step);
    }

    Future<Endpoint> resolveEp(TeamRole role) async {
      if (endpointResolver != null) {
        final ep = await endpointResolver(role);
        if (ep != null) return ep;
        throw Exception('No model configured for ${role.name}.');
      }
      if (role.modelOverride != null && role.modelOverride!.trim().isNotEmpty) {
        await ModelGateway.instance.start();
        final tok = await ModelGateway.instance.token();
        return (base: ModelGateway.baseUrl, model: role.modelOverride!.trim(), key: tok);
      }
      final ep = await AgentModels.endpointFor(role.agentKey);
      if (ep == null) throw Exception('No brain configured for ${role.name}. Add a model or key in Settings.');
      return ep;
    }

    final baseRunTool = toolRunner ?? AssimilisTools.run;

    // Filter Assimilis tools according to user toggles for this task.
    List<Map<String, dynamic>> baseSchemas() => AssimilisTools.schemas.where((s) {
          final n = '${(s['function'] as Map)['name']}';
          if (!allowPhoneAgent && n == 'phone_task') return false;
          if (!allowA2a && (n == 'list_devices' || n == 'ask_device')) return false;
          return true;
        }).toList();

    var checkerCalled = false;

    Future<String> runWorkstationJob(String task) async {
      if (_cancelled) return 'Cancelled by user.';
      emit('workstation', 'Workstation', 'delegate', 'Workstation job: $task');
      final wsRole = TeamRole(
        id: 'workstation',
        name: 'Workstation',
        summary: 'Workstation agent',
        agentKey: 'workstation',
        systemPrompt: 'You are the Assimilis Workstation agent. Complete the assigned job using your file, document, '
            'device, calculator, and Assimilis tools, and return a clear result.',
      );
      final ep = await resolveEp(wsRole);
      final wsTools = BuiltInTools.all();
      final wsByName = {for (final t in wsTools) t.name: t};
      final schemas = [
        for (final t in wsTools) _agentToolToSchema(t),
        ...baseSchemas().where((s) => !wsByName.containsKey('${(s['function'] as Map)['name']}')),
      ];
      final res = await AgentLoop.run(
        ep,
        [
          {'role': 'system', 'content': wsRole.systemPrompt},
          {'role': 'user', 'content': task},
        ],
        tools: schemas,
        maxRounds: 6,
        client: client,
        onTool: (n) => emit('workstation', 'Workstation', 'tool', 'Used $n'),
        runTool: (n, a) async {
          if (_cancelled) return 'Cancelled.';
          if (wsByName.containsKey(n)) {
            if (toolRunner != null) return toolRunner(n, a);
            return wsByName[n]!.run(a);
          }
          return baseRunTool(n, a);
        },
      );
      emit('workstation', 'Workstation', 'answer', 'Workstation finished', res.text);
      return res.text;
    }

    Future<String> runRole(TeamRole role, String instruction, {int depth = 0}) async {
      if (_cancelled) return 'Cancelled by user.';
      if (role.id == 'checker') checkerCalled = true;
      emit(role.id, role.name, role.id == 'checker' ? 'check' : 'plan',
          depth == 0 ? 'Starting on goal' : 'Assigned: ${instruction.length > 100 ? '${instruction.substring(0, 100)}…' : instruction}');
      final ep = await resolveEp(role);

      final roleSchemas = <Map<String, dynamic>>[...baseSchemas()];
      if (allowWorkstation) {
        roleSchemas.add(_fn(
          'workstation_task',
          'Hand a job to the Workstation agent (has file, document, device, calculator and Assimilis tools).',
          {'task': {'type': 'string'}},
          ['task'],
        ));
      }
      if (depth == 0 && teammates.isNotEmpty) {
        roleSchemas.add(_fn(
          'delegate_to_role',
          'Delegate a concrete subtask to another active role on this team. Available roles: '
              '${teammates.map((r) => '${r.id} (${r.name}: ${r.summary})').join('; ')}.',
          {
            'role': {'type': 'string', 'description': 'Role id: ${teammates.map((r) => r.id).join(', ')}'},
            'instruction': {'type': 'string', 'description': 'Exact subtask and context for that role'},
          },
          ['role', 'instruction'],
        ));
      }

      final res = await AgentLoop.run(
        ep,
        [
          {'role': 'system', 'content': role.systemPrompt},
          {'role': 'user', 'content': instruction},
        ],
        tools: roleSchemas,
        maxRounds: depth == 0 ? 10 : 6,
        client: client,
        onTool: (n) => emit(role.id, role.name, 'tool', 'Called $n'),
        runTool: (n, a) async {
          if (_cancelled) return 'Cancelled by user.';
          if (n == 'workstation_task' && allowWorkstation) {
            return runWorkstationJob('${a['task'] ?? ''}');
          }
          if (n == 'delegate_to_role' && depth == 0) {
            final targetId = '${a['role'] ?? ''}'.trim().toLowerCase();
            final target = teammates.cast<TeamRole?>().firstWhere(
                  (r) => r!.id == targetId || r.name.toLowerCase() == targetId,
                  orElse: () => null,
                );
            if (target == null) {
              return 'Unknown role "$targetId". Available: ${teammates.map((r) => r.id).join(', ')}.';
            }
            final sub = '${a['instruction'] ?? ''}'.trim();
            emit(role.id, role.name, 'delegate', 'Delegated to ${target.name}', sub);
            return runRole(target, sub, depth: depth + 1);
          }
          if (n == 'phone_task' && !allowPhoneAgent) return 'Phone Agent is disabled for this team task.';
          if ((n == 'list_devices' || n == 'ask_device') && !allowA2a) return 'A2A devices are disabled for this team task.';
          return baseRunTool(n, a);
        },
      );
      emit(role.id, role.name, role.id == 'checker' ? 'check' : 'answer',
          '${role.name} completed (${res.toolsUsed.length} tools)', res.text);
      return res.text;
    }

    try {
      final teamLine = teammates.isEmpty
          ? 'You are working solo.'
          : 'Active teammates you can delegate to: ${teammates.map((r) => '${r.id} (${r.name})').join(', ')}.';
      var draft = await runRole(manager, 'User goal:\n${run.goal}\n\n$teamLine');

      // Ensure the Checker always re-checks when enabled and the Manager hasn't already asked it.
      if (!_cancelled && checker != null && checker.id != manager.id && !checkerCalled) {
        emit(manager.id, manager.name, 'delegate', 'Sending draft to ${checker.name} for verification');
        final review = await runRole(
          checker,
          'Original goal:\n${run.goal}\n\nManager\'s draft answer:\n$draft\n\n'
              'Re-check accuracy, calculations and completeness. Begin with APPROVED: or REVISE:.',
          depth: 1,
        );
        if (!_cancelled && !review.toUpperCase().startsWith('APPROVED')) {
          emit(manager.id, manager.name, 'plan', 'Revising answer based on ${checker.name}\'s feedback');
          draft = await runRole(
            manager,
            'Original goal:\n${run.goal}\n\nYour previous draft:\n$draft\n\n'
                'Checker feedback:\n$review\n\nAddress every point raised by the Checker and produce the final answer.',
            depth: 1,
          );
        }
      }

      run.finalAnswer = draft;
      run.status = _cancelled ? 'cancelled' : 'done';
      run.finishedAt = DateTime.now();
    } catch (e) {
      run.status = _cancelled ? 'cancelled' : 'error';
      run.finishedAt = DateTime.now();
      run.finalAnswer = 'Team task stopped: $e';
      emit('system', 'Team', 'error', '$e');
    }

    await saveRun(run);
    return run;
  }

  Future<List<TeamTaskRun>> history() async {
    try {
      final raw = (await AssimilisSettings.get()).blob('team_runs');
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return [for (final m in list) TeamTaskRun.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRun(TeamTaskRun run) async {
    try {
      final list = await history();
      list.removeWhere((r) => r.id == run.id);
      list.insert(0, run);
      if (list.length > 20) list.removeRange(20, list.length);
      await (await AssimilisSettings.get()).setBlob('team_runs', jsonEncode(list.map((r) => r.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    await (await AssimilisSettings.get()).setBlob('team_runs', '[]');
  }
}
