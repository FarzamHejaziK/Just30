import SwiftUI
import FamilyControls
import ManagedSettings

@main
struct OneWayApp: App {
    @StateObject private var model = BlockModel()
    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--preview-websites") {
                AddWebsitesView().environmentObject(model)
            } else {
                HomeView().environmentObject(model)
            }
            #else
            HomeView().environmentObject(model)
            #endif
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: BlockModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showApps = false
    @State private var showWebsites = false
    private let accent = Color(red: 0.62, green: 0.89, blue: 0.62)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 30)).foregroundStyle(accent)
                        Text("Less temptation.\nMore intention.").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Add it once. Keep it blocked.").foregroundStyle(.secondary)
                    }.padding(.top, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        Label(status, systemImage: model.approved ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.headline).foregroundStyle(model.approved ? accent : .orange)
                        Text("This is an add-only list. There are no remove, pause, or reset controls.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !model.approved {
                            Button("Enable Screen Time Access") { Task { await model.authorize() } }
                                .buttonStyle(.borderedProminent).disabled(model.busy || !model.loaded)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))

                    let actionLayout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 12))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    actionLayout {
                        addButton("Add apps", detail: "Apps & categories", icon: "square.grid.2x2.fill") { showApps = true }
                        addButton("Add websites", detail: "Domains & links", icon: "globe") { showWebsites = true }
                    }.disabled(!model.approved || !model.loaded)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("YOUR BLOCK LIST").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                        if model.list.isEmpty {
                            Text("A little distance starts here.").font(.headline)
                            Text("Add the apps and sites you want out of reach. Review each addition carefully: you cannot remove it in OneWay.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(Array(model.list.apps), id: \.self) { token in
                            lockedRow { Label(token).labelStyle(.titleAndIcon) }
                        }
                        ForEach(Array(model.list.categories), id: \.self) { token in
                            lockedRow { Label(token).labelStyle(.titleAndIcon) }
                        }
                        ForEach(Array(model.list.websites), id: \.self) { token in
                            lockedRow { Label(token).labelStyle(.titleAndIcon) }
                        }
                        ForEach(model.list.domains.sorted(), id: \.self) { domain in
                            lockedRow { Label(domain, systemImage: "globe") }
                        }
                    }

                    Text("OneWay cannot prevent you from revoking Screen Time access in iOS Settings or deleting the app. Website filtering depends on browser support. Adding typed websites also disables Safari Private Browsing.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                }.padding(24)
            }
            .background(Color(red: 0.055, green: 0.07, blue: 0.06))
            .navigationTitle("OneWay").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showApps) { AddAppsView() }
            .sheet(isPresented: $showWebsites) { AddWebsitesView() }
            .alert("Couldn't update the block list", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .onChange(of: phase) { _, value in if value == .active { model.refresh() } }
        }.tint(accent).preferredColorScheme(.dark)
    }

    private var status: String {
        if !model.loaded { return "Saved list needs attention" }
        if !model.approved { return "Screen Time access required" }
        return model.list.isEmpty ? "Ready for your first block" : "Blocking enabled"
    }

    private func addButton(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: icon).font(.system(size: 23, weight: .medium))
                        .frame(width: 28, height: 28, alignment: .leading)
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(accent.opacity(0.10), in: Circle())
                }.foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
            .background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.16), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .opacity(model.approved && model.loaded ? 1 : 0.5)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityHint(detail)
    }
    private func lockedRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack { content(); Spacer(); Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
            .padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AddAppsView: View {
    @EnvironmentObject private var model: BlockModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = FamilyActivitySelection(includeEntireCategory: true)
    @State private var confirm = false
    private var hasSelection: Bool { !draft.applicationTokens.isEmpty || !draft.categoryTokens.isEmpty || !draft.webDomainTokens.isEmpty }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Choose additions only. Your saved blocks stay blocked, even if you deselect them here.")
                    .font(.subheadline).foregroundStyle(.secondary).padding()
                if let error = model.error { Text(error).font(.footnote).foregroundStyle(.orange).padding(.horizontal) }
                FamilyActivityPicker(selection: $draft)
            }
            .navigationTitle("Add blocks").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        do {
                            _ = try model.list.adding(apps: draft.applicationTokens, categories: draft.categoryTokens, websites: draft.webDomainTokens)
                            model.error = nil
                            confirm = true
                        } catch { model.error = error.localizedDescription }
                    }.disabled(!hasSelection)
                }
            }
            .confirmationDialog("Add these blocks?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Add to block list") { if model.add(selection: draft) { dismiss() } }
            } message: { Text("These additions cannot be removed in OneWay. Entire categories also block other apps and websites in those categories.") }
        }
    }
}

