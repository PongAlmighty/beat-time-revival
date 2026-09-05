import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Beat-grid popup: a 1000-beat ruler across the top, then one strip per
// zone showing what local hour each beat span is there, tinted by
// work/day/night so "is @330 the middle of the night for them?" reads at a
// glance. A "now" line marks the current beat; hovering any point converts
// that beat to local time in every row.
Panel {
  id: root
  moduleName: "io.github.pongalmighty.beattime"
  ipcTarget: "io.github.pongalmighty.beattime"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by must be that
  // widget (popout coordinator, switchPanelFrom).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    // Set after showing: showing hands the popout coordinator over, which
    // closes the previously open panel, and that close clears the flag.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Time state. Offsets come from tzdata via `date`, so DST is always
  //      right; the home row follows the system timezone (travel-proof).
  property double nowUtc: Date.now()
  property var offsets: ({})
  property string systemTz: ""

  readonly property var zoneConfig: setting("zones", Model.defaultZones())
  // System timezones that keep the configured home label. Outside this list
  // (or with none configured) the home row is labeled by where the system
  // clock actually is, so traveling relabels it automatically.
  readonly property var homeZoneNames: setting("homeZones", [])
  readonly property bool centibeats: setting("centibeats", false) === true
  readonly property bool glyphs: setting("glyphs", true) === true
  readonly property int beatsPerCell: Model.cellSize(setting("beatsPerCell", 50))
  readonly property int columns: 1000 / beatsPerCell
  readonly property color fg: bar ? bar.foreground : "#e0e0e0"
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family

  readonly property var zones: buildZones()

  function buildZones() {
    var out = []
    for (var i = 0; i < zoneConfig.length; i++) {
      var cfg = zoneConfig[i]
      var key = cfg.home ? "HOME" : cfg.zone
      var probed = offsets[key] || null
      var label = cfg.label
      // Away from the configured home zone, label the home row by where the
      // system actually is (e.g. "New York" while traveling).
      if (cfg.home && systemTz !== "" && homeZoneNames.indexOf(systemTz) === -1)
        label = systemTz.split("/").pop().replace(/_/g, " ")
      // Config strings are sanitized here — the single source every
      // consumer (panel texts, bar hover label) reads from.
      out.push({
        label: Model.plainText(label),
        shortLabel: Model.plainText(cfg.shortLabel || ""),
        abbr: Model.plainText(cfg.abbr || (probed ? probed.abbr : "")),
        home: cfg.home === true,
        offsetMin: probed ? probed.offsetMin : null
      })
    }
    return out
  }

  readonly property var homeRow: {
    for (var i = 0; i < zones.length; i++) if (zones[i].home) return zones[i]
    return null
  }
  readonly property bool ready: homeRow !== null && homeRow.offsetMin !== null

  // Beats need no zone: the label is live before the tzdata probe returns.
  readonly property string beatLabel: Model.beatLabel(nowUtc, centibeats)
  readonly property double dayStart: Model.bielDayStartUtc(nowUtc)
  readonly property double nowBeats: Model.beatsAt(nowUtc)
  // Biel's own calendar day — the day the ruler spans.
  readonly property string bielDate: Model.dateLabel(nowUtc, 60)

  // Hovered beat (whole), or -1. The moment every row converts when set.
  property int hoverBeat: -1
  readonly property double focusUtc: hoverBeat >= 0 ? Model.beatToUtc(dayStart, hoverBeat) : nowUtc

  // What the bar pill shows on hover.
  readonly property string compactLabel: ready ? Model.compactLabel(zones, nowUtc, glyphs) : ""

  // ---- Grid geometry.
  readonly property real stripW: Style.space(660)
  readonly property real cellGap: 1
  readonly property real cellW: (stripW - (columns - 1) * cellGap) / columns
  readonly property real cellH: Style.space(38)
  readonly property real rulerH: Style.space(22)
  readonly property real headerW: Style.space(168)
  readonly property real headerGap: Style.space(14)
  readonly property real rowGap: Style.space(6)
  readonly property real stripX: headerW + headerGap

  function refresh() {
    var script = "echo \"TZNAME $(timedatectl show -p Timezone --value 2>/dev/null)\"; echo \"HOME $(date +'%z %Z')\""
    for (var i = 0; i < zoneConfig.length; i++) {
      var zone = String(zoneConfig[i].zone || "")
      if (zone === "" || !/^[A-Za-z0-9_\/+-]+$/.test(zone)) continue
      script += "; echo \"" + zone + " $(TZ='" + zone + "' date +'%z %Z')\""
    }
    offsetsProc.command = ["bash", "-c", script]
    offsetsProc.running = true
  }

  Process {
    id: offsetsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "")
        if (raw.trim() === "") return
        var m = /(^|\n)TZNAME\s+(\S+)/.exec(raw)
        if (m) root.systemTz = m[2]
        var parsed = Model.parseOffsetLines(raw)
        if (parsed.HOME) root.offsets = parsed
      }
    }
  }

  // A beat lasts 86.4 s, so the label needs second precision to turn over on
  // time. Offsets can only change at wall-clock hour boundaries (DST
  // switches) or when the clock jumps (suspend/resume, timezone changed
  // while traveling), so re-probe exactly then rather than every tick.
  SystemClock {
    precision: SystemClock.Seconds
    onDateChanged: {
      var previous = root.nowUtc
      root.nowUtc = date.getTime()
      var jumped = Math.abs(root.nowUtc - previous) > 120000
      if ((date.getMinutes() === 0 && date.getSeconds() === 0) || jumped)
        root.refresh()
    }
  }

  Component.onCompleted: root.refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    // contentWidth is the card's outer width: unlike fittedContentHeight,
    // fittedContentWidth does not add the padding/border inset, so add it
    // here or the last column gets clipped.
    contentWidth: panel.fittedContentWidth(root.stripX + root.stripW + panel.verticalContentInset)
    contentHeight: panel.fittedContentHeight(rowsCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: rowsCol
        width: parent.width
        spacing: root.rowGap

        // ---- Ruler row: the beat itself, plus @000…@950 column starts.
        Item {
          width: rowsCol.width
          height: root.rulerH

          Row {
            width: root.headerW
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              text: root.hoverBeat >= 0 ? "@" + (root.hoverBeat < 10 ? "00" : root.hoverBeat < 100 ? "0" : "") + root.hoverBeat : root.beatLabel
              color: root.hoverBeat >= 0 ? Color.accent : root.fg
              font.family: root.fontFam
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              text: "BMT " + root.bielDate
              color: Qt.darker(root.fg, 1.5)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            x: root.stripX
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.cellGap

            Repeater {
              model: root.columns

              Item {
                required property int index
                width: root.cellW
                height: root.rulerH

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: Model.rulerLabel(parent.index, root.beatsPerCell)
                  color: Qt.darker(root.fg, 1.4)
                  font.family: root.fontFam
                  font.pixelSize: Style.font.caption - 1
                }
              }
            }
          }
        }

        Text {
          visible: !root.ready
          text: "Reading timezones…"
          color: Qt.darker(root.fg, 1.5)
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Repeater {
          model: root.ready ? root.zones : []

          Item {
            id: zoneItem
            required property var modelData
            readonly property var zoneRow: modelData
            readonly property bool rowReady: zoneRow.offsetMin !== null
            readonly property string zoneDate: rowReady ? Model.dateLabel(root.focusUtc, zoneRow.offsetMin) : ""
            readonly property string homeDate: Model.dateLabel(root.focusUtc, root.homeRow.offsetMin)
            width: rowsCol.width
            height: root.cellH

            // ---- Row header: location name, (abbr), local time, offset.
            Column {
              width: root.headerW
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Row {
                spacing: Style.space(6)

                Text {
                  text: zoneItem.zoneRow.label
                  textFormat: Text.PlainText
                  color: root.fg
                  font.family: root.fontFam
                  font.pixelSize: Style.font.body
                  font.bold: zoneItem.zoneRow.home
                }
                Text {
                  visible: zoneItem.zoneRow.abbr !== ""
                  text: "(" + zoneItem.zoneRow.abbr + ")"
                  textFormat: Text.PlainText
                  color: Qt.darker(root.fg, 1.5)
                  font.family: root.fontFam
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Row {
                spacing: Style.space(6)

                Text {
                  visible: root.glyphs && zoneItem.rowReady
                  text: zoneItem.rowReady ? Model.dayNightGlyph(root.focusUtc, zoneItem.zoneRow.offsetMin) : ""
                  color: root.hoverBeat >= 0 ? Color.accent : root.fg
                  font.family: root.fontFam
                  font.pixelSize: Style.font.body
                }
                Text {
                  text: zoneItem.rowReady ? Model.timeLabel(root.focusUtc, zoneItem.zoneRow.offsetMin) : "—"
                  color: root.hoverBeat >= 0 ? Color.accent : root.fg
                  font.family: root.fontFam
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  // Home shows its date; others their offset from home, plus
                  // the date whenever their calendar day differs from home's.
                  text: zoneItem.zoneRow.home
                    ? zoneItem.zoneDate
                    : (zoneItem.rowReady
                        ? Model.diffLabel(zoneItem.zoneRow.offsetMin, root.homeRow.offsetMin)
                          + (zoneItem.zoneDate !== zoneItem.homeDate ? "  " + zoneItem.zoneDate : "")
                        : "")
                  color: Qt.darker(root.fg, 1.5)
                  font.family: root.fontFam
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }

            // ---- Beat strip: one Biel day left to right, each cell the
            //      zone's local hour at that beat span.
            Row {
              x: root.stripX
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.cellGap

              Repeater {
                model: zoneItem.rowReady ? root.columns : 0

                Rectangle {
                  required property int index
                  readonly property var c: Model.cell(index, root.beatsPerCell, root.dayStart, zoneItem.zoneRow.offsetMin)
                  readonly property bool hot: root.hoverBeat >= 0 && Math.floor(root.hoverBeat / root.beatsPerCell) === index
                  width: root.cellW
                  height: root.cellH
                  radius: Style.space(3)
                  color: c.tint === "work" ? Qt.alpha(Color.accent, hot ? 0.50 : 0.28)
                       : c.tint === "day" ? Qt.alpha(root.fg, hot ? 0.24 : 0.10)
                       : Qt.alpha(root.fg, hot ? 0.16 : 0.035)

                  Text {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 0.85
                    text: c.isMidnight ? c.dayLabel.replace(" ", "\n") : String(c.hour)
                    color: c.isMidnight ? root.fg
                         : c.tint === "night" ? Qt.darker(root.fg, 1.6)
                         : root.fg
                    font.family: root.fontFam
                    font.pixelSize: c.isMidnight ? Style.font.caption - 2 : Style.font.caption
                    font.bold: c.isMidnight
                  }
                }
              }
            }
          }
        }
      }

      // ---- "Now" line across ruler and all rows, at the exact beat.
      Rectangle {
        x: root.stripX + root.nowBeats / 1000 * root.stripW - 1
        y: 0
        width: 2
        height: rowsCol.height
        radius: 1
        color: Color.accent
        opacity: 0.9
      }

      // ---- Hover conversion: every row's header switches to the local
      //      time at the hovered beat, answering "@330 is what for them?".
      MouseArea {
        x: root.stripX
        y: 0
        width: root.stripW
        height: rowsCol.height
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
          root.hoverBeat = Math.max(0, Math.min(999, Math.floor(mouse.x / root.stripW * 1000)))
        }
        onExited: root.hoverBeat = -1
      }
    }
  }
}
