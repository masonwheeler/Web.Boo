namespace Boo.Web

import System.Linq.Enumerable
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
import Boo.Lang.Compiler.TypeSystem
import Boo.Lang.Compiler.TypeSystem.Internal
import Boo.Lang.Environments
import Boo.Lang.Compiler.TypeSystem.Services

//based on System.Net.HttpListener
//see also https://bitbucket.org/lorenzopolidori/http-form-parser/src

class WebBooAttribute(AbstractAstAttribute):
	[Getter(Path)]
	private _path as string

	[Property(Regex)]
	private _regex as RELiteralExpression

	[Property(HasQueryString)]
	private _hasQueryString = BoolLiteralExpression(false)

	[Property(FileServer)]
	private _fileServer = BoolLiteralExpression(false)

	[Property(TemplateServer, not string.IsNullOrWhiteSpace(value.Value))]
	private _templateServer as StringLiteralExpression

	[Property(TemplateImports, value.Items.All({e | e.NodeType == NodeType.StringLiteralExpression}))]
	private _templateImports = ArrayLiteralExpression()

	[Property(TemplateBaseClass, not string.IsNullOrWhiteSpace(value.Name))]
	private _templateBaseClass as ReferenceExpression

	def constructor():
		super()

	def constructor(path as StringLiteralExpression):
		super()
		_path = path.Value

	override def Apply(node as Node):
		assert node isa ClassDefinition
		var webBooNode = node as ClassDefinition
		webBooNode.Accept(WebBooTransformer(self))

