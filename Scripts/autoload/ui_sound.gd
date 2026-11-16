extends Node
## Interface feedback for the whole game, wired up as nodes appear (no screen needs to do anything).
## Autoload name: UiSound
## - Buttons: a click when pressed; a short buzz and a red flash when a disabled one is clicked (so "nothing
##   happened" never goes unexplained); a soft tick when the pointer moves onto a Home tile or a big
##   PrimaryButton
## - Tabs (TabContainer): a swish, and the new tab's page fades in
## - Popups (AcceptDialog and friends): a whoosh, and their content fades and rises in
## A button with the meta "silent" set skips the click (for buttons that play their own sound).
## Settings: "ui_sounds" (on by default) turns the sounds off; the motion stays.

const HOVER_VOLUME := -10.0
const CLICK_VOLUME := -2.0
const ERROR_TINT := Color(1.6, 0.55, 0.55)

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func enabled() -> bool:
	return bool(GameState.get_setting("ui_sounds", true))

func play(sound: String, volume_db: float = 0.0) -> void:
	if enabled():
		Sound.play(sound, volume_db)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.pressed.connect(_on_pressed.bind(button))
		button.gui_input.connect(_on_button_input.bind(button))
		if node is HomeTile or (node is Button and (node as Button).theme_type_variation == &"PrimaryButton"):
			button.mouse_entered.connect(_on_hover.bind(button))
		elif node is Button:
			# Buttons set to PrimaryButton after they're added still get the hover tick
			button.mouse_entered.connect(func():
				if is_instance_valid(button) and (button as Button).theme_type_variation == &"PrimaryButton":
					_on_hover(button))
	elif node is TabContainer:
		(node as TabContainer).tab_changed.connect(_on_tab_changed.bind(node))
	elif node is AcceptDialog:
		(node as AcceptDialog).about_to_popup.connect(_on_popup.bind(node))

func _on_pressed(button: BaseButton) -> void:
	if not button.has_meta("silent"):
		play("click", CLICK_VOLUME)

func _on_hover(button: BaseButton) -> void:
	if is_instance_valid(button) and not button.disabled:
		play("hover", HOVER_VOLUME)

## A click on a disabled button: buzz and flash it red, so the player knows it can't be done right now
func _on_button_input(event: InputEvent, button: BaseButton) -> void:
	if not button.disabled or not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	play("error", -4.0)
	var t := button.create_tween()
	button.self_modulate = ERROR_TINT
	t.tween_property(button, "self_modulate", Color.WHITE, 0.35)

## The tab's page fades in (a container would undo a slide, so it's a fade)
func _on_tab_changed(_index: int, tabs: TabContainer) -> void:
	play("tab", -3.0)
	var page := tabs.get_current_tab_control()
	if page:
		page.modulate.a = 0.0
		page.create_tween().tween_property(page, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## A popup's content fades in
func _on_popup(dialog: AcceptDialog) -> void:
	play("open", -3.0)
	for child in dialog.get_children():
		if child is Control and not (child is Button) and child.visible:
			var c := child as Control
			c.modulate.a = 0.0
			c.create_tween().tween_property(c, "modulate:a", 1.0, 0.2).set_delay(0.03)
			break
