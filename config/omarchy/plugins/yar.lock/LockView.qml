import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  property string userName: Quickshell.env("USER") || "yar"
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  // Time & Date state
  property var currentTime: new Date()

  // Layout & CapsLock state
  property string activeLayout: "EN"
  property bool capsLockActive: false

  // Custom lock background detection
  readonly property string customLockBgPng: Quickshell.env("HOME") + "/.config/omarchy/lockscreen.png"
  readonly property string customLockBgJpg: Quickshell.env("HOME") + "/.config/omarchy/lockscreen.jpg"
  property bool customBgExists: false
  property string effectiveBgPath: root.backgroundPath

  readonly property string placeholderText: "Введите пароль"
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function formatRussianDate(d) {
    if (!d) d = new Date()
    var days = ["Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"]
    var months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    return days[d.getDay()] + ", " + d.getDate() + " " + months[d.getMonth()]
  }

  function displayName(name) {
    if (!name || name === "yar") return "Ярослав"
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    checkCustomBgProc.running = true
    layoutCheckProc.running = true
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  onFailureMessageChanged: {
    if (failureMessage.length > 0) {
      shakeAnim.restart()
    }
  }

  onBackgroundPathChanged: {
    if (!checkCustomBgProc.running) checkCustomBgProc.running = true
  }

  // Timer for clock updates
  Timer {
    id: clockTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.currentTime = new Date()
  }

  // Custom background check process
  Process {
    id: checkCustomBgProc
    command: ["bash", "-c", "if [[ -f $HOME/.config/omarchy/lockscreen.png ]]; then echo \"$HOME/.config/omarchy/lockscreen.png\"; elif [[ -f $HOME/.config/omarchy/lockscreen.jpg ]]; then echo \"$HOME/.config/omarchy/lockscreen.jpg\"; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p.length > 0) {
          root.customBgExists = true
          root.effectiveBgPath = p
        } else {
          root.customBgExists = false
          root.effectiveBgPath = root.backgroundPath
        }
      }
    }
  }

  function checkLayout() {
    if (!layoutCheckProc.running) layoutCheckProc.running = true
  }

  function toggleLayout() {
    root.activeLayout = (root.activeLayout === "RU" ? "EN" : "RU")
    if (!layoutToggleProc.running) layoutToggleProc.running = true
  }

  function resetLayout() {
    root.activeLayout = "EN"
    if (!layoutResetProc.running) layoutResetProc.running = true
  }

  // Layout & CapsLock check process
  Process {
    id: layoutCheckProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/scripts/lock-layout.sh", "check"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        var parts = raw.split("|")
        var map = parts[0] || ""
        if (map.toLowerCase().indexOf("rus") >= 0) {
          root.activeLayout = "RU"
        } else {
          root.activeLayout = "EN"
        }
        root.capsLockActive = (parts[1] === "true")
      }
    }
  }

  // Toggle layout process
  Process {
    id: layoutToggleProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/scripts/lock-layout.sh", "toggle"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        var parts = raw.split("|")
        var map = parts[0] || ""
        if (map.toLowerCase().indexOf("rus") >= 0) {
          root.activeLayout = "RU"
        } else {
          root.activeLayout = "EN"
        }
        root.capsLockActive = (parts[1] === "true")
      }
    }
  }

  // Reset layout to English
  Process {
    id: layoutResetProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/scripts/lock-layout.sh", "reset"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        var parts = raw.split("|")
        var map = parts[0] || ""
        if (map.toLowerCase().indexOf("rus") >= 0) {
          root.activeLayout = "RU"
        } else {
          root.activeLayout = "EN"
        }
        root.capsLockActive = (parts[1] === "true")
      }
    }
  }

  Timer {
    id: layoutPollTimer
    interval: 1200
    repeat: true
    running: root.inputEnabled || root.loadBackground
    onTriggered: {
      if (!layoutCheckProc.running) layoutCheckProc.running = true
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var name = String(event.name)
      if (name.indexOf("activelayout") !== -1 || name.indexOf("keyboard") !== -1) {
        if (!layoutCheckProc.running) layoutCheckProc.running = true
      }
    }
  }

  // Power actions
  Process { id: suspendProc; command: ["systemctl", "suspend"] }
  Process { id: rebootProc; command: ["omarchy", "system", "reboot"] }
  Process { id: shutdownProc; command: ["omarchy", "system", "shutdown"] }

  // Background
  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.effectiveBgPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 0.5
      blurMax: 36
      blurMultiplier: 1.1
      contrast: 0.04
      brightness: -0.06
    }

    // Soft dark overlay
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0.02, 0.02, 0.05, 0.32)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // Top / Clock & Date Section
    Item {
      id: clockSection
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: authCard.top
      anchors.bottomMargin: 46
      width: clockCol.implicitWidth
      height: clockCol.implicitHeight

      Column {
        id: clockCol
        anchors.centerIn: parent
        spacing: 4

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Qt.formatTime(root.currentTime, "HH:mm")
          font.family: Style.font.family
          font.pixelSize: 96
          font.weight: Font.DemiBold
          color: Commons.Color.foreground
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.formatRussianDate(root.currentTime)
          font.family: Style.font.family
          font.pixelSize: 19
          font.weight: Font.Normal
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.85)
        }
      }
    }

    // Center Card Shake Animation
    SequentialAnimation {
      id: shakeAnim
      NumberAnimation { target: authCard; property: "anchors.horizontalCenterOffset"; to: -16; duration: 50; easing.type: Easing.OutQuad }
      NumberAnimation { target: authCard; property: "anchors.horizontalCenterOffset"; to: 16; duration: 50; easing.type: Easing.InOutQuad }
      NumberAnimation { target: authCard; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50; easing.type: Easing.InOutQuad }
      NumberAnimation { target: authCard; property: "anchors.horizontalCenterOffset"; to: 10; duration: 50; easing.type: Easing.InOutQuad }
      NumberAnimation { target: authCard; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50; easing.type: Easing.OutQuad }
    }

    // Central Auth Card
    Rectangle {
      id: authCard
      width: 420
      height: cardCol.implicitHeight + 54
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 60
      radius: 24
      color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.75)
      border.color: root.errorState
        ? Commons.Color.lock.borderError
        : (passwordInput.activeFocus ? Commons.Color.lock.borderActive : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.3))
      border.width: root.errorState || passwordInput.activeFocus ? 2 : 1.2
      clip: true

      Column {
        id: cardCol
        anchors.centerIn: parent
        spacing: 18
        width: parent.width - 48

        // User Avatar + Name Row
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 16

          Rectangle {
            id: avatarCircle
            width: 58
            height: 58
            radius: 29
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.15)
            border.color: Commons.Color.accent
            border.width: 1.5
            clip: true

            Image {
              id: faceImg
              anchors.fill: parent
              source: "file://" + Quickshell.env("HOME") + "/.face"
              fillMode: Image.PreserveAspectCrop
              visible: status === Image.Ready
            }

            Text {
              anchors.centerIn: parent
              visible: faceImg.status !== Image.Ready
              text: "󰀉"
              font.family: Style.font.family
              font.pixelSize: 30
              color: Commons.Color.accent
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
              text: root.displayName(root.userName)
              font.family: Style.font.family
              font.pixelSize: 19
              font.bold: true
              color: Commons.Color.foreground
            }

            Text {
              text: "Сеанс заблокирован"
              font.family: Style.font.family
              font.pixelSize: 12
              color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.65)
            }
          }
        }

        // Input Field Box
        Rectangle {
          id: inputFieldBox
          width: parent.width
          height: 50
          radius: 14
          color: Qt.rgba(0, 0, 0, 0.45)
          border.color: root.errorState
            ? Commons.Color.lock.borderError
            : (passwordInput.activeFocus ? Commons.Color.lock.borderActive : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.22))
          border.width: root.errorState || passwordInput.activeFocus ? 1.5 : 1

          Row {
            anchors.fill: parent
            anchors.leftMargin: 15
            anchors.rightMargin: 12
            spacing: 10

            // Left lock icon
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              font.family: Style.font.family
              font.pixelSize: 16
              color: passwordInput.activeFocus ? Commons.Color.accent : Commons.Color.lock.placeholder
            }

            // Center input
            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 25 - 16 - (layoutBadge.width + 12) - (root.fingerprintConfigured ? 24 : 0)
              height: parent.height

              TextInput {
                id: passwordInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignLeft
                activeFocusOnPress: true
                clip: true
                enabled: root.inputEnabled && !root.authenticatingPassword
                readOnly: root.authenticatingPassword
                echoMode: TextInput.Password
                passwordCharacter: "\u25CF"
                passwordMaskDelay: 0
                color: Commons.Color.lock.text
                selectionColor: Commons.Color.lock.selection
                selectedTextColor: Commons.Color.lock.text
                font.family: Style.font.family
                font.pixelSize: text.length > 0 ? 19 : 14
                font.letterSpacing: text.length > 0 ? 3 : 0
                cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0

                cursorDelegate: Rectangle {
                  width: 2
                  color: Commons.Color.accent
                  visible: passwordInput.cursorVisible
                }

                onTextChanged: {
                  if (!root.syncingPasswordText) root.passwordTextEdited(text)
                  if (text.length > 0) root.wakeRequested()
                  if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
                }

                onAccepted: {
                  var submitted = root.passwordText
                  root.passwordTextEdited("")
                  if (submitted.length > 0) root.submitPassword(submitted)
                }

                Keys.onPressed: function(event) {
                  root.wakeRequested()
                  if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                    root.passwordTextEdited("")
                    root.resetLayout()
                    event.accepted = true
                    return
                  }
                  // Toggle layout on keyboard shortcuts (Alt+Shift, Ctrl+Shift, Super+Space)
                  if ((event.key === Qt.Key_Shift && (event.modifiers & Qt.AltModifier)) ||
                      (event.key === Qt.Key_Alt && (event.modifiers & Qt.ShiftModifier)) ||
                      (event.key === Qt.Key_Shift && (event.modifiers & Qt.ControlModifier)) ||
                      (event.key === Qt.Key_Control && (event.modifiers & Qt.ShiftModifier)) ||
                      (event.key === Qt.Key_Space && (event.modifiers & Qt.MetaModifier)) ||
                      (event.key === Qt.Key_Space && (event.modifiers & Qt.ControlModifier))) {
                    root.toggleLayout()
                    event.accepted = true
                    return
                  }
                  root.checkLayout()
                }
              }

              // Placeholder
              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: root.authenticatingPassword ? "Проверка…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
                visible: passwordInput.text.length === 0
                color: root.authenticatingPassword ? Commons.Color.lock.text : (root.failureMessage.length > 0 ? Commons.Color.lock.textError : Commons.Color.lock.placeholder)
                font.family: Style.font.family
                font.pixelSize: 14
                font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
                elide: Text.ElideRight
              }
            }

            // Fingerprint indicator (if configured)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.fingerprintConfigured
              text: "󰈷"
              font.family: Style.font.family
              font.pixelSize: 17
              color: Commons.Color.accent
            }

            // Layout indicator badge (clickable to switch layout!)
            Rectangle {
              id: layoutBadge
              anchors.verticalCenter: parent.verticalCenter
              width: 36
              height: 24
              radius: 6
              color: layoutMouseArea.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35) : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.2)
              border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.6)
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: root.activeLayout
                font.family: Style.font.family
                font.pixelSize: 11
                font.bold: true
                color: Commons.Color.accent
              }

              MouseArea {
                id: layoutMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleLayout()
              }
            }
          }
        }

        // Caps Lock Warning Pill
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.capsLockActive
          width: capsRow.implicitWidth + 20
          height: 26
          radius: 13
          color: Qt.rgba(0.9, 0.6, 0.1, 0.2)
          border.color: Qt.rgba(0.9, 0.6, 0.1, 0.6)
          border.width: 1

          Row {
            id: capsRow
            anchors.centerIn: parent
            spacing: 6

            Text {
              text: "󰪛"
              font.family: Style.font.family
              font.pixelSize: 13
              color: "#ffb454"
            }

            Text {
              text: "CAPS LOCK ВКЛЮЧЕН"
              font.family: Style.font.family
              font.pixelSize: 11
              font.bold: true
              color: "#ffb454"
            }
          }
        }

        // Error message text if failure
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.errorState && !root.capsLockActive
          text: root.failureMessage.length > 0 ? root.failureMessage : "Неверный пароль"
          font.family: Style.font.family
          font.pixelSize: 12
          color: Commons.Color.lock.textError
        }
      }
    }

    // Bottom Footer / Hints & Quick Power Actions
    Item {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 30
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: 40
      anchors.rightMargin: 40
      height: 32

      // OS info
      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Text {
          text: "󰣇 Omarchy"
          font.family: Style.font.family
          font.pixelSize: 13
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
        }
      }

      // Shortcut Hint
      Text {
        anchors.centerIn: parent
        text: "Enter — разблокировать   •   Esc — очистить"
        font.family: Style.font.family
        font.pixelSize: 12
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
      }

      // Power Buttons
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 18

        // Sleep
        Text {
          text: "󰤄 Сон"
          font.family: Style.font.family
          font.pixelSize: 13
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: parent.color = Commons.Color.accent
            onExited: parent.color = Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
            onClicked: suspendProc.running = true
          }
        }

        // Reboot
        Text {
          text: "󰜉 Перезагрузка"
          font.family: Style.font.family
          font.pixelSize: 13
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: parent.color = Commons.Color.accent
            onExited: parent.color = Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
            onClicked: rebootProc.running = true
          }
        }

        // Shutdown
        Text {
          text: "󰐥 Выключение"
          font.family: Style.font.family
          font.pixelSize: 13
          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onEntered: parent.color = Commons.Color.urgent
            onExited: parent.color = Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.6)
            onClicked: shutdownProc.running = true
          }
        }
      }
    }
  }
}
