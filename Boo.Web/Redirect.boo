namespace Boo.Web

import System

class Redirect:
"""Implements a HTTP redirect"""

	[Getter(URL)]
	_url as string

	[Getter(Code)]
	_code as int = 303

	public def constructor(url as string):
		assert not string.IsNullOrWhiteSpace(url)
		_url = url

	public def constructor(url as string, code as int):
		assert not string.IsNullOrWhiteSpace(url)
		assert code in (300, 301, 302, 303, 304, 305, 306, 307, 308)
		_url = url
		_code = code
