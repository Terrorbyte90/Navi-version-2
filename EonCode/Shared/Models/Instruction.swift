import Foundation

// iOS → macOS instruction queue item
struct Instruction: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var status: InstructionStatus
    var deviceID: String          // Source device
    var instruction: String
    var projectID: UUID?
    var conversationID: UUID?
    var currentStep: Int
    var totalSteps: Int
    var steps: [InstructionStepRecord]
    var result: String?
    var error: String?

    init(
        id: UUID = UUID(),
        instruction: String,
        projectID: UUID? = nil,
        conversationID: UUID? = nil,
        deviceID: String = UIDevice.deviceID
    ) {
        self.id = id
        self.createdAt = Date()
        self.updatedAt = Date()
        self.status = .pending
        self.deviceID = deviceID
        self.instruction = instruction
        self.projectID = projectID
        self.conversationID = conversationID
        self.currentStep = 0
        self.totalSteps = 0
        self.steps = []
    }

    var filename: String { "\(id.uuidString).json" }

    mutating func updateStep(index: Int, total: Int, record: InstructionStepRecord) {
        currentStep = index
        totalSteps = total
        steps.append(record)
        updatedAt = Date()
    }

    static func == (lhs: Instruction, rhs: Instruction) -> Bool {
        lhs.id == rhs.id
    }
}

enum InstructionStatus: String, Codable, Equatable {
    case pending
    case running
    case completed
    case failed
    case paused
    case cancelled

    var isActive: Bool { self == .pending || self == .running }
}

struct InstructionStepRecord: Codable, Equatable {
    var index: Int
    var action: String
    var status: String
    var output: String
    var timestamp: Date

    init(index: Int, action: String, status: String, output: String) {
        self.index = index
        self.action = action
        self.status = status
        self.output = output
        self.timestamp = Date()
    }
}

// Device identity helper
enum UIDevice {
    static var deviceID: String {
        #if os(macOS)
        return Host.current().name ?? "mac-unknown"
        #else
        return Foundation.ProcessInfo.processInfo.globallyUniqueString
        #endif
    }

    static var deviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "iPhone"
        #endif
    }

    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}
