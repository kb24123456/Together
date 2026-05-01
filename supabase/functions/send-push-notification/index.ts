import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "jsr:@panva/jose";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const apnsKeyId = Deno.env.get("APNS_KEY_ID") || "";
const apnsTeamId = Deno.env.get("APNS_TEAM_ID") || "";
const apnsPrivateKeyPEM = Deno.env.get("APNS_PRIVATE_KEY") || "";
const webhookSecret = Deno.env.get("TOGETHER_PUSH_WEBHOOK_SECRET") || "";
const appBundleId = "com.pigdog.Together";

const supabase = createClient(supabaseUrl, serviceRoleKey);

// JWT cached per instance; APNs token is valid for up to 60 minutes.
let cachedJWT: { token: string; exp: number } | null = null;

async function getApnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && cachedJWT.exp > now + 300) return cachedJWT.token;

  const privateKey = await importPKCS8(apnsPrivateKeyPEM, "ES256");
  const jwt = await new SignJWT({ iss: apnsTeamId, iat: now })
    .setProtectedHeader({ alg: "ES256", kid: apnsKeyId })
    .sign(privateKey);

  cachedJWT = { token: jwt, exp: now + 3000 };  // 50 min
  return jwt;
}

async function sendAPNs(
  deviceToken: string,
  notification: { title: string; body: string; eventType?: string },
  taskId: string | undefined,
  senderId: string | undefined,
): Promise<{ ok: boolean; status: number; deleteToken: boolean; reason?: string; environment: "production" | "development" }> {
  const productionResult = await sendAPNsToEnvironment("production", deviceToken, notification, taskId, senderId);
  if (productionResult.ok || productionResult.status !== 400 || productionResult.reason !== "BadDeviceToken") {
    return productionResult;
  }

  // Debug/development builds generate sandbox APNs tokens. TestFlight and
  // App Store builds generate production tokens. Production-first keeps the
  // user-facing TestFlight path fast while preserving local debug delivery.
  return sendAPNsToEnvironment("development", deviceToken, notification, taskId, senderId);
}

