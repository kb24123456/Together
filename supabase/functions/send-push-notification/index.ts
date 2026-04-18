import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "jsr:@panva/jose";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const apnsKeyId = Deno.env.get("APNS_KEY_ID") || "";
const apnsTeamId = Deno.env.get("APNS_TEAM_ID") || "";
const apnsPrivateKeyPEM = Deno.env.get("APNS_PRIVATE_KEY") || "";
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
  notification: { title: string; body: string },
  taskId: string | undefined,
): Promise<{ ok: boolean; status: number; deleteToken: boolean }> {
  const jwt = await getApnsJWT();
  const payload = {
    aps: {
      alert: { title: notification.title, body: notification.body },
      sound: "default",
      badge: 1,
      category: "TASK_NUDGE",
    },
    task_id: taskId,
  };
  const url = `https://api.sandbox.push.apple.com/3/device/${deviceToken}`;
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
  return { ok: res.ok, status: res.status, deleteToken: res.status === 410 };
}

function buildNotification(
  table: string,
  type: string,
  record: Record<string, unknown>,
  actorName: string,
): { title: string; body: string } | null {
  if (table === "tasks" && type === "INSERT") {
    if (record.assignee_mode === "partner") {
      return { title: "新任务", body: `${actorName} 给你分配了「${record.title}」` };
    }
    return null;
  }
  if (table === "tasks" && type === "UPDATE") {
    if (record.status === "completed") {
      return { title: "任务完成", body: `${actorName} 完成了「${record.title}」` };
    }
    return null;
  }
  if (table === "task_messages") {
    if (record.type === "nudge") {
      return { title: "提醒", body: `${actorName} 提醒你完成任务` };
    }
    if (record.type === "comment") {
      return { title: "留言", body: `${actorName} 给你留了言` };
    }
    if (record.type === "rps_result") {
      return { title: "✊✌️✋", body: `${actorName} 发起了石头剪刀布！` };
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    const { type, table, record } = payload;

    const actorId = record?.creator_id || record?.sender_id;
    if (!actorId) return new Response("No actor", { status: 200 });

    // Look up space_id — either on record directly, or via tasks join for task_messages.
    let spaceId = record?.space_id;
    if (!spaceId && table === "task_messages") {
      const { data: task } = await supabase
        .from("tasks")
        .select("space_id")
        .eq("id", record.task_id)
        .single();
      spaceId = task?.space_id;
    }
    if (!spaceId) return new Response("No space", { status: 200 });

    // Find partner (everyone else in space).
    const { data: members } = await supabase
      .from("space_members")
      .select("user_id")
      .eq("space_id", spaceId)
      .neq("user_id", actorId);

    if (!members || members.length === 0) return new Response("No partner", { status: 200 });
    const partnerId = members[0].user_id;

    // Partner's device tokens.
    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", partnerId);

    if (!tokens || tokens.length === 0) return new Response("No tokens", { status: 200 });

    // Actor display name.
    const { data: actor } = await supabase
      .from("space_members")
      .select("display_name")
      .eq("space_id", spaceId)
      .eq("user_id", actorId)
      .single();

    const actorName = actor?.display_name || "伴侣";

    const notification = buildNotification(table, type, record, actorName);
    if (!notification) return new Response("Skip", { status: 200 });

    const taskId: string | undefined =
      table === "task_messages" ? (record.task_id as string | undefined) : (record.id as string | undefined);

    let sentCount = 0;
    for (const { token } of tokens) {
      try {
        const result = await sendAPNs(token, notification, taskId);
        if (result.ok) {
          sentCount++;
        } else if (result.deleteToken) {
          await supabase.from("device_tokens").delete().eq("token", token);
          console.warn(`[APNs] 410 Unregistered — deleted token ${token.substring(0, 8)}...`);
        } else {
          console.error(`[APNs] ${result.status} for ${token.substring(0, 8)}...`);
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
