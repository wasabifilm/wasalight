import org.kde.falkon 1.0 as Falkon
import QtQuick 2.3

Falkon.PluginInterface {
    function activeTab() {
        var tabs = Falkon.Tabs.getAll({})
        for (var index = 0; index < tabs.length; index++) {
            if (tabs[index].current) {
                return tabs[index]
            }
        }
        return null
    }

    init: function(state, settingsPath) {}
    testPlugin: function() { return true }
    unload: function() {}

    Falkon.BrowserAction {
        id: zoomOutButton
        identity: 'wasalight-companion-zoom-out'
        name: 'Companion zoom out'
        title: 'Zoom −'
        toolTip: 'Zoom −'
        badgeText: '−'
        location: Falkon.BrowserAction.NavigationToolBar
        onClicked: {
            var tab = activeTab()
            if (tab) {
                tab.zoomOut()
            }
        }
    }

    Falkon.BrowserAction {
        id: zoomInButton
        identity: 'wasalight-companion-zoom-in'
        name: 'Companion zoom in'
        title: 'Zoom +'
        toolTip: 'Zoom +'
        badgeText: '+'
        location: Falkon.BrowserAction.NavigationToolBar
        onClicked: {
            var tab = activeTab()
            if (tab) {
                tab.zoomIn()
            }
        }
    }
}
