import QtQuick
import QtQuick.Effects
import "../../core" as Core
import "../../services" as Services

Item {
	id: root

	// Layout properties (from JSON config, logical pixels)
	property real slotX: 0
	property real slotY: 0
	property real maxHeight: 400
	property int imageIndex: 0
	property string collectionName: ""
	property bool editMode: false

	// Signals to parent
	signal indexPersist(int newIndex)
	signal slotMoved(real newX, real newY)
	signal slotResized(real newMaxHeight)
	signal middleClicked(real globalX, real globalY)
	signal rightClicked()

	readonly property real sp: Core.Theme.dpiScale

	x: Math.round(slotX * sp)
	y: Math.round(slotY * sp)
	width: _imageWidth
	height: Math.round(maxHeight * sp)

	// Computed image dimensions (preserve aspect ratio)
	property real _imageWidth: {
		if (imgFront.sourceSize.width > 0 && imgFront.sourceSize.height > 0) {
			var ratio = imgFront.sourceSize.width / imgFront.sourceSize.height
			return Math.round(height * ratio)
		}
		// Default aspect ratio before image loads
		return Math.round(height * 0.667)
	}

	property string _currentPath: Services.Portraits.getImage(collectionName, imageIndex)

	// === Crossfade: two stacked images ===

	property bool _useFront: true

	onImageIndexChanged: {
		var newPath = Services.Portraits.getImage(collectionName, imageIndex)
		if (newPath === "") return

		if (_useFront) {
			imgBack.source = "file://" + newPath
		} else {
			imgFront.source = "file://" + newPath
		}
		_useFront = !_useFront
		_currentPath = newPath
	}

	// Shadow + rounded corners container
	Item {
		id: frameContainer
		anchors.fill: parent

		layer.enabled: true
		layer.effect: MultiEffect {
			shadowEnabled: true
			shadowColor: Qt.rgba(0, 0, 0, 0.55)
			shadowVerticalOffset: Math.round(6 * root.sp)
			shadowHorizontalOffset: Math.round(2 * root.sp)
			shadowBlur: 0.7
			maskEnabled: true
			maskThresholdMin: 0.5
			maskSource: ShaderEffectSource {
				sourceItem: Rectangle {
					width: frameContainer.width
					height: frameContainer.height
					radius: Core.Theme.radius.lg
				}
			}
		}

		// Back image (crossfade target)
		Image {
			id: imgBack
			anchors.fill: parent
			asynchronous: true
			fillMode: Image.PreserveAspectFit
			cache: true
			sourceSize.height: Math.round(root.maxHeight * root.sp * 2)
			opacity: root._useFront ? 0.0 : 1.0

			Behavior on opacity {
				NumberAnimation {
					duration: Core.Anims.duration.normal
					easing.type: Core.Anims.ease.standard
				}
			}
		}

		// Front image (initial / crossfade source)
		Image {
			id: imgFront
			anchors.fill: parent
			asynchronous: true
			fillMode: Image.PreserveAspectFit
			cache: true
			sourceSize.height: Math.round(root.maxHeight * root.sp * 2)
			source: root._currentPath ? "file://" + root._currentPath : ""
			opacity: root._useFront ? 1.0 : 0.0

			Behavior on opacity {
				NumberAnimation {
					duration: Core.Anims.duration.normal
					easing.type: Core.Anims.ease.standard
				}
			}
		}

		// Placeholder while loading
		Rectangle {
			anchors.fill: parent
			radius: Core.Theme.radius.lg
			color: Core.Theme.glass2
			visible: imgFront.status !== Image.Ready && imgBack.status !== Image.Ready
		}

		// Edit mode border
		Rectangle {
			anchors.fill: parent
			radius: Core.Theme.radius.lg
			color: "transparent"
			border.width: root.editMode ? Math.round(2 * root.sp) : 0
			border.color: Core.Theme.accent
			visible: root.editMode

			Behavior on border.width {
				NumberAnimation { duration: Core.Anims.duration.fast }
			}
		}
	}

	// === Edit mode: resize handle (bottom-right corner) ===
	Rectangle {
		id: resizeHandle
		visible: root.editMode
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.margins: Math.round(-4 * root.sp)
		width: Math.round(16 * root.sp)
		height: Math.round(16 * root.sp)
		radius: Math.round(8 * root.sp)
		color: Core.Theme.accent
		opacity: resizeMa.containsMouse ? 1.0 : 0.7

		MouseArea {
			id: resizeMa
			anchors.fill: parent
			hoverEnabled: true
			cursorShape: Qt.SizeFDiagCursor
			property real _startY: 0
			property real _startHeight: 0

			onPressed: (mouse) => {
				_startY = mouse.y + resizeHandle.y + root.y
				_startHeight = root.maxHeight
			}
			onPositionChanged: (mouse) => {
				if (!pressed) return
				var currentY = mouse.y + resizeHandle.y + root.y
				var delta = (currentY - _startY) / root.sp
				var newH = Math.max(100, _startHeight + delta)
				root.slotResized(Math.round(newH))
			}
		}
	}
}
