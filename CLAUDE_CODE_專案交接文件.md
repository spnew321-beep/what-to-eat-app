# 這餐吃什麼 — Claude Code 專案交接文件 v4.2

> 這份文件取代先前版本。v2 新增了完整的「資料生命週期審查」(見第 8 節)。v3 一度把「成員標籤(people)」整個概念拿掉、併入「自訂標籤(tags)」——**這個決定在 v4 被推翻**,復原成「成員」跟「自訂標籤」兩套獨立系統。**v4.2 再進一步釐清兩者的定位分工,拿掉了兩者之間唯一剩下的連結:**
>
> - **成員(`people`,人物標籤)**:結構化資料,綁定帳號(`owner_user_id`),有 `name`/`color`/`prefs` 欄位,可以被加入多個 `groups`(透過 `group_members`)。**用途是「發起決策時要邀請/通知誰」,跟餐廳完全沒有關聯**——不貼餐廳、不能標記「誰喜歡這間店」。群組的角色是「這群人一起決定要吃什麼」的邀請名單,未來(Tier 2+)接上真帳號後,發起協作場次可以直接通知群組裡的人。
> - **自訂標籤(`custom_tags`)**:完全自由的文字,存在 `restaurants.custom_tags`(`text[]` 陣列)。**「這間是誰喜歡的」這種備註,現在統一用自訂標籤記錄**(例如打「哥哥最愛」),不再有結構化的餐廳↔成員關聯。系統不解析內容,`restaurant_tags` 這張表整個拿掉,不需要建。
>
> 換句話說:v4 解決的是「成員該不該是結構化資料」(該),v4.2 解決的是「成員該不該連結到餐廳」(不該——那是自訂標籤的工作,成員只負責「這次決策要通知誰」)。詳見第 2、5 節。這份文件本身已經是討論完的定案結果,不是待確認的草案,Claude Code 可以直接照著做,不需要再回頭跟使用者確認這些規則。
>
> 搭配同一批交付檔案裡的 `meal-picker.html`——那是目前唯一能跑的原型,UI 邏輯、互動細節都在裡面,已經套用 v4.2 的設計,建議直接讀那個檔案作為介面與互動邏輯的參考起點,這份文件負責補完原型沒有、也不可能有的部分(資料庫、帳號、排程、多人同步、真通知)。

---

## 0. 給接手者的第一步建議

1. 先讀 `meal-picker.html`,理解目前所有畫面與互動。這個原型是 zero-dependency 的單一 HTML 檔(因為聊天 Artifact 環境會擋外部資源),**這個限制在 Claude Code 環境不存在,可以放心用 React/正式套件重建**。
2. 原型有個已知問題:`window.storage`(Artifact 儲存 API)在使用者的環境裡持續回報寫入失敗。這不是程式邏輯錯誤,換到 Supabase 之後這個問題自然消失,不需要在原型裡除錯。
3. **本文件第 8 節的「資料生命週期審查」是這次更新的重點**,裡面记录了十個原本的資料模型會卡死或報錯的地方,以及最後拍板的解法。寫程式前務必先讀那一節,因為它會直接影響 SQL schema 該怎麼寫。
4. 目標是「用原型的互動邏輯與視覺方向重建成正式產品」,不是複製原型。介面可以優化,但第 7 節的視覺語言是已經迭代多輪確認的方向,調整前建議先跟使用者確認。

---

## 1. 產品是什麼

一個幫「一群人(家庭/朋友/同事)」決定要吃什麼的 App。核心價值:
- 把個人的餐廳口袋名單集中管理,可以用自訂標籤標記「這是誰可能喜歡的店」之類的備註
- 決策時可以把特定自訂標籤的店快速拉進候選名單
- 用抽籤轉盤、系統建議、或多人協作場次,把「這餐吃什麼」這種每天都要吵的小決定變成好玩、公平、有效率的流程;協作場次可以選一個成員群組作為邀請/通知對象

---

## 2. 使用情境與角色(這次審查後已簡化)

### 情境 A:個人模式
一個帳號管理自己的一切——餐廳收藏、地圖、決策歷史,全部只屬於這個帳號,不分群組。

