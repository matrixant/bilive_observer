extends Node
class_name BiliveClient
@icon("icon/sitemap.svg")


enum ProtocolVersion {
	RAW_JSON = 0,  # JSON 格式的文本消息
	RAW_INT = 1,  # 32位整数，房间人气
	ZLIB_JSON = 2,  # zlib 压缩的数据包
	BROTLI = 3  # brotli 压缩的数据包
}

enum OperationType {
	HEARTBEAT = 2,  # 心跳包(客户端发出)，通常每 30 秒发送一次。长时间（70 秒后）不发送会断连。
	HEARTBEAT_RESPONSE = 3,  # 心跳包回应(服务端发出)，消息内容包含房间人气
	MESSAGE = 5,  # 弹幕、广播等全部信息(服务端发出)
	ENTER_ROOM = 7,  # 进入房间(客户端发出) websocket 连接成功后要发送的第一个数据包，发送要进入的房间 ID
	ENTER_ROOM_RESPONSE = 8  # 进房回应(服务端发出)
}

const PACKET_HEADER_SIZE := 16
const PACKET_LENGTH_OFFSET := 0
const PACKET_HEADER_SIZE_OFFSET := 4
const PACKET_PROTOCOL_VERSION_OFFSET := 6
const PACKET_OPERATION_TYPE_OFFSET := 8
const PACKET_SEQUENCE_OFFSET := 12


# 心跳包间隔，超过 70 会被断开连接。
@export_range(10, 60) var heartbeat_interval := 30
# 连接时超时时间，超时后断开连接
@export var connect_timeout: int = 5
# 真实房间 ID
@export var room_id: int = 0


# 心跳定时器
var _ws_hb_timer := Timer.new()
# websocket 连接
var _ws := WebSocketPeer.new()
# 未连接: false    已连接: true
var _ws_connected := false
# 处理连接 true
var _ws_process := false
# 接收到消息
signal message_received(messages: PackedStringArray)
signal connection_error(code: int, reason: String)

## room_id 为真实房间 ID
func connect_room(room_id: int, url: String, verify_tls: bool = true,
		trusted_tls_certificate: X509Certificate = null):
	var err = _ws.connect_to_url(url, verify_tls, trusted_tls_certificate)
	if err != OK:
		push_error("Can not connect to url: %s" % url)
		_ws_process = false
	self.room_id = room_id
	_ws_process = true
	
	var timeout := get_tree().create_timer(connect_timeout)
	timeout.timeout.connect(
		func():
			if not _ws_connected:
				_ws.close()
	)


func get_client_state():
	return _ws.get_ready_state()


func get_host_url():
	return _ws.get_requested_url()


func close(code: int = 1000, reason: String = ""):
	_ws.close(code, reason)


# 准备环境，等到调用 connect_room 后才开始处理连接
func _ready() -> void:
	#	处理 websocket 心跳包定时
	add_child(_ws_hb_timer)
	_ws_hb_timer.wait_time = heartbeat_interval
	_ws_hb_timer.timeout.connect(
		func():
			_ws.put_packet(_encode_packet("", OperationType.HEARTBEAT))
	)
	
	_ws_connected = false
	_ws_process = false


func _process(delta: float) -> void:
	if _ws_process:
		_ws.poll()
		var state = _ws.get_ready_state()
		match state:
			WebSocketPeer.STATE_CONNECTING:
				pass
			WebSocketPeer.STATE_OPEN:
				if not _ws_connected:
					_ws_connected = true
	#				发送进房消息
					var body = _encode_packet(JSON.stringify({"roomid": room_id}),
							OperationType.ENTER_ROOM)
					_ws.put_packet(body)
					_ws_hb_timer.start()
				
				while _ws.get_available_packet_count():
					_process_packet(_ws.get_packet())
			WebSocketPeer.STATE_CLOSING:
				pass
			WebSocketPeer.STATE_CLOSED:
				_ws_connected = false
				_ws_process = false
				if not _ws_hb_timer.is_stopped():
					_ws_hb_timer.stop()
				var code = _ws.get_close_code()
				var reason = _ws.get_close_reason()
				connection_error.emit(code, reason)
				print_debug("WebSocket closed with code: %d, reason %s. Clean: %s" % [code, reason, code != -1])


func _process_packet(packet: PackedByteArray):
	var protcol_ver := _read_int_from_buf(packet, 6, 2)
	var op_type := _read_int_from_buf(packet, 8, 4)
	var messages: PackedStringArray
	match protcol_ver:
		ProtocolVersion.RAW_JSON:
