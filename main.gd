extends Node2D
## Top-down Blackjack for Godot 4.x.
## Graphics and sound effects are generated in code, so no asset files are needed.
## Keys: Space = Deal, H = Hit, S = Stand, D = Double, P = Split, M = Mute.

const W := 1280.0
const H := 720.0
const CARD := Vector2(100, 140)
const SHOE_POS := Vector2(1130, 140)
const DEALER_Y := 140.0
const PLAYER_Y := 470.0
const MAX_HANDS := 4
const RATE := 22050
const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const RED := Color(0.80, 0.10, 0.12)
const BLACK := Color(0.10, 0.10, 0.14)
const GOLD := Color(0.93, 0.78, 0.35)

enum State { BETTING, PLAYER, DEALER, OVER }


class Card:
	var rank := 0   # 0 = Ace ... 12 = King
	var suit := 0   # 0 spade, 1 heart, 2 diamond, 3 club
	var pos := Vector2.ZERO
	var target := Vector2.ZERO
	var rot := 0.0
	var flip := 0.0  # 0 = back showing, 1 = face showing

	func value() -> int:
		if rank == 0:
			return 11
		return mini(rank + 1, 10)


var shoe: Array = []
var player_hands: Array = [[]]
var hand_wagers: Array = []
var hand_texts: Array = []
var hand_cols: Array = []
var cur := 0
var has_split := false
var dealer_hand: Array = []
var dealer_hidden := false
var balance := 1000
var bet := 25
var state := State.BETTING
var message := "Place your bet"
var msg_color := Color.WHITE

var felt: GradientTexture2D
var sb_face: StyleBoxFlat
var sb_back: StyleBoxFlat
var sb_back_in: StyleBoxFlat
var sb_shadow: StyleBoxFlat
var shoe_card := Card.new()

var deal_btn: Button
var hit_btn: Button
var stand_btn: Button
var double_btn: Button
var split_btn: Button
var clear_btn: Button
var mute_btn: Button
var chip_btns: Array[Button] = []

var sounds := {}
var sfx_players: Array[AudioStreamPlayer] = []
var muted := false

const SAVE_PATH := "user://blackjack_save.json"
var menu: Control
var menu_buttons := {}
var menu_status: Label
var menu_btn: Button
var menu_open := false
var started := false


func _ready() -> void:
	randomize()
	_make_resources()
	_make_sounds()
	_build_ui()
	_build_menu()
	_new_shoe()
	_update_buttons()
	_open_menu()


# ---------------------------------------------------------------- setup

func _make_box(bg: Color, radius: int, border := 0, border_col := Color.WHITE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.anti_aliasing = true
	return s


func _make_resources() -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("2f9460"), Color("1c6e42"), Color("0c3b24")])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	felt = GradientTexture2D.new()
	felt.gradient = g
	felt.fill = GradientTexture2D.FILL_RADIAL
	felt.fill_from = Vector2(0.5, 0.5)
	felt.fill_to = Vector2(1.0, 0.5)
	felt.width = 512
	felt.height = 288

	sb_face = _make_box(Color(0.98, 0.97, 0.93), 8, 1, Color(0.6, 0.6, 0.6))
	sb_back = _make_box(Color(0.13, 0.22, 0.55), 8, 5, Color(0.96, 0.96, 0.96))
	sb_back_in = _make_box(Color(0, 0, 0, 0), 4, 2, GOLD)
	sb_shadow = _make_box(Color(0, 0, 0, 0.35), 9)


func _mk_btn(txt: String, pos: Vector2, sz: Vector2, col: Color, cb: Callable, fsize := 20,
		parent: Node = null) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	var variants := {
		"normal": col,
		"hover": col.lightened(0.15),
		"pressed": col.darkened(0.2),
		"disabled": col.darkened(0.55),
	}
	for key in variants:
		b.add_theme_stylebox_override(key, _make_box(variants[key], 10, 2, Color(1, 1, 1, 0.25)))
	b.pressed.connect(cb)
	if parent == null:
		add_child(b)
	else:
		parent.add_child(b)
	return b


