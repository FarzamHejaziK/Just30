import SwiftUI
import AppKit

private enum Palette {
    static let mint = Color(red: 0.67, green: 0.91, blue: 0.69)
    static let background = Color(red: 0.065, green: 0.080, blue: 0.074)
    static let sidebar = Color(red: 0.047, green: 0.058, blue: 0.054)
    static let card = Color.white.opacity(0.045)
}

@main
struct OneWayMacApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("JustThirty", id: "main") {
            MainView().environmentObject(model)
                .frame(minWidth: 860, minHeight: 650)
                .preferredColorScheme(.dark)
                .tint(Palette.mint)
        }
        .defaultSize(width: 1000, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Background permissions…") { model.openPermissions() }
            }
        }
    }
}

private enum Page: String, CaseIterable {
    case overview = "Overview", websites = "Websites", apps = "Apps"
    var symbol: String {
        switch self { case .overview: "square.grid.2x2"; case .websites: "globe"; case .apps: "app.dashed" }
    }
}
private enum AddSheet: String, Identifiable { case apps, websites; var id: String { rawValue } }

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    @State private var page = Page.overview
    @State private var sheet: AddSheet?
    @State private var confirmAccess = false
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statusCard
                    allowanceCard
                    if page == .overview {
                        HStack(spacing: 16) {
                            actionCard("Add apps", subtitle: "Make room for your focus", symbol: "square.grid.2x2.fill") { sheet = .apps }
                            actionCard("Add websites", subtitle: "Find a site. Leave it behind.", symbol: "globe") { sheet = .websites }
                        }
                    }
                    blockList
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "info.circle")
                        Text("Website rules cover the exact domains you add, including the shown aliases. Other subdomains, proxies, and some browser DNS settings can bypass them. Outside timed access, only apps saved in your block list close. Browsers stay open unless you blocked the browser app itself. Existing website connections may continue until you quit and reopen the browser. A Mac administrator can disable the service.")
                            .fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(32).frame(maxWidth: 1000, alignment: .leading)
            }.background(Palette.background)
        }
        .background(Palette.background)
        .sheet(item: $sheet) { item in
            if item == .websites { WebsiteSheet().environmentObject(model) }
            else { AppsSheet().environmentObject(model) }
        }
        .alert("Couldn't update JustThirty", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog("Start access?", isPresented: $confirmAccess, titleVisibility: .visible) {
            Button("Start timer and unlock") { Task { await model.resumeAccess() } }
        } message: {
            Text("Save work in your blocked apps first. All blocked apps and websites unlock together. The timer runs until you tap Pause access, even while you are away. Pausing or reaching zero closes only your saved blocked apps and restores website rules. Existing website connections may continue until you quit and reopen the browser. Pausing preserves unused time for later today.")
        }
        .task { await model.refresh() }
        .onReceive(timer) { _ in if phase == .active { Task { await model.refresh() } } }
        .onChange(of: phase) { _, value in if value == .active { Task { await model.refresh() } } }
    }

    private var allowanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("DAILY ACCESS", systemImage: "timer").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.mint)
            if let session = model.session {
                if session.isActive(), let end = session.endsAt {
                    Text(end, style: .timer).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("Timer running. Pause to save unused time. On pause or expiry, only saved blocked apps close and website rules resume. Existing website connections may continue.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Pause access") { Task { await model.endSession() } }.disabled(model.busy)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(AccessSession.clock(session.budget.remaining)) left today").font(.system(size: 19, weight: .semibold))
                            Text("Start to unlock. Pause to block and save time. 30 minutes shared each day.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { confirmAccess = true } label: {
                            Label(session.budget.used > 0 ? "Resume access" : "Start access", systemImage: "play.fill")
                        }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                            .disabled(!model.canAdd || model.list.isEmpty || session.budget.remaining < 1)
                    }
                }
            } else {
                Text("Connect to the updated background service to use daily access.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.system(size: 28)).foregroundStyle(Palette.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("JustThirty").font(.system(size: 23, weight: .bold, design: .rounded))
                    Text("FOR YOUR MAC").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                }
            }.padding(.top, 25).padding(.horizontal, 10)
            VStack(spacing: 7) {
                ForEach(Page.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.symbol).frame(width: 20)
                            Text(item.rawValue).fontWeight(.medium)
                            Spacer()
                            if item == .websites { Text("\(model.list.domains.count)").foregroundStyle(.secondary) }
                            if item == .apps { Text("\(model.list.applications.count)").foregroundStyle(.secondary) }
                        }.font(.system(size: 13)).padding(12)
                            .background(page == item ? Palette.mint.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(page == item ? Palette.mint : .white.opacity(0.65))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Label("An add-only space", systemImage: "lock.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.mint)
                Text("30 minutes a day.\nYour list stays add-only.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(12)
        }.padding(18).frame(width: 210).frame(maxHeight: .infinity).background(Palette.sidebar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(page == .overview ? "YOUR SPACE, RECLAIMED" : "YOUR BLOCK LIST")
                .font(.system(size: 10, weight: .semibold)).tracking(2.4).foregroundStyle(Palette.mint)
            HStack(alignment: .center) {
                Text(page == .overview ? "Less temptation.\nMore intention." : page.rawValue)
                    .font(.system(size: 36, weight: .bold, design: .rounded)).lineSpacing(0)
                Spacer()
                if page != .overview {
                    Button { sheet = page == .apps ? .apps : .websites } label: {
                        Label(page == .apps ? "Add apps" : "Add websites", systemImage: "plus")
                    }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!model.canAdd)
                }
            }
            Text(page == .overview ? "Add it once. Keep your attention for what matters." : "Your saved additions stay here. There are no removal controls.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: model.connected && model.healthy ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.system(size: 23)).foregroundStyle(model.connected && model.healthy ? Palette.mint : .orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.statusTitle).font(.system(size: 14, weight: .semibold))
                Text(statusDetail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                if let issue = model.serviceIssue, !model.healthy {
                    Text(issue).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if !model.connected {
                Button(model.status == .requiresApproval ? "Open Settings" : "Set up") {
                    Task { await model.setUp() }
                }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(model.busy)
            }
        }.padding(20).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
    }
    private var statusDetail: String {
        if model.connected { return "The background service runs with the window closed and starts again when your Mac restarts." }
        if model.status == .requiresApproval { return "Allow JustThirty under Login Items & Extensions → App Background Activity. macOS may ask for your administrator password." }
        return "One-time setup lets JustThirty apply website rules and close blocked apps in the background. Existing network rules are preserved."
    }

    private func actionCard(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 19) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 25)).frame(width: 30, height: 30)
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28).background(Palette.mint.opacity(0.10), in: Circle())
                }.foregroundStyle(Palette.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(21).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.mint.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.mint.opacity(0.18), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
        // Pickers can be explored before setup; committing is disabled until the service is ready.
    }

    private var blockList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(page == .overview ? "ALREADY OUT OF THE WAY" : "SAVED BLOCKS")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.secondary)
                Spacer()
                if !model.connected && !model.list.isEmpty { Text("Last known list").font(.caption).foregroundStyle(.orange) }
            }
            if visibleEmpty {
                HStack(spacing: 17) {
                    Image(systemName: "leaf").font(.system(size: 26)).foregroundStyle(Palette.mint.opacity(0.65))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A little distance starts here.").font(.system(size: 14, weight: .medium))
                        Text("Choose an app or website above. Review each addition before it becomes part of your list.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(23).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 15))
            }
            if page != .websites {
                ForEach(model.list.applications) { app in
                    savedRow {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.system(size: 13, weight: .medium))
                            Text("App · blocked outside timed access").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if page != .apps {
                ForEach(model.list.domains.sorted(), id: \.self) { domain in
                    savedRow {
                        Image(systemName: "globe").foregroundStyle(Palette.mint).frame(width: 28)
                        Text(domain).font(.system(size: 13)).textSelection(.enabled)
                    }
                }
            }
        }
    }
    private var visibleEmpty: Bool {
        switch page { case .overview: model.list.isEmpty; case .apps: model.list.applications.isEmpty; case .websites: model.list.domains.isEmpty }
    }
    private func savedRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content(); Spacer(); Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary) }
            .padding(13).background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SheetHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 25, height: 25) }
                .buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
        }
    }
}

