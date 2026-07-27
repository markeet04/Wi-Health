const admin = require('firebase-admin');
const {readFileSync} = require('node:fs');
const serviceAccount = JSON.parse(readFileSync('secrets/serviceAccount.json', 'utf8'));
admin.initializeApp({credential: admin.credential.cert(serviceAccount), databaseURL: 'https://wi-health-faa5d-default-rtdb.asia-southeast1.firebasedatabase.app'});
const db = admin.database();
(async () => {
  const usersSnap = await db.ref('users').get();
  const devices = {};
  for (const id of ['seed-device-1','seed-device-2','seed-device-3','seed-device-4']) {
    const snap = await db.ref(`devices/${id}`).get();
    devices[id] = snap.exists() ? snap.val() : null;
  }
  console.log('usersCount=', usersSnap.exists() ? Object.keys(usersSnap.val()).length : 0);
  console.log(JSON.stringify({ users: usersSnap.exists() ? usersSnap.val() : null, devices }, null, 2));
})();
