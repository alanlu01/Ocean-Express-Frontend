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
  - body: `{ "name": "Demo User", "email": "user@example.com", "password": "...", "phone": "09xxxxxxxx" }`
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
    {
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
          "imageUrl": null
        }
      ]
    }
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
  - 前端 demo 仍會內建一組分類資料，若後端有回傳則覆蓋使用。
- 推播/即時：建議新增 SSE / WebSocket 端點 `GET /orders/stream`（依 user token 僅推播本人訂單），事件：`order.updated` payload 同 `GET /orders/:id` 的 data；或提供 `/orders/:id/stream` 針對單筆訂單推播狀態變化。

## 外送員（Deliverer）
- `GET /delivery/available` (auth: deliverer)
  - 回傳可接單列表（座標若有可傳，若無則僅回傳名稱）：  
    `{ "data": [ { "id": "ord-001", "code": "A1-892", "fee": 85, "distanceKm": 1.2, "etaMinutes": 12, "status": "available", "merchant": { "name": "...", "lat": 25.0, "lng": 121.5 }, "customer": { "name": "...", "phone": "...", "lat": 25.01, "lng": 121.53 }, "dropoff": { "name": "資工系館" } } ] }`
  - 欄位說明：`dropoff.name` 直接來自買家下單的 `deliveryLocation.name`；若前端送出座標則回傳即可（來源為預設地點清單）。

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
- Restaurant: `{ id, name, imageUrl?, address?, phone?, rating? }`
- MenuItem: `{ id, name, description, price<int>, sizes[], spicinessOptions[], allergens[], tags[] }`
- Order: `{ id, restaurantId, userId, items[], status, etaMinutes?, placedAt, requestedTime?, deliveryLocation{name,lat?,lng?}, deliveryFee<int>?, totalAmount<int>?, notes?, rating? }`
- DeliveryTask（可共用 order id）：`{ id, riderId, status, merchant{}, customer{}, history[], fee<int> }`

## 缺少 / 待實作（前端已串接或預留）
- `POST /orders/:id/rating`：買家送達後評分（分數 1-5 + comment），需儲存並回傳於 `GET /orders/:id`、`GET /orders?status=history`。
- `GET /delivery/locations`：回傳預設外送地點清單（含 name/lat/lng），支援分類；目前前端內建 demo，若後端提供則覆蓋使用。
- `GET /orders/stream`（SSE/WebSocket）：依使用者 token 推播訂單狀態變更，事件 payload 同 `GET /orders/:id`；若無法即時，請提供最小化輪詢 ETag/Last-Modified。
- 菜單欄位 `allergens`, `tags` 需在 `GET /restaurants/:id/menu` 回傳；目前不再使用 `drinkOptions` / `drinkOption*`。
- 下單 payload 已包含 `deliveryFee`、`totalAmount`，請驗證/落庫並於訂單詳情回傳（皆為整數）。
- 餐廳評分 `rating` 欄位請於列表/詳情回傳。
- `GET /restaurants/:id/reviews`：回傳餐廳評論列表（rating/comment/userName/createdAt），前端菜單頁會顯示評論區塊。
- 狀態枚舉對齊：`available, assigned, en_route_to_pickup, picked_up, delivering, delivered, cancelled`（請提供現有狀態與映射，如有 `preparing/completed`）。
- 訂單詳情：回傳 `deliveryFee/totalAmount/riderName/riderPhone/statusHistory[{status,timestamp}]`，`items.price`；列表 `GET /orders?status=` 至少帶 `totalAmount`（可選 `deliveryFee`）。
- 下單計價：建議由後端依菜單價 × 數量 + deliveryFee 計算並寫入 `totalAmount`；如採前端計算也請驗證。
- 外送員聯絡：請提供 `riderName/riderPhone` 欄位（含權限控管）。

## 修改紀錄
- 保持回應格式 `{ data }` / `{ message, code }`，時間需 ISO8601（可含毫秒）；`menuItemId` 仍為下單必填。
- 菜單新增 `allergens`, `tags` 欄位，移除 `drinkOptions` 與相關欄位。
- 下單 payload 目前僅送 `menuItemId/size/spiciness/addDrink/quantity`，移除 `drinkOption*`；保留 `deliveryFee/totalAmount`（整數），`deliveryLocation` 可含 lat/lng。
- 訂單詳情回傳 `deliveryFee/totalAmount/riderName/riderPhone/statusHistory/items.price`，新增 `POST /orders/:id/rating`。
- 建議新增 `GET /delivery/locations`（預設地點清單、分類）與 SSE/WebSocket `GET /orders/stream` 推播訂單狀態。
- 2025-01-06：合併 api.md 到本檔，新增註冊 phone 欄位說明，補充待實作清單。
- 2025-01-07：金額改整數（元）、餐廳新增 rating 欄位、地點回傳支援分類且保留前端 demo 清單，移除飲料選項相關欄位。
