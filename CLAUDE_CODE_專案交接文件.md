# 這餐吃什麼 — Claude Code 專案交接文件 v5

> 這份文件取代先前版本。v2 新增了完整的「資料生命週期審查」(見第 8 節)。v3 一度把「成員標籤(people)」整個概念拿掉、併入「自訂標籤(tags)」——**這個決定在 v4 被推翻**,復原成「成員」跟「自訂標籤」兩套獨立系統。v4.2 拿掉了成員與餐廳之間唯一的連結(`restaurant_tags`)。v4.3 把「群組」的假資料機制整個拿掉,改成「👥 群組」分頁全部鎖住、家人飲食偏好小抄搬去 ☰ 更多獨立存在。**v5 再翻一次案,把群組做成真的能用的功能**,但用一個新方式解決 v4.3 當時卡住的問題:
>
> - **群組(`groups`/`group_members`)重新做成真的功能**。群組底下的每個 member,除了名字/代表色/飲食偏好之外,多一個「已連結/未連結使用者帳號」的狀態欄位(`linked_user_id`)。**未連結**就是原本「家人偏好小抄」的樣子——沒有身份,純粹備忘;**已連結**代表這個 member 對應到一個真的帳號,協作場次建立時會被自動列入邀請。這樣「群組」不再是 v4.3 之前那種拿假資料硬湊的東西,而是「member 可能有身份、也可能還沒有」的誠實名單。目前原型裡沒有真帳號系統,所以 `linked_user_id` 永遠是 null,「連結」這個動作本身還是「尚未開放」的提示——但欄位跟 UI 已經照未來的樣子做出來了。
> - **原本獨立於群組之外的「家人偏好小抄」整個併入群組**。member 現在一定屬於某個群組,不再有「沒有群組」的家人;群組的 CRUD(建立/改名/刪除)跟 member 的 CRUD(新增/編輯/刪除)都是真的能操作的功能,不是佔位提示。
> - **協作場次的「選好友群組」解鎖了**:選一個群組後,已連結的成員自動加入參與者名單,未連結的成員不會自動加入,但一樣可以用邀請連結加入——這正是 v4.3 當時懸而未決的問題(沒帳號的人要怎麼被通知)的答案:不主動通知,但保留手動加入的路。
> - **新增「🧾 點餐」分頁**:決策結束、選定餐廳之後,可以開一筆點餐,讓大家各自輸入想點的東西(飲料店、便當店這種需要收單的場景),不用主揪一個一個問、一個一個記。目前多裝置各自輸入的部分(群組邀點餐/連結發點餐)還是「尚未開放」的畫面預覽,單機模式(自建成員清單)是真的能用的功能。
> - **⭐ 收藏併入 🗺️ 地圖 分頁**(分頁內左右切換,不是獨立的上層分頁),空出來的分頁位置給「點餐」,底部分頁列維持 5 個:地圖、群組、決策、點餐、更多。
> - **自訂標籤(`custom_tags`)完全不受影響**,還是完全自由的文字,存在 `restaurants.custom_tags`。
>
> 換句話說:v4 解決「成員該不該是結構化資料」(該);v4.2 解決「成員該不該連結到餐廳」(不該);v4.3 解決「沒有真帳號的『群組』該不該假裝存在」(不該,先誠實鎖住);**v5 解決「群組該用什麼方式變成真的」(用『member 有已連結/未連結兩種狀態』這個誠實的中間態,而不是等真帳號系統全部到位才能動)**。詳見第 2、5 節。這份文件本身已經是討論完的定案結果,不是待確認的草案,Claude Code 可以直接照著做,不需要再回頭跟使用者確認這些規則。
>
> 搭配同一批交付檔案裡的 `meal-picker.html`——那是目前唯一能跑的原型,UI 邏輯、互動細節都在裡面,已經套用 v5 的設計,建議直接讀那個檔案作為介面與互動邏輯的參考起點,這份文件負責補完原型沒有、也不可能有的部分(資料庫、帳號、排程、多人同步、真通知、真好友系統)。

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
- 用抽籤轉盤、系統建議、或多人協作場次,把「這餐吃什麼」這種每天都要吵的小決定變成好玩、公平、有效率的流程;協作場次可以選一個群組快速帶入已連結帳號的成員,也可以純用邀請連結自由邀請
- 決定好要吃哪間之後,可以開一筆點餐,讓大家各自輸入想點的東西,不用主揪一個一個問

