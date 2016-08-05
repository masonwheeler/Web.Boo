namespace Boo.Web

import System
import System.Net

class WebBooClass:
	[Getter(Request)]
	private _request as HttpListenerRequest
	
	def constructor(context as System.Net.HttpListenerRequest):
		_request = context
	
	virtual public def Get() as string:
		raise System.IO.FileNotFoundException()

	virtual public def Get(values as System.Collections.Generic.IDictionary[of string, string]) as string:
		return Get()

	virtual public def Get(value as string) as string:
		return Get()
		
	virtual public def Get(values as string*) as string:
		return Get()

	abstract protected internal def _DispatchGet_(path as string) as string:
		pass
	
	protected def ParseQueryString(query as string) as System.Collections.Generic.IDictionary[of string, string]:
		var pairs = query.Split(*(char('&'),))
		var result = System.Collections.Generic.Dictionary[of string, string]()
		for pair in pairs:
			try:
				key as string, value as string = pair.Split(*(char('='),))
				result[key] = value
			except as IndexOutOfRangeException:
				pass
		return result