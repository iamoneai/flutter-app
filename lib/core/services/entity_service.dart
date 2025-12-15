import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../utils/iin_generator.dart';
import '../models/entity.dart';
import '../models/entity_employee.dart';
import '../models/iin_access.dart';

/// Entity Service - Handles all Entity (Business) operations
class EntityService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  CollectionReference get _entitiesCollection => _firestore.collection('entities');
  CollectionReference get _iinsCollection => _firestore.collection('iins');
  CollectionReference get _iinAccessCollection => _firestore.collection('iin_access');
  CollectionReference get _entityEmployeesCollection => _firestore.collection('entity_employees');
  CollectionReference get _invitationsCollection => _firestore.collection('entity_invitations');

  /// Create a new Entity (Business)
  /// Returns the entity ID and brain IIN
  Future<Map<String, String>> createEntity({
    required String name,
    required String creatorUid,
    String? description,
  }) async {
    try {
      // 1. Generate Entity Brain IIN (20EE-YYMM-XXXX-XXXX)
      final brainIinId = IINGenerator.generateEntityIIN();

      // 2. Create entity document
      final entityRef = _entitiesCollection.doc();
      final entityId = entityRef.id;

      await entityRef.set({
        'name': name,
        'description': description,
        'status': 'active',
        'ownerUid': creatorUid,
        'brainIinId': brainIinId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3. Create Entity Brain IIN document
      await _iinsCollection.doc(brainIinId).set({
        'iinType': 'entity_brain',
        'ownerType': 'entity',
        'ownerId': entityId,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. Grant creator admin access to the entity brain IIN
      await _iinAccessCollection.add({
        'iinId': brainIinId,
        'uid': creatorUid,
        'role': 'admin',
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Entity created: $entityId with Brain IIN: $brainIinId');

      return {
        'entityId': entityId,
        'brainIinId': brainIinId,
      };
    } catch (e) {
      debugPrint('Error creating entity: $e');
      rethrow;
    }
  }

  /// Get entity by ID
  Future<Entity?> getEntity(String entityId) async {
    final doc = await _entitiesCollection.doc(entityId).get();
    if (doc.exists) {
      return Entity.fromFirestore(doc);
    }
    return null;
  }

  /// Get all entities owned by a user
  Future<List<Entity>> getUserOwnedEntities(String uid) async {
    final query = await _entitiesCollection
        .where('ownerUid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .get();

    return query.docs.map((doc) => Entity.fromFirestore(doc)).toList();
  }

  /// Get all entities a user has access to (via IIN access)
  Future<List<Entity>> getUserAccessibleEntities(String uid) async {
    // Get all entity brain IINs the user has access to
    final accessQuery = await _iinAccessCollection
        .where('uid', isEqualTo: uid)
        .where('active', isEqualTo: true)
        .get();

    final List<Entity> entities = [];

    for (final accessDoc in accessQuery.docs) {
      final data = accessDoc.data() as Map<String, dynamic>;
      final iinId = data['iinId'] as String;

      // Get the IIN to find the entity
      final iinDoc = await _iinsCollection.doc(iinId).get();
      if (iinDoc.exists) {
        final iinData = iinDoc.data() as Map<String, dynamic>;
        if (iinData['iinType'] == 'entity_brain' || iinData['iinType'] == 'entity_employee') {
          final entityId = iinData['ownerId'] as String;
          final entity = await getEntity(entityId);
          if (entity != null && entity.isActive && !entities.any((e) => e.entityId == entityId)) {
            entities.add(entity);
          }
        }
      }
    }

    return entities;
  }

  /// Update entity details
  Future<void> updateEntity(String entityId, {
    String? name,
    String? description,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;

    await _entitiesCollection.doc(entityId).update(updates);
  }

  /// Suspend an entity
  Future<void> suspendEntity(String entityId) async {
    await _entitiesCollection.doc(entityId).update({
      'status': 'suspended',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reactivate an entity
  Future<void> reactivateEntity(String entityId) async {
    await _entitiesCollection.doc(entityId).update({
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Invite an employee to the entity
  Future<String> inviteEmployee({
    required String entityId,
    required String email,
    required String invitedByUid,
    String role = 'member',
  }) async {
    // Check if invitation already exists
    final existingQuery = await _invitationsCollection
        .where('entityId', isEqualTo: entityId)
        .where('email', isEqualTo: email.toLowerCase())
        .where('status', isEqualTo: 'pending')
        .get();

    if (existingQuery.docs.isNotEmpty) {
      throw Exception('An invitation for this email already exists');
    }

    // Create invitation
    final inviteRef = _invitationsCollection.doc();
    final expiresAt = DateTime.now().add(const Duration(days: 7));

    await inviteRef.set({
      'entityId': entityId,
      'email': email.toLowerCase(),
      'role': role,
      'status': 'pending',
      'invitedByUid': invitedByUid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    debugPrint('Invitation created for $email to entity $entityId');
    return inviteRef.id;
  }

  /// Accept an invitation and create employee IIN
  Future<String> acceptInvitation({
    required String invitationId,
    required String uid,
  }) async {
    // Get invitation
    final inviteDoc = await _invitationsCollection.doc(invitationId).get();
    if (!inviteDoc.exists) {
      throw Exception('Invitation not found');
    }

    final invitation = EntityInvitation.fromFirestore(inviteDoc);

    if (invitation.status != 'pending') {
      throw Exception('Invitation is no longer valid');
    }

    if (invitation.isExpired) {
      await _invitationsCollection.doc(invitationId).update({'status': 'expired'});
      throw Exception('Invitation has expired');
    }

    // Generate Employee IIN (20AE-YYMM-XXXX-XXXX)
    final employeeIinId = IINGenerator.generateEntityEmployeeIIN();

    // Create Employee IIN document
    await _iinsCollection.doc(employeeIinId).set({
      'iinType': 'entity_employee',
      'ownerType': 'entity',
      'ownerId': invitation.entityId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create IIN access mapping
    await _iinAccessCollection.add({
      'iinId': employeeIinId,
      'uid': uid,
      'role': invitation.role,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create entity employee record
    final employeeId = EntityEmployee.createId(invitation.entityId, uid);
    await _entityEmployeesCollection.doc(employeeId).set({
      'entityId': invitation.entityId,
      'uid': uid,
      'employeeIinId': employeeIinId,
      'status': 'active',
      'role': invitation.role,
      'departmentIds': [],
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update invitation status
    await _invitationsCollection.doc(invitationId).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('Employee $uid joined entity ${invitation.entityId} with IIN: $employeeIinId');
    return employeeIinId;
  }

  /// Get pending invitations for a user's email
  Future<List<EntityInvitation>> getPendingInvitations(String email) async {
    final query = await _invitationsCollection
        .where('email', isEqualTo: email.toLowerCase())
        .where('status', isEqualTo: 'pending')
        .get();

    return query.docs.map((doc) => EntityInvitation.fromFirestore(doc)).toList();
  }

  /// Get entity employees
  Future<List<EntityEmployee>> getEntityEmployees(String entityId) async {
    final query = await _entityEmployeesCollection
        .where('entityId', isEqualTo: entityId)
        .where('status', isEqualTo: 'active')
        .get();

    return query.docs.map((doc) => EntityEmployee.fromFirestore(doc)).toList();
  }

  /// Remove employee from entity
  Future<void> removeEmployee(String entityId, String uid) async {
    final employeeId = EntityEmployee.createId(entityId, uid);

    // Get employee to find their IIN
    final employeeDoc = await _entityEmployeesCollection.doc(employeeId).get();
    if (!employeeDoc.exists) return;

    final employee = EntityEmployee.fromFirestore(employeeDoc);

    // Revoke IIN access
    final accessQuery = await _iinAccessCollection
        .where('iinId', isEqualTo: employee.employeeIinId)
        .where('uid', isEqualTo: uid)
        .get();

    for (final doc in accessQuery.docs) {
      await doc.reference.update({
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Update employee status
    await _entityEmployeesCollection.doc(employeeId).update({
      'status': 'removed',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('Employee $uid removed from entity $entityId');
  }

  /// Update employee role
  Future<void> updateEmployeeRole(String entityId, String uid, String newRole) async {
    final employeeId = EntityEmployee.createId(entityId, uid);

    // Update employee role
    await _entityEmployeesCollection.doc(employeeId).update({
      'role': newRole,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Get employee to find their IIN
    final employeeDoc = await _entityEmployeesCollection.doc(employeeId).get();
    if (!employeeDoc.exists) return;

    final employee = EntityEmployee.fromFirestore(employeeDoc);

    // Update IIN access role
    final accessQuery = await _iinAccessCollection
        .where('iinId', isEqualTo: employee.employeeIinId)
        .where('uid', isEqualTo: uid)
        .where('active', isEqualTo: true)
        .get();

    for (final doc in accessQuery.docs) {
      await doc.reference.update({
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
