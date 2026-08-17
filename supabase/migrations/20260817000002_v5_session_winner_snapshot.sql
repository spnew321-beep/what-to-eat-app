-- ============================================================================
-- 這餐吃什麼 App — decision_sessions 贏家文字快照 (v6)
-- ============================================================================
-- winner_restaurant_id 只在贏家是「真的收藏餐廳」時才有值——本場次臨時新增
-- 的候選(adhoc,只有 adhoc_name/adhoc_category,沒有對應的 restaurants 列)
-- 贏了以後完全沒地方查得到名字。owner 端不會壞,因為 finishCollabWithWinner()
-- 是從本機已經有的候選物件直接讀 name/category,不用重查;但訪客端的
-- guest-session state 動作只能靠資料庫查,查不到就只能顯示「已結束」。
--
-- 補兩個文字快照欄位,不管贏家是不是真餐廳都一定會寫入,比照
-- decision_history.restaurant_name / session_pool.adhoc_name 的做法。
-- winner_restaurant_id 繼續保留,給真餐廳的情況額外查價位用。
-- ============================================================================

alter table decision_sessions add column winner_name text;
alter table decision_sessions add column winner_category text;