func _build_ui() -> void:
	var y := 632.0
	var chip_defs := [[10, Color("2c5fb3")], [25, Color("b32c2c")], [50, Color("d9822b")], [100, Color("2b2b33")]]
	var x := 40.0
	for d in chip_defs:
		chip_btns.append(_mk_btn("+%d" % d[0], Vector2(x, y), Vector2(70, 50), d[1], _add_bet.bind(d[0])))
		x += 74.0
	clear_btn = _mk_btn("Clear", Vector2(x, y), Vector2(70, 50), Color("555555"), _clear_bet)

	deal_btn = _mk_btn("Deal (Space)", Vector2(430, y), Vector2(150, 50), Color("1f8a4c"), _start_round)
	hit_btn = _mk_btn("Hit (H)", Vector2(590, y), Vector2(110, 50), Color("2c5fb3"), _hit)
	stand_btn = _mk_btn("Stand (S)", Vector2(710, y), Vector2(130, 50), Color("b32c2c"), _stand)
	double_btn = _mk_btn("Double (D)", Vector2(850, y), Vector2(140, 50), Color("9a6b14"), _double)
	split_btn = _mk_btn("Split (P)", Vector2(1000, y), Vector2(140, 50), Color("7a3fa0"), _split)
	mute_btn = _mk_btn("Sound: On", Vector2(1150, y), Vector2(96, 50), Color("444a55"), _toggle_mute, 15)
	menu_btn = _mk_btn("Menu (Esc)", Vector2(1128, 32), Vector2(110, 30), Color("444a55"), _open_menu, 15)

	for _i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		sfx_players.append(p)


func _new_shoe() -> void:
	shoe.clear()
	for _d in 6:
		for s in 4:
			for r in 13:
				var c := Card.new()
				c.rank = r
				c.suit = s
				shoe.append(c)
	shoe.shuffle()


# ---------------------------------------------------------------- sound (synthesized)

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


# kind: 0 sine, 1 soft square, 2 triangle
func _add_tone(b: PackedFloat32Array, t0: float, dur: float, f0: float, f1: float,
		gain: float, decay: float, kind := 0) -> void:
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var idx := start + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, float(i) / n) / RATE
		var s := sin(phase)
		if kind == 1:
			s = signf(s) * 0.6
		elif kind == 2:
			s = asin(s) * 2.0 / PI
		b[idx] += s * exp(-t * decay) * minf(t / 0.004, 1.0) * gain


func _add_noise(b: PackedFloat32Array, t0: float, dur: float, gain: float,
		decay: float, smooth: float) -> void:
	var start := int(t0 * RATE)
	var n := int(dur * RATE)
	var last := 0.0
	for i in n:
		var idx := start + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		last = lerpf(last, randf_range(-1.0, 1.0), smooth)
		b[idx] += last * exp(-t * decay) * minf(t / 0.002, 1.0) * gain


