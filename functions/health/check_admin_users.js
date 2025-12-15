const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

db.collection('admin_users').get()
  .then(snap => {
    console.log('admin_users collection - Total docs:', snap.size);
    snap.forEach(doc => {
      console.log('\nDoc ID:', doc.id);
      console.log('Data:', JSON.stringify(doc.data(), null, 2));
    });
    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