---

## 2. 使用情境與角色

### 情境 A:個人模式
一個帳號管理自己的一切——餐廳收藏、地圖、決策歷史,全部只屬於這個帳號。

### 情境 B:協作模式(多人各自在自己裝置上操作)
發起人建立協作場次,設定截止時間(未來 7 天內任選,預設 1 小時後)與決策模式,選一個群組(已連結帳號的成員自動列入)或純用邀請連結自由邀請。受邀者用**訪客身份**(當場輸入名字)或**登入自己的帳號**加入,在截止時間前各自新增候選店家、對候選表態、按「完成」。截止時間一到,系統依候選狀況自動結算,結果同步給所有人。

### 關鍵原則(v5 定案):群組(含 member)、自訂標籤,兩套完全獨立、互不連結的系統

**群組與 member(`groups`/`group_members`)**——這次翻案的核心:
- `groups`:一個帳號可以建立多個群組(例如「家人」「公司同事」),每個群組屬於建立它的帳號
- `group_members`:每個群組底下的成員,有自己的欄位:`id`、`group_id`、`name`、`color`、`prefs`(飲食偏好)、`linked_user_id`(可為 null,references `auth.users`)
- **`linked_user_id` 是這次的關鍵欄位**:null = 未連結(現在的樣子,純粹備忘,沒有身份,不會被通知);有值 = 已連結真帳號,協作場次選這個群組時會自動列入邀請
- **不貼餐廳**(沒有 `restaurant_tags`)——「這間店誰喜歡」還是統一記在自訂標籤裡,群組/member 的職責只有「這群人是誰、飲食偏好是什麼、有沒有連結帳號」
- 目前原型沒有真帳號系統,所以 `linked_user_id` 恆為 null,「連結帳號」這個動作是 UI 上的「尚未開放」提示,但整套資料結構已經照未來的樣子做好,Tier 2 接上 Auth 之後,「連結」只是把某個 member 的 `linked_user_id` 設成對應的 `auth.users.id`,不需要改表結構

**自訂標籤(`custom_tags`)**——完全自由的文字,是餐廳唯一的「誰喜歡/什麼場合」備註管道:
- 存在 `restaurants.custom_tags`(`text[]` 陣列),沒有自己的表,不能被重複使用/共用,每間餐廳各自維護(前端可以把所有餐廳目前用過的自訂標籤字串收集起來做篩選/快速加入候選,但這是應用層的文字比對,不是資料庫關聯)
- 使用者可以輸入任何文字,包括人名、類型、心情、場合等等,系統不解析、不限制內容——想記錄「哥哥最愛」就直接打這幾個字當自訂標籤
- 不參照 `group_members` 表,純粹是餐廳自己的分類備註

這兩套系統**不要互相取代、合併或建立關聯**。演變過程:v3 把成員併入自訂標籤(拿掉結構化意義,已推翻);v4 復原成兩套獨立系統但成員還能貼餐廳;v4.2 拿掉成員貼餐廳的關聯;v4.3 把群組整個拿掉,家人變成獨立於群組之外的飲食偏好備忘;**v5 把家人備忘併回群組底下,並且讓群組透過「已連結/未連結」狀態變成真的能用的功能**。

**協作場次裡真正會出現、會按✅、會表態的參與者(`session_participants`)**,不管是從已連結群組成員自動帶入、還是訪客用連結加入,都是「這個場次的真實與會名單」,跟 `group_members` 是分開的兩張表——已連結的 member 加入場次時,`session_participants.user_id` 會等於該 member 的 `linked_user_id`;未連結的 member 如果本人之後用連結加入,是以訪客或自己帳號的身份加入,系統不會自動幫它跟原本的 member 記錄配對(這個「配對/認領」機制目前不存在,理由同第 8 節問題 8——避免搶認領衝突,等真帳號系統成熟後再設計)。

---

## 3. 現有原型狀況(對照 meal-picker.html)

> **狀態更新(v5)**:群組從「整頁鎖住的佔位」變成真的能建立/管理的功能;家人偏好小抄併入群組;⭐ 收藏併入 🗺️ 地圖;新增 🧾 點餐分頁。下面的清單是**目前原型的實際狀態**。

