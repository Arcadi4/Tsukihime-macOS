// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Ported from knife (https://github.com/AuroraWright/knife) by AuroraWright: knife/src/ui.rs (enter_side, leave_side, side_nav)
import Foundation

/// A screen opened from a tab of the system menu.
public protocol ISubMenu: AnyObject {
    /// The tab the screen belongs to.
    var tab: Int { get }
    var Tab: Int { get }

    /// The focus helper.
    var side: SideFocus { get }
    var Side: SideFocus { get }
}

public extension ISubMenu {
    var Tab: Int { tab }
    var Side: SideFocus { side }
}

/// The focus of a screen opened from the system menu that sits on the menu's tabs (knife `side`): left from the page's first column hands the cursor to the
/// tabs, up and down move it, decide on another tab opens that tab (the submenu closes), decide on its own tab or right returns to the page, cancel closes
/// the submenu (sub_4CEA0 while a submenu is open).
public final class SideFocus {
    private unowned let _owner: UiScreen
    private let _ownTab: Int

    /// Creates the helper for `owner`, the submenu of system menu tab `ownTab`.
    public init(_ owner: UiScreen, _ ownTab: Int) {
        _owner = owner
        _ownTab = ownTab
    }

    public init(owner: UiScreen, ownTab: Int) {
        _owner = owner
        _ownTab = ownTab
    }

    /// True while the tabs have the focus.
    public private(set) var active: Bool = false
    public var Active: Bool { active }

    /// The system menu under the submenu, or null when the screen was opened from the title.
    public var menu: SystemMenuScreen? {
        guard let root = _owner.root else { return nil }
        return root.stack.compactMap { $0 as? SystemMenuScreen }.first
    }
    public var Menu: SystemMenuScreen? { menu }

    /// Hands the focus to the tabs (false when there is no menu below).
    @discardableResult
    public func enter() -> Bool {
        guard menu != nil else { return false }
        active = true
        return true
    }
    @discardableResult
    public func Enter() -> Bool {
        enter()
    }

    /// Gives the focus back to the page.
    public func leave() {
        active = false
    }
    public func Leave() {
        leave()
    }

    /// Canvas x from which the submenu's page starts (the system menu's window ends at 368).
    private static let pageLeft: Float = 372.0

    private static func overTab(_ input: UiInput) -> Bool {
        for i in 0..<5 {
            if SystemMenuScreen.tabRect(i).contains(input.pointerX, input.pointerY) {
                return true
            }
        }
        return false
    }

    /// Steps the tab focus. Returns true when the input was used (the page must ignore it).
    @discardableResult
    public func step(_ input: UiInput, _ ctx: UiContext) -> Bool {
        guard active, let m = menu else { return false }

        if input.cancel {
            leave()
            ctx.sound(.buzzer)
            _owner.close()
            m.close()
            return true
        }

        // the mouse takes the focus back: a pointer that moves onto the page, or clicks on it, leaves the tabs (package K12)
        if (input.pointerMoved || input.click) && input.pointerActive && input.pointerX >= Self.pageLeft && !Self.overTab(input) {
            leave()
            return false
        }

        let before = ctx.menuTab
        if input.up || input.down {
            ctx.menuTab = (ctx.menuTab + (input.up ? 4 : 1)) % 5
        }

        if input.pointerMoved {
            for i in 0..<5 {
                if SystemMenuScreen.tabRect(i).contains(input.pointerX, input.pointerY) {
                    ctx.menuTab = i
                }
            }
        }

        if ctx.menuTab != before {
            ctx.sound(.cursor)
        }

        if input.right {
            leave()
            return true
        }

        var click = -1
        if input.click {
            for i in 0..<5 {
                if SystemMenuScreen.tabRect(i).contains(input.pointerX, input.pointerY) {
                    click = i
                }
            }
        }

        if input.decide || click >= 0 {
            if click >= 0 {
                ctx.menuTab = click
            }

            if ctx.menuTab == _ownTab {
                leave()
            } else {
                leave()
                _owner.close()
                if let tab = MenuTab(rawValue: ctx.menuTab) {
                    m.act(tab)
                }
            }
        }

        return true
    }

    @discardableResult
    public func Step(_ input: UiInput, _ ctx: UiContext) -> Bool {
        step(input, ctx)
    }

    /// A click on a tab of the menu below while the page has the focus (the tabs stay tappable under the submenu).
    @discardableResult
    public func clickOnTab(_ input: UiInput, _ ctx: UiContext) -> Bool {
        guard input.click, let m = menu else { return false }

        for i in 0..<5 {
            if SystemMenuScreen.tabRect(i).contains(input.pointerX, input.pointerY) {
                ctx.menuTab = i
                if i != _ownTab {
                    _owner.close()
                    if let tab = MenuTab(rawValue: i) {
                        m.act(tab)
                    }
                }
                return true
            }
        }
        return false
    }

    @discardableResult
    public func ClickOnTab(_ input: UiInput, _ ctx: UiContext) -> Bool {
        clickOnTab(input, ctx)
    }
}
