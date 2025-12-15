const admin = require('firebase-admin');
admin.initializeApp();

admin.auth().listUsers(10)
  .then(result => {
    console.log('Firebase Auth Users:');
    result.users.forEach(user => {
      console.log('\nUID:', user.uid);
      console.log('Email:', user.email);
      console.log('Provider:', user.providerData[0]?.providerId);
    });
    process.exit(0);
  })
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