### 情境 B:協作模式(多人各自在自己裝置上操作)
發起人建立協作場次,設定截止時間(未來 7 天內任選,預設 1 小時後)與決策模式,分享邀請連結。受邀者用**訪客身份**(當場輸入名字)或**登入自己的帳號**加入,在截止時間前各自新增候選店家、對候選表態、按「完成」。截止時間一到,系統依候選狀況自動結算,結果同步給所有人。

### 關鍵原則(v4.2 定案):「成員」跟「自訂標籤」是兩套完全獨立的系統,而且互不連結

**成員(`people`,人物標籤)**——結構化資料,不是自由文字,但也不貼在餐廳上:
- 有自己的欄位:`id`、`owner_user_id`(綁定帳號)、`name`、`color`、`prefs`(飲食偏好)
- 可以被加入多個 `groups`(透過 `group_members`:`group_id` × `person_id`)
- **不貼餐廳**——沒有 `restaurant_tags` 這張表,成員跟 `restaurants` 完全沒有資料庫層級的關聯
- 這一套的用途是「群組發起決策時,要邀請/通知誰」,不是「這間店誰喜歡」。成員沒有身份狀態,不會被「代管」「認領」或「轉移」(v2 就定案,見第 8 節問題 2、8)——真人要用自己身份參與,直接自己申請帳號,成員標籤跟真實帳號是兩個永遠不相交的世界。飲食偏好(`prefs`)保留是因為對「決定要吃什麼」這件事本身還有參考價值(例如系統建議時可以參考群組成員的飲食偏好),跟餐廳無關

**自訂標籤(`custom_tags`)**——完全自由的文字,是餐廳唯一的「誰喜歡/什麼場合」備註管道:
- 存在 `restaurants.custom_tags`(`text[]` 陣列),沒有自己的表,不能被重複使用/共用,每間餐廳各自維護(前端可以把所有餐廳目前用過的自訂標籤字串收集起來做篩選/快速加入候選,但這是應用層的文字比對,不是資料庫關聯)
- 使用者可以輸入任何文字,包括人名、類型、心情、場合等等,系統不解析、不限制內容——想記錄「哥哥最愛」就直接打這幾個字當自訂標籤
- 不參照 `people` 表,不能拿來組群組,純粹是餐廳自己的分類備註

這兩套系統**不要互相取代、合併或建立關聯**——v3 曾經把兩者併成一套「自訂標籤」(拿掉了成員的結構化意義);v4 復原成兩套獨立系統,但當時還留著 `restaurant_tags` 讓成員可以貼餐廳;v4.2 進一步認清「這間店誰喜歡」根本不需要結構化關聯,自訂標籤自由文字就夠用,於是把 `restaurant_tags` 也拿掉了,成員徹底變成「跟餐廳無關、只跟決策通知有關」的資料。

**協作場次裡真正會出現、會按✅、會表態的參與者,一律是透過邀請連結真的加入的人**(訪客或登入帳號),跟「成員」是兩個完全獨立的概念。「選群組」是設定這次決策的邀請/通知對象(Tier 2+ 接上真帳號後可以真的推播通知),不會自動帶入候選店家——候選店家要嘛手動瀏覽收藏挑,要嘛用自訂標籤快速篩選,兩者不再是同一套機制。

---

## 3. 現有原型狀況(對照 meal-picker.html)

> **狀態更新(v4)**:`補充-UIUX優化定案.md` 訂的三批優化(編輯功能、協作場次畫面重構、一致性修正)、`補充-食物類型擴充定案.md` 的自訂類型,都已經做進 `meal-picker.html` 原型裡了。**成員(people)跟自訂標籤(custom_tags)已復原成兩套獨立系統**,不是待辦。下面的清單是**目前原型的實際狀態**。

