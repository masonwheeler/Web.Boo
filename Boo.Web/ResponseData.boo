namespace Boo.Web

import System
import System.IO
import Newtonsoft.Json.Linq

class ResponseData:
	[Getter(AsString)]
	private _asString as string

	[Getter(AsStream)]
	private _asStream as Stream

	[Getter(AsJson)]
	private _asJson as JToken

	def constructor(value as string):
		_asString = value

	def constructor(value as Stream):
		_asStream = value

	def constructor(value as JToken):
		_asJson = value

	static def op_Implicit(value as string) as ResponseData:
		return ResponseData(value)

	static def op_Implicit(value as Stream) as ResponseData:
		return ResponseData(value)

	static def op_Implicit(value as JToken) as ResponseData:
		return ResponseData(value)