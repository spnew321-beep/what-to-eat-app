-- ============================================================================
-- 這餐吃什麼 App — RLS Policies (v5)
-- ============================================================================
-- 補上 20260816000000_v5_schema.sql 裡刻意留白的 RLS policy。
--
-- 原則:
--   1. 每個帳號只能讀寫「自己的」資料——直接有 owner_user_id 欄位的表,
--      用 owner_user_id = auth.uid() 判斷;沒有 owner_user_id 的子表
--      (group_members / restaurant_menu_items / restaurant_photos /
--      order_items / session_participants / session_pool / session_votes),
--      往上查父層的 owner_user_id 判斷。
--   2. decision_sessions 系列表(session_participants/session_pool/
--      session_votes)跟 orders 家族,這裡只開放給 owner——**訪客憑邀請
--      連結(invite_token)的存取,不透過這裡的 RLS policy 放行**,
--      刻意不放。交接文件第 5 節本文的建議是訪客寫入要走 Edge Function,
--      在 Function 裡驗證 token 沒過期後,用 service_role(本來就不受
--      RLS 限制)代為寫入,不要讓訪客直接拿到能繞過 RLS 的權限。這份
--      Edge Function 是後續 Tier 2 任務(邀請連結真的能用)才會實作。
--   3. group_members.linked_user_id 目前恆為 null(App 裡「連結帳號」
--      這個動作本身還沒做),所以這裡不寫「已連結的人可以讀自己那筆
--      member」這種 policy——等真的有連結流程時再補。
-- ============================================================================

