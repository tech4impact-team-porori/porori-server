import { createClient } from 'npm:@supabase/supabase-js@2';

type VWorldAddressType = 'road' | 'parcel';

type VWorldPoint = {
  x?: string;
  y?: string;
};

type VWorldResult = {
  point?: VWorldPoint;
  text?: string;
  refined?: {
    text?: string;
    structure?: {
      level0?: string;
      level1?: string;
      level2?: string;
      level3?: string;
      level4L?: string;
      level4LC?: string;
      level4A?: string;
      level4AC?: string;
    };
  };
};

type VWorldResponse = {
  response?: {
    status?: string;
    result?: VWorldResult;
    error?: {
      code?: string;
      text?: string;
    };
  };
};

type GeocodeMatch = {
  provider: 'vworld';
  sourceType: VWorldAddressType;
  matchedAddress: string;
  latitude: number;
  longitude: number;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'POST requests only' }, 405);
  }

  const apiKey = Deno.env.get('VWORLD_API_KEY');
  if (!apiKey) {
    return jsonResponse({ error: 'VWORLD_API_KEY is not configured' }, 500);
  }

  const authResult = await authorizeOperator(request);
  if (!authResult.ok) {
    return jsonResponse({ error: authResult.error }, authResult.status);
  }

  let body: { address?: unknown };
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const address = typeof body.address === 'string' ? body.address.trim() : '';
  if (!address) {
    return jsonResponse({ error: 'Address is required' }, 400);
  }

  try {
    const match =
      (await fetchVWorldCoordinate(address, 'road', apiKey)) ??
      (await fetchVWorldCoordinate(address, 'parcel', apiKey));

    if (!match) {
      return jsonResponse(
        {
          error: 'No coordinate match found',
          query: address,
          match: null,
        },
        404,
      );
    }

    return jsonResponse({ query: address, match });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'VWorld geocoding failed';
    return jsonResponse({ error: message }, 502);
  }
});

async function authorizeOperator(request: Request): Promise<
  | {
      ok: true;
    }
  | {
      ok: false;
      status: number;
      error: string;
    }
> {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return { ok: false, status: 401, error: 'Authentication required' };
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !supabaseAnonKey) {
    return { ok: false, status: 500, error: 'Supabase env is not configured' };
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: {
        Authorization: authHeader,
      },
    },
  });

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();
  if (userError || !user) {
    return { ok: false, status: 401, error: 'Invalid session' };
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('role')
    .eq('auth_user_id', user.id)
    .maybeSingle();

  if (profileError) {
    return { ok: false, status: 500, error: 'Could not verify operator role' };
  }

  if (profile?.role !== 'admin' && profile?.role !== 'mediator') {
    return { ok: false, status: 403, error: 'Operator role required' };
  }

  return { ok: true };
}

async function fetchVWorldCoordinate(
  address: string,
  type: VWorldAddressType,
  apiKey: string,
): Promise<GeocodeMatch | null> {
  const url = new URL('https://api.vworld.kr/req/address');
  url.searchParams.set('service', 'address');
  url.searchParams.set('request', 'getcoord');
  url.searchParams.set('version', '2.0');
  url.searchParams.set('crs', 'epsg:4326');
  url.searchParams.set('address', address);
  url.searchParams.set('refine', 'true');
  url.searchParams.set('simple', 'false');
  url.searchParams.set('format', 'json');
  url.searchParams.set('type', type);
  url.searchParams.set('key', apiKey);

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`VWorld request failed with HTTP ${response.status}`);
  }

  const data = (await response.json()) as VWorldResponse;
  const payload = data.response;
  const status = payload?.status;

  if (status === 'NOT_FOUND') {
    return null;
  }

  if (status !== 'OK') {
    const detail = payload?.error?.text ?? payload?.error?.code ?? status;
    throw new Error(`VWorld rejected the address lookup: ${detail}`);
  }

  const result = payload?.result;
  const longitude = Number(result?.point?.x);
  const latitude = Number(result?.point?.y);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new Error('VWorld returned an invalid coordinate');
  }

  return {
    provider: 'vworld',
    sourceType: type,
    matchedAddress: result?.refined?.text ?? result?.text ?? address,
    latitude,
    longitude,
  };
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}