已經做出來、邏輯完整、可互動的部分:
- 5 個分頁:🗺️ 地圖(內含左右切換的「地圖／收藏」)・👥 群組・🎯 決策・🧾 點餐・☰ 更多
- 餐廳收藏(CRUD 含編輯;地圖定位板;食物類型下拉篩選、自訂標籤下拉篩選,同一列並排),現在收在「地圖」分頁裡用左右分頁切換,不是獨立的上層分頁
- 每間餐廳可維護:自訂標籤(自由文字)、菜單存放區(常點餐點+價格,可多筆增刪)、菜單照片(多張上傳,原型階段存在瀏覽器記憶體)
- 👥 群組分頁:真的能建立群組、改名、刪除;點進群組可以新增/編輯/刪除 member,每個 member 顯示「🔓 未連結帳號」或「✅ 已連結帳號」徽章(目前恆為未連結,連結動作是尚未開放提示)、飲食偏好標籤
- 決策:個人抽籤、系統建議、協作場次(候選/表態合併在同一個子分頁、參與者另一個子分頁 → 轉盤結果)。抽籤與協作場次候選頁的自訂標籤 chip 是**篩選**用途,不是整批匯入
- 協作場次的「這次要找誰一起決定」畫面兩個選項都能用:「👥 選好友群組」(選一個群組,已連結成員自動列入參與者,未連結的可事後用連結加入)、「🔗 自由邀請」(純用連結,不需要群組)
- 🧾 點餐分頁:建立一筆點餐可以「從決策紀錄匯入」或「直接選店」,再選「📝 自建成員清單」(單機操作,可從群組匯入成員或自由輸入,自己幫每個人填品項跟價錢,真的能用)、「👥 群組邀點餐」或「🔗 連結發點餐」(多裝置各自輸入,連結功能尚未開放,先預覽接下來的畫面)
- ☰ 更多分頁有「自訂標籤管理」「食物類型管理」兩個入口,可以改名、刪除、看使用數量
- 決策結果可輸出成分享圖片(純 Canvas 繪製,是真功能)

明確是 placeholder、需要在 Claude Code 補上真功能的部分:
- 帳號系統、`linked_user_id` 真的能連結、多裝置即時同步
- 協作場次/點餐的邀請連結真的能產生、能分享
- 「群組邀點餐」「連結發點餐」的多裝置各自輸入(目前落地在跟自建成員清單一樣的畫面,單機代填)
- 隱私權政策/服務條款/帳號設定/意見回饋(各自有客製化的「尚未開放」提示文字)
- Google 地圖真實店家搜尋(API 金鑰不能放前端,暫不內建)
- 菜單照片的長期保存(要接 Supabase Storage)

**注意**:協作場次原本原型裡有「模擬新增訪客」「立即結算(測試用)」幾顆 demo/假機制按鈕方便單機測試,都已經拿掉(正式版靠真實邀請連結 + 第 6 節的排程雙保險結算)。這代表**這個原型現在沒有辦法在瀏覽器裡端到端測試「有人加入協作場次」的流程**,只能測試候選/表態/倒數這幾塊,要等 Tier 2 接上真帳號與邀請連結才能完整測試。點餐的「群組邀點餐/連結發點餐」同理。

---

## 4. 資訊架構詳細說明

### 🗺️ 地圖 / ⭐ 收藏(v5 併成同一個分頁)
分頁內用左右分頁(segmented control)切換「🗺️ 地圖」跟「⭐ 收藏」,不再是各自獨立的上層分頁——這是空出分頁位置給「點餐」的做法。收藏內容不變:支援新增與編輯,篩選同一列並排:「★ 只看最愛」切換 chip、「食物類型」下拉、「自訂標籤」下拉(沒有自訂標籤時這個下拉不顯示)。**沒有成員篩選**——群組跟餐廳沒有關聯。每間餐廳的詳細內容包含:名稱、類型、價位、自訂標籤、菜單存放區、菜單照片、備註。

