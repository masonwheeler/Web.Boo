namespace Boo.Web

import System
import System.IO
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
