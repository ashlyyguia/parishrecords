const https = require('https');

const {
  EMAILJS_SERVICE_ID,
  EMAILJS_TEMPLATE_ID,
  EMAILJS_PUBLIC_KEY,
  EMAILJS_PRIVATE_KEY,
  EMAILJS_FROM_NAME,
  EMAILJS_REPLY_TO,
} = process.env;

function postJson(url, payload) {
  return new Promise((resolve, reject) => {
    const data = Buffer.from(JSON.stringify(payload));
    const u = new URL(url);

    const req = https.request(
      {
        method: 'POST',
        protocol: u.protocol,
        hostname: u.hostname,
        port: u.port || 443,
        path: u.pathname + u.search,
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': data.length,
        },
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => {
          body += chunk;
        });
        res.on('end', () => {
          resolve({ statusCode: res.statusCode || 0, body });
        });
      }
    );

    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function sendVerificationCodeEmail(to, code) {
  if (!EMAILJS_SERVICE_ID || !EMAILJS_TEMPLATE_ID || !EMAILJS_PUBLIC_KEY) {
    throw new Error(
      'EmailJS is not configured. Set EMAILJS_SERVICE_ID, EMAILJS_TEMPLATE_ID, and EMAILJS_PUBLIC_KEY.'
    );
  }

  const expiresAt = new Date(Date.now() + 15 * 60 * 1000);
  const expiresAtLabel = expiresAt
    .toISOString()
    .replace('T', ' ')
    .replace(/\.\d{3}Z$/, ' UTC');

  const payload = {
    service_id: EMAILJS_SERVICE_ID,
    template_id: EMAILJS_TEMPLATE_ID,
    user_id: EMAILJS_PUBLIC_KEY,
    // EmailJS requires a private key for server-side usage.
    // If you created a private key in EmailJS, set EMAILJS_PRIVATE_KEY.
    ...(EMAILJS_PRIVATE_KEY ? { accessToken: EMAILJS_PRIVATE_KEY } : {}),
    template_params: {
      email: to,
      to_email: to,
      code: code,
      passcode: code,
      time: expiresAtLabel,
      minutes_valid: 15,
      app_name: 'ParishRecord',
      from_name: EMAILJS_FROM_NAME || 'ParishRecord',
      reply_to: EMAILJS_REPLY_TO || undefined,
    },
  };

  const resp = await postJson(
    'https://api.emailjs.com/api/v1.0/email/send',
    payload
  );

  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw new Error(
      `EmailJS send failed: ${resp.statusCode} ${resp.body || ''}`
    );
  }
}

module.exports = {
  sendVerificationCodeEmail,
};
