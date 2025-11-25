//
//  LoginView.swift
//  OceanExpress
//
//  Created by 呂翰昇 on 2025/10/13.
//

import SwiftUI

// MARK: - DTOs for Auth API (top-level to avoid @MainActor isolation in Swift 6)
struct LoginReq: Codable { let email: String; let password: String }
struct APIUser: Codable { let id: Int; let email: String }
struct LoginResp: Codable { let token: String; let user: APIUser }

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
                        // App Title
                        Text("Ocean Express")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.tint)
                            .padding(.top, 60)

                        // Email Field
                        TextField("Email", text: $email, prompt: Text("Email"))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal, 32)

                        // Password Field
                        SecureField("Password", text: $password, prompt: Text("Password"))
                            .textContentType(.password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal, 32)
                            .submitLabel(.go)
                            .onSubmit { login() }

                        // Role Selector
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

                        // Login Button
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

                        // Register Link
                        HStack {
                            Text("Don't have an account?")
                                .foregroundColor(.gray)
                            NavigationLink {
                                RegisterView()
                            } label: {
                                Text("Sign Up")
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
                Alert(title: Text("Login Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func performLogout() {
        UserDefaults.standard.removeObject(forKey: "auth_token")
        withAnimation { isLoggedIn = false }
    }

    private func handleSwitchRole() {
        performLogout()
        role = .customer
    }

    func login() {
        guard !email.isEmpty, !password.isEmpty else {
            alertMessage = "Please enter both email and password."
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

        func showError(_ msg: String) {
            DispatchQueue.main.async {
                alertMessage = msg
                showAlert = true
            }
        }
    }

    @ViewBuilder
    private func roleDestination(_ role: AuthRole) -> some View {
        switch role {
        case .customer:
            HomeView(onLogout: performLogout, onSwitchRole: handleSwitchRole)
        case .deliverer:
            DelivererModule(onLogout: performLogout, onSwitchRole: handleSwitchRole)
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
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
            Alert(title: Text("註冊結果"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func register() {
        guard !name.isEmpty, !email.isEmpty, !password.isEmpty, !confirmPassword.isEmpty else {
            alertMessage = "請填寫所有欄位"
            showAlert = true
            return
        }
        guard password == confirmPassword else {
            alertMessage = "兩次輸入的密碼不一致"
            showAlert = true
            return
        }

        isLoading = true
        Task {
            do {
                try await AuthAPI.register(name: name, email: email, password: password)
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
