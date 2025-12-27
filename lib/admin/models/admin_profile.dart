// IAMONEAI - Admin Profile Model
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminProfile {
  final String uid;
  final String email;
  String firstName;
  String lastName;
  String? iin;
  final DateTime createdAt;
  DateTime updatedAt;

  AdminProfile({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    this.iin,
    required this.createdAt,
    required this.updatedAt,
  });

  String get displayName {
    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      return '$firstName $lastName'.trim();
    }
    return email.split('@').first;
  }

  factory AdminProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdminProfile(
      uid: doc.id,
      email: data['email'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      iin: data['iin'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'iin': iin,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  AdminProfile copyWith({
    String? firstName,
    String? lastName,
    String? iin,
  }) {
    return AdminProfile(
      uid: uid,
      email: email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      iin: iin ?? this.iin,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
