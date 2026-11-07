class_name DevAccess
extends RefCounted
## One team password for developer mode and every "Save to repo".
##
## The GitHub token (fine-grained, Contents read & write on bliksa/keeper only)
## is stored in the repo encrypted with the password: data/dev_access.json
## {salt, iv, data, mac, iterations}. Entering the password decrypts it in the
## browser (kept like a pasted token, user://github_token). No server, and the
## token is never in the game in plain text. Set up / change it in Developer
## mode > Shortcuts > Team password.
##
## Key: SHA-256 stretched ITERATIONS times over salt + password; AES-256-CBC for
## the token, HMAC-SHA256 to tell a wrong password.

const PATH := "res://data/dev_access.json"
const REPO_PATH := "godot/data/dev_access.json"
const ITERATIONS := 60000

## Overrides the bundled file (tests, or right after setting it up here).
static var data_override: Variant = null


static func data() -> Dictionary:
	if data_override is Dictionary:
		return data_override
	if not FileAccess.file_exists(PATH):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if d is Dictionary and d.has("data") else {}


## A team password exists (the game asks for it instead of a token).
static func is_set_up() -> bool:
	return not data().is_empty()


static func _sha(b: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish()


## [aes key, mac key] from the password.
static func _keys(password: String, salt: PackedByteArray, iterations: int) -> Array:
	var pw := password.to_utf8_buffer()
	var k := _sha(salt + pw)
	for i in iterations:
		k = _sha(k + salt)
	return [_sha(k + "enc".to_utf8_buffer()), _sha(k + "mac".to_utf8_buffer())]


static func encrypt(token: String, password: String) -> Dictionary:
	var c := Crypto.new()
	var salt := c.generate_random_bytes(16)
	var iv := c.generate_random_bytes(16)
	var keys := _keys(password, salt, ITERATIONS)
	var plain := token.strip_edges().to_utf8_buffer()
	# PKCS#7 padding to the AES block size.
	var pad := 16 - plain.size() % 16
	for i in pad:
		plain.append(pad)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, keys[0], iv)
	var enc := aes.update(plain)
	aes.finish()
	var mac := c.hmac_digest(HashingContext.HASH_SHA256, keys[1], iv + enc)
	return {"salt": Marshalls.raw_to_base64(salt), "iv": Marshalls.raw_to_base64(iv),
		"data": Marshalls.raw_to_base64(enc), "mac": Marshalls.raw_to_base64(mac), "iterations": ITERATIONS}


## The token, or "" when the password is wrong.
static func decrypt(d: Dictionary, password: String) -> String:
	if d.is_empty() or password == "":
		return ""
	var salt := Marshalls.base64_to_raw(str(d.get("salt", "")))
	var iv := Marshalls.base64_to_raw(str(d.get("iv", "")))
	var enc := Marshalls.base64_to_raw(str(d.get("data", "")))
	var keys := _keys(password, salt, int(d.get("iterations", ITERATIONS)))
	var mac := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, keys[1], iv + enc)
	if Marshalls.raw_to_base64(mac) != str(d.get("mac", "")) or enc.size() == 0 or enc.size() % 16 != 0:
		return ""
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, keys[0], iv)
	var plain := aes.update(enc)
	aes.finish()
	var pad: int = plain[plain.size() - 1]
	if pad < 1 or pad > 16:
		return ""
	return plain.slice(0, plain.size() - pad).get_string_from_utf8()


## Unlocks saving with the team password; false = wrong password.
static func unlock(password: String) -> bool:
	var token := decrypt(data(), password)
	if token == "":
		return false
	GitHubSave.set_token(token)
	return true


