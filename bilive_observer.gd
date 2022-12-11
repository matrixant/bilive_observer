extends Node
class_name BiliveObserver
@icon("icon/bilibili.svg")

# 弹幕、广播消息的类型
const MessageType := {
	"DANMU": "DANMU_MSG",  # 弹幕消息
	"SC": "SUPER_CHAT_MESSAGE",  # 付费 SC
	
	"GIFT": "SEND_GIFT",  # 投喂礼物
	"GIFTS": "COMBO_SEND",  # 连击礼物
	
	"USER_ENTER": "INTERACT_WORD",  # 进房提示
	
	"GUARD_ENTER": "ENTRY_EFFECT",  # 舰长进房提示
	"GUARD_BUY": "GUARD_BUY",  # 上舰提示
	"GUARD_RENEW": "USER_TOAST_MSG",  #"续费了舰长"
	"NOTICE": "NOTICE_MSG",  # 在本房间续费了舰长
	
	"REAL_TIME_MSG_UPDATE": "ROOM_REAL_TIME_MESSAGE_UPDATE",  # 粉丝关注变动
	"FANS_LIKE": "FAN_LIKE_CHANGE",  # 粉丝关注
	"WATCHED_USERS": "WATCHED_CHANGE",  # 观看人数改变
	"ONLINE_RANK_COUNT": "ONLINE_RANK_COUNT",  # 高能榜计数
	"ONLINE_RANK_V2": "ONLINE_RANK_V2",  # 高能榜前 7 变化（大概）
	"ONLINE_RANK_TOP3": "ONLINE_RANK_TOP3",  # 高能榜前 3 变化
	
	"HOT_RANK_CHANGED": "HOT_RANK_CHANGED",  # 分区排行变化，例如单价游戏分区
	"HOT_RANK_CHANGED_V2": "HOT_RANK_CHANGED_V2",  # 二级分区变化，例如单价游戏下的独立游戏分区
	
	"LIKE_INFO_CLICK": "LIKE_INFO_V3_CLICK",  # 为主播点赞
	"LIKE_INFO_UPDATE": "LIKE_INFO_V3_UPDATE",  # 点赞数更新
	
#	下面几个接收到过，但没有研究具体代表什么
	"SC_DEL": "SUPER_CHAT_MESSAGE_DELETE",
	"COMMON_NOTICE_DANMUKU": "COMMON_NOTICE_DANMUKU",
	"PREPARING": "PREPARING",
	"SHOPPING_CART_SHOW": "SHOPPING_CART_SHOW",
	"HOT_ROOM_NOTIFY": "HOT_ROOM_NOTIFY",
	"BANNER": "WIDGET_BANNER",
	"GOTO_BUY_FLOW": "GOTO_BUY_FLOW",
	"INTERACTIVE_GAME": "LIVE_INTERACTIVE_GAME",
	"STOP_LIVE_ROOM": "STOP_ROOM_ROOM_LIST",
	"SPECIAL_GIFT": "SPECIAL_GIFT",
	
#	ROOM_POPULARITY 是自己加的，为了让心跳包回复的人气和其它消息统一
	"ROOM_POPULARITY": "ROOM_POPULARITY",
#	ROOM_ENTERED 是自己加的，为了让进入直播间的回复和其它消息统一
	"ROOM_ENTERED": "ROOM_ENTERED",
}

# B 站 websocket 连接地址
@export var wss_default_url: String = "wss://broadcastlv.chat.bilibili.com:2245/sub"
# 显示在地址栏里的房间 ID，有可能不是真实 ID，后续需要通过 API 再获取真实 ID
@export var room_disp_id: int = 1377453
# http 请求间隔，建议请求间隔大于 1 秒。（规避反爬虫机制）
@export_range(1, 5, 0.1) var request_interval := 1.0
# 心跳包间隔，超过 70 会被断开连接。
@export_range(10, 60) var heartbeat_interval := 30

@export var log_enabled := false

# 房间真实 ID，B 站给一些大主播会分配短 ID，直接通过短 ID 没法访问到直播间，
# 要先用 API 取到房间真实 ID 再进行连接。
var _room_real_id: int

