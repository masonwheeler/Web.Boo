namespace Boo.Web

import System
import Boo.Lang.Compiler.Ast

class AbortException(Exception):
"""Quick way to return an error code"""
	[Getter(Code)]
	_code as int

	public def constructor(code as int):
		super()
		_code = code

[Meta]
def Abort(code as int) as Statement:
	unless a >= 400 and a < 600:
		raise "Abort value must be a valid 4xx or 5xx error code"
	return [|raise AbortException($code)|]
