-- ============================================================================
-- 這餐吃什麼 App — Grant table privileges to `service_role` (v5 補充)
-- ============================================================================
-- 跟 20260816000004_v5_grants.sql 是同一個坑:用 SQL Editor 手動建的表,
-- 不會自動套用 Supabase 預設角色權限——這次踩到的是 service_role。
--
-- 一般認知裡 service_role 天生繞過 RLS,但那只表示「RLS policy 不會擋
-- service_role」,底層 GRANT 這層完全是另一回事,兩者互不相關。guest-session
-- Edge Function 用 service_role 幫訪客讀寫協作場次資料時,少了這個 GRANT
-- 一樣會被 Postgres 擋成 42501 permission denied,即使程式邏輯完全正確。
--
-- 只補協作場次相關的表(guest-session function 實際會碰到的),
-- 外加 restaurants 唯讀(訪客端要顯示候選餐廳的名稱/類型/價位)。
-- ============================================================================

grant select, insert, update, delete on
  decision_sessions,
  session_participants,
  session_pool,
  session_votes
to service_role;

grant select on restaurants to service_role;
