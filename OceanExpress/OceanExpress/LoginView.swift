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

// Fallback placeholder to fix "Cannot find 'HomeView' in scope" during compilation
// Remove this when the real `HomeView` file is included in the target.

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



struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoggedIn = false
    @State private var role: AuthRole = .customer

    var body: some View {
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
                        Button("Sign Up") {
                            // 之後導向註冊頁
                        }
                        .fontWeight(.semibold)
                    }
                    .padding(.top, 12)

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

    @MainActor
    private func decodeLoginResp(_ data: Data) throws -> LoginResp {
        try JSONDecoder().decode(LoginResp.self, from: data)
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

        let demoMode = true // 將來可改成 true 或偵測環境變數

        if demoMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                alertMessage = "⚠️ Server unavailable — entering demo mode"
                showAlert = true
                UserDefaults.standard.set("demo-token", forKey: "auth_token")
                isLoading = false
                withAnimation { isLoggedIn = true }
            }
            return
        }

        let url = URL(string: "http://localhost:3000/auth/login")! // 部署後改為你的伺服器網址
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(LoginReq(email: email, password: password))

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async { isLoading = false }

            if let err = err {
                showError("Network error: \(err.localizedDescription)")
                return
            }
            guard let http = resp as? HTTPURLResponse, let data = data else {
                showError("No response from server")
                return
            }

            if (200..<300).contains(http.statusCode) {
                Task { @MainActor in
                    do {
                        let result = try decodeLoginResp(data)
                        UserDefaults.standard.set(result.token, forKey: "auth_token")
                        withAnimation { isLoggedIn = true }
                    } catch {
                        alertMessage = "Response parse error"
                        showAlert = true
                    }
                }
            } else {
                if let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String {
                    showError(msg)
                } else {
                    showError("Login failed (\(http.statusCode))")
                }
            }
        }.resume()

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
