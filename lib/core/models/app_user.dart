import 'package:cloud_firestore/cloud_firestore.dart';

/// App User Model - Stored in /users/{uid}
/// Base user profile for all users
class AppUser {
  final String uid;
  final String email;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? personalIinId; // Their personal IIN
  final String status; // 'active', 'suspended', 'deleted'
  final String role; // 'user', 'admin', 'super_admin', etc.
  final DateTime createdAt;
  final DateTime? updatedAt;

  AppUser({
    required this.uid,
    required this.email,
    this.displayName,
    this.firstName,
    this.lastName,
    this.personalIinId,
    required this.status,
    required this.role,
    required this.createdAt,
    this.updatedAt,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'],
      firstName: data['firstName'],
      lastName: data['lastName'],
      personalIinId: data['personalIinId'],
      status: data['status'] ?? 'active',
      role: data['role'] ?? 'user',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      if (displayName != null) 'displayName': displayName,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (personalIinId != null) 'personalIinId': personalIinId,
      'status': status,
      'role': role,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  bool get isActive => status == 'active';
  bool get hasPersonalIIN => personalIinId != null && personalIinId!.isNotEmpty;

  String get fullName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return displayName ?? email.split('@').first;
  }

  AppUser copyWith({
    String? displayName,
    String? firstName,
    String? lastName,
    String? personalIinId,
    String? status,
    String? role,
    DateTime? updatedAt,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      personalIinId: personalIinId ?? this.personalIinId,
      status: status ?? this.status,
      role: role ?? this.role,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
