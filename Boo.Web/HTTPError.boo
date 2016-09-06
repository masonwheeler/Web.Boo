namespace Boo.Web

import System
import System.Collections.Generic

class HttpError(Exception):
	[Getter(Headers)]
	_headers as IDictionary[of string, string]
	
	[Getter(HttpData)]
	_data as string
	
	public def constructor(status as string, headers as IDictionary[of string, string], data as string):
		super(status)
		_headers = headers
		_data = data
