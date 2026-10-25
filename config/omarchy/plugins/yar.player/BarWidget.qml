import QtQuick
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "yar.player"

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: {
    var best = null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || (!p.trackTitle && !p.trackArtist)) continue
      if (!best || (p.isPlaying && !best.isPlaying)) best = p
    }
    return best
  }
  readonly property bool hasMedia: activePlayer !== null
  readonly property bool playing: activePlayer ? activePlayer.isPlaying === true : false
  readonly property string playIcon: playing ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string displayText: {
    if (root.artist !== "" && root.title !== "") return root.artist + " - " + root.title
    return root.title !== "" ? root.title : root.artist
  }
  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground

  // 190 + the island's 2 x 10 px padding = 210 logical px.
  visible: hasMedia
  implicitWidth: hasMedia ? 190 : 0
  implicitHeight: barSize

  function runAction(name) {
    var p = activePlayer
    if (!p) return
    if (name === "previous") {
      if (p.canGoPrevious) p.previous()
    } else if (name === "next") {
      if (p.canGoNext) p.next()
    } else if (name === "playPause") {
      if (p.isPlaying && p.canPause) p.pause()
      else if (!p.isPlaying && p.canPlay) p.play()
      else if (p.canTogglePlaying) p.togglePlaying()
    }
  }

  component PlayerButton: Item {
    id: button

    property string glyph: ""
    property string action: ""
    property bool active: true
    property int glyphSize: Style.font.body

    width: Style.space(22)
    height: Style.space(22)
    opacity: active ? 1 : 0.35

    Rectangle {
      anchors.fill: parent
      radius: 0
      color: hover.hovered && button.active ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : "transparent"
    }

    Text {
      anchors.centerIn: parent
      text: button.glyph
      color: root.foreground
      font.family: bar ? bar.fontFamily : Style.font.family
      font.pixelSize: button.glyphSize
      renderType: Text.NativeRendering
    }

    HoverHandler { id: hover }

    MouseArea {
      anchors.fill: parent
      cursorShape: button.active ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (button.active) root.runAction(button.action)
    }
  }

  Row {
    id: controls
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    PlayerButton {
      glyph: "󰒮"
      action: "previous"
      active: root.activePlayer !== null && root.activePlayer.canGoPrevious === true
    }

    PlayerButton {
      glyph: root.playIcon
      action: "playPause"
      active: root.activePlayer !== null &&
        (root.activePlayer.canTogglePlaying === true ||
         root.activePlayer.canPlay === true ||
         root.activePlayer.canPause === true)
    }

    PlayerButton {
      glyph: "󰒭"
      action: "next"
      active: root.activePlayer !== null && root.activePlayer.canGoNext === true
    }
  }

  Item {
    id: titleClip
    anchors.left: controls.right
    anchors.leftMargin: Style.space(6)
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    clip: true

    Text {
      id: titleStatic
      anchors.centerIn: parent
      visible: !titleScroll.needsScroll
      text: root.displayText
      color: root.foreground
      font.family: bar ? bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      lineHeightMode: Text.FixedHeight
      lineHeight: Style.font.body
    }

    Text {
      id: titleScroll
      visible: needsScroll
      anchors.verticalCenter: parent.verticalCenter
      text: root.displayText
      color: root.foreground
      font.family: bar ? bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      lineHeightMode: Text.FixedHeight
      lineHeight: Style.font.body

      property bool needsScroll: implicitWidth > titleClip.width

      NumberAnimation on x {
        running: titleScroll.needsScroll
        loops: Animation.Infinite
        duration: Math.max(6000, titleScroll.implicitWidth * 25)
        from: titleClip.width
        to: -titleScroll.implicitWidth
        easing.type: Easing.Linear
      }
    }
  }
}
