const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function fixPermissions() {
  const users = ['admin@iamoneai.com', 'mariodepinho@gmail.com'];
  
  for (const email of users) {
    await db.collection('admin_users').doc(email).update({
      permissions: ['all']
    });
    console.log(`Fixed permissions for ${email}`);
  }
  
  console.log('Done!');
  process.exit(0);
}

fixPermissions();
