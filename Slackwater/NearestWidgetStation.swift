// Slackwater — GPL v3. The nearest stations the "Any/Tide/Current Station"
// widgets follow, cached into the App Group by whichever app has a fix: the
// phone's LocationService, and the watch's list (#524).
import Foundation

/// Caches the nearest station of any series, of tide, and of current into the
/// App Group. A namesake chosen in the app answers for its place. Returns
/// whether any key changed, so a caller reloads widget timelines only then.
func cacheNearestWidgetStations(lat: Double, lon: Double,
                                defaults: UserDefaults = AppGroup.defaults) -> Bool {
    var any: (km: Double, item: StationItem)?
    var tide: (km: Double, item: StationItem)?
    var current: (km: Double, item: StationItem)?
    for item in StationItem.all {
        let km = item.km(fromLat: lat, lon: lon)
        if any == nil || km < any!.km { any = (km, item) }
        switch item.series {
        case .tide: if tide == nil || km < tide!.km { tide = (km, item) }
        case .current: if current == nil || km < current!.km { current = (km, item) }
        }
    }
    let chosen = chosenStationIDs(defaults)
    var changed = false
    for (nearest, key) in [(any, AppGroup.currentLocationStationKey),
                           (tide, AppGroup.nearestTideStationKey),
                           (current, AppGroup.nearestCurrentStationKey)] {
        guard let item = nearest?.item else { continue }
        let group = StationItem.byPlace[item.placeKey] ?? []
        let id = group.first { chosen.contains($0.id) }?.id ?? item.id
        guard defaults.string(forKey: key) != id else { continue }
        defaults.set(id, forKey: key)
        changed = true
    }
    return changed
}

/// The namesake picks on disk. Builds before the catalog could rename a
/// station kept them as place key → id; the values are the ids.
func chosenStationIDs(_ defaults: UserDefaults) -> Set<String> {
    if let ids = defaults.stringArray(forKey: AppGroup.chosenStationsKey) { return Set(ids) }
    let legacy = defaults.dictionary(forKey: AppGroup.chosenStationsKey) as? [String: String] ?? [:]
    return Set(legacy.values)
}
