// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

protocol OnboardingCardProtocol {
    var cardType: IntroViewModel.InformationCards { get set }
    var infoModel: InfoModelProtocol { get set }

    func sendCardViewTelemetry()
    func sendTelemetryButton(isPrimaryAction: Bool)
}

struct OnboardingCardViewModel: OnboardingCardProtocol {
    var cardType: IntroViewModel.InformationCards
    var infoModel: InfoModelProtocol

    init(cardType: IntroViewModel.InformationCards,
         infoModel: InfoModelProtocol) {

        self.cardType = cardType
        self.infoModel = infoModel
    }

    func sendCardViewTelemetry() {
        let extra = [TelemetryWrapper.EventExtraKey.cardType.rawValue: cardType.telemetryValue]
        let eventObject: TelemetryWrapper.EventObject = cardType.isOnboardingScreen ?
            . onboardingCardView : .upgradeCardView

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .view,
                                     object: eventObject,
                                     value: nil,
                                     extras: extra)
    }

    func sendTelemetryButton(isPrimaryAction: Bool) {
        let eventObject: TelemetryWrapper.EventObject
        let extra = [TelemetryWrapper.EventExtraKey.cardType.rawValue: cardType.telemetryValue]

        switch (isPrimaryAction, cardType.isOnboardingScreen) {
        case (true, true):
            eventObject = TelemetryWrapper.EventObject.onboardingPrimaryButton
        case (false, true):
            eventObject = TelemetryWrapper.EventObject.onboardingSecondaryButton
        case (true, false):
            eventObject = TelemetryWrapper.EventObject.upgradePrimaryButton
        case (false, false):
            eventObject = TelemetryWrapper.EventObject.upgradeSecondaryButton
        }

        TelemetryWrapper.recordEvent(category: .action,
                                     method: .tap,
                                     object: eventObject,
                                     value: nil,
                                     extras: extra)
    }
}
