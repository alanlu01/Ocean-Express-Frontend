import SwiftUI

struct CustomerOrderDetailView: View {
    @EnvironmentObject private var orderStore: CustomerOrderStore
    @Environment(\.openURL) private var openURL
    let order: CustomerOrder

    @State private var detail: OrderAPI.OrderDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var ratingScore: Int = 5
    @State private var ratingComment: String = ""
    @State private var isSubmittingRating = false

    private let timeline: [(CustomerOrderStatus, String)] = [
        (.preparing, "已下單"),
        (.assigned, "餐廳備餐/待分配"),
        (.pickedUp, "外送員取餐"),
        (.delivering, "配送中"),
        (.delivered, "已送達")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                timelineSection
                itemsSection
                notesSection
                contactSection
                ratingSection
            }
            .padding(.horizontal)
            .padding(.top, 12)
        }
        .navigationTitle("訂單詳情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
        .alert("載入失敗", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("關閉", role: .cancel) { }
            Button("重試") { Task { await loadDetail() } }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.title)
                        .font(.title3.weight(.semibold))
                    Text(status.displayText)
                        .font(.subheadline)
                        .foregroundStyle(status == .delivered ? Color.green : Color.accentColor)
                }
                Spacer()
                if let total = detail?.totalAmount ?? order.totalAmount {
                    Text("$\(total)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
            }
            if let remaining = remainingMinutes, status != .delivered {
                Label("預估剩餘 \(remaining) 分鐘", systemImage: "timer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let placed = detail?.placedAt ?? order.placedAt
                Label(placed.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("進度")
                .font(.headline)
            VStack(spacing: 12) {
                ForEach(Array(timeline.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .center, spacing: 12) {
                        VStack {
                            Circle()
                                .fill(timelineStatus(for: item.0) ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: 12, height: 12)
                            if index < timeline.count - 1 {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 2, height: 28)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.1)
                                .font(.subheadline)
                                .foregroundStyle(timelineStatus(for: item.0) ? Color.primary : Color.secondary)
                            if let ts = statusTime(for: item.0) {
                                Text(ts, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("餐點明細")
                .font(.headline)
            if let items = detail?.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(item.size ?? "") \(item.spiciness ?? "")\(item.addDrink == true ? " • 加飲料" : "")".trimmingCharacters(in: .whitespaces))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("數量 \(item.quantity ?? 1)")
                            if let price = item.price {
                                Text("單價 $\(price)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            } else {
                Text("尚無餐點資訊，請稍後重試。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let fee = detail?.deliveryFee {
                HStack {
                    Text("外送費")
                    Spacer()
                    Text("$\(fee)")
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("送達資訊")
                .font(.headline)
            let locationName = detail?.deliveryLocation?.name ?? order.location
            if !locationName.isEmpty {
                Label(locationName, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
            }
            if let note = detail?.notes, !note.isEmpty {
                Label(note, systemImage: "text.bubble")
                    .font(.subheadline)
            }
            if let requested = detail?.requestedTime {
                Label("期望送達 \(requested.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("聯繫外送員")
                .font(.headline)
            let phone = detail?.riderPhone ?? order.riderPhone
            if let phone, !phone.isEmpty, let telURL = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                Button {
                    openURL(telURL)
                } label: {
                    Label("撥打外送員 \(phone)", systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Text("尚未取得外送員電話，請稍後再試。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("評分")
                .font(.headline)
            if status == .delivered {
                if let existing = detail?.rating ?? order.rating {
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { idx in
                            Image(systemName: idx <= existing.score ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                        }
                        if let comment = existing.comment, !comment.isEmpty {
                            Text(comment)
                                .font(.subheadline)
                        }
                    }
                } else {
                    starPicker
                    TextField("留下評論（選填）", text: $ratingComment, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await submitRating() }
                    } label: {
                        if isSubmittingRating {
                            ProgressView()
                        } else {
                            Text("送出評分")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmittingRating)
                }
            } else {
                Text("送達後即可評分。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var starPicker: some View {
        HStack {
            ForEach(1...5, id: \.self) { score in
                Image(systemName: score <= ratingScore ? "star.fill" : "star")
                    .foregroundColor(.yellow)
                    .font(.title2)
                    .onTapGesture { ratingScore = score }
            }
        }
    }

    private var status: CustomerOrderStatus {
        if let detailStatus = detail?.status, let mapped = CustomerOrderStatus(rawValue: detailStatus) {
            return mapped
        }
        return order.status
    }

    private var remainingMinutes: Int? {
        let eta = detail?.etaMinutes ?? order.etaMinutes
        guard let eta else { return nil }
        let base = detail?.placedAt ?? order.placedAt
        let etaDate = base.addingTimeInterval(Double(eta) * 60)
        return max(0, Int(ceil(etaDate.timeIntervalSinceNow / 60)))
    }

    private func timelineStatus(for target: CustomerOrderStatus) -> Bool {
        guard status != .cancelled else { return false }
        let orderIndex = stageIndex
        guard let targetIndex = timeline.firstIndex(where: { $0.0 == target }) else { return false }
        return targetIndex <= orderIndex
    }

    private func statusTime(for target: CustomerOrderStatus) -> Date? {
        var historyDict: [CustomerOrderStatus: Date] = [:]
        detail?.statusHistory?.forEach { record in
            if let mapped = CustomerOrderStatus(rawValue: record.status), let ts = record.timestamp {
                historyDict[mapped] = ts
            }
        }
        historyDict[.preparing] = historyDict[.preparing] ?? (detail?.placedAt ?? order.placedAt)
        return historyDict[target]
    }

    private var stageIndex: Int {
        switch status {
        case .preparing, .available: return 0
        case .assigned, .enRouteToPickup: return 1
        case .pickedUp: return 2
        case .delivering: return 3
        case .delivered: return 4
        case .cancelled: return 0
        }
    }

    private func loadDetail() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if DemoConfig.isEnabled {
            let mock = OrderAPI.OrderDetail(
                id: order.id,
                restaurantName: order.title,
                status: order.status.rawValue,
                etaMinutes: order.etaMinutes,
                placedAt: order.placedAt,
                items: [
                    .init(name: "招牌便當", size: "大份", spiciness: "小辣", addDrink: true, quantity: 1, price: 120)
                ],
                deliveryLocation: .init(name: order.location.isEmpty ? "校園" : order.location, lat: nil, lng: nil),
                notes: "請在大門口交付",
                requestedTime: nil,
                deliveryFee: 20,
                totalAmount: 140,
                riderName: "王外送",
                riderPhone: "0900-000-000",
                statusHistory: nil,
                rating: nil
            )
            detail = mock
            orderStore.applyDetail(mock)
            return
        }

        do {
            let token = UserDefaults.standard.string(forKey: "auth_token")
            let data = try await OrderAPI.fetchOrderDetail(id: order.id, token: token)
            detail = data
            orderStore.applyDetail(data)
            if let rating = data.rating {
                ratingScore = rating.score
                ratingComment = rating.comment ?? ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitRating() async {
        guard status == .delivered else { return }
        isSubmittingRating = true
        defer { isSubmittingRating = false }
        let rating = OrderAPI.OrderRating(score: ratingScore, comment: ratingComment.isEmpty ? nil : ratingComment)
        do {
            if !DemoConfig.isEnabled {
                let token = UserDefaults.standard.string(forKey: "auth_token")
                try await OrderAPI.submitRating(orderId: order.id, score: ratingScore, comment: rating.comment, token: token)
            }
            detail?.rating = rating
            orderStore.updateRating(orderId: order.id, rating: rating)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
