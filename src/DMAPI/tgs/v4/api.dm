#define TGS4_PARAM_INFO_JSON "tgs_json"

#define TGS4_INTEROP_ACCESS_IDENTIFIER "tgs_tok"

#define TGS4_RESPONSE_SUCCESS "tgs_succ"

#define TGS4_TOPIC_CHANGE_PORT "tgs_port"
#define TGS4_TOPIC_CHANGE_REBOOT_MODE "tgs_rmode"
#define TGS4_TOPIC_CHAT_COMMAND "tgs_chat_comm"
#define TGS4_TOPIC_EVENT "tgs_event"

#define TGS4_COMM_ONLINE "tgs_on"
#define TGS4_COMM_IDENTIFY "tgs_ident"
#define TGS4_COMM_VALIDATE "tgs_vali"
#define TGS4_COMM_SERVER_PRIMED "tgs_prime"
#define TGS4_COMM_WORLD_REBOOT "tgs_reboot"
#define TGS4_COMM_END_PROCESS "tgs_kill"
#define TGS4_COMM_CHAT "tgs_chat_send"

#define TGS4_PARAMETER_COMMAND "tgs_com"
#define TGS4_PARAMETER_DATA "tgs_data"

#define TGS4_PARAMETER_NEW_PORT "new_port"
#define TGS4_PARAMETER_NEW_REBOOT_MODE "new_rmode"

/datum/tgs_api/v4
	var/access_identifier
	var/instance_name
	var/host_path
	var/json_path
	var/chat_channels_json_path
	var/chat_commands_json_path
	var/reboot_mode = TGS_REBOOT_MODE_NORMAL
	
	var/list/intercepted_message_queue
	
	var/list/custom_commands

	var/list/cached_test_merges
	var/datum/tgs_revision_information/cached_revision

	var/datum/tgs_event_handler/event_handler

/datum/tgs_api/v4/ApiVersion()
	return "4.0.0.0"

/datum/tgs_api/v4/OnWorldNew(datum/tgs_event_handler/event_handler)
	json_path = world.params[TGS4_PARAM_INFO_JSON]
	if(!json_path)
		TGS_ERROR_LOG("Missing [TGS4_PARAM_INFO_JSON] world parameter!")
		return
	var/json_file = file2text(json_path)
	if(!json_file)
		TGS_ERROR_LOG("Missing specified json file: [json_path]")
		return
	var/cached_json = json_decode(json_file)
	if(!cached_json)
		TGS_ERROR_LOG("Failed to decode info json: [json_file]")
		return

	access_identifier = cached_json["access_identifier"]
	instance_name = text2num(cached_json["instance_name"])
	host_path = cached_json["host_path"]
	if(cached_json["api_validate_only"])
		Export(TGS4_COMM_VALIDATE)
		del(world)
		
	chat_channels_json_path = cached_json["chat_channels_json"]
	chat_commands_json_path = cached_json["chat_commands_json"]
	src.event_handler = event_handler
	instance_name = cached_json["instance_name"]

	cached_test_merges = list()
	var/json = cached_json["test_merges"]
	for(var/I in json)
		var/datum/tgs_revision_information/test_merge/tm = new
		tm.number = text2num(I)
		var/list/entry = json[I]
		tm.pull_request_commit = entry["pr_commit"]
		tm.author = entry["author"]
		tm.title = entry["title"]
		tm.commit = entry["commit"]
		tm.origin_commit = entry["origin_commit"]
		tm.time_merged = text2num(entry["time_merged"])
		tm.comment = entry["comment"]
		tm.url = entry["url"]

	cached_revision = new
	cached_revision.commit = cached_json["commit"]
	cached_revision.origin_commit = cached_json["origin_commit"]

	ListCustomCommands()

/datum/tgs_api/v4/OnInitializationComplete()
	Export(TGS4_COMM_SERVER_PRIMED)
	var/tgs4_secret_sleep_offline_sauce = 24051994
	var/old_sleep_offline = world.sleep_offline
	sleep(1)
	if(world.sleep_offline == tgs4_secret_sleep_offline_sauce)	//if not someone changed it
		world.sleep_offline = old_sleep_offline

/datum/tgs_api/v4/OnTopic(T)
	var/list/params = params2list(T)
	var/their_sCK = params[TGS4_INTEROP_ACCESS_IDENTIFIER]
	if(!their_sCK)
		return FALSE	//continue world/Topic

	if(their_sCK != access_identifier)
		return "Invalid comms key!";

	var/command = params[TGS4_INTEROP_ACCESS_IDENTIFIER]
	if(!command)
		return "No command!"

	switch(command)
		if(TGS4_TOPIC_CHAT_COMMAND)
			var/result = HandleCustomCommand(params[TGS4_TOPIC_CHAT_COMMAND])
			if(!result)
				return json_encode(list("error" = "Error running chat command!"))
			return result
		if(TGS4_TOPIC_EVENT)
			intercepted_message_queue = list()
			event_handler.HandleEvent(text2num(params[TGS4_TOPIC_EVENT]))
			. = json_encode(intercepted_message_queue)
			intercepted_message_queue = null
			return
	
	return "Unknown command: [command]"

