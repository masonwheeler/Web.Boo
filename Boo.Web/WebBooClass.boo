namespace Boo.Web

import System
import System.Net

class WebBooClass:

	public static final EXE_DIR = System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetEntryAssembly().Location)

	protected static _templateDict as System.Collections.Generic.Dictionary[of string, Func[of WebBooTemplate]]

	[Getter(Request)]
	private _request as HttpListenerRequest

	[Getter(Response)]
	private _response as HttpListenerResponse

	[Getter(SessionData)]
	private _session as Session

	def constructor(context as System.Net.HttpListenerContext, session as Session):
		_request = context.Request
		_response = context.Response
		_session = session
	
	virtual public def Get() as ResponseData:
		raise System.IO.FileNotFoundException()

	virtual public def Get(values as System.Collections.Generic.IDictionary[of string, string]) as ResponseData:
		return Get()

	virtual public def Get(value as string) as ResponseData:
		return Get()
		
	virtual public def Get(values as string*) as ResponseData:
		return Get()

	virtual public def Post(values as System.Collections.Generic.IDictionary[of string, string]) as ResponseData:
		return Get()

	abstract protected internal def _DispatchGet_(path as string) as ResponseData:
		pass
	
	virtual protected internal def _DispatchPost_(path as string) as ResponseData:
		return Post(ParsePostData())
	
	protected def ParseQueryString() as System.Collections.Generic.IDictionary[of string, string]:
		var result = System.Collections.Generic.Dictionary[of string, string]()
		for key in Request.QueryString.AllKeys:
			result[key] = Request.QueryString[key]
		return result

	protected def ParsePostData() as System.Collections.Generic.IDictionary[of string, string]:
		var parser = HttpUtils.HttpContentParser(Request.InputStream)
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
		else: return null

	protected static def AddTemplateType(cls as Type):
		assert cls.BaseType == WebBooTemplate
		_templateDict.Add(cls.Name, {return Activator.CreateInstance(cls) cast WebBooTemplate})

	protected static def LoadTemplates(searchPath as string, mask as string, *imports as (string)):
		var tc = Boo.Lang.Useful.BooTemplate.TemplateCompiler()
		tc.TemplateBaseClass = WebBooTemplate
		tc.DefaultImports.AddRange(imports)
		tc.DefaultImports.Add('Boo.Web')
		var folder = System.IO.Path.Combine(EXE_DIR, 'templates', searchPath)
		_templateDict = System.Collections.Generic.Dictionary[of string, System.Func[of Boo.Web.WebBooTemplate]]()
		for template in System.IO.Directory.EnumerateFiles(folder, mask):
			var filename = System.IO.Path.GetFileNameWithoutExtension(template)
			tc.TemplateClassName = filename
			var cu = tc.CompileFile(template)
			if cu.Errors.Count > 0:
				raise cu.Errors.ToString()
			AddTemplateType(cu.GeneratedAssembly.GetType(filename))
