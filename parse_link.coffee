# Parse a server name and group code from a group link
module.exports = (link) ->
	# Input format: tagpro-pi.koalabeast.com/group/aaaaaaaa
	link = link.toLowerCase()

	{
		serverName: link[7...link.indexOf(".koalabeast")]
		groupCode: link[-8..]
	}