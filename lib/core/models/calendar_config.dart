import 'package:cloud_firestore/cloud_firestore.dart';

// ═══════════════════════════════════════════════════════════
// MAIN CONFIG CLASS
// ═══════════════════════════════════════════════════════════

class CalendarConfig {
  final bool enabled;
  final double stageNumber;
  final String stageName;
  final CalendarExtractionSettings extraction;
  final CalendarDefaultSettings defaults;
  final CalendarRecurrenceSettings recurrence;
  final CalendarConflictSettings conflictDetection;
  final Map<String, CalendarEventTypeConfig> eventTypes;
  final CalendarQuerySettings query;
  final DateTime? updatedAt;
  final String? updatedBy;

  CalendarConfig({
    required this.enabled,
    required this.stageNumber,
    required this.stageName,
    required this.extraction,
    required this.defaults,
    required this.recurrence,
    required this.conflictDetection,
    required this.eventTypes,
    required this.query,
    this.updatedAt,
    this.updatedBy,
  });

  factory CalendarConfig.defaults() {
    return CalendarConfig(
      enabled: true,
      stageNumber: 6.7,
      stageName: 'Calendar/Events',
      extraction: CalendarExtractionSettings.defaults(),
      defaults: CalendarDefaultSettings.defaults(),
      recurrence: CalendarRecurrenceSettings.defaults(),
      conflictDetection: CalendarConflictSettings.defaults(),
      eventTypes: CalendarEventTypeConfig.defaultTypes(),
      query: CalendarQuerySettings.defaults(),
    );
  }

  factory CalendarConfig.fromFirestore(Map<String, dynamic> data) {
    return CalendarConfig(
      enabled: data['enabled'] ?? true,
      stageNumber: (data['stageNumber'] ?? 6.7).toDouble(),
      stageName: data['stageName'] ?? 'Calendar/Events',
      extraction: CalendarExtractionSettings.fromFirestore(data['extraction'] ?? {}),
      defaults: CalendarDefaultSettings.fromFirestore(data['defaults'] ?? {}),
      recurrence: CalendarRecurrenceSettings.fromFirestore(data['recurrence'] ?? {}),
      conflictDetection: CalendarConflictSettings.fromFirestore(data['conflictDetection'] ?? {}),
      eventTypes: _parseEventTypes(data['eventTypes']),
      query: CalendarQuerySettings.fromFirestore(data['query'] ?? {}),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      updatedBy: data['updatedBy'],
    );
  }

