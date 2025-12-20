//
//  LoginView.swift
//  OceanExpress
//
//  Created by 呂翰昇 on 2025/10/13.
//

import SwiftUI

// 使用者角色
enum AuthRole: String, CaseIterable, Identifiable {
    case customer
    case deliverer
    case restaurant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .customer: return "買家"
        case .deliverer: return "外送員"
        case .restaurant: return "餐廳"
        }
    }

    var icon: String {
        switch self {
        case .customer: return "person.crop.circle"
        case .deliverer: return "bicycle"
        case .restaurant: return "fork.knife.circle"
        }
    }
}

// MARK: - Login View
struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoggedIn = false
    @State private var role: AuthRole = .customer
    @State private var serverRole: AuthRole? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoggedIn {
                    roleDestination(role)
                        .transition(AnyTransition.slide)
                } else {
                    VStack(spacing: 24) {
                        Text("Ocean Express")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.tint)
                            .padding(.top, 60)

                        TextField("電子郵件", text: $email, prompt: Text("請輸入 Email"))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal, 32)

                        SecureField("密碼", text: $password, prompt: Text("請輸入密碼"))
                            .textContentType(.password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal, 32)
                            .submitLabel(.go)
                            .onSubmit { login() }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("登入身分").font(.headline)
                            HStack(spacing: 12) {
                                ForEach(AuthRole.allCases) { option in
                                    Button {
                                        role = option
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: option.icon)
                                            Text(option.title)
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .background(role == option ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                                        .foregroundStyle(role == option ? Color.accentColor : Color.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(role == option ? Color.accentColor : Color.clear, lineWidth: 1)
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 32)

                        Button(action: login) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Text("以 \(role.title) 登入")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isLoading)
                        .padding(.horizontal, 32)

                        HStack {
                            Text("還沒有帳號？")
                                .foregroundColor(.gray)
                            NavigationLink {
                                RegisterView()
                            } label: {
                                Text("去註冊")
                                    .fontWeight(.semibold)
                            }
                        }

                        Spacer()
                    }
                }
            }
            .tint(.accentColor)
            .accentColor(.accentColor)
            .animation(.default, value: isLoggedIn)
            .alert(isPresented: $showAlert) {
                Alert(title: Text("登入訊息"), message: Text(alertMessage), dismissButton: .default(Text("確定")))
            }
            .task {
                await restoreSessionIfNeeded()
            }
        }
    }

    private func performLogout() {
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "auth_role")
        UserDefaults.standard.removeObject(forKey: "auth_user_id")
        UserDefaults.standard.removeObject(forKey: "restaurant_id")
        NotificationManager.shared.disablePushForSession()
        withAnimation { isLoggedIn = false }
    }

    private func restoreSessionIfNeeded() async {
        guard !isLoggedIn else { return }
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: "auth_token"), !token.isEmpty else { return }
        if let savedRole = defaults.string(forKey: "auth_role"), let restored = AuthRole(rawValue: savedRole) {
            role = restored
            serverRole = restored
        }
        NotificationManager.shared.enablePushForSession()
        // 補傳推播裝置資訊（若尚未上傳）
        if NotificationManager.shared.apnsToken != nil {
            NotificationManager.shared.registerDeviceIfNeeded(
                userId: defaults.string(forKey: "auth_user_id"),
                role: defaults.string(forKey: "auth_role"),
                restaurantId: defaults.string(forKey: "restaurant_id"),
                authToken: token
            )
        }
        withAnimation { isLoggedIn = true }
    }

    private func attemptSwitchRole(to newRole: AuthRole) {
        // 買家/外送員可互換；餐廳介面需餐廳帳號或 Demo
        let allowedRestaurant = DemoConfig.isEnabled || serverRole == .restaurant
        if newRole == .restaurant && !allowedRestaurant {
            alertMessage = "此帳號無餐廳權限，無法進入餐廳介面。"
            showAlert = true
            return
        }
        withAnimation { role = newRole; isLoggedIn = true }
    }

    func login() {
        guard !email.isEmpty, !password.isEmpty else {
            alertMessage = "請輸入 Email 與密碼"
            showAlert = true
            return
        }

        isLoading = true

        let isDemoLogin = email.lowercased() == "demo" && password == "demo"

        if isDemoLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                alertMessage = "⚠️ Demo 模式啟用"
                showAlert = true
                UserDefaults.standard.set("demo-token", forKey: "auth_token")
                UserDefaults.standard.set(role.rawValue, forKey: "auth_role")
                UserDefaults.standard.set("demo-user", forKey: "auth_user_id")
                DemoConfig.setDemo(enabled: true)
                serverRole = role
                NotificationManager.shared.enablePushForSession()
                isLoading = false
                withAnimation { isLoggedIn = true }
            }
            return
        } else {
            DemoConfig.setDemo(enabled: false)
            serverRole = nil
            UserDefaults.standard.removeObject(forKey: "auth_role")
            UserDefaults.standard.removeObject(forKey: "auth_user_id")
            UserDefaults.standard.removeObject(forKey: "restaurant_id")
        }

        Task {
            do {
                let result = try await AuthAPI.login(email: email, password: password)
                DemoConfig.setDemo(enabled: false)
                let backendRole = AuthRole(rawValue: result.user.role) ?? .customer
                serverRole = backendRole
                UserDefaults.standard.set(result.token, forKey: "auth_token")
                UserDefaults.standard.set(backendRole.rawValue, forKey: "auth_role")
                UserDefaults.standard.set(result.user.id, forKey: "auth_user_id")
                if let rid = result.user.restaurantId, !rid.isEmpty {
                    UserDefaults.standard.set(rid, forKey: "restaurant_id")
                } else {
                    UserDefaults.standard.removeObject(forKey: "restaurant_id")
                }
                NotificationManager.shared.enablePushForSession()
                let selected = role
                switch backendRole {
                case .restaurant:
                    if selected != .restaurant {
                        alertMessage = "此帳號角色為「餐廳」，已切換。"
                        showAlert = true
                    }
                    role = .restaurant
                case .deliverer:
                    if selected != .deliverer {
                        alertMessage = "此帳號角色為「外送員」，已切換。"
                        showAlert = true
                    }
                    role = .deliverer
                case .customer:
                    // 買家帳號允許在買家 / 外送員介面之間切換
                    if selected == .restaurant {
                        alertMessage = "此帳號無餐廳權限，已切換為買家。"
                        showAlert = true
                        role = .customer
                    } else {
                        role = selected
                    }
                }
                isLoading = false
                if NotificationManager.shared.apnsToken != nil {
                    NotificationManager.shared.registerDeviceIfNeeded(userId: result.user.id, role: backendRole.rawValue, restaurantId: result.user.restaurantId, authToken: result.token)
                }
                withAnimation { isLoggedIn = true }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private func roleDestination(_ role: AuthRole) -> some View {
        switch role {
        case .customer:
            HomeView(onLogout: performLogout, onSwitchRole: { attemptSwitchRole(to: .deliverer) })
        case .deliverer:
            DelivererModule(onLogout: performLogout, onSwitchRole: { attemptSwitchRole(to: .customer) })
        case .restaurant:
            RestaurantModule(onLogout: performLogout, onSwitchRole: { attemptSwitchRole(to: .customer) })
        }
    }
}

#Preview {
    LoginView()
}

