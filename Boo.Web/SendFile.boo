namespace Boo.Web

import System
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast

[Meta]
def SendFile(filename as Expression) as Expression:
	return [|System.IO.FileStream(System.IO.Path.Combine(EXE_DIR, 'www', StripLeadingSlash($filename)), System.IO.FileMode.Open)|]

def StripLeadingSlash(filename as string) as string:
	if filename.StartsWith('/') or filename.StartsWith('\\'):
		return filename[1:]
	return filename