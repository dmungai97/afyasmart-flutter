// CORS + JSON response helpers, previously copy-pasted into all three
// functions.

export function corsHeaders(): HeadersInit {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  };
}

// deno-lint-ignore no-explicit-any
export function json(body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}

export function preflight(): Response {
  return new Response(null, { status: 204, headers: corsHeaders() });
}
