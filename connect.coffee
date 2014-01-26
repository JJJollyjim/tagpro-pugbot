schema = require "./schema"
colors = require "colors"
tls    = require "tls"

mtype  = schema.mtype

process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0"

module.exports = (server, port, username, callback) ->
	sock = tls.connect port, server

	sock.protoWrite = (type, data={}) ->
		sdata = schema.byType(type).serialize data # Serialize data
		buf = new Buffer(6 + sdata.length) # Create message buffer

		buf.writeUInt16BE(type, 0) # Write message type
		buf.writeUInt32BE(sdata.length, 2) # Write serialized data length
		sdata.copy(buf, 6, 0) # Write serialized data to buffer

		sock.write buf

		# console.log("--> #{schema.mtypeN[type]} (#{sdata.length})".blue)

	sock.on "secureConnect", ->
		callback("Connect", {})

		# Send version info
		sock.protoWrite mtype.Version, {
			version: 66052
			release: "1.2.4"
			os: "OSX"
			osVersion: "10.9.0 (i386)"
		}

		# Send username
		sock.protoWrite mtype.Authenticate, {
			username: username
		}

		# Send pings
		setInterval ->
			sock.protoWrite mtype.Ping
		, 15 * 1000 # Every 15 seconds (30 is the DC threshold)

	handleData = (buf) ->
		type = buf.readUInt16BE(0)
		len = buf.readUInt32BE(2)

		msg = buf.slice(6, len+6)

		if type isnt mtype.UDPTunnel
			try
				data = schema.byType(type).parse(msg)
			catch
				console.error("#{x}: #{b}".red) for b,x in buf 
				throw new Error("Couldn't parse message!")


			callback(type, data)
			# console.log "<-- #{schema.mtypeN[type]} (#{len})".yellow

			if buf.length > len+6
				handleData(buf.slice(len+6))

	sock.on "data", (buf) ->
		handleData(buf)

	sock.on "close", ->
		callback("Disconnect", {})

	sock.on "error", ->
		callback("Error", {})

	return sock.protoWrite