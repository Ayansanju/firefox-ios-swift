/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

class TrayToBrowserAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func animateTransition(transitionContext: UIViewControllerContextTransitioning) {
        if let bvc = transitionContext.viewControllerForKey(UITransitionContextToViewControllerKey) as? BrowserViewController,
           let tabTray = transitionContext.viewControllerForKey(UITransitionContextFromViewControllerKey) as? TabTrayController {
            transitionFromTray(tabTray, toBrowser: bvc, usingContext: transitionContext)
        }
    }

    func transitionDuration(transitionContext: UIViewControllerContextTransitioning) -> NSTimeInterval {
        return 0.4
    }
}

private extension TrayToBrowserAnimator {
    func transitionFromTray(tabTray: TabTrayController, toBrowser bvc: BrowserViewController, usingContext transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView()
        let tabCollectionView = tabTray.collectionView
        let tabManager = bvc.tabManager
        let browser = bvc.tabManager.selectedTab
        let bvcHeader = bvc.header
        let bvcFooter = bvc.footer
        let tabTrayAddTabButton = tabTray.addTabButton
        let tabTraySettingsButton = tabTray.settingsButton
        let tabIndex = tabManager.selectedIndex
        let urlBar = bvc.urlBar
        let readerModeBar = bvc.readerModeBar

        // Hide browser components
        toggleWebViewVisibility(show: false, usingTabManager: tabManager)
        bvc.homePanelController?.view.hidden = true

        // Take a snapshot of the collection view that we can scale/fade out. We don't need to wait for screen updates since it's already rendered on the screen
        let tabCollectionViewSnapshot = tabCollectionView.snapshotViewAfterScreenUpdates(false)
        tabCollectionView.alpha = 0
        tabCollectionViewSnapshot.frame = tabCollectionView.frame
        container.insertSubview(tabCollectionViewSnapshot, aboveSubview: tabTray.view)

        // Create a fake cell to use for the upscaling animation
        var cellFrame: CGRect?
        if let attr = tabCollectionView.collectionViewLayout.layoutAttributesForItemAtIndexPath(NSIndexPath(forItem: tabIndex, inSection: 0)) {
            cellFrame = tabCollectionView.convertRect(attr.frame, toView: container)
        }
        let cell = createTransitionCellFromBrowser(browser, withFrame: cellFrame!)
        cell.backgroundHolder.layer.cornerRadius = 0

        container.insertSubview(bvc.view, aboveSubview: tabCollectionViewSnapshot)
        container.insertSubview(cell, aboveSubview: bvc.view)

        // Flush any pending layout/animation code in preperation of the animation call
        container.layoutIfNeeded()

        // Reset any transform we had previously on the header and transform them to where the cell will be animating from
        bvcHeader.transform = CGAffineTransformIdentity
        bvcFooter.transform = CGAffineTransformIdentity
        readerModeBar?.transform = CGAffineTransformIdentity
        bvcHeader.transform = transformForHeaderFrame(bvcHeader.frame, toCellFrame: cell.frame)
        bvcFooter.transform = transformForFooterFrame(bvcFooter.frame, toCellFrame: cell.frame)

        // If we're in reader mode, transform it along with the header
        if let readerModeBar = readerModeBar {
            readerModeBar.transform = transformForReaderBarFrame(readerModeBar.frame, toCellFrame: cell.frame)
        }

        var finalFrame = bvc.webViewContainer.frame

        // If we're navigating to a home panel and we were expecting to show the toolbar, add more height to end frame since 
        // there is no toolbar for home panels
        if AboutUtils.isAboutURL(browser?.url) && bvc.shouldShowToolbarForTraitCollection(bvc.traitCollection) {
            bvcFooter.hidden = true
            finalFrame.size.height += UIConstants.ToolbarHeight
        }

        UIView.animateWithDuration(self.transitionDuration(transitionContext),
            delay: 0, usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: UIViewAnimationOptions.CurveEaseInOut,
            animations:
        {
            // Scale up the cell and reset the transforms for the header/footers
            cell.frame = finalFrame
            container.layoutIfNeeded()

            cell.title.transform = CGAffineTransformMakeTranslation(0, -cell.title.frame.height)
            bvcHeader.transform = CGAffineTransformIdentity
            bvcFooter.transform = CGAffineTransformIdentity
            readerModeBar?.transform = CGAffineTransformIdentity

            urlBar.updateAlphaForSubviews(1)
            bvcFooter.alpha = 1

            tabCollectionViewSnapshot.transform = CGAffineTransformMakeScale(0.9, 0.9)
            tabCollectionViewSnapshot.alpha = 0

            // Push out the navigation bar buttons
            let buttonOffset = tabTrayAddTabButton.frame.width + TabTrayControllerUX.ToolbarButtonOffset
            tabTrayAddTabButton.transform = CGAffineTransformTranslate(CGAffineTransformIdentity, buttonOffset , 0)
            tabTraySettingsButton.transform = CGAffineTransformTranslate(CGAffineTransformIdentity, -buttonOffset , 0)

        }, completion: { finished in
            // Remove any of the views we used for the animation
            cell.removeFromSuperview()
            tabCollectionViewSnapshot.removeFromSuperview()

            bvc.startTrackingAccessibilityStatus()
            toggleWebViewVisibility(show: true, usingTabManager: tabManager)
            bvc.homePanelController?.view.hidden = false
            bvcFooter.hidden = false
            transitionContext.completeTransition(true)
        })
    }
}

class BrowserToTrayAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func animateTransition(transitionContext: UIViewControllerContextTransitioning) {
        if let bvc = transitionContext.viewControllerForKey(UITransitionContextFromViewControllerKey) as? BrowserViewController,
           let tabTray = transitionContext.viewControllerForKey(UITransitionContextToViewControllerKey) as? TabTrayController {
            transitionFromBrowser(bvc, toTabTray: tabTray, usingContext: transitionContext)
        }
    }

    func transitionDuration(transitionContext: UIViewControllerContextTransitioning) -> NSTimeInterval {
        return 0.4
    }
}

private extension BrowserToTrayAnimator {
    func transitionFromBrowser(bvc: BrowserViewController, toTabTray tabTray: TabTrayController, usingContext transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView()
        let tabCollectionView = tabTray.collectionView
        let tabManager = bvc.tabManager
        let browser = bvc.tabManager.selectedTab
        let bvcHeader = bvc.header
        let bvcFooter = bvc.footer
        let tabTrayAddTabButton = tabTray.addTabButton
        let tabTraySettingsButton = tabTray.settingsButton
        let tabIndex = tabManager.selectedIndex
        let urlBar = bvc.urlBar
        let readerModeBar = bvc.readerModeBar

        // Insert tab tray below the browser and force a layout so the collection view can get it's frame right
        container.insertSubview(tabTray.view, belowSubview: bvc.view)

        // Force subview layout on the collection view so we can calculate the correct end frame for the animation
        tabTray.view.layoutSubviews()
        tabCollectionView.scrollToItemAtIndexPath(NSIndexPath(forItem: tabIndex, inSection: 0), atScrollPosition: .CenteredVertically, animated: false)

        // Build a tab cell that we will use to animate the scaling of the browser to the tab
        let cell = createTransitionCellFromBrowser(browser, withFrame: tabCollectionView.frame)

        // Take a snapshot of the collection view to perform the scaling/alpha effect
        let tabCollectionViewSnapshot = tabCollectionView.snapshotViewAfterScreenUpdates(true)
        tabCollectionViewSnapshot.frame = tabCollectionView.frame
        tabCollectionViewSnapshot.transform = CGAffineTransformMakeScale(0.9, 0.9)
        tabCollectionViewSnapshot.alpha = 0
        tabTray.view.addSubview(tabCollectionViewSnapshot)

        cell.title.transform = CGAffineTransformMakeTranslation(0, -cell.title.frame.size.height)
        container.addSubview(cell)
        cell.layoutIfNeeded()

        // Hide views we don't want to show during the animation in the BVC
        bvc.homePanelController?.view.hidden = true
        toggleWebViewVisibility(show: false, usingTabManager: tabManager)

        // Since we are hiding the collection view and the snapshot API takes the snapshot after the next screen update,
        // the screenshot ends up being blank unless we set the collection view hidden after the screen update happens. 
        // To work around this, we dispatch the setting of collection view to hidden after the screen update is completed.
        dispatch_async(dispatch_get_main_queue()) {
            tabCollectionView.hidden = true
            var finalFrame: CGRect?
            if let attr = tabCollectionView.collectionViewLayout.layoutAttributesForItemAtIndexPath(NSIndexPath(forItem: tabIndex, inSection: 0)) {
                finalFrame = tabCollectionView.convertRect(attr.frame, toView: container)
            }

            UIView.animateWithDuration(self.transitionDuration(transitionContext),
                delay: 0, usingSpringWithDamping: 1,
                initialSpringVelocity: 0,
                options: UIViewAnimationOptions.CurveEaseInOut,
                animations:
            {
                if let finalFrame = finalFrame {
                    cell.frame = finalFrame
                    cell.layoutIfNeeded()

                    cell.title.transform = CGAffineTransformIdentity
                    bvcHeader.transform = transformForHeaderFrame(bvcHeader.frame, toCellFrame: finalFrame)
                    bvcFooter.transform = transformForFooterFrame(bvcFooter.frame, toCellFrame: finalFrame)

                    if let readerModeBar = readerModeBar {
                        readerModeBar.transform = transformForReaderBarFrame(readerModeBar.frame, toCellFrame: finalFrame)
                    }
                }

                urlBar.updateAlphaForSubviews(0)
                bvcFooter.alpha = 0

                tabCollectionViewSnapshot.transform = CGAffineTransformIdentity
                tabCollectionViewSnapshot.alpha = 1
                tabTrayAddTabButton.transform = CGAffineTransformIdentity
                tabTraySettingsButton.transform = CGAffineTransformIdentity
            }, completion: { finished in
                // Remove any of the views we used for the animation
                cell.removeFromSuperview()
                tabCollectionViewSnapshot.removeFromSuperview()
                tabCollectionView.hidden = false

                toggleWebViewVisibility(show: true, usingTabManager: tabManager)
                bvc.homePanelController?.view.hidden = false
                bvc.stopTrackingAccessibilityStatus()

                transitionContext.completeTransition(true)
            })
        }
    }
}

