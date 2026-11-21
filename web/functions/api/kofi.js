// POST /api/kofi — Ko-fi purchase of the EOS Webcam item → signed licence key, emailed to the buyer.
// Cloudflare Pages Function (eos.4xs.dev). Same scheme as preflight.4xs.dev: Ed25519 key, verified
// offline by src/eos-webcam.js. Ko-fi's account webhook points at PTZ Vote, which hands this item's
// orders here by item code (KOFI_PRODUCTS in its wrangler.toml).
// Author: Pavel Kotyza <kotyza@gmail.com> - 4xs.dev
//
// Env (Pages → Settings → Variables and secrets):
//   KOFI_VERIFICATION_TOKEN  secret — Ko-fi → Settings → API → Webhooks → Verification token
//   EOS_SIGNING_KEY          secret — Ed25519 private key PEM (Projects/.eos-webcam-signing/signing.pem)
//   KOFI_SHOP_CODE           the shop item's direct_link_code; only that item issues a key
//   CF_ACCOUNT_ID, CF_EMAIL_TOKEN  Cloudflare Email Sending (same as Preflight)
//   MAIL_FROM, MAIL_REPLY_TO sender and reply-to addresses
//   EOS_KEYS                 optional KV binding: key kept 1 hour under the buyer email for /thanks
//
// Keys are deterministic (same payment → same key), so Ko-fi retries re-send the same key.

const NEEDED = ['KOFI_VERIFICATION_TOKEN', 'EOS_SIGNING_KEY', 'KOFI_SHOP_CODE', 'CF_ACCOUNT_ID', 'CF_EMAIL_TOKEN', 'MAIL_FROM', 'MAIL_REPLY_TO'];
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// GET — setup check: which variables are present, never their values.
export function onRequestGet({ env }) {
  const set = Object.fromEntries([...NEEDED, 'EOS_KEYS'].map((k) => [k, Boolean(env[k])]));
  return Response.json({ function: 'ok', variables: set }, { headers: { 'cache-control': 'no-store' } });
}

export async function onRequestPost({ request, env }) {
  const text = (status, body) => new Response(body, { status, headers: { 'content-type': 'text/plain' } });
  let data;
  try {
    data = JSON.parse((await request.formData()).get('data'));
  } catch {
    return text(400, 'bad request');
  }
  if (!env.KOFI_VERIFICATION_TOKEN || data.verification_token !== env.KOFI_VERIFICATION_TOKEN) return text(401, 'bad token');

  const ours = data.type === 'Shop Order' && Array.isArray(data.shop_items) &&
    data.shop_items.some((i) => i && i.direct_link_code === env.KOFI_SHOP_CODE);
  if (!env.KOFI_SHOP_CODE || !ours) return text(200, 'ignored');

  const email = String(data.email ?? '').trim();
  if (!EMAIL_RE.test(email)) {
    console.error('kofi: purchase without a usable email', data.kofi_transaction_id);
    return text(200, 'no email');
  }
  const missing = NEEDED.filter((k) => !env[k]);
  if (missing.length) {
    console.error('kofi: missing variables', missing.join(', '));
    return text(500, 'not configured'); // Ko-fi retries once they are set
  }

  const key = await issueKey(env.EOS_SIGNING_KEY, {
    subject: email,
    issued: String(data.timestamp ?? '').slice(0, 10) || new Date().toISOString().slice(0, 10),
    txn: String(data.kofi_transaction_id ?? ''),
  });
  if (env.EOS_KEYS) await env.EOS_KEYS.put('email:' + email.toLowerCase(), key, { expirationTtl: 3600 });

  const r = await fetch(`https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/email/sending/send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.CF_EMAIL_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      to: [email],
      from: env.MAIL_FROM,
      reply_to: env.MAIL_REPLY_TO,
      subject: 'Your EOS Webcam licence key',
      text: [
        `Thank you for supporting EOS Webcam${data.from_name ? ', ' + data.from_name : ''}.`,
        '',
        'Your licence key:',
        '',
        key,
        '',
        'Menu bar camera icon → Unlock picture controls → paste the key → Save key.',
        '(Or paste it on the preview page, http://127.0.0.1:8809.)',
        'It unlocks brightness, contrast, saturation and mirror, checked on your Mac, no internet needed.',
        '',
        'Questions: reply to this email.',
        '— Pavel Kotyza, https://eos.4xs.dev',
      ].join('\n'),
    }),
  }).catch((e) => ({ ok: false, status: 0, text: async () => String(e) }));
  if (!r.ok) {
    console.error('kofi: send failed', r.status, await r.text(), data.kofi_transaction_id);
    return text(500, 'send failed');
  }
  console.log('kofi: key sent', data.kofi_transaction_id);
  return text(200, 'ok');
}

// EW1.<base64url payload>.<base64url Ed25519 signature over the encoded payload>
export async function issueKey(pem, payload) {
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----|\s/g, '')), (c) => c.charCodeAt(0));
  const priv = await crypto.subtle.importKey('pkcs8', der, { name: 'Ed25519' }, false, ['sign']);
  const encoded = b64url(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, priv, new TextEncoder().encode(encoded));
  return `EW1.${encoded}.${b64url(new Uint8Array(sig))}`;
}

function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