func _to_wav(b: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _make_sounds() -> void:
	var b := _buf(0.14)
	_add_noise(b, 0.0, 0.14, 0.6, 28.0, 0.45)
	_add_tone(b, 0.0, 0.05, 140.0, 90.0, 0.25, 60.0)
	sounds["deal"] = _to_wav(b)

	b = _buf(0.1)
	_add_noise(b, 0.0, 0.1, 0.45, 45.0, 0.7)
	_add_tone(b, 0.0, 0.06, 220.0, 150.0, 0.2, 50.0)
	sounds["flip"] = _to_wav(b)

	b = _buf(0.25)
	_add_noise(b, 0.0, 0.03, 0.5, 150.0, 1.0)
	_add_tone(b, 0.0, 0.22, 2600.0, 2600.0, 0.3, 22.0)
	_add_tone(b, 0.0, 0.22, 3900.0, 3900.0, 0.2, 28.0)
	_add_tone(b, 0.0, 0.22, 1700.0, 1700.0, 0.2, 18.0)
	sounds["chip"] = _to_wav(b)

	b = _buf(0.06)
	_add_tone(b, 0.0, 0.04, 1500.0, 1500.0, 0.25, 120.0)
	_add_noise(b, 0.0, 0.02, 0.2, 150.0, 1.0)
	sounds["click"] = _to_wav(b)

	b = _buf(0.8)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for i in notes.size():
		_add_tone(b, i * 0.09, 0.4, notes[i], notes[i], 0.22, 6.0, 2)
		_add_tone(b, i * 0.09, 0.3, notes[i] * 2.0, notes[i] * 2.0, 0.05, 9.0)
	sounds["win"] = _to_wav(b)

	b = _buf(1.2)
	var fan := [523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0]
	for i in fan.size():
		_add_tone(b, i * 0.08, 0.35, fan[i], fan[i], 0.2, 7.0, 2)
	for f in [1046.5, 1318.5, 1568.0]:
		_add_tone(b, 0.5, 0.65, f, f, 0.14, 3.0, 2)
	sounds["blackjack"] = _to_wav(b)

	b = _buf(0.7)
	_add_tone(b, 0.0, 0.3, 330.0, 300.0, 0.14, 5.0, 1)
	_add_tone(b, 0.22, 0.4, 247.0, 196.0, 0.14, 5.0, 1)
	sounds["lose"] = _to_wav(b)

	b = _buf(0.55)
	_add_tone(b, 0.0, 0.5, 420.0, 100.0, 0.14, 3.0, 1)
	sounds["bust"] = _to_wav(b)

	b = _buf(0.4)
	_add_tone(b, 0.0, 0.15, 440.0, 440.0, 0.3, 14.0)
	_add_tone(b, 0.13, 0.15, 440.0, 440.0, 0.3, 14.0)
	sounds["push"] = _to_wav(b)


func _play(sfx: String, pitch := 1.0, vol := 0.0) -> void:
	if muted or not sounds.has(sfx) or sfx_players.is_empty():
		return
	var chosen: AudioStreamPlayer = sfx_players[0]
	for q in sfx_players:
		if not q.playing:
			chosen = q
			break
	chosen.stream = sounds[sfx]
	chosen.pitch_scale = pitch
	chosen.volume_db = vol
	chosen.play()


func _toggle_mute() -> void:
	muted = not muted
	mute_btn.text = "Sound: Off" if muted else "Sound: On"
	_play("click")


# ---------------------------------------------------------------- menu / save / load

func _build_menu() -> void:
	menu = Control.new()
	menu.position = Vector2.ZERO
	menu.size = Vector2(W, H)
	menu.visible = false
	add_child(menu)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.size = Vector2(W, H)
	menu.add_child(dim)  # also swallows clicks meant for the table

	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _make_box(Color(0.06, 0.18, 0.11, 0.97), 16, 3, GOLD))
	panel.size = Vector2(380, 500)
	panel.position = Vector2((W - 380.0) / 2.0, (H - 500.0) / 2.0)
	menu.add_child(panel)

	var title := Label.new()
	title.text = "BLACKJACK"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 24)
	title.size = Vector2(380, 60)
	panel.add_child(title)

	var defs := [
		["resume", "Resume", Color("1f8a4c"), _menu_resume],
		["new", "New Game", Color("2c5fb3"), _menu_new],
		["save", "Save Game", Color("9a6b14"), _menu_save],
		["load", "Load Game", Color("7a3fa0"), _menu_load],
		["quit", "Quit", Color("b32c2c"), _menu_quit],
	]
	var y := 104.0
	for d in defs:
		menu_buttons[d[0]] = _mk_btn(d[1], Vector2(40, y), Vector2(300, 52), d[2], d[3], 22, panel)
		y += 64.0

	menu_status = Label.new()
	menu_status.add_theme_font_size_override("font_size", 16)
	menu_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_status.position = Vector2(20, y + 4)
	menu_status.size = Vector2(340, 56)
	panel.add_child(menu_status)


func _open_menu(status := "") -> void:
	menu_open = true
	menu.visible = true
	menu_status.text = status
	if status == "" and started and not (state == State.BETTING or state == State.OVER):
		menu_status.text = "Finish the hand to save."
	_refresh_menu()


func _close_menu() -> void:
	menu_open = false
	menu.visible = false


func _refresh_menu() -> void:
	var between := state == State.BETTING or state == State.OVER
	var busy := state == State.DEALER
	menu_buttons["resume"].disabled = not started
	menu_buttons["new"].disabled = busy
	menu_buttons["save"].disabled = not (started and between)
	menu_buttons["load"].disabled = busy or not FileAccess.file_exists(SAVE_PATH)


func _reset_table() -> void:
	player_hands = [[]]
	dealer_hand.clear()
	hand_wagers.clear()
	hand_texts.clear()
	hand_cols.clear()
	cur = 0
	has_split = false
	dealer_hidden = false
	state = State.BETTING


func _menu_resume() -> void:
	if started:
		_play("click")
		_close_menu()


func _menu_new() -> void:
	if state == State.DEALER:
		return
	balance = 1000
	bet = 25
	_reset_table()
	_new_shoe()
	message = "New game - place your bet"
	msg_color = Color.WHITE
	started = true
	_update_buttons()
	_close_menu()
	_play("chip")


func _menu_save() -> void:
	if not (state == State.BETTING or state == State.OVER):
		return
	var data := {"version": 1, "balance": balance, "bet": bet, "muted": muted}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		menu_status.text = "Could not save (error %d)." % FileAccess.get_open_error()
		return
	f.store_string(JSON.stringify(data))
	f.close()
	menu_status.text = "Game saved."
	_play("click")
	_refresh_menu()


