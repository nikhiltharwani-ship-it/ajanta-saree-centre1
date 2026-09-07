const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();

const ADMINS = {
  nikhilasc: '0521',
  kailashasc: '2105',
};
const adminEmail = (id) => `${id}@ajantasareecentre.app`;
const customerEmail = (id) => `${String(id).trim().toLowerCase()}@customers.ajantasareecentre.app`;

function requireAdmin(request) {
  if (request.auth?.token?.role !== 'admin') {
    throw new HttpsError('permission-denied', 'Admin access required.');
  }
}

async function ensureAdminUser(id) {
  const email = adminEmail(id);
  try {
    return await auth.getUserByEmail(email);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    return auth.createUser({ email, displayName: id });
  }
}

exports.loginAdmin = onCall(async (request) => {
  const id = String(request.data?.adminId || '').trim().toLowerCase();
  const pin = String(request.data?.pin || '').trim();
  if (!ADMINS[id] || ADMINS[id] !== pin) {
    throw new HttpsError('unauthenticated', 'Invalid Admin ID or PIN.');
  }
  const user = await ensureAdminUser(id);
  await auth.setCustomUserClaims(user.uid, { role: 'admin', adminId: id });
  await db.collection('userProfiles').doc(user.uid).set({
    role: 'admin',
    adminId: id,
    email: user.email || adminEmail(id),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  const token = await auth.createCustomToken(user.uid, { role: 'admin', adminId: id });
  return { token };
});

exports.loginCustomer = onCall(async (request) => {
  const id = String(request.data?.customerId || '').trim().toLowerCase();
  const pin = String(request.data?.pin || '').trim();
  if (!id || !/^\d{4,}$/.test(pin)) {
    throw new HttpsError('unauthenticated', 'Invalid Customer ID or PIN.');
  }
  const customerRef = db.collection('customers').doc(id);
  const customerSnap = await customerRef.get();
  if (!customerSnap.exists) {
    throw new HttpsError('unauthenticated', 'Invalid Customer ID or PIN.');
  }
  const customer = customerSnap.data() || {};
  if (String(customer.pin || '') !== pin) {
    throw new HttpsError('unauthenticated', 'Invalid Customer ID or PIN.');
  }
  let user;
  const uid = String(customer.authUid || '').trim();
  if (uid) {
    try { user = await auth.getUser(uid); } catch (_) { user = null; }
  }
  if (!user) {
    try { user = await auth.getUserByEmail(customerEmail(id)); }
    catch (_) { user = await auth.createUser({ email: customerEmail(id), displayName: customer.name || id }); }
  }
  await auth.setCustomUserClaims(user.uid, { role: 'customer', customerId: id });
  await customerRef.set({ authUid: user.uid }, { merge: true });
  await db.collection('userProfiles').doc(user.uid).set({
    role: 'customer',
    customerId: id,
    email: user.email || customerEmail(id),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  const token = await auth.createCustomToken(user.uid, { role: 'customer', customerId: id });
  return { token };
});

async function validateCustomer(data) {
  const id = String(data.customerId || '').trim().toLowerCase();
  const name = String(data.name || '').trim();
  const pin = String(data.pin || '').trim();
  const gstNumber = String(data.gstNumber || '').trim();
  if (!id || !name || !/^\d{4,}$/.test(pin)) {
    throw new HttpsError('invalid-argument', 'Customer ID, name and a 4+ digit PIN are required.');
  }
  return { id, name, pin, gstNumber };
}

async function getOrCreateCustomerUser(id, pin, name) {
  const email = customerEmail(id);
  let user;
  try {
    user = await auth.getUserByEmail(email);
    user = await auth.updateUser(user.uid, { displayName: name });
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await auth.createUser({ email, displayName: name });
  }
  await auth.setCustomUserClaims(user.uid, { role: 'customer', customerId: id });
  return user;
}

exports.createCustomerAccount = onCall(async (request) => {
  requireAdmin(request);
  const { id, name, pin, gstNumber } = await validateCustomer(request.data || {});
  const ref = db.collection('customers').doc(id);
  const existing = await ref.get();
  if (existing.exists) throw new HttpsError('already-exists', 'Customer ID already exists.');
  const user = await getOrCreateCustomerUser(id, pin, name);
  await db.runTransaction(async (tx) => {
    tx.set(ref, { id, name, pin, gstNumber, outstanding: 0, authUid: user.uid });
    tx.set(db.collection('userProfiles').doc(user.uid), {
      role: 'customer', customerId: id, email: user.email || customerEmail(id),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { uid: user.uid };
});

exports.ensureCustomerAccount = onCall(async (request) => {
  requireAdmin(request);
  const { id, name, pin, gstNumber } = await validateCustomer(request.data || {});
  const user = await getOrCreateCustomerUser(id, pin, name);
  await db.collection('customers').doc(id).set({ id, name, pin, gstNumber, authUid: user.uid }, { merge: true });
  await db.collection('userProfiles').doc(user.uid).set({
    role: 'customer', customerId: id, email: user.email || customerEmail(id),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { uid: user.uid };
});

exports.updateCustomerAccount = onCall(async (request) => {
  requireAdmin(request);
  const oldId = String(request.data?.oldCustomerId || '').trim().toLowerCase();
  const { id, name, pin, gstNumber } = await validateCustomer(request.data || {});
  if (!oldId) throw new HttpsError('invalid-argument', 'Old Customer ID is required.');
  const oldRef = db.collection('customers').doc(oldId);
  const oldDoc = await oldRef.get();
  if (!oldDoc.exists) throw new HttpsError('not-found', 'Customer not found.');
  const oldData = oldDoc.data() || {};
  const existingNew = id === oldId ? null : await db.collection('customers').doc(id).get();
  if (existingNew?.exists) throw new HttpsError('already-exists', 'New Customer ID already exists.');

  let user;
  const uid = String(oldData.authUid || '').trim();
  if (uid) {
    user = await auth.getUser(uid);
    user = await auth.updateUser(uid, { email: customerEmail(id), displayName: name });
  } else {
    user = await getOrCreateCustomerUser(id, pin, name);
  }
  await auth.setCustomUserClaims(user.uid, { role: 'customer', customerId: id });
  await db.runTransaction(async (tx) => {
    tx.set(db.collection('customers').doc(id), {
      id, name, pin, gstNumber,
      outstanding: Number(oldData.outstanding || 0), authUid: user.uid,
    }, { merge: true });
    if (oldId !== id) tx.delete(oldRef);
    tx.set(db.collection('userProfiles').doc(user.uid), {
      role: 'customer', customerId: id, email: user.email || customerEmail(id),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  return { uid: user.uid };
});

exports.deleteCustomerAccount = onCall(async (request) => {
  requireAdmin(request);
  const id = String(request.data?.customerId || '').trim().toLowerCase();
  const ref = db.collection('customers').doc(id);
  const snap = await ref.get();
  if (!snap.exists) return { deleted: false };
  const uid = String(snap.data()?.authUid || '').trim();
  if (uid) {
    try { await auth.deleteUser(uid); } catch (e) { if (e.code !== 'auth/user-not-found') throw e; }
    await db.collection('userProfiles').doc(uid).delete().catch(() => {});
  }
  await ref.delete();
  return { deleted: true };
});
