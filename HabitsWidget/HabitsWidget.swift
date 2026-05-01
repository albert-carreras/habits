import WidgetKit
import SwiftUI

@main
struct HabitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        HabitsSmallWidget()
        ThingsSmallWidget()
        HabitsLockScreenWidget()
        AddThingLockScreenWidget()
    }
}