func _menu_load() -> void:
	if state == State.DEALER:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		menu_status.text = "No saved game found."
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("balance"):
		menu_status.text = "Save file is damaged."
		return
	balance = maxi(int(parsed["balance"]), 10)
	bet = clampi(int(parsed.get("bet", 25)), 0, _max_bet())
	if bet <= 0:
		bet = mini(10, _max_bet())
	muted = bool(parsed.get("muted", false))
	mute_btn.text = "Sound: Off" if muted else "Sound: On"
	_reset_table()
	if shoe.size() < 60:
		_new_shoe()
	message = "Game loaded"
	msg_color = Color.WHITE
	started = true
	_update_buttons()
	_close_menu()
	_play("chip")


func _menu_quit() -> void:
	get_tree().quit()


# ---------------------------------------------------------------- game logic

func _total_wager() -> int:
	var t := 0
	for w in hand_wagers:
		t += w
	return t


func _can_double() -> bool:
	if state != State.PLAYER or cur >= player_hands.size():
		return false
	var h: Array = player_hands[cur]
	return h.size() == 2 and balance >= hand_wagers[cur]


func _can_split() -> bool:
	if state != State.PLAYER or cur >= player_hands.size():
		return false
	if player_hands.size() >= MAX_HANDS:
		return false
	var h: Array = player_hands[cur]
	if h.size() != 2:
		return false
	var a: Card = h[0]
	var b: Card = h[1]
	if a.value() != b.value():
		return false
	if has_split and a.rank == 0:  # no re-splitting aces
		return false
	return balance >= hand_wagers[cur]


func _update_buttons() -> void:
	var can_bet := state == State.BETTING or state == State.OVER
	deal_btn.disabled = not can_bet or bet <= 0
	for b in chip_btns:
		b.disabled = not can_bet
	clear_btn.disabled = not can_bet
	hit_btn.disabled = state != State.PLAYER
	stand_btn.disabled = state != State.PLAYER
	double_btn.disabled = not _can_double()
	split_btn.disabled = not _can_split()


func _max_bet() -> int:
	return balance - balance % 10


func _add_bet(amount: int) -> void:
	bet = mini(bet + amount, _max_bet())
	_play("chip", randf_range(0.95, 1.08))
	_update_buttons()


func _clear_bet() -> void:
	bet = 0
	_play("click")
	_update_buttons()


func _eval(hand: Array, hide_hole := false) -> Vector2i:
	var total := 0
	var aces := 0
	for i in hand.size():
		if hide_hole and i == 1:
			continue
		var c: Card = hand[i]
		total += c.value()
		if c.rank == 0:
			aces += 1
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return Vector2i(total, 1 if aces > 0 else 0)


func _is_blackjack(hand: Array) -> bool:
	return hand.size() == 2 and _eval(hand).x == 21


func _hand_center(i: int) -> float:
	var hn := player_hands.size()
	if hn <= 1:
		return W / 2.0
	return 360.0 + (840.0 / hn) * (i + 0.5)


func _layout_all() -> void:
	# Dealer
	var n := dealer_hand.size()
	var sp := minf(78.0, 560.0 / maxf(n, 1))
	var total := (n - 1) * sp
	for i in n:
		var c: Card = dealer_hand[i]
		c.target = Vector2(W / 2.0 - total / 2.0 + i * sp, DEALER_Y)
	# Player hands
	var hn := player_hands.size()
	for hi in hn:
		var h: Array = player_hands[hi]
		var k := h.size()
		var cx := _hand_center(hi)
		var sp2 := 0.0
		if hn == 1:
			sp2 = minf(78.0, 560.0 / maxf(k, 1))
		else:
			sp2 = clampf((840.0 / hn - 110.0) / maxf(k - 1, 1), 22.0, 60.0)
		var tot := (k - 1) * sp2
		for j in k:
			var c: Card = h[j]
			c.target = Vector2(cx - tot / 2.0 + j * sp2, PLAYER_Y)


func _deal_to(hand: Array, face_up: bool) -> void:
	var c: Card = shoe.pop_back()
	c.pos = SHOE_POS
	c.target = SHOE_POS
	c.rot = randf_range(-0.04, 0.04)
	c.flip = 0.0
	hand.append(c)
	_layout_all()
	_play("deal", randf_range(0.92, 1.1))
	if face_up:
		var t := create_tween()
		t.tween_property(c, "flip", 1.0, 0.25).set_delay(0.15)
	await get_tree().create_timer(0.4).timeout