-- ----------------------------------------------------------------------------
-- groups
-- ----------------------------------------------------------------------------
create policy "groups_select_own" on groups for select using (owner_user_id = auth.uid());
create policy "groups_insert_own" on groups for insert with check (owner_user_id = auth.uid());
create policy "groups_update_own" on groups for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy "groups_delete_own" on groups for delete using (owner_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- group_members(透過 group_id 往上查 groups.owner_user_id)
-- ----------------------------------------------------------------------------
create policy "group_members_select_own" on group_members for select using (
  exists (select 1 from groups g where g.id = group_members.group_id and g.owner_user_id = auth.uid())
);
create policy "group_members_insert_own" on group_members for insert with check (
  exists (select 1 from groups g where g.id = group_members.group_id and g.owner_user_id = auth.uid())
);
create policy "group_members_update_own" on group_members for update using (
  exists (select 1 from groups g where g.id = group_members.group_id and g.owner_user_id = auth.uid())
) with check (
  exists (select 1 from groups g where g.id = group_members.group_id and g.owner_user_id = auth.uid())
);
create policy "group_members_delete_own" on group_members for delete using (
  exists (select 1 from groups g where g.id = group_members.group_id and g.owner_user_id = auth.uid())
);

-- ----------------------------------------------------------------------------
-- restaurants
-- ----------------------------------------------------------------------------
create policy "restaurants_select_own" on restaurants for select using (owner_user_id = auth.uid());
create policy "restaurants_insert_own" on restaurants for insert with check (owner_user_id = auth.uid());
create policy "restaurants_update_own" on restaurants for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy "restaurants_delete_own" on restaurants for delete using (owner_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- restaurant_menu_items(透過 restaurant_id 往上查 restaurants.owner_user_id)
-- ----------------------------------------------------------------------------
create policy "restaurant_menu_items_select_own" on restaurant_menu_items for select using (
  exists (select 1 from restaurants r where r.id = restaurant_menu_items.restaurant_id and r.owner_user_id = auth.uid())
);
create policy "restaurant_menu_items_insert_own" on restaurant_menu_items for insert with check (
  exists (select 1 from restaurants r where r.id = restaurant_menu_items.restaurant_id and r.owner_user_id = auth.uid())
);
create policy "restaurant_menu_items_update_own" on restaurant_menu_items for update using (
  exists (select 1 from restaurants r where r.id = restaurant_menu_items.restaurant_id and r.owner_user_id = auth.uid())
) with check (
  exists (select 1 from restaurants r where r.id = restaurant_menu_items.restaurant_id and r.owner_user_id = auth.uid())
);
create policy "restaurant_menu_items_delete_own" on restaurant_menu_items for delete using (
  exists (select 1 from restaurants r where r.id = restaurant_menu_items.restaurant_id and r.owner_user_id = auth.uid())
);

-- ----------------------------------------------------------------------------
-- restaurant_photos(透過 restaurant_id 往上查 restaurants.owner_user_id)
-- ----------------------------------------------------------------------------
create policy "restaurant_photos_select_own" on restaurant_photos for select using (
  exists (select 1 from restaurants r where r.id = restaurant_photos.restaurant_id and r.owner_user_id = auth.uid())
);
create policy "restaurant_photos_insert_own" on restaurant_photos for insert with check (
  exists (select 1 from restaurants r where r.id = restaurant_photos.restaurant_id and r.owner_user_id = auth.uid())
);
create policy "restaurant_photos_update_own" on restaurant_photos for update using (
  exists (select 1 from restaurants r where r.id = restaurant_photos.restaurant_id and r.owner_user_id = auth.uid())
) with check (
  exists (select 1 from restaurants r where r.id = restaurant_photos.restaurant_id and r.owner_user_id = auth.uid())
);
create policy "restaurant_photos_delete_own" on restaurant_photos for delete using (
  exists (select 1 from restaurants r where r.id = restaurant_photos.restaurant_id and r.owner_user_id = auth.uid())
);

-- ----------------------------------------------------------------------------
-- custom_categories
-- ----------------------------------------------------------------------------
create policy "custom_categories_select_own" on custom_categories for select using (owner_user_id = auth.uid());
create policy "custom_categories_insert_own" on custom_categories for insert with check (owner_user_id = auth.uid());
create policy "custom_categories_update_own" on custom_categories for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy "custom_categories_delete_own" on custom_categories for delete using (owner_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- custom_prefs
-- ----------------------------------------------------------------------------
create policy "custom_prefs_select_own" on custom_prefs for select using (owner_user_id = auth.uid());
create policy "custom_prefs_insert_own" on custom_prefs for insert with check (owner_user_id = auth.uid());
create policy "custom_prefs_update_own" on custom_prefs for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy "custom_prefs_delete_own" on custom_prefs for delete using (owner_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- decision_history
-- ----------------------------------------------------------------------------
create policy "decision_history_select_own" on decision_history for select using (owner_user_id = auth.uid());
create policy "decision_history_insert_own" on decision_history for insert with check (owner_user_id = auth.uid());
create policy "decision_history_delete_own" on decision_history for delete using (owner_user_id = auth.uid());
-- 決策歷史不開放 update,產生後只有讀跟刪(比照原型行為,歷史紀錄不能改)

-- ----------------------------------------------------------------------------
-- decision_sessions(訪客憑 invite_token 的存取走 Edge Function,不在此開放)
-- ----------------------------------------------------------------------------
create policy "decision_sessions_select_own" on decision_sessions for select using (owner_user_id = auth.uid());
create policy "decision_sessions_insert_own" on decision_sessions for insert with check (owner_user_id = auth.uid());
create policy "decision_sessions_update_own" on decision_sessions for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy "decision_sessions_delete_own" on decision_sessions for delete using (owner_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- session_participants(透過 session_id 往上查 decision_sessions.owner_user_id)
-- ----------------------------------------------------------------------------
create policy "session_participants_select_own" on session_participants for select using (
  exists (select 1 from decision_sessions s where s.id = session_participants.session_id and s.owner_user_id = auth.uid())
);
create policy "session_participants_insert_own" on session_participants for insert with check (
  exists (select 1 from decision_sessions s where s.id = session_participants.session_id and s.owner_user_id = auth.uid())
);
create policy "session_participants_update_own" on session_participants for update using (
  exists (select 1 from decision_sessions s where s.id = session_participants.session_id and s.owner_user_id = auth.uid())
) with check (
  exists (select 1 from decision_sessions s where s.id = session_participants.session_id and s.owner_user_id = auth.uid())
);
create policy "session_participants_delete_own" on session_participants for delete using (
  exists (select 1 from decision_sessions s where s.id = session_participants.session_id and s.owner_user_id = auth.uid())
);

-- ----------------------------------------------------------------------------
-- session_pool(透過 session_id 往上查 decision_sessions.owner_user_id)
-- ----------------------------------------------------------------------------
create policy "session_pool_select_own" on session_pool for select using (
  exists (select 1 from decision_sessions s where s.id = session_pool.session_id and s.owner_user_id = auth.uid())
);
create policy "session_pool_insert_own" on session_pool for insert with check (
  exists (select 1 from decision_sessions s where s.id = session_pool.session_id and s.owner_user_id = auth.uid())
);
create policy "session_pool_update_own" on session_pool for update using (
  exists (select 1 from decision_sessions s where s.id = session_pool.session_id and s.owner_user_id = auth.uid())
) with check (
  exists (select 1 from decision_sessions s where s.id = session_pool.session_id and s.owner_user_id = auth.uid())
);
create policy "session_pool_delete_own" on session_pool for delete using (
  exists (select 1 from decision_sessions s where s.id = session_pool.session_id and s.owner_user_id = auth.uid())
);

-- ----------------------------------------------------------------------------
-- session_votes(透過 pool_item_id → session_pool → decision_sessions.owner_user_id)
-- ----------------------------------------------------------------------------
create policy "session_votes_select_own" on session_votes for select using (
  exists (
    select 1 from session_pool p join decision_sessions s on s.id = p.session_id
    where p.id = session_votes.pool_item_id and s.owner_user_id = auth.uid()
  )
);
create policy "session_votes_insert_own" on session_votes for insert with check (
  exists (
    select 1 from session_pool p join decision_sessions s on s.id = p.session_id
    where p.id = session_votes.pool_item_id and s.owner_user_id = auth.uid()
  )
);
create policy "session_votes_delete_own" on session_votes for delete using (
  exists (
    select 1 from session_pool p join decision_sessions s on s.id = p.session_id
    where p.id = session_votes.pool_item_id and s.owner_user_id = auth.uid()
  )
);

-- ----------------------------------------------------------------------------
-- orders
-- ----------------------------------------------------------------------------
create policy "orders_select_own" on orders for select using (owner_user_id = auth.uid());
create policy "orders_insert_own" on orders for insert with check (owner_user_id = auth.uid());
create policy "orders_update_own" on orders for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
create policy "orders_delete_own" on orders for delete using (owner_user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- order_items(透過 order_id 往上查 orders.owner_user_id)
-- ----------------------------------------------------------------------------
create policy "order_items_select_own" on order_items for select using (
  exists (select 1 from orders o where o.id = order_items.order_id and o.owner_user_id = auth.uid())
);
create policy "order_items_insert_own" on order_items for insert with check (
  exists (select 1 from orders o where o.id = order_items.order_id and o.owner_user_id = auth.uid())
);
create policy "order_items_update_own" on order_items for update using (
  exists (select 1 from orders o where o.id = order_items.order_id and o.owner_user_id = auth.uid())
) with check (
  exists (select 1 from orders o where o.id = order_items.order_id and o.owner_user_id = auth.uid())
);
create policy "order_items_delete_own" on order_items for delete using (
  exists (select 1 from orders o where o.id = order_items.order_id and o.owner_user_id = auth.uid())
);
