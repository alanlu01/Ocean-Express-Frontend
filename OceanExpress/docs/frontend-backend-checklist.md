# OceanExpress 前後端功能與 API 對照檢查表

此文件列出目前前端已實作的流程、依賴的後端端點與欄位，方便前後端共同確認。如有欄位/行為與後端不符，請調整後端或通知前端更新。

## 認證 / 推播
- `POST /auth/login` → 回傳 `{ data:{ token, user:{ id, email, role, restaurantId? } } }`；前端持久化 `auth_token/auth_role/auth_user_id/restaurant_id`，重開 App 不會自動登出。
- 推播註冊：App 啟動向 APNs 取得 device token；登入後呼叫 `POST /push/register`（Header 帶 Bearer），body：
  ```json
  { "token": "<apns_token>", "platform": "ios", "userId": "<auth_user_id>", "role": "<auth_role>", "restaurantId": "<restaurant_id?>" }
  ```
- 登出會清除上述持久化資料，不再上報。

## 買家端（Customer）
- 餐廳列表：`GET /restaurants`，需回 `{id,name,imageUrl?,rating?}`（rating 可為 number/int/string）。
- 餐廳菜單：`GET /restaurants/{id}/menu`，支援 `{data:{items:[...]}}` 或扁平 `[... ]`；欄位 `id,name,description,price<int>,sizes?,spicinessOptions?,allergens?,tags?,imageUrl?,isAvailable,sortOrder?`。
- 下單：`POST /orders`，body 帶 `deliveryLocation{name,lat?,lng?}`、`items[].menuItemId`，前端會送 `deliveryFee/totalAmount`（整數）。
- 訂單列表/詳情：`GET /orders?status=active|history`、`GET /orders/{id}`，需回 `etaMinutes,totalAmount,deliveryFee,rating?,items[],deliveryLocation`。
- 評分：`POST /orders/{id}/rating {score,comment?}`；列表/詳情顯示 rating。

## 餐廳端（Restaurant Admin）
- 訂單列表：`GET /restaurant/orders?status=active|history`（可選 `restaurantId`），每筆需含 `restaurantId`，欄位 `code,status,placedAt,etaMinutes,totalAmount,deliveryFee,customer{name,phone},items[{id,name,size,spiciness,quantity,price}]`。
- 訂單狀態更新：`PATCH /restaurant/orders/{id}/status {status}`（帶 Bearer）。
- 菜單 CRUD：
  - `GET /restaurant/menu` → `[menu items]`
  - `POST /restaurant/menu`、`PATCH /restaurant/menu/{id}`、`DELETE /restaurant/menu/{id}`
  - 欄位：`name,description,price<int>,sizes[],spicinessOptions[],allergens[],tags[],imageUrl?,isAvailable,sortOrder?,restaurantId?`
- 評論：`GET /restaurants/{id}/reviews` → `[{id?,userName?,rating<int>,comment?,createdAt?}]`；前端使用登入餐廳的 `restaurantId` 呼叫。

## 外送員端（Deliverer）
- 可接/進行中/歷史任務：`GET /delivery/available|active|history`，欄位：
  - `id,code,status,fee<int>,distanceKm<double>,etaMinutes<int>,canPickup?,notes?,merchant{name,lat?,lng?},customer{name?,phone?,email?},dropoff{name?,lat?,lng?}`
  - status 使用 snake_case：`available,assigned,en_route_to_pickup,picked_up,delivering,delivered,cancelled`
- 接單：`POST /delivery/{id}/accept`（接受空 JSON）。
- 更新狀態：`PATCH /delivery/{id}/status {status}`。
- 事故回報：`POST /delivery/{id}/incident {note}`。
- 騎手定位回報：**新加** `POST /delivery/{id}/location {lat,lng}`，前端每 ~10 秒對所有進行中任務上報一次。

## ETA / 距離計算（後端）
- 後端已在建單時用餐廳座標 + 收貨座標（haversine）計算 `distanceKm`、`etaMinutes`；需餐廳/收貨地有 lat/lng。
- 若需動態 ETA，後端可利用前端回報的騎手位置（/delivery/{id}/location）。

## 其他備註
- Demo 模式（`demo-token` 或 DEMO_MODE）只用本地假資料，不呼叫後端。
- 所有金額欄位均以整數元為單位。
- 時間欄位採 ISO8601（前端有多種解析容錯）。***