func _reveal_hole() -> void:
	dealer_hidden = false
	if dealer_hand.size() > 1:
		var c: Card = dealer_hand[1]
		var t := create_tween()
		t.tween_property(c, "flip", 1.0, 0.3)
		_play("flip")
	await get_tree().create_timer(0.5).timeout


func _start_round() -> void:
	if not (state == State.BETTING or state == State.OVER):
		return
	if bet <= 0 or bet > balance:
		return
	_play("chip")
	if shoe.size() < 60:
		_new_shoe()
	hand_wagers = [bet]
	balance -= bet
	player_hands = [[]]
	dealer_hand.clear()
	cur = 0
	has_split = false
	hand_texts.clear()
	hand_cols.clear()
	message = ""
	dealer_hidden = true
	state = State.DEALER
	_update_buttons()

	var h0: Array = player_hands[0]
	await _deal_to(h0, true)
	await _deal_to(dealer_hand, true)
	await _deal_to(h0, true)
	await _deal_to(dealer_hand, false)

	if _is_blackjack(h0) or _is_blackjack(dealer_hand):
		await _reveal_hole()
		_resolve()
		return
	state = State.PLAYER
	_update_buttons()


func _hit() -> void:
	if state != State.PLAYER:
		return
	var h: Array = player_hands[cur]
	state = State.DEALER
	_update_buttons()
	await _deal_to(h, true)
	if _eval(h).x >= 21:
		_advance()
	else:
		state = State.PLAYER
		_update_buttons()


func _stand() -> void:
	if state != State.PLAYER:
		return
	_play("click")
	state = State.DEALER
	_update_buttons()
	_advance()


func _double() -> void:
	if not _can_double():
		return
	_play("chip")
	var h: Array = player_hands[cur]
	balance -= hand_wagers[cur]
	hand_wagers[cur] = hand_wagers[cur] * 2
	state = State.DEALER
	_update_buttons()
	await _deal_to(h, true)
	_advance()


func _split() -> void:
	if not _can_split():
		return
	_play("chip")
	var h: Array = player_hands[cur]
	var w: int = hand_wagers[cur]
	balance -= w
	var moved: Card = h.pop_back()
	player_hands.insert(cur + 1, [moved])
	hand_wagers.insert(cur + 1, w)
	has_split = true
	state = State.DEALER
	_update_buttons()
	_layout_all()
	await get_tree().create_timer(0.35).timeout
	await _deal_to(h, true)
	var first: Card = h[0]
	if first.rank == 0 or _eval(h).x >= 21:  # split aces get one card only
		_advance()
	else:
		state = State.PLAYER
		_update_buttons()


## Called when the current hand is finished. Moves to the next hand (dealing its
## second card after a split) or hands over to the dealer.
func _advance() -> void:
	cur += 1
	while cur < player_hands.size():
		var h: Array = player_hands[cur]
		if h.size() < 2:
			await _deal_to(h, true)
		var first: Card = h[0]
		if first.rank == 0 or _eval(h).x >= 21:
			cur += 1
			continue
		state = State.PLAYER
		_update_buttons()
		return
	_after_player()


func _after_player() -> void:
	var any_live := false
	for h in player_hands:
		if _eval(h).x <= 21:
			any_live = true
	if not any_live:
		await _reveal_hole()
		_resolve()
	else:
		_dealer_turn()


func _dealer_turn() -> void:
	state = State.DEALER
	_update_buttons()
	await _reveal_hole()
	while _eval(dealer_hand).x < 17:  # dealer stands on all 17s
		await _deal_to(dealer_hand, true)
	_resolve()


