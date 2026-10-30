import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    if (id <= 0) return null
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    return [1, 2, 3, -1, 4, 5, 6, 7, 8]
  }

  function focusWorkspace(id) {
    if (!root.bar || id <= 0) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: modelData === -1 ? (root.vertical ? "\u2014" : "|") : (focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData)))
        interactive: modelData > 0
        pressable: modelData > 0
        opacity: modelData === -1 ? 0.35 : (occupied || focused ? 1 : 0.5)
        horizontalMargin: modelData === -1 ? 2 : 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : (modelData === -1 ? Style.space(10) : Style.space(20))
        fixedHeight: root.vertical ? (modelData === -1 ? Style.space(10) : root.barSize) : root.barSize
        onPressed: function() { if (modelData > 0) root.focusWorkspace(modelData) }
      }
    }
  }
}
