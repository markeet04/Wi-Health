const admin = require('firebase-admin');
const {readFileSync} = require('node:fs');
const serviceAccount = JSON.parse(readFileSync('secrets/serviceAccount.json', 'utf8'));
admin.initializeApp({credential: admin.credential.cert(serviceAccount), databaseURL: 'https://wi-health-faa5d-default-rtdb.asia-southeast1.firebasedatabase.app'});
const db = admin.database();
(async () => {
  const uid = 'Bw5UvRv64GPA1H4iuPi9OqCciox1';
  const updates = {
    [`users/${uid}/devices/seed-device-1`]: true,
    [`users/${uid}/devices/seed-device-2`]: true,
    'devices/seed-device-1/meta/ownerUid': uid,
    'devices/seed-device-2/meta/ownerUid': uid,
  };
  await db.ref().update(updates);
  console.log('Linked devices seed-device-1 and seed-device-2 to', uid);
  const userDevices = await db.ref(`users/${uid}/devices`).get();
  const dev1Owner = await db.ref('devices/seed-device-1/meta/ownerUid').get();
  const dev2Owner = await db.ref('devices/seed-device-2/meta/ownerUid').get();
  console.log('userDevices=', userDevices.exists() ? userDevices.val() : null);
  console.log('dev1Owner=', dev1Owner.exists() ? dev1Owner.val() : null);
  console.log('dev2Owner=', dev2Owner.exists() ? dev2Owner.val() : null);
})();
