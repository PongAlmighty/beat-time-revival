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
//
// The zone list is edited in place, following the shell's own gestures:
// drag a row header to reorder (the bar's widget-drag, same threshold),
// click a header to rename, the right-edge action button removes, and
// "+ Add zone" opens a searchable tzdata picker. Keyboard: j/k move the
// cursor, Enter renames, x removes, a adds, Shift+J/K move the row.
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
    cancelEdits()
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
  readonly property var compactParts: ready ? Model.compactParts(zones, nowUtc, glyphs) : []
  readonly property string compactLabel: compactParts.join(Model.SEPARATOR)
  readonly property int zoneCount: zones.length

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
  readonly property real actionGap: Style.space(8)
  readonly property real actionW: Style.space(22)
  readonly property real rowsW: stripX + stripW + actionGap + actionW
  readonly property real rowPitch: cellH + rowGap
  readonly property real zonesY: rulerH + rowGap
  readonly property real gridH: zonesY + zones.length * cellH + Math.max(0, zones.length - 1) * rowGap
  readonly property real dragThreshold: Style.space(4)
  // Height the picker's list needs below the add row (its own max).
  readonly property real pickerReserve: Style.spacing.popupRowHeight * 6 + 5 * Style.spacing.labelGap + Style.space(50) + Style.spacing.xxs

  // ---- Zone editing state.
  // cursorRow is the row the mouse is over or the keyboard cursor sits on:
  // the target of x / Enter / Shift+J / Shift+K, and where the remove
  // button shows. actionHot mirrors mouse hover over the remove button so
  // it can render its hover state even though the hover area sits on top.
  property int cursorRow: -1
  property bool actionHot: false
  property int editRow: -1
  property bool addOpen: false
  property string pendingZone: ""
  property var tzNames: []
  property int dragFrom: -1
  property int dragTo: -1
  property real dragOffset: 0
  readonly property bool dragging: dragFrom >= 0
  readonly property bool editing: addOpen || editRow >= 0

  function cancelEdits() {
    addOpen = false
    editRow = -1
    pendingZone = ""
    endDrag()
  }

  // Applied locally first so the grid redraws on the gesture itself; the
  // shell.json write comes back through the bar as the same value. The host
  // widget's copy is kept in step so the bar's hover label follows too.
  function persistZones(list) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.zones = list
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function validZoneName(zone) {
    return zone !== "" && /^[A-Za-z0-9_\/+-]+$/.test(zone)
  }

  // Adds a zone row; an already-listed zone just moves the cursor to it.
  // Without a short label the row waits for tzdata's abbreviation ("JST")
  // so the bar shows the real one rather than a guess from the city name.
  function addZone(zone, label, shortLabel) {
    zone = String(zone || "").trim()
    if (!validZoneName(zone)) return false
    if (Model.zoneIndex(zoneConfig, zone) >= 0) {
      cursorRow = Model.zoneIndex(zoneConfig, zone)
      return false
    }
    var short = String(shortLabel || "").trim()
    if (short === "") {
      addProc.zone = zone
      addProc.label = String(label || "").trim()
      addProc.command = ["bash", "-c", "TZ='" + zone + "' date +%Z"]
      addProc.running = true
      return true
    }
    appendZone(zone, String(label || "").trim() || Model.cityLabel(zone), short)
    return true
  }

  function appendZone(zone, label, shortLabel) {
    if (Model.zoneIndex(zoneConfig, zone) >= 0) return
    var list = zoneConfig.slice()
    list.push({ label: label, shortLabel: shortLabel, zone: zone })
    persistZones(list)
    cursorRow = list.length - 1
    refresh()
  }

  function removeZoneAt(index) {
    if (index < 0 || index >= zoneConfig.length || zoneConfig[index].home) return
    var list = zoneConfig.slice()
    list.splice(index, 1)
    persistZones(list)
    if (cursorRow >= list.length) cursorRow = list.length - 1
  }

  function removeZoneByName(zone) {
    removeZoneAt(Model.zoneIndex(zoneConfig, String(zone || "").trim()))
  }

  function moveZone(from, to) {
    if (from < 0 || from >= zoneConfig.length) return
    var target = Math.max(0, Math.min(zoneConfig.length - 1, to))
    if (target === from) return
    persistZones(Model.moveItem(zoneConfig, from, target))
    cursorRow = target
  }

  function renameZoneAt(index, label, shortLabel) {
    if (index < 0 || index >= zoneConfig.length) return
    var list = zoneConfig.slice()
    var next = {}
    for (var key in list[index]) next[key] = list[index][key]
    var cleanLabel = String(label || "").trim()
    var cleanShort = String(shortLabel || "").trim()
    if (cleanLabel !== "") next.label = cleanLabel
    if (cleanShort !== "") next.shortLabel = cleanShort
    list[index] = next
    persistZones(list)
  }

  function moveCursor(dy) {
    if (zones.length === 0) return
    if (cursorRow < 0) cursorRow = dy > 0 ? 0 : zones.length - 1
    else cursorRow = Math.max(0, Math.min(zones.length - 1, cursorRow + dy))
  }

  function startRename(index) {
    if (index < 0 || index >= zones.length) return
    addOpen = false
    cursorRow = index
    editRow = index
  }

  function finishRename() {
    editRow = -1
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // IPC "add": show the panel with the picker ready to type into.
  function openAddFromHotkey() {
    if (!root.opened) root.openFromHotkey()
    Qt.callLater(root.openAdd)
  }

  function openAdd() {
    if (addOpen) return
    editRow = -1
    addOpen = true
    pendingZone = ""
    labelField.text = ""
    shortField.text = ""
    if (tzNames.length === 0) tzProc.running = true
    Qt.callLater(function() { if (root.addOpen) picker.open() })
  }

  function cancelAdd() {
    addOpen = false
    pendingZone = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function commitAdd() {
    if (pendingZone === "") {
      cancelAdd()
      return
    }
    if (addZone(pendingZone, labelField.text, shortField.text)) cancelAdd()
  }

  // Picking a zone prefills the label from the city and the short label
  // from tzdata's abbreviation ("JST"), which needs a probe; the city
  // stands in until it answers, and a short label the user already typed
  // over is left alone.
  function pickZone(zone) {
    if (!validZoneName(zone)) return
    pendingZone = zone
    labelField.text = Model.cityLabel(zone)
    shortField.text = Model.shortLabelFor(zone, "")
    abbrProc.zone = zone
    abbrProc.command = ["bash", "-c", "TZ='" + zone + "' date +%Z"]
    abbrProc.running = true
    Qt.callLater(function() { labelField.selectAll(); labelField.forceActiveFocus() })
  }

  function endDrag() {
    dragFrom = -1
    dragTo = -1
    dragOffset = 0
  }

  // Insertion slot `to` (0..n, "before row to") → final index for moveZone.
  function dropAt(from, to) {
    if (to === from || to === from + 1) return
    moveZone(from, to > from ? to - 1 : to)
  }

  function refresh() {
    var script = "echo \"TZNAME $(timedatectl show -p Timezone --value 2>/dev/null)\"; echo \"HOME $(date +'%z %Z')\""
    for (var i = 0; i < zoneConfig.length; i++) {
      var zone = String(zoneConfig[i].zone || "")
      if (!validZoneName(zone)) continue
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

  // The picker's options: every zone tzdata knows, fetched the first time
  // the add row opens.
  Process {
    id: tzProc
    command: ["timedatectl", "list-timezones"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.tzNames = Model.parseTimezoneList(text)
    }
  }

  Process {
    id: addProc
    property string zone: ""
    property string label: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.appendZone(addProc.zone, addProc.label || Model.cityLabel(addProc.zone),
                                        Model.shortLabelFor(addProc.zone, String(text || "").trim()))
    }
  }

  Process {
    id: abbrProc
    property string zone: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.addOpen || abbrProc.zone !== root.pendingZone) return
        if (shortField.text === Model.shortLabelFor(abbrProc.zone, ""))
          shortField.text = Model.shortLabelFor(abbrProc.zone, String(text || "").trim())
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
    contentWidth: panel.fittedContentWidth(root.rowsW + panel.verticalContentInset)
    // The picker's list drops below the add row and would be clipped by the
    // panel window, so the card grows to hold it while the list is open.
    contentHeight: panel.fittedContentHeight(rowsCol.implicitHeight + (picker.popupOpen ? root.pickerReserve : 0))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Inline editors own the keys while they have focus (the shell's
      // wifi-passphrase pattern); the picker's own list handles its keys.
      blocked: root.editing
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: root.startRename(root.cursorRow)
      onDeleteRequested: root.removeZoneAt(root.cursorRow)
      onTextKey: function(t) {
        if (t === "a") root.openAdd()
        else if (t === "J") root.moveZone(root.cursorRow, root.cursorRow + 1)
        else if (t === "K") root.moveZone(root.cursorRow, root.cursorRow - 1)
      }

      Column {
        id: rowsCol
        width: parent.width
        spacing: root.rowGap

        // ---- Ruler row: the beat itself, plus @000…@950 column starts.
        Item {
          width: root.rowsW
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
            required property int index
            required property var modelData
            readonly property var zoneRow: modelData
            readonly property bool rowReady: zoneRow.offsetMin !== null
            readonly property string zoneDate: rowReady ? Model.dateLabel(root.focusUtc, zoneRow.offsetMin) : ""
            readonly property string homeDate: Model.dateLabel(root.focusUtc, root.homeRow.offsetMin)
            readonly property bool hasCursor: root.cursorRow === index
            readonly property bool isDragSource: root.dragFrom === index
            readonly property bool renaming: root.editRow === index
            width: root.rowsW
            height: root.cellH
            z: isDragSource ? 10 : 0
            opacity: isDragSource ? 0.85 : 1
            transform: Translate { y: zoneItem.isDragSource ? root.dragOffset : 0 }

            onRenamingChanged: {
              if (!renaming) return
              renameLabel.text = root.zoneConfig[index] ? String(root.zoneConfig[index].label || "") : zoneRow.label
              renameShort.text = zoneRow.shortLabel
              Qt.callLater(function() { renameLabel.selectAll(); renameLabel.forceActiveFocus() })
            }

            function commitRename() {
              root.renameZoneAt(index, renameLabel.text, renameShort.text)
              root.finishRename()
            }

            // ---- Row cursor: the shared hover-cursor fill behind the header
            //      column, where x / Enter / Shift+J / Shift+K apply.
            CursorSurface {
              width: root.headerW
              height: root.cellH
              hasCursor: zoneItem.hasCursor && !zoneItem.renaming
              foreground: root.fg
            }

            // ---- Row header: location name, (abbr), local time, offset.
            Column {
              visible: !zoneItem.renaming
              width: root.headerW - Style.spacing.md
              x: Style.spacing.md
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

            // ---- Rename in place: click-to-edit swaps the header for label
            //      and short-label fields. Enter commits, Escape cancels.
            Row {
              visible: zoneItem.renaming
              x: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm

              TextField {
                id: renameLabel
                width: root.headerW - Style.spacing.md - Style.spacing.sm - Style.space(48)
                verticalPadding: Style.spacing.sm
                placeholderText: "Label"
                foreground: root.fg
                font.family: root.fontFam
                onAccepted: zoneItem.commitRename()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { root.finishRename(); event.accepted = true }
                }
              }
              TextField {
                id: renameShort
                width: Style.space(48)
                verticalPadding: Style.spacing.sm
                placeholderText: "Short"
                foreground: root.fg
                font.family: root.fontFam
                onAccepted: zoneItem.commitRename()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { root.finishRename(); event.accepted = true }
                }
              }
            }

            // ---- Header gestures: drag to reorder (the bar's widget-drag —
            //      plain left button past a small threshold), click to rename.
            MouseArea {
              id: headerMouse
              width: root.headerW
              height: root.cellH
              visible: !zoneItem.renaming
              acceptedButtons: Qt.LeftButton
              cursorShape: pressed && dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

              property bool dragging: false
              property bool suppressClick: false
              property real pressX: 0
              property real pressY: 0

              onPressed: function(mouse) {
                dragging = false
                suppressClick = false
                pressX = mouse.x
                pressY = mouse.y
              }

              onPositionChanged: function(mouse) {
                if (!(mouse.buttons & Qt.LeftButton)) return
                var distance = Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY)
                if (!dragging && distance >= root.dragThreshold) {
                  dragging = true
                  root.cancelEdits()
                  root.dragFrom = zoneItem.index
                  root.cursorRow = zoneItem.index
                }
                if (!dragging) return
                root.dragOffset = mouse.y - pressY
                // Pointer position in the zone list's own coordinates; the
                // nearest row boundary is the insertion slot.
                var pointerY = zoneItem.index * root.rowPitch + mouse.y
                root.dragTo = Math.max(0, Math.min(root.zones.length, Math.round(pointerY / root.rowPitch)))
              }

              onReleased: function(mouse) {
                if (!dragging) return
                suppressClick = true
                dragging = false
                var from = root.dragFrom
                var to = root.dragTo
                root.endDrag()
                root.dropAt(from, to)
              }

              onCanceled: {
                dragging = false
                root.endDrag()
              }

              onClicked: function(mouse) {
                if (suppressClick) { suppressClick = false; return }
                root.startRename(zoneItem.index)
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

            // ---- Remove: the right-edge row action (Bluetooth's "Forget"),
            //      shown while the row has the cursor. Home tracks the system
            //      timezone and stays.
            PanelActionButton {
              x: root.stripX + root.stripW + root.actionGap
              anchors.verticalCenter: parent.verticalCenter
              visible: zoneItem.hasCursor && !zoneItem.zoneRow.home && !root.dragging && !zoneItem.renaming
              iconText: "󰅙"
              tooltipText: "Remove"
              foreground: root.fg
              hoverColor: root.fg
              fontFamily: root.fontFam
              hasCursor: zoneItem.hasCursor && root.actionHot
              onClicked: root.removeZoneAt(zoneItem.index)
            }
          }
        }

        // ---- Add zone: a muted line that swaps for the picker, label
        //      fields, and confirm/cancel actions (weather's click-to-edit
        //      plus the network panel's confirm button).
        Item {
          id: addRow
          width: root.rowsW
          height: root.addOpen ? Style.space(32) : Style.space(22)
          visible: root.ready

          Keys.onPressed: function(event) {
            if (root.addOpen && event.key === Qt.Key_Escape) { root.cancelAdd(); event.accepted = true }
          }

          Row {
            visible: !root.addOpen
            x: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Text {
              text: "󰐕"
              color: addMouse.containsMouse ? root.fg : Qt.darker(root.fg, 1.5)
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              text: "Add zone"
              color: addMouse.containsMouse ? root.fg : Qt.darker(root.fg, 1.5)
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
            }
          }

          MouseArea {
            id: addMouse
            width: root.headerW
            height: parent.height
            visible: !root.addOpen
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openAdd()
          }

          Row {
            visible: root.addOpen
            x: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.controlGap

            SearchableDropdown {
              id: picker
              width: Style.spacing.searchableDropdownWidth
              anchors.verticalCenter: parent.verticalCenter
              showLabel: false
              triggerLabel: root.pendingZone === "" ? "Search timezone" : root.pendingZone
              value: root.pendingZone
              options: root.tzNames
              placeholderText: "Search timezone"
              emptyText: root.tzNames.length === 0 ? "Reading tzdata…" : "No matches"
              foreground: root.fg
              fontFamily: root.fontFam
              onChanged: function(value) { root.pickZone(value) }
            }

            TextField {
              id: labelField
              width: Style.space(128)
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "Label"
              foreground: root.fg
              font.family: root.fontFam
              onAccepted: root.commitAdd()
            }

            TextField {
              id: shortField
              width: Style.space(64)
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "Short"
              foreground: root.fg
              font.family: root.fontFam
              onAccepted: root.commitAdd()
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰄬"
              tooltipText: "Add"
              enabled: root.pendingZone !== ""
              focusable: true
              foreground: root.fg
              hoverColor: root.fg
              fontFamily: root.fontFam
              onClicked: root.commitAdd()
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅙"
              tooltipText: "Cancel"
              focusable: true
              foreground: root.fg
              hoverColor: root.fg
              fontFamily: root.fontFam
              onClicked: root.cancelAdd()
            }
          }
        }
      }

      // ---- "Now" line across ruler and zone rows, at the exact beat.
      Rectangle {
        x: root.stripX + root.nowBeats / 1000 * root.stripW - 1
        y: 0
        width: 2
        height: root.gridH
        radius: 1
        color: Color.accent
        opacity: 0.9
      }

      // ---- Drop marker: the bar's insertion line, between rows.
      Rectangle {
        visible: root.dragging && root.dragTo >= 0 && root.dragTo !== root.dragFrom && root.dragTo !== root.dragFrom + 1
        x: 0
        y: root.zonesY + root.dragTo * root.rowPitch - root.rowGap / 2 - height / 2
        width: root.rowsW
        height: Style.spacing.xs
        radius: height / 2
        color: Color.accent
        z: 20
      }

      // ---- Hover: beat conversion over the strips, row cursor over the
      //      whole zone list. Hover-only (no buttons), so presses fall
      //      through to the header gestures and the remove button beneath.
      MouseArea {
        x: 0
        y: root.zonesY
        width: root.rowsW
        height: Math.max(0, root.gridH - root.zonesY)
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: function(mouse) {
          var sx = mouse.x - root.stripX
          root.hoverBeat = (sx >= 0 && sx < root.stripW)
            ? Math.max(0, Math.min(999, Math.floor(sx / root.stripW * 1000)))
            : -1
          root.actionHot = mouse.x >= root.stripX + root.stripW + root.actionGap
          if (root.dragging) return
          var row = Math.floor(mouse.y / root.rowPitch)
          var inRow = mouse.y - row * root.rowPitch < root.cellH
          root.cursorRow = inRow && row >= 0 && row < root.zones.length ? row : -1
        }
        onExited: {
          root.hoverBeat = -1
          root.actionHot = false
          if (!root.dragging && !root.editing) root.cursorRow = -1
        }
      }
    }
  }
}
