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
  moduleName: "yar.sysinfo"

  property int cpuUtil: 0
  property int cpuTemp: 0
  property string cpuModel: "CPU"

  property int gpuUtil: 0
  property int gpuTemp: 0
  property real gpuMemUsed: 0
  property real gpuMemTotal: 0
  property string gpuName: "GPU"

  property real ramUsedGb: 0
  property real ramTotalGb: 0
  property int ramPercent: 0
  property int ramTemp: 0

  property bool isHovered: buttonHover.containsMouse

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function updateData(raw) {
    if (!raw || raw.length === 0) return
    try {
      var res = JSON.parse(raw)
      if (res.cpu) {
        root.cpuUtil = res.cpu.util || 0
        root.cpuTemp = res.cpu.temp || 0
        if (res.cpu.model) root.cpuModel = res.cpu.model
      }
      if (res.gpu) {
        root.gpuUtil = res.gpu.util || 0
        root.gpuTemp = res.gpu.temp || 0
        root.gpuMemUsed = res.gpu.mem_used_gb || 0
        root.gpuMemTotal = res.gpu.mem_total_gb || 0
        if (res.gpu.name) root.gpuName = res.gpu.name
      }
      if (res.ram) {
        root.ramUsedGb = res.ram.used_gb || 0
        root.ramTotalGb = res.ram.total_gb || 0
        root.ramPercent = res.ram.percent || 0
        root.ramTemp = res.ram.temp || 0
      }
    } catch (e) {}
  }

  function launchBtop() {
    if (root.bar && typeof root.bar.run === "function") {
      root.bar.run("omarchy-launch-or-focus-tui btop")
    }
  }

  function tempColor(temp) {
    if (temp >= 82) return "#ff5555"
    if (temp >= 72) return "#ffb86c"
    return Commons.Color.foreground
  }

  function thermometerColor(temp) {
    if (temp >= 82) return "#ff5555"
    if (temp >= 72) return "#ffb86c"
    return "#ff9e64"
  }

  function utilColor(util) {
    if (util >= 85) return "#ff5555"
    if (util >= 70) return "#ffb86c"
    return Commons.Color.foreground
  }

  FileView {
    id: sysinfoFile
    path: "/dev/shm/sysinfo.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.updateData(text())
    onFileChanged: reload()
  }

  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: sysinfoFile.reload()
  }

  Component.onCompleted: sysinfoFile.reload()

  Rectangle {
    id: button

    implicitWidth: contentRow.implicitWidth + 16
    implicitHeight: Math.max(26, Style.bar.iconSlot)
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6

    color: root.isHovered
      ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)
      : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.05)
    border.width: 1
    border.color: root.isHovered
      ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.35)
      : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.18)

    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }

    RowLayout {
      id: contentRow
      anchors.centerIn: parent
      spacing: 10

      // ================= 1. БЛОК: CPU И ОЗУ =================
      RowLayout {
        spacing: 6

        // CPU Icon
        Text {
          text: ""
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body + 1
          color: root.cpuUtil >= 85 ? "#ff5555" : "#8be9fd"
          renderType: Text.NativeRendering
        }

        // CPU Load
        Text {
          text: String(root.cpuUtil) + "%"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          color: root.utilColor(root.cpuUtil)
          renderType: Text.NativeRendering
        }

        // CPU Thermometer Icon
        Text {
          text: ""
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: root.thermometerColor(root.cpuTemp)
          renderType: Text.NativeRendering
        }

        // CPU Temp
        Text {
          text: String(root.cpuTemp) + "°"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: root.tempColor(root.cpuTemp)
          renderType: Text.NativeRendering
        }

        // Spacing between CPU and RAM inside the same block
        Item { Layout.preferredWidth: 4 }

        // RAM Icon
        Text {
          text: ""
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body + 1
          color: root.ramPercent >= 85 ? "#ff5555" : "#bd93f9"
          renderType: Text.NativeRendering
        }

        // RAM Used / Total (GB)
        Text {
          text: root.ramUsedGb.toFixed(1) + "/" + root.ramTotalGb.toFixed(1) + "G"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          color: root.utilColor(root.ramPercent)
          renderType: Text.NativeRendering
        }

        // RAM Thermometer Icon
        Text {
          visible: root.ramTemp > 0
          text: ""
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: root.thermometerColor(root.ramTemp)
          renderType: Text.NativeRendering
        }

        // RAM Temp
        Text {
          visible: root.ramTemp > 0
          text: String(root.ramTemp) + "°"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: root.tempColor(root.ramTemp)
          renderType: Text.NativeRendering
        }
      }

      // ================= РАЗДЕЛИТЕЛЬ МЕЖДУ ДВУМЯ ЧАСТЯМИ =================
      Rectangle {
        Layout.preferredWidth: 1
        Layout.preferredHeight: 14
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.22)
      }

      // ================= 2. БЛОК: ВИДЕОКАРТА (GPU И VRAM) =================
      RowLayout {
        spacing: 6

        // GPU Icon
        Text {
          text: "󰾲"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body + 1
          color: root.gpuUtil >= 85 ? "#ff5555" : "#50fa7b"
          renderType: Text.NativeRendering
        }

        // GPU Load
        Text {
          text: String(root.gpuUtil) + "%"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          color: root.utilColor(root.gpuUtil)
          renderType: Text.NativeRendering
        }

        // GPU Thermometer Icon
        Text {
          text: ""
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: root.thermometerColor(root.gpuTemp)
          renderType: Text.NativeRendering
        }

        // GPU Temp
        Text {
          text: String(root.gpuTemp) + "°"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: root.tempColor(root.gpuTemp)
          renderType: Text.NativeRendering
        }

        // Spacing before VRAM inside the GPU block
        Item { Layout.preferredWidth: 4 }

        // VRAM Icon
        Text {
          text: "󰘚"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body + 1
          color: (root.gpuMemTotal > 0 && (root.gpuMemUsed / root.gpuMemTotal) >= 0.85) ? "#ff5555" : "#50fa7b"
          renderType: Text.NativeRendering
        }

        // VRAM Used / Total (GB)
        Text {
          text: root.gpuMemUsed.toFixed(1) + "/" + (root.gpuMemTotal % 1 === 0 ? root.gpuMemTotal.toFixed(0) : root.gpuMemTotal.toFixed(1)) + "G"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          color: (root.gpuMemTotal > 0 && (root.gpuMemUsed / root.gpuMemTotal) >= 0.85) ? "#ff5555" : Commons.Color.foreground
          renderType: Text.NativeRendering
        }
      }
    }

    MouseArea {
      id: buttonHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.launchBtop()
    }
  }
}
