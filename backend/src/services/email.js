const https = require('https');

let emailjs;
try {
  // Optional dependency (works if installed). Allows EmailJS SDK send which can behave differently vs raw API.
  // If not present, we keep using the raw HTTPS call.
  emailjs = require('@emailjs/nodejs');
} catch (_e) {
  emailjs = null;
}

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
    console.warn('\n======================================================');
    console.warn('⚠️ EMAILJS IS NOT CONFIGURED IN .env FILE');
    console.warn(`📩 MOCK EMAIL SENT TO: ${to}`);
    console.warn(`🔑 VERIFICATION CODE:  ${code}`);
    console.warn('======================================================\n');
    // We return successfully so development and testing can continue
    return;
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

  const resp = await postJson('https://api.emailjs.com/api/v1.0/email/send', payload);

  if (resp.statusCode >= 200 && resp.statusCode < 300) {
    return;
  }

  // Fallback: try the official EmailJS Node SDK if available.
  // Some accounts/configurations behave differently with the SDK vs raw REST call.
  if (emailjs) {
    try {
      const options = EMAILJS_PRIVATE_KEY ? { privateKey: EMAILJS_PRIVATE_KEY } : undefined;
      await emailjs.send(
        EMAILJS_SERVICE_ID,
        EMAILJS_TEMPLATE_ID,
        payload.template_params,
        {
          publicKey: EMAILJS_PUBLIC_KEY,
          ...(options || {}),
        }
      );
      return;
    } catch (e) {
      throw new Error(
        `EmailJS send failed: ${resp.statusCode} ${resp.body || ''} | SDK fallback failed: ${e && e.message ? e.message : String(e)}`
      );
    }
  }

  throw new Error(`EmailJS send failed: ${resp.statusCode} ${resp.body || ''}`);
}

// ---------------------------------------------------------------------------
// Welcome email for newly registered parishioners.
//
// The subject and body are written here, so the wording can be changed in
// code. Sent through SMTP when SMTP_HOST is set (e.g. Gmail with an app
// password), otherwise through EmailJS with EMAILJS_WELCOME_TEMPLATE_ID — that
// template only needs {{subject}} as its subject and {{{message_html}}} as its
// body. With neither configured, the email is only logged.
// ---------------------------------------------------------------------------

const PARISH_NAME = process.env.PARISH_NAME || 'Holy Parish';
const APP_URL = process.env.APP_URL || 'https://holyparish.web.app';

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** Builds the welcome email. Pure: no I/O, so it can be unit-tested. */
function buildWelcomeEmail({ displayName, email }) {
  const name = (displayName || '').toString().trim() || 'Parishioner';
  const firstName = name.split(/\s+/)[0];
  const subject = `Welcome to ${PARISH_NAME} — your account is ready`;

  const text = [
    `Dear ${firstName},`,
    '',
    `Peace be with you! You have successfully registered to ${PARISH_NAME}'s online parish records system.`,
    '',
    'With your account you can:',
    '  • Request baptismal, confirmation, marriage and funeral certificates',
    '  • Add your household members and link their parish records',
    '  • Track the status of your requests and receive updates',
    '  • Stay informed with parish announcements and Mass schedules',
    '',
    `Sign in anytime at ${APP_URL} using ${email}.`,
    '',
    'If you did not create this account, please contact the parish office.',
    '',
    'God bless,',
    `The ${PARISH_NAME} Parish Office`,
  ].join('\n');

  const li = (t) => `<li style="margin:4px 0">${t}</li>`;
  const html = `<!doctype html>
<html><body style="margin:0;padding:0;background:#f4f1ea;font-family:Georgia,'Times New Roman',serif;color:#2b2b2b">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f1ea;padding:24px 0">
<tr><td align="center">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:#ffffff;border-radius:12px;overflow:hidden;border:1px solid #e6dfd0">
<tr><td style="background:#5b2c83;padding:24px 28px;color:#ffffff">
<div style="font-size:13px;letter-spacing:2px;text-transform:uppercase;opacity:.85">${escapeHtml(PARISH_NAME)}</div>
<div style="font-size:24px;margin-top:6px">Welcome to our parish family</div>
</td></tr>
<tr><td style="padding:28px;font-size:16px;line-height:1.6">
<p style="margin:0 0 14px">Dear ${escapeHtml(firstName)},</p>
<p style="margin:0 0 14px">Peace be with you! You have <strong>successfully registered</strong> to ${escapeHtml(PARISH_NAME)}'s online parish records system.</p>
<p style="margin:0 0 6px">With your account you can:</p>
<ul style="margin:0 0 16px;padding-left:20px">
${li('Request baptismal, confirmation, marriage and funeral certificates')}
${li('Add your household members and link their parish records')}
${li('Track the status of your requests and receive updates')}
${li('Stay informed with parish announcements and Mass schedules')}
</ul>
<p style="margin:0 0 22px">Sign in anytime using <strong>${escapeHtml(email)}</strong>.</p>
<p style="margin:0 0 22px"><a href="${escapeHtml(APP_URL)}" style="display:inline-block;background:#5b2c83;color:#ffffff;text-decoration:none;padding:12px 22px;border-radius:8px;font-family:Arial,sans-serif;font-size:15px">Open ${escapeHtml(PARISH_NAME)}</a></p>
<p style="margin:0 0 4px;font-size:13px;color:#6b6b6b">If you did not create this account, please contact the parish office.</p>
</td></tr>
<tr><td style="padding:18px 28px;background:#faf7f0;font-size:14px;color:#555">God bless,<br>The ${escapeHtml(PARISH_NAME)} Parish Office</td></tr>
</table>
</td></tr></table>
</body></html>`;

  // Same content without the <!doctype>/<html>/<body> wrapper, for services
  // (EmailJS) that put the message inside their own HTML document.
  const htmlBody = html
    .replace(/^[\s\S]*?<body[^>]*>/i, '')
    .replace(/<\/body>[\s\S]*$/i, '')
    .trim();

  return { subject, text, html, htmlBody };
}

