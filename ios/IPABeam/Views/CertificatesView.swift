import SwiftUI
import UniformTypeIdentifiers

struct CertificatesView: View {
    @Environment(AppState.self) private var state
    @State private var showAdd = false

    var body: some View {
        Page(title: "Zertifikate", subtitle: "Damit signiert IPA Beam Apps für dein iPhone.") {
            ForEach(state.signingSets) { set in
                CertificateCard(set: set, selected: set.id == state.selectedSigningID)
            }

            Button {
                showAdd = true
            } label: {
                Label("Zertifikat hinzufügen", systemImage: "plus")
            }
            .buttonStyle(BeamButtonStyle())

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Was brauche ich?", symbol: "questionmark.circle.fill")
                info("key.fill", "Zertifikat (.p12)", "Dein Apple-Entwicklerzertifikat inkl. privatem Schlüssel und Passwort – z. B. am Mac aus der Schlüsselbundverwaltung exportiert.")
                info("checkmark.shield.fill", "Provisioning-Profil", "Die .mobileprovision-Datei, in der dein iPhone eingetragen ist.")
                info("lock.fill", "Sicher gespeichert", "Das Passwort liegt verschlüsselt im iOS-Schlüsselbund, die Dateien nur auf diesem Gerät.")
            }
            .glassCard()
        }
        .sheet(isPresented: $showAdd) {
            AddCertificateSheet()
                .presentationDetents([.large])
                .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: state.pendingCertificateFile) { _, newValue in
            if newValue != nil { showAdd = true }
        }
    }

    private func info(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CertificateCard: View {
    @Environment(AppState.self) private var state
    let set: SigningSet
    let selected: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { state.selectedSigningID = set.id }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.accent)
                            .frame(width: 44, height: 44)
                            .shadow(color: Theme.indigo.opacity(0.7), radius: 10)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(set.certificateName)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(2)
                        Text(set.profile.teamName.isEmpty ? set.profile.teamID : "\(set.profile.teamName) · \(set.profile.teamID)")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.success)
                    }
                }
                HStack(spacing: 6) {
                    Pill(text: set.profile.name, symbol: "doc.badge.gearshape.fill", tint: Theme.cyan)
                    Pill(text: set.profile.bundlePattern, symbol: "tag.fill", tint: Theme.indigo)
                }
                HStack(spacing: 6) {
                    Pill(text: set.profile.isExpired ? "Abgelaufen" : "Noch \(set.profile.daysLeft) Tage",
                         symbol: "clock.fill",
                         tint: set.profile.isExpired ? Theme.danger : (set.profile.daysLeft < 8 ? Theme.warning : Theme.success))
                    Pill(text: set.profile.provisionsAllDevices ? "Alle Geräte" : "\(set.profile.deviceCount) Geräte",
                         symbol: "iphone", tint: Theme.magenta)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .neonBorder(cornerRadius: 22, lineWidth: 1.2, active: selected)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation { state.delete(set) }
            } label: {
                Label("Entfernen", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add sheet

private struct AddCertificateSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var p12URL: URL?
    @State private var profileURL: URL?
    @State private var password = ""
    @State private var picking: PickKind?
    @State private var error: String?

    enum PickKind: Identifiable {
        case p12, profile
        var id: Int { self == .p12 ? 0 : 1 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    pickRow(title: "Zertifikat (.p12)", symbol: "key.fill", file: p12URL) { picking = .p12 }
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Theme.cyan)
                            .frame(width: 22)
                        SecureField("Passwort des Zertifikats", text: $password)
                            .textContentType(.password)
                    }
                    .glassCard(padding: 16, cornerRadius: 18)
                    pickRow(title: "Provisioning-Profil", symbol: "checkmark.shield.fill", file: profileURL) { picking = .profile }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.danger)
                    }

                    Button {
                        save()
                    } label: {
                        Label("Prüfen & speichern", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(BeamButtonStyle())
                    .disabled(p12URL == nil || profileURL == nil)
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .navigationTitle("Zertifikat hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: picking == .profile ? [.mobileProvision, .data] : [.p12, .pkcs12, .data]
        ) { result in
            guard case .success(let url) = result else { return }
            if picking == .profile || url.pathExtension.lowercased() == "mobileprovision" {
                profileURL = url
            } else {
                p12URL = url
            }
            picking = nil
        }
        .onAppear {
            if let pending = state.pendingCertificateFile {
                if pending.pathExtension.lowercased() == "mobileprovision" { profileURL = pending } else { p12URL = pending }
                state.pendingCertificateFile = nil
            }
        }
    }

    private func pickRow(title: String, symbol: String, file: URL?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold))
                    Text(file?.lastPathComponent ?? "Datei wählen …")
                        .font(.system(size: 12))
                        .foregroundStyle(file == nil ? Color.white.opacity(0.45) : Theme.success)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: file == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(file == nil ? Color.white.opacity(0.5) : Theme.success)
            }
            .glassCard(padding: 16, cornerRadius: 18)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
    }

    private func save() {
        guard let p12URL, let profileURL else { return }
        do {
            try state.addSigningSet(p12URL: p12URL, password: password, profileURL: profileURL)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
