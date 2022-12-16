extends Node
class_name BiliveAPI
@icon("icon/scroll.svg")


enum RequestType {
	ROOM_PLAY_INFO,
	CHAT_CONF,
	ROOM_INFO,
	USER_INFO,
	USER_FACE
}

# http 请求间隔，建议请求间隔大于 1 秒。（规避反爬虫机制）
@export_range(1, 5, 0.1) var request_interval := 1.0

# 连接请求间隔定时器
var _http_req_timer := Timer.new()

# B 站直播相关 API 文件
const live_api_file := "res://addons/bilive_observer/live_api.json"

# HTTP 连接请求
var _http := HTTPRequest.new()
# HTTP 请求列表，每次有新的请求就加到这个列表里，然后等请求间隔大于一秒后再依次进行真正的
# 网络请求。存储数据为请求 url 和请求类型
var _http_request_list: Array
var _http_request_type_list: Array[RequestType]
# 请求用户头像时缓存 uid，用于指示当前请求用户的id，并判断用户头像是否重复请求
var _user_face_request_uid_list: Array[int]
# 请求用户信息时缓存的 uid，用于判断用户信息是否重复请求
var _user_info_request_uid_list: Array[int]

var live_apis: Dictionary

signal room_real_id_requested(room_id: int)
signal host_server_requested(host_servers: Array)
signal room_info_requested(room_info: Dictionary)
signal user_info_requested(user_info: Dictionary)
signal user_face_requested(uid: int, face_img: Image)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
#	处理 HTTP 请求间隔定时
	add_child(_http_req_timer)
	_http_req_timer.wait_time = request_interval
	_http_req_timer.one_shot = true
	_http_req_timer.timeout.connect(
		func():
#			如果请求列表非空且请求间隔满足，开始下一个请求
			if not _http_request_list.is_empty() and _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
				var req = _http_request_list.pop_front()
				_http_request(req.url, req.method)
#				print_debug("Request next. %d" % _http_request_list.size())
	)
#	处理 HTTP 请求结果
	add_child(_http)
	_http.request_completed.connect(
		func (result: int, response_code: int, headers: PackedStringArray,
				body: PackedByteArray):
#			弹出本次请求类型
			var request_type = _http_request_type_list.pop_front()
			if result == HTTPRequest.RESULT_SUCCESS:
				if request_type != RequestType.USER_FACE:
					var response = JSON.parse_string(body.get_string_from_utf8())
					if response.code != 0:
						push_error("Request error: {code} {message}".format(response))
					else:
						match request_type:
							RequestType.ROOM_PLAY_INFO:
								room_real_id_requested.emit(response.data.room_id)
							RequestType.CHAT_CONF:
								host_server_requested.emit(response.data.host_server_list)
							RequestType.ROOM_INFO:
								room_info_requested.emit(response.data.room_info)
							RequestType.USER_INFO:
								_user_info_request_uid_list.pop_front()
								user_info_requested.emit(response.data)
				else:
					var image = Image.new()
					var error = image.load_png_from_buffer(body)
					if error != OK:
						push_error("Couldn't load the image.")
					var uid: int = _user_face_request_uid_list.pop_front()
					user_face_requested.emit(uid, image)
#			如果请求列表非空且请求间隔满足，开始下一个请求
			if not _http_request_list.is_empty() and _http_req_timer.is_stopped():
				var req = _http_request_list.pop_front()
				_http_request(req.url, req.method)
#				print_debug("Request next. %d" % _http_request_list.size())
	)
	
	live_apis = JSON.parse_string(FileAccess.open(live_api_file, FileAccess.READ).get_as_text())


# NOTE: 如果短时间内连接请求很多会导致后面的请求延迟很久。
# 获取直播间开播信息
func room_play_info_request(room_disp_id: int):
	_http_request_append(live_apis.live.info.room_play_info.url + "?room_id=" + str(room_disp_id),
			HTTPClient.METHOD_GET)
	_http_request_type_list.append(RequestType.ROOM_PLAY_INFO)


# 获取直播服务器配置
func chat_conf_request(room_real_id: int):
	_http_request_append(live_apis.live.info.chat_conf.url + "?room_id=" + str(room_real_id),
			HTTPClient.METHOD_GET)
	_http_request_type_list.append(RequestType.CHAT_CONF)


# 获取直播间信息
func room_info_request(room_real_id: int):
	_http_request_append(live_apis.live.info.room_info.url + "?room_id=" + str(room_real_id),
			HTTPClient.METHOD_GET)
	_http_request_type_list.append(RequestType.ROOM_INFO)


# 获取用户信息
func user_info_request(uid: int):
	if uid in _user_info_request_uid_list:
		return
	_http_request_append(live_apis.user.info.info.url + "?mid=" + str(uid),
			HTTPClient.METHOD_GET)
	_http_request_type_list.append(RequestType.USER_INFO)
	_user_info_request_uid_list.append(uid)


# 获取用户头像
func user_face_request(uid: int, face_url: String):
	if uid in _user_face_request_uid_list:
		return
	_http_request_append(face_url + "@.png", HTTPClient.METHOD_GET)
	_http_request_type_list.append(RequestType.USER_FACE)
	_user_face_request_uid_list.append(uid)
#	print_debug("Face request list size: %d" % _user_face_request_uid_list.size())


# uid 用户信息是否在请求队列中
func is_user_info_request_queued(uid: int) -> bool:
	return uid in _user_info_request_uid_list


# uid 用户头像是否在请求队列中
func is_user_face_request_queued(uid: int) -> bool:
	return uid in _user_face_request_uid_list


# 追加请求，每次将新的请求加入队列，等到连接间隔过后依次请求。
# 外部不要直接访问 _http_request_append 和 _http_request
# 使用上面提供的函数进行请求。
func _http_request_append(url: String, method: HTTPClient.Method):
	if _http_req_timer.is_stopped() and _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		if _http_request_list.is_empty():
			_http_request(url, method)
		else:
			var req = _http_request_list.pop_front()
			_http_request(req.url, req.method)
			_http_request_list.append({"url":url, "method":method})
	else:
		_http_request_list.append({"url":url, "method":method})
#	print_debug("Request append: %d" % _http_request_list.size())


func _http_request(url: String, method: HTTPClient.Method):
	var err = _http.request(url, [], true, method)
	if err != OK:
		push_error("HTTP request error.")
	_http_req_timer.start()