function emailjsWelcomeConfigured() {
  return !!(EMAILJS_SERVICE_ID && EMAILJS_PUBLIC_KEY && process.env.EMAILJS_WELCOME_TEMPLATE_ID);
}

function welcomeTransport() {
  if (process.env.SMTP_HOST) return 'smtp';
  if (emailjsWelcomeConfigured()) return 'emailjs';
  return 'none';
}

async function sendWelcomeViaSmtp(to, message) {
  const nodemailer = require('nodemailer');
  const port = Number(process.env.SMTP_PORT || 587);
  const mailer = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port,
    secure: process.env.SMTP_SECURE ? process.env.SMTP_SECURE === 'true' : port === 465,
    auth: process.env.SMTP_USER
      ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
      : undefined,
    // Fail fast: some hosts (e.g. Railway) block outgoing SMTP, and the
    // default 2-minute timeout would hold the request open.
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 20000,
  });
  const fromAddress = process.env.SMTP_FROM || process.env.SMTP_USER;
  await mailer.sendMail({
    from: `"${EMAILJS_FROM_NAME || PARISH_NAME}" <${fromAddress}>`,
    to,
    replyTo: EMAILJS_REPLY_TO || undefined,
    subject: message.subject,
    text: message.text,
    html: message.html,
  });
}

async function sendWelcomeViaEmailjs(to, displayName, message) {
  const resp = await postJson('https://api.emailjs.com/api/v1.0/email/send', {
    service_id: EMAILJS_SERVICE_ID,
    template_id: process.env.EMAILJS_WELCOME_TEMPLATE_ID,
    user_id: EMAILJS_PUBLIC_KEY,
    ...(EMAILJS_PRIVATE_KEY ? { accessToken: EMAILJS_PRIVATE_KEY } : {}),
    template_params: {
      email: to,
      to_email: to,
      to_name: displayName || 'Parishioner',
      subject: message.subject,
      message_html: message.htmlBody,
      message_text: message.text,
      from_name: EMAILJS_FROM_NAME || PARISH_NAME,
      reply_to: EMAILJS_REPLY_TO || undefined,
    },
  });
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw new Error(`EmailJS send failed: ${resp.statusCode} ${resp.body || ''}`);
  }
}

/**
 * Sends the welcome email. Returns { sent: boolean, transport }.
 * SMTP is tried first when configured; if it fails (e.g. the host blocks
 * SMTP ports) and EmailJS is configured, EmailJS (HTTPS) is used instead.
 * Throws only when every configured transport fails.
 */
async function sendWelcomeEmail(to, displayName) {
  const message = buildWelcomeEmail({ displayName, email: to });
  const transport = welcomeTransport();

  if (transport === 'smtp') {
    try {
      await sendWelcomeViaSmtp(to, message);
      return { sent: true, transport: 'smtp' };
    } catch (e) {
      if (!emailjsWelcomeConfigured()) throw e;
      console.warn(`[welcome-email] SMTP failed (${e.message}); trying EmailJS.`);
      await sendWelcomeViaEmailjs(to, displayName, message);
      return { sent: true, transport: 'emailjs' };
    }
  }

  if (transport === 'emailjs') {
    await sendWelcomeViaEmailjs(to, displayName, message);
    return { sent: true, transport };
  }

  console.warn(`[welcome-email] No email transport configured; not sent to ${to}.`);
  return { sent: false, transport };
}

module.exports = {
  sendVerificationCodeEmail,
  buildWelcomeEmail,
  sendWelcomeEmail,
  welcomeTransport,
};
