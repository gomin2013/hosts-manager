import SwiftUI

/// Above the list while the file can't be written — what's wrong and how to fix it (replaces the 10 pt
/// "Helper needs approval" caption, audit #12). The list stays readable underneath.
struct HelperBanner: View {
    @Environment(HelperInstaller.self) private var installer

    var body: some View {
        let needsApproval = installer.status == .requiresApproval
        HStack(spacing: 12) {
            Image(systemName: needsApproval ? "lock.shield.fill" : "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(localized(needsApproval ? "banner.approve.title" : "banner.missing.title"))
                    .font(.app(13, .semibold))
                Text(localized(needsApproval ? "banner.approve.desc"
                               : installer.status == .unavailable ? "helper.unavailable" : "banner.missing.desc"))
                    .font(.app(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if needsApproval {
                Button(localized("helper.openSettings"), action: installer.openLoginItems)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

/// Nothing matches the search, or the file has no entries yet.
struct EntriesEmptyState: View {
    @Environment(HostsViewModel.self) private var vm
    var canWrite = true

    var body: some View {
        if vm.isSearching {
            ContentUnavailableView.search(text: vm.searchText)
        } else {
            ContentUnavailableView {
                Label(localized("empty.noEntries.title"), systemImage: "network")
            } description: {
                Text(localized("empty.noEntries.desc"))
            } actions: {
                Button(localized("btn.add"), action: vm.beginAdd).disabled(!canWrite)
            }
        }
    }
}
