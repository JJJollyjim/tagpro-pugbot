dgram = require "dgram"

module.exports = (server, port = 64738, callback) ->
	# Create UDP socket
	sock = dgram.createSocket("udp4")

	# Listen for errors
	sock.on "error", (err) ->
		callback(err, null)

	# Send ping packet
	sock.send new Buffer([0,0,0,0,1,2,3,1,0,0,0,0]), 0, 12, port, server

	# Listen for reply
	sock.on "message", (msg, rinfo) ->
		response = 
			version: "#{msg.readInt16BE(0)}.#{msg.readInt8(2)}.#{msg.readInt8(3)}"
			users:
				current: msg.readUInt32BE(12)
				max: msg.readUInt32BE(16)


		callback(null, response)

		sock.close()