import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type RevenueCatWebhookBody = {
  event?: {
    type?: string;
    app_user_id?: string;
    entitlement_id?: string | null;
    entitlement_ids?: string[] | null;
    product_id?: string | null;
    original_transaction_id?: string | null;
    transaction_id?: string | null;
    store?: string | null;
    environment?: string | null;
    purchased_at_ms?: number | null;
    expiration_at_ms?: number | null;
    event_timestamp_ms?: number | null;
  };
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const expectedAuthorization = Deno.env.get("REVENUECAT_WEBHOOK_AUTHORIZATION") || "";
const proEntitlementID = Deno.env.get("REVENUECAT_PRO_ENTITLEMENT_ID") || "pro";

const supabase = createClient(supabaseUrl, serviceRoleKey);

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function dateFromMillis(ms: number | null | undefined): string | null {
  if (typeof ms !== "number" || Number.isFinite(ms) === false) return null;
  return new Date(ms).toISOString();
}

function entitlementIDs(event: NonNullable<RevenueCatWebhookBody["event"]>): string[] {
  const ids = new Set<string>();
  if (typeof event.entitlement_id === "string" && event.entitlement_id.length > 0) {
    ids.add(event.entitlement_id);
  }
  for (const id of event.entitlement_ids ?? []) {
    if (typeof id === "string" && id.length > 0) ids.add(id);
  }
  return [...ids];
}

function isRevocationEvent(type: string): boolean {
  // CANCELLATION usually means auto-renew was turned off; access should remain
  // until RevenueCat sends EXPIRATION. BILLING_ISSUE may still recover or enter
  // platform grace, so it must not immediately revoke server access.
  return type === "EXPIRATION";
}

function parseUserID(appUserID: string | undefined): string | null {
  if (!appUserID) return null;
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidPattern.test(appUserID) ? appUserID : null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "METHOD_NOT_ALLOWED" });
  }

  const authorization = req.headers.get("authorization") || "";
  if (!expectedAuthorization || authorization !== expectedAuthorization) {
    console.warn("[RevenueCat] Unauthorized webhook request");
    return json(401, { ok: false, error: "UNAUTHORIZED" });
  }

  let body: RevenueCatWebhookBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { ok: false, error: "INVALID_JSON" });
  }

  const event = body.event;
  if (!event || typeof event.type !== "string") {
    return json(400, { ok: false, error: "MISSING_EVENT" });
  }

  const userID = parseUserID(event.app_user_id);
  if (!userID) {
    return json(400, { ok: false, error: "INVALID_APP_USER_ID" });
  }

  const ids = entitlementIDs(event);
  if (!ids.includes(proEntitlementID)) {
    return json(200, { ok: true, ignored: true, reason: "NON_PRO_ENTITLEMENT" });
  }

  const now = new Date().toISOString();
  const eventAt = dateFromMillis(event.event_timestamp_ms) ?? now;
  const isRevoked = isRevocationEvent(event.type);

  const { data: existing, error: existingError } = await supabase
    .from("premium_entitlements")
    .select("last_event_at")
    .eq("provider", "revenuecat")
    .eq("user_id", userID)
    .eq("entitlement_id", proEntitlementID)
    .maybeSingle();

  if (existingError) {
    console.error("[RevenueCat] entitlement lookup failed", existingError);
    return json(500, { ok: false, error: "LOOKUP_FAILED" });
  }

  if (existing?.last_event_at && new Date(existing.last_event_at).getTime() > new Date(eventAt).getTime()) {
    return json(200, { ok: true, ignored: true, reason: "STALE_EVENT" });
  }

  const row = {
    user_id: userID,
    provider: "revenuecat",
    entitlement_id: proEntitlementID,
    product_id: event.product_id ?? null,
    original_transaction_id: event.original_transaction_id ?? null,
    transaction_id: event.transaction_id ?? null,
    store: event.store ?? null,
    environment: event.environment ?? null,
    purchased_at: dateFromMillis(event.purchased_at_ms),
    expires_at: dateFromMillis(event.expiration_at_ms),
    revoked_at: isRevoked ? now : null,
    last_event_type: event.type,
    last_event_at: eventAt,
    raw_event: event,
  };

  const { error } = await supabase
    .from("premium_entitlements")
    .upsert(row, { onConflict: "provider,user_id,entitlement_id" });

  if (error) {
    console.error("[RevenueCat] entitlement upsert failed", error);
    return json(500, { ok: false, error: "UPSERT_FAILED" });
  }

  return json(200, { ok: true, user_id: userID, entitlement_id: proEntitlementID });
});