# websocket 客户端
var _client := BiliveClient.new()
# HTTP 请求 API
var _api := BiliveAPI.new()
# WebSocket 服务器列表
var _host_servers: Array


signal popularity_received(num: int)  # 直播间人气，心跳回复时附带
signal user_entered(uid: int, uname: String)  # 有人进入直播间
signal guard_entered(uid: int, guard: Dictionary)
signal danmu_received(uid: int, uname: String, danmu: String)  # 收到弹幕消息
signal gift_received(uid: int, uname: String, gift: Dictionary)  # 收到礼物
signal watch_changed(num: int)  # 观看人数改变
signal super_chat_received(uid: int, uname: String, sc: Dictionary)  # 付费留言

signal room_real_id_requested(id: int)

signal user_info_requested(uid: int, uname: String, uface: String)
signal user_face_requested(uid: int, face: Image)

signal msg_received(msg)


var user_list: Dictionary

var _log_file: FileAccess


func start(room_id: int = -1):
	if room_id > 0:
		room_disp_id = room_id
#	请求直播间开播信息，获取真实房间 ID
	_api.room_play_info_request(room_disp_id)


func stop():
	_client.stop()
	pass

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	add_child(_client)
	_client.heartbeat_interval = heartbeat_interval
#	_client.wss_url = wss_url
	_client.message_received.connect(_process_message)
	_client.connection_error.connect(
		func(code, reson):
			if not _host_servers.is_empty():
				var host_server = _host_servers.pop_back()
#				试连每一个主机，直到找到能够连接到的主机
				var wss_url := "wss://{host}:{wss_port}/sub".format(host_server)
				print_debug("Try connect to %s." % wss_url)
				_client.connect_room(_room_real_id, wss_url)
	)
	
	add_child(_api)
	_api.request_interval = request_interval
	_api.room_real_id_requested.connect(
		func(room_id: int):
			_room_real_id = room_id
			print_debug("Room real id: %s" % _room_real_id)
#			请求聊天服务器配置，获取 WebSocket 服务器主机列表
			_api.chat_conf_request(room_id)
	)
	_api.host_server_requested.connect(
		func(host_servers: Array):
#			var wss_url := "wss://{host}:{wss_port}/sub".format(host_servers[0])
#			先尝试使用默认连接，连接失败再尝试这里请求的连接
			_client.connect_room(_room_real_id, wss_default_url)
			print_debug("Try connect to %s." % wss_default_url)
			_host_servers.append_array(host_servers)
	)
	_api.user_info_requested.connect(
		func(user_info: Dictionary):
#			这里要把 mid 强制转换成整型，否则可能会判断失败
			if (user_info.mid as int) in user_list:
				if user_list[(user_info.mid as int)].name.is_empty() or user_list[(user_info.mid as int)].face_url.is_empty():
					user_list[(user_info.mid as int)].name = user_info.name
					user_list[(user_info.mid as int)].face_url = user_info.face
					_api.user_face_request((user_info.mid as int), user_info.face)
			else:
				add_user(user_info.mid, user_info.name, user_info.face)
				print_debug("Add %d, total %d" % [user_info.mid, user_list.size()])
#			print("[%d]编号：{mid}, 名字：{name}, 性别：{sex}, 等级：{level}".format(user_info) % user_list.size())
	)
	_api.user_face_requested.connect(
		func(uid: int, face_img: Image):
#			print_debug("User[%s] face requested" % uid)
			user_face_requested.emit(uid, face_img)
	)
	
	if log_enabled:
		var time := Time.get_datetime_dict_from_system()
#		print_debug(time)
		_log_file = FileAccess.open("msg_log_{year}{month}{day}{hour}{minute}{second}.txt".format(time)
				, FileAccess.WRITE)


func _process_message(messages: PackedStringArray):
	var json := JSON.new()
	for message in messages:
		if log_enabled:
			_log_file.store_line(message)
#		_log_file.store_string(message+"\n")
#		print_debug(message)
		var err = json.parse(message)
		if err == OK:
			var msg_data = json.data
			if typeof(msg_data) == TYPE_DICTIONARY:
				msg_received.emit(msg_data)