/datum/tgs_api/v4/proc/Export(command, list/data)
	var/url = "[host_path]/Interop?[TGS4_INTEROP_ACCESS_IDENTIFIER]=[url_encode(access_identifier)]&[TGS4_PARAMETER_COMMAND]=[url_encode(command)]"
	if(data)
		url = "[url]&[TGS4_PARAMETER_DATA]=[url_encode(json_encode(data))]"
	var/list/res = world.Export(url)
	if(!istype(res))
		TGS_ERROR_LOG("Error contacting TGS webapi at [host_path] (command: [command])! world.Export returned something not a list (probably null): [res]")
		return
	var/byond_status = res["STATUS"]
	var/byond_content = res["CONTENT"]
	if(byond_status != "200 OK")
		TGS_ERROR_LOG("Error contacting TGS webapi at [host_path] (command: [command])! Top level HTTP [byond_status]: [byond_content]")
		return
	var/json = json_decode(byond_content)	//always expecting json
	if(!json)
		TGS_ERROR_LOG("Error contacting TGS webapi at [host_path] (command: [command])! Byond content not json: [byond_content]")
		return
	var/status = json["STATUS"]
	var/content = json["CONTENT"]
	if(status != 200)	//HTTP OK
		TGS_ERROR_LOG("Error contacting TGS webapi at [host_path] (command: [command])! HTTP [status]: [json_encode(content)]")
		return
	return content

/datum/tgs_api/v4/OnReboot()
	var/json = Export(TGS4_COMM_WORLD_REBOOT)
	var/list/result = json_decode(json)
	if(!result)
		return
	
	//TODO: Port handling

/datum/tgs_api/v4/InstanceName()
	return instance_name

/datum/tgs_api/v4/TestMerges()
	return cached_test_merges
	
/datum/tgs_api/v4/EndProcess()
	Export(TGS4_COMM_END_PROCESS)

/datum/tgs_api/v4/Revision()
	return cached_revision

/datum/tgs_api/v4/ChatBroadcast(message, list/channels)
	var/list/ids
	if(length(channels))
		ids = list()
		for(var/I in channels)
			var/datum/tgs_chat_channel/channel = I
			ids += channel.id
	message = list("message" = message, "channels" = ids)
	if(intercepted_message_queue)
		intercepted_message_queue += list(message)
	else
		Export(TGS4_COMM_CHAT, message)

/datum/tgs_api/v4/ChatTargetedBroadcast(message, admin_only)
	message = list("message" = message, "channels" = admin_only ? "admin" : "game")
	if(intercepted_message_queue)
		intercepted_message_queue += list(message)
	else
		Export(TGS4_COMM_CHAT, message)

/datum/tgs_api/v4/ChatPrivateMessage(message, datum/tgs_chat_user/user)
	message = list("message" = message, "user" = list("id" = user.id, "channel" = user.channel.id))
	if(intercepted_message_queue)
		intercepted_message_queue += list(message)
	else
		Export(TGS4_COMM_CHAT, message)

/datum/tgs_api/v4/ChatChannelInfo()
	. = list()
	//no caching cause tgs may change this
	var/list/json = json_decode(file2text(chat_channels_json_path))
	for(var/I in json)
		. += DecodeChannel(I)

/datum/tgs_api/v4/proc/DecodeChannel(channel_json)
	var/datum/tgs_chat_channel/channel = new
	channel.id = channel_json["id"]
	channel.friendly_name = channel_json["friendly_name"]
	channel.connection_name = channel_json["connection_name"]
	channel.is_admin_channel = channel_json["is_admin_channel"]
	channel.is_private_channel = channel_json["is_private_channel"] || FALSE
	return channel

#undef TGS4_TOPIC_COMMAND
#undef TGS4_TOPIC_TOKEN
#undef TGS4_TOPIC_SUCCESS
#undef TGS4_TOPIC_SWAP
#undef TGS4_TOPIC_SWAP_DELAYED
#undef TGS4_TOPIC_CHAT_COMMAND
#undef TGS4_TOPIC_EVENT

#undef TGS4_COMM_SERVER_PRIMED
#undef TGS4_COMM_SERVER_REBOOT
#undef TGS4_COMM_END_PROCESS
#undef TGS4_COMM_CHAT

#undef TGS4_COMM_VALIDATE

/*
The MIT License

Copyright (c) 2017 Jordan Brown

Permission is hereby granted, free of charge,
to any person obtaining a copy of this software and
associated documentation files (the "Software"), to
deal in the Software without restriction, including
without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom
the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice
shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/