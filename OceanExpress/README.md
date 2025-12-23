# OceanExpress (iOS)

SwiftUI 前端，支援買家 / 外送員 / 餐廳三角色，串接 `https://ocean-express-backend.onrender.com`。

## 主要功能
- 買家：餐廳列表、菜單、下單、歷史訂單與評分。
- 外送員：任務清單、接單/更新狀態、導航、位置回報。
- 餐廳：訂單管理、狀態更新、菜單維護、報表與評論查看。

## 開發環境
- Xcode 15+（已在 26.1 SDK 測試）
- iOS 17+ target
- SwiftUI + Combine + MapKit

## 環境變數 / 設定
- API base：`https://ocean-express-backend.onrender.com`（寫在 `APIClient.swift`）。
- 登入後的 token 會存 `UserDefaults`，啟動時自動帶入。
- 外送地點：呼叫 `/delivery/locations`，支援分類；未回資料時有 fallback。

## 建置/執行
1. 開啟 `OceanExpress.xcodeproj`。
2. 選擇 `OceanExpress` scheme，目標裝置 Simulator 或實機。
3. Run (`⌘R`)。

## 注意事項
- 已移除所有 demo/mock 資料，功能全走後端 API。
- 登出會清除 token 並清空密碼欄位（帳號會保留）。***
