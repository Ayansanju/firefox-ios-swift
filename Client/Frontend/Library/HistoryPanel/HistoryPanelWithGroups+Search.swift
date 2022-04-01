// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

// MARK: - UISearchBarDelegate
extension HistoryPanelWithGroups: UISearchBarDelegate {
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let searchText = searchBar.text, !searchText.isEmpty else { return }

        // Do search and show
        performSearch(term: searchText)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard let searchText = searchBar.text, !searchText.isEmpty else {
            return
        }

        // Do cancelable search
        performSearch(term: searchText)
    }
    
    func exitSearchState() {
        applySnapshot()
        self.searchbar.resignFirstResponder()
        viewModel.isSearchInProgress = false
        toggleEmptyState()
    }
    
    // Using mock query that returns history from today's section
    // TODO: Replace with query in https://mozilla-hub.atlassian.net/browse/FXIOS-4000
    private func performSearch(term: String) {
        viewModel.performSearch(term: term) { success in
            guard success, !viewModel.filterMockSites.isEmpty else {
                toggleEmptyState()
                return
            }
            
            // Create search results snapshot and apply
            var snapshot = NSDiffableDataSourceSnapshot<HistoryPanelSections, AnyHashable>()
            snapshot.appendSections([HistoryPanelSections.searchResults])
            snapshot.appendItems(viewModel.filterMockSites)
            diffableDatasource?.apply(snapshot, animatingDifferences: false)
        }
    }
}

// MARK: - KeyboardHelperDelegate
extension HistoryPanelWithGroups: KeyboardHelperDelegate {
    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        keyboardState = state
    }
    
    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardDidShowWithState state: KeyboardState) {
        keyboardState = state
        updateLayoutForKeyboard()
        UIView.animate(withDuration: state.animationDuration, delay: 0,
                       options: [UIView.AnimationOptions(rawValue: UInt(state.animationCurve.rawValue << 16))], animations: {
            self.bottomStackView.layoutIfNeeded()
        })
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        keyboardState = nil
        updateLayoutForKeyboard()
        UIView.animate(withDuration: state.animationDuration, delay: 0,
                       options: [UIView.AnimationOptions(rawValue: UInt(state.animationCurve.rawValue << 16))], animations: {
            self.bottomStackView.layoutIfNeeded()
        })
    }
}
