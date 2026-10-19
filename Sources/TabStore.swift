import Foundation

/// One persisted tab: its last known URL and palette index (`0` = no colour).
struct TabRecord: Codable, Equatable {
    var url: String
    var color: Int
}

/// UserDefaults persistence for the open tabs and the selected index.
///
/// Missing or corrupt data is tolerated and degrades to "no tabs", which the
/// caller treats as a first launch.
enum TabStore {
    static let tabsKey = "PiWebTabs"
    static let selectedKey = "PiWebTabsSelected"

    static func load(from defaults: UserDefaults = .standard) -> (tabs: [TabRecord], selected: Int) {
        guard let data = defaults.data(forKey: tabsKey),
              let tabs = try? JSONDecoder().decode([TabRecord].self, from: data) else {
            return ([], 0)
        }
        return (tabs, defaults.integer(forKey: selectedKey))
    }

    static func save(tabs: [TabRecord], selected: Int, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(tabs) {
            defaults.set(data, forKey: tabsKey)
        }
        defaults.set(selected, forKey: selectedKey)
    }
}
