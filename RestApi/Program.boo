namespace RestApi

import Boo.Web

[WebBoo('/')]
class Index:
	def Get():
		return ('Hello, World!')

Application('http://localhost:5000/').Run()
