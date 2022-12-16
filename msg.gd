extends HBoxContainer

@export var avatar_size := 24

var _user: BiliveInfo.User

func set_user(user: BiliveInfo.User):
	_user = user
	if not _user.name.is_empty():
		set_user_name(_user.name)
	if _user.avatar != null:
		set_avatar(_user.avatar)


func set_avatar(img: Image):
	if img != null:
		img.resize(avatar_size, avatar_size, Image.INTERPOLATE_BILINEAR)
		$Avatar.texture = ImageTexture.create_from_image(img)


func set_user_name(uname: String):
	$Name.text = uname


func set_info(info: String):
	$Info.text = ": " + info


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Avatar.custom_minimum_size = Vector2i(avatar_size, avatar_size)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