private class WebBooTransformer(DepthFirstTransformer):
	private static final METHODS = System.Collections.Generic.List[of string](('Get', 'Post', 'Head', 'Put', 'Delete'))
	private static final STRING_TYPE = SimpleTypeReference('string')
	private static final MATCHES_TYPE = GenericTypeReference('System.Collections.Generic.IEnumerable', STRING_TYPE.CleanClone())
	private static final STREAM_RETURN_TYPE = TypeReference.Lift(System.IO.Stream)
	private static final ARGS_DICT_TYPE = TypeReference.Lift(System.Collections.Generic.IDictionary[of string, string])

	private _superFound as bool

	private _mainGetFound as bool

	private _constructorFound as bool

	private _singleGetMatch as bool

	private _getMatches as bool

	private _attr as WebBooAttribute

	def constructor(attr as WebBooAttribute):
		super()
		_attr = attr

	override def OnClassDefinition(node as ClassDefinition):
		node.BaseTypes.Reject({tr | tr.ToString() == 'object'})
		if node.BaseTypes.Count > 0:
			ProcessBaseTypes(node.BaseTypes)
		else: node.BaseTypes.Add(TypeReference.Lift(Boo.Web.WebBooClass))
		super(node)
		unless _constructorFound:
			var ctr = [|
				public def constructor(context as System.Net.HttpListenerContext, session as Session):
					super(context, session)
			|]
			node.Members.Add(ctr)
		
		if _attr.FileServer.Value:
			if _attr.TemplateServer is not null:
				SetFileServerWithTemplateServer(node)
			else: SetFileServer(node) 
		elif _attr.TemplateServer is not null:
			SetTemplateServer(node)
		unless _mainGetFound:
			CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) does not define a default Get() method."))
		BuildDispatch(node)
		if _attr.Path is not null:
			var init = [|
				initialization:
					Boo.Web.Application.RegisterWebBooClass($(_attr.Path), {r, s | return $(ReferenceExpression(node.Name))(r, s)})
			|]
			node.GetAncestor[of Module]().Globals.Add(init)

	private def ProcessBaseTypes(baseTypes as TypeReferenceCollection):
		var nrs = My[of NameResolutionService].Instance
		def isInterface(t as IType):
			return (nrs.Resolve(t.ToString(), EntityType.Type) cast IType)?.IsInterface
		
		if baseTypes.All(isInterface):
			baseTypes.Insert(0, TypeReference.Lift(Boo.Web.WebBooClass))
			return
		
		var baseType = baseTypes[0]
		typeRef as IType = nrs.Resolve(baseType.ToString(), EntityType.Type)
		if typeRef is null or not typeRef.IsAssignableFrom(My[of TypeSystemServices].Instance.Map(Boo.Web.WebBooClass)):
			raise "$(baseType.ToString()) is not a valid WebBoo base class"

	override def OnConstructor(node as Constructor):
		if node.IsStatic:
			super(node)
		else:
			raise "WebBoo class's constructor must take 0 parameters" if node.Parameters.Count > 0
			super(node)
			unless _superFound:
				node.Body.Insert(0, ExpressionStatement([|super(context, session)|]))
			node.Parameters.Add(ParameterDeclaration('context', TypeReference.Lift(System.Net.HttpListenerContext)))
			node.Parameters.Add(ParameterDeclaration('session', TypeReference.Lift(Boo.Web.Session)))
			_constructorFound = true

	override def OnMethodInvocationExpression(node as MethodInvocationExpression):
		if node.Target.NodeType == NodeType.SuperLiteralExpression:
			raise "Super constructor invocation should not pass arguments" unless node.Arguments.Count == 0
			node.Arguments.Add([|context|])
			_superFound = true

	override def OnMethod(node as Method):
		__switch__(METHODS.IndexOf(node.Name), gett, post, head, put, delete)
		return
		:gett
		OnGetMethod(node); return
		:post
		OnPostMethod(node); return
		:head
		OnHeadMethod(node); return
		:put
		OnPutMethod(node); return
		:delete
		OnDeleteMethod(node); return

	private def SetFlags(node as Method):
		if node.IsPrivate or node.IsProtected or node.IsInternal:
			raise "HTTP methods can't have non-public visibility."
		if node.IsStatic:
			raise "HTTP methods must be not be static."
		if node.ReturnType is not null and not ((node.ReturnType.Matches(STRING_TYPE)) or (node.ReturnType.Matches(STREAM_RETURN_TYPE))):
			raise "HTTP methods must return String or Stream"
		node.Modifiers = node.Modifiers | TypeMemberModifiers.Override | TypeMemberModifiers.Public
		node.ReturnType = TypeReference.Lift(ResponseData)

	private def IsGetMethod(node as Method) as bool:
		var args = node.Parameters
		if args.Count == 0:
			_mainGetFound = true
			return true
		if args.Count == 1:
			var arg1 = args[0]
			if arg1.Type is null:
				arg1.Type = ARGS_DICT_TYPE.CleanClone()
				return true
			if arg1.Type.Matches(STRING_TYPE):
				_singleGetMatch = true
				return true
			if arg1.Type.Matches(MATCHES_TYPE):
				_getMatches = true
				return true
		return false

	private def IsPostOrPutMethod(node as Method) as bool:
		var args = node.Parameters
		if args.Count == 1:
			var arg1 = args[0]
			if arg1.Type is null:
				arg1.Type = ARGS_DICT_TYPE.CleanClone()
				return true
		return false

	private def OnGetMethod(node as Method):
		return unless IsGetMethod(node)
		SetFlags(node)

	private def OnPostMethod(node as Method):
		return unless IsPostOrPutMethod(node)
		SetFlags(node)

	private def OnHeadMethod(node as Method):
		pass

	private def OnPutMethod(node as Method):
		return unless IsPostOrPutMethod(node)
		SetFlags(node)

	private def OnDeleteMethod(node as Method):
		if node.Parameters.Count == 0:
			SetFlags(node)

	private def EnsureLinq(node as ClassDefinition):
		var module = node.GetAncestor[of Module]()
		unless module.Imports.Any({imp | imp.Expression.ToString() == 'System.Linq.Enumerable'}):
			var newImport = [|import System.Linq.Enumerable|]
			newImport.Entity = ImportedNamespace(newImport, My[of NameResolutionService].Instance.ResolveQualifiedName(newImport.Namespace))
			module.Imports.Add(newImport)

	private def BuildDispatch(node as ClassDefinition):
		var dispatch = [|
			override protected def _DispatchGet_(path as string) as ResponseData:
				pass
		|]
		var body = dispatch.Body
		EnsureMatchDispatch() if _singleGetMatch or _getMatches
		if _attr.Regex is not null:
			EnsureLinq(node)
			body.Add([|var matches = $(_attr.Regex).Matches(path).Cast[of System.Text.RegularExpressions.Match]()\
				.Select({m | return m.Value}).Where({s | return not string.IsNullOrEmpty(s)}).ToArray()|])
			var noMatch = IfStatement([|matches.Length == 0|], Block(), Block())
			noMatch.TrueBlock.Add([|return Get()|])
			body.Add(noMatch)
			body = noMatch.FalseBlock
			if self._singleGetMatch:
				var singleGet = IfStatement([|matches.Length == 1|], Block(), Block())
				singleGet.TrueBlock.Add([|return Get(matches[0])|])
				body.Add(singleGet)
				body = singleGet.FalseBlock
			body.Add([|return Get(matches)|])
			unless _singleGetMatch or _getMatches:
				CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) specifies a regex but no Get methods to match a regex"))
		elif _attr.HasQueryString.Value:
			body.Add([|return Get(ParseQueryString())|])
		else:
			body.Add([|return Get()|])
		node.Members.Add(dispatch)

	private def EnsureMatchDispatch():
		if _attr.Regex is null:
			_attr.Regex = RELiteralExpression('/(.*)/')
		_getMatches = true

	private static final _fsDefaultGet = [|
		override def Get() as ResponseData:
			return SendFile('/index.html')
	|]

	private def SetFileServer(node as ClassDefinition):
		if _getMatches:
			CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) can't be a FileServer with a Get(string*) method already defined"))
			return
		var fs = [|
			override public def Get(values as string*) as ResponseData:
				return SendFile(string.Join('', values))
		|]
		node.Members.Add(fs)
		unless _mainGetFound:
			node.Members.Add(_fsDefaultGet.CleanClone())
			_mainGetFound = true
		EnsureMatchDispatch()

	private def GetStaticConstructor(node as ClassDefinition) as Constructor:
		var result = node.Members.OfType[of Constructor]().Where({c | c.IsStatic}).SingleOrDefault()
		if result is null:
			result = Constructor()
			result.Modifiers |= TypeMemberModifiers.Static
			node.Members.Add(result)
		return result

	private def PrepareClassConstructor(node as ClassDefinition):
		var ctor = GetStaticConstructor(node)
		var searchPath = System.IO.Path.GetDirectoryName(WebBooClass.StripLeadingSlash(_attr.TemplateServer.Value))
		var filename = System.IO.Path.GetFileName(_attr.TemplateServer.Value)
		var init = [|LoadTemplates($searchPath, $filename)|]
		if _attr.TemplateBaseClass is not null:
			init.Arguments.Add(_attr.TemplateBaseClass.CleanClone())
		init.Arguments.AddRange(_attr.TemplateImports.Items)
		ctor.Body.Add(init)

	private static final _templateDefaultGet = [|
		override def Get() as ResponseData:
			return ProcessTemplate('index')
	|]

	private def SetTemplateServer(node as ClassDefinition) as Method:
		if _getMatches:
			CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) can't be a TemplateServer with a Get(string*) method already defined"))
			return null
		PrepareClassConstructor(node)
		var result = [|
			override public def Get(values as string*) as ResponseData:
				var result = ProcessTemplate(string.Join('', values))
				return result if result is not null
				raise System.IO.FileNotFoundException()
		|]
		node.Members.Add(result)
		var post = [|
			override protected internal def _DispatchPost_(path as string) as ResponseData:
				var result = ProcessTemplate(path)
				return result if result is not null
				return super._DispatchPost_(path)
		|]
		node.Members.Add(post)
		EnsureMatchDispatch()
		unless _mainGetFound:
			node.Members.Add(_templateDefaultGet.CleanClone())
			_mainGetFound = true
		return result

	private def SetFileServerWithTemplateServer(node as ClassDefinition):
		var processor = SetTemplateServer(node)
		return if processor is null
		processor.Body.Statements.Remove(processor.Body.LastStatement)
		processor.Body.Add([|return SendFile(string.Join('', values))|])
