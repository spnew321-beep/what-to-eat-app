-- ============================================================================
-- 這餐吃什麼 App — Tier 2 Schema Migration (v5)
-- ============================================================================
-- 來源：CLAUDE_CODE_專案交接文件.md 第 5 節（v5 版本，2026-08-16）。
--
-- 這份檔案整份取代原本的 20260812000000_initial_schema.sql（那份是 pre-v5
-- 的舊 schema，還在用 people/restaurant_tags，沒有 v5 的
-- group_members.linked_user_id、也沒有 orders/order_items，跟現在的資料
-- 模型完全對不上，故直接整份重寫，不保留舊檔內容）。
--
-- 核心變更（詳見交接文件第 2、5 節）：
--   - people 表拿掉，改成 groups + group_members（member 有 nullable 的
--     linked_user_id，null = 未連結真帳號的備忘成員，有值 = 已連結，
--     協作場次會自動邀請）
--   - 沒有 restaurant_tags：「誰喜歡這間店」統一記在 restaurants.custom_tags
--   - decision_sessions 恢復 group_id 欄位（ON DELETE SET NULL）
--   - 新增 orders / order_items（點餐功能）
--
-- 重要：本檔案「刻意不包含」任何 RLS 的 CREATE POLICY 語句，只開關
-- ENABLE ROW LEVEL SECURITY。Policy 的具體邏輯（尤其是 decision_sessions
-- 系列表、group_members.linked_user_id 的寫入權限）需要另外設計，
-- 詳見交接文件第 5 節本文說明。啟用 RLS 但沒有任何 policy 時，依 Postgres
-- 行為，非 table owner/superuser 的存取會全部被擋下（等同預設拒絕），
-- 在補上 policy 之前這些表事實上無法被一般使用者讀寫。
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 群組:帳號自己建立的群組,例如「家人」「公司同事」
-- ----------------------------------------------------------------------------
create table groups (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  created_at timestamptz default now()
);

-- 群組成員:結構化資料,linked_user_id 可為 null——
-- null = 未連結真帳號(純飲食偏好備忘),有值 = 已連結,協作場次會自動邀請
-- 不貼餐廳(沒有 restaurant_tags),「誰喜歡這間店」統一記在 restaurants.custom_tags
create table group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references groups(id) on delete cascade not null,
  name text not null,
  color text not null,
  prefs text[] default '{}',
  linked_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz default now()
);

create table restaurants (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  category text not null,
  price smallint check (price between 1 and 3),
  note text,
  lat double precision,  -- 真經緯度,原型的相對座標(x/y%)不搬過來,一開始留空
  lng double precision,
  favorite boolean default false,
  custom_tags text[] default '{}',  -- 完全自由的文字標籤,不參照 group_members,系統不解析內容
  created_at timestamptz default now()
);

-- 菜單存放區:常點的餐點及價格,一間餐廳可有多筆
create table restaurant_menu_items (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid references restaurants(id) on delete cascade not null,
  name text not null,
  price numeric(10,2),
  sort_order integer default 0,
  created_at timestamptz default now()
);

-- 菜單照片:跟上面的文字清單是疊加關係,不是取代,一間餐廳可上傳多張
create table restaurant_photos (
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid references restaurants(id) on delete cascade not null,
  storage_path text not null,  -- Supabase Storage 路徑,不要把照片路徑塞進 restaurants 表
  created_at timestamptz default now()
);

-- 使用者自訂的食物類型,跟前端寫死的 8 種預設類型並存;預設類型不進資料庫
create table custom_categories (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  created_at timestamptz default now(),
  unique (owner_user_id, name)
);

-- 使用者自訂的飲食偏好,跟前端寫死的 7 種預設偏好並存;預設偏好不進資料庫
create table custom_prefs (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  created_at timestamptz default now(),
  unique (owner_user_id, name)
);

create table decision_history (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  restaurant_id uuid references restaurants(id) on delete set null, -- 餐廳被刪除時清空,只留下面文字備份
  restaurant_name text not null,
  category text not null,
  decided_at timestamptz default now()
);

create table decision_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  group_id uuid references groups(id) on delete set null, -- 選群組建立時記錄選了哪個群組,群組刪除不影響已建立的場次
  decision_mode text check (decision_mode in ('random','vote_first')) not null,
  deadline_at timestamptz not null, -- 絕對截止時間,建立時設定,限未來7天內,預設建立時間+1小時
  invite_token text unique,
  status text default 'collecting' check (status in ('collecting','waiting','done','no_result')),
  winner_restaurant_id uuid references restaurants(id),
  cleanup_after timestamptz, -- = deadline_at + 1小時緩衝,排程依此清除整個場次
  created_at timestamptz default now()
);

-- 真人參與者。已連結的群組成員自動加入時,user_id = 該 group_member 的 linked_user_id;
-- 訪客或其他登入帳號手動加入時比照原本邏輯。這張表不參照 group_members,是獨立快照
create table session_participants (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references decision_sessions(id) on delete cascade,
  user_id uuid references auth.users(id), -- 用登入帳號加入才有值
  display_name text not null, -- 訪客輸入的名字,或登入者的暱稱
  is_guest boolean default true,
  ready boolean default false,
  joined_at timestamptz default now()
);

-- 候選店家:可能來自某人收藏,也可能是場次專用臨時新增
create table session_pool (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references decision_sessions(id) on delete cascade,
  restaurant_id uuid references restaurants(id) on delete cascade,
  adhoc_name text,       -- 場次專用臨時候選才有值(不掛在任何人收藏底下)
  adhoc_category text,
  added_by_participant_id uuid references session_participants(id),
  created_at timestamptz default now(),
  check (restaurant_id is not null or adhoc_name is not null)
);

create table session_votes (
  pool_item_id uuid references session_pool(id) on delete cascade,
  voter_participant_id uuid references session_participants(id) on delete cascade,
  accepted boolean not null,
  primary key (pool_item_id, voter_participant_id)
);

-- 點餐:決策之後開的收單清單
create table orders (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  restaurant_id uuid references restaurants(id) on delete set null, -- 餐廳被刪除時清空,只留下面文字備份
  restaurant_name text,
  category text,
  mode text check (mode in ('manual','group','link')) not null,
  group_id uuid references groups(id) on delete set null, -- group 模式才有值
  created_at timestamptz default now()
);

-- 點餐項目:姓名/品項/價格,member_id 可為 null(自由輸入的人沒有對應的群組成員)
-- ——manual 模式是主揪代填,group/link 模式(Tier 2+ 才會真的多裝置各自輸入)填的人也不一定有帳號
create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade not null,
  member_id uuid references group_members(id) on delete set null, -- 從群組匯入時記錄來源成員,用來去重、避免改名後重複匯入
  person_name text not null,
  item text,
  price numeric(10,2),
  created_at timestamptz default now()
);

-- ----------------------------------------------------------------------------
-- 啟用 Row Level Security(只開關,不含 CREATE POLICY——見檔頭說明)
-- ----------------------------------------------------------------------------
alter table groups enable row level security;
alter table group_members enable row level security;
alter table restaurants enable row level security;
alter table restaurant_menu_items enable row level security;
alter table restaurant_photos enable row level security;
alter table custom_categories enable row level security;
alter table custom_prefs enable row level security;
alter table decision_history enable row level security;
alter table decision_sessions enable row level security;
alter table session_participants enable row level security;
alter table session_pool enable row level security;
alter table session_votes enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
