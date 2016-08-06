namespace Boo.Web

import System
import System.Net

class WebBooClass:
	
	protected static final EXE_DIR = System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetEntryAssembly().Location)
	
	[Getter(Request)]
	private _request as HttpListenerRequest
	
	def constructor(context as System.Net.HttpListenerRequest):
		_request = context
	
	virtual public def Get() as ResponseData:
		raise System.IO.FileNotFoundException()

	virtual public def Get(values as System.Collections.Generic.IDictionary[of string, string]) as ResponseData:
		return Get()

	virtual public def Get(value as string) as ResponseData:
		return Get()
		
	virtual public def Get(values as string*) as ResponseData:
		return Get()

	abstract protected internal def _DispatchGet_(path as string) as ResponseData:
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
