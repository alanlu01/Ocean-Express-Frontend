# OceanExpress 後端 API 規格（Rust/axum + MongoDB）

面向角色：`customer`（買家）、`deliverer`（外送員）、`restaurant`（餐廳）。  
所有時間採 ISO8601 UTC，ID 一律 string（Mongo ObjectId/UUID 皆可，但對前端以 string 傳遞）。

## 環境變數
- `API_BASE_URL`：前端用來組 API 位址（預設 http://localhost:3000）。  
- `DEMO_MODE`：true/1/yes 強制 demo 模式（前端會用本地假資料）。正式環境請關閉；Deliverer 介面在非 Demo 狀態下會直接呼叫以下配送 API。

## 通用規範
- 認證：JWT，受保護路由需 `Authorization: Bearer <token>`.
- 成功回傳：`200/201` 一律包 `{ "data": ... }`；錯誤：`{ "message": "...", "code": "..." }`（前端已強制依此解碼）。
- 時間格式：ISO8601 UTC（可含毫秒），包含 `placedAt/requestedTime/createdAt` 等欄位。
- 狀態枚舉（前後端需對齊）：  
  - 訂單/配送：`available, assigned, en_route_to_pickup, picked_up, delivering, delivered, cancelled`
  - 角色：`customer, deliverer, restaurant`
  - 下單地點：前端只送 `deliveryLocation.name`，不送 lat/lng；回傳也請移除 `deliveryLocation.lat/lng`。

## Auth
- `POST /auth/login`
  - body: `{ "email": "user@example.com", "password": "..." }`
  - 200:
    ```json
    { "data": { "token": "<jwt>", "user": { "id": "u123", "email": "user@example.com", "role": "customer" } } }
    ```
  - 401: `{ "message": "invalid credentials", "code": "auth.invalid" }`

- `POST /auth/register`
  - body: `{ "name": "Demo User", "email": "user@example.com", "password": "..." }`
  - 201: `{ "data": { "id": "u124", "email": "user@example.com", "role": "customer" } }`（也可直接回 token，前後端自行決定）
  - 400: `{ "message": "email exists", "code": "auth.email_taken" }`

## 餐廳 & 菜單
- `GET /restaurants`
  - 200:
    ```json
    { "data": [ { "id": "rest-001", "name": "Marina Burger", "imageUrl": "https://..." } ] }
    ```

- `GET /restaurants/:id`
  - 200: `{ "data": { "id": "...", "name": "...", "imageUrl": "...", "address": "...", "phone": "..." } }`

- `GET /restaurants/:id/menu`
  - 200:
    ```json
    { "items": [ { "id": "menu-001", "name": "Burger", "description": "...", "price": 180, "sizes": ["Regular"], "spicinessOptions": ["Mild","Medium","Hot"], "imageUrl": null } ] }
    ```

## 買家訂單
- `POST /orders` (auth: customer)
  - body:
    ```json
    {
      "restaurantId": "rest-001",
      "items": [
        { "menuItemId": "menu-001", "size": "Regular", "spiciness": "Mild", "addDrink": true, "quantity": 2 }
      ],
      "deliveryLocation": { "name": "資工系館" },
      "notes": "請在警衛室交付",
      "requestedTime": "2025-11-23T10:30:00Z"
    }
  ```
  - 備註：`deliveryLocation.name` 為固定地點名稱，會原樣出現在外送員 API 的 `dropoff.name`。
  - 201: `{ "data": { "id": "ord-001", "status": "available", "etaMinutes": 20 } }`
  - 備註：`menuItemId` 為必填，前端已改為以此欄位下單。

- `GET /orders?status=active|history` (auth: customer)
  - 200: `{ "data": [ { "id": "ord-001", "restaurantName": "Marina Burger", "status": "delivering", "etaMinutes": 8, "placedAt": "2025-11-23T02:00:00Z" } ] }`

- `GET /orders/:id` (auth: customer)
  - 200: 詳細訂單（含 items、狀態時間戳）。

- `PATCH /orders/:id/cancel` (auth: customer)
  - 200: `{ "data": { "status": "cancelled" } }`

## 外送員（Deliverer）
- `GET /delivery/available` (auth: deliverer)
  - 回傳可接單列表（座標若有可傳，若無則僅回傳名稱）：  
    `{ "data": [ { "id": "ord-001", "code": "A1-892", "fee": 85, "distanceKm": 1.2, "etaMinutes": 12, "status": "available", "merchant": { "name": "...", "lat": 25.0, "lng": 121.5 }, "customer": { "name": "...", "phone": "...", "lat": 25.01, "lng": 121.53 }, "dropoff": { "name": "資工系館" } } ] }`
  - 欄位說明：`dropoff.name` 直接來自買家下單的 `deliveryLocation.name`；目前前端不送 lat/lng。

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

- （可選）`POST /delivery/:id/location` (auth: deliverer)
  - body: `{ "lat": 25.0, "lng": 121.5, "heading": 180 }`

## 錯誤格式
```json
{ "message": "invalid credentials", "code": "auth.invalid" }
```
常見錯誤碼：`auth.invalid`, `auth.forbidden`, `order.not_found`, `order.conflict`, `validation.failed`, `server.error`

## 資料模型摘要
- User: `{ id, email, role }`
- Restaurant: `{ id, name, imageUrl?, address?, phone? }`
- MenuItem: `{ id, name, description, price, sizes[], spicinessOptions[] }`
- Order: `{ id, restaurantId, userId, items[], status, etaMinutes?, placedAt, requestedTime?, deliveryLocation{name}, notes? }`
- DeliveryTask（可共用 order id）：`{ id, delivererId?, status, fee, distanceKm, etaMinutes?, merchant{}, customer{}, dropoff{}, history[] }`

## 修改紀錄
- 調整成功/錯誤回應格式說明為統一 `{ data }` / `{ message, code }`，明確標示時間需 ISO8601（可含毫秒），並強調下單的 `menuItemId` 為必填；配合前端解碼改寫。
- 下單/回傳的 `deliveryLocation` 移除 `lat/lng`（前端只送名稱），請後端同步調整序列化/驗證；配送端 `dropoff` 若無座標也可只回傳名稱。
- 下單 items 僅接受 `menuItemId`（不再傳 name）；後端請依 id 取菜單資料，避免因名稱變動/重複導致錯位。
- 新增外送員綁定欄位 `delivererId`，並擴充外送員相關 API：包含任務詳情 `GET /delivery/:id`、歷史紀錄 `GET /delivery/history`、收益統計 `GET /delivery/earnings` 與通知輪詢 `GET /delivery/notifications` 等，對應 OpenAPI 中新增的 `DeliveryNotification` 和 `EarningsSummary` schema。