func _resolve() -> void:
	dealer_hidden = false
	var d := _eval(dealer_hand).x
	var dbj := _is_blackjack(dealer_hand)
	var multi := player_hands.size() > 1
	var win := Color("ffe066")
	var lose := Color("ff7b7b")
	var push := Color("e8e8e8")
	hand_texts.clear()
	hand_cols.clear()
	var net_total := 0
	var long_msg := ""
	var long_col := push
	var any_bj := false
	var single_bust := false

	for i in player_hands.size():
		var h: Array = player_hands[i]
		var w: int = hand_wagers[i]
		var p := _eval(h).x
		var pbj := (not has_split) and _is_blackjack(h)
		var payout := 0
		var st := ""
		var lm := ""
		var col := push
		if p > 21:
			st = "BUST"
			lm = "Bust! Dealer wins"
			col = lose
		elif pbj and dbj:
			payout = w
			st = "PUSH"
			lm = "Push - both have Blackjack"
		elif pbj:
			payout = w + int(w * 1.5)
			st = "BLACKJACK"
			lm = "Blackjack! Pays 3 to 2"
			col = win
			any_bj = true
		elif dbj:
			st = "LOSE"
			lm = "Dealer has Blackjack"
			col = lose
		elif d > 21:
			payout = w * 2
			st = "WIN"
			lm = "Dealer busts! You win"
			col = win
		elif p > d:
			payout = w * 2
			st = "WIN"
			lm = "You win!"
			col = win
		elif p == d:
			payout = w
			st = "PUSH"
			lm = "Push"
		else:
			st = "LOSE"
			lm = "Dealer wins"
			col = lose
		balance += payout
		net_total += payout - w
		hand_texts.append(st)
		hand_cols.append(col)
		long_msg = lm
		long_col = col
		single_bust = p > 21

	if multi:
		if net_total > 0:
			message = "Net +$%d" % net_total
			msg_color = win
		elif net_total < 0:
			message = "Net -$%d" % -net_total
			msg_color = lose
		else:
			message = "Break even"
			msg_color = push
	else:
		message = long_msg
		msg_color = long_col
		if net_total > 0:
			message += "   +$%d" % net_total
		elif net_total < 0:
			message += "   -$%d" % -net_total

	if any_bj and not multi:
		_play("blackjack")
	elif net_total > 0:
		_play("win")
	elif net_total < 0:
		_play("bust" if (single_bust and not multi) else "lose")
	else:
		_play("push")

	if balance < 10:
		balance = 1000
		message += "   (out of chips - new bankroll)"
	bet = mini(bet, _max_bet())
	if bet <= 0:
		bet = mini(10, _max_bet())
	state = State.OVER
	_update_buttons()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if menu_open and started:
				_close_menu()
			elif not menu_open:
				_open_menu()
			return
		if menu_open:
			return
		match event.keycode:
			KEY_SPACE, KEY_ENTER:
				if not deal_btn.disabled:
					_start_round()
			KEY_H:
				if not hit_btn.disabled:
					_hit()
			KEY_S:
				if not stand_btn.disabled:
					_stand()
			KEY_D:
				if not double_btn.disabled:
					_double()
			KEY_P:
				if not split_btn.disabled:
					_split()
			KEY_M:
				_toggle_mute()


func _process(delta: float) -> void:
	if menu_open:
		_refresh_menu()
	var k := 1.0 - exp(-delta * 10.0)
	for c in dealer_hand:
		c.pos = c.pos.lerp(c.target, k)
	for h in player_hands:
		for c in h:
			c.pos = c.pos.lerp(c.target, k)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _text(txt: String, pos: Vector2, size: int, col: Color, center := false, shadow := true) -> void:
	var f := ThemeDB.fallback_font
	var p := pos
	var align := HORIZONTAL_ALIGNMENT_LEFT
	var width := -1.0
	if center:
		p = Vector2(pos.x - 600.0, pos.y)
		align = HORIZONTAL_ALIGNMENT_CENTER
		width = 1200.0
	if shadow:
		draw_string(f, p + Vector2(2, 2), txt, align, width, size, Color(0, 0, 0, 0.55))
	draw_string(f, p, txt, align, width, size, col)


func _total_text(hand: Array, hide: bool) -> String:
	var e := _eval(hand, hide)
	if e.y == 1 and e.x < 21 and not hide:
		return "Soft %d" % e.x
	return str(e.x)


