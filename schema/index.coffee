protobuf = require "protobuf"
fs       = require "fs"

module.exports = schema = new protobuf.Schema(fs.readFileSync("#{__dirname}/mumble.desc"))

schema.mtypeN = {
	0: "Version",           1: "UDPTunnel",            2: "Authenticate",
	3: "Ping",              4: "Reject",               5: "ServerSync",
	6: "ChannelRemove",     7: "ChannelState",         8: "UserRemove",
	9: "UserState",         10: "BanList",             11: "TextMessage",
	12: "PermissionDenied", 13: "ACL",                 14: "QueryUsers",
	15: "CryptSetup",       16: "ContextActionModify", 17: "ContextAction",
	18: "UserList",         19: "VoiceTarget",         20: "PermissionQuery",
	21: "CodecVersion",     22: "UserStats",           23: "RequestBlob",
	24: "ServerConfig",     25: "SuggestConfig"
}

schema.mtype = {
	"Version": 0,           "UDPTunnel": 1,            "Authenticate": 2,
	"Ping": 3,              "Reject": 4,               "ServerSync": 5,
	"ChannelRemove": 6,     "ChannelState": 7,         "UserRemove": 8,
	"UserState": 9,         "BanList": 10,             "TextMessage": 11,
	"PermissionDenied": 12, "ACL": 13,                 "QueryUsers": 14,
	"CryptSetup": 15,       "ContextActionModify": 16, "ContextAction": 17,
	"UserList": 18,         "VoiceTarget": 19,         "PermissionQuery": 20,
	"CodecVersion": 21,     "UserStats": 22,           "RequestBlob": 23,
	"ServerConfig": 24,     "SuggestConfig": 25
}

schema.byType = (typenum) ->
	schema["MumbleProto.#{schema.mtypeN[typenum]}"]
