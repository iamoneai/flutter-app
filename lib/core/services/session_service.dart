import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/iin.dart';
import '../models/iin_access.dart';
import '../models/user_session.dart';
import '../models/entity.dart';

/// Session Service - Manages user's active IIN context
/// All business logic operates on activeIinId, never on userId
class SessionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  CollectionReference get _userSessionsCollection => _firestore.collection('user_sessions');
  CollectionReference get _iinsCollection => _firestore.collection('iins');
  CollectionReference get _iinAccessCollection => _firestore.collection('iin_access');
  CollectionReference get _entitiesCollection => _firestore.collection('entities');
  CollectionReference get _usersCollection => _firestore.collection('users');

  /// Get the current active IIN for a user
  Future<String?> getActiveIIN(String uid) async {
    final doc = await _userSessionsCollection.doc(uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>?;
      return data?['activeIinId'];
    }
    return null;
  }

  /// Set the active IIN for a user
  Future<void> setActiveIIN(String uid, String iinId) async {
    // Verify user has access to this IIN
    final hasAccess = await _verifyIINAccess(uid, iinId);
    if (!hasAccess) {
      throw Exception('User does not have access to this IIN');
    }

    await _userSessionsCollection.doc(uid).set({
      'activeIinId': iinId,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint('Active IIN set to $iinId for user $uid');
  }

  /// Watch the user session for changes
  Stream<UserSession?> watchSession(String uid) {
    return _userSessionsCollection.doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserSession.fromFirestore(doc);
      }
      return null;
    });
  }

  /// Get all IINs the user has access to with their context
  Future<List<IINContext>> getUserIINContexts(String uid) async {
    // Get all access records for this user
    final accessQuery = await _iinAccessCollection
        .where('uid', isEqualTo: uid)
        .where('active', isEqualTo: true)
        .get();

    final List<IINContext> contexts = [];

    for (final accessDoc in accessQuery.docs) {
      final access = IINAccess.fromFirestore(accessDoc);

      // Get the IIN
      final iinDoc = await _iinsCollection.doc(access.iinId).get();
      if (!iinDoc.exists) continue;

      final iin = IIN.fromFirestore(iinDoc);
      if (!iin.isActive) continue;

      // Build context based on IIN type
      String displayName;
      String? entityName;

      if (iin.isPersonal) {
        // Get user's display name
        final userDoc = await _usersCollection.doc(iin.ownerId).get();
        final userData = userDoc.data() as Map<String, dynamic>?;
        displayName = userData?['displayName'] ?? 'Personal';
      } else {
        // Get entity name
        final entityDoc = await _entitiesCollection.doc(iin.ownerId).get();
        if (entityDoc.exists) {
          final entity = Entity.fromFirestore(entityDoc);
          entityName = entity.name;
          displayName = iin.isEntityBrain
              ? '${entity.name} (Admin)'
              : '${entity.name} (Employee)';
        } else {
          displayName = 'Unknown Entity';
        }
      }

      contexts.add(IINContext(
        iin: iin,
        access: access,
        displayName: displayName,
        entityName: entityName,
      ));
    }

    // Sort: personal first, then by entity name
    contexts.sort((a, b) {
      if (a.iin.isPersonal && !b.iin.isPersonal) return -1;
      if (!a.iin.isPersonal && b.iin.isPersonal) return 1;
      return a.displayName.compareTo(b.displayName);
    });

    return contexts;
  }

  /// Get the current active IIN context
  Future<IINContext?> getActiveIINContext(String uid) async {
    final activeIinId = await getActiveIIN(uid);
    if (activeIinId == null) return null;

    final contexts = await getUserIINContexts(uid);
    return contexts.cast<IINContext?>().firstWhere(
      (c) => c?.iin.iinId == activeIinId,
      orElse: () => null,
    );
  }

  /// Switch to personal IIN
  Future<void> switchToPersonal(String uid) async {
    final userDoc = await _usersCollection.doc(uid).get();
    if (!userDoc.exists) throw Exception('User not found');

    final userData = userDoc.data() as Map<String, dynamic>;
    final personalIinId = userData['personalIinId'];

    if (personalIinId == null) {
      throw Exception('User does not have a personal IIN');
    }

    await setActiveIIN(uid, personalIinId);
  }

  /// Switch to an entity IIN
  Future<void> switchToEntity(String uid, String entityId) async {
    // Find the user's IIN for this entity
    final contexts = await getUserIINContexts(uid);
    final entityContext = contexts.cast<IINContext?>().firstWhere(
      (c) => c?.iin.ownerId == entityId && !c!.iin.isPersonal,
      orElse: () => null,
    );

    if (entityContext == null) {
      throw Exception('User does not have access to this entity');
    }

    await setActiveIIN(uid, entityContext.iin.iinId);
  }

  /// Verify user has access to an IIN
  Future<bool> _verifyIINAccess(String uid, String iinId) async {
    final query = await _iinAccessCollection
        .where('uid', isEqualTo: uid)
        .where('iinId', isEqualTo: iinId)
        .where('active', isEqualTo: true)
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  /// Get the user's role for the active IIN
  Future<String?> getActiveRole(String uid) async {
    final activeIinId = await getActiveIIN(uid);
    if (activeIinId == null) return null;

    final query = await _iinAccessCollection
        .where('uid', isEqualTo: uid)
        .where('iinId', isEqualTo: activeIinId)
        .where('active', isEqualTo: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;

    final data = query.docs.first.data() as Map<String, dynamic>;
    return data['role'];
  }

  /// Check if user is currently in personal context
  Future<bool> isInPersonalContext(String uid) async {
    final activeIinId = await getActiveIIN(uid);
    if (activeIinId == null) return true;

    final iinDoc = await _iinsCollection.doc(activeIinId).get();
    if (!iinDoc.exists) return true;

    final data = iinDoc.data() as Map<String, dynamic>;
    return data['iinType'] == 'personal';
  }

  /// Check if user is currently in entity context
  Future<bool> isInEntityContext(String uid) async {
    return !(await isInPersonalContext(uid));
  }
}

/// IIN Context - Combines IIN, access, and display info
class IINContext {
  final IIN iin;
  final IINAccess access;
  final String displayName;
  final String? entityName;

  IINContext({
    required this.iin,
    required this.access,
    required this.displayName,
    this.entityName,
  });

  bool get isPersonal => iin.isPersonal;
  bool get isEntityBrain => iin.isEntityBrain;
  bool get isEntityEmployee => iin.isEntityEmployee;
  String get role => access.role;
  bool get hasAdminAccess => access.hasAdminAccess;
}
