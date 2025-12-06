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
        }
    }

    private func performLogout() {
        UserDefaults.standard.removeObject(forKey: "auth_token")
        withAnimation { isLoggedIn = false }
    }

    private func switchRole(to newRole: AuthRole) {
        withAnimation {
            role = newRole
            isLoggedIn = true
        }
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
                DemoConfig.setDemo(enabled: true)
                isLoading = false
                withAnimation { isLoggedIn = true }
            }
            return
        } else {
            DemoConfig.setDemo(enabled: false)
        }

        Task {
            do {
                let result = try await AuthAPI.login(email: email, password: password)
                DemoConfig.setDemo(enabled: false)
                UserDefaults.standard.set(result.token, forKey: "auth_token")
                isLoading = false
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
            HomeView(onLogout: performLogout, onSwitchRole: { switchRole(to: .deliverer) })
        case .deliverer:
            DelivererModule(onLogout: performLogout, onSwitchRole: { switchRole(to: .customer) })
        case .restaurant:
            RestaurantComingSoonView()
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
struct RestaurantComingSoonView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                Text("餐廳端介面製作中")
                    .font(.title3.weight(.semibold))
                Text("敬請期待！")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("餐廳端")
        }
    }
}
