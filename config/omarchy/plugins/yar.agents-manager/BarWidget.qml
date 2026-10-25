import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "yar.agents-manager"

  property var agents: []
  property var history: []
  property int activeCount: agents.length
  property bool hasBusy: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function close() {
    popup.open = false
  }

  function refresh(full) {
    if (fetchProc.running) return
    var helper = "/home/yar/.config/omarchy/plugins/yar.agents-manager/agents-helper.py"
    var isFull = (full === true) || (popup && popup.open)
    fetchProc.command = isFull ? [helper] : [helper, "--lite"]
    fetchProc.running = true
  }

  function focusAgent(address) {
    if (!address) return
    popup.open = false
    var helper = "/home/yar/.config/omarchy/plugins/yar.agents-manager/agents-helper.py"
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run(helper + " focus " + address)
    } else {
      if (focusProc.running) focusProc.running = false
      focusProc.command = [helper, "focus", address]
      focusProc.running = true
    }
  }

  function killAgent(pid, windowPid, address) {
    if (!pid) return
    var helper = "/home/yar/.config/omarchy/plugins/yar.agents-manager/agents-helper.py"
    var wpidStr = windowPid ? String(windowPid) : ""
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run(helper + " kill " + String(pid) + " " + wpidStr)
    } else {
      if (killProc.running) killProc.running = false
      killProc.command = [helper, "kill", String(pid), wpidStr]
      killProc.running = true
    }

    // Optimistically update list
    var remaining = []
    for (var i = 0; i < root.agents.length; i++) {
      if (root.agents[i].pid !== pid) remaining.push(root.agents[i])
    }
    root.agents = remaining
    delayTimer.restart()
  }

  function resumeSession(cid) {
    if (!cid) return
    popup.open = false
    var helper = "/home/yar/.config/omarchy/plugins/yar.agents-manager/agents-helper.py"
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run(helper + " resume " + cid)
    } else {
      if (resumeProc.running) resumeProc.running = false
      resumeProc.command = [helper, "resume", cid]
      resumeProc.running = true
    }
  }

  Timer {
    id: delayTimer
    interval: 800
    repeat: false
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "yar.agents-manager"
    function toggle(): void { popup.open = !popup.open }
    function open(): void { popup.open = true }
    function close(): void { popup.open = false }
    function refresh(): void { root.refresh() }
  }

  Timer {
    interval: popup.open ? 1800 : 5000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProc
    command: ["/home/yar/.config/omarchy/plugins/yar.agents-manager/agents-helper.py", "--lite"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          var list = res.active || []
          root.agents = list
          if (res.history && res.history.length > 0) {
            root.history = res.history
          }
          var busy = false
          for (var i = 0; i < list.length; i++) {
            if (list[i].status === "busy") busy = true
          }
          root.hasBusy = busy
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: focusProc
    command: []
  }

  Process {
    id: killProc
    command: []
  }

  Process {
    id: resumeProc
    command: []
  }

  // Semi-transparent pill button
  Rectangle {
    id: button
    implicitWidth: contentRow.implicitWidth + 14
    implicitHeight: Math.max(26, Style.bar.iconSlot)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
    color: "transparent"
    border.width: 0
    border.color: "transparent"

    Behavior on color {
      ColorAnimation { duration: 150 }
    }
    Behavior on border.color {
      ColorAnimation { duration: 150 }
    }

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: 5

      // Agent / Bot icon
      Text {
        text: "󰚩"
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        color: root.hasBusy 
          ? "#50fa7b" 
          : (root.activeCount > 0 ? Commons.Color.foreground : Commons.Color.muted)
        renderType: Text.NativeRendering
      }

      // Count badge
      Text {
        text: String(root.activeCount)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        color: root.activeCount > 0 ? Commons.Color.foreground : Commons.Color.muted
        renderType: Text.NativeRendering
      }

      // Activity indicator dot
      Rectangle {
        width: 6
        height: 6
        radius: 3
        visible: root.activeCount > 0
        color: root.hasBusy ? "#50fa7b" : "#8be9fd"

        SequentialAnimation on opacity {
          running: root.hasBusy
          loops: Animation.Infinite
          PropertyAnimation { to: 0.3; duration: 600 }
          PropertyAnimation { to: 1.0; duration: 600 }
        }
      }
    }

    HoverHandler {
      id: buttonHover
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        popup.open = !popup.open
        if (popup.open) root.refresh(true)
      }
    }
  }

  // Popup panel with dual-pane layout: Active Agents on Left, History on Right
  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    triggerMode: "click"
    open: false
    contentWidth: Style.space(820)
    contentHeight: Style.space(560)

    RowLayout {
      id: mainRowLayout
      anchors.fill: parent
      anchors.margins: Style.space(12)
      spacing: Style.space(12)

      // ================= LEFT PANE: ACTIVE AGENTS =================
      ColumnLayout {
        id: leftPane
        Layout.preferredWidth: Style.space(420)
        Layout.fillHeight: true
        spacing: 8

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          Text {
            text: "Запущенные агенты"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            color: Commons.Color.foreground
            renderType: Text.NativeRendering
          }

          Item { Layout.fillWidth: true }

          Rectangle {
            implicitWidth: badgeText.implicitWidth + 8
            implicitHeight: 18
            radius: 4
            color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)

            Text {
              id: badgeText
              anchors.centerIn: parent
              text: root.activeCount + " активн."
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption * 0.9
              color: Commons.Color.foreground
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.1)
        }

        // Scrollable list of active agents
        Flickable {
          id: activeAgentsFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: activeAgentsColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          ColumnLayout {
            id: activeAgentsColumn
            width: activeAgentsFlick.width
            spacing: 8

            // Active Agent Cards
            Repeater {
              model: root.agents

              Rectangle {
                id: agentCard
                Layout.fillWidth: true
                implicitHeight: agentCardLayout.implicitHeight + 20
                radius: 7
                color: cardClickArea.containsMouse 
                  ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.14)
                  : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.05)
                border.width: 1
                border.color: cardClickArea.containsMouse 
                  ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)
                  : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                // Card click handler (z: 0) - clicks anywhere except close button focus agent
                MouseArea {
                  id: cardClickArea
                  anchors.fill: parent
                  z: 0
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.focusAgent(modelData.address)
                }

                ColumnLayout {
                  id: agentCardLayout
                  anchors.fill: parent
                  anchors.margins: 10
                  spacing: 7
                  z: 1

                  // Top row: Name, PID, status badge, workspace badge, close button
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                      text: "󱚣 " + (modelData.name || "Agent")
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      color: Commons.Color.foreground
                    }

                    Text {
                      text: "PID " + modelData.pid
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.85
                      color: Commons.Color.muted
                    }

                    Item { Layout.fillWidth: true }

                    // Status badge
                    Rectangle {
                      implicitWidth: statusLabel.implicitWidth + 10
                      implicitHeight: 18
                      radius: 4
                      color: modelData.status === "busy" ? "#1e3a24" : "#22313f"
                      border.width: 1
                      border.color: modelData.status === "busy" ? "#50fa7b" : "#8be9fd"

                      Text {
                        id: statusLabel
                        anchors.centerIn: parent
                        text: modelData.status_text || "Ожидает"
                        font.pixelSize: Style.font.caption * 0.85
                        color: modelData.status === "busy" ? "#50fa7b" : "#8be9fd"
                      }
                    }

                    // Workspace badge
                    Rectangle {
                      implicitWidth: wsLabel.implicitWidth + 10
                      implicitHeight: 18
                      radius: 4
                      color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)

                      Text {
                        id: wsLabel
                        anchors.centerIn: parent
                        text: "WS " + (modelData.workspace || "?")
                        font.pixelSize: Style.font.caption * 0.85
                        color: Commons.Color.foreground
                      }
                    }

                    // Close button (z: 10, independent click handling)
                    Rectangle {
                      id: closeBtn
                      z: 10
                      implicitWidth: 22
                      implicitHeight: 22
                      radius: 4
                      color: closeBtnArea.containsMouse ? "#e05555" : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)

                      Behavior on color { ColorAnimation { duration: 120 } }

                      Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: closeBtnArea.containsMouse ? "#ffffff" : Commons.Color.muted
                      }

                      MouseArea {
                        id: closeBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true
                        onClicked: function(mouse) {
                          mouse.accepted = true
                          root.killAgent(modelData.pid, modelData.window_pid, modelData.address)
                        }
                      }
                    }
                  }

                  // Middle: Task text in padded inset box
                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: taskText.implicitHeight + 12
                    radius: 5
                    color: Qt.rgba(0, 0, 0, 0.25)
                    border.width: 1
                    border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08)

                    Text {
                      id: taskText
                      anchors.fill: parent
                      anchors.margins: 7
                      text: modelData.task || "Без активной задачи"
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      color: Commons.Color.foreground
                      wrapMode: Text.Wrap
                      maximumLineCount: 4
                      elide: Text.ElideRight
                      lineHeight: 1.15
                    }
                  }

                  // Bottom metadata row
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                      text: "📁 " + (modelData.cwd || "~")
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.85
                      color: Commons.Color.muted
                      elide: Text.ElideMiddle
                      Layout.maximumWidth: Style.space(200)
                    }

                    Text {
                      visible: modelData.cid_short !== ""
                      text: "🆔 " + modelData.cid_short
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.85
                      color: Commons.Color.muted
                    }

                    Text {
                      visible: modelData.active_task !== undefined && modelData.active_task !== ""
                      text: modelData.active_task || ""
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.85
                      font.bold: true
                      color: "#50fa7b"
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      text: "Клик: открыть окно"
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.8
                      color: cardClickArea.containsMouse ? Commons.Color.foreground : Commons.Color.muted
                      opacity: cardClickArea.containsMouse ? 0.9 : 0.5
                    }
                  }
                }
              }
            }

            // Empty state for active agents
            Text {
              Layout.fillWidth: true
              visible: root.activeCount === 0
              text: "Нет запущенных агентов"
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              color: Commons.Color.muted
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }

      // ================= VERTICAL DIVIDER =================
      Rectangle {
        Layout.fillHeight: true
        width: 1
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)
      }

      // ================= RIGHT PANE: SESSION HISTORY =================
      ColumnLayout {
        id: rightPane
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: 6

          Text {
            text: "История сессий"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            color: Commons.Color.foreground
            renderType: Text.NativeRendering
          }

          Item { Layout.fillWidth: true }

          Text {
            text: root.history.length + " сессий"
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            color: Commons.Color.muted
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.1)
        }

        // Scrollable list of history items
        Flickable {
          id: historyFlick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: historyColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          ColumnLayout {
            id: historyColumn
            width: historyFlick.width
            spacing: 6

            // History items
            Repeater {
              model: root.history

              Rectangle {
                Layout.fillWidth: true
                implicitHeight: historyItemLayout.implicitHeight + 14
                radius: 6
                color: histClickArea.containsMouse 
                  ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)
                  : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.04)
                border.width: 1
                border.color: histClickArea.containsMouse 
                  ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.3)
                  : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08)

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                MouseArea {
                  id: histClickArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.resumeSession(modelData.cid)
                }

                ColumnLayout {
                  id: historyItemLayout
                  anchors.fill: parent
                  anchors.margins: 7
                  spacing: 4

                  // Top row: Date, Short ID
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                      text: "📅 " + (modelData.date || "")
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.85
                      font.bold: true
                      color: Commons.Color.foreground
                    }

                    Text {
                      text: "🆔 " + (modelData.cid_short || "")
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.85
                      color: Commons.Color.muted
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      visible: modelData.is_active === true
                      text: "● Открыта"
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption * 0.8
                      font.bold: true
                      color: "#50fa7b"
                    }
                  }

                  // Prompt preview (2 lines)
                  Text {
                    Layout.fillWidth: true
                    text: modelData.prompt || "Без названия"
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption * 0.9
                    color: histClickArea.containsMouse ? Commons.Color.foreground : Commons.Color.muted
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 1.15
                  }
                }
              }
            }

            // Empty history state
            Text {
              Layout.fillWidth: true
              visible: root.history.length === 0
              text: "Нет сохраненных сессий"
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              color: Commons.Color.muted
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }
}
