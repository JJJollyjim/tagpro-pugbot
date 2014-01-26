colors   = require "colors"

config   = require "./config"
ping     = require "./ping"
Bot      = require "./bot"

pingStart = new Date().getTime()

[server, port] = config.host.split(":")

ping server, port, (err, data) ->
	if err then throw new Error("Error pinging server!")

	pingTime = (new Date().getTime()) - pingStart

	console.log " Server:".grey.bold + " #{server}".grey
	console.log "   Port:".grey.bold + " #{port}".grey
	console.log "  Users:".grey.bold + " #{data.users.current}/#{data.users.max}".grey
	console.log "   Ping:".grey.bold + " #{pingTime}ms".grey
	console.log "Version:".grey.bold + " #{data.version}".grey

	for username, channel of config.bots
		new Bot(config.host, username, channel).connect()