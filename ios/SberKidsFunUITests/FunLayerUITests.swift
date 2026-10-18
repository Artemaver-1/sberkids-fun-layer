import XCTest

/// Настоящие жесты на устройстве — то, что не проверить юнит-тестами ядра:
/// удержание аватарки (призраки) и «потянуть ленту и держать» (обезьянка).
///
///     xcodebuild test -project SberKidsFun.xcodeproj -scheme SberKidsFun \
///       -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates
///
/// Тост «найдено … из 4» появляется в конце эффекта — по нему тест понимает, что пасхалка сработала.
final class FunLayerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        sleep(3)
        return app
    }

    private func foundToast(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "найден")).firstMatch
    }

    /// Точка в окне в pt (макет 780 px шириной → 0,5 pt на пиксель).
    private func point(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    func testGhostsNeedFullHoldOnAvatar() {
        let app = launch(["-push", "profile"])
        let avatar = point(app, 195, 240)

        // обычное нажатие и короткое удержание — ничего не происходит
        avatar.tap()
        avatar.press(forDuration: 2.5)
        XCTAssertFalse(foundToast(app).waitForExistence(timeout: 9), "призраки не должны появляться от короткого удержания")

        // 5 секунд на аватарке — призраки
        avatar.press(forDuration: 6)
        XCTAssertTrue(foundToast(app).waitForExistence(timeout: 12), "после удержания аватарки 5 с должны быть призраки и тост")
    }

    func testMonkeyPullAndKeepHolding() {
        let app = launch(["-tab", "content"])
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        // тянем ленту вниз и не отпускаем палец 4 с — обезьянка должна пробежать, пока палец держит
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: XCUIGestureVelocity(500), thenHoldForDuration: 4)
        XCTAssertTrue(foundToast(app).waitForExistence(timeout: 8), "обезьянка должна доиграть до конца и показать тост")
    }
}
