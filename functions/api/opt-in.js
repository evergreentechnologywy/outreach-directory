const CITY_TAGS = {
  las_vegas: 'Las Vegas',
  miami: 'Miami',
  new_york: 'New York',
  los_angeles: 'Los Angeles',
  other: 'Nationwide',
};

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      ...CORS_HEADERS,
    },
  });
}

function normalizePhone(phone) {
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `+${digits}`;
  if (phone.startsWith('+')) return phone;
  return `+${digits}`;
}

function subtextAuthHeader(secretKey) {
  const encoded = btoa(`${secretKey}:`);
  return { Authorization: `Basic ${encoded}` };
}

function buildSubtextBody(data) {
  const body = new URLSearchParams();
  body.set('phone_number', data.phone);
  body.set('first_name', data.name);
  body.set('email', data.email);
  body.append('tags[]', data.cityTag);
  body.append('tags[]', 'VIP Opt-In');
  body.set('metadata[source]', 'vip-weekly-opt-in');
  body.set('metadata[city]', data.city);
  return body;
}

async function syncToSubtext(env, data) {
  const secretKey = env.SUBTEXT_SECRET_KEY;
  if (!secretKey) {
    throw new Error('SUBTEXT_SECRET_KEY is not configured');
  }

  const headers = {
    ...subtextAuthHeader(secretKey),
    'Content-Type': 'application/x-www-form-urlencoded',
  };

  const createRes = await fetch('https://joinsubtext.com/v3/subscribers', {
    method: 'POST',
    headers,
    body: buildSubtextBody(data),
  });

  if (createRes.ok) {
    return createRes.json();
  }

  if (createRes.status === 422) {
    const updateRes = await fetch(
      `https://joinsubtext.com/v3/subscribers/${encodeURIComponent(data.phone)}`,
      {
        method: 'PUT',
        headers,
        body: buildSubtextBody(data),
      },
    );

    if (updateRes.ok) {
      return updateRes.json();
    }

    const resubscribeRes = await fetch(
      `https://joinsubtext.com/v3/subscribers/${encodeURIComponent(data.phone)}/resubscribe`,
      {
        method: 'POST',
        headers: subtextAuthHeader(secretKey),
      },
    );

    if (resubscribeRes.ok) {
      const updateAfterResub = await fetch(
        `https://joinsubtext.com/v3/subscribers/${encodeURIComponent(data.phone)}`,
        {
          method: 'PUT',
          headers,
          body: buildSubtextBody(data),
        },
      );
      if (updateAfterResub.ok) {
        return updateAfterResub.json();
      }
    }
  }

  const errorText = await createRes.text();
  throw new Error(`Subtext sync failed (${createRes.status}): ${errorText}`);
}

async function syncToResend(env, data) {
  const apiKey = env.RESEND_API_KEY;
  if (!apiKey) return null;

  const res = await fetch('https://api.resend.com/contacts', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email: data.email,
      firstName: data.name,
      unsubscribed: false,
      properties: {
        phone: data.phone,
        city: data.city,
        source: 'vip-weekly-opt-in',
      },
    }),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Resend sync failed (${res.status}): ${errorText}`);
  }

  return res.json();
}

export async function onRequestOptions() {
  return jsonResponse({ ok: true });
}

export async function onRequestPost(context) {
  const { request, env } = context;

  try {
    const payload = await request.json();
    const { name, phone, email, city, consent } = payload;

    if (!name?.trim() || !phone?.trim() || !email?.trim() || !city?.trim()) {
      return jsonResponse({ error: 'Missing required fields' }, 400);
    }

    if (!consent) {
      return jsonResponse({ error: 'Consent is required' }, 400);
    }

    const data = {
      name: name.trim(),
      phone: normalizePhone(phone.trim()),
      email: email.trim().toLowerCase(),
      city,
      cityTag: CITY_TAGS[city] || city,
    };

    await syncToSubtext(env, data);

    try {
      await syncToResend(env, data);
    } catch (err) {
      console.error('Resend sync error (non-fatal):', err.message);
    }

    return jsonResponse({ success: true, synced: true });
  } catch (err) {
    console.error('Opt-in handler error:', err.message);
    if (err.message.includes('SUBTEXT_SECRET_KEY')) {
      return jsonResponse({ error: 'Service configuration error' }, 503);
    }
    return jsonResponse({ error: 'Failed to sync subscriber. Please try again.' }, 502);
  }
}