struct WebsiteSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var pending: WebsiteSuggestion?
    @State private var confirmation = false
    @State private var added: String?
    @FocusState private var focused: Bool
    private var suggestions: [WebsiteSuggestion] { WebsiteCatalog.matches(query) }
    private var candidate: WebsiteSuggestion? {
        guard let site = WebsiteCatalog.candidate(query), (try? MacDomain.validated(site.domain)) != nil else { return nil }
        return site
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SheetHeader(title: "Find it. Block it. Move on.", subtitle: "Search a familiar site or paste a website link.")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.mint)
                TextField("Site name or example.com", text: $query).textFieldStyle(.plain).focused($focused)
                    .onSubmit { if let site = candidate, !model.isBlocked(site), model.canAdd { pending = site; confirmation = true } }
                    .accessibilityLabel("Search websites")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
            }.padding(15).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            if !model.canAdd {
                Label("Finish background setup to save blocks. You can explore websites now.", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            if let added { Label(added, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Palette.mint) }
            if let error = model.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let site = candidate {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: site.symbol).font(.system(size: 24)).foregroundStyle(Palette.mint).frame(width: 35)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(site.name).font(.system(size: 17, weight: .semibold))
                                    Text("These exact website names will be blocked:").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Text(MacDomain.expanded(site).sorted().joined(separator: "  ·  "))
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Button {
                                pending = site; confirmation = true
                            } label: {
                                Label(model.isBlocked(site) ? "Already in your block list" : "Add website", systemImage: model.isBlocked(site) ? "lock.fill" : "plus")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }.buttonStyle(.borderedProminent)
                                .foregroundStyle(model.canAdd && !model.isBlocked(site) ? Color.black : Color.secondary)
                                .disabled(!model.canAdd || model.isBlocked(site))
                        }.padding(20).background(Palette.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if !suggestions.isEmpty {
                        Text(query.isEmpty ? "COMMON DISTRACTIONS" : "SUGGESTED WEBSITES")
                            .font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
                        ForEach(suggestions) { site in
                            Button { query = site.domain; added = nil } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: site.symbol).font(.system(size: 19)).frame(width: 32).foregroundStyle(Palette.mint)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(site.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                        Text(site.domain).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: model.isBlocked(site) ? "lock.fill" : "arrow.up.left").foregroundStyle(.secondary)
                                }.padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    } else if candidate == nil {
                        Text("Enter a full domain such as example.com. A pasted link will block its hostname, not just one page.")
                            .foregroundStyle(.secondary).font(.system(size: 13)).padding(.vertical, 12)
                    }
                }
            }
            Text("No removal controls. Other subdomains must be added separately. Reopen existing browser tabs after adding a site; cached connections may take time to close.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 550, height: 650).background(Palette.background)
        .onAppear { focused = true }
        .alert("Add this website permanently?", isPresented: $confirmation, presenting: pending) { site in
            Button("Cancel", role: .cancel) {}
            Button("Add to block list") {
                Task { if await model.addWebsite(site) { added = "\(site.name) added. Your saved blocks stay in place."; query = "" } }
            }
        } message: { site in Text("\(MacDomain.expanded(site).sorted().joined(separator: ", "))\n\nThese rules apply to this Mac. You cannot remove them inside JustThirty.") }
    }
}