  static Map<String, CalendarEventTypeConfig> _parseEventTypes(dynamic data) {
    if (data == null || data is! Map) {
      return CalendarEventTypeConfig.defaultTypes();
    }
    final result = <String, CalendarEventTypeConfig>{};
    data.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        result[key.toString()] = CalendarEventTypeConfig.fromFirestore(value);
      }
    });
    return result.isEmpty ? CalendarEventTypeConfig.defaultTypes() : result;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enabled': enabled,
      'stageNumber': stageNumber,
      'stageName': stageName,
      'extraction': extraction.toFirestore(),
      'defaults': defaults.toFirestore(),
      'recurrence': recurrence.toFirestore(),
      'conflictDetection': conflictDetection.toFirestore(),
      'eventTypes': eventTypes.map((key, value) => MapEntry(key, value.toFirestore())),
      'query': query.toFirestore(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    };
  }

  CalendarConfig copyWith({
    bool? enabled,
    double? stageNumber,
    String? stageName,
    CalendarExtractionSettings? extraction,
    CalendarDefaultSettings? defaults,
    CalendarRecurrenceSettings? recurrence,
    CalendarConflictSettings? conflictDetection,
    Map<String, CalendarEventTypeConfig>? eventTypes,
    CalendarQuerySettings? query,
    String? updatedBy,
  }) {
    return CalendarConfig(
      enabled: enabled ?? this.enabled,
      stageNumber: stageNumber ?? this.stageNumber,
      stageName: stageName ?? this.stageName,
      extraction: extraction ?? this.extraction,
      defaults: defaults ?? this.defaults,
      recurrence: recurrence ?? this.recurrence,
      conflictDetection: conflictDetection ?? this.conflictDetection,
      eventTypes: eventTypes ?? this.eventTypes,
      query: query ?? this.query,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// EXTRACTION SETTINGS
// ═══════════════════════════════════════════════════════════

class CalendarExtractionSettings {
  final String mode; // 'llm' | 'pattern' | 'hybrid'
  final CalendarLLMSettings llm;

  CalendarExtractionSettings({
    required this.mode,
    required this.llm,
  });

  factory CalendarExtractionSettings.defaults() {
    return CalendarExtractionSettings(
      mode: 'llm',
      llm: CalendarLLMSettings.defaults(),
    );
  }

  factory CalendarExtractionSettings.fromFirestore(Map<String, dynamic> data) {
    return CalendarExtractionSettings(
      mode: data['mode'] ?? 'llm',
      llm: CalendarLLMSettings.fromFirestore(data['llm'] ?? {}),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'mode': mode,
      'llm': llm.toFirestore(),
    };
  }

  CalendarExtractionSettings copyWith({
    String? mode,
    CalendarLLMSettings? llm,
  }) {
    return CalendarExtractionSettings(
      mode: mode ?? this.mode,
      llm: llm ?? this.llm,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// LLM SETTINGS
// ═══════════════════════════════════════════════════════════

class CalendarLLMSettings {
  final String provider;
  final String model;
  final double temperature;
  final int maxTokens;

  CalendarLLMSettings({
    required this.provider,
    required this.model,
    required this.temperature,
    required this.maxTokens,
  });

  factory CalendarLLMSettings.defaults() {
    return CalendarLLMSettings(
      provider: 'gemini',
      model: 'gemini-2.0-flash-exp',
      temperature: 0.2,
      maxTokens: 300,
    );
  }

  factory CalendarLLMSettings.fromFirestore(Map<String, dynamic> data) {
    return CalendarLLMSettings(
      provider: data['provider'] ?? 'gemini',
      model: data['model'] ?? 'gemini-2.0-flash-exp',
      temperature: (data['temperature'] ?? 0.2).toDouble(),
      maxTokens: data['maxTokens'] ?? 300,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'provider': provider,
      'model': model,
      'temperature': temperature,
      'maxTokens': maxTokens,
    };
  }

  CalendarLLMSettings copyWith({
    String? provider,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return CalendarLLMSettings(
      provider: provider ?? this.provider,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// DEFAULT SETTINGS
// ═══════════════════════════════════════════════════════════

class CalendarDefaultSettings {
  final int reminderMinutes;
  final String eventType;
  final String status;
  final String source;

  CalendarDefaultSettings({
    required this.reminderMinutes,
    required this.eventType,
    required this.status,
    required this.source,
  });

  factory CalendarDefaultSettings.defaults() {
    return CalendarDefaultSettings(
      reminderMinutes: 60,
      eventType: 'event',
      status: 'active',
      source: 'chat',
    );
  }

  factory CalendarDefaultSettings.fromFirestore(Map<String, dynamic> data) {
    return CalendarDefaultSettings(
      reminderMinutes: data['reminderMinutes'] ?? 60,
      eventType: data['eventType'] ?? 'event',
      status: data['status'] ?? 'active',
      source: data['source'] ?? 'chat',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'reminderMinutes': reminderMinutes,
      'eventType': eventType,
      'status': status,
      'source': source,
    };
  }

  CalendarDefaultSettings copyWith({
    int? reminderMinutes,
    String? eventType,
    String? status,
    String? source,
  }) {
    return CalendarDefaultSettings(
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
      eventType: eventType ?? this.eventType,
      status: status ?? this.status,
      source: source ?? this.source,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// RECURRENCE SETTINGS
// ═══════════════════════════════════════════════════════════

class CalendarRecurrenceSettings {
  final bool enabled;
  final List<String> types;
  final int maxOccurrences;

  CalendarRecurrenceSettings({
    required this.enabled,
    required this.types,
    required this.maxOccurrences,
  });

  factory CalendarRecurrenceSettings.defaults() {
    return CalendarRecurrenceSettings(
      enabled: true,
      types: ['none', 'daily', 'weekly', 'monthly', 'yearly'],
      maxOccurrences: 52,
    );
  }

  factory CalendarRecurrenceSettings.fromFirestore(Map<String, dynamic> data) {
    return CalendarRecurrenceSettings(
      enabled: data['enabled'] ?? true,
      types: (data['types'] as List?)?.cast<String>() ?? ['none', 'daily', 'weekly', 'monthly', 'yearly'],
      maxOccurrences: data['maxOccurrences'] ?? 52,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enabled': enabled,
      'types': types,
      'maxOccurrences': maxOccurrences,
    };
  }

  CalendarRecurrenceSettings copyWith({
    bool? enabled,
    List<String>? types,
    int? maxOccurrences,
  }) {
    return CalendarRecurrenceSettings(
      enabled: enabled ?? this.enabled,
      types: types ?? this.types,
      maxOccurrences: maxOccurrences ?? this.maxOccurrences,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// CONFLICT SETTINGS
// ═══════════════════════════════════════════════════════════

class CalendarConflictSettings {
  final bool enabled;
  final int bufferMinutes;
  final bool askOnConflict;

  CalendarConflictSettings({
    required this.enabled,
    required this.bufferMinutes,
    required this.askOnConflict,
  });

  factory CalendarConflictSettings.defaults() {
    return CalendarConflictSettings(
      enabled: true,
      bufferMinutes: 30,
      askOnConflict: true,
    );
  }

  factory CalendarConflictSettings.fromFirestore(Map<String, dynamic> data) {
    return CalendarConflictSettings(
      enabled: data['enabled'] ?? true,
      bufferMinutes: data['bufferMinutes'] ?? 30,
      askOnConflict: data['askOnConflict'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'enabled': enabled,
      'bufferMinutes': bufferMinutes,
      'askOnConflict': askOnConflict,
    };
  }

  CalendarConflictSettings copyWith({
    bool? enabled,
    int? bufferMinutes,
    bool? askOnConflict,
  }) {
    return CalendarConflictSettings(
      enabled: enabled ?? this.enabled,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      askOnConflict: askOnConflict ?? this.askOnConflict,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// EVENT TYPE CONFIG
// ═══════════════════════════════════════════════════════════

class CalendarEventTypeConfig {
  final String icon;
  final String color;
  final int defaultReminder;

  CalendarEventTypeConfig({
    required this.icon,
    required this.color,
    required this.defaultReminder,
  });

  factory CalendarEventTypeConfig.fromFirestore(Map<String, dynamic> data) {
    return CalendarEventTypeConfig(
      icon: data['icon'] ?? '📌',
      color: data['color'] ?? '#2196F3',
      defaultReminder: data['defaultReminder'] ?? 60,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'icon': icon,
      'color': color,
      'defaultReminder': defaultReminder,
    };
  }

  static Map<String, CalendarEventTypeConfig> defaultTypes() {
    return {
      'appointment': CalendarEventTypeConfig(
        icon: '🏥',
        color: '#4CAF50',
        defaultReminder: 60,
      ),
      'reminder': CalendarEventTypeConfig(
        icon: '⏰',
        color: '#FF9800',
        defaultReminder: 15,
      ),
      'deadline': CalendarEventTypeConfig(
        icon: '📅',
        color: '#F44336',
        defaultReminder: 1440,
      ),
      'event': CalendarEventTypeConfig(
        icon: '📌',
        color: '#2196F3',
        defaultReminder: 60,
      ),
      'meeting': CalendarEventTypeConfig(
        icon: '👥',
        color: '#9C27B0',
        defaultReminder: 15,
      ),
    };
  }

  CalendarEventTypeConfig copyWith({
    String? icon,
    String? color,
    int? defaultReminder,
  }) {
    return CalendarEventTypeConfig(
      icon: icon ?? this.icon,
      color: color ?? this.color,
      defaultReminder: defaultReminder ?? this.defaultReminder,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// QUERY SETTINGS
// ═══════════════════════════════════════════════════════════

class CalendarQuerySettings {
  final int defaultLookaheadDays;
  final int maxEventsPerQuery;
  final bool includeCompleted;

  CalendarQuerySettings({
    required this.defaultLookaheadDays,
    required this.maxEventsPerQuery,
    required this.includeCompleted,
  });

  factory CalendarQuerySettings.defaults() {
    return CalendarQuerySettings(
      defaultLookaheadDays: 7,
      maxEventsPerQuery: 20,
      includeCompleted: false,
    );
  }

  factory CalendarQuerySettings.fromFirestore(Map<String, dynamic> data) {
    return CalendarQuerySettings(
      defaultLookaheadDays: data['defaultLookaheadDays'] ?? 7,
      maxEventsPerQuery: data['maxEventsPerQuery'] ?? 20,
      includeCompleted: data['includeCompleted'] ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'defaultLookaheadDays': defaultLookaheadDays,
      'maxEventsPerQuery': maxEventsPerQuery,
      'includeCompleted': includeCompleted,
    };
  }

  CalendarQuerySettings copyWith({
    int? defaultLookaheadDays,
    int? maxEventsPerQuery,
    bool? includeCompleted,
  }) {
    return CalendarQuerySettings(
      defaultLookaheadDays: defaultLookaheadDays ?? this.defaultLookaheadDays,
      maxEventsPerQuery: maxEventsPerQuery ?? this.maxEventsPerQuery,
      includeCompleted: includeCompleted ?? this.includeCompleted,
    );
  }
}
