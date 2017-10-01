﻿namespace Boo.Web

import System
import System.Collections.Generic
import System.IO
import System.Linq.Enumerable
import System.Net

internal interface IDispatcher:
	def Register(paths as (string), loader as Func[of HttpListenerContext, Session, WebBooClass])
	
	def Dispatch(paths as (string), context as HttpListenerContext, s as Session, ref result as ResponseData) as bool

class Application:
	
	[Property(SessionStore)]
	private _sessionStore as Store

	[Property(SessionInitializer)]
	private _sessionInitializer as Action[of Session]

	private class SubpathDispatcher(IDispatcher):
		private _pathMap = Dictionary[of string, IDispatcher]()
		
		def Register(subpaths as (string), loader as Func[of HttpListenerContext, Session, WebBooClass]):
			if subpaths.Length > 1:
				dispatcher as IDispatcher
				unless _pathMap.TryGetValue(subpaths[0], dispatcher):
					dispatcher = SubpathDispatcher()
					_pathMap[subpaths[0]] = dispatcher
				dispatcher.Register(subpaths[1:], loader)
			else:
				assert not _pathMap.ContainsKey(subpaths[0])
				_pathMap[subpaths[0]] = RequestDispatcher(loader)
		
		def Dispatch(paths as (string), context as HttpListenerContext, s as Session, ref result as ResponseData) as bool:
			return false if paths.Length == 0
			dispatcher as IDispatcher
			return false unless _pathMap.TryGetValue(paths[0], dispatcher)
			return dispatcher.Dispatch(paths[1:], context, s, result)
		
	private class RequestDispatcher(SubpathDispatcher, IDispatcher):
		_loader as Func[of HttpListenerContext, Session, WebBooClass]
		
		def constructor(loader as Func[of HttpListenerContext, Session, WebBooClass]):
			_loader = loader
		
		def Dispatch(paths as (string), context as HttpListenerContext, s as Session, ref result as ResponseData) as bool:
			var worked = false
			if paths.Length > 0:
				worked = super(paths, context, s, result)
				return true if worked
			var handler = _loader(context, s)
			if context.Request.HttpMethod == 'GET':
				result = handler._DispatchGet_(string.Join('/', paths))
				return true
			elif context.Request.HttpMethod == 'POST':
				result = handler._DispatchPost_(string.Join('/', paths))
				return true
			elif context.Request.HttpMethod == 'PUT':
				result = handler._DispatchPut_(string.Join('/', paths))
				return true
			elif context.Request.HttpMethod == 'DELETE':
				result = handler._DispatchDelete_(string.Join('/', paths))
				return true
			return false

	static _dispatcher = SubpathDispatcher()
	
	static _paths = Dictionary[of string, Func[of HttpListenerContext, Session, WebBooClass]]()
	
	static def RegisterWebBooClass([Required] path as string, [Required] loader as Func[of HttpListenerContext, Session, WebBooClass]):
		if path.EndsWith('/'):
			path = path[:-1]
		
		_paths.Add(path, loader)

	static _errorHandlers = Dictionary[of int, Func[of int, HttpListenerRequest, ResponseData]]()

	static def RegisterErrorHandler(code as int, [Required] handler as Func[of int, HttpListenerRequest, ResponseData]):
		if _errorHandlers.ContainsKey(code):
			raise ArgumentException("Attempted to register error handler code $code multiple times")
		_errorHandlers.Add(code, handler)

	static def LoadPaths():
		for pair in _paths.OrderBy({kv | kv.Key.Length}):
			var subpaths = ( ('',) if pair.Key == '' else pair.Key.Split(*(char('/'),)) )
			_dispatcher.Register(subpaths, pair.Value)
	
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
		elif result.IsDone:
			pass
		else: assert false, 'Unknown response type'
	
	private def DispatchData(paths as (string), context as HttpListenerContext, ref result as ResponseData) as bool:
		if _sessionStore is not null:
			return Session.WithSession(context.Request, context.Response, _sessionStore, _sessionInitializer, result) do (s as Session,
					ref result as ResponseData) as bool:
				return _dispatcher.Dispatch(paths, context, s, result)
		else:
			return _dispatcher.Dispatch(paths, context, null, result)

	private def RunErrorHandler(context as HttpListenerContext, code as int):
		var result = _errorHandlers[code](code, context.Request)
		HandleResponse(result, context.Response)

	private def SendError(context as HttpListenerContext, code as int):
		if _errorHandlers.ContainsKey(code):
			RunErrorHandler(context, code)
			return
		
		message as string
		if code == 404:
			message = 'Not found'
		elif code == 500:
			message = 'Internal Server Error'
		message = "$code $message"
		context.Response.StatusCode = code
		using writer = System.IO.StreamWriter(context.Response.OutputStream):
				writer.Write(message)

	public def Run():
		listener = System.Net.HttpListener()
		for prefix in _prefixes:
			listener.Prefixes.Add(prefix)
		listener.Start()
		LoadPaths()
		while true:
			var context = listener.GetContext()
			try:
				var request = context.Request
				result as ResponseData
				var url = request.RawUrl.Split(*(char('?'),))[0]
				var paths = url.Split(*(char('/'),))
				paths = paths[:-1] if paths[paths.Length - 1] == ''
				if DispatchData(paths, context, result):
					if result is not null:
						HandleResponse(result, context.Response)
			except as FileNotFoundException:
				SendError(context, 404)
			except as DirectoryNotFoundException:
				SendError(context, 404)
			except a as AbortException:
				SendError(context, a.Code)
			except x as Exception:
				SendError(context, 500)
				print x
			context.Response.OutputStream.Close()
