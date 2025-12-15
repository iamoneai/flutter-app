const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

db.collection('admin').doc('tech_docs').collection('modules').get()
  .then(snap => {
    console.log('Total modules:', snap.size);
    snap.forEach(doc => {
      const data = doc.data();
      console.log('ID:', doc.id, '| order:', data.order, '| name:', data.name);
    });
    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
