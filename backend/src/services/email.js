const nodemailer = require('nodemailer');

const {
  SMTP_HOST,
  SMTP_PORT,
  SMTP_USER,
  SMTP_PASS,
  SMTP_FROM,
} = process.env;

let transporter;

function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: SMTP_HOST,
      port: Number(SMTP_PORT) || 587,
      secure: false,
      auth:
        SMTP_USER && SMTP_PASS
          ? {
              user: SMTP_USER,
              pass: SMTP_PASS,
            }
          : undefined,
    });
  }
  return transporter;
}

async function sendVerificationCodeEmail(to, code) {
  const from = SMTP_FROM || SMTP_USER;
  if (!from) {
    throw new Error('SMTP_FROM or SMTP_USER must be configured');
  }

  const transport = getTransporter();
  const mailOptions = {
    from,
    to,
    subject: 'Your ParishRecord verification code',
    text: `Your verification code is: ${code}\n\nEnter this 6-digit code in the app to complete your registration.`,
    html: `<p>Your verification code is:</p>
<p style="font-size:24px;font-weight:bold;letter-spacing:4px;">${code}</p>
<p>Enter this 6-digit code in the app to complete your registration.</p>`,
  };

  await transport.sendMail(mailOptions);
}

module.exports = {
  sendVerificationCodeEmail,
};