### 👥 群組(v5:從佔位提示變成真的功能)
兩層畫面:上層是群組列表(卡片列出群組名 + 成員數,右上角「＋」新增群組),點進去是該群組的成員詳情(卡片列出每個 member 的頭像、名字、已/未連結徽章、飲食偏好標籤,右上角「＋」新增 member,每個 member 可以 ✎ 編輯 / 🗑 刪除,群組本身也可以改名/刪除)。新增/編輯 member 的表單裡有一個徽章顯示目前的連結狀態,點了會提示「需要帳號系統才能連結真帳號」。這一頁完全取代了 v4.3 的「家人偏好小抄」——member 現在一定屬於某個群組。

### 🎯 決策
三個子模式:
1. **抽籤**:候選名單 + 轉盤(個人用,快速)。候選名單上方有依自訂標籤產生的篩選 chip,點一下**不是整批匯入**,而是把下方「顯示所有店家」清單篩選成只顯示該標籤的餐廳,使用者再逐一勾選要加入候選的店家。協作場次候選頁的自訂標籤 chip 是同一套邏輯
2. **系統建議**:類型篩選 + 一鍵建議,自動排除最近吃過的類型
3. **協作場次**:見第 6 節詳細流程。「這次要找誰一起決定」畫面兩個選項都能用:「👥 選好友群組」(選一個群組,已連結成員自動加入,列出「X 位已連結成員會自動加入,其餘 Y 位未連結成員可以用邀請連結加入」的提示)、「🔗 自由邀請」(純用連結);候選店家一律用自訂標籤 chip 快速加入,或手動瀏覽/新增,不會因為選了誰而自動帶入候選

### 🧾 點餐(v5 新增)
決定好要吃哪間之後開一筆點餐,流程分兩步:
1. **選店家**:「🎯 從決策紀錄匯入」(挑一間最近決定過的店)或「🍽️ 直接選店」(從收藏挑)
2. **選收集方式**:「📝 自建成員清單」(單機操作,主揪自己幫每個人填品項跟價錢,成員可以「從群組匯入」批次帶入某個群組的所有 member,也可以自由輸入名字;真的能用)、「👥 群組邀點餐」/「🔗 連結發點餐」(多裝置各自輸入,連結功能尚未開放,先落地到跟自建清單一樣的畫面,單機代填)

點餐詳情頁是一份可編輯的清單(姓名/品項/價格三欄,可增刪),底部即時算小計,方便團訂結帳。

### ☰ 更多
頂部是兩個管理入口:「🏷️ 自訂標籤管理」「🍜 食物類型管理」。下方是 App 層級資訊:隱私權政策、服務條款、帳號設定、關於、意見回饋。**不再有「家人偏好小抄」入口**——併入群組了。

---

## 5. 資料模型(已套用第 8 節審查結果 + v5:群組/member 用已連結/未連結狀態重新做成真功能,新增點餐)

### 核心原則
- 餐廳收藏、地圖、決策歷史、群組都是「帳號個人的」
- **群組/member(`groups`/`group_members`)跟自訂標籤(`custom_tags`)是兩套獨立系統,不要合併、不要建立關聯**:群組/member 是結構化資料(綁帳號、有 `prefs`、有 `linked_user_id`),用途是「這群人是誰、飲食偏好是什麼、有沒有連結真帳號」;自訂標籤是完全自由的文字(只存在餐廳自己身上),用途是「這間店的備註,包括誰喜歡」
- **`linked_user_id` 是 nullable 的**,代表 member 不一定有真身份;有身份的話,協作場次會自動列入邀請,沒有的話還是可以靠邀請連結加入,兩者不衝突
- member 沒有「代管被本人認領」的機制(v2 定案,見第 8 節問題 8)——`linked_user_id` 由帳號本人透過某種驗證流程(例如收到邀請、確認關係)設定,不是自動配對搶認領,這部分的具體流程留給 Tier 2 設計 Auth 時一併定案
- 協作場次的參與者(`session_participants`,真人)是完全獨立的世界,場次建立時參與者名單已是快照,不即時查詢群組
- 每間餐廳除了基本資料,還有一份可多筆的菜單(常點餐點+價格)跟菜單照片
- 點餐(`orders`/`order_items`)是決策之後的延伸功能,`order_items` 目前用純文字記錄姓名(不強制參照 `group_members` 或 `session_participants`),因為「誰在填」本來就可能是主揪代填、也可能是任何一個有連結的人——這個欄位刻意保持鬆散,比照 `decision_history.restaurant_name`、`session_pool.adhoc_name` 的文字備份模式;Tier 2 如果要做「群組邀點餐/連結發點餐」的真多裝置各自輸入,屆時可能需要類似 `session_participants` 的 `order_participants` 表來記錄「誰真的用自己的裝置填了這筆」,現在不用先設計

