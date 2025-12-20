# OceanExpress 後端 API 規格（Rust/axum + MongoDB）

面向角色：`customer`（買家）、`deliverer`（外送員）、`restaurant`（餐廳）。  
所有時間採 ISO8601 UTC，ID 一律 string（Mongo ObjectId/UUID 皆可，但對前端以 string 傳遞）。

## 環境變數
- `API_BASE_URL`：前端用來組 API 位址（預設 http://localhost:3000）。  

## 通用規範
- 認證：JWT，受保護路由需 `Authorization: Bearer <token>`.
- 成功回傳：`200/201` 一律包 `{ "data": ... }`；錯誤：`{ "message": "...", "code": "..." }`（前端已強制依此解碼）。
- 時間格式：ISO8601 UTC（可含毫秒），包含 `placedAt/requestedTime/createdAt` 等欄位。
- 狀態枚舉（前後端需對齊）：  
  - 訂單/配送：`available, assigned, en_route_to_pickup, picked_up, delivering, delivered, cancelled`
  - 角色：`customer, deliverer, restaurant`
  - 下單地點：前端會送 `deliveryLocation.name`，若有可選地點座標則一併回傳/儲存 `lat/lng`（來源為預設地點清單）。
- 金額欄位一律為整數（元）：`price/priceDelta/deliveryFee/totalAmount/fee` 不使用小數。

## Auth
- `POST /auth/login`
  - body: `{ "email": "user@example.com", "password": "..." }`
  - 200:
    ```json
    { "data": { "token": "<jwt>", "user": { "id": "u123", "email": "user@example.com", "role": "customer" } } }
    ```
  - 401: `{ "message": "invalid credentials", "code": "auth.invalid" }`

- `POST /auth/register`
  - body: `{ "name": "Sample User", "email": "user@example.com", "password": "...", "phone": "09xxxxxxxx" }`
  - 201: `{ "data": { "id": "u124", "email": "user@example.com", "role": "customer", "phone": "09xxxxxxxx" } }`（也可直接回 token，前後端自行決定）
  - 400: `{ "message": "email exists", "code": "auth.email_taken" }`

## 餐廳 & 菜單
- `GET /restaurants`
  - 200:
    ```json
    { "data": [ { "id": "rest-001", "name": "Marina Burger", "imageUrl": "https://...", "rating": 4.5 } ] }
    ```

- `GET /restaurants/:id`
  - 200: `{ "data": { "id": "...", "name": "...", "imageUrl": "...", "address": "...", "phone": "...", "rating": 4.5 } }`

- `GET /restaurants/:id/reviews`
  - 200:
    ```json
    {
      "data": [
        { "id": "rev-001", "userName": "Alice", "rating": 5, "comment": "餐點好吃，送餐準時！", "createdAt": "2025-11-23T02:00:00Z" }
      ]
    }
    ```

- `GET /restaurants/:id/menu`
  - 200:
    ```json
    { "data": {
      "items": [
        {
          "id": "menu-001",
          "name": "Burger",
          "description": "...",
          "price": 180,
          "sizes": ["Regular"],
          "spicinessOptions": ["Mild", "Medium", "Hot"],
          "allergens": ["peanut", "milk"],
          "tags": ["主餐", "人氣"],
          "imageUrl": null,
          "isAvailable": true,
          "sortOrder": 1
        }
      ]
    } }
    ```

## 買家訂單
- `POST /orders` (auth: customer)
  - body:
    ```json
    {
      "restaurantId": "rest-001",
      "items": [
        {
          "menuItemId": "menu-001",
          "size": "Regular",
          "spiciness": "Mild",
          "addDrink": true,
          "quantity": 2
        }
      ],
      "deliveryLocation": { "name": "資工系館", "lat": 25.084, "lng": 121.67 },
      "notes": "請在警衛室交付",
      "requestedTime": "2025-11-23T10:30:00Z",
      "deliveryFee": 20,
      "totalAmount": 320
    }
  ```
  - 備註：`deliveryLocation.name` 為固定地點名稱，會原樣出現在外送員 API 的 `dropoff.name`。
  - 201: `{ "data": { "id": "ord-001", "status": "available", "etaMinutes": 20 } }`
  - 400: 若品項已暫停販售（`isAvailable=false`），建議回傳 `{ "message": "menu item unavailable", "code": "menu.unavailable" }`。
  - 備註：`menuItemId` 為必填，前端已改為以此欄位下單。

