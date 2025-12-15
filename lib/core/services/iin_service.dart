import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/iin_generator.dart';
import '../models/iin.dart';
import '../models/iin_access.dart';
import '../models/user_session.dart';

/// IIN Service - Handles all IIN operations
class IINService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  CollectionReference get _iinsCollection => _firestore.collection('iins');
  CollectionReference get _iinAccessCollection => _firestore.collection('iin_access');
  CollectionReference get _userSessionsCollection => _firestore.collection('user_sessions');
  CollectionReference get _usersCollection => _firestore.collection('users');

  /// Create a Personal IIN for a new user
  /// Called automatically after user registration
  Future<String> createPersonalIIN(String uid) async {
    final iinId = IINGenerator.generatePersonalIIN();

    // Create the IIN document
    await _iinsCollection.doc(iinId).set({
      'iinType': 'personal',
      'ownerType': 'user',
      'ownerId': uid,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create the access mapping (user owns their personal IIN)
    await _iinAccessCollection.add({
      'iinId': iinId,
      'uid': uid,
      'role': 'owner',
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update user profile with their personal IIN
    await _usersCollection.doc(uid).update({
      'personalIinId': iinId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Set this as the active IIN
    await setActiveIIN(uid, iinId);

    return iinId;
  }

  /// Create an Entity Brain IIN for a new entity
  Future<String> createEntityBrainIIN(String entityId, String creatorUid) async {
    final iinId = IINGenerator.generateEntityIIN();

    // Create the IIN document
    await _iinsCollection.doc(iinId).set({
      'iinType': 'entity_brain',
      'ownerType': 'entity',
      'ownerId': entityId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create the access mapping (creator is admin)
    await _iinAccessCollection.add({
      'iinId': iinId,
      'uid': creatorUid,
      'role': 'admin',
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return iinId;
  }

  /// Create an Employee IIN for a user joining an entity
  Future<String> createEmployeeIIN(String entityId, String uid) async {
    final iinId = IINGenerator.generateEntityEmployeeIIN();

    // Create the IIN document
    await _iinsCollection.doc(iinId).set({
      'iinType': 'entity_employee',
      'ownerType': 'entity',
      'ownerId': entityId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create the access mapping
    await _iinAccessCollection.add({
      'iinId': iinId,
      'uid': uid,
      'role': 'member',
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return iinId;
  }

  /// Set the user's active IIN
  Future<void> setActiveIIN(String uid, String iinId) async {
    await _userSessionsCollection.doc(uid).set({
      'activeIinId': iinId,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Get the user's active IIN
  Future<String?> getActiveIIN(String uid) async {
    final doc = await _userSessionsCollection.doc(uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;
      return data?['activeIinId'];
    }
    return null;
  }

  /// Get user session stream
  Stream<UserSession?> watchUserSession(String uid) {
    return _userSessionsCollection.doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserSession.fromFirestore(doc);
      }
      return null;
    });
  }

  /// Get IIN by ID
  Future<IIN?> getIIN(String iinId) async {
    final doc = await _iinsCollection.doc(iinId).get();
    if (doc.exists) {
      return IIN.fromFirestore(doc);
    }
    return null;
  }

  /// Get all IINs a user has access to
  Future<List<IIN>> getUserIINs(String uid) async {
    // Get all access records for this user
    final accessQuery = await _iinAccessCollection
        .where('uid', isEqualTo: uid)
        .where('active', isEqualTo: true)
        .get();

    final iinIds = accessQuery.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['iinId'] as String;
    }).toList();

    if (iinIds.isEmpty) return [];

    // Get all IIN documents
    final List<IIN> iins = [];
    for (final iinId in iinIds) {
      final iin = await getIIN(iinId);
      if (iin != null && iin.isActive) {
        iins.add(iin);
      }
    }

    return iins;
  }

  /// Get user's access record for a specific IIN
  Future<IINAccess?> getUserIINAccess(String uid, String iinId) async {
    final query = await _iinAccessCollection
        .where('uid', isEqualTo: uid)
        .where('iinId', isEqualTo: iinId)
        .where('active', isEqualTo: true)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return IINAccess.fromFirestore(query.docs.first);
    }
    return null;
  }

  /// Grant access to an IIN for a user
  Future<void> grantIINAccess(String iinId, String uid, String role) async {
    // Check if access already exists
    final existing = await getUserIINAccess(uid, iinId);
    if (existing != null) {
      // Update existing access
      await _iinAccessCollection.doc(existing.id).update({
        'role': role,
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Create new access
      await _iinAccessCollection.add({
        'iinId': iinId,
        'uid': uid,
        'role': role,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Revoke access to an IIN for a user
  Future<void> revokeIINAccess(String iinId, String uid) async {
    final query = await _iinAccessCollection
        .where('uid', isEqualTo: uid)
        .where('iinId', isEqualTo: iinId)
        .get();

    for (final doc in query.docs) {
      await doc.reference.update({
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Check if user has access to an IIN
  Future<bool> hasAccess(String uid, String iinId) async {
    final access = await getUserIINAccess(uid, iinId);
    return access != null && access.active;
  }

  /// Suspend an IIN
  Future<void> suspendIIN(String iinId) async {
    await _iinsCollection.doc(iinId).update({
      'status': 'suspended',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reactivate an IIN
  Future<void> reactivateIIN(String iinId) async {
    await _iinsCollection.doc(iinId).update({
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
