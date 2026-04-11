import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Variants {
	model: Quickshell.screens

	PanelWindow {
		id: panel

		required property var modelData
		screen: modelData

		readonly property real sp: Core.Theme.dpiScale

		// === Layout data from JSON ===

		property var layoutData: ({})
		property var currentTagSlots: {
			var tag = Services.Compositor.activeTag
			var entry = layoutData[tag]
			return entry && entry.slots ? entry.slots : []
		}
		property string currentCollection: {
			var tag = Services.Compositor.activeTag
			var entry = layoutData[tag]
			return entry && entry.collection ? entry.collection : ""
		}

		// === Visibility ===

		property bool tagActive: {
			var tag = Services.Compositor.activeTag
			return tag !== "" && layoutData[tag] !== undefined
		}
		property bool sliding: false
		property bool editMode: false
		property real _showOpacity: 0.0

		visible: (tagActive && !sliding) ||
			fadeInAnim.running || _showOpacity > 0

		color: "transparent"
		focusable: editMode

		WlrLayershell.layer: WlrLayer.Bottom
		WlrLayershell.namespace: "somewm-shell:collage"
		WlrLayershell.keyboardFocus: editMode
			? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
		WlrLayershell.exclusionMode: ExclusionMode.Ignore

		anchors {
			top: true; bottom: true; left: true; right: true
		}

		// Input mask: only slot areas in view mode, full screen in edit mode
		mask: Region { item: interactiveArea }

		// === Fade-in / hide logic ===

		onTagActiveChanged: {
			if (tagActive && !sliding) {
				_startFadeIn()
			} else {
				_showOpacity = 0.0
			}
		}

		Timer {
			id: fadeInDelay
			interval: 200
			onTriggered: fadeInAnim.start()
		}

		NumberAnimation {
			id: fadeInAnim
			target: panel
			property: "_showOpacity"
			from: 0.0; to: 1.0
			duration: Core.Anims.duration.normal
			easing.type: Core.Anims.ease.decel
		}

		function _startFadeIn() {
			fadeInAnim.stop()
			panel._showOpacity = 0.0
			fadeInDelay.restart()
		}

		function _instantHide() {
			fadeInDelay.stop()
			fadeInAnim.stop()
			panel._showOpacity = 0.0
		}

		// === Interactive area (mask source) ===

		Item {
			id: interactiveArea
			anchors.fill: parent

			// Full-screen mask for edit mode
			Rectangle {
				id: editMask
				anchors.fill: parent
				visible: panel.editMode
				color: "transparent"
			}

			// Per-slot masks for view mode scroll (positioned by Repeater below)
		}

		// === Main content ===

		Item {
			id: content
			anchors.fill: parent
			opacity: panel._showOpacity

			// Collage slots
			Repeater {
				id: slotRepeater
				model: panel.currentTagSlots

				CollageSlot {
					id: slotDelegate
					required property var modelData
					required property int index

					slotX: modelData.x || 0
					slotY: modelData.y || 0
					maxHeight: modelData.maxHeight || 400
					imageIndex: modelData.imageIndex || 0
					collectionName: panel.currentCollection
					editMode: panel.editMode

					// View mode: scroll area mask (matches slot position + size)
					Rectangle {
						id: slotMask
						parent: interactiveArea
						x: slotDelegate.x
						y: slotDelegate.y
						width: slotDelegate.width
						height: slotDelegate.height
						color: "transparent"
						visible: !panel.editMode
					}

					// === Interaction handlers ===

					onImageIndexChanged: (newIndex) => {
						_updateSlot(index, "imageIndex", newIndex)
					}
					onSlotMoved: (newX, newY) => {
						_updateSlot(index, "x", newX)
						_updateSlot(index, "y", newY)
					}
					onSlotResized: (newMaxHeight) => {
						_updateSlot(index, "maxHeight", newMaxHeight)
					}
					onMiddleClicked: (gx, gy) => {
						collectionPicker.open(gx, gy)
					}
					onRightClicked: {
						var path = Services.Portraits.getImage(
							panel.currentCollection, modelData.imageIndex || 0)
						if (path) {
							// Sanitize path: escape single quotes for shell
							var safePath = path.replace(/'/g, "'\\''")
							Services.Compositor.spawn("qimgv '" + safePath + "'")
						}
					}

					// Scroll handler (view + edit mode)
					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.MiddleButton | Qt.RightButton
						propagateComposedEvents: true

						onWheel: (wheel) => {
							var delta = wheel.angleDelta.y > 0 ? -1 : 1
							var newIdx = (parent.imageIndex + delta)
							var imgs = Services.Portraits.getImagesForCollection(
								panel.currentCollection)
							if (imgs.length > 0) {
								newIdx = ((newIdx % imgs.length) + imgs.length) % imgs.length
							}
							parent.imageIndex = newIdx
							saveBounce.restart()
							wheel.accepted = true
						}

						onClicked: (mouse) => {
							if (!panel.editMode) return
							if (mouse.button === Qt.MiddleButton) {
								var gp = mapToItem(content, mouse.x, mouse.y)
								parent.middleClicked(gp.x, gp.y)
							} else if (mouse.button === Qt.RightButton) {
								parent.rightClicked()
							}
						}
					}

					// Drag handler (edit mode only)
					DragHandler {
						enabled: panel.editMode
						target: parent
						onActiveChanged: {
							if (!active) {
								// Save new position
								var newX = Math.round(parent.x / panel.sp)
								var newY = Math.round(parent.y / panel.sp)
								parent.slotMoved(newX, newY)
								saveBounce.restart()
							}
						}
					}
				}
			}

			// Edit mode indicator text
			Text {
				visible: panel.editMode
				anchors.top: parent.top
				anchors.horizontalCenter: parent.horizontalCenter
				anchors.topMargin: Core.Theme.spacing.lg
				text: "EDIT MODE  —  drag to move  |  scroll to cycle  |  middle-click for collection  |  Escape to save"
				font.family: Core.Theme.fontUI
				font.pixelSize: Core.Theme.fontSize.sm
				color: Core.Theme.accent
				opacity: 0.8

				Rectangle {
					anchors.fill: parent
					anchors.margins: -Core.Theme.spacing.sm
					z: -1
					radius: Core.Theme.radius.sm
					color: Core.Theme.glass1
				}
			}
		}

		// === Collection picker popup ===

		CollectionPicker {
			id: collectionPicker
			anchors.fill: parent
			currentCollection: panel.currentCollection

			onCollectionSelected: (name) => {
				_setCollection(name)
				saveBounce.restart()
			}
		}

		// === Keyboard handling (edit mode) ===

		Keys.onEscapePressed: {
			if (collectionPicker.shown) {
				collectionPicker.close()
			} else if (editMode) {
				_exitEditMode()
			}
		}

		// === Layout JSON persistence ===

		FileView {
			id: layoutFile
			path: Quickshell.env("HOME") + "/.config/quickshell/somewm/collage-layouts.json"
			watchChanges: true
			onFileChanged: {
				// Ignore echoes from our own saves
				if (!panel._ignoreFileChange) panel._loadLayout()
			}
		}

		property bool _ignoreFileChange: false

		function _loadLayout() {
			var raw = layoutFile.text()
			if (!raw || !raw.trim()) {
				panel.layoutData = ({})
				return
			}
			try {
				panel.layoutData = JSON.parse(raw)
			} catch (e) {
				console.error("Collage layout parse error:", e)
				panel.layoutData = ({})
			}
		}

		// Debounced save
		Timer {
			id: saveBounce
			interval: 1000
			onTriggered: panel._saveLayout()
		}

		// Queued write process
		property var _saveQueue: []
		function _saveLayout() {
			var json = JSON.stringify(panel.layoutData, null, 2)
			_saveQueue.push(json)
			_drainSaveQueue()
		}
		function _drainSaveQueue() {
			if (saveProc.running || _saveQueue.length === 0) return
			var json = _saveQueue.shift()
			// Escape JSON for shell: encode as base64 to avoid any escaping issues
			var b64 = Qt.btoa(json)
			saveProc.command = ["bash", "-c",
				"mkdir -p ~/.config/quickshell/somewm && " +
				"echo '" + b64 + "' | base64 -d > " +
				"~/.config/quickshell/somewm/collage-layouts.json"]
			panel._ignoreFileChange = true
			saveProc.running = true
		}
		Process {
			id: saveProc
			onRunningChanged: {
				if (!running) {
					// Brief delay before re-enabling file watch to skip echo
					ignoreTimer.restart()
					panel._drainSaveQueue()
				}
			}
		}
		Timer {
			id: ignoreTimer
			interval: 500
			onTriggered: panel._ignoreFileChange = false
		}

		// === Slot data mutation helpers ===
		// Mutate in place — don't reassign layoutData (avoids Repeater rebuild).
		// The _dirty flag ensures save captures the latest state.
		property bool _dirty: false

		function _updateSlot(slotIndex, key, value) {
			var tag = Services.Compositor.activeTag
			if (!layoutData[tag] || !layoutData[tag].slots[slotIndex]) return
			layoutData[tag].slots[slotIndex][key] = value
			_dirty = true
		}

		function _setCollection(name) {
			var tag = Services.Compositor.activeTag
			if (!layoutData[tag]) return
			layoutData[tag].collection = name
			_dirty = true
		}

		// === Edit mode management ===

		function _enterEditMode() {
			panel.editMode = true
			// Block desktop scroll-to-switch-tags
			overlayGuardProc.command = ["somewm-client", "eval",
				"_somewm_shell_overlay = true"]
			overlayGuardProc.running = true
		}

		function _exitEditMode() {
			panel.editMode = false
			_saveLayout()
			// Unblock desktop scroll
			overlayGuardProc.command = ["somewm-client", "eval",
				"_somewm_shell_overlay = false"]
			overlayGuardProc.running = true
		}

		Process { id: overlayGuardProc }

		// === IPC handler ===

		IpcHandler {
			target: "somewm-shell:collage"

			function editToggle(): void {
				if (panel.editMode) {
					panel._exitEditMode()
				} else if (panel.tagActive) {
					panel._enterEditMode()
				}
			}

			function slideStart(newTag: string): void {
				// Force exit edit mode if active
				if (panel.editMode) panel._exitEditMode()
				panel._instantHide()
				panel.sliding = true
				// Pre-set active tag atomically (setTag IPC is idempotent)
				if (newTag && newTag !== "")
					Services.Compositor.activeTag = newTag
			}

			function slideEnd(): void {
				panel.sliding = false
				if (panel.tagActive) {
					panel._startFadeIn()
				}
			}
		}

		// === Startup: fetch initial active tag ===

		Process {
			id: initTagProc
			command: ["somewm-client", "eval",
				"local s = require('awful').screen.focused(); " +
				"return s and s.selected_tag and s.selected_tag.name or ''"]
			stdout: StdioCollector {
				onStreamFinished: {
					var tag = panel._ipcValue(text)
					if (tag && tag !== "") {
						Services.Compositor.activeTag = tag
					}
				}
			}
		}

		function _ipcValue(raw) {
			var s = raw.trim()
			var nl = s.indexOf("\n")
			return nl >= 0 ? s.substring(nl + 1) : s
		}

		Component.onCompleted: {
			_loadLayout()
			initTagProc.running = true
		}
	}
}
