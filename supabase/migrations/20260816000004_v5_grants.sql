-- ============================================================================
-- 這餐吃什麼 App — Grant table privileges to `authenticated` (v5 補充)
-- ============================================================================
-- 用 SQL Editor 手動 CREATE TABLE(不是透過 Supabase Table Editor UI 建的)
-- 不會自動套用 Supabase 預設的 anon/authenticated 角色權限——RLS policy
-- 只負責「篩選看得到哪些 row」,底層一定要先有 GRANT 才有資格碰這張表,
-- 兩者是分開的兩層。少了這步,即使 policy 寫對了,查詢還是會直接被
-- Postgres 擋成 42501 permission denied。
--
-- 只 grant 給 authenticated,不 grant 給 anon——目前設計沒有任何合法的
-- 匿名存取路徑(訪客用邀請連結加入的功能,交接文件跟 RLS policy 檔案
-- 都已經說明是走 Edge Function + service_role,不透過這裡的角色權限),
-- anon 沒有 grant,RLS 就算了也一樣進不去,雙重保險。
-- ============================================================================

grant usage on schema public to authenticated;

grant select, insert, update, delete on
  groups,
  group_members,
  restaurants,
  restaurant_menu_items,
  restaurant_photos,
  custom_categories,
  custom_prefs,
  decision_history,
  decision_sessions,
  session_participants,
  session_pool,
  session_votes,
  orders,
  order_items
to authenticated;