struct AppsSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var pending: BlockedApplication?
    @State private var confirmation = false
    @State private var added: String?
    private var apps: [BlockedApplication] { model.installedApps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(title: "Choose what stays closed.", subtitle: "Add an installed Mac app to your block list.")
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.mint)
                TextField("Search your apps", text: $query).textFieldStyle(.plain).accessibilityLabel("Search installed apps")
            }.padding(15).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            if !model.canAdd { Text("Finish background setup to add apps.").font(.system(size: 12)).foregroundStyle(.orange) }
            if let added { Label(added, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.mint).font(.system(size: 12)) }
            if let error = model.error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(apps) { app in
                        Button { pending = app; confirmation = true } label: {
                            HStack(spacing: 12) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                    Text(app.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Image(systemName: model.isBlocked(app) ? "lock.fill" : "plus").foregroundStyle(Palette.mint)
                            }.padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 11)).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!model.canAdd || model.isBlocked(app))
                    }
                    if model.loadingApps { ProgressView("Finding installed apps…").padding(24) }
                    else if apps.isEmpty { Text("No matching apps found.").foregroundStyle(.secondary).padding(24) }
                }
            }
            HStack {
                Text("Save your work first. Blocked apps close immediately and each time you reopen them.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Browse…") { if let app = model.chooseApp() { pending = app; confirmation = true } }
                    .disabled(!model.canAdd)
            }
        }.padding(28).frame(width: 550, height: 650).background(Palette.background)
        .alert("Block this app permanently?", isPresented: $confirmation, presenting: pending) { app in
            Button("Cancel", role: .cancel) {}
            Button("Block app", role: .destructive) { Task { if await model.addApp(app) { added = "\(app.name) added to your block list." } } }
        } message: { app in Text("\(app.name) will close, including any unsaved work. JustThirty will close it again whenever it opens. You cannot remove it inside JustThirty.") }
    }
}
