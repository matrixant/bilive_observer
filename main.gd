extends Control

const MSG := preload("res://msg.tscn")


var _user_list: Dictionary

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$BiliveObserver.start()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


# NOTE: 这里如果不限定 uid 为 int 的话，后续判断是否在字典里时可能出错。
func _on_bilive_observer_danmu_received(uid: int, uname, danmu) -> void:
	if not uid in _user_list:
		_user_list[uid] = BiliveInfo.User.new(uid, uname)
		var msg := MSG.instantiate()
		%Message.add_child(msg)
		msg.set_user(_user_list[uid])
		msg.set_info(danmu)
		msg.set_name(str(uid))
		$BiliveObserver.request_user_info(uid)
	else:
		var msg = %Message.get_node(str(uid))
		msg.set_info(danmu)
		%Message.move_child(msg, -1)
	pass # Replace with function body.


func _on_bilive_observer_user_info_requested(uid: int, info) -> void:
	if uid in _user_list:
		_user_list[uid].name = info.name
		_user_list[uid].face_url = info.face
		var msg = %Message.get_node(str(uid))
		msg.set_user(_user_list[uid])
		$BiliveObserver.request_user_face(uid, info.face)


func _on_bilive_observer_user_face_requested(uid: int, face) -> void:
	if uid in _user_list:
		_user_list[uid].avatar = face
		var msg = %Message.get_node(str(uid))
		msg.set_user(_user_list[uid])


func _on_bilive_observer_popularity_received(num) -> void:
	%Popularity.text = "在线人数：" + str(num)
	pass # Replace with function body.
