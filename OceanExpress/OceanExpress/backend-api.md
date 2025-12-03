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

- `POST /delivery/:id/accept` (auth: deliverer)
  - 200: `{ "data": { ...DeliveryTask 同上..., "status": "assigned" } }`

- `GET /delivery/active` (auth: deliverer)
  - 200: 回傳該外送員的任務列表（包含已完成、已取消，前端會自行區分 active/history）。

- `PATCH /delivery/:id/status` (auth: deliverer)
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
- DeliveryTask（可共用 order id）：`{ id, riderId, status, merchant{}, customer{}, history[] }`

## 修改紀錄
- 調整成功/錯誤回應格式說明為統一 `{ data }` / `{ message, code }`，明確標示時間需 ISO8601（可含毫秒），並強調下單的 `menuItemId` 為必填；配合前端解碼改寫。
- 下單/回傳的 `deliveryLocation` 移除 `lat/lng`（前端只送名稱），請後端同步調整序列化/驗證；配送端 `dropoff` 若無座標也可只回傳名稱。
- 下單 items 僅接受 `menuItemId`（不再傳 name）；後端請依 id 取菜單資料，避免因名稱變動/重複導致錯位。
