class_name GitHubSave
extends Node
## Commits files to the game's GitHub repository straight from the browser
## (level editor, animation lab), so a change reaches everyone after the next
## automatic build. Uses the GitHub REST API with a personal access token the
## user enters once; the token stays in this browser (user://).
##
## commit({"godot/data/levels/cave.txt": bytes, …}, "message") → {ok, error, url}

signal progress(text: String)

const OWNER := "bliksa"
const REPO := "keeper"
const TOKEN_FILE := "user://github_token"

## Override for tests (a local mock of the API); also settable with ?gh_api=… on the web.
static var api_base := "https://api.github.com"


static func has_token() -> bool:
	return get_token() != ""


static func get_token() -> String:
	if not FileAccess.file_exists(TOKEN_FILE):
		return ""
	return FileAccess.get_file_as_string(TOKEN_FILE).strip_edges()


static func set_token(token: String) -> void:
	var f := FileAccess.open(TOKEN_FILE, FileAccess.WRITE)
	if f:
		f.store_string(token.strip_edges())


static func forget_token() -> void:
	if FileAccess.file_exists(TOKEN_FILE):
		DirAccess.remove_absolute(TOKEN_FILE)


func _ready() -> void:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('gh_api') || ''")
		if q is String and q != "":
			api_base = q


func _api(method: int, path: String, body: Variant = null) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"Authorization: Bearer " + get_token(),
		"X-GitHub-Api-Version: 2022-11-28",
		"Content-Type: application/json",
	])
	var url := api_base + "/repos/%s/%s%s" % [OWNER, REPO, path]
	var err := req.request(url, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "request failed (%d)" % err}
	var res: Array = await req.request_completed
	req.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text) if text != "" else {}
	if code < 200 or code >= 300:
		var msg := "HTTP %d" % code
		if data is Dictionary and data.has("message"):
			msg += ": " + str(data.message)
		if code == 401:
			msg += " (token invalid or expired)"
		elif code == 403 or code == 404:
			msg += " (token needs Contents: read & write on %s/%s)" % [OWNER, REPO]
		return {"ok": false, "error": msg}
	return {"ok": true, "data": data}


## Reads a text file from the default branch (e.g. to merge before saving).
func read_text(path: String) -> Dictionary:
	var repo := await _api(HTTPClient.METHOD_GET, "")
	if not repo.ok:
		return repo
	var branch: String = repo.data.get("default_branch", "main")
	var r := await _api(HTTPClient.METHOD_GET, "/contents/%s?ref=%s" % [path, branch.uri_encode()])
	if not r.ok:
		return r
	var b64: String = str(r.data.get("content", "")).replace("\n", "")
	return {"ok": true, "text": Marshalls.base64_to_raw(b64).get_string_from_utf8()}


## One commit with all files (path in repo -> PackedByteArray) on the default branch.
func commit(files: Dictionary, message: String) -> Dictionary:
	if not has_token():
		return {"ok": false, "error": "no token"}
	progress.emit("Connecting to GitHub…")
	var repo := await _api(HTTPClient.METHOD_GET, "")
	if not repo.ok:
		return repo
	var branch: String = repo.data.get("default_branch", "main")
	var ref := await _api(HTTPClient.METHOD_GET, "/git/ref/heads/" + branch)
	if not ref.ok:
		return ref
	var head: String = ref.data.object.sha
	var head_commit := await _api(HTTPClient.METHOD_GET, "/git/commits/" + head)
	if not head_commit.ok:
		return head_commit
	var tree := []
	var n := 0
	for path in files:
		n += 1
		progress.emit("Uploading %d / %d…" % [n, files.size()])
		var blob := await _api(HTTPClient.METHOD_POST, "/git/blobs",
			{"content": Marshalls.raw_to_base64(files[path]), "encoding": "base64"})
		if not blob.ok:
			return blob
		tree.append({"path": path, "mode": "100644", "type": "blob", "sha": blob.data.sha})
	progress.emit("Committing…")
	var new_tree := await _api(HTTPClient.METHOD_POST, "/git/trees",
		{"base_tree": head_commit.data.tree.sha, "tree": tree})
	if not new_tree.ok:
		return new_tree
	var c := await _api(HTTPClient.METHOD_POST, "/git/commits",
		{"message": message, "tree": new_tree.data.sha, "parents": [head]})
	if not c.ok:
		return c
	var upd := await _api(HTTPClient.METHOD_PATCH, "/git/refs/heads/" + branch, {"sha": c.data.sha})
	if not upd.ok:
		return upd
	progress.emit("Saved.")
	return {"ok": true, "sha": c.data.sha, "url": "https://github.com/%s/%s/commit/%s" % [OWNER, REPO, c.data.sha]}


# --- token dialog -----------------------------------------------------------------

## Overlay asking for a token. Calls on_done(true) once a token is stored.
static func token_dialog(parent: Control, on_done: Callable) -> Control:
	var root := Control.new()
	root.size = Vector2(1066, 600)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.size = root.size
	root.add_child(dim)
	var card := Panel.new()
	card.position = Vector2(233, 120)
	card.size = Vector2(600, 320)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f172a")
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)
	var title := UiKit.label("Save to GitHub", 20, Color.WHITE, true)
	title.position = Vector2(24, 18)
	card.add_child(title)
	var help := UiKit.label(
		"Saving commits straight to %s/%s; the game rebuilds in ~2 minutes.\n\n" % [OWNER, REPO] +
		"Paste a GitHub token once (kept only in this browser):\n" +
		"github.com → Settings → Developer settings → Fine-grained tokens →\n" +
		"Repository access: only %s/%s · Permissions: Contents = Read and write." % [OWNER, REPO],
		12, Color("#cbd5e1"))
	help.position = Vector2(24, 56)
	help.size = Vector2(552, 120)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	card.add_child(help)
	var edit := LineEdit.new()
	edit.secret = true
	edit.placeholder_text = "github_pat_…"
	edit.position = Vector2(24, 200)
	edit.size = Vector2(552, 36)
	card.add_child(edit)
	var cancel := UiKit.button("Cancel", Vector2(120, 36), 12)
	cancel.position = Vector2(326, 260)
	cancel.pressed.connect(func():
		root.queue_free()
		on_done.call(false))
	card.add_child(cancel)
	var ok := UiKit.button("Save token", Vector2(130, 36), 12, Color("#059669"))
	ok.position = Vector2(456, 260)
	ok.pressed.connect(func():
		if edit.text.strip_edges() == "":
			return
		set_token(edit.text)
		root.queue_free()
		on_done.call(true))
	card.add_child(ok)
	parent.add_child(root)
	edit.grab_focus()
	return root
