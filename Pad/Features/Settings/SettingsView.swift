import DashUpKit
import PhotosUI
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmForget = false
    @State private var newTitle = ""
    @State private var newURL = ""
    @State private var photo: PhotosPickerItem?

    var body: some View {
        @Bindable var settings = model.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings").font(.ui(30, .semibold)).tracking(-0.66).foregroundStyle(Theme.text)
                    .padding(.bottom, Theme.sectionGap)

                group("Mac") {
                    row {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.macName ?? "Not paired").font(.ui(15, .semibold)).foregroundStyle(Theme.text)
                            ConnectionLabel()
                        }
                        Spacer()
                        QuietButton(title: "Forget this Mac", color: Theme.needsText) { confirmForget = true }
                    }
                }

                group("You") {
                    row {
                        Text("Name for the greeting").font(.ui(14.5)).foregroundStyle(Theme.text)
                        Spacer()
                        TextField("", text: $settings.name, prompt: Text(model.firstName.isEmpty ? "Your name" : model.firstName).foregroundStyle(Theme.text3))
                            .font(.ui(14.5))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.text)
                            .frame(width: 240)
                    }
                }

                group("Background") {
                    row {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surface2)
                            if let image = model.backgroundImage {
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                        }
                        .frame(width: 72, height: 48)
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Photo behind the cards").font(.ui(14.5)).foregroundStyle(Theme.text)
                            Text(model.backgroundImage == nil ? "None — the plain dark background." : "Darkened so text stays readable.")
                                .font(.ui(12.5)).foregroundStyle(Theme.text3)
                        }
                        Spacer()
                        if model.backgroundImage != nil {
                            QuietButton(title: "Remove") { model.removeBackground() }
                        }
                        PhotosPicker(selection: $photo, matching: .images) {
                            Text(model.backgroundImage == nil ? "Choose photo" : "Change")
                                .font(.ui(13.5, .medium))
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(Theme.surface2, in: .rect(cornerRadius: 11, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline2))
                        }
                    }
                    if model.backgroundImage != nil {
                        row {
                            Text("Dim").font(.ui(14.5)).foregroundStyle(Theme.text).frame(width: 80, alignment: .leading)
                            Slider(value: $settings.backgroundDim, in: 0.2...0.9).tint(Theme.text2)
                        }
                        row {
                            Text("Blur").font(.ui(14.5)).foregroundStyle(Theme.text).frame(width: 80, alignment: .leading)
                            Slider(value: $settings.backgroundBlur, in: 0...40).tint(Theme.text2)
                        }
                    }
                }
                .onChange(of: photo) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) { model.setBackground(data) }
                        photo = nil
                    }
                }

                group("Standby") {
                    row {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dim to the desk clock after").font(.ui(14.5)).foregroundStyle(Theme.text)
                            Text("A request from Claude Code still shows up, and you can answer it there.")
                                .font(.ui(12.5)).foregroundStyle(Theme.text3)
                        }
                        Spacer()
                        Picker("", selection: $settings.standbyMinutes) {
                            Text("Never").tag(0)
                            Text("2 minutes").tag(2)
                            Text("5 minutes").tag(5)
                            Text("10 minutes").tag(10)
                            Text("30 minutes").tag(30)
                        }
                        .tint(Theme.text2)
                    }
                    row {
                        Text("Show standby now").font(.ui(14.5)).foregroundStyle(Theme.text)
                        Spacer()
                        OutlineButton(title: "Dim") { model.enterStandby() }
                    }
                }

                group("Open in Chrome") {
                    ForEach(model.settings.sites) { site in
                        row {
                            Favicon(url: site.url, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(site.title).font(.ui(14.5)).foregroundStyle(Theme.text)
                                Text(site.url).font(.ui(12.5)).foregroundStyle(Theme.text3)
                            }
                            Spacer()
                            QuietButton(title: "Remove") { model.settings.sites.removeAll { $0.id == site.id } }
                        }
                    }
                    row {
                        TextField("", text: $newTitle, prompt: Text("Name").foregroundStyle(Theme.text3))
                            .frame(width: 180)
                        TextField("", text: $newURL, prompt: Text("URL").foregroundStyle(Theme.text3))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Spacer()
                        QuietButton(title: "Add", color: Theme.text) {
                            let url = newURL.contains("://") ? newURL : "https://\(newURL)"
                            guard !newURL.isEmpty else { return }
                            model.settings.sites.append(.init(title: newTitle.isEmpty ? Favicon.host(url) : newTitle, url: url))
                            newTitle = ""
                            newURL = ""
                        }
                    }
                    .font(.ui(14.5))
                    .foregroundStyle(Theme.text)
                }

                group("Pinned apps") {
                    row {
                        Text("Long-press any app and choose Pin to Home. Pinned apps that aren't open sit at the end of the Apps row.")
                            .font(.ui(13.5)).foregroundStyle(Theme.text2).lineSpacing(3)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.immediately)
        .alert("Forget \(model.macName ?? "this Mac")?", isPresented: $confirmForget) {
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive) { model.forgetMac() }
        } message: {
            Text("You'll need a new code from the Mac to pair again.")
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title)
            VStack(spacing: 0) { content() }
                .card()
        }
        .padding(.bottom, 32)
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) { content() }
            .padding(.horizontal, 18)
            .frame(minHeight: 60)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
