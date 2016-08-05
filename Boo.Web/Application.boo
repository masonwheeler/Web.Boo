namespace Boo.Web

import System
import System.Collections.Generic
import System.Net

internal interface IDispatcher:
	def Register(paths as (string), loader as Func[of HttpListenerRequest, WebBooClass])
	
	def Dispatch(paths as (string), request as HttpListenerRequest, ref result as string) as bool

class Application:
	
	private class SubpathDispatcher(IDispatcher):
		private _pathMap = Dictionary[of string, IDispatcher]()
		
		def Register(subpaths as (string), loader as Func[of HttpListenerRequest, WebBooClass]):
			if subpaths.Length > 1:
				dispatcher as IDispatcher
				unless _pathMap.TryGetValue(subpaths[0], dispatcher):
					dispatcher = SubpathDispatcher()
					_pathMap[subpaths[0]] = dispatcher
				dispatcher.Register(subpaths[1:], loader)
			else:
				_pathMap[subpaths[0]] = RequestDispatcher(loader)
		
		def Dispatch(paths as (string), request as HttpListenerRequest, ref result as string) as bool:
			return false if paths.Length == 0
			dispatcher as IDispatcher
			return false unless _pathMap.TryGetValue(paths[0], dispatcher)
			return dispatcher.Dispatch(paths[1:], request, result)
	
	private class RequestDispatcher(SubpathDispatcher, IDispatcher):
		_loader as Func[of HttpListenerRequest, WebBooClass]
		
		def constructor(loader as Func[of HttpListenerRequest, WebBooClass]):
			_loader = loader
		
		def Dispatch(paths as (string), request as HttpListenerRequest, ref result as string) as bool:
			var worked = false
			if paths.Length > 0:
				worked = super(paths, request, result)
				return true if worked
			var handler = _loader(request)
			if request.HttpMethod == 'GET':
				result = handler._DispatchGet_(string.Join('/', paths))
				return true
			return false

	static _dispatcher = SubpathDispatcher()
	
	static def RegisterWebBooClass([Required] path as string, [Required] loader as Func[of HttpListenerRequest, WebBooClass]):
		if path.EndsWith('/'):
			path = path[:-1]
		
		var subpaths = ( ('',) if path == '' else path.Split(*(char('/'),)) )
		subpaths[subpaths.Length - 1] += '/'
		_dispatcher.Register(subpaths, loader)
	
	_prefixes as (string)
	
	public def constructor([Required] *prefixes as (string)):
		raise "Application requires at least one prefix to run" if prefixes.Length == 0
	
	public def Run():
			listener = System.Net.HttpListener()
			for prefix in _prefixes:
				listener.Prefixes.Add(prefix)
			var context = listener.GetContext()
			var request = context.Request
			result as string
			if _dispatcher.Dispatch(request.RawUrl.Split(*(char('/'),)), request, result):
				using writer = System.IO.StringWriter(context.Response.OutputStream):
					writer.Write(result)
				context.Response.OutputStream.Close()