已經做出來、邏輯完整、可互動的部分:
- 5 個分頁:🗺️ 地圖・⭐ 收藏・👥 群組・🎯 決策・☰ 更多
- 餐廳收藏(CRUD 含編輯,不再是只能新增/刪除;地圖定位板;類型下拉篩選、成員標籤下拉篩選、自訂標籤下拉篩選三組並存)
- 每間餐廳可維護:人物標籤(可複選既有成員標籤)、自訂標籤(自由文字,可自己輸入任意詞)、菜單存放區(常點餐點名稱+價格,可多筆增刪)、菜單照片(多張上傳,原型階段存在瀏覽器記憶體,重新整理會消失,正式版要接 Supabase Storage)
- 成員標籤管理:👥 群組分頁頂部有「所有成員標籤」區塊,可以直接新增/編輯/刪除,不需要先進某個群組才能管理;群組本身是兩層導覽(群組列表 → 點進去看成員標籤名單),「刪除這個群組」按鈕在頁面最下方
- ☰ 更多分頁新增「自訂標籤管理」「食物類型管理」兩個入口(見第 4 節「資訊架構調整」說明),自訂標籤/自訂類型終於有專屬地方可以改名、刪除、看使用數量,不用再靠「剛好在編輯某間餐廳」才摸得到
- 決策:個人抽籤、系統建議、協作場次(候選/表態合併在同一個子分頁、參與者另一個子分頁 → 轉盤結果)
- 決策結果可輸出成分享圖片(純 Canvas 繪製,是真功能)

明確是 placeholder、需要在 Claude Code 補上真功能的部分:
- 邀請連結、帳號系統、多裝置即時同步(目前是單機模擬)
- 隱私權政策/服務條款/帳號設定/意見回饋(各自有客製化的「尚未開放」提示文字,不是共用同一句)
- Google 地圖真實店家搜尋(API 金鑰不能放前端,暫不內建)
- 菜單照片的長期保存(要接 Supabase Storage)

**注意**:協作場次原本原型裡有「模擬新增訪客」「立即結算(測試用)」兩顆 demo 按鈕方便單機測試,`補充-UIUX優化定案.md` 定案拿掉了(正式版靠真實邀請連結 + 第 6 節的排程雙保險結算)。這代表**這個原型現在沒有辦法在瀏覽器裡端到端測試「有人加入協作場次」的流程**,只能測試候選/表態/倒數這幾塊,要等 Tier 2 接上真帳號與邀請連結才能完整測試。

---

## 4. 資訊架構詳細說明

### 🗺️ 地圖 / ⭐ 收藏
使用者「自己的」店家收藏,不分群組,支援新增與編輯(不是只能新增後就改不了)。收藏篩選同一列並排(不是上下分開的區塊):「★ 只看最愛」切換 chip、「食物類型」下拉(8 種預設 + 使用者自訂類型)、「自訂標籤」下拉(依 `restaurants.custom_tags` 裡實際出現過的文字篩選,沒有自訂標籤時這個下拉不顯示)。**沒有成員篩選**——成員跟餐廳沒有關聯,見第 2 節關鍵原則。每間餐廳的詳細內容包含:名稱、類型、價位、自訂標籤(自由輸入任意文字,可多個,想記「誰喜歡」就直接打人名當標籤)、菜單存放區(常點餐點+價格,可多筆增刪)、菜單照片(可多張上傳)、備註。

### 👥 群組
第一層是群組列表,點進去是第二層的成員標籤名單(群組 = 一組成員標籤的集合)。頁面頂部有獨立的「所有成員標籤」區塊,可以直接新增/編輯/刪除,不需要先進某個群組。群組詳細頁裡可新增成員標籤(名字/代表色/飲食偏好)、可從既有的成員標籤庫裡加入到這個群組、可移出此群組或完全刪除(完全刪除只影響群組歸屬,**不影響任何餐廳**,因為成員本來就不貼餐廳),「刪除這個群組」按鈕在頁面最下方。這個分頁的定位是「決策要邀請誰」,不是「餐廳分類」。

### 🎯 決策
三個子模式:
1. **抽籤**:候選名單 + 轉盤(個人用,快速)。候選名單上方有「快速加入」chip,是依帳號目前用過的**自訂標籤**產生的(例如「🏷️ 常去(3)」),點一下把該標籤的所有餐廳一次拉進候選,取代原本(v4.2 之前)以成員為單位的快速加入
2. **系統建議**:類型篩選 + 一鍵建議,自動排除最近吃過的類型
3. **協作場次**:見第 6 節詳細流程。選群組是設定這次的邀請/通知對象,不會自動帶入候選店家;候選店家一樣是用自訂標籤 chip 快速加入,或手動瀏覽/新增

### ☰ 更多
頂部是兩個管理入口(這次資訊架構調整新增的,見下方說明):「🏷️ 自訂標籤管理」「🍜 食物類型管理」。下方是 App 層級資訊:隱私權政策、服務條款、帳號設定、關於、意見回饋。

