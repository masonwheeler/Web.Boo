namespace Templates

import System
import Boo.Web

[WebBoo('/', FileServer: true, TemplateServer: '/*.boo')]
class Homepage:
	pass

Application('http://localhost:2468/').Run()