func _draw() -> void:
	# Table
	draw_texture_rect(felt, Rect2(0, 0, W, H), false)
	draw_arc(Vector2(W / 2.0, -270), 560, deg_to_rad(28), deg_to_rad(152), 96, Color(GOLD, 0.55), 3.0, true)
	_text("BLACKJACK PAYS 3 TO 2", Vector2(W / 2.0, 268), 20, Color(GOLD, 0.75), true, false)

	# Wooden rail
	var wood := Color(0.22, 0.12, 0.06)
	draw_rect(Rect2(0, 0, W, 24), wood)
	draw_rect(Rect2(0, H - 24, W, 24), wood)
	draw_rect(Rect2(0, 0, 24, H), wood)
	draw_rect(Rect2(W - 24, 0, 24, H), wood)
	draw_rect(Rect2(24, 24, W - 48, H - 48), Color(GOLD, 0.5), false, 2.0)

	# Shoe
	if shoe.size() > 0:
		for i in 4:
			shoe_card.pos = SHOE_POS + Vector2(-i * 2.0, -i * 2.0)
			_draw_card(shoe_card)
		_text("%d cards" % shoe.size(), Vector2(SHOE_POS.x, 236), 16, Color(1, 1, 1, 0.7), true)

	# Cards
	for c in dealer_hand:
		_draw_card(c)
	for h in player_hands:
		for c in h:
			_draw_card(c)

	# Dealer label
	if dealer_hand.size() > 0:
		_text("DEALER  %s" % _total_text(dealer_hand, dealer_hidden), Vector2(W / 2.0, 52), 24, Color.WHITE, true)

	# Player hand labels
	var hn := player_hands.size()
	for i in hn:
		var h: Array = player_hands[i]
		if h.is_empty():
			continue
		var cx := _hand_center(i)
		var active := hn > 1 and i == cur and (state == State.PLAYER or state == State.DEALER)
		var tcol := GOLD if active else Color.WHITE
		if hn == 1:
			_text("YOU  %s" % _total_text(h, false), Vector2(cx, 580), 24, tcol, true)
		else:
			_text(_total_text(h, false), Vector2(cx, 580), 24, tcol, true)
			_text("$%d" % hand_wagers[i], Vector2(cx, 606), 18, GOLD, true)
			if active:
				var by := PLAYER_Y - 92.0 + sin(Time.get_ticks_msec() / 180.0) * 3.0
				draw_colored_polygon(PackedVector2Array([
					Vector2(cx - 11, by - 14), Vector2(cx + 11, by - 14), Vector2(cx, by)
				]), GOLD)
			elif state == State.OVER and i < hand_texts.size():
				_text(hand_texts[i], Vector2(cx, PLAYER_Y - 84), 22, hand_cols[i], true)

	if message != "":
		_text(message, Vector2(W / 2.0, 350), 36, msg_color, true)

	# HUD
	_text("BALANCE", Vector2(50, 58), 16, GOLD)
	_text("$%d" % balance, Vector2(50, 96), 36, Color.WHITE)

	var in_betting := state == State.BETTING or state == State.OVER
	var shown := bet if in_betting else _total_wager()
	if shown > 0:
		_draw_bet(shown, Vector2(110, 480))
	_text(("BET  $%d" if in_betting else "WAGER  $%d") % shown, Vector2(70, 560), 22, GOLD)


func _draw_card(c: Card) -> void:
	var sx := maxf(absf(cos(c.flip * PI)), 0.03)
	var rect := Rect2(-CARD / 2.0, CARD)
	draw_set_transform(c.pos + Vector2(5, 7), c.rot, Vector2(sx, 1))
	draw_style_box(sb_shadow, rect)
	draw_set_transform(c.pos, c.rot, Vector2(sx, 1))
	if c.flip > 0.5:
		_draw_face(c, rect, sx)
	else:
		_draw_back(rect)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_back(rect: Rect2) -> void:
	draw_style_box(sb_back, rect)
	draw_style_box(sb_back_in, rect.grow(-11))
	var lattice := Color(0.55, 0.65, 0.95, 0.55)
	for gx in range(-30, 31, 15):
		for gy in range(-45, 46, 15):
			var p := Vector2(gx, gy)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)
			]), lattice)


func _draw_face(c: Card, rect: Rect2, sx: float) -> void:
	draw_style_box(sb_face, rect)
	var col := RED if (c.suit == 1 or c.suit == 2) else BLACK

	_corner(c, col)
	draw_set_transform(c.pos, c.rot + PI, Vector2(sx, 1))
	_corner(c, col)
	draw_set_transform(c.pos, c.rot, Vector2(sx, 1))

	if c.rank == 0:
		_draw_suit(Vector2.ZERO, 38, c.suit, col)
	elif c.rank >= 10:
		draw_rect(Rect2(-32, -50, 64, 100), Color(col, 0.35), false, 2.0)
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(-40, 19), RANKS[c.rank], HORIZONTAL_ALIGNMENT_CENTER, 80, 54, col)
		_draw_suit(Vector2(-20, -38), 10, c.suit, col)
		_draw_suit(Vector2(20, 38), 10, c.suit, col, true)
	else:
		for p in _pips(c.rank + 1):
			_draw_suit(Vector2(p.x * 17.0, p.y * 40.0), 12, c.suit, col, p.y > 0.0)