#			JSON 文本数据
			messages.append(packet.slice(16).get_string_from_utf8())
			pass
		ProtocolVersion.RAW_INT:
#			心跳包回复，返回直播间人气值
			if op_type == OperationType.HEARTBEAT_RESPONSE:
				var pop_num := _read_int_from_buf(packet, 16, 4)
#				心跳包返回人气，单独处理。
#				这里自己加了一条 cmd 为 ROOM_POPULARITY 的数据，
#				以便与其它弹幕和广播数据统一
				messages.append('{"cmd":"ROOM_POPULARITY","popularity":%d}' % pop_num)
			elif op_type == OperationType.ENTER_ROOM_RESPONSE:
#				进入直播间后的回应，单独处理。
#				这里自己加了一条 cmd 为 ROOM_ENTERED 的数据，
#				以便与其它弹幕和广播数据统一
				messages.append('{"cmd":"ROOM_ENTERED","room_id":%d}' % room_id)
		ProtocolVersion.ZLIB_JSON:
#			zlib 压缩的 JSON 数据，则解压后返回包内内容
			messages.append_array(_decode_packet(packet))
		ProtocolVersion.BROTLI:
#			NOTE: 暂时没有实现使用 Brotli 的解压缩方法
#			（目前的弹幕好像还没有用这种压缩，所以这里也不折腾了。）
			messages.append_array(_decode_packet(packet, false))
		_:
			push_error("Unknown Protocol Type.")
	if not messages.is_empty():
		message_received.emit(messages)
	else:
		push_error("Empty message.")


func _encode_packet(content: String, op) -> PackedByteArray:
	var data_buf := content.to_utf8_buffer()
	var packet_len := data_buf.size() + PACKET_HEADER_SIZE
	var packet: PackedByteArray = [0, 0, 0, 0, 0, PACKET_HEADER_SIZE, 0, 1, 0, 0, 0, op, 0, 0, 0, 1]
	_store_int_to_buf(packet, PACKET_LENGTH_OFFSET, 4, packet_len)
	packet.append_array(data_buf)
	return packet


# NOTE: 默认只处理了 zlib 压缩
func _decode_packet(packet: PackedByteArray, _zlib_compression = true) -> PackedStringArray:
	if packet.size() < PACKET_HEADER_SIZE:
		push_error("%s size[%d] too small." % [packet, packet.size()])
		return [] as PackedStringArray
	var packet_len := _read_int_from_buf(packet, PACKET_LENGTH_OFFSET, 4)
#	NOTE: 这里给解压后的数据分配的空间是压缩数据的 1032 倍
#	（zlib 官方给出的理论最高压缩率是 1032:1 。）
	var data_buf := packet.slice(PACKET_HEADER_SIZE).decompress(
			packet.size() * 1032, FileAccess.COMPRESSION_DEFLATE)
#	解压缩之后数据包里面可能有很多个包连在一块，需要根据整帧长度和分包长度进行分割
	var frame_len := data_buf.size()
	var message: PackedStringArray
	while frame_len > 0:
		var sub_pkt_len := _read_int_from_buf(data_buf, PACKET_LENGTH_OFFSET, 4)
		var sub_pkt_data := data_buf.slice(PACKET_HEADER_SIZE, sub_pkt_len)
		message.append(sub_pkt_data.get_string_from_utf8())
		data_buf = data_buf.slice(sub_pkt_len)
		frame_len -= sub_pkt_len
		pass
	return message


func _int_to_byte_array(val: int, bytes: int) -> PackedByteArray:
	if bytes < 1:
		push_error("bytes [%d] too small." % bytes)
		return [] as PackedByteArray
	var arr: PackedByteArray
	arr.resize(bytes)
	for i in range(bytes, 0, -1):
		arr[i - 1] = val & 0xFF
		val >>= 8
	
	return arr


func _store_int_to_buf(buf: PackedByteArray, start: int, bytes: int, value: int):
	if buf.size() < bytes:
		push_error("%s size[%d] too small." % [buf, buf.size()])
	for i in range(start + bytes - 1, start - 1, -1):
		buf[i] = value & 0xFF
		value >>= 8


func _read_int_from_buf(buf: PackedByteArray, start: int, bytes: int) -> int:
	var value := 0
	if buf.size() < bytes:
		push_error("%s size[%d] too small." % [buf, buf.size()])
		return -1
	for i in range(start, start + bytes):
		value <<= 8
		value += buf[i]
	return value
