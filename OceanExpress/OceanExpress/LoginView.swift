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

struct LoginView: View {
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isLoggedIn = false

    var body: some View {
        Group {
            if isLoggedIn {
                HomeView()
                    .transition(.slide)
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

                    // Login Button
                    Button(action: login) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Log In")
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
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Login Error"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    @MainActor
    private func decodeLoginResp(_ data: Data) throws -> LoginResp {
        try JSONDecoder().decode(LoginResp.self, from: data)
    }

    func login() {
        guard !email.isEmpty, !password.isEmpty else {
            alertMessage = "Please enter both email and password."
            showAlert = true
            return
        }

        isLoading = true

        let demoMode = true // 將來可改成 false 或偵測環境變數

        if demoMode {
            // 嘗試連線前先檢查是否能 reach server
            let demoUser = APIUser(id: 0, email: email.isEmpty ? "demo@oceanexpress.app" : email)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                alertMessage = "⚠️ Server unavailable — entering demo mode"
                showAlert = true
                UserDefaults.standard.set("demo-token", forKey: "auth_token")
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
}

#Preview {
    LoginView()
}
