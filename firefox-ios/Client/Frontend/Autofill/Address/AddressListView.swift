// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import Common
import Shared
import Storage

// MARK: - AddressListView

/// A view displaying a list of addresses.
struct AddressListView: View {
    // MARK: - Constants

    enum Constants {
        static let imageWidth: CGFloat = 200
        static let contentUnavailableViewPadding: CGFloat = 24
        static let vStackSpacing: CGFloat = 0
        static let titleFontSize: CGFloat = 22
        static let subtitleFontSize: CGFloat = 16
        static let contentUnavailableViewTopPadding: CGFloat = 125
    }

    // MARK: - Properties

    let windowUUID: WindowUUID
    @Environment(\.themeManager)
    var themeManager
    @ObservedObject var viewModel: AddressListViewModel
    @State private var customLightGray: Color = .clear

    @State var titleTextColor: Color = .clear
    @State var subTextColor: Color = .clear
    @State var imageColor: Color = .clear

    // MARK: - Body

    var body: some View {
        Group {
            if viewModel.showSection {
                List {
                    Section(header: Text(String.Addresses.Settings.SavedAddressesSectionTitle)) {
                        ForEach(viewModel.addresses, id: \.self) { address in
                            AddressCellView(
                                windowUUID: windowUUID,
                                address: address,
                                onTap: {
                                    if viewModel.isEditingFeatureEnabled {
                                        viewModel.addressTapped(address)
                                    }
                                }
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundColor(customLightGray)
                }
                .listStyle(.plain)
                .listRowInsets(EdgeInsets())
            } else {
                contentUnavailableView
                    .padding(.top, Constants.contentUnavailableViewTopPadding)
                    .padding(.horizontal, Constants.contentUnavailableViewPadding)
                Spacer()
            }
        }
        .sheet(item: $viewModel.destination) { destination in
            NavigationView {
                switch destination {
                case .add:
                    EditAddressViewControllerRepresentable(model: viewModel)
                        .navigationBarTitle(String.Addresses.Settings.Edit.AutofillAddAddressTitle, displayMode: .inline)
                        .navigationBarItems(
                            leading: Button(String.Addresses.Settings.Edit.CloseNavBarButtonLabel) {
                                viewModel.cancelAddButtonTap()
                            },
                            trailing: Button(String.Addresses.Settings.Edit.AutofillSaveButton) {
                                viewModel.saveAddressButtonTap()
                            }
                        )

                case .edit:
                    EditAddressViewControllerRepresentable(model: viewModel)
                        .toolbar {
                            ToolbarItemGroup(placement: .cancellationAction) {
                                Button(String.Addresses.Settings.Edit.AutofillCancelButton) {
                                    viewModel.cancelEditButtonTap()
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            viewModel.fetchAddresses()
            applyTheme(theme: themeManager.getCurrentTheme(for: windowUUID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .ThemeDidChange)) { notification in
            guard let uuid = notification.windowUUID, uuid == windowUUID else { return }
            applyTheme(theme: themeManager.getCurrentTheme(for: windowUUID))
        }
    }

    // MARK: - Theme Application

    /// Applies the theme to the view.
    /// - Parameter theme: The theme to be applied.
    func applyTheme(theme: Theme) {
        let color = theme.colors
        customLightGray = Color(color.textSecondary)
        titleTextColor = Color(color.textPrimary)
        subTextColor = Color(color.textSecondary)
        imageColor = Color(color.iconSecondary)
    }

    @ViewBuilder var contentUnavailableView: some View {
        VStack {
            Image(StandardImageIdentifiers.Large.location)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.imageWidth)
                .foregroundColor(imageColor)
                .accessibility(hidden: true)

            VStack(spacing: Constants.vStackSpacing) {
                Text(
                    String(
                        format: String.Addresses.Settings.SaveAddressesToFirefox,
                        AppName.shortName.rawValue
                    )
                )
                .preferredBodyFont(size: Constants.titleFontSize)
                .foregroundColor(titleTextColor)

                Text(String.Addresses.Settings.SecureSaveInfo)
                    .preferredBodyFont(size: Constants.subtitleFontSize)
                    .foregroundColor(subTextColor)
            }
            .multilineTextAlignment(.center)
        }
    }
}
