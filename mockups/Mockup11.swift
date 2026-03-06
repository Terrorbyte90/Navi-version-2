// Mockup11 — "ChatGPT Clone"
// Extremely faithful recreation of ChatGPT's dark mode UI (2025/2026).
// Sidebar with conversation list, centered chat, rounded input pill, model selector.
import SwiftUI

struct Mockup11: View {
    @State private var selectedTab = 0 // 0=Project, 1=Chat, 2=Browser, 3=Settings
    @State private var selectedProject: String? = "Eon X"
    @State private var selectedFile: String? = nil
    @State private var expandedProjects: Set<String> = ["Eon X"]
    @State private var sidebarVisible = true
    @State private var selectedChat = "Eon X — Gauge-vy"
    @State private var modelPickerOpen = false

    // ChatGPT exact dark mode palette
    let sidebarBg = Color(red: 0.09, green: 0.09, blue: 0.09)       // #171717
    let mainBg = Color(red: 0.13, green: 0.13, blue: 0.13)           // #212121
    let userBubble = Color(red: 0.185, green: 0.185, blue: 0.185)    // #2f2f2f
    let inputBg = Color(red: 0.185, green: 0.185, blue: 0.185)       // #2f2f2f
    let inputBorder = Color(red: 0.25, green: 0.25, blue: 0.25)      // #404040
    let codeBg = Color(red: 0.118, green: 0.118, blue: 0.118)        // #1e1e1e
    let hoverBg = Color(red: 0.16, green: 0.16, blue: 0.16)          // #292929
    let textPrimary = Color(red: 0.925, green: 0.925, blue: 0.925)   // #ececec
    let textSecondary = Color(red: 0.68, green: 0.68, blue: 0.68)    // #adadad
    let textMuted = Color(red: 0.5, green: 0.5, blue: 0.5)           // #808080
    let divider = Color.white.opacity(0.08)
    let gptGreen = Color(red: 0.455, green: 0.667, blue: 0.612)      // #74aa9c

