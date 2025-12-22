import * as admin from 'firebase-admin';

// Initialize if not already
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

async function addMissingTriggers() {
  const docRef = db.collection('config').doc('pipeline')
    .collection('stages').doc('memory_extraction');

  // New triggers to add
  const newFactTriggers = [
    'i just got',
    'i recently',
    'i now have',
    'i have a',
    'i bought',
    'i got a'
  ];

  const newPreferenceTriggers = [
    'i really enjoy',
    'i really like',
    'i enjoy',
    'i prefer'
  ];

  // Use arrayUnion to add without duplicates
  await docRef.update({
    'triggers.fact': admin.firestore.FieldValue.arrayUnion(...newFactTriggers),
    'triggers.preference': admin.firestore.FieldValue.arrayUnion(...newPreferenceTriggers),
  });

  console.log('✅ Triggers added successfully!');
  console.log('Added to fact:', newFactTriggers);
  console.log('Added to preference:', newPreferenceTriggers);
}

addMissingTriggers()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