async function sendAPNsToEnvironment(
  environment: "production" | "development",
  deviceToken: string,
  notification: { title: string; body: string; eventType?: string },
  taskId: string | undefined,
  senderId: string | undefined,
): Promise<{ ok: boolean; status: number; deleteToken: boolean; reason?: string; environment: "production" | "development" }> {
  const jwt = await getApnsJWT();
  const category = categoryForEventType(notification.eventType);
  const payload = {
    aps: {
      alert: { title: notification.title, body: notification.body },
      sound: "default",
      badge: 1,
      category,
      "content-available": 1,
    },
    task_id: taskId,
    sender_id: senderId,
    event_type: notification.eventType,
  };
  const host = environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const url = `https://${host}/3/device/${deviceToken}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": appBundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify(payload),
  });
  let reason: string | undefined;
  if (!res.ok) {
    try {
      const body = await res.json();
      reason = typeof body?.reason === "string" ? body.reason : undefined;
    } catch {
      reason = undefined;
    }
  }
  return { ok: res.ok, status: res.status, deleteToken: res.status === 410, reason, environment };
}

function categoryForEventType(eventType: string | undefined): string {
  if (eventType === "pair_unbound") return "PAIR_STATUS";
  if (eventType === "task_created" || eventType === "task_nudge") return "TASK_NUDGE";
  return "together.notification.generic";
}

function buildNotification(
  table: string,
  type: string,
  record: Record<string, unknown>,
  oldRecord?: Record<string, unknown>,
): { title: string; body: string; eventType?: string } | null {
  if (table === "space_members" && type === "DELETE") {
    return {
      title: "双人空间已解除",
      body: "对方已解除绑定，当前设备将回到单人模式",
      eventType: "pair_unbound",
    };
  }
  if (table === "tasks" && type === "INSERT") {
    if (record.assignee_mode === "partner") {
      return { title: "新任务", body: `伴侣给你分配了「${record.title}」`, eventType: "task_created" };
    }
    return null;
  }
  if (table === "tasks" && type === "UPDATE") {
    const hasOldRecord = oldRecord && Object.keys(oldRecord).length > 0;
    if (record.status === "completed" && (!hasOldRecord || oldRecord?.status !== "completed")) {
      return { title: "任务完成", body: `伴侣完成了「${record.title}」`, eventType: "task_completed" };
    }
    if (hasOldRecord && record.assignment_state === "accepted" && oldRecord?.assignment_state !== "accepted") {
      return { title: "任务已接受", body: `伴侣接受了「${record.title}」`, eventType: "task_accepted" };
    }
    if (hasOldRecord && record.assignment_state === "declined" && oldRecord?.assignment_state !== "declined") {
      return { title: "任务被婉拒", body: `伴侣觉得「${record.title}」不太合适`, eventType: "task_declined" };
    }
    return null;
  }
  if (table === "task_messages" && type === "INSERT") {
    if (record.type === "nudge") {
      return { title: "提醒", body: "伴侣提醒你完成任务", eventType: "task_nudge" };
    }
    if (record.type === "comment") {
      return { title: "留言", body: "伴侣给你留了言", eventType: "task_comment" };
    }
    if (record.type === "rps_result") {
      return { title: "✊✌️✋", body: "伴侣发起了石头剪刀布！", eventType: "task_rps" };
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    const providedSecret = req.headers.get("x-together-webhook-secret") || "";
    if (!webhookSecret || providedSecret !== webhookSecret) {
      console.warn("[Push] Unauthorized webhook request");
      return new Response("Unauthorized", { status: 401 });
    }

    const payload = await req.json();
    const { type, table, record, old_record } = payload;

    const actorId: string | undefined = record?.creator_id || record?.sender_id || record?.user_id;

    // Resolve space_id — either on record directly, or via tasks join for task_messages.
    let spaceId: string | undefined = record?.space_id;
    if (!spaceId && table === "task_messages") {
      const { data: task } = await supabase
        .from("tasks")
        .select("space_id")
        .eq("id", record.task_id)
        .single();
      spaceId = task?.space_id;
    }
    if (!spaceId) return new Response("No space", { status: 200 });

    // Server-side sender exclusion (post-migration 023).
    // The client now writes the Supabase auth.uid into
    // tasks.creator_supabase_user_id / task_messages.sender_supabase_user_id
    // alongside the legacy local-UUID creator_id. When that column is set we
    // can drop the sender's device_tokens directly, avoiding the
    // willPresent-only client filter that misses background/locked deliveries
    // (the "user gets a push for their own action" bug). Old rows written by
    // pre-migration clients leave the column null; in that case we fall back
    // to fanning out to every member and rely on client-side filtering.
    const senderSupabaseUserId: string | undefined =
      record?.creator_supabase_user_id || record?.sender_supabase_user_id ||
      (table === "space_members" && type === "DELETE" ? record?.user_id : undefined);

    const { data: members } = await supabase
      .from("space_members")
      .select("user_id")
      .eq("space_id", spaceId);

    if (!members || members.length === 0) return new Response("No members", { status: 200 });

    const memberIds = members
      .map((m) => m.user_id)
      .filter((id) => senderSupabaseUserId ? id !== senderSupabaseUserId : true);

    if (memberIds.length === 0) return new Response("No recipients (sender excluded)", { status: 200 });

    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token")
      .in("user_id", memberIds);

    if (!tokens || tokens.length === 0) return new Response("No tokens", { status: 200 });

    const notification = buildNotification(table, type, record, old_record);
    if (!notification) return new Response("Skip", { status: 200 });

    const taskId: string | undefined = table === "task_messages"
      ? (record.task_id as string | undefined)
      : table === "tasks"
        ? (record.id as string | undefined)
        : undefined;

    let sentCount = 0;
    for (const { token } of tokens) {
      try {
        const result = await sendAPNs(token, notification, taskId, actorId);
        if (result.ok) {
          sentCount++;
        } else if (result.deleteToken) {
          await supabase.from("device_tokens").delete().eq("token", token);
          console.warn(`[APNs] 410 Unregistered — deleted token ${token.substring(0, 8)}...`);
        } else {
          console.error(`[APNs] ${result.status} ${result.reason ?? "Unknown"} env=${result.environment} for ${token.substring(0, 8)}...`);
        }
      } catch (e) {
        console.error(`[APNs] exception: ${e}`);
      }
    }

    return new Response(JSON.stringify({ sent: sentCount }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(`[Push] Error: ${error}`);
    // Always return 200 so Supabase webhook doesn't auto-retry and double-push.
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
});
