import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'entity_login_screen.dart';
import 'entity_dashboard.dart';

/// Entity Auth Wrapper - Checks if user has entity access
class EntityAuthWrapper extends StatelessWidget {
  const EntityAuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          return const EntityLoginScreen();
        }

        // Check if user has any entity access
        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('iin_access')
              .where('uid', isEqualTo: snapshot.data!.uid)
              .where('active', isEqualTo: true)
              .get(),
          builder: (context, accessSnapshot) {
            if (accessSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!accessSnapshot.hasData || accessSnapshot.data!.docs.isEmpty) {
              return const EntityLoginScreen(
                message: 'No entity access found. Please contact an admin to get invited.',
              );
            }

            // Check if any access is for entity IINs
            return FutureBuilder<bool>(
              future: _hasEntityAccess(snapshot.data!.uid, accessSnapshot.data!.docs),
              builder: (context, entityAccessSnapshot) {
                if (entityAccessSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                if (entityAccessSnapshot.data != true) {
                  return const EntityLoginScreen(
                    message: 'No entity access found. Create or join an entity to access this dashboard.',
                  );
                }

                return const EntityDashboard();
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _hasEntityAccess(String uid, List<QueryDocumentSnapshot> accessDocs) async {
    for (final doc in accessDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final iinId = data['iinId'] as String;

      final iinDoc = await FirebaseFirestore.instance.collection('iins').doc(iinId).get();
      if (iinDoc.exists) {
        final iinData = iinDoc.data() as Map<String, dynamic>;
        final iinType = iinData['iinType'] as String?;
        if (iinType == 'entity_brain' || iinType == 'entity_employee') {
          return true;
        }
      }
    }
    return false;
  }
}
