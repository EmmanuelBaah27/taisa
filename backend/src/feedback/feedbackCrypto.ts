import { createCipheriv, randomBytes } from 'crypto';

export interface EncryptedFeedbackEnvelope {
  readonly nonce: string;
  readonly authenticationTag: string;
  readonly ciphertext: string;
}

export function parseFeedbackEncryptionKey(encoded: string): Buffer {
  const key = Buffer.from(encoded, 'base64');
  if (key.length !== 32 || key.toString('base64') !== encoded) {
    throw new Error('Feedback encryption key must be exactly 32 base64-encoded bytes');
  }
  return key;
}

export function encryptFeedback(
  plaintext: string,
  key: Buffer,
): EncryptedFeedbackEnvelope {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  return {
    nonce: nonce.toString('base64'),
    authenticationTag: cipher.getAuthTag().toString('base64'),
    ciphertext: ciphertext.toString('base64'),
  };
}
