import Foundation

class DataService: ObservableObject {
    static let shared = DataService()
    
    private let baseURL = "http://127.0.0.1:8767/api"
    private let session = URLSession.shared
    private var serverProcess: Process?
    private var progressTimer: Timer?
    
    @Published var currentUser: User?
    @Published var investmentRequests: [InvestmentRequest] = []
    @Published var summary: InvestmentSummary?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var cacheProgress = CacheProgress()
    
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let date = formatter.date(from: dateString) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
        return d
    }()
    
    private func ensureServerRunning(completion: @escaping (Bool) -> Void) {
        func checkHealth(attempt: Int) {
            guard attempt < 30 else {
                print("API server not responding after 30 attempts")
                completion(false)
                return
            }
            
            let healthURL = URL(string: "http://localhost:8767/api/health")!
            let request = URLRequest(url: healthURL, timeoutInterval: 2)
            
            session.dataTask(with: request) { [weak self] _, response, error in
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("API server ready (attempt \(attempt + 1))")
                    completion(true)
                    return
                }
                
                if attempt == 0 {
                    print("API server not running, starting it...")
                    self?.startAPIServer { success in
                        if success {
                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                                checkHealth(attempt: attempt + 1)
                            }
                        } else {
                            completion(false)
                        }
                    }
                } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        checkHealth(attempt: attempt + 1)
                    }
                }
            }.resume()
        }
        
        checkHealth(attempt: 0)
    }
    
    private func startAPIServer(completion: @escaping (Bool) -> Void) {
        let serverPath = "\(NSHomeDirectory())/Documents/projects/Planned-Investment-Governance/api_server.py"
        let serverDir = (serverPath as NSString).deletingLastPathComponent
        
        guard FileManager.default.fileExists(atPath: serverPath) else {
            print("Could not find api_server.py at: \(serverPath)")
            DispatchQueue.main.async { completion(false) }
            return
        }
        
        print("Starting API server from: \(serverPath)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3")
        process.arguments = [serverPath]
        process.currentDirectoryURL = URL(fileURLWithPath: serverDir)
        var env = ProcessInfo.processInfo.environment
        env["SNOWFLAKE_CONNECTION_NAME"] = "DemoAcct"
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        
        let logPath = "\(serverDir)/api_server.log"
        FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
        if let logHandle = FileHandle(forWritingAtPath: logPath) {
            process.standardOutput = logHandle
            process.standardError = logHandle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        
        do {
            try process.run()
            serverProcess = process
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                let healthURL = URL(string: "http://localhost:8767/api/health")!
                let request = URLRequest(url: healthURL, timeoutInterval: 2)
                
                self.session.dataTask(with: request) { _, response, _ in
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        print("API server started successfully")
                        DispatchQueue.main.async { completion(true) }
                    } else {
                        print("API server failed to start")
                        DispatchQueue.main.async { completion(false) }
                    }
                }.resume()
            }
        } catch {
            print("Failed to start API server: \(error)")
            DispatchQueue.main.async { completion(false) }
        }
    }
    
    func loadInitialDataInBackground() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.cacheProgress.message = "Starting API server..."
        }
        
        let healthURL = URL(string: "http://127.0.0.1:8767/api/health")!
        var serverStarted = false
        
        func tryConnect(attempt: Int) {
            guard attempt < 120 else {
                DispatchQueue.main.async {
                    self.lastError = "Failed to connect to API server"
                    self.isLoading = false
                    self.cacheProgress.message = "Connection failed"
                }
                return
            }
            
            DispatchQueue.main.async {
                if attempt > 0 && attempt % 4 == 0 {
                    self.cacheProgress.message = "Waiting for API server... (\(attempt / 2)s)"
                }
            }
            
            let request = URLRequest(url: healthURL, timeoutInterval: 2)
            
            self.session.dataTask(with: request) { [weak self] _, response, error in
                guard let self = self else { return }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    DispatchQueue.main.async {
                        self.cacheProgress.message = "Loading data..."
                    }
                    self.loadCurrentUser {}
                    self.loadSummary {}
                    self.loadInvestmentRequests {}
                } else {
                    if !serverStarted {
                        serverStarted = true
                        self.startAPIServer { _ in }
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        tryConnect(attempt: attempt + 1)
                    }
                }
            }.resume()
        }
        
        tryConnect(attempt: 0)
    }
    
    func loadInitialData(completion: @escaping () -> Void) {
        startProgressPolling()
        
        ensureServerRunning { [weak self] success in
            guard success, let self = self else {
                DispatchQueue.main.async {
                    self?.stopProgressPolling()
                    self?.lastError = "Failed to start API server"
                    completion()
                }
                return
            }
            
            self.waitForCacheReady {
                self.stopProgressPolling()
                self.loadAllData {
                    if self.summary == nil {
                        print("Data load failed, retrying...")
                        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                            self.loadAllData {
                                DispatchQueue.main.async { completion() }
                            }
                        }
                    } else {
                        DispatchQueue.main.async { completion() }
                    }
                }
            }
        }
    }
    
    private func loadAllData(completion: @escaping () -> Void) {
        let group = DispatchGroup()
        
        group.enter()
        self.loadCurrentUser { group.leave() }
        
        group.enter()
        self.loadSummary { group.leave() }
        
        group.enter()
        self.loadInvestmentRequests { group.leave() }
        
        group.notify(queue: .main) {
            completion()
        }
    }
    
    private func startProgressPolling() {
        DispatchQueue.main.async {
            self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.pollCacheProgress()
            }
        }
    }
    
    private func stopProgressPolling() {
        DispatchQueue.main.async {
            self.progressTimer?.invalidate()
            self.progressTimer = nil
        }
    }
    
    private func pollCacheProgress() {
        guard let url = URL(string: "\(baseURL)/cache/progress") else { return }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                DispatchQueue.main.async {
                    self?.cacheProgress.status = json["status"] as? String ?? "idle"
                    self?.cacheProgress.currentStep = json["current_step"] as? String ?? ""
                    self?.cacheProgress.stepsCompleted = json["steps_completed"] as? Int ?? 0
                    self?.cacheProgress.totalSteps = json["total_steps"] as? Int ?? 4
                    self?.cacheProgress.message = json["message"] as? String ?? ""
                }
            }
        }.resume()
    }
    
    private func waitForCacheReady(completion: @escaping () -> Void) {
        func checkProgress(attempt: Int) {
            guard attempt < 300 else {
                DispatchQueue.main.async { completion() }
                return
            }
            
            guard let url = URL(string: "\(baseURL)/cache/progress") else {
                DispatchQueue.main.async { completion() }
                return
            }
            
            session.dataTask(with: url) { [weak self] data, response, error in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                        checkProgress(attempt: attempt + 1)
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self?.cacheProgress.status = status
                    self?.cacheProgress.currentStep = json["current_step"] as? String ?? ""
                    self?.cacheProgress.stepsCompleted = json["steps_completed"] as? Int ?? 0
                    self?.cacheProgress.totalSteps = json["total_steps"] as? Int ?? 4
                    self?.cacheProgress.message = json["message"] as? String ?? ""
                }
                
                if status == "complete" {
                    DispatchQueue.main.async { completion() }
                } else {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                        checkProgress(attempt: attempt + 1)
                    }
                }
            }.resume()
        }
        
        checkProgress(attempt: 0)
    }
    
    func loadCurrentUser(completion: @escaping () -> Void) {
        guard let url = URL(string: "\(baseURL)/user") else {
            completion()
            return
        }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                defer { completion() }
                guard let self = self, let data = data else { return }
                
                do {
                    self.currentUser = try self.decoder.decode(User.self, from: data)
                } catch {
                    print("Error decoding user: \(error)")
                }
            }
        }.resume()
    }
    
    func loadSummary(completion: @escaping () -> Void = {}) {
        guard let url = URL(string: "\(baseURL)/summary") else {
            completion()
            return
        }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                defer { completion() }
                guard let self = self, let data = data else { return }
                
                do {
                    self.summary = try self.decoder.decode(InvestmentSummary.self, from: data)
                } catch {
                    print("Error decoding summary: \(error)")
                }
            }
        }.resume()
    }
    
    func loadInvestmentRequests(theater: String? = nil, industrySegment: String? = nil, quarter: String? = nil, status: String? = nil, completion: @escaping () -> Void = {}) {
        var urlString = "\(baseURL)/requests"
        var params: [String] = []
        if let theater = theater { params.append("theater=\(theater)") }
        if let industrySegment = industrySegment { params.append("industry_segment=\(industrySegment)") }
        if let quarter = quarter { params.append("quarter=\(quarter)") }
        if let status = status { params.append("status=\(status)") }
        if !params.isEmpty { urlString += "?" + params.joined(separator: "&") }
        
        guard let url = URL(string: urlString) else {
            completion()
            return
        }
        
        isLoading = true
        session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                defer { completion() }
                guard let self = self, let data = data else { return }
                
                do {
                    self.investmentRequests = try self.decoder.decode([InvestmentRequest].self, from: data)
                } catch {
                    print("Error decoding investment requests: \(error)")
                }
            }
        }.resume()
    }
    
    func loadRequestDetail(requestId: Int, completion: @escaping (InvestmentRequest?) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)") else {
            completion(nil)
            return
        }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, let data = data else {
                    completion(nil)
                    return
                }
                
                do {
                    let request = try self.decoder.decode(InvestmentRequest.self, from: data)
                    completion(request)
                } catch {
                    print("Error decoding request detail: \(error)")
                    completion(nil)
                }
            }
        }.resume()
    }
    
    func searchAccounts(query: String, completion: @escaping ([SFDCAccount]) -> Void) {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/accounts/search?q=\(encodedQuery)") else {
            completion([])
            return
        }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, let data = data else {
                    completion([])
                    return
                }
                
                do {
                    let accounts = try self.decoder.decode([SFDCAccount].self, from: data)
                    completion(accounts)
                } catch {
                    print("Error decoding accounts: \(error)")
                    completion([])
                }
            }
        }.resume()
    }
    
    func loadOpportunities(for accountId: String, completion: @escaping ([SFDCOpportunity]) -> Void) {
        guard let url = URL(string: "\(baseURL)/accounts/\(accountId)/opportunities") else {
            completion([])
            return
        }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, let data = data else {
                    completion([])
                    return
                }
                
                do {
                    let opps = try self.decoder.decode([SFDCOpportunity].self, from: data)
                    completion(opps)
                } catch {
                    print("Error decoding opportunities: \(error)")
                    completion([])
                }
            }
        }.resume()
    }
    
    func createRequest(title: String, accountId: String?, accountName: String?, investmentType: String?, amount: Double?, quarter: String?, justification: String?, expectedOutcome: String?, riskAssessment: String?, theater: String?, industrySegment: String?, completion: @escaping (Bool, Int?) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests") else {
            completion(false, nil)
            return
        }
        
        var body: [String: Any] = [
            "REQUEST_TITLE": title,
            "STATUS": "DRAFT"
        ]
        if let accountId = accountId { body["ACCOUNT_ID"] = accountId }
        if let accountName = accountName { body["ACCOUNT_NAME"] = accountName }
        if let investmentType = investmentType { body["INVESTMENT_TYPE"] = investmentType }
        if let amount = amount { body["REQUESTED_AMOUNT"] = amount }
        if let quarter = quarter { body["INVESTMENT_QUARTER"] = quarter }
        if let justification = justification { body["BUSINESS_JUSTIFICATION"] = justification }
        if let expectedOutcome = expectedOutcome { body["EXPECTED_OUTCOME"] = expectedOutcome }
        if let riskAssessment = riskAssessment { body["RISK_ASSESSMENT"] = riskAssessment }
        if let theater = theater { body["THEATER"] = theater }
        if let industrySegment = industrySegment { body["INDUSTRY_SEGMENT"] = industrySegment }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                    var requestId: Int? = nil
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        requestId = json["REQUEST_ID"] as? Int
                    }
                    self.loadInvestmentRequests()
                    self.loadSummary()
                    completion(true, requestId)
                } else {
                    completion(false, nil)
                }
            }
        }.resume()
    }
    
    func updateRequest(requestId: Int, title: String?, accountId: String?, accountName: String?, investmentType: String?, amount: Double?, quarter: String?, justification: String?, expectedOutcome: String?, riskAssessment: String?, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)") else {
            completion(false)
            return
        }
        
        var body: [String: Any] = [:]
        if let title = title { body["REQUEST_TITLE"] = title }
        if let accountId = accountId { body["ACCOUNT_ID"] = accountId }
        if let accountName = accountName { body["ACCOUNT_NAME"] = accountName }
        if let investmentType = investmentType { body["INVESTMENT_TYPE"] = investmentType }
        if let amount = amount { body["REQUESTED_AMOUNT"] = amount }
        if let quarter = quarter { body["INVESTMENT_QUARTER"] = quarter }
        if let justification = justification { body["BUSINESS_JUSTIFICATION"] = justification }
        if let expectedOutcome = expectedOutcome { body["EXPECTED_OUTCOME"] = expectedOutcome }
        if let riskAssessment = riskAssessment { body["RISK_ASSESSMENT"] = riskAssessment }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.loadInvestmentRequests()
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func deleteRequest(requestId: Int, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.loadInvestmentRequests()
                    self.loadSummary()
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func submitRequest(requestId: Int, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)/submit") else {
            completion(false, "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.loadInvestmentRequests()
                    self.loadSummary()
                    completion(true, nil)
                } else {
                    var errorMsg = "Unknown error"
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = json["error"] as? String {
                        errorMsg = err
                    }
                    completion(false, errorMsg)
                }
            }
        }.resume()
    }
    
    func withdrawRequest(requestId: Int, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)/withdraw") else {
            completion(false, "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.loadInvestmentRequests()
                    self.loadSummary()
                    completion(true, nil)
                } else {
                    var errorMsg = "Unknown error"
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = json["error"] as? String {
                        errorMsg = err
                    }
                    completion(false, errorMsg)
                }
            }
        }.resume()
    }
    
    func approveRequest(requestId: Int, comments: String?, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)/approve") else {
            completion(false, "Invalid URL")
            return
        }
        
        var body: [String: Any] = [:]
        if let comments = comments { body["COMMENTS"] = comments }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    DispatchQueue.global().async {
                        self.loadInvestmentRequests()
                        self.loadSummary()
                    }
                    completion(true, nil)
                } else {
                    var errorMsg = "Unknown error"
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = json["error"] as? String {
                        errorMsg = err
                    }
                    completion(false, errorMsg)
                }
            }
        }.resume()
    }
    
    func rejectRequest(requestId: Int, comments: String?, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)/reject") else {
            completion(false, "Invalid URL")
            return
        }
        
        var body: [String: Any] = [:]
        if let comments = comments { body["COMMENTS"] = comments }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.loadInvestmentRequests()
                    self.loadSummary()
                    completion(true, nil)
                } else {
                    var errorMsg = "Unknown error"
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = json["error"] as? String {
                        errorMsg = err
                    }
                    completion(false, errorMsg)
                }
            }
        }.resume()
    }
    
    func linkOpportunity(requestId: Int, opportunityId: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)/opportunities") else {
            completion(false)
            return
        }
        
        let body: [String: Any] = ["OPPORTUNITY_ID": opportunityId]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func unlinkOpportunity(requestId: Int, opportunityId: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)/opportunities/\(opportunityId)") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func loadLinkedOpportunities(for requestId: Int, completion: @escaping ([SFDCOpportunity]) -> Void) {
        guard let url = URL(string: "\(baseURL)/requests/\(requestId)/opportunities") else {
            completion([])
            return
        }
        
        session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, let data = data else {
                    completion([])
                    return
                }
                
                do {
                    let opps = try self.decoder.decode([SFDCOpportunity].self, from: data)
                    completion(opps)
                } catch {
                    print("Error decoding linked opportunities: \(error)")
                    completion([])
                }
            }
        }.resume()
    }
}