### 實體關聯(概念層級)
```
users(帳號)
  └─ 擁有 groups(群組)、restaurants(收藏)、decision_history(歷史)、
     decision_sessions(場次)、custom_categories(自訂食物類型)、orders(點餐)

custom_categories(帳號自己新增的食物類型,跟前端寫死的 8 種預設類型並存)
  └─ 不對 restaurants.category 設外鍵,靠文字比對關聯,改名/刪除時應用層批次更新

groups(帳號自己的群組,例如「家人」「公司同事」)
  └─ group_members(群組成員,結構化資料:名字/顏色/飲食偏好/linked_user_id)
       └─ linked_user_id 可為 null:null = 未連結(純備忘),有值 = 已連結真帳號
       └─ **不連結 restaurants**——「誰喜歡這間店」還是記在 custom_tags

restaurants(餐廳,屬於某個 user)
  ├─ custom_tags:text[] 欄位,完全自由的文字標籤,唯一的「誰喜歡/什麼場合」備註管道
  ├─ restaurant_menu_items:餐廳的常點餐點清單(一對多,文字+價格)
  └─ restaurant_photos:餐廳的菜單照片(一對多,跟上面文字清單疊加,不是取代)

decision_history(決策歷史,屬於某個 user)

decision_sessions(協作場次)
  ├─ group_id:選群組建立時記錄選了哪個群組(ON DELETE SET NULL,群組刪除不影響已建立的場次)
  ├─ 建立時快照參與者(已連結的 group_members 自動快照進 session_participants)
  ├─ deadline_at:絕對截止時間
  ├─ status:collecting | waiting | done | no_result
  ├─ session_participants:真人(訪客或登入帳號),已連結成員加入時 user_id = 該 member 的 linked_user_id
  ├─ session_pool:候選店家,可以是某人收藏裡的店,也可以是場次專用臨時候選
  └─ session_votes:表態篩選模式專用

orders(點餐,屬於某個 user)
  ├─ restaurant_id:選的店(ON DELETE SET NULL,只留文字備份)
  ├─ mode:manual | group | link
  ├─ group_id:group 模式才有值(ON DELETE SET NULL)
  └─ order_items:每一筆姓名+品項+價格(文字備份,不強制參照 group_members/session_participants)
```

### 正式的 Supabase (Postgres) SQL

```sql
-- 群組:帳號自己建立的群組,例如「家人」「公司同事」
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

-- 點餐項目:姓名/品項/價格,姓名是文字備份,不強制參照 group_members 或 session_participants
-- ——manual 模式是主揪代填,group/link 模式(Tier 2 才會真的多裝置各自輸入)填的人也不一定有帳號
create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade not null,
  person_name text not null,
  item text,
  price numeric(10,2),
  created_at timestamptz default now()
);
```

啟用 Row Level Security,`owner_user_id = auth.uid()` 是基本擁有者規則(`groups`、`orders` 也適用;`group_members` 透過 `group_id` 關聯回 `groups` 判斷擁有者,`order_items` 透過 `order_id` 關聯回 `orders`)。`restaurant_menu_items`/`restaurant_photos` 同理透過 `restaurant_id` 關聯回 `restaurants` 判斷擁有者。菜單照片建議直接用 Supabase Storage 存檔案本體,`storage_path` 只存路徑。`restaurants.category` 維持純文字欄位、不對 `custom_categories` 設外鍵,改名/刪除自訂類型時由應用層邏輯批次更新符合的 `restaurants.category` 文字值,做法比照 `decision_history.restaurant_name` 的文字備份模式。`decision_sessions`/`session_participants`/`session_pool`/`session_votes`/`orders`/`order_items` 這幾張表因為訪客沒有帳號,需要另外設計「憑 `invite_token` 換取有限寫入權限」的規則(建議透過一個 Edge Function 驗證 token 沒過期,再用 service role 代為寫入,不要讓訪客直接拿到能繞過 RLS 的權限)。`group_members.linked_user_id` 的寫入(也就是「連結帳號」這個動作)建議也走 Edge Function,驗證雙方同意後才設定,不要讓任何一方單方面把別人的 `auth.users.id` 填進來。