struct AddWebsitesView: View {
    @EnvironmentObject private var model: BlockModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var input = ""
    @State private var pending: WebsiteSuggestion?
    @State private var success: String?
    @State private var showConfirmation = false
    private let accent = Color(red: 0.62, green: 0.89, blue: 0.62)
    private var candidate: WebsiteSuggestion? { WebsiteCatalog.candidate(input) }
    private var suggestions: [WebsiteSuggestion] { WebsiteCatalog.matches(input) }
    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var alreadyBlocked: Bool { candidate.map { $0.domains.isSubset(of: model.list.domains) } ?? false }
    private var capacityExceeded: Bool { candidate.map { model.list.domains.union($0.domains).count > 50 } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find it. Block it.\nMove on.")
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                        Text("Search a familiar site or paste any website link.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(accent)
                        TextField("Site name or example.com", text: $input)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).submitLabel(.done).focused($searchFocused)
                            .onSubmit { review() }
                            .accessibilityLabel("Search websites by name or domain")
                        if !input.isEmpty {
                            Button { input = ""; success = nil; searchFocused = true } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.accessibilityLabel("Clear search")
                        }
                    }.padding(16).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    if let success {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium)).foregroundStyle(accent)
                            .accessibilityIdentifier("website-added")
                    }
                    if let error = model.error {
                        Text(error).font(.subheadline).foregroundStyle(.orange)
                    }

                    if let site = candidate {
                        preview(site)
                    } else if !trimmed.isEmpty && suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Add any website", systemImage: "globe")
                                .font(.headline)
                            Text("Keep typing a full domain, like example.com, or paste a link. You'll see exactly what gets blocked before you add it.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(18).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                    }

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(trimmed.isEmpty ? "COMMON WEBSITES" : "SUGGESTIONS")
                                .font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                            ForEach(suggestions) { site in
                                suggestionRow(site)
                            }
                        }
                    }

                    if !model.list.domains.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("ALREADY BLOCKED").font(.caption.weight(.semibold)).tracking(1.5)
                                Spacer()
                                Text("\(model.list.domains.count)/50 domains").font(.caption)
                            }.foregroundStyle(.secondary)
                            ForEach(model.list.domains.sorted(), id: \.self) { domain in
                                HStack {
                                    Text(domain).font(.subheadline)
                                    Spacer()
                                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(accent)
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                    Text("Suggestions stay on your phone. Website filtering also turns off Safari Private Browsing and depends on browser support.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(red: 0.055, green: 0.07, blue: 0.06))
            .navigationTitle("Add websites").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if candidate != nil {
                    VStack(spacing: 10) {
                        Button(action: review) {
                            Label(alreadyBlocked ? "Already blocked" : "Block this website", systemImage: alreadyBlocked ? "checkmark.shield.fill" : "lock.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(alreadyBlocked || capacityExceeded || !model.approved)
                        Text(capacityExceeded ? "This would exceed the 50-domain limit." : "Once added, you can't remove it in OneWay.")
                            .font(.caption).foregroundStyle(capacityExceeded ? .orange : .secondary)
                    }.padding(.horizontal, 24).padding(.vertical, 14).background(.ultraThinMaterial)
                }
            }
            .onChange(of: input) { _, value in
                if !value.isEmpty { success = nil }
                model.error = nil
            }
            .confirmationDialog("Block \(pending?.name ?? "this website")?", isPresented: $showConfirmation, titleVisibility: .visible) {
                Button("Add permanent block") {
                    guard let site = pending else { return }
                    if model.add(domains: site.domains) {
                        input = ""
                        searchFocused = false
                        success = "\(site.name) added to your block list"
                    }
                }
            } message: {
                Text((pending?.domains.sorted().joined(separator: "\n") ?? "") + "\n\nThese domains will stay in your block list. There is no undo in OneWay.")
            }
        }.tint(accent).preferredColorScheme(.dark)
    }

    private func preview(_ site: WebsiteSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                siteIcon(site.symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(site.name).font(.title3.weight(.semibold))
                    Text(alreadyBlocked ? "Already in your block list" : "Ready to block")
                        .font(.subheadline).foregroundStyle(accent)
                }
                Spacer(minLength: 0)
                Image(systemName: alreadyBlocked ? "checkmark.shield.fill" : "arrow.down.circle")
                    .foregroundStyle(accent)
            }
            Divider()
            ForEach(site.domains.sorted(), id: \.self) { domain in
                Label(domain, systemImage: "globe").font(.subheadline).textSelection(.enabled)
            }
            Text("Blocks whole domains, not just the page in a pasted link.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.25), lineWidth: 1))
    }

    private func suggestionRow(_ site: WebsiteSuggestion) -> some View {
        let blocked = site.domains.isSubset(of: model.list.domains)
        return Button {
            input = site.domain
            searchFocused = false
        } label: {
            HStack(spacing: 14) {
                siteIcon(site.symbol)
                VStack(alignment: .leading, spacing: 4) {
                    Text(site.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(site.domain).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if blocked {
                    Label("Blocked", systemImage: "checkmark").font(.caption).foregroundStyle(accent)
                } else {
                    Image(systemName: "arrow.up.left").font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel("\(site.name), \(site.domain)\(blocked ? ", already blocked" : ", preview block")")
    }

    private func siteIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .medium))
            .foregroundStyle(accent).frame(width: 44, height: 44)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func review() {
        guard let site = candidate, !alreadyBlocked, !capacityExceeded else { return }
        pending = site
        searchFocused = false
        showConfirmation = true
    }
}
