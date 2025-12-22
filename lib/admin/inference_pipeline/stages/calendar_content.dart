import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CalendarContent extends StatefulWidget {
  const CalendarContent({super.key});

  @override
  State<CalendarContent> createState() => _CalendarContentState();
}

class _CalendarContentState extends State<CalendarContent> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _config = {};

  // Test state
  final TextEditingController _iinController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _isTesting = false;
  Map<String, dynamic>? _testResult;

  // Recent events state
  List<Map<String, dynamic>> _recentEvents = [];
  bool _loadingEvents = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _iinController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('pipeline')
          .collection('stages')
          .doc('calendar')
          .get();

      if (doc.exists && doc.data() != null) {
        setState(() {
          _config = doc.data()!;
        });
      } else {
        // Use defaults
        _config = _getDefaults();
      }
    } catch (e) {
      _showError('Failed to load config: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _getDefaults() {
    return {
      'enabled': true,
      'stageNumber': 6.7,
      'stageName': 'Calendar/Events',
      'extraction': {
        'mode': 'llm',
        'llm': {
          'provider': 'gemini',
          'model': 'gemini-2.0-flash-exp',
          'temperature': 0.2,
          'maxTokens': 300,
        },
      },
      'defaults': {
        'reminderMinutes': 60,
        'eventType': 'event',
        'status': 'active',
        'source': 'chat',
      },
      'recurrence': {
        'enabled': true,
        'types': ['none', 'daily', 'weekly', 'monthly', 'yearly'],
        'maxOccurrences': 52,
      },
      'conflictDetection': {
        'enabled': true,
        'bufferMinutes': 30,
        'askOnConflict': true,
      },
      'eventTypes': {
        'appointment': {'icon': '🏥', 'color': '#4CAF50', 'defaultReminder': 60},
        'reminder': {'icon': '⏰', 'color': '#FF9800', 'defaultReminder': 15},
        'deadline': {'icon': '📅', 'color': '#F44336', 'defaultReminder': 1440},
        'event': {'icon': '📌', 'color': '#2196F3', 'defaultReminder': 60},
        'meeting': {'icon': '👥', 'color': '#9C27B0', 'defaultReminder': 15},
      },
      'query': {
        'defaultLookaheadDays': 7,
        'maxEventsPerQuery': 20,
        'includeCompleted': false,
      },
    };
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('config')
          .doc('pipeline')
          .collection('stages')
          .doc('calendar')
          .set({
        ..._config,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSuccess('Configuration saved');
    } catch (e) {
      _showError('Failed to save: $e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _loadRecentEvents(String iin) async {
    if (iin.isEmpty) return;

    setState(() => _loadingEvents = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('memories')
          .doc(iin)
          .collection('events')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      setState(() {
        _recentEvents = snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    } catch (e) {
      debugPrint('Failed to load events: $e');
    } finally {
      setState(() => _loadingEvents = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⑥.7 Calendar/Events'),
            Text(
              'config/pipeline/stages/calendar',
              style: TextStyle(fontSize: 12, color: Colors.teal[300]),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveConfig,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverviewCard(),
            const SizedBox(height: 24),
            _buildExtractionCard(),
            const SizedBox(height: 24),
            _buildConflictCard(),
            const SizedBox(height: 24),
            _buildEventTypesCard(),
            const SizedBox(height: 24),
            _buildQueryCard(),
            const SizedBox(height: 24),
            _buildPipelineCard(),
            const SizedBox(height: 24),
            _buildTestCard(),
            const SizedBox(height: 24),
            _buildRecentEventsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard() {
    final enabled = _config['enabled'] ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_month, color: Colors.teal[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stage Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Parse and manage calendar events from chat', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Enable toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stage Enabled', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Enable calendar event extraction and management', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Switch(
                  value: enabled,
                  onChanged: (value) {
                    setState(() {
                      _config['enabled'] = value;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Info box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal[100]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.teal[700], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This stage extracts calendar events from messages like "Dentist appointment Tuesday at 3pm" and stores them in memories/{iin}/events collection.',
                      style: TextStyle(fontSize: 13, color: Colors.teal[800]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractionCard() {
    final extraction = _config['extraction'] ?? {};
    final mode = extraction['mode'] ?? 'llm';
    final llm = extraction['llm'] ?? {};
    final provider = llm['provider'] ?? 'gemini';
    final model = llm['model'] ?? 'gemini-2.0-flash-exp';
    final temperature = (llm['temperature'] ?? 0.2).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_fix_high, color: Colors.purple[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Extraction Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Configure how events are parsed from messages', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Mode
            const Text('Extraction Mode', style: TextStyle(fontWeight: FontWeight.w500)),
            Text('How to parse event details', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: mode,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'llm', child: Text('LLM (Most Accurate)')),
                DropdownMenuItem(value: 'pattern', child: Text('Pattern Matching (Fast)')),
                DropdownMenuItem(value: 'hybrid', child: Text('Hybrid (Both methods)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _config['extraction'] = {...extraction, 'mode': value};
                  });
                }
              },
            ),
            const SizedBox(height: 24),

            // Provider
            const Text('LLM Provider', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: provider,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                DropdownMenuItem(value: 'anthropic', child: Text('Anthropic')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    final updatedLlm = {...llm, 'provider': value};
                    _config['extraction'] = {...extraction, 'llm': updatedLlm};
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // Model
            const Text('Model', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: model,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'gemini-2.0-flash-exp',
              ),
              onChanged: (value) {
                setState(() {
                  final updatedLlm = {...llm, 'model': value};
                  _config['extraction'] = {...extraction, 'llm': updatedLlm};
                });
              },
            ),
            const SizedBox(height: 16),

            // Temperature
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Temperature', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Lower = more deterministic (0.0-1.0)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Text(
                  temperature.toStringAsFixed(2),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Slider(
              value: temperature,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              onChanged: (value) {
                setState(() {
                  final updatedLlm = {...llm, 'temperature': value};
                  _config['extraction'] = {...extraction, 'llm': updatedLlm};
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictCard() {
    final conflict = _config['conflictDetection'] ?? {};
    final enabled = conflict['enabled'] ?? true;
    final bufferMinutes = (conflict['bufferMinutes'] ?? 30).toDouble();
    final askOnConflict = conflict['askOnConflict'] ?? true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.amber[600]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Conflict Detection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Detect overlapping or conflicting events', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            _buildToggle(
              'Enable Conflict Detection',
              'Check for overlapping events when adding new ones',
              enabled,
              (value) => setState(() {
                _config['conflictDetection'] = {...conflict, 'enabled': value};
              }),
            ),
            const SizedBox(height: 16),

            // Buffer minutes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Buffer Minutes', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Time buffer to consider as overlap (0-120 min)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Text(
                  '${bufferMinutes.round()} min',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Slider(
              value: bufferMinutes,
              min: 0,
              max: 120,
              divisions: 24,
              onChanged: (value) {
                setState(() {
                  _config['conflictDetection'] = {...conflict, 'bufferMinutes': value.round()};
                });
              },
            ),
            const SizedBox(height: 16),

            _buildToggle(
              'Ask on Conflict',
              'Prompt user to resolve when conflict detected',
              askOnConflict,
              (value) => setState(() {
                _config['conflictDetection'] = {...conflict, 'askOnConflict': value};
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTypesCard() {
    final eventTypes = Map<String, dynamic>.from(_config['eventTypes'] ?? {});

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.category, color: Colors.blue[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Event Types', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Configure icons and colors for event types', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            ...eventTypes.entries.map((entry) {
              final type = entry.key;
              final config = Map<String, dynamic>.from(entry.value);
              final icon = config['icon'] ?? '📌';
              final color = config['color'] ?? '#2196F3';
              final reminder = config['defaultReminder'] ?? 60;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _parseColor(color).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(icon, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            type.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Default reminder: $reminder min',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    // Color indicator
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _parseColor(color),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String hexColor) {
    try {
      final hex = hexColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }

  Widget _buildQueryCard() {
    final query = _config['query'] ?? {};
    final lookaheadDays = (query['defaultLookaheadDays'] ?? 7).toDouble();
    final maxEvents = (query['maxEventsPerQuery'] ?? 20).toDouble();
    final includeCompleted = query['includeCompleted'] ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.search, color: Colors.green[400]),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Query Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Configure event query behavior', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Lookahead days
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Default Lookahead', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Days ahead to show by default (1-30)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Text(
                  '${lookaheadDays.round()} days',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Slider(
              value: lookaheadDays,
              min: 1,
              max: 30,
              divisions: 29,
              onChanged: (value) {
                setState(() {
                  _config['query'] = {...query, 'defaultLookaheadDays': value.round()};
                });
              },
            ),
            const SizedBox(height: 16),

            // Max events
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Max Events per Query', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Maximum events to return (5-50)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                Text(
                  '${maxEvents.round()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            Slider(
              value: maxEvents,
              min: 5,
              max: 50,
              divisions: 9,
              onChanged: (value) {
                setState(() {
                  _config['query'] = {...query, 'maxEventsPerQuery': value.round()};
                });
              },
            ),
            const SizedBox(height: 16),

            _buildToggle(
              'Include Completed Events',
              'Show past/completed events in queries',
              includeCompleted,
              (value) => setState(() {
                _config['query'] = {...query, 'includeCompleted': value};
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(String label, String description, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildPipelineCard() {
    return Card(
      color: Colors.teal[50],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree, color: Colors.teal[700]),
                const SizedBox(width: 12),
                Text(
                  'Pipeline Flow',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal[800]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('⑥.5 Conflict Check → Checks for memory conflicts',
                style: TextStyle(fontSize: 14, color: Colors.teal[900])),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal[300]!),
              ),
              child: Row(
                children: [
                  Text('⑥.7 Calendar/Events',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal[900])),
                  const SizedBox(width: 8),
                  Text('→ Extracts and manages calendar events',
                      style: TextStyle(fontSize: 14, color: Colors.teal[900])),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('⑦ Curiosity Module → Asks clarification questions',
                style: TextStyle(fontSize: 14, color: Colors.teal[900])),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Calendar Intents:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.teal[800])),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildIntentChip('schedule_add', 'Add events'),
                      _buildIntentChip('schedule_query', 'Query schedule'),
                      _buildIntentChip('schedule_update', 'Modify events'),
                      _buildIntentChip('schedule_delete', 'Cancel events'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntentChip(String intent, String description) {
    return Tooltip(
      message: description,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.teal[100],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          intent,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.teal[800]),
        ),
      ),
    );
  }

  Widget _buildTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.science, color: Colors.teal[400]),
                    const SizedBox(width: 12),
                    const Text('Test Stage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('LIVE', style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            const Text('IIN (required)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _iinController,
              decoration: const InputDecoration(
                hintText: 'XXXX-XXXX-XXXX-XXXX',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                // Load recent events when IIN changes
                if (_iinController.text.length >= 16) {
                  _loadRecentEvents(_iinController.text.trim());
                }
              },
            ),
            const SizedBox(height: 16),

            const Text('Test Message', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g., "I have a dentist appointment tomorrow at 3pm"',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isTesting ? null : _runTest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isTesting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Run Test', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Results', style: TextStyle(fontWeight: FontWeight.w500)),
                if (_testResult != null)
                  InkWell(
                    onTap: () {
                      final jsonString = const JsonEncoder.withIndent('  ').convert(_testResult);
                      Clipboard.setData(ClipboardData(text: jsonString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Results copied!'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, size: 14, color: Colors.blue[800]),
                          const SizedBox(width: 4),
                          Text('Copy', style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.w500, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 400),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: _testResult != null
                  ? SingleChildScrollView(
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(_testResult),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    )
                  : Center(
                      child: Text('Enter IIN and message, then click "Run Test"', style: TextStyle(color: Colors.grey[500])),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentEventsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.history, color: Colors.indigo[400]),
                    const SizedBox(width: 12),
                    const Text('Recent Events (Debug)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_loadingEvents)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _loadRecentEvents(_iinController.text.trim()),
                    tooltip: 'Refresh',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            if (_recentEvents.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    _iinController.text.isEmpty
                        ? 'Enter an IIN above to view recent events'
                        : 'No events found for this user',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              ..._recentEvents.map((event) => _buildEventRow(event)),
          ],
        ),
      ),
    );
  }

  Widget _buildEventRow(Map<String, dynamic> event) {
    final title = event['title'] ?? 'Untitled';
    final type = event['type'] ?? 'event';
    final status = event['status'] ?? 'active';
    final date = event['date'];
    String dateStr = 'Unknown date';
    if (date is Timestamp) {
      dateStr = date.toDate().toString().substring(0, 16);
    }

    final eventTypes = Map<String, dynamic>.from(_config['eventTypes'] ?? {});
    final typeConfig = eventTypes[type] ?? {'icon': '📌', 'color': '#2196F3'};
    final icon = typeConfig['icon'] ?? '📌';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                Text('$type • $dateStr', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'active' ? Colors.green[100] : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: status == 'active' ? Colors.green[800] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runTest() async {
    if (_iinController.text.isEmpty) {
      _showError('IIN is required');
      return;
    }
    if (_messageController.text.isEmpty) {
      _showError('Message is required');
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final response = await http.post(
        Uri.parse('https://pipelinechat-qqkntitb3a-uc.a.run.app'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'iin': _iinController.text.trim(),
          'message': _messageController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        // Extract calendar stage info
        final stages = result['stageSummary'] as List?;
        final calendarStage = stages?.firstWhere(
          (s) => s['name'] == 'Calendar' || s['name'] == 'Calendar/Events',
          orElse: () => null,
        );

        setState(() => _testResult = {
          'fullResponse': result,
          'calendarStage': calendarStage,
          'note': 'Check stageSummary for Calendar details',
        });

        // Refresh events list
        _loadRecentEvents(_iinController.text.trim());
      } else {
        setState(() => _testResult = {
          'error': 'Request failed',
          'statusCode': response.statusCode,
          'body': response.body,
        });
      }
    } catch (e) {
      setState(() => _testResult = {'error': e.toString()});
    } finally {
      setState(() => _isTesting = false);
    }
  }
}