- `GET /orders?status=active|history` (auth: customer)
  - 200: `{ "data": [ { "id": "ord-001", "restaurantName": "Marina Burger", "status": "delivering", "etaMinutes": 8, "placedAt": "2025-11-23T02:00:00Z", "totalAmount": 320 } ] }`

- `GET /orders/:id` (auth: customer)
  - 200: 詳細訂單（含 items、狀態時間戳、外送費、評分、外送員電話）。
    ```json
    {
      "data": {
        "id": "ord-001",
        "restaurantName": "Marina Burger",
        "status": "delivering",
        "etaMinutes": 8,
        "placedAt": "2025-11-23T02:00:00Z",
        "deliveryLocation": { "name": "資工系館", "lat": 25.084, "lng": 121.67 },
        "deliveryFee": 20,
        "totalAmount": 320,
        "riderName": "王外送",
        "riderPhone": "0900-000-000",
        "items": [
          { "name": "Burger", "size": "Regular", "spiciness": "Mild", "addDrink": true, "quantity": 2, "price": 180 }
        ],
        "notes": "請在警衛室交付",
        "statusHistory": [ { "status": "preparing", "timestamp": "..." }, { "status": "delivering", "timestamp": "..." } ],
        "rating": { "score": 5, "comment": "準時且餐點完整" }
      }
    }
    ```

- `POST /orders/:id/rating` (auth: customer)
  - body: `{ "score": 1-5, "comment": "..." }`
  - 200: `{ "data": { "score": 5, "comment": "..." } }`

- `PATCH /orders/:id/cancel` (auth: customer)
  - 200: `{ "data": { "status": "cancelled" } }`

## 送餐地點 & 即時推播
- `GET /delivery/locations`  
  - 回傳預設地點清單（用於下單選單），支援分類。範例：  
    ```json
    { "data": [ { "category": "校園示範", "items": [ { "name": "行政大樓", "lat": 25.1503372, "lng": 121.7655292 } ] } ] }
    ```
  - 前端會直接使用後端回傳的分類與座標，請確保資料齊全。
- 推播/即時：建議新增 SSE / WebSocket 端點 `GET /orders/stream`（依 user token 僅推播本人訂單），事件：`order.updated` payload 同 `GET /orders/:id` 的 data；或提供 `/orders/:id/stream` 針對單筆訂單推播狀態變化。

## 外送員（Deliverer）
- `GET /delivery/available` (auth: deliverer)
  - 回傳可接單列表（座標若有可傳，若無則僅回傳名稱）：  
    `{ "data": [ { "id": "ord-001", "code": "A1-892", "fee": 85, "distanceKm": 1.2, "etaMinutes": 12, "status": "available", "merchant": { "name": "...", "lat": 25.0, "lng": 121.5 }, "customer": { "name": "...", "phone": "...", "lat": 25.01, "lng": 121.53 }, "dropoff": { "name": "資工系館" } } ] }`
  - 欄位說明：`dropoff.name` 直接來自買家下單的 `deliveryLocation.name`；若前端送出座標則回傳即可（來源為預設地點清單）。

- `GET /delivery/:id` (auth: deliverer)
  - 200: `{ "data": { ...DeliveryTask 同上... } }`
  - 僅允許讀取：
    - 任務為 `available`（尚未綁定外送員），或
    - 任務的 `delivererId` 等於當前登入外送員 id。
  - 若找不到或無權限則回傳 404/403（錯誤格式同下方通用錯誤）。

- `POST /delivery/:id/accept` (auth: deliverer)
  - 用途：外送員接單並綁定該任務的 `delivererId`，同時將狀態從 `available` 改為 `assigned`。
  - 200: `{ "data": { ...DeliveryTask 同上..., "status": "assigned", "delivererId": "<currentUserId>" } }`
  - 400: 若訂單已被其他外送員接走或不在 `available` 狀態（可使用 `order.conflict` 之類錯誤碼）。

- `GET /delivery/active` (auth: deliverer)
  - 200: 回傳該外送員目前進行中的任務列表（例如 `assigned/en_route_to_pickup/picked_up/delivering`），不含已完成/已取消。

- `GET /delivery/history` (auth: deliverer)
  - 查詢該外送員的歷史配送紀錄（通常為 `delivered` 或 `cancelled` 的任務）。
  - Query 參數：
    - `from` (optional, date): 起始日期（含），格式 `YYYY-MM-DD`。
    - `to` (optional, date): 結束日期（含），格式 `YYYY-MM-DD`。
  - 200: `{ "data": [ { ...DeliveryTask 同上..., "status": "delivered" }, ... ] }`

