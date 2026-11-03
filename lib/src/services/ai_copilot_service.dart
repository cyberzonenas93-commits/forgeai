import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/forge_models.dart';

/// Service for AI Copilot features.
///
/// Supports both OpenAI (GPT-4o) and Anthropic (Claude) providers.
/// The selected provider and API keys are persisted to SharedPreferences.
class AiCopilotService {
  AiCopilotService._();

  static final AiCopilotService instance = AiCopilotService._();

  static const _kOpenAiApiKey = 'openai_api_key';
  static const _kAnthropicApiKey = 'anthropic_api_key';
  static const _kSelectedProvider = 'ai_copilot_provider';

  String? _openAiApiKey;
  String? _anthropicApiKey;
  AiProviderKind _selectedProvider = AiProviderKind.openai;

  String? get openAiApiKey => _openAiApiKey;
  String? get anthropicApiKey => _anthropicApiKey;
  AiProviderKind get selectedProvider => _selectedProvider;

  /// Backward-compatible getter — returns the OpenAI key.
  String? get apiKey => _openAiApiKey;

  /// Whether the active provider has a configured API key.
  bool get hasApiKey {
    final key = _activeApiKey;
    return key != null && key.isNotEmpty;
  }

  String? get _activeApiKey => switch (_selectedProvider) {
    AiProviderKind.openai => _openAiApiKey,
    AiProviderKind.anthropic => _anthropicApiKey,
    AiProviderKind.gemini => null,
  };

  /// Load saved keys and provider selection from SharedPreferences.
  /// Safe to call multiple times.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _openAiApiKey = prefs.getString(_kOpenAiApiKey);
      _anthropicApiKey = prefs.getString(_kAnthropicApiKey);
      final providerName = prefs.getString(_kSelectedProvider);
      if (providerName != null) {
        _selectedProvider = AiProviderKind.values.firstWhere(
          (p) => p.name == providerName,
          orElse: () => AiProviderKind.openai,
        );
      }
    } catch (_) {
      // Fail silently — service stays at defaults.
    }
  }

  /// Persist the selected provider.
  Future<void> updateSelectedProvider(AiProviderKind provider) async {
    _selectedProvider = provider;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSelectedProvider, provider.name);
  }

  /// Persist the OpenAI API key. Pass an empty string to clear.
  Future<void> updateOpenAiApiKey(String key) async {
    final trimmed = key.trim();
    _openAiApiKey = trimmed.isEmpty ? null : trimmed;
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_kOpenAiApiKey);
    } else {
      await prefs.setString(_kOpenAiApiKey, trimmed);
    }
  }

  /// Backward-compatible key update — updates the OpenAI key.
  Future<void> updateApiKey(String key) => updateOpenAiApiKey(key);

  /// Persist the Anthropic API key. Pass an empty string to clear.
  Future<void> updateAnthropicApiKey(String key) async {
    final trimmed = key.trim();
    _anthropicApiKey = trimmed.isEmpty ? null : trimmed;
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_kAnthropicApiKey);
    } else {
      await prefs.setString(_kAnthropicApiKey, trimmed);
    }
  }

  /// Clear the OpenAI API key.
  Future<void> clearApiKey() => updateOpenAiApiKey('');

  /// Send [messages] to the active LLM provider and return the assistant reply.
  ///
  /// [messages] must be a list of `{'role': 'user'|'assistant', 'content': '…'}`
  /// maps representing the full conversation history (oldest first).
  ///
  /// Throws [AiCopilotException] on configuration or API errors.
  Future<String> sendMessage(List<Map<String, String>> messages) async {
    final key = _activeApiKey;
    if (key == null || key.isEmpty) {
      throw AiCopilotException.noApiKey(_selectedProvider);
    }
    return switch (_selectedProvider) {
      AiProviderKind.openai => _callOpenAi(key, messages),
      AiProviderKind.anthropic => _callAnthropic(key, messages),
      AiProviderKind.gemini =>
        throw const AiCopilotException('Gemini is not yet supported.'),
    };
  }

  Future<String> _callOpenAi(
    String key,
    List<Map<String, String>> messages,
  ) async {
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'model': 'gpt-4o', 'messages': messages}),
    );

    if (response.statusCode == 401) {
      throw AiCopilotException.invalidKey(AiProviderKind.openai);
    }
    if (response.statusCode != 200) {
      throw AiCopilotException(
        'OpenAI error ${response.statusCode}: ${_extractError(response.body)}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['choices'] as List).first['message']['content'] as String;
  }

  Future<String> _callAnthropic(
    String key,
    List<Map<String, String>> messages,
  ) async {
    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'claude-opus-4-5-20251101',
        'max_tokens': 1024,
        'messages': messages,
      }),
    );

    if (response.statusCode == 401) {
      throw AiCopilotException.invalidKey(AiProviderKind.anthropic);
    }
    if (response.statusCode != 200) {
      throw AiCopilotException(
        'Anthropic error ${response.statusCode}: ${_extractError(response.body)}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['content'] as List).first['text'] as String;
  }

  String _extractError(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      return data['error']?['message'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }
}

/// Thrown by [AiCopilotService.sendMessage] on configuration or API errors.
class AiCopilotException implements Exception {
  const AiCopilotException(this.message);

  factory AiCopilotException.noApiKey(AiProviderKind provider) =>
      AiCopilotException(
        'No ${_providerName(provider)} API key found. '
        'Go to Settings → AI Copilot to add your key.',
      );

  factory AiCopilotException.invalidKey(AiProviderKind provider) =>
      AiCopilotException(
        'Invalid ${_providerName(provider)} API key. '
        'Please check your key in Settings → AI Copilot.',
      );

  final String message;

  static String _providerName(AiProviderKind p) => switch (p) {
    AiProviderKind.openai => 'OpenAI',
    AiProviderKind.anthropic => 'Anthropic',
    AiProviderKind.gemini => 'Gemini',
  };

  @override
  String toString() => message;
}
