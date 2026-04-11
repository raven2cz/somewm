pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core" as Core

Singleton {
	id: root

	// Base directory for portrait collections
	readonly property string basePath: {
		var cfg = Core.Config._data
		var p = cfg && cfg.collage && cfg.collage.portraitBasePath
			? cfg.collage.portraitBasePath : ""
		return p || (Quickshell.env("HOME") +
			"/Pictures/wallpapers/public-wallpapers/portrait")
	}

	// Available collections: [{name, path, imageCount}]
	property var collections: []

	// Per-collection image cache: { "joy": ["/path/img1.jpg", ...], ... }
	property var _imageCache: ({})

	// Loading flag
	property bool loading: false

	// === Public API ===

	function getImagesForCollection(name) {
		if (_imageCache[name]) return _imageCache[name]
		// Not cached yet — trigger scan, return empty
		_scanCollection(name)
		return []
	}

	function getImage(collection, index) {
		var imgs = getImagesForCollection(collection)
		if (imgs.length === 0) return ""
		var idx = ((index % imgs.length) + imgs.length) % imgs.length
		return imgs[idx]
	}

	function randomImage(collection) {
		var imgs = getImagesForCollection(collection)
		if (imgs.length === 0) return ""
		return imgs[Math.floor(Math.random() * imgs.length)]
	}

	function imageCount(collection) {
		var imgs = _imageCache[collection]
		return imgs ? imgs.length : 0
	}

	function refresh() {
		_imageCache = ({})
		_scanCollections()
	}

	// === Collection directory scanning ===

	function _scanCollections() {
		root.loading = true
		collectionsProc.command = ["find", "-L", root.basePath,
			"-mindepth", "1", "-maxdepth", "1", "-type", "d"]
		collectionsProc.running = true
	}

	Process {
		id: collectionsProc
		stdout: StdioCollector {
			onStreamFinished: {
				var lines = text.trim().split("\n")
				var result = []
				lines.sort()
				lines.forEach(function(line) {
					if (!line) return
					var name = line.split("/").pop()
					result.push({ name: name, path: line, imageCount: 0 })
				})
				root.collections = result
				root.loading = false
				// Count images per collection
				if (result.length > 0) _countProc_start()
			}
		}
	}

	// Count images per collection via a single find call
	function _countProc_start() {
		countProc.command = ["bash", "-c",
			"for d in " + root.basePath + "/*/; do " +
			"n=$(find -L \"$d\" -maxdepth 1 -type f " +
			"\\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \\) " +
			"| wc -l); echo \"$(basename \"$d\") $n\"; done"]
		countProc.running = true
	}

	Process {
		id: countProc
		stdout: StdioCollector {
			onStreamFinished: {
				var lines = text.trim().split("\n")
				var counts = {}
				lines.forEach(function(line) {
					if (!line) return
					var parts = line.split(" ")
					var count = parseInt(parts[parts.length - 1]) || 0
					var name = parts.slice(0, parts.length - 1).join(" ")
					counts[name] = count
				})
				// Update collection imageCount
				var updated = root.collections.map(function(c) {
					return {
						name: c.name,
						path: c.path,
						imageCount: counts[c.name] || 0
					}
				})
				root.collections = updated
			}
		}
	}

	// === Per-collection image scanning ===

	property string _pendingScanCollection: ""

	function _scanCollection(name) {
		var colPath = root.basePath + "/" + name
		root._pendingScanCollection = name
		imageScanProc.command = ["find", "-L", colPath,
			"-maxdepth", "1", "-type", "f",
			"(", "-name", "*.jpg", "-o", "-name", "*.jpeg",
			"-o", "-name", "*.png", "-o", "-name", "*.webp", ")"]
		imageScanProc.running = true
	}

	Process {
		id: imageScanProc
		stdout: StdioCollector {
			onStreamFinished: {
				var lines = text.trim().split("\n")
				var result = []
				lines.sort()
				lines.forEach(function(line) {
					if (line) result.push(line)
				})
				var cache = Object.assign({}, root._imageCache)
				cache[root._pendingScanCollection] = result
				root._imageCache = cache
			}
		}
	}

	// === IPC ===

	IpcHandler {
		target: "somewm-shell:portraits"
		function refresh(): void { root.refresh() }
	}

	// Initial scan on startup
	Component.onCompleted: _scanCollections()
}