---

## 6. 協作場次 & 點餐完整流程

### 協作場次流程(已依審查結果更新,v5 補上真群組)

```
1. Owner 進「決策」→「協作場次」
2. 選擇找誰一起決定:
   - 「👥 選好友群組」:選一個群組,已連結帳號的成員自動列入參與者快照;
     未連結的成員不會自動加入,但一樣可以在下一步的邀請連結加入
   - 「🔗 自由邀請」:純用連結,空白開始,不預先帶入任何人
   —— 不管選哪個,都**不影響候選店家怎麼湊**(候選一律用自訂標籤快速加入或手動瀏覽)
3. 設定決策模式(直接轉盤 / 先表態篩選)—— 一開始選定,場次期間不能中途更改
4. 設定截止時間:絕對時間點(幾月幾號幾點幾分),可選未來 7 天內,預設建立時間 + 1 小時
5. 產生邀請連結,有效期 = 場次截止時間(不是固定 1 小時)
6. 受邀者訪客身份的暫存資料,保留時間同樣跟著場次截止時間走,不是固定 1 小時
7. 截止時間之前,所有人(包括訪客、自動列入的已連結成員)都可以:
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
```

### 逾時觸發機制(A+B 雙保險,已定案)
- **A(排程保底)**:Supabase Scheduled Function,每 1 分鐘掃描一次 `decision_sessions`,找出 `status in ('collecting','waiting') and deadline_at <= now()` 的場次,依上方第 8 步結算;同時掃描 `status in ('done','no_result') and cleanup_after <= now()` 的場次執行刪除。就算所有人都沒開著頁面,場次也會準時結算跟清除,只有最多 1 分鐘的誤差。
- **B(前端主動檢查)**:任何人打開場次畫面時,前端比對目前時間是否已超過 `deadline_at`,超過的話呼叫跟排程一樣的結算邏輯,讓「剛好有人在看」的情況能更即時反應,不用等排程的下一次執行。

### 點餐流程(v5 新增)

```
1. 使用者進「點餐」分頁,按「＋」開一筆新的
2. 選店家:「從決策紀錄匯入」(挑一間最近決定過的店)或「直接選店」(從收藏挑)
3. 選收集方式:
   - 「自建成員清單」:單機操作,立刻進入點餐詳情頁,主揪自己幫每個人填品項跟價錢,
     成員可以「從群組匯入」批次帶入某個群組的所有 member(略過已存在的同名),
     也可以自由輸入名字新增一筆
   - 「群組邀點餐」:選一個群組 → 進入邀請連結畫面(Tier 2 才會真的能分享)→
     繼續之後進入跟自建清單相同的詳情頁,items 依群組成員預先建好空白列
   - 「連結發點餐」:同上,但不預選群組,items 一開始是空的
4. 詳情頁:姓名/品項/價格三欄可編輯,可增刪,底部即時算小計
5. 沒有「結算」或「送出」動作——這筆點餐會一直留著可以回來改,
   要清掉就手動刪除整筆
```

Tier 2 如果要做到「群組邀點餐/連結發點餐」真的多裝置各自輸入,需要類似協作場次 `session_participants` 的機制(例如 `order_participants`,記錄誰用自己的裝置加入了這筆點餐、填了哪幾筆),現在的 `order_items.person_name` 只是文字備份,不夠支撐「即時看到別人正在打字」這種體驗,這個留到那個階段一併設計。

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
  - 群組列表/群組成員卡沿用既有的 `.groupListRow`/`.memberCard`/`.kindBadge` 樣式語彙,沒有另外發明一套新元件

---

## 8. 資料生命週期審查(十題定案 + v5 補充)

原型階段用假資料看不出來的問題,接上真資料庫後會直接卡死或報錯,逐一審查定案如下:

