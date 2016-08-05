namespace HelloWorld

import Boo.Web

[WebBoo('/', Regex: /(.*)/)]
class Hello:
	def Get():
		return Get('World')

	def Get(name as string):
		return "Hello, $(name)!"

Application('http://localhost:2468/').Run()