### 資訊架構調整(v4.1:統一自訂項目的管理入口 + 用詞消歧)
在這之前,「自訂標籤」跟「自訂類型」只能在編輯某間餐廳時順手改,沒有專屬入口,使用者要整理/改錯字得先找一間有用到的餐廳才行。這次調整:
- **☰ 更多分頁新增「自訂標籤管理」「食物類型管理」兩個畫面**,列出帳號目前用過的所有自訂標籤/自訂類型,可以 ✎ 改名(連動更新所有用到的餐廳)、🗑 刪除(標籤直接從餐廳陣列移除;類型連動變成「未分類」)。自訂類型管理畫面右上角有「＋」可以新增;自訂標籤沒有「＋」,因為它本來就沒有獨立的表,只能在餐廳表單裡打字產生,管理畫面只負責整理既有的
- 管理畫面沿用「所有成員標籤」畫面已經在用的列表樣式(整列 + ✎/🗑),三種自訂項目的管理互動統一,不用每個地方學一套新的
- **UI 文案裡「成員」一律改成「成員標籤」**(所有成員標籤、新增成員標籤、編輯成員標籤……),跟協作場次的「參與者」(真人)明確區分開來,避免「成員」一詞同時代表「你自己編的假標籤」跟「真的加入場次的人」造成混淆。人數統計維持用「X 人」,不受影響

---

## 5. 資料模型(已套用第 8 節審查結果 + v4:成員/自訂標籤兩套獨立系統)

### 核心原則
- 餐廳收藏、地圖、決策歷史都是「帳號個人的」,不分群組
- **成員(`people`)跟自訂標籤(`custom_tags`)是兩套獨立系統,不要合併、不要建立關聯**:成員是結構化資料(綁帳號、有 `prefs`、可以入群組),用途是「決策要通知/邀請誰」;自訂標籤是完全自由的文字(只存在餐廳自己身上,不能重複使用、不能組群組),用途是「這間店的備註,包括誰喜歡」
- 成員沒有身份狀態,不會被「代管」「認領」或「轉移」(v2 定案,見第 8 節問題 2、8)
- **成員不貼餐廳**——沒有 restaurant_tags 這張表,想記錄「誰喜歡這間店」一律用 `restaurants.custom_tags` 打文字(例如「哥哥最愛」)
- 群組是「一組成員的集合」,方便快速決定這次協作場次要通知/邀請誰;不會拿群組去拉候選店家,候選店家改用自訂標籤快速加入
- 協作場次的參與者(真人)跟成員是兩個獨立的世界,場次建立時參與者名單已是快照,不會因為群組異動而受影響
- 每間餐廳除了基本資料,還有一份可多筆的菜單(常點餐點+價格)跟菜單照片

### 實體關聯(概念層級)
```
users(帳號)
  └─ 擁有 people(成員)、groups(群組)、restaurants(收藏)、decision_history(歷史)、decision_sessions(場次)、custom_categories(自訂食物類型)

custom_categories(帳號自己新增的食物類型,跟前端寫死的 8 種預設類型並存)
  └─ 不對 restaurants.category 設外鍵,靠文字比對關聯,改名/刪除時應用層批次更新

people(帳號自己的成員標籤,結構化資料,綁帳號,沒有身份狀態、不會被認領或轉移)
  └─ 可以屬於多個 groups;**不連結 restaurants**,只用於決策通知/邀請對象

groups(群組 = 成員的集合,用途是「這次決策要通知誰」)
  └─ group_members:group_id × person_id

restaurants(餐廳,屬於某個 user)
  ├─ custom_tags:text[] 欄位,完全自由的文字標籤,唯一的「誰喜歡/什麼場合」備註管道,跟 people 無關、不參照 people 表
  ├─ restaurant_menu_items:餐廳的常點餐點清單(一對多,文字+價格)
  └─ restaurant_photos:餐廳的菜單照片(一對多,跟上面文字清單疊加,不是取代)

decision_history(決策歷史,屬於某個 user,不分群組)

decision_sessions(協作場次)
  ├─ 建立時快照參與者,不即時查詢群組
  ├─ deadline_at:絕對截止時間
  ├─ status:collecting | waiting | done | no_result
  ├─ session_participants:真人(訪客或登入帳號),不是 people 成員標籤
  ├─ session_pool:候選店家,可以是某人收藏裡的店,也可以是場次專用臨時候選
  └─ session_votes:表態篩選模式專用
```

