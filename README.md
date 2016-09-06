# Web.Boo
#### A simple framework inspired by web.py to design web apps with a minimum of effort, using Boo's metaprogramming
Probably the absolute simplest framework around for building an HTTP server is [web.py](http://webpy.org) for Python.  Unfortunately, it comes with all of Python's baggage: dynamic typing, GIL-inhibited multithreading, slow performance, etc.

Web.Boo is an attempt to recreate the same basic simplicity of implementation, using Boo's metaprogramming facilities.

### The WebBoo attribute
You can create a server page by writing a class and tagging it with the `WebBoo` attribute, which will rewrite the class under the hood to respond to Web requests, and automatically register the class with the Web.Boo server.  Methods named `Get` and `Post` on such a class will respond to HTTP GET and POST requests, respectively.

The WebBoo attribute constructor takes a string, defining the path the class will respond to requests for.  You can add an optional regex to capture further path data and pass it to a Get overload taking arguments.

```
[WebBoo('/', Regex: /(.*)/)]
class Hello:
	def Get(): //default GET handler
		return Get('World')

	def Get(name as string): //responds to a single regex match
		return "Hello, $(name)!"
```

The following signatures are also valid:

```
def Get(values as string*): //responds to multiple regex matches
def Get(values as IDictionary[of string, string]): //responds to a query string
def Post(values as IDictionary[of string, string]): //responds to a POST message, with form data or query string data passed in
```

All `WebBoo`-annotated classes have access to the following properties:

* `Request`: the original [`HttpListenerRequest` object](https://msdn.microsoft.com/en-us/library/system.net.httplistenerrequest(v=vs.110).aspx) representing the web request
* `Response`: the [`HttpListenerResponse` object](https://msdn.microsoft.com/en-us/library/system.net.httplistenerresponse(v=vs.110).aspx) representing the response to the web request
* `SessionData`: an object containing session data that gets persisted between HTTP requests

### Flexible responses
The supported signatures have no return value, because a `Web.Boo` handler can return many different valid types of responses.  Whether you return a `string`, a `Stream`, a `Newtonsoft.Json` object, or a `Redirect`, `Web.Boo` will accept it (while maintaining static type safety) and handle the web response appropriately.

### File server
Most web applications, no matter how dynamic their content, have some need to serve static files, such as images and scripts.  To enable this, simply use the `FileServer` property on the `WebBoo` attribute:

    [WebBoo('/', FileServer: true)]

This will rewrite the class to automatically serve the requested file.  The server will treat the `www` subfolder of the folder containing the server application as the root directory for static content.

### Hierarchical paths
If you place a `FileServer` class on the root directory, which is useful because most modern browsers will automatically ask for `/favicon.ico`, there's no need to worry that it will block other classes registered to more specific paths.  The server's dispatching mechanism automatically matches an incoming request against registered paths from the most specific to the most general.

### Templating
The Boo.Lang.Useful.BooTemplate namespace contains a templating system that allows you to build code templates.  The basic content of the template will be printed directly to output, while anything between `<%` and `%>` tags will be interpreted as Boo code.  (Due to the nonstandard formatting of such templates, the template compiler runs in whitespace-agnostic mode.)  `Web.Boo` can take advantage of this, allowing you to use prebuilt HTML templates and fill in data from a web request, by setting the `TemplateServer` property on the `WebBoo` attribute.  This property defines a filter, showing which templates this path will respond to:

    [WebBoo('/', TemplateServer: '/*.boo')]

Similar to the `FileServer` property, the server will treat the `templates` subfolder of the folder containing the server application as the root directory for template files.  The template code has access to the same `Request`, `Response`, and `Session` properties as normal `WebBoo`-annotated classes, plus a `Query` dictionary and a property called `Result` that can hold any return value that a normal handler method can return.  (If a template assigns a non-null value to `Result`, the normal output of the template will be ignored in favor of the `Result` value.)  It also contains a `TextWriter` property called `Output` which code within the template can write to.

### Session support
If the `Application.SessionStore` property is set, it will create a `Session` object for each web request, persisted to the client via a cookie and persisted on the server side via the storage method defined by the `SessionStore`.  The default method is the `DiskStore` class, which stores session data to disk, but it's possible to create custom session persistence, for example to store session data in a database, by defining a class that inherits from `Boo.Web.Store` and implements the `Contains`, `Cleanup`, and `Remove` methods, and the `self[key as string]` property.

If no `SessionStore` property is set, the `Session` property in `WebBoo`-annotated classes will be `null`.

If the `SessionStore` property is set, it's also possible to assign an `Action[of Session]` function to `Application.SessionInitializer` which will be run for all newly-created sessions (ie. the first time a user visits the site) to initialize it with default data.

### Feedback welcome
Boo.Web requires an up-to-date Boo compiler to build, as it uses the new `initialization` macro under the hood.  Feel free to try it out, and to share any issues or potential improvements you come up with!

### TODO:
Web socket support. (Requires async/await support in the compiler.)
