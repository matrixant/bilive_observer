@tool
extends EditorPlugin

#const BiliveObserver = preload("bilive_observer.gd")
#const BiliveUtils = preload("bilive_utils.gd")

func _enter_tree():
#	add_custom_type("BiliveUtils", "RefCounted", preload("bilive_utils.gd"), get_icon("RefCounted"))
#	add_custom_type("BiliveObserver", "Node", preload("bilive_observer.gd"), get_icon("Node"))
	pass

func _exit_tree():
#	remove_custom_type("BiliveObserver")
#	remove_custom_type("BiliveUtils")
	pass


#func get_icon(node_name: String):
#	return get_editor_interface().get_base_control().get_icon(node_name, "EditorIcons")
