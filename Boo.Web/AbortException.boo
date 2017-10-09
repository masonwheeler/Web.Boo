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
def Abort(code as IntegerLiteralExpression) as Statement:
	var cv = code.Value
	unless cv >= 400 and cv < 600:
		raise "Abort value must be a valid 4xx or 5xx error code"
	var result = [|raise AbortException($cv)|]
	result.LexicalInfo = code.ParentNode.LexicalInfo
	return result
