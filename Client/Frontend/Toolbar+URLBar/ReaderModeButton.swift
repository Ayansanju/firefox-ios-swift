// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Shared

class ReaderModeButton: UIButton {
    // MARK: - Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)
        adjustsImageWhenHighlighted = false
        setImage(UIImage.templateImageNamed("reader"), for: .normal)
        imageView?.contentMode = .scaleAspectFit
        contentHorizontalAlignment = .center
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Variables

    var selectedTintColor: UIColor?
    var unselectedTintColor: UIColor?

    override var isSelected: Bool {
        didSet {
            self.tintColor = (isHighlighted || isSelected) ? selectedTintColor : unselectedTintColor
        }
    }

    override open var isHighlighted: Bool {
        didSet {
            self.tintColor = (isHighlighted || isSelected) ? selectedTintColor : unselectedTintColor
        }
    }

    override var tintColor: UIColor! {
        didSet {
            self.imageView?.tintColor = self.tintColor
        }
    }

    private var savedReaderModeState = ReaderModeState.unavailable

    var readerModeState: ReaderModeState {
        get {
            return savedReaderModeState
        }
        set (newReaderModeState) {
            savedReaderModeState = newReaderModeState
            switch savedReaderModeState {
            case .available:
                self.isEnabled = true
                self.isSelected = false
            case .unavailable:
                self.isEnabled = false
                self.isSelected = false
            case .active:
                self.isEnabled = true
                self.isSelected = true
            }
        }
    }
}

extension ReaderModeButton: NotificationThemeable {
    func applyTheme() {
        selectedTintColor = UIColor.legacyTheme.urlbar.readerModeButtonSelected
        unselectedTintColor = UIColor.legacyTheme.urlbar.readerModeButtonUnselected
    }
}

extension ReaderModeButton: ThemeApplicable {
    func applyTheme(theme: Theme) {
        selectedTintColor = theme.colors.actionPrimary
        unselectedTintColor = theme.colors.actionSecondary
    }
}