private func toggleWebViewVisibility(#show: Bool, usingTabManager tabManager: TabManager) {
    for i in 0..<tabManager.count {
        if let tab = tabManager[i] {
            tab.webView?.hidden = !show
        }
    }
}


/**
Helper methods for calculate affine transforms from frame A to frame B
*/
private func transformForHeaderFrame(headerFrame: CGRect, toCellFrame cellFrame: CGRect) -> CGAffineTransform {
    let scale = cellFrame.size.width / headerFrame.size.width
    // Since the scale will happen in the center of the frame, we move this so the centers of the two frames overlap.
    let tx = cellFrame.origin.x + cellFrame.width/2 - (headerFrame.origin.x + headerFrame.width/2)
    let ty = cellFrame.origin.y - headerFrame.origin.y * scale * 2 // Move this up a little actually keeps it above the web page. I'm not sure what you want
    var transform = CGAffineTransformMakeTranslation(tx, ty)
    return CGAffineTransformScale(transform, scale, scale)
}

private func transformForFooterFrame(footerFrame: CGRect, toCellFrame cellFrame: CGRect) -> CGAffineTransform {
    let tx = cellFrame.origin.x + cellFrame.width/2 - (footerFrame.origin.x + footerFrame.width/2)
    var footerTransform = CGAffineTransformMakeTranslation(tx, -footerFrame.origin.y + cellFrame.origin.y + cellFrame.size.height - footerFrame.size.height)
    let footerScale = cellFrame.size.width / footerFrame.size.width
    return CGAffineTransformScale(footerTransform, footerScale, footerScale)
}

private func transformForReaderBarFrame(readerBarFrame: CGRect, toCellFrame cellFrame: CGRect) -> CGAffineTransform {
    let scale = cellFrame.size.width / readerBarFrame.size.width
    // Since the scale will happen in the center of the frame, we move this so the centers of the two frames overlap.
    let tx = cellFrame.origin.x + cellFrame.width/2 - (readerBarFrame.origin.x + readerBarFrame.width/2)
    let ty = cellFrame.origin.y - readerBarFrame.origin.y * scale * 2 // Move this up a little actually keeps it above the web page. I'm not sure what you want
    var transform = CGAffineTransformMakeTranslation(tx, ty)
    return CGAffineTransformScale(transform, scale, scale)
}

private func createTransitionCellFromBrowser(browser: Browser?, withFrame frame: CGRect) -> TabCell {
    let cell = TabCell(frame: frame)
    cell.background.image = browser?.screenshot
    cell.titleText.text = browser?.displayTitle
    if let favIcon = browser?.displayFavicon {
        cell.favicon.sd_setImageWithURL(NSURL(string: favIcon.url)!)
    } else {
        cell.favicon.image = UIImage(named: "defaultFavicon")
    }
    cell.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius
    cell.innerStroke.hidden = true
    return cell
}
