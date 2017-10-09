namespace Boo.Web

import System
import System.IO
import System.IO.Compression
import System.Linq.Enumerable
import System.Net

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

	protected def ParseQueryString() as System.Collections.Generic.IDictionary[of string, string]:
		var result = System.Collections.Generic.Dictionary[of string, string]()
		for key in Request.QueryString.AllKeys:
			result[key] = Request.QueryString[key]
		return result

	protected def JsonData() as Newtonsoft.Json.Linq.JToken:
		if Request.ContentType == 'application/json' and _input is not null:
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
		var parser = HttpUtils.HttpContentParser(_input)
		if parser.Success:
			return parser.Parameters
		return ParseQueryString()
		//no support for multipart yet
		//parser is available at HttpUtils.HttpMultipartParser, but implementing it will
		//take a bit of work

	protected def ProcessTemplate(path as string) as ResponseData:
		
		creator as Func[of WebBooTemplate]
		if _templateDict.TryGetValue(path, creator):
			var template = creator()
			return template.Process(_request, _response, _session, self.ParsePostData())
		elif path.Contains('/'):
			var paths = path.Split(*(char('/'),))
			path = paths[0]
			paths = paths[1:]
			if _templateDict.TryGetValue(path, creator):
				template = creator()
				var pd = self.ParsePostData()
				for i in range(paths.Length):
					var name = '?p' + (i + 1).ToString()
					pd[name] = paths[i]
				return template.Process(_request, _response, _session, pd)
		return null

	protected static def AddTemplateType(cls as Type):
		assert cls.IsSubclassOf(WebBooTemplate)
		_templateDict.Add(cls.Name, {return Activator.CreateInstance(cls) cast WebBooTemplate})

	protected static def LoadTemplates(searchPath as string, mask as string, *imports as (string)):
		LoadTemplates(searchPath, mask, WebBooTemplate, *imports)

	protected static def LoadTemplates(searchPath as string, mask as string, templateClass as Type, *imports as (string)):
		assert templateClass == WebBooTemplate or templateClass.IsSubclassOf(WebBooTemplate)
		var tc = Boo.Lang.Useful.BooTemplate.TemplateCompiler()
		tc.TemplateBaseClass = templateClass
		tc.DefaultImports.AddRange(imports)
		tc.DefaultImports.Add('Boo.Web')
		
		if templateClass.CustomAttributes.Any({ca | ca.AttributeType == ExecuteProvidedAttribute}):
			tc.AddExecute =  false
		var folder = Path.Combine(EXE_DIR, 'templates', searchPath)
		for template in Directory.EnumerateFiles(folder, mask):
			var filename = Path.GetFileNameWithoutExtension(template)
			tc.TemplateClassName = filename
			var cu = tc.CompileFile(template)
			if cu.Errors.Count > 0:
				raise cu.Errors.ToString()
			AddTemplateType(cu.GeneratedAssembly.GetType(filename))

	protected def SendFile(filename as string) as ResponseData:
		Response.ContentType = MimeTypes.MimeTypeMap.GetMimeType(Path.GetExtension(filename))
		Response.AppendHeader('Cache-Control', 'max-age=86400') //cache for a day
		var path = System.IO.Path.Combine(EXE_DIR, 'www', StripLeadingSlash(filename))
		var tagHash = File.GetLastWriteTimeUtc(path).GetHashCode().ToString()
		Response.AppendHeader('ETag', tagHash)
		var etag = _request.Headers['If-None-Match']
		if etag?.Equals(tagHash):
			return Redirect(304)
		result as Stream = System.IO.FileStream(path, System.IO.FileMode.Open)
		var gzip = _request.Headers['Accept-Encoding']?.Contains('gzip')
		if gzip and result.Length > 1400:
			using gStream = GZipStream(Response.OutputStream, CompressionMode.Compress, true):
				Response.AppendHeader('Content-Encoding', 'gzip')
				result.CopyTo(gStream)
				result.Dispose()
				return ResponseData.Done
		return result


	internal static def StripLeadingSlash(filename as string) as string:
		if filename.StartsWith('/') or filename.StartsWith('\\'):
			return filename[1:]
		return filename