### 正式的 Supabase (Postgres) SQL

```sql
-- 成員(人物標籤):結構化資料,綁帳號,沒有身份狀態,不會被認領或轉移
create table people (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  color text not null,
  prefs text[] default '{}',
  created_at timestamptz default now()
);

create table groups (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references auth.users(id) on delete cascade not null,
  name text not null,
  created_at timestamptz default now()
);

create table group_members (
  group_id uuid references groups(id) on delete cascade,
  person_id uuid references people(id) on delete cascade,
  primary key (group_id, person_id)
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
  custom_tags text[] default '{}',  -- 完全自由的文字標籤,不參照 people 表,系統不解析內容
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
  group_id uuid references groups(id) on delete set null, -- 群組刪除不影響場次,只是失去追溯資訊
  decision_mode text check (decision_mode in ('random','vote_first')) not null,
  deadline_at timestamptz not null, -- 絕對截止時間,建立時設定,限未來7天內,預設建立時間+1小時
  invite_token text unique,
  status text default 'collecting' check (status in ('collecting','waiting','done','no_result')),
  winner_restaurant_id uuid references restaurants(id),
  cleanup_after timestamptz, -- = deadline_at + 1小時緩衝,排程依此清除整個場次
  created_at timestamptz default now()
);

-- 真人參與者,注意:不參照 people 表,成員跟真人是兩個世界
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
```

啟用 Row Level Security,`owner_user_id = auth.uid()` 是基本擁有者規則(`people` 也適用);`group_members` 沒有自己的 `owner_user_id`,透過關聯回 `groups` 判斷擁有者。`restaurant_menu_items`/`restaurant_photos` 沒有自己的 `owner_user_id`,透過 `restaurant_id` 關聯回 `restaurants` 判斷擁有者。菜單照片建議直接用 Supabase Storage 存檔案本體,`storage_path` 只存路徑。`restaurants.category` 維持純文字欄位、不對 `custom_categories` 設外鍵(預設類型本來就不在資料庫裡,兩種類型都用文字比對),改名/刪除自訂類型時由應用層邏輯批次更新符合的 `restaurants.category` 文字值(改名→新名稱;刪除→「未分類」),做法比照 `decision_history.restaurant_name` 的文字備份模式。`decision_sessions`/`session_participants`/`session_pool`/`session_votes` 這幾張表因為訪客沒有帳號,需要另外設計「憑 `invite_token` 換取有限寫入權限」的規則(建議透過一個 Edge Function 驗證 token 沒過期,再用 service role 代為寫入,不要讓訪客直接拿到能繞過 RLS 的權限)。

---

## 6. 協作場次完整流程(已依審查結果更新)

```
1. Owner 進「決策」→「協作場次」
2. 選擇找誰一起決定:選一個已存的群組(設定這次決策的邀請/通知對象,Tier 2+ 接上真帳號後可以真的推播通知) 或「自由邀請」(不指定群組,空白開始)
   —— 這個選擇**不影響候選店家怎麼湊**(候選改用自訂標籤快速加入或手動瀏覽),也不影響誰會真的參與投票
3. 設定決策模式(直接轉盤 / 先表態篩選)—— 一開始選定,場次期間不能中途更改
4. 設定截止時間:絕對時間點(幾月幾號幾點幾分),可選未來 7 天內,預設建立時間 + 1 小時
5. 產生邀請連結,有效期 = 場次截止時間(不是固定 1 小時)
6. 受邀者訪客身份的暫存資料,保留時間同樣跟著場次截止時間走,不是固定 1 小時
   —— 這樣不管場次設多久,參與者的身份跟他做過的動作都撐得到截止那一刻
7. 截止時間之前,所有人(包括訪客)都可以:
   - 從自己收藏挑店家加入候選,或
   - 臨時新增一間「這場次專用」的候選店家(不掛在任何人收藏底下,場次結束就消失)
   - 【表態篩選模式】對候選逐一表示可接受/不可接受
   - 按「我完成了」✅(非必要動作,主要是給對方看個心安,真正的結算看下一步)
8. 截止時間一到(由伺服器排程觸發,見下方),依候選店家數量結算:
   - 候選 ≥ 2 間:表態篩選模式先篩掉有人不可接受的(全部被否決則退回用完整候選名單),
     剩下的進轉盤;直接轉盤模式全部候選直接進轉盤
   - 候選剛好 1 間:不用轉盤,直接是那間,status = done
   - 候選 0 間:status = no_result,場次視為沒有結果
9. 場次結束(done 或 no_result)後保留 1 小時緩衝(cleanup_after),
   讓大家能看到結果、輸出分享圖片
10. 緩衝時間過後,由排程任務整個刪除場次(參與者/候選/表態全部隨 CASCADE 一併清除)
11. 【順手功能】結果畫面提供「把這次的參與者存成新群組」按鈕
    —— 把 session_participants 的名字轉存成新的 people 成員 + 新 group,方便下次直接選group重來一次
```

