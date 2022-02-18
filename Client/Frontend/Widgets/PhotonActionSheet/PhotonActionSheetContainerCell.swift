// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation


// A PhotonActionSheet cell
class PhotonActionSheetContainerCell: UITableViewCell {

    private lazy var containerStackView: UIStackView = .build { stackView in
        stackView.alignment = .fill
        stackView.distribution = .fillProportionally

        // TODO: Laurie - Change alignment when needed
        stackView.axis = .horizontal
    }

    // MARK: - init

    override func prepareForReuse() {
        super.prepareForReuse()
        containerStackView.removeAllArrangedViews()
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        contentView.addSubview(containerStackView)

        setupConstraints()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Table view
    
    func configure(at indexPath: IndexPath, actions: PhotonRowItems, viewModel: PhotonActionSheetViewModel) {
        for action in actions.items {
            action.tintColor = viewModel.tintColor
            configure(with: action)
        }
    }

    //        // TODO: Laurie - Pass in more than 1 action when needed
    //
    //        action.tintColor = viewModel.tintColor
    //        cell.configure(with: [action])
    //
    //        if viewModel.toolbarMenuInversed {
    //            let rowIsLastInSection = indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1
    //            cell.hideBottomBorder(isHidden: rowIsLastInSection)
    //
    //        } else if viewModel.modalStyle == .popover {
    //            let isLastRow = indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1
    //            let isLastSection = indexPath.section == tableView.numberOfSections - 1
    //            let rowIsLast = isLastRow && isLastSection
    //            cell.hideBottomBorder(isHidden: rowIsLast)
    //        }

    // MARK: - Setup

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            containerStackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            containerStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        ])
    }

    func configure(with action: SingleSheetItem) {
        let childView = PhotonActionSheetView()
        childView.configure(with: action)
        containerStackView.addArrangedSubview(childView)
    }

    func hideBottomBorder(isHidden: Bool) {
        containerStackView.arrangedSubviews
          .compactMap { $0 as? PhotonActionSheetView }
          .forEach { $0.bottomBorder.isHidden = isHidden }
    }

    // TODO: Laurie - Add border between child cells
    private func addVerticalBorder(action: PhotonRowItems) {
//        bottomBorder.backgroundColor = UIColor.theme.tableView.separator
//        contentView.addSubview(bottomBorder)
//
//        var constraints = [NSLayoutConstraint]()
//        // Determine if border should be at top or bottom when flipping
//        let top = bottomBorder.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1)
//        let bottom = bottomBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
//        let anchor = action.isFlipped ? top : bottom
//
//        let borderConstraints = [
//            anchor,
//            bottomBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
//            bottomBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
//            bottomBorder.heightAnchor.constraint(equalToConstant: 1)
//        ]
//        constraints.append(contentsOf: borderConstraints)
//
//        NSLayoutConstraint.activate(constraints)
    }
}
