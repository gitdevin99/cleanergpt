import SwiftUI
import WidgetKit

@main
struct CleanerWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        BatteryPulseWidget()
        StorageOrbitWidget()
        ComboDashboardWidget()
        DeviceHealthWidget()
        LastScanWidget()
        QuickCleanWidget()
        WaterEjectWidget()
        DustCleanWidget()
    }
}