    let projects: [(String, [String])] = [
        ("Eon X", ["App.swift", "ConsciousnessEngine.swift", "SensorBridge.swift", "Views/MainView.swift"]),
        ("Eon Y", ["CognitiveEngine.swift", "SwedishLLM.swift", "ThoughtSpace.swift"]),
        ("WeatherApp", ["WeatherApp.swift", "Models/Forecast.swift", "Views/HomeView.swift"])
    ]
    let chatMessages: [(Bool, String)] = [
        (true, "Skapa en ny vy som visar medvetandenivån i realtid med en cirkulär gauge"),
        (false, "Jag skapar `ConsciousnessGaugeView.swift` med en cirkulär progress-indikator…\n```swift\nstruct ConsciousnessGaugeView: View {\n    @ObservedObject var engine: ConsciousnessEngine\n    var body: some View {\n        ZStack {\n            Circle().stroke(lineWidth: 12).opacity(0.2)\n            Circle().trim(from: 0, to: engine.awarenessLevel)\n                .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))\n        }\n    }\n}\n```"),
        (true, "Byt färg till gradient från blå till lila baserat på nivån"),
        (false, "Uppdaterat! Jag lade till en `LinearGradient` som interpolerar mellan blå och lila baserat på `awarenessLevel`.\n```swift\n.stroke(\n    AngularGradient(\n        colors: [.blue, .purple, .blue],\n        center: .center\n    ), style: StrokeStyle(lineWidth: 12, lineCap: .round)\n)\n```"),
        (true, "Perfekt. Bygg projektet")
    ]
    let codeContent = "import SwiftUI\n\nstruct ConsciousnessEngine: ObservableObject {\n    @Published var awarenessLevel: Double = 0.0\n    @Published var cognitiveLoad: Double = 0.0\n\n    func processInput(_ input: SensorData) async {\n        let processed = await neuralBridge.forward(input)\n        awarenessLevel = processed.attention\n        cognitiveLoad = processed.complexity\n    }\n}"

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible { sidebar.frame(width: 260).transition(.move(edge: .leading)) }
            mainArea
        }
        .background(mainBg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar (ChatGPT style)
    var sidebar: some View {
        VStack(spacing: 0) {
            // Top: New chat button + sidebar toggle
            HStack {
                Button { sidebarVisible.toggle() } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 16)).foregroundStyle(textSecondary)
                }.buttonStyle(.plain)
                Spacer()
                Button { } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 16)).foregroundStyle(textSecondary)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 14).padding(.vertical, 12)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(textMuted)
                Text("Sök").font(.callout).foregroundStyle(textMuted)
                Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 8)
                .background(hoverBg, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10).padding(.bottom, 8)

            // Nav tabs
            VStack(spacing: 2) {
                sidebarNavItem("Projekt", icon: "folder", tab: 0)
                sidebarNavItem("Chatt", icon: "bubble.left", tab: 1)
                sidebarNavItem("Webbläsare", icon: "globe", tab: 2)
                sidebarNavItem("Inställningar", icon: "gearshape", tab: 3)
            }.padding(.horizontal, 8)

            Divider().background(divider).padding(.vertical, 8)

            // Chat history / Project list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if selectedTab == 0 { sidebarProjectList }
                    else if selectedTab == 1 { sidebarChatList }
                    else if selectedTab == 2 {
                        Text("Webbhistorik").font(.caption).foregroundStyle(textMuted).padding(.horizontal, 14).padding(.top, 8)
                    } else {
                        Text("").padding(.top, 8) // settings has no sidebar list
                    }
                }.padding(.horizontal, 8)
            }

            Divider().background(divider)

            // Agent status bar
            HStack(spacing: 8) {
                Circle().fill(.orange).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent: Bygger Eon X — 7/12").font(.caption2).foregroundStyle(textSecondary)
                    Text("2.45 SEK").font(.caption2).foregroundStyle(textMuted)
                }
                Spacer()
            }.padding(.horizontal, 14).padding(.vertical, 10)

            Divider().background(divider)

            // Bottom: User profile
            HStack(spacing: 10) {
                Circle().fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay(Text("T").font(.caption).bold().foregroundStyle(.white))
                Text("Terrorbyte").font(.callout).foregroundStyle(textPrimary)
                Spacer()
                Image(systemName: "ellipsis").foregroundStyle(textMuted)
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }.background(sidebarBg)
    }

    func sidebarNavItem(_ label: String, icon: String, tab: Int) -> some View {
        Button { selectedTab = tab } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(selectedTab == tab ? textPrimary : textSecondary)
                    .frame(width: 20)
                Text(label).font(.callout).foregroundStyle(selectedTab == tab ? textPrimary : textSecondary)
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 7)
                .background(selectedTab == tab ? hoverBg : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    var sidebarProjectList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Idag").font(.caption2).fontWeight(.medium).foregroundStyle(textMuted)
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
            ForEach(projects, id: \.0) { name, files in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        if expandedProjects.contains(name) { expandedProjects.remove(name) }
                        else { expandedProjects.insert(name) }
                        selectedProject = name
                    } label: {
                        HStack(spacing: 8) {
                            Text(name).font(.callout).foregroundStyle(selectedProject == name ? textPrimary : textSecondary)
                                .lineLimit(1)
                            Spacer()
                        }.padding(.horizontal, 10).padding(.vertical, 7)
                            .background(selectedProject == name ? hoverBg : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)

                    if expandedProjects.contains(name) {
                        ForEach(files, id: \.self) { file in
                            Button { selectedFile = file; selectedTab = 0 } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text").font(.system(size: 10)).foregroundStyle(textMuted)
                                    Text(file).font(.caption).foregroundStyle(selectedFile == file ? textPrimary : textMuted)
                                        .lineLimit(1)
                                }.padding(.leading, 20).padding(.vertical, 3)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    var sidebarChatList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Idag").font(.caption2).fontWeight(.medium).foregroundStyle(textMuted)
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
            ForEach(["Eon X — Gauge-vy", "Eon Y — LLM-setup", "WeatherApp — Fix"], id: \.self) { chat in
                Button { selectedChat = chat; selectedTab = 1 } label: {
                    Text(chat).font(.callout).foregroundStyle(selectedChat == chat ? textPrimary : textSecondary)
                        .lineLimit(1).padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedChat == chat ? hoverBg : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
            Text("Igår").font(.caption2).fontWeight(.medium).foregroundStyle(textMuted)
                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 2)
            ForEach(["Eon X — Initial setup", "Bugfix: streaming"], id: \.self) { chat in
                Button { selectedTab = 1 } label: {
                    Text(chat).font(.callout).foregroundStyle(textSecondary).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Main Area
    var mainArea: some View {
        VStack(spacing: 0) {
            // Top bar: Model selector + status
            topBar
            // Content
            if selectedTab == 1 { chatView }
            else if selectedTab == 2 { browserView }
            else if selectedTab == 3 { settingsView }
            else if selectedFile != nil { editorView }
            else { chatView } // default to chat like ChatGPT
        }.frame(maxWidth: .infinity)
    }

    var topBar: some View {
        HStack {
            if !sidebarVisible {
                HStack(spacing: 12) {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() } } label: {
                        Image(systemName: "sidebar.left").font(.system(size: 16)).foregroundStyle(textSecondary)
                    }.buttonStyle(.plain)
                    Button { } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 16)).foregroundStyle(textSecondary)
                    }.buttonStyle(.plain)
                }
            }

            // Model picker (ChatGPT style)
            Button { modelPickerOpen.toggle() } label: {
                HStack(spacing: 4) {
                    Text("EonCode").font(.callout).fontWeight(.semibold).foregroundStyle(textPrimary)
                    Text("Haiku 4.5").font(.callout).foregroundStyle(textSecondary)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(textMuted)
                }.padding(.horizontal, 4).padding(.vertical, 4)
            }.buttonStyle(.plain)

            Spacer()

            // Status badges
            HStack(spacing: 12) {
                Text("142.50 SEK").font(.caption).foregroundStyle(textMuted)
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("Mac Online").font(.caption).foregroundStyle(textMuted)
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Chat View (ChatGPT faithful)
    var chatView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(chatMessages.enumerated()), id: \.0) { _, msg in
                        chatMessage(isUser: msg.0, text: msg.1)
                    }
                }.padding(.horizontal, 16).padding(.top, 8)
                    .frame(maxWidth: 768) // ChatGPT max-width
                    .frame(maxWidth: .infinity)
            }

            // Input area (ChatGPT rounded pill)
            inputBar.padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 8)
                .frame(maxWidth: 768).frame(maxWidth: .infinity)
        }
    }

    func chatMessage(isUser: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !isUser {
                // ChatGPT icon
                Circle().fill(gptGreen).frame(width: 28, height: 28)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(.white))
            }
            if isUser { Spacer(minLength: 80) }

            VStack(alignment: .leading, spacing: 8) {
                if isUser {
                    // User: right-aligned bubble
                    Text(text).font(.callout).foregroundStyle(textPrimary)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(userBubble, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    // Assistant: no bubble, just text + code blocks
                    let parts = text.components(separatedBy: "```")
                    ForEach(Array(parts.enumerated()), id: \.0) { i, part in
                        if i % 2 == 1 {
                            // Code block with header bar
                            let lines = part.split(separator: "\n", maxSplits: 1)
                            let lang = lines.count > 1 ? String(lines[0]) : ""
                            let code = lines.count > 1 ? String(lines[1]) : part
                            VStack(spacing: 0) {
                                // Code header
                                HStack {
                                    Text(lang.isEmpty ? "code" : lang).font(.caption2).foregroundStyle(textMuted)
                                    Spacer()
                                    Button { } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "doc.on.doc").font(.system(size: 10))
                                            Text("Kopiera").font(.caption2)
                                        }.foregroundStyle(textMuted)
                                    }.buttonStyle(.plain)
                                }.padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color(red: 0.16, green: 0.16, blue: 0.16))

                                // Code content
                                Text(code).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(textPrimary.opacity(0.9))
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(codeBg)
                            }.clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.vertical, 4)
                        } else if !part.isEmpty {
                            Text(part).font(.callout).foregroundStyle(textPrimary.opacity(0.92))
                                .lineSpacing(4)
                        }
                    }
                    // Action buttons under assistant message
                    HStack(spacing: 16) {
                        Button { } label: { Image(systemName: "doc.on.doc").font(.system(size: 12)) }.buttonStyle(.plain)
                        Button { } label: { Image(systemName: "hand.thumbsup").font(.system(size: 12)) }.buttonStyle(.plain)
                        Button { } label: { Image(systemName: "hand.thumbsdown").font(.system(size: 12)) }.buttonStyle(.plain)
                        Button { } label: { Image(systemName: "arrow.clockwise").font(.system(size: 12)) }.buttonStyle(.plain)
                    }.foregroundStyle(textMuted).padding(.top, 4)
                }
            }

            if isUser {
                // No user avatar in modern ChatGPT
            }
            if !isUser { Spacer(minLength: 40) }
        }.padding(.vertical, 12)
    }

    var inputBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                // Attach button
                Button { } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .medium))
                        .foregroundStyle(textSecondary).frame(width: 32, height: 32)
                        .background(hoverBg, in: Circle())
                }.buttonStyle(.plain)

                // Text input
                VStack(spacing: 0) {
                    HStack(alignment: .bottom) {
                        TextField("Skicka ett meddelande till EonCode", text: .constant(""))
                            .font(.callout).foregroundStyle(textPrimary)
                            .textFieldStyle(.plain)
                            .padding(.vertical, 10).padding(.leading, 14)
                        // Send button
                        Button { } label: {
                            Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(mainBg).frame(width: 30, height: 30)
                                .background(textPrimary, in: Circle())
                        }.buttonStyle(.plain).padding(.trailing, 6).padding(.bottom, 5)
                    }
                }
                .background(inputBg, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(inputBorder, lineWidth: 0.5))
            }

            Text("EonCode kan göra misstag. Kontrollera viktig information.")
                .font(.caption2).foregroundStyle(textMuted)
        }
    }

    // MARK: - Editor View
    var editorView: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.caption).foregroundStyle(textMuted)
                    Text(selectedFile ?? "").font(.callout).foregroundStyle(textPrimary)
                }.padding(.horizontal, 12).padding(.vertical, 6)
                    .background(userBubble, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text("Swift").font(.caption).foregroundStyle(textMuted)
            }.padding(.horizontal, 16).padding(.vertical, 8)

            Divider().background(divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeContent.components(separatedBy: "\n").enumerated()), id: \.0) { i, line in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.system(.caption, design: .monospaced))
                                .foregroundStyle(textMuted.opacity(0.5)).frame(width: 28, alignment: .trailing)
                            gptSyntax(line)
                        }.padding(.vertical, 1)
                    }
                }.padding(16)
            }.background(codeBg)
        }
    }

    func gptSyntax(_ line: String) -> some View {
        let kw = ["import", "struct", "func", "var", "let", "@Published", "async", "await"]
        let types = ["SwiftUI", "ObservableObject", "Double", "SensorData"]
        var result = Text("")
        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            let w = String(word)
            if kw.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(Color(red: 0.86, green: 0.4, blue: 0.65))
            } else if types.contains(w) {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(Color(red: 0.4, green: 0.75, blue: 0.85))
            } else if w.contains("0.0") {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(Color(red: 0.7, green: 0.55, blue: 1.0))
            } else {
                result = result + Text(w + " ").font(.system(.callout, design: .monospaced)).foregroundColor(textPrimary.opacity(0.85))
            }
        }
        return result
    }

    // MARK: - Browser View
    var browserView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Button { } label: { Image(systemName: "chevron.left").font(.caption).foregroundStyle(textMuted) }.buttonStyle(.plain)
                    Button { } label: { Image(systemName: "chevron.right").font(.caption).foregroundStyle(textMuted) }.buttonStyle(.plain)
                    Button { } label: { Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(textMuted) }.buttonStyle(.plain)
                }
                HStack {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(textMuted)
                    Text("developer.apple.com").font(.callout).foregroundStyle(textSecondary)
                    Spacer()
                }.padding(.horizontal, 12).padding(.vertical, 7)
                    .background(userBubble, in: RoundedRectangle(cornerRadius: 10))
            }.padding(12)
            Divider().background(divider)
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "globe").font(.system(size: 40)).foregroundStyle(textMuted.opacity(0.3))
                Text("Webbläsare").font(.callout).foregroundStyle(textMuted)
            }
            Spacer()
        }
    }

    // MARK: - Settings View
    var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inställningar").font(.title3).fontWeight(.semibold).foregroundStyle(textPrimary)

                settingsRow("API-nyckel", value: "sk-●●●●●●●●", icon: "key")
                settingsRow("Modell", value: "Haiku 4.5", icon: "cpu")
                settingsRow("Synkronisering", value: "iCloud", icon: "icloud")
                settingsRow("Tema", value: "ChatGPT Dark", icon: "paintbrush")
                settingsRow("Saldo", value: "142.50 SEK", icon: "creditcard")
            }.padding(24).frame(maxWidth: 600)
        }.frame(maxWidth: .infinity)
    }

    func settingsRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.callout).foregroundStyle(textMuted).frame(width: 20)
                Text(label).font(.callout).foregroundStyle(textPrimary)
            }
            Spacer()
            HStack(spacing: 6) {
                Text(value).font(.callout).foregroundStyle(textSecondary)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(textMuted)
            }
        }.padding(14).background(userBubble, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview { Mockup11() }