- `GET /delivery/earnings` (auth: deliverer)
  - 查詢指定日期區間內外送員的收益統計，對應 OpenAPI 中的 `EarningsSummary`。
  - Query 參數：
    - `from` (required, date): 起始日期（含）。
    - `to` (required, date): 結束日期（含）。
  - 200:
    ```json
    {
      "data": {
        "from": "2025-11-01",
        "to": "2025-11-30",
        "currency": "TWD",
        "totalEarnings": 12345,
        "totalTasks": 42,
        "byDay": [
          { "date": "2025-11-01", "totalEarnings": 300, "taskCount": 2 },
          { "date": "2025-11-02", "totalEarnings": 0, "taskCount": 0 }
        ]
      }
    }
    ```

- `GET /delivery/notifications` (auth: deliverer)
  - 用途：輪詢或長輪詢取得新任務/狀態更新等事件，用來在未整合推播時讓 App 保持同步。
  - Query 參數：
    - `sinceId` (optional): 客戶端最後一次收到的通知 id，伺服器會回傳之後的通知。
    - `since` (optional, date-time): 依時間戳抓取之後建立的通知（ISO8601 UTC）。
  - 200:
    ```json
    {
      "data": [
        { "id": "n1", "type": "new_task_available", "taskId": "ord-001", "status": "available", "createdAt": "2025-11-23T02:00:00Z" },
        { "id": "n2", "type": "task_status_updated", "taskId": "ord-001", "status": "delivering", "createdAt": "2025-11-23T02:10:00Z" }
      ]
    }
    ```

- `PATCH /delivery/:id/status` (auth: deliverer)
  - 用途：外送員更新自己任務的配送狀態，例如 `assigned → en_route_to_pickup → picked_up → delivering → delivered/cancelled`。
  - 僅允許該任務的 `delivererId == currentUser.id` 的外送員呼叫；否則應回傳 403/400。
  - body: `{ "status": "en_route_to_pickup|picked_up|delivering|delivered|cancelled" }`
  - 200: `{ "data": { ...DeliveryTask 同上..., "status": "<status>" } }`

- `POST /delivery/:id/incident` (auth: deliverer)
  - 外送員回報配送異常/狀況。
  - body: `{ "note": "文字描述" }`
  - 200: `{ "data": { "status": "reported" } }`（或回傳更新後的任務，格式與 DeliveryTask 一致）
  - 備註：前端已串接此端點；請確保任務權限與狀態檢查。

- （可選）`POST /delivery/:id/location` (auth: deliverer)
  - body: `{ "lat": 25.0, "lng": 121.5, "heading": 180 }`

## 餐廳端（Restaurant/Admin）
- 權限：`role=restaurant`。若帳號可管理多店，請在 API 接收/推導 `restaurantId`。
- 狀態映射（沿用全局枚舉，前端顯示中文）：`available(未接單)`, `assigned(備餐中)`, `en_route_to_pickup(待取餐)`, `picked_up(已取餐)`, `delivering(配送中)`, `delivered(已完成)`, `cancelled(已取消)`。

- `GET /restaurant/orders?status=active|history[&restaurantId=...]`
  - 200:
    ```json
    {
      "data": [
        {
          "id": "ord-001",
          "code": "A1-892",
          "status": "assigned",
          "placedAt": "2025-11-23T02:00:00Z",
          "etaMinutes": 12,
          "totalAmount": 320,
          "deliveryFee": 20,
          "customer": { "name": "小明", "phone": "0912-000-000" },
          "items": [
            { "id": "menu-001", "name": "Burger", "size": "Regular", "spiciness": "Mild", "quantity": 2, "price": 180 }
          ],
          "notes": "請在警衛室交付",
          "deliveryLocation": { "name": "資工系館", "lat": 25.084, "lng": 121.67 }
        }
      ]
    }
    ```

- `GET /restaurant/orders/:id`
  - 回傳同列表但含 `statusHistory[{status,timestamp}]`、`riderName/riderPhone`（若已指派外送員）。

- `PATCH /restaurant/orders/:id/status`
  - body: `{ "status": "assigned|en_route_to_pickup|picked_up|delivered|cancelled" }`
  - 行為：更新後請推播/通知買家與外送員（事件可沿用 `order.updated`）。

- `GET /restaurant/menu`
  - 200: `{ "data": [ { "id": "menu-001", "name": "...", "description": "...", "price": 180, "sizes": ["中份"], "spicinessOptions": ["不辣"], "allergens": [], "tags": [], "imageUrl": null, "isAvailable": true, "sortOrder": 1 } ] }`