| # | 問題 | 定案結果 |
|---|---|---|
| 1 | 逾時判斷只靠前端瀏覽器倒數,發起人關掉分頁就永遠不會觸發 | 伺服器排程(每分鐘掃描)當保底 + 前端有人打開頁面時主動檢查,雙保險(詳見第 6 節) |
| 2 | 帳號刪除,底下資料的連帶處理沒定義 | 每個帳號只刪自己直接擁有的東西(自己的收藏/群組/標籤/歷史/點餐);貼在別人餐廳上的標籤本來就是別人帳號的資料,不受影響 |
| 3 | 候選名單湊不到 2 間時,原本的「進等待畫面才開始倒數」邏輯永遠不會啟動逾時 | 改成「絕對截止時間」,從場次建立那刻就固定,不管候選湊了沒;決策模式建立時選定;候選/表態在截止前隨時可做;時間到依候選數量結算(≥2 轉盤、剛好 1 間免轉、0 間 = no_result) |
| 4 | 場次沒有「過期/沒結果」的終點狀態,會議累積一堆「永遠進行中」的死場次 | 新增 `no_result` 狀態;所有結束的場次保留 1 小時緩衝(方便看結果、分享圖片)才由排程清除 |
| 5 | 訪客資料/邀請連結固定 1 小時,但場次可能跑更久,訪客資料會在場次結束前就過期消失 | 兩者都改成跟著場次的 `deadline_at` 走,不再是獨立固定 1 小時(這題其實是問題 3 改成絕對截止時間後自動解決的) |
| 6 | 群組被刪除時,底下進行中的協作場次會沒有依歸(外鍵沒設刪除規則會報錯) | 場次建立時參與者名單已快照,不即時查詢群組;`decision_sessions.group_id`(以及 v5 新增的 `orders.group_id`)設為 `ON DELETE SET NULL`,群組刪除不影響已建立的場次/點餐 |
| 7 | 刪除餐廳後,決策歷史裡的 `restaurantId` 會指向不存在的資料 | `ON DELETE SET NULL`,只留店名/類型文字備份,歷史紀錄畫面不會壞,但斷開跳轉關聯(v5 的 `orders.restaurant_id` 也比照同一模式) |
| 8 | 「代管成員被本人認領」這個機制,會衍生搶認領衝突、資料合併規則等一堆複雜情況 | **維持不做自動配對/認領**——`group_members.linked_user_id` 的設定必須是雙方確認過的動作(建議透過邀請流程,見第 5 節 SQL 註解),不是系統自動比對名字或猜測配對。這個決定連帶簡化了問題 2 的規則 |
| 9 | 自由邀請場次結束後,參與者名單直接消失,下次想約同一群人要重新一個個邀請 | v4.3 曾拿掉這個功能(因為當時沒有真群組可以存);**v5 群組復活後,這個功能可以重新設計**——結果畫面「加為好友/存進群組」的按鈕,等 Tier 2 真帳號系統做出來時一併實作,現在原型裡維持「尚未開放」提示,不搶在群組 CRUD 都還沒完全串接帳號系統之前先做 |
| 10 | 地圖用相對座標(x/y%),不是真經緯度,接資料庫後這批資料沒有實際用途 | 資料庫直接規劃 `lat`/`lng` 真經緯度欄位,原型的相對座標不搬過去,欄位一開始留空,一次到位不用之後再改表結構 |

**這次審查過程中額外發現、順手一併定案的細節:**
- 候選名單除了能從既有收藏挑店,協作場次裡任何參與者(包含訪客)都可以臨時新增一間「這場次專用」的候選店家,不掛在任何人收藏底下,場次結束就消失(對應 `session_pool` 表的 `adhoc_name`/`adhoc_category` 欄位)
- `session_participants` 刻意不參照 `group_members` 表——群組成員(可能有身份、可能沒有)跟真人參與者(真的會按✅、會表態)是兩個獨立的資料世界,已連結的成員加入場次時只是把 `linked_user_id` 複製成 `session_participants.user_id`,不是把兩張表關聯起來

**v3→v4 修正紀錄**:v3 曾經把 `people` 表整個併入一套統一的 `tags` 表,這是誤解了「成員」跟「自訂標籤」的定位,v4 已經復原成兩套獨立系統。第 8 節問題 2、8 的定案結論不受這次復原影響,一直都成立。

**v4→v4.2 修正紀錄**:v4 復原兩套系統後,`people` 短暫還留著 `restaurant_tags` 這條連結。討論到協作場次希望能對群組真人發送通知時,才發現「成員貼餐廳」跟「成員是決策通知對象」是兩個不相關的用途硬塞在同一張表上。v4.2 拿掉 `restaurant_tags`,「這間店誰喜歡」全部改記在 `restaurants.custom_tags` 裡,這個決定 v5 沿用不變。

