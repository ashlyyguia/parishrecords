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
      // A reachable but out-of-date service is the worst case: it refuses most
      // real spreads (the pre-2.1 pipeline read 7/59 sample baptismal photos
      // and 0/8 marriage photos), and every refusal looks like a bad photo.
      // /health reports `version` + `registers` from 2.1.0 on.
      let body = null;
      try { body = await res.json(); } catch (_) { body = null; }
      const registers = body && Array.isArray(body.registers) ? body.registers : [];
      const version = body && typeof body.version === 'string' ? body.version : null;
      if (!version || !registers.includes('marriage')) {
        return {
          configured: true,
          reachable: false,
          stale: true,
          message:
            `CV grid service at ${baseUrl} is reachable but OUT OF DATE`
            + `${version ? ` (version ${version})` : ' (no version reported)'} — it will refuse most `
            + 'register photos. Redeploy ocr_service/ to the VPS (see ocr_service/DEPLOY_VPS.md).',
        };
      }
      return {
        configured: true,
        reachable: true,
        version,
        message: `CV grid service reachable at ${baseUrl} (version ${version}).`,
      };
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
