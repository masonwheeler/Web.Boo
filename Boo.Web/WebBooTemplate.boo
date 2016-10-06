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

	[Property(SessionData)]
	private _session as Session

	internal def Process(request as HttpListenerRequest, response as HttpListenerResponse, session as Session,
			query as System.Collections.Generic.IDictionary[of string, string]) as ResponseData:
		_request = request
		_response = response
		_query = query
		_session = session
		Execute()
		return (_result if _result is not null else Output.ToString())

	protected def Print(value as string):
		Output.Write(value)

	abstract def Execute():
		pass
