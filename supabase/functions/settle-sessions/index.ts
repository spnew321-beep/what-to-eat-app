// 這餐吃什麼 App — settle-sessions Edge Function (v6)
// ----------------------------------------------------------------------------
// 排程保底(交接文件第 6 節「逾時觸發機制 A」)。前端只有 owner 剛好開著場次
// 進行中畫面時才會結算/清理,這支函式負責「就算所有人都關掉分頁」也能準時
// 處理:
//   1. 掃描 status='collecting' 且 deadline_at 已過的場次,依候選/表態結算
//   2. 掃描 status in ('done','no_result') 且 cleanup_after 已過的場次,整個刪除
// 結算邏輯刻意跟 meal-picker.html 的 collabSettle()/finishCollabWithWinner()
// 保持一致(候選 0 間 = no_result;vote_first 模式先篩掉有人不接受的,全部
// 被否決則退回完整候選名單;剩下的候選隨機挑一個當贏家——前端的轉盤動畫只是
// 視覺效果,實際選擇本來就是隨機的)。
//
// 部署方式跟 guest-session 一樣:Supabase Dashboard → Edge Functions →
// Via Editor → 貼上整份 → Deploy。接著要設定排程,見交接文件第 6 節說明。
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

async function settleOne(session: any) {
  const { data: pool } = await admin
    .from("session_pool")
    .select("*, restaurants(name, category), session_votes(*)")
    .eq("session_id", session.id);

  const items = (pool || []).map((item: any) => ({
    id: item.id,
    restaurantId: item.restaurant_id,
    name: item.restaurant_id ? item.restaurants?.name : item.adhoc_name,
    category: item.restaurant_id ? item.restaurants?.category : item.adhoc_category,
    isAdhoc: !item.restaurant_id,
    rejectCount: (item.session_votes || []).filter((v: any) => !v.accepted).length,
  }));

  const cleanupAfter = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  if (items.length === 0) {
    await admin
      .from("decision_sessions")
      .update({ status: "no_result", cleanup_after: cleanupAfter })
      .eq("id", session.id);
    return { id: session.id, result: "no_result" };
  }

  let eligible = items;
  if (session.decision_mode === "vote_first") {
    const accepted = items.filter((i: any) => i.rejectCount === 0);
    if (accepted.length > 0) eligible = accepted;
  }

  const winner = eligible[Math.floor(Math.random() * eligible.length)];

  await admin.from("decision_history").insert({
    owner_user_id: session.owner_user_id,
    restaurant_id: winner.isAdhoc ? null : winner.restaurantId,
    restaurant_name: winner.name,
    category: winner.category,
  });

  await admin
    .from("decision_sessions")
    .update({
      status: "done",
      winner_restaurant_id: winner.isAdhoc ? null : winner.restaurantId,
      winner_name: winner.name,
      winner_category: winner.category,
      cleanup_after: cleanupAfter,
    })
    .eq("id", session.id);

  return { id: session.id, result: "done", winner: winner.name };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const nowIso = new Date().toISOString();

  const { data: expired, error: expiredErr } = await admin
    .from("decision_sessions")
    .select("*")
    .eq("status", "collecting")
    .lte("deadline_at", nowIso);

  const settled = [];
  if (!expiredErr && expired) {
    for (const session of expired) {
      try {
        settled.push(await settleOne(session));
      } catch (e) {
        settled.push({ id: session.id, result: "error", message: String(e) });
      }
    }
  }

  const { data: toDelete, error: deleteErr } = await admin
    .from("decision_sessions")
    .delete()
    .in("status", ["done", "no_result"])
    .lte("cleanup_after", nowIso)
    .select("id");

  return json({
    settled,
    deletedCount: deleteErr ? null : (toDelete || []).length,
    expiredErr: expiredErr?.message,
    deleteErr: deleteErr?.message,
  });
});
