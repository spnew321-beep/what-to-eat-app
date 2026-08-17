// 這餐吃什麼 App — guest-session Edge Function (v5)
// ----------------------------------------------------------------------------
// 訪客(沒有登入帳號)透過邀請連結加入協作場次時,唯一能碰資料庫的入口。
// 用 service_role 繞過 RLS,但每個動作都先驗證 invite_token 對應到哪個場次、
// 場次還在收集中且沒過期,確保訪客只能碰自己被邀請的那個場次,碰不到別人的。
//
// 部署方式:Supabase Dashboard → Edge Functions → New function → 命名
// "guest-session" → 把這份檔案整份貼進去 → Deploy。JWT 驗證維持預設開啟,
// 前端呼叫時帶 anon key 當 Authorization,場次授權靠 body 裡的 token 另外檢查。
// ----------------------------------------------------------------------------

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(supabaseUrl, serviceKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }

  const { action, token } = body;
  if (!token) return json({ error: "缺少邀請連結的 token" }, 400);

  const { data: session, error: sessionErr } = await admin
    .from("decision_sessions")
    .select("*")
    .eq("invite_token", token)
    .maybeSingle();
  if (sessionErr || !session) return json({ error: "找不到這個場次,連結可能失效了" }, 404);

  const isOpen = session.status === "collecting" && new Date(session.deadline_at) > new Date();

  // ---------- join：不需要已加入的 participantId，唯一能建立新參與者的動作 ----------
  if (action === "join") {
    const displayName = String(body.displayName || "").trim().slice(0, 40);
    if (!displayName) return json({ error: "請輸入名字" }, 400);
    if (!isOpen) return json({ error: "這個場次已經結束了" }, 400);
    const { data: participant, error: pErr } = await admin
      .from("session_participants")
      .insert({ session_id: session.id, display_name: displayName, is_guest: true })
      .select()
      .single();
    if (pErr || !participant) return json({ error: "加入失敗,請再試一次" }, 500);
    return json({ participantId: participant.id });
  }

  // ---------- 以下動作都要先確認呼叫的人是這個場次真的參與者 ----------
  const participantId = body.participantId;
  if (!participantId) return json({ error: "missing participantId" }, 400);
  const { data: participant, error: partErr } = await admin
    .from("session_participants")
    .select("*")
    .eq("id", participantId)
    .eq("session_id", session.id)
    .maybeSingle();
  if (partErr || !participant) return json({ error: "找不到你的參與者資料,可能需要重新加入" }, 404);

  if (action === "state") {
    const { data: pool } = await admin
      .from("session_pool")
      .select("*, restaurants(name, category, price), session_votes(*)")
      .eq("session_id", session.id)
      .order("created_at", { ascending: true });
    const { data: participants } = await admin
      .from("session_participants")
      .select("id, display_name, is_guest, ready")
      .eq("session_id", session.id)
      .order("joined_at", { ascending: true });

    let winner = null;
    if (session.winner_restaurant_id) {
      const { data: r } = await admin
        .from("restaurants")
        .select("name, category, price")
        .eq("id", session.winner_restaurant_id)
        .maybeSingle();
      winner = r;
    }

    return json({
      session: {
        status: session.status,
        decisionMode: session.decision_mode,
        deadlineAt: session.deadline_at,
        winner,
      },
      pool: (pool || []).map((item: any) => ({
        id: item.id,
        restaurantId: item.restaurant_id,
        name: item.restaurant_id ? item.restaurants?.name : item.adhoc_name,
        category: item.restaurant_id ? item.restaurants?.category : item.adhoc_category,
        price: item.restaurant_id ? item.restaurants?.price : null,
        isAdhoc: !item.restaurant_id,
        accept: (item.session_votes || []).filter((v: any) => v.accepted).length,
        reject: (item.session_votes || []).filter((v: any) => !v.accepted).length,
        myVote:
          (item.session_votes || []).find((v: any) => v.voter_participant_id === participantId)
            ?.accepted ?? null,
      })),
      participants: participants || [],
      me: { id: participant.id, name: participant.display_name, ready: participant.ready },
    });
  }

  if (action === "addCandidate") {
    if (!isOpen) return json({ error: "這個場次已經結束了" }, 400);
    const name = String(body.name || "").trim().slice(0, 60);
    if (!name) return json({ error: "請輸入店名" }, 400);
    const category = String(body.category || "其他").slice(0, 20);
    const { error } = await admin.from("session_pool").insert({
      session_id: session.id,
      adhoc_name: name,
      adhoc_category: category,
      added_by_participant_id: participantId,
    });
    if (error) return json({ error: "新增失敗,請再試一次" }, 500);
    return json({ ok: true });
  }

  if (action === "vote") {
    if (!isOpen) return json({ error: "這個場次已經結束了" }, 400);
    const poolItemId = body.poolItemId;
    const accepted = !!body.accepted;
    if (!poolItemId) return json({ error: "missing poolItemId" }, 400);
    const { error } = await admin
      .from("session_votes")
      .upsert(
        { pool_item_id: poolItemId, voter_participant_id: participantId, accepted },
        { onConflict: "pool_item_id,voter_participant_id" }
      );
    if (error) return json({ error: "投票失敗,請再試一次" }, 500);
    return json({ ok: true });
  }

  if (action === "toggleReady") {
    const { error } = await admin
      .from("session_participants")
      .update({ ready: !participant.ready })
      .eq("id", participantId);
    if (error) return json({ error: "更新失敗,請再試一次" }, 500);
    return json({ ok: true, ready: !participant.ready });
  }

  return json({ error: "unknown action" }, 400);
});
