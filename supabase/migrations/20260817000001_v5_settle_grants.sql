-- ============================================================================
-- 這餐吃什麼 App — service_role 補 decision_history 權限 (v6)
-- ============================================================================
-- settle-sessions Edge Function 排程結算場次時,需要幫 owner 寫一筆
-- decision_history。跟 20260817000000_v5_service_role_grants.sql 同一個坑,
-- 這張表當時漏了,這裡補上。
-- ============================================================================

grant select, insert on decision_history to service_role;
