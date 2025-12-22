import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// ═══════════════════════════════════════════════════════════
// CALENDAR EVENT MODEL
// ═══════════════════════════════════════════════════════════

class CalendarEvent {
  final String id;
  final String title;
  final String type;
  final DateTime date;
  final String? time;
  final String? endTime;
  final String? location;
  final String? description;
  final bool reminderSent;
  final int? reminderTime;
  final String recurrence;
  final String source;
  final String status;
  final DateTime? createdAt;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.type,
    required this.date,
    this.time,
    this.endTime,
    this.location,
    this.description,
    this.reminderSent = false,
    this.reminderTime,
    this.recurrence = 'none',
    this.source = 'chat',
    this.status = 'active',
    this.createdAt,
  });

  factory CalendarEvent.fromFirestore(String id, Map<String, dynamic> data) {
    return CalendarEvent(
      id: id,
      title: data['title'] ?? 'Untitled Event',
      type: data['type'] ?? 'event',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      time: data['time'],
      endTime: data['endTime'],
      location: data['location'],
      description: data['description'],
      reminderSent: data['reminderSent'] ?? false,
      reminderTime: data['reminderTime'],
      recurrence: data['recurrence'] ?? 'none',
      source: data['source'] ?? 'chat',
      status: data['status'] ?? 'active',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  String get typeIcon {
    switch (type) {
      case 'appointment':
        return '🏥';
      case 'reminder':
        return '⏰';
      case 'deadline':
        return '📅';
      case 'meeting':
        return '👥';
      default:
        return '📌';
    }
  }

  Color get typeColor {
    switch (type) {
      case 'appointment':
        return const Color(0xFF4CAF50);
      case 'reminder':
        return const Color(0xFFFF9800);
      case 'deadline':
        return const Color(0xFFF44336);
      case 'meeting':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFF2196F3);
    }
  }

  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);

    if (eventDay == today) {
      return 'Today';
    } else if (eventDay == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    } else {
      return DateFormat('EEE, MMM d').format(date);
    }
  }

  String get formattedTime {
    if (time == null) return 'All day';
    return time!;
  }
}

// ═══════════════════════════════════════════════════════════
// CALENDAR WIDGET
// ═══════════════════════════════════════════════════════════

class CalendarWidget extends StatefulWidget {
  final String iin;
  final int lookaheadDays;
  final Function(CalendarEvent)? onEventTap;
  final Function(CalendarEvent)? onEventEdit;
  final Function(CalendarEvent)? onEventDelete;

  const CalendarWidget({
    super.key,
    required this.iin,
    this.lookaheadDays = 7,
    this.onEventTap,
    this.onEventEdit,
    this.onEventDelete,
  });

  @override
  State<CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends State<CalendarWidget> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endDate = startOfToday.add(Duration(days: widget.lookaheadDays));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('memories')
          .doc(widget.iin)
          .collection('events')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .where('status', isEqualTo: 'active')
          .orderBy('date', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading events',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState();
        }

        final events = docs.map((doc) =>
            CalendarEvent.fromFirestore(doc.id, doc.data() as Map<String, dynamic>)
        ).toList();

        // Group events by date
        final groupedEvents = <String, List<CalendarEvent>>{};
        for (final event in events) {
          final dateKey = DateFormat('yyyy-MM-dd').format(event.date);
          groupedEvents.putIfAbsent(dateKey, () => []);
          groupedEvents[dateKey]!.add(event);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(events.length),
            const SizedBox(height: 12),
            ...groupedEvents.entries.map((entry) => _buildDateSection(entry.key, entry.value)),
          ],
        );
      },
    );
  }

  Widget _buildHeader(int eventCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today, size: 20, color: Colors.blue[600]),
            const SizedBox(width: 8),
            Text(
              'Upcoming Events',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$eventCount event${eventCount != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.blue[800],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'No upcoming events',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your schedule is clear for the next ${widget.lookaheadDays} days',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection(String dateKey, List<CalendarEvent> events) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = DateTime(date.year, date.month, date.day) == today;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isToday ? Colors.blue[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isToday)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                events.first.formattedDate,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isToday ? Colors.blue[800] : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...events.map((event) => _buildEventCard(event)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildEventCard(CalendarEvent event) {
    return GestureDetector(
      onTap: () => widget.onEventTap?.call(event),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: event.typeColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: event.typeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(event.typeIcon, style: const TextStyle(fontSize: 20)),
              ),
            ),
            const SizedBox(width: 12),
            // Event details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        event.formattedTime,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (event.location != null) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.location!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Actions menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[400]),
              onSelected: (action) {
                if (action == 'edit') {
                  widget.onEventEdit?.call(event);
                } else if (action == 'delete') {
                  _confirmDelete(event);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(CalendarEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Are you sure you want to delete "${event.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteEvent(event);
    }
  }

  Future<void> _deleteEvent(CalendarEvent event) async {
    try {
      await FirebaseFirestore.instance
          .collection('memories')
          .doc(widget.iin)
          .collection('events')
          .doc(event.id)
          .update({'status': 'cancelled'});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${event.title} deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('memories')
                    .doc(widget.iin)
                    .collection('events')
                    .doc(event.id)
                    .update({'status': 'active'});
              },
            ),
          ),
        );
      }

      widget.onEventDelete?.call(event);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting event: $e')),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════
// COMPACT CALENDAR CARD (for sidebar/dashboard)
// ═══════════════════════════════════════════════════════════

class CalendarCard extends StatelessWidget {
  final String iin;
  final VoidCallback? onViewAll;

  const CalendarCard({
    super.key,
    required this.iin,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.calendar_today, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Upcoming',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (onViewAll != null)
                  TextButton(
                    onPressed: onViewAll,
                    child: const Text('View All'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            CalendarWidget(
              iin: iin,
              lookaheadDays: 3,
            ),
          ],
        ),
      ),
    );
  }
}
