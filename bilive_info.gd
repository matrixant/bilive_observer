extends RefCounted
class_name BiliveInfo

class User extends RefCounted:
	var id: int
	var name: String
	var face_url: String
	var avatar: Image:
		set(img):
			avatar = img
		get:
			return avatar
	
	func _init(id: int, name: String, face_url: String):
		self.id = id
		self.name = name
		self.face_url = face_url
	
	
	func _to_string() -> String:
		return "%s, uid: %d" % [name, id]


## 
##
