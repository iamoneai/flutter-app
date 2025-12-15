import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

// Initialize if not already
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// ============================================
// HELPER: Generate IIN
// ============================================
function generateIIN(): string {
  const now = new Date();
  const year = now.getFullYear().toString().slice(-2);
  const month = (now.getMonth() + 1).toString().padStart(2, '0');
  const random1 = crypto.randomBytes(2).toString('hex').toUpperCase();
  const random2 = crypto.randomBytes(2).toString('hex').toUpperCase();
  return `20AA-${year}${month}-${random1}-${random2}`;
}

// ============================================
// HELPER: Create identity hash
// ============================================
function createIdentityHash(firstName: string, lastName: string, email: string): string {
  const data = `${firstName.toLowerCase()}:${lastName.toLowerCase()}:${email.toLowerCase()}`;
  return crypto.createHash('sha256').update(data).digest('hex');
}

// ============================================
// POST /user-auth/register
// Creates Firebase Auth user profile with IIN
// ============================================
export const userAuthRegister = functions.https.onRequest(async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const { uid, email, firstName, lastName } = req.body;

    // Validate required fields
    if (!uid || !email || !firstName || !lastName) {
      res.status(400).json({ 
        error: 'Missing required fields',
        required: ['uid', 'email', 'firstName', 'lastName']
      });
      return;
    }

    // Check if user already exists
    const existingUser = await db.collection('users').doc(uid).get();
    if (existingUser.exists) {
      const data = existingUser.data();
      res.status(200).json({
        message: 'User already exists',
        iin: data?.iin,
        isExisting: true
      });
      return;
    }

    // Generate unique IIN
    let iin = generateIIN();
    let iinExists = true;
    let attempts = 0;

    while (iinExists && attempts < 10) {
      const iinCheck = await db.collection('users')
        .where('iin', '==', iin)
        .limit(1)
        .get();
      
      if (iinCheck.empty) {
        iinExists = false;
      } else {
        iin = generateIIN();
        attempts++;
      }
    }

    // Create identity hash
    const identityHash = createIdentityHash(firstName, lastName, email);

    // Create user document
    const userData = {
      iin,
      identityHash,
      email: email.toLowerCase(),
      firstName,
      lastName,
      displayName: `${firstName} ${lastName}`,
      status: 'ACTIVE',
      role: 'user',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Save to Firestore (document ID = Firebase UID)
    await db.collection('users').doc(uid).set(userData);

    // Also create auth_mapping for IIN lookup
    await db.collection('auth_mapping').doc(iin).set({
      uid,
      iin,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`User registered: ${iin} (${email})`);

    res.status(201).json({
      success: true,
      iin,
      message: 'User registered successfully'
    });

  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ 
      error: 'Registration failed',
      details: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});

// ============================================
// GET /user-auth/profile?iin=XXXX-XXXX-XXXX-XXXX
// Get user profile by IIN
// ============================================
export const userAuthProfile = functions.https.onRequest(async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const iin = req.query.iin as string;

    if (!iin) {
      res.status(400).json({ error: 'IIN is required' });
      return;
    }

    // Find user by IIN
    const usersSnapshot = await db.collection('users')
      .where('iin', '==', iin)
      .limit(1)
      .get();

    if (usersSnapshot.empty) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const userDoc = usersSnapshot.docs[0];
    const userData = userDoc.data();

    res.status(200).json({
      success: true,
      profile: {
        iin: userData.iin,
        firstName: userData.firstName,
        lastName: userData.lastName,
        displayName: userData.displayName,
        email: userData.email,
        status: userData.status,
        createdAt: userData.createdAt,
      }
    });

  } catch (error) {
    console.error('Profile fetch error:', error);
    res.status(500).json({ 
      error: 'Failed to fetch profile',
      details: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});

// ============================================
// GET /user-auth/profile-by-uid?uid=XXXXX
// Get user profile by Firebase UID (for login flow)
// ============================================
export const userAuthProfileByUid = functions.https.onRequest(async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const uid = req.query.uid as string;

    if (!uid) {
      res.status(400).json({ error: 'UID is required' });
      return;
    }

    // Get user by Firebase UID
    const userDoc = await db.collection('users').doc(uid).get();

    if (!userDoc.exists) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const userData = userDoc.data();

    res.status(200).json({
      success: true,
      profile: {
        iin: userData?.iin,
        firstName: userData?.firstName,
        lastName: userData?.lastName,
        displayName: userData?.displayName,
        email: userData?.email,
        status: userData?.status,
        createdAt: userData?.createdAt,
      }
    });

  } catch (error) {
    console.error('Profile fetch error:', error);
    res.status(500).json({ 
      error: 'Failed to fetch profile',
      details: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});

// ============================================
// PUT /user-auth/profile
// Update user profile
// ============================================
export const userAuthUpdateProfile = functions.https.onRequest(async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'PUT, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'PUT') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  try {
    const { iin, updates } = req.body;

    if (!iin) {
      res.status(400).json({ error: 'IIN is required' });
      return;
    }

    // Find user by IIN
    const usersSnapshot = await db.collection('users')
      .where('iin', '==', iin)
      .limit(1)
      .get();

    if (usersSnapshot.empty) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const userDoc = usersSnapshot.docs[0];

    // Only allow certain fields to be updated
    const allowedUpdates: Record<string, any> = {};
    const allowedFields = ['firstName', 'lastName', 'displayName'];

    for (const field of allowedFields) {
      if (updates[field] !== undefined) {
        allowedUpdates[field] = updates[field];
      }
    }

    if (Object.keys(allowedUpdates).length === 0) {
      res.status(400).json({ error: 'No valid fields to update' });
      return;
    }

    allowedUpdates.updatedAt = admin.firestore.FieldValue.serverTimestamp();

    await userDoc.ref.update(allowedUpdates);

    res.status(200).json({
      success: true,
      message: 'Profile updated successfully',
      updated: Object.keys(allowedUpdates).filter(k => k !== 'updatedAt')
    });

  } catch (error) {
    console.error('Profile update error:', error);
    res.status(500).json({ 
      error: 'Failed to update profile',
      details: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});