### 逾時觸發機制(A+B 雙保險,已定案)
- **A(排程保底)**:Supabase Scheduled Function,每 1 分鐘掃描一次 `decision_sessions`,找出 `status in ('collecting','waiting') and deadline_at <= now()` 的場次,依上方第 8 步結算;同時掃描 `status in ('done','no_result') and cleanup_after <= now()` 的場次執行刪除。就算所有人都沒開著頁面,場次也會準時結算跟清除,只有最多 1 分鐘的誤差。
- **B(前端主動檢查)**:任何人打開場次畫面時,前端比對目前時間是否已超過 `deadline_at`,超過的話呼叫跟排程一樣的結算邏輯,讓「剛好有人在看」的情況能更即時反應,不用等排程的下一次執行。

### 群組刪除的處理
場次建立當下,參與者名單已經是快照(存進 `session_participants`,不是即時查詢群組),所以群組被刪除完全不影響進行中的場次,場次照樣跑到自然結束。`decision_sessions.group_id` 設為 `ON DELETE SET NULL`,群組沒了場次只是失去追溯資訊,不會被連帶刪除或報錯。

---

## 7. 視覺設計語言(已定案的方向,調整前建議先跟使用者確認)

- **整體氛圍**:深色背景(`#15171C` → `#1B1E24` 漸層),像深夜的餐飲市集
- **籤詩/收據意象**:抽籤結果用撕邊票券卡片呈現(`clip-path` 鋸齒邊),紙張色 `#F3ECDD`、墨色文字 `#232019`
- **色票**:琥珀 `#C99A3D`(強調色/轉盤)、印章紅 `#B23A2E`(主要 CTA)、灰綠 `#5C7A6B`(次要強調)、轉盤色票循環 `#C99A3D #5C7A6B #B23A2E #4E6E81 #7A5C74 #9C5B3E #3E7C74 #7C7C4A`
- **字體**:系統字體優先,數字/代碼類用等寬字體,刻意不用外部字體服務
- **元件語言**:
  - Chip/Filter 一律自動換行,不做橫向滑動(手機易用性明確要求)
  - 候選店家清單統一用「整列可點、右側打勾方塊」的深色列表樣式,不是白底 checkbox
  - 設定型清單(如「更多」分頁)用無外框、整組合併的卡片 + 列間細分隔線,不是每列各自邊框
  - 轉盤用 Canvas 繪製 + CSS `transform: rotate()` 動畫,指標固定在正上方,滑到目標角度是預先計算好的,不是純視覺隨機

---

## 8. 資料生命週期審查(這次更新的核心,十題定案)

原型階段用假資料看不出來的問題,接上真資料庫後會直接卡死或報錯,逐一審查定案如下:

