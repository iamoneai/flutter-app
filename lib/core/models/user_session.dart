import 'package:cloud_firestore/cloud_firestore.dart';

/// User Session Model - Stored in /user_sessions/{uid}
/// Tracks the user's currently active IIN context
class UserSession {
  final String uid;
  final String activeIinId;
  final DateTime lastUpdated;

  UserSession({
    required this.uid,
    required this.activeIinId,
    required this.lastUpdated,
  });

  factory UserSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserSession(
      uid: doc.id,
      activeIinId: data['activeIinId'] ?? '',
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'activeIinId': activeIinId,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  UserSession copyWith({
    String? activeIinId,
    DateTime? lastUpdated,
  }) {
    return UserSession(
      uid: uid,
      activeIinId: activeIinId ?? this.activeIinId,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
