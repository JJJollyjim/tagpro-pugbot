childps  = require "child_process"
moment   = require "moment"
colors   = require "colors"
Redis    = require "redis"
async    = require "async"
_        = require "lodash"

{mtypeN} = require "./schema"
{mtype}  = require "./schema"
connect  = require "./connect"
parse_l  = require "./parse_link"

redis    = Redis.createClient()

firstUpperCase = (str) ->
	str[0].toUpperCase() + str[1..].toLowerCase()

module.exports = class Bot
	session: null

	constructor: (host, @username, @channel) ->
		[@server, @port] = host.split(":")

	connect: ->
		channelTree = {}
		channelNames = {}
		users = {}

		findChannelByPath = (path, root=channelTree) ->
			# Path format: ["Pugs", "Pug 1", "Red"]
			# Calls next level with ["Pug 1", "Red"]
			# Then ["Red"]

			# Iterate this level
			for cid, children of root
				# If this level matches here
				if channelNames[cid] is path[0]
					# If the path ends here return this one
					return cid if path.length is 1

					# Otherwise, if it has children...
					if Object.keys(children).length > 0
						# Check its children
						sub = findChannelByPath(path[1..], children)
						return sub if sub isnt null

			# Return null if nothing found
			return null

		sendMsg = connect @server, @port, @username, (type, data) =>
			# Debug logging
			# console.log(mtypeN[type].blue, data) if type of mtypeN

			switch type # Handle various standard events that only require logging
				when "Connect"    then console.log "[#{@username}]".magenta + " Connected to server!".green
				when "Disconnect" then console.log "[#{@username}]".magenta + " Disconnected from server!".red
				when "Error"      then console.log "[#{@username}]".magenta + " Error connecting to server!".redBG
				when mtype.Reject then console.log "[#{@username}]".magenta + " Couldn't connect to server! #{data.reason}".redBG


			switch type # Handle mumble events that need special code
				when mtype.ServerSync # When the server has sent its initial data to the client
					@session = data.session

					@channelID = findChannelByPath(@channel.split("->"))
					if @channelID is null
						throw new Error("[#{@username}] Couldn't find the specified channel!".redBG)

					sendMsg mtype.UserState,
						session: @session
						channelId: @channelID
						selfMute: true
						selfDeaf: true


				when mtype.TextMessage # When the client receives a chat message
					if data.channelId? # Not a DM
						if data.channelId[0].toString() is @channelID
							URLs = /tagpro-[a-z]+\.koalabeast\.com\/groups\/[a-z]{8}/i.exec(data.message)

							# If any URLs are matched in the message
							if URLs isnt null
								# Get the current URL
								redis.hget "urls", @channel, (err, url) =>
									return if err # <-- Fantastic error handling
									# And make sure it isn't what's just been posted
									return if url is URLs[0]

									sendMsg mtype.TextMessage,
										message: "Checking group…"
										session: [ data.actor ]

									child = childps.fork "./group_probe.coffee", [URLs[0], false],
										execPath: "/usr/local/bin/coffee"

									child.on "message", (msg) =>
										if msg.err
											console.log("Error in group_probe: #{msg.err}".yellow)
											console.log("Link: #{URLs[0]}".yellow)

											sendMsg mtype.TextMessage,
												message: "<font color=\"red\">Uh oh, a problem occoured checking that group link!</font>"
												channelId: [ @channelID ]
										else if msg.result.exists is true
											console.log "[#{@username}]".magenta + " Storing new group link: '#{URLs[0]}' (from user '#{users[data.actor].name}')".blue
											sendMsg mtype.TextMessage,
												message: "Group stored! Thanks #{users[data.actor].name}!"
												channelId: [ @channelID ]

											redis.hset  "urls", @channel, URLs[0]
											redis.hset "names", @channel, users[data.actor].name
											redis.hset "times", @channel, moment().unix()
										else if msg.result.exists is false
											sendMsg mtype.TextMessage,
												message: "<font color=\"red\">The linked group appears not to exist!</font>"
												channelId: [ @channelID ]
										else
											console.log "Not sure what to do with this message!".redBG, msg

									child.on "error", ->
										console.log "Child process failed!".redBG, arguments


				when mtype.UserState # When a user's state is sent or updated
					users[data.session] = {} unless users[data.session]?

					if data.name?      then users[data.session].name = data.name
					if data.channelId? then users[data.session].chan = data.channelId

					if data.channelId? and data.actor isnt @session and data.channelId.toString() is @channelID
						# A user has moved into my channel!
						
						channelPath = @channel

						async.parallel
							url:  (cb) -> redis.hget "urls",  channelPath, cb
							name: (cb) -> redis.hget "names", channelPath, cb
							time: (cb) -> redis.hget "times", channelPath, cb
							(err, res) =>
								if err then console.log "[#{@username}]".magneta + " Error getting link!".red, err

								if _.all( res, (x) -> x? ) # If none of the requests returned null
									link_parts = parse_l res.url

									child = childps.fork "./group_probe.coffee", [res.url, false],
										execPath: "/usr/local/bin/coffee"

									doneNGL = false

									child.on "message", (msg) =>
										if msg.result.exists is false
											redis.hdel "urls",  @channel
											redis.hdel "names", @channel
											redis.hdel "times", @channel

											sendMsg mtype.TextMessage,
												message: "No group link found for this channel"
												session: [ data.actor ]

											doneNGL = true


									child.on "error", -> console.error(arguments)

									async.parallel
										players:    (cb) -> redis.get "num:players:#{res.url}"   , cb
										spectators: (cb) -> redis.get "num:spectators:#{res.url}", cb
									, (err, nums) =>
										unless nums.players? and nums.spectators?
											child = childps.fork "./group_probe.coffee", [res.url, true],
												execPath: "/usr/local/bin/coffee"

											child.on "message", (msg) =>
												unless msg.err
													if msg.result.exists is true
														if not msg.result.player?    then msg.result.player    = 0
														if not msg.result.spectator? then msg.result.spectator = 0
														redis.setex "num:players:#{res.url}",    60, msg.result.player
														redis.setex "num:spectators:#{res.url}", 60, msg.result.spectator

														sendMsg mtype.TextMessage,
															message: """<br>
															<a href=\"http://#{res.url}\">Click here to join group</a><br>
															Server: <b>#{firstUpperCase link_parts.serverName}</b>
															<ul>
																<li>Players: <b>#{msg.result.player}</b></li>
																<li>Spectators: <b>#{msg.result.spectator}</b></li>
															</ul>
															<font color='#666666'><i>
																Link posted by <b>#{res.name}</b> #{moment.unix(res.time).fromNow()}
															</i></font>
															"""
															session: [ data.actor ]
													else unless doneNGL
														redis.hdel "urls",  @channel
														redis.hdel "names", @channel
														redis.hdel "times", @channel

														sendMsg mtype.TextMessage,
															message: "No group link found for this channel"
															session: [ data.actor ]
											child.on "error", -> console.error(arguments)
										else
											sendMsg mtype.TextMessage,
												message: """<br>
												<a href=\"http://#{res.url}\">Click here to join group</a><br>
												Server: <b>#{firstUpperCase link_parts.serverName}</b>
												<ul>
													<li>Players: <b>#{nums.players}</b></li>
													<li>Spectators: <b>#{nums.spectators}</b></li>
												</ul>
												<font color='#666666'><i>
													Link posted by <b>#{res.name}</b> #{moment.unix(res.time).fromNow()}
												</i></font>
												"""
												session: [ data.actor ]
								else # Something nulld
									sendMsg mtype.TextMessage,
										message: "No group link found for this channel"
										session: [ data.actor ]


				when mtype.UserRemove # When a user quits
					delete users[data.session]
					
				when mtype.ChannelState # When a channel's state is sent or updated
					# Save the channel name
					channelNames[data.channelId] = data.name

					unless data.channelId is 0 # If not the root channel

						# Recursively find children of a given parent
						findChildren = (id, haystack) ->
							# If this parent is root, return root's children
							return channelTree if id is 0

							# Loop through channels at this level
							for cid, grandchildren of haystack
								# If it's the parent we're looking for...
								if cid is (id.toString())
									# Return it's children
									return grandchildren
								else
									# Otherwise, check out this parent's children
									sub = findChildren(id, grandchildren)
									# If we found the right parent there, return that
									return sub if sub isnt null

							# Return null if this level didn't find anything
							return null

						siblings = findChildren(data.parent, channelTree)
						siblings[data.channelId] = {}
