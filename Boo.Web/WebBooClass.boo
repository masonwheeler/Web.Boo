namespace Boo.Web

import System
import System.IO
import System.IO.Compression
import System.Linq.Enumerable
import System.Net

import Boo.Lang.Useful.BooTemplate

class WebBooClass:

	public static final EXE_DIR = Path.GetDirectoryName(System.Reflection.Assembly.GetEntryAssembly().Location)

	protected static _templateDict = System.Collections.Generic.Dictionary[of string, Func[of WebBooTemplate]]()

	[Getter(Request)]
	private _request as HttpListenerRequest

	[Getter(Response)]
	private _response as HttpListenerResponse

	[Getter(SessionData)]
	private _session as Session

	private _input as MemoryStream

	def constructor(context as System.Net.HttpListenerContext, session as Session):
		_request = context.Request
		_response = context.Response
		_session = session

	virtual public def Get() as ResponseData:
		raise FileNotFoundException()

	virtual public def Get(values as System.Collections.Generic.IDictionary[of string, string]) as ResponseData:
		return Get()

	virtual public def Get(value as string) as ResponseData:
		return Get()

	virtual public def Get(values as string*) as ResponseData:
		return Get()

	virtual public def Post(values as System.Collections.Generic.IDictionary[of string, string]) as ResponseData:
		return Get()

	virtual public def Put(values as System.Collections.Generic.IDictionary[of string, string]) as ResponseData:
		return Get()

	virtual public def Delete() as ResponseData:
		return Get()

	abstract protected internal def _DispatchGet_(path as string) as ResponseData:
		pass

	virtual protected internal def _DispatchPost_(path as string) as ResponseData:
		return Post(ParsePostData())

	virtual protected internal def _DispatchPut_(path as string) as ResponseData:
		return Put(ParsePostData())

	virtual protected internal def _DispatchDelete_(path as string) as ResponseData:
		return Delete()

	//with interpolated values:
	virtual protected internal def _DispatchGet_(values as (string)) as ResponseData:
		return null

	virtual protected internal def _DispatchPost_(values as (string)) as ResponseData:
		return null

	virtual protected internal def _DispatchPut_(values as (string)) as ResponseData:
		return null

	virtual protected internal def _DispatchDelete_(values as (string)) as ResponseData:
		return null

	virtual protected internal def Options(path as string) as ResponseData:
		pass

	protected def ParseQueryString() as System.Collections.Generic.IDictionary[of string, string]:
		var result = System.Collections.Generic.Dictionary[of string, string]()
		for key in Request.QueryString.AllKeys:
			result[key] = Request.QueryString[key]
		return result

	protected def RawPostData() as string:
		_input.Position = 0
		using reader = StreamReader(_input):
			return reader.ReadToEnd()

	protected def JsonData() as Newtonsoft.Json.Linq.JToken:
		if (Request.ContentType == 'application/json' or Request.ContentType.StartsWith('application/json;')) and _input is not null:
			_input.Position = 0
			using reader = StreamReader(_input):
				try:
					return Newtonsoft.Json.Linq.JToken.Parse(reader.ReadToEnd())
				except as Newtonsoft.Json.JsonReaderException:
					return null
		return null

	protected def ParsePostData() as System.Collections.Generic.IDictionary[of string, string]:
		_input = MemoryStream()
		Request.InputStream.CopyTo(_input)
		_input.Seek(0, SeekOrigin.Begin)
		if Request.ContentType?.StartsWith("multipart/form-data;"):
			var mParser = HttpUtils.HttpMultipartParser(_input, null)
			if mParser.Success:
				return mParser.Parameters
		else:
			var parser = HttpUtils.HttpContentParser(_input)
			if parser.Success:
				return parser.Parameters
		return ParseQueryString()

	private static def GetTemplateCreator(path as string) as Func[of WebBooTemplate]:
		lock _templateDict:
			creator as Func[of WebBooTemplate] = null
			_templateDict.TryGetValue(path, creator)
			return creator
		
	protected def ProcessTemplate(path as string) as ResponseData:
		creator as Func[of WebBooTemplate] = GetTemplateCreator(path)
		if creator is not null:
			var template = creator()
			return template.Process(_request, _response, _session, self.ParsePostData())
		elif path.Contains('/'):
			var paths = path.Split(*(char('/'),))
			path = paths[0]
			paths = paths[1:]
			creator = GetTemplateCreator(path)
			if creator is not null:
				template = creator()
				var pd = self.ParsePostData()
				for i in range(paths.Length):
					var name = '_p' + (i + 1).ToString()
					pd[name] = paths[i]
				return template.Process(_request, _response, _session, pd)
		return null

	protected static def AddTemplateType(cls as Type):
		assert cls.IsSubclassOf(WebBooTemplate)
		_templateDict[cls.Name] = {return Activator.CreateInstance(cls) cast WebBooTemplate}

	protected static def LoadTemplates(searchPath as string, mask as string, *imports as (string)):
		LoadTemplates(searchPath, mask, WebBooTemplate, *imports)

	// adapted from code found at
	// https://stackoverflow.com/a/1406853/32914
	private static def IsFileReady(filename as string) as bool:
		// If the file can be opened for exclusive access it means that the file
		// is no longer locked by another process.
		try:
			using inputStream = File.Open(filename, FileMode.Open, FileAccess.Read, FileShare.None):
				return inputStream.Length > 0
		except:
			return false

	private static def LoadTemplate(template as string, tc as TemplateCompiler):
		var filename = Path.GetFileNameWithoutExtension(template)
		tc.TemplateClassName = filename
		var cu = tc.CompileFile(template)
		if cu.Errors.Count > 0:
			raise cu.Errors.ToString()
		AddTemplateType(cu.GeneratedAssembly.GetType(filename))

	private static _watcher as FileSystemWatcher
	private static _tc as TemplateCompiler

	protected static def LoadTemplates(searchPath as string, mask as string, templateClass as Type, *imports as (string)):
		assert templateClass == WebBooTemplate or templateClass.IsSubclassOf(WebBooTemplate)
		_tc = TemplateCompiler()
		_tc.TemplateBaseClass = templateClass
		_tc.DefaultImports.AddRange(imports)
		_tc.DefaultImports.Add('Boo.Web')
		
		if templateClass.CustomAttributes.Any({ca | ca.AttributeType == ExecuteProvidedAttribute}):
			_tc.AddExecute =  false
		var folder = Path.Combine(EXE_DIR, 'templates', searchPath)
		lock _templateDict:
			for template in Directory.EnumerateFiles(folder, mask):
				LoadTemplate(template, _tc)
		
		_watcher = FileSystemWatcher(folder, mask)
		//_watcher.NotifyFilter = NotifyFilters.LastAccess | NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.DirectoryName
		_watcher.Changed += TemplateChanged
		_watcher.Created += TemplateChanged
		_watcher.Deleted += TemplateDeleted
		_watcher.Renamed += TemplateRenamed
		_watcher.EnableRaisingEvents = true

	private static def TemplateChanged(sender as object, e as FileSystemEventArgs):
		var filename = e.FullPath
		if IsFileReady(filename):
			lock _templateDict:
				LoadTemplate(filename, _tc)

	private static def TemplateDeleted(source, e as FileSystemEventArgs):
		var filename = Path.GetFileNameWithoutExtension(e.FullPath)
		if _templateDict.ContainsKey(filename):
			lock _templateDict:
				_templateDict.Remove(filename)

	private static def TemplateRenamed(source, e as RenamedEventArgs):
		var filename = Path.GetFileNameWithoutExtension(e.OldFullPath)
		if _templateDict.ContainsKey(filename):
			lock _templateDict:
				_templateDict.Remove(filename)
		TemplateChanged(source, e)

	protected def SendFile(filename as string) as ResponseData:
		var ext = Path.GetExtension(filename)
		Response.ContentType = ('application/wasm' if ext.Equals('.wasm') else MimeTypes.MimeTypeMap.GetMimeType(ext))
		Response.AppendHeader('Cache-Control', 'max-age=86400') //cache for a day
		var path = System.IO.Path.Combine(EXE_DIR, 'www', StripLeadingSlash(filename))
		var tagHash = File.GetLastWriteTimeUtc(path).GetHashCode().ToString()
		Response.AppendHeader('ETag', tagHash)
		var etag = _request.Headers['If-None-Match']
		if etag?.Equals(tagHash):
			return Redirect(304)
		result as Stream = FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)
		var gzip = _request.Headers['Accept-Encoding']?.Contains('gzip')
		if gzip and result.Length > 1400:
			try:
				using gStream = GZipStream(Response.OutputStream, CompressionMode.Compress, true):
					Response.AppendHeader('Content-Encoding', 'gzip')
					result.CopyTo(gStream)
					result.Dispose()
			except as HttpListenerException:
				result.Dispose()
			return ResponseData.Done
		return result


	internal static def StripLeadingSlash(filename as string) as string:
		if filename.StartsWith('/') or filename.StartsWith('\\'):
			return filename[1:]
		return filename