## The password prompt (developer mode and "Save to repo"). on_done(ok).
static func password_dialog(parent: Node, on_done: Callable, allow_token := true) -> Control:
	var root := Control.new()
	root.size = Vector2(1066, 600)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.size = root.size
	root.add_child(dim)
	var card := Panel.new()
	card.position = Vector2(283, 150)
	card.size = Vector2(500, 250)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f172a")
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)
	var title := UiKit.label("Developer mode", 20, Color.WHITE, true)
	title.position = Vector2(24, 18)
	card.add_child(title)
	var help := UiKit.label("Enter the team password. This browser remembers it\n(it also unlocks “Save to repo” everywhere).", 12, Color("#cbd5e1"))
	help.position = Vector2(24, 56)
	card.add_child(help)
	var edit := LineEdit.new()
	edit.secret = true
	edit.placeholder_text = "Team password"
	edit.position = Vector2(24, 112)
	edit.size = Vector2(452, 36)
	card.add_child(edit)
	var msg := UiKit.label("", 12, Color("#f87171"))
	msg.position = Vector2(24, 152)
	card.add_child(msg)
	if allow_token:
		var tok := UiKit.button("Use a GitHub token", Vector2(170, 32), 11, Color(0, 0, 0, 0), Color("#94a3b8"))
		tok.position = Vector2(16, 196)
		tok.tooltip_text = "Paste your own GitHub token instead of the team password"
		tok.pressed.connect(func():
			root.queue_free()
			GitHubSave.token_dialog(parent, on_done, true))
		card.add_child(tok)
	var cancel := UiKit.button("Cancel", Vector2(110, 36), 12)
	cancel.position = Vector2(246, 194)
	cancel.pressed.connect(func():
		root.queue_free()
		on_done.call(false))
	card.add_child(cancel)
	var ok := UiKit.button("Unlock", Vector2(110, 36), 12, Color("#059669"))
	ok.position = Vector2(366, 194)
	var try := func():
		msg.text = "Checking…"
		await parent.get_tree().process_frame
		if unlock(edit.text):
			root.queue_free()
			on_done.call(true)
		else:
			msg.text = "Wrong password."
			edit.select_all()
	ok.pressed.connect(try)
	edit.text_submitted.connect(func(_t): try.call())
	card.add_child(ok)
	parent.add_child(root)
	edit.grab_focus()
	return root


## Team password setup: a token + a password → data/dev_access.json committed
## with that token. on_done(ok).
static func setup_dialog(parent: Node, gh: GitHubSave, on_done: Callable) -> Control:
	var root := Control.new()
	root.size = Vector2(1066, 600)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.size = root.size
	root.add_child(dim)
	var card := Panel.new()
	card.position = Vector2(213, 70)
	card.size = Vector2(640, 440)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f172a")
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)
	var title := UiKit.label("Team password", 20, Color.WHITE, true)
	title.position = Vector2(24, 18)
	card.add_child(title)
	var help := UiKit.label(
		"Everyone who knows this password can open developer mode and save to the repo, without a token.\n" +
		"1. GitHub token: github.com → Settings → Developer settings → Fine-grained tokens → only %s/%s, Contents = Read and write.\n" % [GitHubSave.OWNER, GitHubSave.REPO] +
		"2. A long password (e.g. four random words). The token is stored in the repo encrypted with it.\n" +
		"Changing it later: set it up again here; the old password stops working after the next build.",
		12, Color("#cbd5e1"))
	help.position = Vector2(24, 54)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.custom_minimum_size = Vector2(592, 0)
	help.size = Vector2(592, 130)
	card.add_child(help)
	var fields := []
	for i in 3:
		var e := LineEdit.new()
		e.secret = true
		e.placeholder_text = ["GitHub token (github_pat_…)", "Team password", "Team password again"][i]
		e.position = Vector2(24, 196 + i * 46)
		e.size = Vector2(592, 36)
		card.add_child(e)
		fields.append(e)
	if GitHubSave.has_token():
		fields[0].placeholder_text = "GitHub token (empty = the one this browser already uses)"
	var msg := UiKit.label("", 12, Color("#f87171"))
	msg.position = Vector2(24, 336)
	msg.size = Vector2(592, 40)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	card.add_child(msg)
	var cancel := UiKit.button("Cancel", Vector2(110, 36), 12)
	cancel.position = Vector2(370, 386)
	cancel.pressed.connect(func():
		root.queue_free()
		on_done.call(false))
	card.add_child(cancel)
	var ok := UiKit.button("Save", Vector2(130, 36), 12, Color("#059669"))
	ok.position = Vector2(490, 386)
	ok.pressed.connect(func():
		var token: String = fields[0].text.strip_edges()
		if token == "":
			token = GitHubSave.get_token()
		var pw: String = fields[1].text
		if token == "":
			msg.text = "Paste a GitHub token."
			return
		if pw.length() < 12:
			msg.text = "Use at least 12 characters (e.g. four random words)."
			return
		if pw != fields[2].text:
			msg.text = "The two passwords differ."
			return
		msg.text = "Encrypting…"
		await parent.get_tree().process_frame
		var d := encrypt(token, pw)
		GitHubSave.set_token(token)
		msg.text = "Saving to the repo…"
		var res: Dictionary = await gh.commit({REPO_PATH: (JSON.stringify(d, " ", false) + "\n").to_utf8_buffer()},
			"Developer mode: team password\n\nThe repo token, encrypted with the team password (data/dev_access.json).")
		if not res.ok:
			msg.text = "Save failed: " + str(res.error)
			if "token" in str(res.error):
				GitHubSave.forget_token()
			return
		data_override = d
		root.queue_free()
		on_done.call(true))
	card.add_child(ok)
	parent.add_child(root)
	fields[0].grab_focus()
	return root
