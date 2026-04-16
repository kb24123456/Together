import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const apnsKeyId = Deno.env.get("APNS_KEY_ID") || "";
const apnsTeamId = Deno.env.get("APNS_TEAM_ID") || "";
const apnsPrivateKey = Deno.env.get("APNS_PRIVATE_KEY") || "";
const appBundleId = "com.pigdog.Together";

const supabase = createClient(supabaseUrl, serviceRoleKey);

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    const { type, table, record, old_record } = payload;

    // 确定操作者 ID
    const actorId = record?.creator_id || record?.sender_id;
    if (!actorId) return new Response("No actor", { status: 200 });

    // 确定 space_id
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

    // 查找对方的 user_id
    const { data: members } = await supabase
      .from("space_members")
      .select("user_id")
      .eq("space_id", spaceId)
      .neq("user_id", actorId);

    if (!members || members.length === 0) {
      return new Response("No partner", { status: 200 });
    }

    const partnerId = members[0].user_id;

    // 查找对方的 device tokens
    const { data: tokens } = await supabase
      .from("device_tokens")
      .select("token")
      .eq("user_id", partnerId);

    if (!tokens || tokens.length === 0) {
      return new Response("No tokens", { status: 200 });
    }

    // 查找操作者的昵称
    const { data: actor } = await supabase
      .from("space_members")
      .select("display_name")
      .eq("space_id", spaceId)
      .eq("user_id", actorId)
      .single();

    const actorName = actor?.display_name || "伴侣";

    // 构造推送内容
    const notification = buildNotification(table, type, record, actorName);
    if (!notification) return new Response("Skip", { status: 200 });

    // ��送 APNs
    let sentCount = 0;
    for (const { token } of tokens) {
      const success = await sendAPNs(token, notification);
      if (success) sentCount++;
    }

    return new Response(JSON.stringify({ sent: sentCount }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error(`[Push] Error: ${error}`);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

function buildNotification(
  table: string,
  type: string,
  record: Record<string, unknown>,
  actorName: string
): { title: string; body: string } | null {
  if (table === "tasks" && type === "INSERT") {
    if (record.assignee_mode === "partner") {
      return { title: "新任务", body: `${actorName} 给你分配了「${record.title}」` };
    }
    return null;
  }
  if (table === "tasks" && type === "UPDATE") {
    if (record.status === "completed") {
      return {
        title: "任务完成",
        body: `${actorName} 完成了「${record.title}」`,
      };
    }
    // 已读变更不发推送
    if (record.is_read_by_partner === true) return null;
    return null;
  }
  if (table === "task_messages") {
    if (record.type === "nudge") {
      return { title: "催一下", body: `${actorName} 催你完成任务` };
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

async function sendAPNs(
  deviceToken: string,
  notification: { title: string; body: string }
): Promise<boolean> {
  // APNs HTTP/2 推送
  // 注意：完整实现需要使用 .p8 私钥生成 JWT
  // 此处为框架代码，APNs JWT 签名需要在部署时通过 jose 库补充
  const apnsPayload = {
    aps: {
      alert: { title: notification.title, body: notification.body },
      sound: "default",
      badge: 1,
    },
  };

  // 生产环境使用: https://api.push.apple.com
  // 沙盒环境使用: https://api.sandbox.push.apple.com
  const url = `https://api.sandbox.push.apple.com/3/device/${deviceToken}`;

  try {
    // TODO: 实现完整的 APNs JWT 签名和 HTTP/2 请求
    // 需要配置 Supabase Secrets: APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY
    console.log(
      `[APNs] Would send to ${deviceToken.substring(0, 8)}...: ${JSON.stringify(apnsPayload)}`
    );
    return true;
  } catch (error) {
    console.error(`[APNs] Error: ${error}`);
    return false;
  }
}