func _corner(c: Card, col: Color) -> void:
	var half := CARD / 2.0
	var rs: String = RANKS[c.rank]
	draw_string(ThemeDB.fallback_font, Vector2(-half.x + 7, -half.y + 24), rs,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
	_draw_suit(Vector2(-half.x + 17, -half.y + 39), 8, c.suit, col)


func _pips(n: int) -> Array:
	var side := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	match n:
		2: return [Vector2(0, -1), Vector2(0, 1)]
		3: return [Vector2(0, -1), Vector2(0, 0), Vector2(0, 1)]
		4: return side
		5: return side + [Vector2(0, 0)]
		6: return side + [Vector2(-1, 0), Vector2(1, 0)]
		7: return side + [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -0.5)]
		8: return side + [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -0.5), Vector2(0, 0.5)]
		9: return side + [Vector2(-1, -0.33), Vector2(1, -0.33), Vector2(-1, 0.33), Vector2(1, 0.33), Vector2(0, 0)]
		10: return side + [Vector2(-1, -0.33), Vector2(1, -0.33), Vector2(-1, 0.33), Vector2(1, 0.33), Vector2(0, -0.67), Vector2(0, 0.67)]
	return []


func _draw_suit(p: Vector2, s: float, suit: int, col: Color, down := false) -> void:
	var k := -1.0 if down else 1.0
	match suit:
		0:  # spade
			draw_circle(p + Vector2(-0.28, 0.10 * k) * s, 0.34 * s, col)
			draw_circle(p + Vector2(0.28, 0.10 * k) * s, 0.34 * s, col)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -0.72 * k) * s, p + Vector2(-0.61, 0.12 * k) * s, p + Vector2(0.61, 0.12 * k) * s
			]), col)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-0.14, 0.68 * k) * s, p + Vector2(0.14, 0.68 * k) * s, p + Vector2(0, 0.1 * k) * s
			]), col)
		1:  # heart
			draw_circle(p + Vector2(-0.28, -0.12 * k) * s, 0.34 * s, col)
			draw_circle(p + Vector2(0.28, -0.12 * k) * s, 0.34 * s, col)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-0.61, -0.04 * k) * s, p + Vector2(0.61, -0.04 * k) * s, p + Vector2(0, 0.7 * k) * s
			]), col)
		2:  # diamond
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0, -0.72 * k) * s, p + Vector2(0.47, 0) * s,
				p + Vector2(0, 0.72 * k) * s, p + Vector2(-0.47, 0) * s
			]), col)
		3:  # club
			draw_circle(p + Vector2(0, -0.30 * k) * s, 0.31 * s, col)
			draw_circle(p + Vector2(-0.31, 0.08 * k) * s, 0.31 * s, col)
			draw_circle(p + Vector2(0.31, 0.08 * k) * s, 0.31 * s, col)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-0.31, 0.08 * k) * s, p + Vector2(0.31, 0.08 * k) * s, p + Vector2(0, -0.30 * k) * s
			]), col)
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(-0.14, 0.70 * k) * s, p + Vector2(0.14, 0.70 * k) * s, p + Vector2(0, 0.05 * k) * s
			]), col)


func _chip_color(d: int) -> Color:
	match d:
		10: return Color("2c5fb3")
		25: return Color("b32c2c")
		50: return Color("d9822b")
	return Color("2b2b33")


func _draw_chip(p: Vector2, d: int, label: bool) -> void:
	var col := _chip_color(d)
	draw_circle(p + Vector2(2, 3), 24, Color(0, 0, 0, 0.3))
	draw_circle(p, 24, col)
	for i in 8:
		var a := i * TAU / 8.0
		draw_arc(p, 21, a - 0.17, a + 0.17, 6, Color(1, 1, 1, 0.9), 6.0)
	draw_circle(p, 15, col.darkened(0.15))
	draw_arc(p, 15, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 1.5, true)
	if label:
		draw_string(ThemeDB.fallback_font, Vector2(p.x - 20, p.y + 5), str(d),
			HORIZONTAL_ALIGNMENT_CENTER, 40, 14, Color.WHITE)


func _draw_bet(amount: int, base: Vector2) -> void:
	var denoms: Array[int] = [100, 50, 25, 10]
	var rem := amount
	var column := 0
	for d in denoms:
		var cnt := floori(rem / float(d))
		rem -= cnt * d
		if cnt <= 0:
			continue
		var x := base.x + column * 54.0
		var shown := mini(cnt, 10)
		for j in shown:
			_draw_chip(Vector2(x, base.y - j * 5.0), d, j == shown - 1)
		column += 1