| # | 問題 | 定案結果 |
|---|---|---|
| 1 | 逾時判斷只靠前端瀏覽器倒數,發起人關掉分頁就永遠不會觸發 | 伺服器排程(每分鐘掃描)當保底 + 前端有人打開頁面時主動檢查,雙保險(詳見第 6 節) |
| 2 | 帳號刪除,底下資料的連帶處理沒定義 | 每個帳號只刪自己直接擁有的東西(自己的收藏/群組/標籤/歷史);貼在別人餐廳上的標籤本來就是別人帳號的資料,不受影響 |
| 3 | 候選名單湊不到 2 間時,原本的「進等待畫面才開始倒數」邏輯永遠不會啟動逾時 | 改成「絕對截止時間」,從場次建立那刻就固定,不管候選湊了沒;決策模式建立時選定;候選/表態在截止前隨時可做;時間到依候選數量結算(≥2 轉盤、剛好 1 間免轉、0 間 = no_result) |
| 4 | 場次沒有「過期/沒結果」的終點狀態,會議累積一堆「永遠進行中」的死場次 | 新增 `no_result` 狀態;所有結束的場次保留 1 小時緩衝(方便看結果、分享圖片)才由排程清除 |
| 5 | 訪客資料/邀請連結固定 1 小時,但場次可能跑更久,訪客資料會在場次結束前就過期消失 | 兩者都改成跟著場次的 `deadline_at` 走,不再是獨立固定 1 小時(這題其實是問題 3 改成絕對截止時間後自動解決的) |
| 6 | 群組被刪除時,底下進行中的協作場次會沒有依歸(外鍵沒設刪除規則會報錯) | 場次建立時參與者名單已快照,不即時查詢群組;`group_id` 設為 `ON DELETE SET NULL`,群組刪除不影響場次 |
| 7 | 刪除餐廳後,決策歷史裡的 `restaurantId` 會指向不存在的資料 | `ON DELETE SET NULL`,只留店名/類型文字備份,歷史紀錄畫面不會壞,但斷開跳轉關聯(反正目前沒有這個功能) |
| 8 | 「代管成員被本人認領」這個機制,會衍生搶認領衝突、資料合併規則等一堆複雜情況 | **整個機制拿掉**——「人」永遠只是帳號自己的標籤,沒有身份狀態,不會被認領或轉移。真人要用自己身份參與,直接自己申請帳號,標籤跟真實帳號是兩個永遠不相交的世界。這個決定連帶簡化了問題 2 的規則 |
| 9 | 自由邀請場次結束後,參與者名單直接消失,下次想約同一群人要重新一個個邀請 | 結果畫面加「把這次的參與者存成新群組」按鈕(一鍵把 `session_participants` 轉存成 `people` 標籤 + 新 `group`) |
| 10 | 地圖用相對座標(x/y%),不是真經緯度,接資料庫後這批資料沒有實際用途 | 資料庫直接規劃 `lat`/`lng` 真經緯度欄位,原型的相對座標不搬過去,欄位一開始留空,一次到位不用之後再改表結構 |

**這次審查過程中額外發現、順手一併定案的細節:**
- 候選名單除了能從既有收藏挑店,協作場次裡任何參與者(包含訪客)都可以臨時新增一間「這場次專用」的候選店家,不掛在任何人收藏底下,場次結束就消失(對應 `session_pool` 表的 `adhoc_name`/`adhoc_category` 欄位)
- `session_participants` 刻意不參照 `people` 表——成員(備忘用途)跟真人參與者(真的會按✅、會表態)是兩個獨立的資料世界,不要混在一起,這是這次審查最重要的架構簡化

**v3→v4 修正紀錄**:v3 曾經把 `people` 表整個併入一套統一的 `tags` 表(拿掉 `prefs` 欄位,`group_members`/`restaurant_tags` 改參照 `tag_id`),這是誤解了「成員」跟「自訂標籤」的定位,v4 已經復原成本節寫的兩套獨立系統(`people` 結構化 + `restaurants.custom_tags` 自由文字)。第 8 節問題 2、8 的定案結論(不設代管/認領機制、帳號各刪各的)不受這次復原影響,一直都成立。

**v4→v4.2 修正紀錄**:v4 復原兩套系統後,`people` 短暫還留著 `restaurant_tags` 這條連結,讓成員可以貼餐廳(這其實是 v2 原本的設計,一直沒被質疑過)。討論到協作場次希望能對群組真人發送通知時,才發現「成員貼餐廳」跟「成員是決策通知對象」根本是兩個不相關的用途硬塞在同一張表上。v4.2 拿掉 `restaurant_tags`,成員徹底只剩「決策通知對象」這一個用途;「這間店誰喜歡」全部改記在 `restaurants.custom_tags` 裡。

---

## 9. 分階段路線圖