- `POST /restaurant/menu`
  - body: `{ "name": "...", "description": "...", "price": 180, "sizes": [], "spicinessOptions": [], "allergens": [], "tags": [], "imageUrl": null, "isAvailable": true, "sortOrder": 1 }`
  - 201: `{ "data": { "id": "menu-001", ... } }`

- `PATCH /restaurant/menu/:id`
  - body: 同上欄位為可選；可用於上下架（`isAvailable` 切換暫停販售）、排序（`sortOrder`）。

- 報表 `GET /restaurant/reports?range=today|7d|30d&restaurantId=...`
  - 200:
    ```json
    {
      "data": {
        "range": "7d",
        "totalRevenue": 25800,
        "orderCount": 132,
        "topItems": [
          { "id": "menu-001", "name": "Burger", "quantity": 56, "revenue": 10080 },
          { "id": "menu-002", "name": "沙拉", "quantity": 34, "revenue": 6120 }
        ]
      }
    }
    ```
  - 金額整數（元），若提供自訂起迄日亦可。

## 錯誤格式
```json
{ "message": "invalid credentials", "code": "auth.invalid" }
```
常見錯誤碼：`auth.invalid`, `auth.forbidden`, `order.not_found`, `order.conflict`, `menu.unavailable`, `validation.failed`, `server.error`

## 資料模型摘要
- User: `{ id, email, role }`
- Restaurant: `{ id, name, imageUrl?, address?, phone?, rating? }`
- MenuItem: `{ id, name, description, price<int>, sizes[], spicinessOptions[], allergens[], tags[], imageUrl?, isAvailable?, sortOrder? }`
- Order: `{ id, restaurantId, userId, items[], status, etaMinutes?, placedAt, requestedTime?, deliveryLocation{name,lat?,lng?}, deliveryFee<int>?, totalAmount<int>?, notes?, rating?, riderName?, riderPhone?, statusHistory[] }`
- DeliveryTask（可共用 order id）：`{ id, delivererId?(=riderId), status, fee<int>, distanceKm?, etaMinutes?, merchant{}, customer{}, dropoff{}, history[] }`

## 缺少 / 待實作（前端已串接或預留）
- `POST /orders/:id/rating`：買家送達後評分（分數 1-5 + comment），需儲存並回傳於 `GET /orders/:id`、`GET /orders?status=history`。
- `GET /delivery/locations`：回傳預設外送地點清單（含 name/lat/lng），支援分類；前端以此為準。
- `GET /orders/stream`（SSE/WebSocket）：依使用者 token 推播訂單狀態變更，事件 payload 同 `GET /orders/:id`；若無法即時，請提供最小化輪詢 ETag/Last-Modified。
- 菜單欄位 `allergens`, `tags`, `isAvailable`, `sortOrder` 需在 `GET /restaurants/:id/menu` 回傳；目前不再使用 `drinkOptions` / `drinkOption*`。
- 下單 payload 需驗證/落庫 `deliveryFee`、`totalAmount`（整數）；建議由後端計算，前端送出的值請比對。
- 餐廳評分/評論：`rating` 欄位請於列表/詳情回傳，`GET /restaurants/:id/reviews` 回傳評論列表。
- 外送員聯絡：請提供 `riderName/riderPhone` 欄位（含權限控管）。
- 餐廳端：`GET /restaurant/orders`、`GET /restaurant/orders/:id`、`PATCH /restaurant/orders/:id/status`（推播買家/外送員）；`GET/POST/PATCH /restaurant/menu`；`GET /restaurant/reports`（today/7d/30d 或自訂）。

## 修改紀錄
- 統一回應格式 `{ data }` / `{ message, code }`，時間採 ISO8601（可含毫秒）；金額欄位改整數元。
- 下單改用 `menuItemId` 為必填，`deliveryLocation` 支援 name+lat/lng（預設清單）；配送端 `dropoff` 可僅有名稱。
- 菜單新增 `allergens`, `tags`, `isAvailable`, `sortOrder`，移除飲料選項相關欄位。
- 外送員任務綁定 `delivererId`（riderId）並新增/擴充 `GET /delivery/:id`、`/history`、`/earnings`、`/notifications` 等端點，配送狀態更新需驗證任務綁定。
- 餐廳端新增訂單列表/狀態更新推播、菜單管理與報表 API，權限需 `role=restaurant`（多店需傳 `restaurantId`）。
- 2025-01-06：合併 api.md 到本檔、註冊 phone 欄位說明，補充待實作清單。
- 2025-01-07：金額改整數、餐廳 rating、地點分類回傳，移除飲料選項相關欄位。
- 2025-01-08：新增餐廳端 API 與權限說明。
