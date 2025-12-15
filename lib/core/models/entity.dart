import 'package:cloud_firestore/cloud_firestore.dart';

/// Entity Model - Stored in /entities/{entityId}
/// Represents a business/organization
class Entity {
  final String entityId;
  final String name;
  final String? description;
  final String status; // 'active', 'suspended', 'deleted'
  final String ownerUid; // Creator's uid
  final String? brainIinId; // Entity Brain IIN
  final DateTime createdAt;
  final DateTime? updatedAt;

  Entity({
    required this.entityId,
    required this.name,
    this.description,
    required this.status,
    required this.ownerUid,
    this.brainIinId,
    required this.createdAt,
    this.updatedAt,
  });

  factory Entity.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Entity(
      entityId: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      status: data['status'] ?? 'active',
      ownerUid: data['ownerUid'] ?? '',
      brainIinId: data['brainIinId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      if (description != null) 'description': description,
      'status': status,
      'ownerUid': ownerUid,
      if (brainIinId != null) 'brainIinId': brainIinId,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  bool get isActive => status == 'active';

  Entity copyWith({
    String? name,
    String? description,
    String? status,
    String? brainIinId,
    DateTime? updatedAt,
  }) {
    return Entity(
      entityId: entityId,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      ownerUid: ownerUid,
      brainIinId: brainIinId ?? this.brainIinId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
