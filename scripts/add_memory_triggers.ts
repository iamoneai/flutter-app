import * as admin from 'firebase-admin';

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function addMissingTriggers() {
  const docRef = db.collection('config').doc('pipeline')
    .collection('stages').doc('memory_extraction');

  console.log('Adding missing triggers to memory_extraction config...');

  // New triggers to add
  const newFactTriggers = [
    'i just got',
    'i recently',
    'i now have',
    'i have a',
    'i got a',
    'i bought',
    'i just bought',
    'i just started',
    'i just finished',
  ];

  const newPreferenceTriggers = [
    'i really enjoy',
    'i really like',
    'i enjoy',
    'i prefer',
    'i always',
    'i usually',
  ];

  const newRelationshipTriggers = [
    'my friend',
    'my cousin',
    'my uncle',
    'my aunt',
    'my nephew',
    'my niece',
    'my coworker',
    'my colleague',
    'my boss',
    'my neighbor',
  ];

  try {
    // Use arrayUnion to add without duplicates
    await docRef.update({
      'triggers.fact': admin.firestore.FieldValue.arrayUnion(...newFactTriggers),
      'triggers.preference': admin.firestore.FieldValue.arrayUnion(...newPreferenceTriggers),
      'triggers.relationship': admin.firestore.FieldValue.arrayUnion(...newRelationshipTriggers),
    });

    console.log('✅ Triggers added successfully!');
    console.log('');
    console.log('Added to fact:', newFactTriggers);
    console.log('Added to preference:', newPreferenceTriggers);
    console.log('Added to relationship:', newRelationshipTriggers);

    // Verify by reading back
    const doc = await docRef.get();
    const data = doc.data();
    console.log('');
    console.log('Current trigger counts:');
    console.log('  fact:', data?.triggers?.fact?.length || 0);
    console.log('  preference:', data?.triggers?.preference?.length || 0);
    console.log('  relationship:', data?.triggers?.relationship?.length || 0);
    console.log('  event:', data?.triggers?.event?.length || 0);
    console.log('  todo:', data?.triggers?.todo?.length || 0);
    console.log('  goal:', data?.triggers?.goal?.length || 0);

  } catch (error) {
    console.error('Error adding triggers:', error);
    throw error;
  }
}

addMissingTriggers()
  .then(() => {
    console.log('');
    console.log('Done! Run pipeline tests again to verify.');
    process.exit(0);
  })
  .catch(err => {
    console.error('Failed:', err);
    process.exit(1);
  });
