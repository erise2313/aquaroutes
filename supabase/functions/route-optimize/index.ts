// Road-following route planning for GenTri WASA deliveries.
//
// Takes the station and the stops to visit, and returns the order to visit
// them in plus the actual road geometry between them. Before this existed,
// the app drew straight lines between coordinates and called that a route
// (lib/services/route_optimization.dart explains why).
//
// Provider is chosen by configuration, so switching needs no app release:
//   * ORS_API_KEY secret set  -> OpenRouteService optimization (VROOM).
//     The production path once the client organisation owns the account.
//   * otherwise               -> an OSRM `trip` endpoint, by default the
//     keyless FOSSGIS instance. Fine for testing; its terms allow at most
//     one request per second and no heavy use, so it is not a production
//     backend. OSRM_BASE_URL overrides it (e.g. a self-hosted OSRM).
//
// Keys live here as Supabase secrets and never reach the app. That is the
// whole point of the function: the Google implementation this replaces
// shipped a service-account private key inside the client.

const USER_AGENT = "GenTri-WASA/1.0 (+https://gentri-wasa.web.app)";
const DEFAULT_OSRM_BASE = "https://routing.openstreetmap.de/routed-car";
const MAX_STOPS = 25;
const TIMEOUT_MS = 10_000;

type LatLng = { lat: number; lng: number };

type RoutePlan = {
  provider: "osrm" | "openrouteservice";
  /** Visiting order, as indices into the request's `stops`. */
  sequence: number[];
  /** Road geometry from the origin through every stop, as [lat, lng]. */
  points: [number, number][];
  distance_m: number;
  duration_s: number;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isLatLng(v: unknown): v is LatLng {
  if (typeof v !== "object" || v === null) return false;
  const { lat, lng } = v as Record<string, unknown>;
  return typeof lat === "number" && typeof lng === "number" &&
    Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
}

/**
 * Role claim of the caller's JWT. The Supabase gateway has already verified
 * the signature (verify_jwt), so reading the payload here is safe.
 */
function jwtRole(req: Request): string | null {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const padded = b64.padEnd(Math.ceil(b64.length / 4) * 4, "=");
    const payload = JSON.parse(atob(padded));
    return typeof payload.role === "string" ? payload.role : null;
  } catch {
    return null;
  }
}

/** Standard encoded-polyline decoder (precision 5), returning [lat, lng]. */
function decodePolyline(encoded: string): [number, number][] {
  const points: [number, number][] = [];
  let index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    for (const axis of [0, 1]) {
      let result = 0, shift = 0, byte: number;
      do {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      const delta = result & 1 ? ~(result >> 1) : result >> 1;
      if (axis === 0) lat += delta; else lng += delta;
    }
    points.push([lat / 1e5, lng / 1e5]);
  }
  return points;
}

async function planWithOsrm(origin: LatLng, stops: LatLng[]): Promise<RoutePlan> {
  const base = (Deno.env.get("OSRM_BASE_URL") ?? DEFAULT_OSRM_BASE).replace(/\/$/, "");
  const coords = [origin, ...stops].map((p) => `${p.lng},${p.lat}`).join(";");
  // source=first pins the station as the start; roundtrip=false means the
  // driver doesn't have to be routed back to it at the end.
  const url = `${base}/trip/v1/driving/${coords}?source=first&roundtrip=false&geometries=geojson&overview=full`;

  const res = await fetch(url, {
    headers: { "User-Agent": USER_AGENT },
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`OSRM HTTP ${res.status}`);
  const data = await res.json();
  if (data.code !== "Ok" || !Array.isArray(data.trips) || data.trips.length === 0) {
    throw new Error(`OSRM returned ${data.code ?? "no trip"}`);
  }

  // `waypoints` is in *input* order; each carries its position in the trip.
  // Input 0 is the station, so stop j is input j + 1.
  const waypoints = data.waypoints as { waypoint_index: number }[];
  const sequence = stops
    .map((_, j) => j)
    .sort((a, b) => waypoints[a + 1].waypoint_index - waypoints[b + 1].waypoint_index);

  const trip = data.trips[0];
  const points = (trip.geometry.coordinates as [number, number][])
    .map(([lng, lat]) => [lat, lng] as [number, number]);

  return {
    provider: "osrm",
    sequence,
    points,
    distance_m: Math.round(trip.distance),
    duration_s: Math.round(trip.duration),
  };
}

async function planWithOrs(key: string, origin: LatLng, stops: LatLng[]): Promise<RoutePlan> {
  // Not exercised until the client organisation's ORS key is added as a
  // secret -- verify this path end-to-end at that point.
  const res = await fetch("https://api.openrouteservice.org/optimization", {
    method: "POST",
    headers: {
      Authorization: key,
      "Content-Type": "application/json",
      "User-Agent": USER_AGENT,
    },
    body: JSON.stringify({
      jobs: stops.map((s, j) => ({ id: j + 1, location: [s.lng, s.lat] })),
      vehicles: [{ id: 1, profile: "driving-car", start: [origin.lng, origin.lat] }],
      options: { g: true },
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`ORS HTTP ${res.status}`);
  const data = await res.json();
  const route = data.routes?.[0];
  if (!route) throw new Error("ORS returned no route");

  const sequence = (route.steps as { type: string; id?: number; job?: number }[])
    .filter((s) => s.type === "job")
    .map((s) => (s.id ?? s.job ?? 0) - 1);
  if (sequence.length !== stops.length) {
    throw new Error(`ORS left ${stops.length - sequence.length} stop(s) unassigned`);
  }

  return {
    provider: "openrouteservice",
    sequence,
    points: decodePolyline(route.geometry),
    distance_m: Math.round(route.distance ?? 0),
    duration_s: Math.round(route.duration ?? 0),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);

  // Signed-in users only. The anon key is public (it ships in the website),
  // so accepting it would let anyone push traffic through this function to
  // the routing provider -- and the keyless provider blocks by source IP,
  // which would break routing for every real user at once.
  if (jwtRole(req) !== "authenticated") {
    return json({ error: "Sign in to plan a route." }, 401);
  }

  let payload: { origin?: unknown; stops?: unknown };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Request body must be JSON." }, 400);
  }

  const { origin, stops } = payload;
  if (!isLatLng(origin) || !Array.isArray(stops) || !stops.every(isLatLng)) {
    return json({ error: "Expected { origin: {lat, lng}, stops: [{lat, lng}, ...] }." }, 400);
  }
  if (stops.length === 0) return json({ error: "No stops to route." }, 400);
  if (stops.length > MAX_STOPS) {
    return json({ error: `At most ${MAX_STOPS} stops per route.` }, 400);
  }

  const orsKey = Deno.env.get("ORS_API_KEY");
  try {
    const plan = orsKey
      ? await planWithOrs(orsKey, origin, stops)
      : await planWithOsrm(origin, stops);
    return json(plan);
  } catch (e) {
    // Deliberately no coordinates in the log: stops are customer addresses.
    console.error("route-optimize failed:", e instanceof Error ? e.message : String(e));
    return json({ error: "The routing service is unavailable right now." }, 502);
  }
});