// MARK: - Register View
struct RegisterView: View {
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""

    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(header: Text("基本資料")) {
                    TextField("姓名", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("電子郵件", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("電話（09xxxxxxxx）", text: $phone)
                        .keyboardType(.numberPad)
                    SecureField("密碼", text: $password)
                    SecureField("再次輸入密碼", text: $confirmPassword)
                }

                Section {
                    Button {
                        register()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("建立帳號")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(isLoading)
                    .listRowSeparator(.hidden)
                }
            }
            .padding(.top, 12)
        }
        .navigationTitle("註冊")
        .alert(isPresented: $showAlert) {
            Alert(title: Text("註冊結果"), message: Text(alertMessage), dismissButton: .default(Text("好的")))
        }
    }

    private func register() {
        guard !name.isEmpty, !email.isEmpty, !phone.isEmpty, !password.isEmpty, !confirmPassword.isEmpty else {
            alertMessage = "請填寫所有欄位"
            showAlert = true
            return
        }
        guard password == confirmPassword else {
            alertMessage = "兩次輸入的密碼不一致"
            showAlert = true
            return
        }
        guard phone.range(of: "^09\\d{8}$", options: .regularExpression) != nil else {
            alertMessage = "電話格式需為 09 開頭的 10 碼數字"
            showAlert = true
            return
        }

        isLoading = true
        Task {
            do {
                try await AuthAPI.register(name: name, email: email, password: password, phone: phone)
                DispatchQueue.main.async {
                    isLoading = false
                    alertMessage = "註冊成功，請以新帳號登入。"
                    showAlert = true
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}

// MARK: - Restaurant Placeholder View
// 已移除占位頁，改為 RestaurantModule
