colors = require "colors"
cookie = require "cookie"
http   = require "http"
io     = require "socket.io-client"
_      = require "lodash"
parse_l= require "./parse_link"

# Grab a session cookie from the specified server
get_cookie = (serverName, callback) ->
	(http.get "http://tagpro-#{serverName}.koalabeast.com/", (res) ->
		if "set-cookie" of res.headers
			cookies = cookie.parse(res.headers["set-cookie"][0])
			
			if "tagpro" of cookies
				callback null, cookies.tagpro
				
			else callback "Server #{serverName} sent no session cookie"
		else callback "Server #{serverName} sent no cookies"
	).on "error", (e) ->
		callback e.code

check_page = (serverName, groupCode, sessionID, callback) ->
	req = http.get
		hostname: "tagpro-#{serverName}.koalabeast.com"
		path: "/groups/#{groupCode}/"
		headers: Cookie: cookie.serialize("tagpro", sessionID)
	, (res) -> callback(null, res.statusCode is 200)
	
	req.on "error", -> callback("Error checking group page!")

leave_group = (serverName, sessionID) ->
	req = http.get
		hostname: "tagpro-#{serverName}.koalabeast.com",
		path: "/groups/leave/"
		headers:
			Cookie: cookie.serialize("tagpro", sessionID)

	, (res) ->

	req.on "error", (e) ->
		callback e.code

callback = _.once (err, result) ->
	process.send
		err: err
		result: result


link_parts = parse_l process.argv[2]

get_cookie link_parts.serverName, (err, sessionID) -> # Grab session cookie
	if err then return callback err
	check_page link_parts.serverName, link_parts.groupCode, sessionID, (err, exists) ->
		if err then return callback err

		if process.argv[3] is "false" or exists is false
			callback null, exists: exists
		else
			socket_url = "http://tagpro-#{link_parts.serverName}.koalabeast.com:81/groups/#{link_parts.groupCode}"
			socket = io.connect socket_url,
				cookie: cookie.serialize("tagpro", sessionID)

			is_connected = false
			is_full = false

			setTimeout ->
				unless is_connected
					socket.disconnect()
					callback "Couldn't connect to group"
			, 3000

			members = {}
			myID = ""

			socket.on "connect", ->
				is_connected = true

				socket.emit "touch", "page"

				setTimeout ->
					return if is_full

					counts = _(members).countBy((is_spec, id) ->
						return "self"      if id is myID
						return "spectator" if is_spec
						return "player"
					).pick((count, type) -> type isnt "self")
					.value()

					counts.exists = true

					socket.disconnect()
					leave_group link_parts.serverName, sessionID
					callback null, counts

				, 2000

			socket.on "member", (info) ->
				members[info.id or "?"] = info.spectator

			socket.on "full", ->
				is_full = true
				callback null, {player: 8, spectator: 4}

				socket.disconnect()
				leave_group link_parts.serverName, sessionID

			socket.on "you", (id) -> myID    = id
			socket.on "error",    -> callback "Couldn't connect to group"