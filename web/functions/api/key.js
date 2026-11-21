// POST /api/key { email } — the thanks page asks for the key of a purchase that just happened.
// Answers { key } once /api/kofi stored it (1 hour, KV binding EOS_KEYS), else { pending: true }.
// Anyone who knows a buyer's email within that hour can read the key — accepted at 5 EUR; it is emailed anyway.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const reply = (body, status = 200) => Response.json(body, { status, headers: { 'cache-control': 'no-store' } });

export async function onRequestPost({ request, env }) {
  if (!env.EOS_KEYS) return reply({ error: 'not configured' }, 503);
  let email = '';
  try { email = String((await request.json()).email ?? '').trim().toLowerCase(); } catch { return reply({ error: 'bad request' }, 400); }
  if (!EMAIL_RE.test(email) || email.length > 200) return reply({ error: 'Please enter the email you paid with.' }, 400);
  const key = await env.EOS_KEYS.get('email:' + email);
  return reply(key ? { key } : { pending: true });
}
