import AppKit
import ClockifyCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: TrackerModel
    @State private var description = ""
    @State private var apiKey = ""
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(model.running == nil ? Color.accentColor : .red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clockify Bar").font(.headline)
                    Text(model.connected ? model.workspaceName : "A little less friction. A little more focus.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if model.showSettings || !model.connected { settings }
            else { tracker }

            Divider()
            HStack {
                Button { NSWorkspace.shared.open(URL(string: "https://app.clockify.me/tracker")!) } label: {
                    Label("Open Clockify", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    model.showSettings.toggle()
                    apiKey = ""
                } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
                    .disabled(model.busy)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.plain).help("Quit (leaves any Clockify timer running)")
                    .accessibilityLabel("Quit Clockify Bar")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { descriptionFocused = true }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.connected ? "Settings" : "Connect your account").font(.title3.weight(.semibold))
            Text("Paste your Clockify API key. It’s stored securely in macOS Keychain.")
                .font(.callout).foregroundStyle(.secondary)
            SecureField(model.connected ? "New API key" : "API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { connect() }
            HStack {
                Link("Get your API key ↗", destination: URL(string: "https://app.clockify.me/user/settings")!)
                    .font(.caption)
                Spacer()
                Button(model.connected ? "Update key" : "Connect", action: connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
            }
            if model.connected {
                Divider()
                Picker("Workspace", selection: Binding(get: { model.workspaceID }, set: { id in
                    Task { await model.selectWorkspace(id) }
                })) {
                    ForEach(model.workspaces) { workspace in Text(workspace.name).tag(workspace.id) }
                }.disabled(model.busy)
                Text("The icon tracks the selected workspace. Switching workspaces or quitting does not stop timers.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Done") { model.showSettings = false }.disabled(model.busy)
            }
            Text("Status syncs every 5 minutes and when you open the menu. Click the icon to open this menu, including while tracking.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var tracker: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.statusKnown {
                Label("Status needs a refresh", systemImage: "questionmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let running = model.running {
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.statusKnown ? "TRACKING NOW" : "LAST KNOWN TIMER", systemImage: "record.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    Text(running.title).font(.title3.weight(.medium)).lineLimit(3)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(duration(from: running.timeInterval.start, to: context.date))
                            .font(.system(size: 28, weight: .light, design: .monospaced))
                    }
                    Button {
                        Task { await model.stop() }
                    } label: { Label("Stop tracking", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(.red).disabled(model.busy || !model.statusKnown)
                }
            } else {
                newEntryInput
                if let error = model.projectError {
                    Text(error + " Use Refresh to try again.")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            recentEntries
            HStack {
                if let sync = model.lastSync {
                    Text("Synced \(sync.formatted(date: .omitted, time: .shortened))")
                }
                Spacer()
                Button { Task { await model.refresh(includeHistory: true, force: true) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }.buttonStyle(.plain).disabled(model.busy)
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private var canStart: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.busy && model.statusKnown
    }

    private var selectedProjectName: String {
        model.projects.first { $0.id == model.selectedProjectID }?.name ?? "No project"
    }

    private var newEntryInput: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Project", selection: $model.selectedProjectID) {
                    Text("No project").tag("")
                    ForEach(model.projects) { project in
                        Text(project.name).tag(project.id)
                    }
                }.pickerStyle(.inline)
            } label: {
                Image(systemName: model.selectedProjectID.isEmpty ? "folder" : "folder.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(model.selectedProjectID.isEmpty ? Color.secondary : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Project: " + selectedProjectName)
            .accessibilityLabel("Choose project").accessibilityValue(selectedProjectName)
            .disabled(model.busy)

            Divider().frame(height: 18)

            TextField("What are you working on?", text: $description)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($descriptionFocused)
                .onSubmit { startNew() }
                .accessibilityLabel("New time entry description")

            Button(action: startNew) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .offset(x: 1)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor, in: Circle())
                    .opacity(canStart ? 1 : 0.4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).help("Start tracking (Return)")
            .accessibilityLabel("Start tracking")
            .disabled(!canStart)
        }
        .padding(6)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(descriptionFocused ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var recentEntries: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT ENTRIES").font(.caption.weight(.semibold))
                Spacer()
                Text(model.running == nil ? "Click to start again" : "Stop the timer to start again").font(.caption)
            }.foregroundStyle(.secondary)
            if model.recent.isEmpty {
                Text(model.busy ? "Loading your recent entries…" : model.error != nil
                     ? "Recent entries couldn’t be loaded. Try Refresh."
                     : "No completed entries in this workspace yet. Check your workspace in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.recent) { entry in
                            Button {
                                Task { await model.start(description: entry.description ?? "", copying: entry) }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title).font(.system(size: 13, weight: .medium))
                                            .lineLimit(2).multilineTextAlignment(.leading)
                                        HStack(spacing: 6) {
                                            Text(entry.timeInterval.start, style: .date)
                                            if let end = entry.timeInterval.end {
                                                Text("· " + duration(from: entry.timeInterval.start, to: end))
                                            }
                                            if entry.projectId != nil { Image(systemName: "folder") }
                                        }.font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "play.circle").font(.title3).foregroundStyle(Color.accentColor)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(model.busy || !model.statusKnown || model.running != nil)
                            .help("Start a new timer with this description, project, task, tags, and billability")
                        }
                    }
                // A ScrollView has no intrinsic height in an NSPopover.
                // Reserve space so loaded rows cannot collapse to zero height.
                }.frame(height: min(CGFloat(model.recent.count) * 72, 288))
            }
        }
    }

    private func connect() {
        Task {
            await model.connect(key: apiKey)
            if !model.showSettings { apiKey = "" }
        }
    }

    private func startNew() {
        guard model.statusKnown else { return }
        Task {
            await model.start(description: description)
            if model.running != nil, model.error == nil { description = "" }
        }
    }

    private func duration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
