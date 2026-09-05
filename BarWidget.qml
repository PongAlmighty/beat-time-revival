import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Beat-time pill: the current Swatch Internet Time (e.g. "@767") that
// expands to each configured zone's local time and day/night glyph on
// hover; right click opens the 1000-beat grid (left click is left to the
// bar/compositor).
BarWidget {
  id: root
  moduleName: "io.github.pongalmighty.beattime"

  // Optional glyph in front of the beat. Sanitized because WidgetButton's
  // internal Text uses AutoText, which would rich-text-parse a crafted
  // setting.
  readonly property string icon: Model.plainText(setting("icon", ""))

  // Set "hoverExpand": false on the widget entry to keep the pill a static
  // beat — the expansion shifts neighboring bar widgets, which not everyone
  // wants.
  readonly property bool hoverExpand: setting("hoverExpand", true) === true

  readonly property string beat: panelLoader.item ? panelLoader.item.beatLabel : "@···"
  readonly property var compactParts: panelLoader.item ? panelLoader.item.compactParts : []
  readonly property string compact: compactParts.join(Model.SEPARATOR)
  readonly property bool expanded: hoverExpand && !vertical && button.tooltipHovered && compact !== ""

  // With up to `tickerZones` rows in the popup (home included) the hover
  // label sits still. Past that it becomes a window the width of the
  // entries that fit under that count and the full list scrolls through
  // it slowly, ticker style, so a long list never shoves the neighboring
  // widgets around.
  readonly property int zoneCount: panelLoader.item ? panelLoader.item.zoneCount : 0
  readonly property int tickerZones: Math.max(2, parseInt(setting("tickerZones", 3), 10) || 3)
  readonly property real tickerSpeed: Math.max(1, Number(setting("tickerSpeed", 22)) || 22)
  readonly property bool ticker: zoneCount > tickerZones
  readonly property string tickerWindowText: compactParts.slice(0, tickerZones - 1).join(Model.SEPARATOR)
  readonly property string tickerLoopText: compact + Model.SEPARATOR

  // Vertical bars stack the beat one character per line, like the clock.
  readonly property var verticalLines: beat.split("")

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.pongalmighty.beattime"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
    function add(): void { if (panelLoader.item) panelLoader.item.openAddFromHotkey() }
    function addZone(zone: string): void { if (panelLoader.item) panelLoader.item.addZone(zone, "", "") }
    function removeZone(zone: string): void { if (panelLoader.item) panelLoader.item.removeZoneByName(zone) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Keep WidgetButton as the interaction surface, but draw the beat and
    // expanding label separately so centering a longer string cannot move
    // the beat. The button grows only to the right of its fixed position.
    text: " "
    fixedWidth: root.vertical ? -1 : labelRow.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? verticalCol.implicitHeight + scaledVerticalPadding * 2 : -1
    foreground: "transparent"
    tooltipText: ""

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.togglePanel()
      else if (b === Qt.MiddleButton) root.refresh()
    }
  }

  readonly property color labelColor: button.active && button.useActiveColor
    ? button.activeColor
    : (root.bar ? root.bar.barForeground : Color.foreground)

  Row {
    id: labelRow
    visible: !root.vertical
    anchors.left: button.left
    anchors.leftMargin: button.scaledHorizontalMargin
    anchors.verticalCenter: button.verticalCenter
    spacing: root.expanded ? Style.space(8) : 0

    Text {
      visible: root.icon !== ""
      text: root.icon + " "
      textFormat: Text.PlainText
      color: root.labelColor
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      renderType: Text.NativeRendering
    }

    Text {
      text: root.beat
      textFormat: Text.PlainText
      color: root.labelColor
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      renderType: Text.NativeRendering
    }

    Text {
      visible: root.expanded && !root.ticker
      text: root.compact
      textFormat: Text.PlainText
      color: root.labelColor
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      renderType: Text.NativeRendering
    }

    Item {
      id: tickerView
      visible: root.expanded && root.ticker
      clip: true
      width: windowMeter.advanceWidth
      height: scroller.implicitHeight
      anchors.verticalCenter: parent.verticalCenter

      TextMetrics {
        id: windowMeter
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        text: root.tickerWindowText
      }

      TextMetrics {
        id: loopMeter
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        text: root.tickerLoopText
      }

      // The loop text twice over, scrolled by exactly one copy and
      // restarted, so the wrap is seamless.
      Text {
        id: scroller
        text: root.tickerLoopText + root.tickerLoopText
        textFormat: Text.PlainText
        color: root.labelColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering

        NumberAnimation on x {
          running: tickerView.visible && loopMeter.advanceWidth > 0
          from: 0
          to: -loopMeter.advanceWidth
          duration: Math.max(1000, loopMeter.advanceWidth / root.tickerSpeed * 1000)
          loops: Animation.Infinite
        }
      }
    }
  }

  Column {
    id: verticalCol
    visible: root.vertical
    anchors.centerIn: button
    spacing: 0

    Repeater {
      model: root.vertical ? root.verticalLines : []

      Text {
        required property string modelData
        text: modelData
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        color: root.labelColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }
  }
}
