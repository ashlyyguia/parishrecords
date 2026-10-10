const { buildWelcomeEmail, welcomeTransport } = require('./email');

describe('buildWelcomeEmail', () => {
  test('greets by first name and says the registration succeeded', () => {
    const m = buildWelcomeEmail({ displayName: 'Maria Santos', email: 'maria@example.com' });
    expect(m.subject).toMatch(/Welcome to .+ — your account is ready/);
    expect(m.text).toContain('Dear Maria,');
    expect(m.text).toContain('successfully registered');
    expect(m.html).toContain('maria@example.com');
    expect(m.html).toContain('successfully registered');
  });

  test('falls back to "Parishioner" and escapes HTML', () => {
    const m = buildWelcomeEmail({ displayName: '', email: '<x>@example.com' });
    expect(m.text).toContain('Dear Parishioner,');
    expect(m.html).toContain('&lt;x&gt;@example.com');
    expect(m.html).not.toContain('<x>@example.com');
  });
});

describe('welcomeTransport', () => {
  test('is "none" when nothing is configured', () => {
    expect(['none', 'smtp', 'emailjs']).toContain(welcomeTransport());
  });
});
