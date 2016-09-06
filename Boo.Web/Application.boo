namespace Boo.Web

import System
import System.Collections.Generic
import System.IO
import System.Net

internal interface IDispatcher:
	def Register(paths as (string), loader as Func[of HttpListenerContext, WebBooClass])
	
	def Dispatch(paths as (string), context as HttpListenerContext, ref result as ResponseData) as bool

class Application:
	
	private class SubpathDispatcher(IDispatcher):
		private _pathMap = Dictionary[of string, IDispatcher]()
		
		def Register(subpaths as (string), loader as Func[of HttpListenerContext, WebBooClass]):
			if subpaths.Length > 1:
				dispatcher as IDispatcher
				unless _pathMap.TryGetValue(subpaths[0], dispatcher):
					dispatcher = SubpathDispatcher()
					_pathMap[subpaths[0]] = dispatcher
				dispatcher.Register(subpaths[1:], loader)
			else:
				_pathMap[subpaths[0]] = RequestDispatcher(loader)
		
		def Dispatch(paths as (string), context as HttpListenerContext, ref result as ResponseData) as bool:
			return false if paths.Length == 0
			dispatcher as IDispatcher
			return false unless _pathMap.TryGetValue(paths[0], dispatcher)
			return dispatcher.Dispatch(paths[1:], context, result)
		
	private class RequestDispatcher(SubpathDispatcher, IDispatcher):
		_loader as Func[of HttpListenerContext, WebBooClass]
		
		def constructor(loader as Func[of HttpListenerContext, WebBooClass]):
			_loader = loader
		
		def Dispatch(paths as (string), context as HttpListenerContext, ref result as ResponseData) as bool:
			var worked = false
			if paths.Length > 0:
				worked = super(paths, context, result)
				return true if worked
			var handler = _loader(context)
			if context.Request.HttpMethod == 'GET':
				result = handler._DispatchGet_(string.Join('/', paths))
				return true
			elif context.Request.HttpMethod == 'POST':
				result = handler._DispatchPost_(string.Join('/', paths))
				return true
			return false

	static _dispatcher = SubpathDispatcher()
	
	static def RegisterWebBooClass([Required] path as string, [Required] loader as Func[of HttpListenerContext, WebBooClass]):
		if path.EndsWith('/'):
			path = path[:-1]
		
		var subpaths = ( ('',) if path == '' else path.Split(*(char('/'),)) )
		_dispatcher.Register(subpaths, loader)
	
	_prefixes as (string)
	
	public def constructor([Required] *prefixes as (string)):
		raise "Application requires at least one prefix to run" if prefixes.Length == 0
		_prefixes = prefixes
	
	private def HandleResponse(result as ResponseData, response as HttpListenerResponse):
		if result.AsString is not null:
			using writer = System.IO.StreamWriter(response.OutputStream):
				writer.Write(result.AsString)
		elif result.AsStream is not null:
			result.AsStream.CopyTo(response.OutputStream)
			result.AsStream.Close()
		elif result.AsJson is not null:
			response.ContentType = 'application/json'
			using writer = System.IO.StreamWriter(response.OutputStream):
				writer.Write(result.AsJson.ToString())
		elif result.AsRedirect is not null:
			var red = result.AsRedirect
			response.StatusCode = red.Code
			response.RedirectLocation = red.URL
		else: assert false, 'Unknown response type'
	
	public def Run():
		listener = System.Net.HttpListener()
		for prefix in _prefixes:
			listener.Prefixes.Add(prefix)
		listener.Start()
		while true:
			var context = listener.GetContext()
			try:
				var request = context.Request
				result as ResponseData
				var url = request.RawUrl.Split(*(char('?'),))[0]
				var paths = url.Split(*(char('/'),))
				paths = paths[:-1] if paths[paths.Length - 1] == ''
				if _dispatcher.Dispatch(paths, context, result):
					if result is not null:
						HandleResponse(result, context.Response)
			except:
				context.Response.StatusCode = 500
			context.Response.OutputStream.Close()