#				NOTE: 2022-12-06 弹幕命令后面有的会带一串不明意义的数串，这里单独处理
				if msg_data.cmd.begins_with(MessageType.DANMU):
					danmu_received.emit(msg_data.info[2][0], msg_data.info[2][1], msg_data.info[1])
#					先用 uid 和 uname 生成用户对象，后续再请求头像信息
					add_user(msg_data.info[2][0], msg_data.info[2][1])
					print("%s[%d]说: %s" % [msg_data.info[2][1], msg_data.info[2][0], msg_data.info[1]])
#					print_debug(msg_data)
					continue
				match msg_data.cmd:
					MessageType.SC:
#						NOTE: SC 有两种，SUPER_CHAT_MESSAGE 和 SUPER_CHAT_MESSAGE_JPN
#						这里直接匹配 SUPER_CHAT_MESSAGE（JPN结尾的也会同步发送这个版本）
						super_chat_received.emit(msg_data.data.uid, msg_data.data.user_info.uname, msg_data.data)
#						付费留言里面用户ID、用户名和头像地址都有了，可以直接请求头像
						add_user(msg_data.data.uid, msg_data.data.user_info.uname, msg_data.data.user_info.face)
#						print("[SC]%s[%d]说: %s" % [msg_data.data.user_info.uname, msg_data.data.uid, msg_data.data.message])
					MessageType.GIFT:
#						"data":{"action":"投喂","giftId":31531,"giftName":"PK票","giftType":5,"num":1,"uid":1234567,"uname":"ABC",...}
						gift_received.emit(msg_data.data.uid, msg_data.data.uname, msg_data.data)
#						礼物消息里面用户ID、用户名和头像地址都有了，可以直接请求头像 
						add_user(msg_data.data.uid, msg_data.data.uname, msg_data.data.face)
#						print("%s%s礼物: %s x %d" % [msg_data.data.uname, msg_data.data.action, msg_data.data.giftName, msg_data.data.num])
					MessageType.GIFTS:
#						"data":{"action":"投喂","gift_id":30869,"gift_name":"心动卡","gift_num":0,"total_num":10,"uid":1234567,"uname":"ABC",...}
						gift_received.emit(msg_data.data.uid, msg_data.data.uname, msg_data.data)
#						先用 uid 和 uname 生成用户对象，后续再请求头像信息
						add_user(msg_data.data.uid, msg_data.data.uname)
#						print("%s%s礼物: %s x %d" % [msg_data.data.uname, msg_data.data.action, msg_data.data.gift_name, msg_data.data.total_num])
					MessageType.USER_ENTER:
						user_entered.emit(msg_data.data.uid, msg_data.data.uname)
#						print("%s进入房间" % msg_data.data.uname)
					MessageType.GUARD_ENTER:
						guard_entered.emit(msg_data.data.uid)
#						先用 uid 生成用户对象，后续再请求详细信息
						add_user(msg_data.data.uid)
						print(msg_data.data.copy_writing)
					MessageType.STOP_LIVE_ROOM:
						pass
					MessageType.ROOM_ENTERED:
						print("连接直播间[%d]成功" % msg_data.room_id)
						pass
					MessageType.ROOM_POPULARITY:
						var pop_num: int = msg_data.popularity
						popularity_received.emit(pop_num)
#						print("人气: %d" % pop_num);
					_:
#						print("Unhandled: %s" % msg_data.cmd)
						pass
#				print_debug(message)
			else:
				printerr("Unexpected data")
		else:
			printerr("JSON Parse Error: %s in %s at line %s" % [json.get_error_message(), message, json.get_error_line()])


func add_user(uid: int, uname: String = "", uface: String = ""):
	if uid in user_list:
#		print("%s already in list" % uid)
		return
	var user = BiliveInfo.User.new(uid, uname, uface)
	user_list[uid] = user
	if uface.is_empty() or uname.is_empty():
		_api.user_info_request(uid)
	else:
		_api.user_face_request(uid, uface)
#	user_info_requested.emit(uid, uname, uface)
	print("%s added: %d" % [user, user_list.size()])
	print("Request list %d" % _api._user_info_request_uid_list.size())
	
	