**v4→v4.3 修正紀錄**:`groups`/`group_members` 拿 `people` 標籤模擬、卻無法真的通知任何人,v4.3 判斷這套機制製造的麻煩比帶來的價值多,整個拿掉,`people` 縮回成獨立於群組之外的「家人偏好小抄」。

**v4.3→v5 修正紀錄(這次)**:v4.3 拿掉群組的理由是「假資料模擬真通知,製造轉換麻煩」,但完全不做群組,又讓「家人偏好小抄」跟「協作場次找人」這兩件事永遠是分開的兩張皮,使用者體驗上很奇怪(明明就是同一群家人,收藏偏好備忘跟協作場次找人卻要分開兩個地方管理)。v5 用 `linked_user_id` 這個 nullable 欄位解開這個兩難:群組跟 member 現在就是真表、真功能,不是模擬;「連結真帳號」這件事被獨立成一個狀態欄位,欄位可以誠實地是 null(還沒連結),不需要打腫臉充胖子生出一個並不存在的通知對象。這樣「群組」從一開始就是對的表結構,Tier 2 接 Auth 時只是把 `linked_user_id` 的寫入邏輯做出來,不需要重新設計整套群組系統或搬移既有資料。

---

## 9. 分階段路線圖

| 階段 | 內容 | 狀態 |
|---|---|---|
| Tier 0 | 單人模式,基本五分頁功能 | ✅ 原型已完成 |
| Tier 1 | 協作場次 UI 全部蓋完,未串接後端功能先做空按鈕 | ✅ 原型已完成 |
| Tier 1.5 | UI/UX 檢視與優化(編輯功能補完、協作場次畫面重構、一致性修正) | ✅ 原型已完成 |
| Tier 1.6 | 群組/member 復活(已連結/未連結狀態)、地圖收藏合併、新增點餐分頁 | ✅ 原型已完成(v5) |
| **Tier 2(交給 Claude Code)** | **接上 Supabase:真帳號(Auth)、真資料庫(第 5 節 schema)、排程結算(第 6 節)、Realtime 同步、邀請連結真的能用、`linked_user_id` 真的能連結** | 🔜 下一步 |
| Tier 3 | 拍照記錄三餐、AI 估算熱量、依歷史自動排除重複類型 | 未來 |
| Tier 4 | 正式部署(Vercel/Netlify),取得正式網址 | 未來 |

**為什麼選 Supabase**:關聯式資料庫對應「帳號→群組/餐廳→決策場次/點餐」的關聯結構;內建 Auth 解決帳號(也是 `linked_user_id` 能真的動起來的前提);內建 Realtime 解決協作場次與點餐的即時同步;Scheduled Functions/`pg_cron` 解決第 8 節的逾時排程需求,不用另外架服務。免費層額度(500MB DB、5 萬月活躍用戶、200 個並發 Realtime 連線)對這個規模綽綽有餘,唯一要注意免費專案連續 7 天沒存取會自動暫停(資料還在,手動喚醒即可)。

---

## 10. 交付檔案清單

- `meal-picker.html` — 目前唯一可執行的原型,UI/互動邏輯的參考起點,已套用 v5 設計
- `CLAUDE_CODE_專案交接文件.md`(本文件)— 資料庫、帳號、排程、路線圖、第 8 節生命週期審查
- `補充-UIUX優化定案.md` — UI/UX 檢視問題清單與定案結果,已全部做進原型
- `補充-食物類型擴充定案.md` — 食物類型可自訂擴充的定案結果

---

## 11. UI/UX 優化指引(✅ 已執行完畢,見 `補充-UIUX優化定案.md`)

> 這節是歷史紀錄,不是待辦。UX 檢視的問題清單跟最終定案結果記錄在同一批交付檔案裡的 `補充-UIUX優化定案.md`,三批改動(編輯功能、協作場次畫面重構、一致性修正)都已經做進 `meal-picker.html` 裡並實測過。

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
```

### 使用建議
先讓 Claude Code 產出問題清單跟建議(不動手改),看過之後**自己決定優先順序**,再請它動手——不需要一次全部改完,可以先挑你最有感的一兩項處理,看效果再決定要不要繼續。
