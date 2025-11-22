# OceanExpress 後端 API 規格（Rust/axum + MongoDB）

面向三種角色：買家（customer）、外送員（deliverer）、餐廳（restaurant）。認證採 JWT，所有受保護路由需 `Authorization: Bearer <token>`。時間一律用 ISO8601 UTC。

## 架構建議
- axum + tokio + hyper，資料存 MongoDB（集合可用 `users`, `restaurants`, `menu_items`, `orders`, `delivery_tasks`）。
- 認證：bcrypt 儲存密碼、JWT 內含 `sub`(userId) 與 `role`。
- 序列化：serde；非同步：futures/tokio。

## 通用欄位
- `id`: string (Mongo ObjectId)
- `role`: `customer | deliverer | restaurant`
- 訂單狀態（前後端一致）：`available`（待接）、`assigned`、`en_route_to_pickup`、`picked_up`、`delivering`、`delivered`、`cancelled`

## 認證
- `POST /auth/login`
  - body: `{ "email": "...", "password": "..." }`
  - 200: `{ "token": "<jwt>", "user": { "id": "...", "email": "...", "role": "customer|deliverer|restaurant" } }`
  - 401: `{ "message": "invalid credentials" }`

## 餐廳與菜單
- `GET /restaurants`
  - 200: `{ "data": [ { "id": "...", "name": "...", "imageUrl": "..." } ] }`

- `GET /restaurants/:id`
  - 200: `{ "id": "...", "name": "...", "imageUrl": "...", "address": "...", "phone": "..." }`

- `GET /restaurants/:id/menu`
  - 200: `{ "items": [ { "id": "...", "name": "...", "description": "...", "price": 120, "sizes": ["Regular"], "spicinessOptions": ["Mild","Medium","Hot"], "imageUrl": "..." } ] }`

（餐廳端後台可再補 CRUD，但前端目前僅讀取。）

## 買家訂單／購物車
前端本地維護購物車，下單時傳整筆。

- `POST /orders`
  - auth: customer
  - body:
    ```json
    {
      "restaurantId": "...",
      "items": [
        { "menuItemId": "...", "size": "Regular", "spiciness": "Mild", "addDrink": true, "quantity": 2 }
      ],
      "deliveryLocation": { "name": "資工系館" },
      "notes": "請在警衛室交付",
      "requestedTime": "2025-11-23T10:30:00Z"
    }
    ```
  - 201: `{ "id": "...", "status": "available", "etaMinutes": 20 }`

- `GET /orders?status=active|history`
  - auth: customer
  - 200: `{ "data": [ { "id": "...", "restaurantName": "...", "status": "delivering", "etaMinutes": 8, "placedAt": "..." } ] }`

- `GET /orders/:id`
  - 200: 詳細訂單，含 items、狀態時間戳。

- `PATCH /orders/:id/cancel`
  - 200: `{ "status": "cancelled" }`

## 外送員（Deliverer）
- `GET /delivery/available`
  - auth: deliverer
  - 200: `{ "data": [ { "id": "...", "code": "A1-892", "fee": 85, "distanceKm": 1.2, "etaMinutes": 12, "merchant": { "name": "...", "address": "...", "lat": 25.0, "lng": 121.5 }, "customer": { "name": "...", "phone": "...", "address": "..." } } ] }`

- `POST /delivery/:id/accept`
  - auth: deliverer
  - 200: `{ "status": "assigned" }`

- `GET /delivery/active`
  - 200: 配送員目前的任務列表（同 Deliverer App 的 Active/History 視圖）。

- `PATCH /delivery/:id/status`
  - auth: deliverer
  - body: `{ "status": "en_route_to_pickup|picked_up|delivering|delivered|cancelled" }`
  - 200: `{ "status": "<status>" }`

- （可選）`POST /delivery/:id/location`
  - auth: deliverer
  - body: `{ "lat": 25.0, "lng": 121.5, "heading": 180 }`

## 角色／設定
- `GET /me`
  - 回傳使用者基本資料與角色。
- `POST /auth/logout`（如需使 token 失效，可維護黑名單或旋轉密鑰）

## 回傳格式與錯誤
- 成功：200/201，包在 `{ data: ... }` 或直接物件，需一致。
- 失敗：4xx/5xx，`{ "message": "...", "code": "..." }`

## 需要前後端對齊的枚舉
- Order/Delivery 狀態：`available, assigned, en_route_to_pickup, picked_up, delivering, delivered, cancelled`
- 角色：`customer, deliverer, restaurant`

## 後端工作項目列表
1) 認證：login 發 JWT，middleware 驗證並注入使用者與角色。  
2) 餐廳/菜單查詢：公共 GET，Mongo 建索引（name / restaurantId）。  
3) 買家下單：`POST /orders` 產生初始 `available` 狀態訂單，寫入 `orders` 集合；可同時寫 `delivery_tasks`（同 id）。  
4) 買家查詢/取消：`GET /orders`, `GET /orders/:id`, `PATCH /orders/:id/cancel`。  
5) 外送員流程：`GET /delivery/available`（篩選 status=available）、`POST /delivery/:id/accept`（原子更新 status=assigned, riderId）、`PATCH /delivery/:id/status` 依流程更新；`GET /delivery/active` 回傳該外送員的 active/history。  
6) （可選）定位上報與推播：可先 stub，前端目前未接即時通訊。  

以上為 RESTful 介面草案，足以支援現有前端頁面（登入、餐廳列表/菜單、購物車下單、訂單狀態、外送員任務流程）。*** End Patch*** Wait patch end? need proper format. Apply patch? We used apply_patch with file addition content. Need ensure end "*** End Patch".done ok. Should confirm file creation. Let's proceed. Need ensure instructions compliance. No more modifications. Provide summary. No tests. final message summarize doc created path. need mention dev branch merge done earlier etc. No more actions. final response include file path. concise. End. Need mention policy approval never ensures not ask. Done. Mention restful spec. Done. Need suggest next steps maybe review. Final message. Need to mention created backend-api.md. Provide instruction reading. Provide restful enumerations. finalize. Ende.】.【
