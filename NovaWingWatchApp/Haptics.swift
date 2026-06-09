import WatchKit

/// Taptic feedback addressed by intent. Auto-fire is deliberately silent
/// (it'd buzz constantly); everything impactful gets a tap.
enum Haptic {
    private static func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    static func kill()      { play(.click) }
    static func playerHit() { play(.failure) }
    static func powerUp()   { play(.success) }
    static func bomb()      { play(.directionDown) }
    static func capture()   { play(.failure) }
    static func rescue()    { play(.success) }
    static func wave()      { play(.notification) }
    static func gameOver()  { play(.failure) }
    static func uiTap()     { play(.click) }
}
