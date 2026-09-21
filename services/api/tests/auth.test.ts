import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, createLocalJWKSet, SignJWT } from 'jose';
import { digest, verifyIdentity } from '../src/auth.js';

const { privateKey, publicKey } = await generateKeyPair('RS256');
const jwk = await exportJWK(publicKey); jwk.kid = 'test-key';
const keys = createLocalJWKSet({ keys: [jwk] });
const nonce = 'server-bound-test-nonce';
async function token(overrides: Record<string, unknown> = {}) {
  return new SignJWT({ nonce, email: 'learner@example.test', email_verified: true, ...overrides })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setSubject('subject-123')
    .setAudience('fleunce-test-client').setIssuer('https://accounts.google.com')
    .setIssuedAt().setExpirationTime('5m').sign(privateKey);
}
test('Google ID token signature, audience, issuer and nonce are verified', async () => {
  const identity = await verifyIdentity('google', await token(), digest(nonce), { googleClientID: 'fleunce-test-client' }, keys);
  assert.deepEqual(identity, { provider: 'google', subject: 'subject-123', email: 'learner@example.test' });
});
test('signed tokens for another client or nonce are rejected', async () => {
  const value = await token();
  await assert.rejects(verifyIdentity('google', value, digest('other-nonce'), { googleClientID: 'fleunce-test-client' }, keys));
  await assert.rejects(verifyIdentity('google', value, digest(nonce), { googleClientID: 'another-client' }, keys));
});
test('missing nonce and untrusted signatures are rejected', async () => {
  await assert.rejects(verifyIdentity('google', await token({ nonce: null }), digest(nonce), { googleClientID: 'fleunce-test-client' }, keys));
  const value = await token();
  const other = await generateKeyPair('RS256');
  const otherJWK = await exportJWK(other.publicKey); otherJWK.kid = 'test-key';
  await assert.rejects(verifyIdentity('google', value, digest(nonce), { googleClientID: 'fleunce-test-client' }, createLocalJWKSet({ keys: [otherJWK] })));
});
test('Apple issuer is separate and email can use a private relay address', async () => {
  const value = await new SignJWT({ nonce, email: 'private@privaterelay.appleid.com', email_verified: 'true' })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setSubject('apple-subject')
    .setAudience('fleunce-test-client').setIssuer('https://appleid.apple.com').setIssuedAt().setExpirationTime('5m').sign(privateKey);
  const identity = await verifyIdentity('apple', value, digest(nonce), { appleClientID: 'fleunce-test-client' }, keys);
  assert.equal(identity.email, 'private@privaterelay.appleid.com');
  await assert.rejects(verifyIdentity('google', value, digest(nonce), { googleClientID: 'fleunce-test-client' }, keys));
});
test('unverified email is not persisted as verified identity data', async () => {
  const identity = await verifyIdentity('google', await token({ email_verified: false }), digest(nonce), { googleClientID: 'fleunce-test-client' }, keys);
  assert.equal(identity.email, null);
});
test('expired and stale identity tokens are rejected', async () => {
  const value = await new SignJWT({ nonce }).setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
    .setSubject('expired').setAudience('fleunce-test-client').setIssuer('https://accounts.google.com')
    .setIssuedAt(1).setExpirationTime(2).sign(privateKey);
  await assert.rejects(verifyIdentity('google', value, digest(nonce), { googleClientID: 'fleunce-test-client' }, keys));
});
test('Google authorized party and multiple audiences cannot authorize another client', async () => {
  await assert.rejects(verifyIdentity('google', await token({ azp: 'another-client' }), digest(nonce), { googleClientID: 'fleunce-test-client' }, keys));
  const claims = { nonce, sub: 'subject', iss: 'https://accounts.google.com', aud: ['fleunce-test-client', 'another-client'], iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 300 };
  const multi = await new SignJWT(claims).setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).sign(privateKey);
  await assert.rejects(verifyIdentity('google', multi, digest(nonce), { googleClientID: 'fleunce-test-client' }, keys));
  const authorized = await new SignJWT({ ...claims, azp: 'fleunce-test-client' }).setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).sign(privateKey);
  assert.equal((await verifyIdentity('google', authorized, digest(nonce), { googleClientID: 'fleunce-test-client' }, keys)).subject, 'subject');
});
test('Android Google tokens require their server audience and an allowlisted Android party', async () => {
  const config = { googleClientID: 'fleunce-test-client', googleAndroidServerClientID: 'fleunce-android-server',
    googleAndroidClientIDs: ['fleunce-android-debug', 'fleunce-android-play'] };
  const androidToken = (aud: string, azp?: string) => new SignJWT({ nonce, azp }).setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
    .setSubject('same-google-user').setAudience(aud).setIssuer('https://accounts.google.com').setIssuedAt().setExpirationTime('5m').sign(privateKey);
  for (const party of config.googleAndroidClientIDs) {
    const value = await androidToken(config.googleAndroidServerClientID, party);
    assert.equal((await verifyIdentity('google', value, digest(nonce), config, keys)).subject, 'same-google-user');
  }
  for (const [aud, party] of [['fleunce-android-server', undefined], ['fleunce-android-server', 'other-android-app'],
    ['other-server', 'fleunce-android-debug'], ['fleunce-test-client', 'fleunce-android-debug'], ['fleunce-android-server', 'fleunce-android-server']]) {
    await assert.rejects(verifyIdentity('google', await androidToken(aud!, party), digest(nonce), config, keys));
  }
  assert.equal((await verifyIdentity('google', await token(), digest(nonce), config, keys)).provider, 'google');
  await assert.rejects(verifyIdentity('google', await androidToken('fleunce-android-server', 'fleunce-android-debug'), digest(nonce),
    { ...config, googleAndroidClientIDs: [] }, keys));
});
test('unexpected provider email content is never retained', async () => {
  for (const email of ['not-an-email', 'x\ny@example.test', 'x'.repeat(300) + '@example.test']) {
    const identity = await verifyIdentity('google', await token({ email }), digest(nonce), { googleClientID: 'fleunce-test-client' }, keys);
    assert.equal(identity.email, null);
  }
});
