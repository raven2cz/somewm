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

		// Display tag: decoupled from Services.Compositor.activeTag
		// to avoid Repeater rebuilds during slide animation.
		// Updated only when it's safe (not sliding).
		property string _displayTag: ""

		property var currentTagSlots: {
			var entry = layoutData[_displayTag]
			return entry && entry.slots ? entry.slots : []
		}
		property string currentCollection: {
			var entry = layoutData[_displayTag]
			return entry && entry.collection ? entry.collection : ""
		}

		// === Visibility ===

		property bool tagActive: {
			return _displayTag !== "" && layoutData[_displayTag] !== undefined
		}
		property bool sliding: false
		property bool editMode: false
		property real _showOpacity: 0.0

		// Surface is fullscreen only when showing content.
		// When hidden, anchors are disabled to shrink the layer surface
		// and remove compositing overhead on NVIDIA.
		property bool _surfaceActive: (tagActive && !sliding) ||
			fadeInAnim.running || _showOpacity > 0

		visible: _surfaceActive
		color: "transparent"
		focusable: editMode

		WlrLayershell.layer: WlrLayer.Bottom
		WlrLayershell.namespace: "somewm-shell:collage"
		WlrLayershell.keyboardFocus: editMode
			? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
		WlrLayershell.exclusionMode: ExclusionMode.Ignore

		anchors {
			top: _surfaceActive; bottom: _surfaceActive
			left: _surfaceActive; right: _surfaceActive
		}

		// Input mask: slot areas in view, full screen in edit/picker mode
		mask: Region {
			item: (panel.editMode || collectionPicker.shown)
				? fullMask : interactiveArea
		}

		Item {
			id: fullMask
			anchors.fill: parent
		}

		// === Display tag management ===

		// Sync _displayTag from activeTag when not sliding
		Connections {
			target: Services.Compositor
			function onActiveTagChanged() {
				if (!panel.sliding)
					panel._displayTag = Services.Compositor.activeTag
			}
		}

		// === Fade-in / hide logic ===

		onTagActiveChanged: {
			if (tagActive && !sliding) {
				_startFadeIn()
			} else {
				_instantHide()
			}
		}

		Timer {
			id: fadeInDelay
			interval: 200
			onTriggered: fadeInAnim.start()
		}

		property real _showScale: 1.0

		ParallelAnimation {
			id: fadeInAnim
			NumberAnimation {
				target: panel
				property: "_showOpacity"
				from: 0.0; to: 1.0
				duration: Core.Anims.duration.normal
				easing.type: Core.Anims.ease.decel
			}
			NumberAnimation {
				target: panel
				property: "_showScale"
				from: 0.96; to: 1.0
				duration: Core.Anims.duration.normal
				easing.type: Core.Anims.ease.decel
			}
		}

		function _startFadeIn() {
			fadeInAnim.stop()
			panel._showOpacity = 0.0
			panel._showScale = 0.96
			fadeInDelay.restart()
		}

		function _instantHide() {
			fadeInDelay.stop()
			fadeInAnim.stop()
			panel._showOpacity = 0.0
			panel._showScale = 0.96
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
			scale: panel._showScale
			transformOrigin: Item.Center
			focus: panel.editMode

			Keys.onEscapePressed: {
				if (collectionPicker.shown) {
					collectionPicker.close()
				} else if (panel.editMode) {
					panel._exitEditMode()
				}
			}

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

					onIndexPersist: (newIndex) => {
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
							parent.indexPersist(newIdx)
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

		// === Layout JSON persistence ===

		FileView {
			id: layoutFile
			path: Quickshell.env("HOME") + "/.config/quickshell/somewm/collage-layouts.json"
			watchChanges: true
			onTextChanged: {
				// Fires on initial async load AND external file changes.
				// Ignore echoes from our own saves.
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
			var layoutPath = Quickshell.env("HOME") +
				"/.config/quickshell/somewm/collage-layouts.json"
			// Write via python3 with sys.argv — no shell escaping needed
			saveProc.command = ["python3", "-c",
				"import sys,os;d=os.path.dirname(sys.argv[1]);" +
				"os.makedirs(d,exist_ok=True);" +
				"open(sys.argv[1],'w').write(sys.argv[2])",
				layoutPath, json]
			panel._ignoreFileChange = true
			saveProc.running = true
		}
		Process {
			id: saveProc
			onRunningChanged: {
				if (!running) {
					if (saveProc.exitCode !== 0)
						console.error("Collage layout save failed, exit code:", saveProc.exitCode)
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
			var tag = panel._displayTag
			if (!layoutData[tag] || !layoutData[tag].slots[slotIndex]) return
			layoutData[tag].slots[slotIndex][key] = value
			_dirty = true
			// Force binding re-evaluation for properties that depend on layoutData
			layoutData = Object.assign({}, layoutData)
		}

		function _setCollection(name) {
			var tag = panel._displayTag
			if (!layoutData[tag]) return
			layoutData[tag].collection = name
			_dirty = true
			layoutData = Object.assign({}, layoutData)
		}

		// === Edit mode management ===

		property bool _desiredOverlay: false

		function _enterEditMode() {
			panel.editMode = true
			_pushOverlayGuard(true)
		}

		function _exitEditMode() {
			panel.editMode = false
			_saveLayout()
			_pushOverlayGuard(false)
		}

		function _pushOverlayGuard(val) {
			_desiredOverlay = val
			if (overlayGuardProc.running) return  // will drain in onRunningChanged
			overlayGuardProc.command = ["somewm-client", "eval",
				"_somewm_shell_overlay = " + (_desiredOverlay ? "true" : "false")]
			overlayGuardProc.running = true
		}

		Process {
			id: overlayGuardProc
			onRunningChanged: {
				if (!running) {
					// If desired state changed while running, push again
					var current = overlayGuardProc.command[2].indexOf("true") >= 0
					if (current !== panel._desiredOverlay)
						panel._pushOverlayGuard(panel._desiredOverlay)
				}
			}
		}

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
				// Force exit edit mode and close picker if active
				if (collectionPicker.shown) collectionPicker.close()
				if (panel.editMode) panel._exitEditMode()
				panel._instantHide()
				panel.sliding = true
				// Do NOT update _displayTag here — defer to slideEnd
				// to avoid Repeater rebuild during slide animation.
				// activeTag is set globally for other consumers.
				if (newTag && newTag !== "")
					Services.Compositor.activeTag = newTag
			}

			function slideEnd(): void {
				// Apply the pending tag now (after slide animation completes)
				panel._displayTag = Services.Compositor.activeTag
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
						panel._displayTag = tag
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
			initTagProc.running = true
		}
	}
}
