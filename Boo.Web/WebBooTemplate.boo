namespace Boo.Web

import System
import System.Net

class WebBooTemplate(Boo.Lang.Useful.BooTemplate.ITemplate):
	[Property(Output)]
	_output as System.IO.TextWriter = System.IO.StringWriter()

	[Getter(Request)]
	private _request as HttpListenerRequest

	[Getter(Response)]
	private _response as HttpListenerResponse

	[Getter(Query)]
	private _query as System.Collections.Generic.IDictionary[of string, string]

	[Property(Result)]
	private _result as ResponseData

	internal def Process(request as HttpListenerRequest, response as HttpListenerResponse,
			query as System.Collections.Generic.IDictionary[of string, string]) as ResponseData:
		_request = request
		_response = response
		_query = query
		Execute()
		return (_result if _result is not null else Output.ToString())

	abstract def Execute():
		pass
