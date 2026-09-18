/**
 * Boot-time reachability check for the Python CV grid service.
 *
 * The OCR routes are CV-first and fall back to word-clustering when the grid
 * service is unreachable -- a fallback that can misplace columns and swap
 * groom/bride. That fallback is per-request and easy to miss in the logs, so an
 * operator can run the whole backend without noticing every marriage scan is
 * silently degraded. This reports the service's status once at startup so a
 * misconfiguration (URL unset, service down) is loud where it's set up.
 *
 * Never throws: a health probe must not stop the API from booting.
 */
async function cvGridStatus({ env = process.env, fetchImpl = fetch, timeoutMs = 4000 } = {}) {
  const baseUrl = env.OCR_SERVICE_URL;
  if (!baseUrl) {
    return {
      configured: false,
      reachable: false,
      message:
        'OCR_SERVICE_URL is not set — register scans will use the low-accuracy '
        + 'word-clustering fallback. Set OCR_SERVICE_URL to the CV grid service.',
    };
  }

  const healthUrl = `${baseUrl.replace(/\/$/, '')}/health`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(healthUrl, { signal: controller.signal });
    if (res && res.ok) {
      return { configured: true, reachable: true, message: `CV grid service reachable at ${baseUrl}.` };
    }
    return {
      configured: true,
      reachable: false,
      message:
        `CV grid service at ${baseUrl} returned an unhealthy status`
        + `${res && res.status ? ` (${res.status})` : ''} — scans will use the low-accuracy fallback.`,
    };
  } catch (e) {
    return {
      configured: true,
      reachable: false,
      message:
        `CV grid service at ${baseUrl} is unreachable — scans will use the `
        + 'low-accuracy fallback. Start it (see ocr_service/README.md).',
    };
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { cvGridStatus };