| 階段 | 內容 | 狀態 |
|---|---|---|
| Tier 0 | 單人模式,基本五分頁功能 | ✅ 原型已完成 |
| Tier 1 | 協作場次 UI 全部蓋完,未串接後端功能先做空按鈕 | ✅ 原型已完成 |
| Tier 1.5 | UI/UX 檢視與優化(編輯功能補完、協作場次畫面重構、一致性修正,見 `補充-UIUX優化定案.md`) | ✅ 原型已完成 |
| **Tier 2(交給 Claude Code)** | **接上 Supabase:真帳號(Auth)、真資料庫(第 5 節 schema)、排程結算(第 6 節)、Realtime 同步、邀請連結真的能用** | 🔜 下一步 |
| Tier 3 | 拍照記錄三餐、AI 估算熱量、依歷史自動排除重複類型 | 未來 |
| Tier 4 | 正式部署(Vercel/Netlify),取得正式網址 | 未來 |

**為什麼選 Supabase**:關聯式資料庫對應「群組→成員→餐廳→決策場次」的關聯結構;內建 Auth 解決帳號;內建 Realtime 解決協作場次的即時✅同步;Scheduled Functions/`pg_cron` 解決第 8 節的逾時排程需求,不用另外架服務。免費層額度(500MB DB、5 萬月活躍用戶、200 個並發 Realtime 連線)對這個規模綽綽有餘,唯一要注意免費專案連續 7 天沒存取會自動暫停(資料還在,手動喚醒即可)。

---

## 10. 交付檔案清單

- `meal-picker.html` — 目前唯一可執行的原型,UI/互動邏輯的參考起點,已套用 UI/UX 優化定案
- `CLAUDE_CODE_專案交接文件.md`(本文件)— 資料庫、帳號、排程、路線圖、第 8 節生命週期審查,以及第 11 節 UI/UX 優化指引(已執行完畢)
- `補充-UIUX優化定案.md` — UI/UX 檢視問題清單與定案結果,已全部做進原型
- `補充-食物類型擴充定案.md` — 食物類型可自訂擴充的定案結果

---

## 11. UI/UX 優化指引(✅ 已執行完畢,見 `補充-UIUX優化定案.md`)

> 這節原本是「下一步要做的事」,現在已經執行完了。UX 檢視的問題清單跟最終定案結果記錄在同一批交付檔案裡的 `補充-UIUX優化定案.md`,三批改動(編輯功能、協作場次畫面重構、一致性修正)都已經做進 `meal-picker.html` 裡並實測過。下面保留原始的開場白紀錄,純粹是歷史脈絡,不是待辦。

目前第 8 節的資料生命週期問題都已定案,`meal-picker.html` 的功能也都做到位了(五分頁、收藏標籤、群組、三種決策模式、協作場次含臨時候選與存成群組)。**下一步不是加新功能,是針對「好不好用」做一次專業檢視跟優化**。

### 可以直接複製貼給 Claude Code 的開場白

```
目前功能都做完了,現在想針對整個 App 做一次使用者體驗的檢視跟優化,不是加新功能。

請你扮演一個資深 UI/UX 設計師,重新審視整個 App:
1. 先列出你觀察到的具體問題(操作流程太長、資訊層次不清楚、按鈕位置不直覺、
   文字太多不好掃視、視覺回饋不夠明確等等),每個問題講清楚在哪個畫面、
   具體是什麼狀況
2. 針對每個問題提出改善建議
3. 先不要動手改,列完問題清單跟建議給我看,我確認過優先順序之後再開始做

第 7 節已經記錄了目前的視覺語言(色票、字體、票券轉盤的風格方向),這次優化
請保留這個大方向,調整的是「好不好用」,不是「整個重新設計」。

另外特別請你注意這三個地方:

1. 協作場次的「進行中」畫面現在資訊量很大——倒數時間、候選店家、臨時新增、
   表態、參與者名單全部疊在同一頁,滑很長,可能需要用分段標籤或摺疊區塊讓
   畫面不要一次塞這麼多

2. 新增餐廳/新增標籤的表單步驟偏多——類型、價位、標籤、備註一次全部要填,
   可以考慮哪些是「填了更好但可以先跳過」,降低第一次使用的門檻

3. 各個「尚未開放」的空按鈕現在都是同一種灰色提示,之後功能陸續補上時,要
   確保使用者清楚知道「這個按了會發生什麼」,而不是每次都跳一樣的提示
```

### 使用建議
先讓 Claude Code 產出問題清單跟建議(不動手改),看過之後**自己決定優先順序**,再請它動手——不需要一次全部改完,可以先挑你最有感的一兩項處理,看效果再決定要不要繼續。
