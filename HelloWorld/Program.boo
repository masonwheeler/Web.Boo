namespace HelloWorld

import Boo.Web

[WebBoo('/')]
class Hello:
	def Get():
		return 'Hello World!'

[WebBoo("/$name/")]
class HelloName:
	def Get(name as string):
		return "Hello, $(name)!"

Application('http://localhost:2468/').Run()
