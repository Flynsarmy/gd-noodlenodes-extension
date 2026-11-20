@tool
## Root labels shared by the root list and the system views' portal badges.

static func count_names(infos: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for root_id: int in infos:
		var root_name := str(infos[root_id].get("name", ""))
		counts[root_name] = int(counts.get(root_name, 0)) + 1
	return counts


static func label(info: Dictionary, duplicate_names: Dictionary) -> String:
	var root_name := str(info.get("name", ""))
	var host_name := str(info.get("host_node_name", ""))
	if host_name.is_empty():
		return root_name
	var generic := root_name == str(info.get("class", ""))
	var duplicated := int(duplicate_names.get(root_name, 0)) > 1
	return "%s › %s" % [host_name, root_name] if generic or duplicated else root_name
