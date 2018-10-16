namespace Boo.Web

import System.Linq.Enumerable
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
import Boo.Lang.Compiler.TypeSystem
import Boo.Lang.Environments

//based on System.Net.HttpListener
//see also https://bitbucket.org/lorenzopolidori/http-form-parser/src

class WebBooAttribute(AbstractAstAttribute):
	[Getter(Path)]
	private _path as string

	private _interpPath as ExpressionInterpolationExpression

	[Getter(Interpolations)]
	private _interpolations as ExpressionCollection

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

	def constructor(path as ExpressionInterpolationExpression):
		super()
		ValidateInterpolatedPath(path)
		_interpPath = path

	private def ValidateInterpolatedPath(path as ExpressionInterpolationExpression):
		_interpolations = ExpressionCollection()
		unless path.Expressions.All({e | e.NodeType in (NodeType.StringLiteralExpression, NodeType.ReferenceExpression, NodeType.TryCastExpression)}):
			raise "All interpolations must be of the form '\$name' or '\$(name as type)'"
		for exprType in path.Expressions.OfType[of TryCastExpression]().Select({tce | string.Intern(tce.Type.ToString())}):
			if exprType not in ('int', 'long', 'float', 'single', 'double', 'string'):
				raise "All interpolations must be a string or a simple numeric type"
		if path.Expressions[0].NodeType != NodeType.StringLiteralExpression:
			raise "An interpolated path must not begin with an interpolation expression"
		var sb = System.Text.StringBuilder()
		for i in range(path.Expressions.Count):
			var expr = path.Expressions[i]
			if expr.NodeType == NodeType.StringLiteralExpression:
				sb.Append((expr cast StringLiteralExpression).Value)
			else:
				var last = path.Expressions[i - 1]
				if last.NodeType != NodeType.StringLiteralExpression or not ((last cast StringLiteralExpression).Value.EndsWith('/')):
					raise "Only one interpolated expression is allowed per path segment"
				if i + 1 < path.Expressions.Count:
					var next = path.Expressions[i + 1]
					if next.NodeType != NodeType.StringLiteralExpression or not ((last cast StringLiteralExpression).Value.StartsWith('/')):
						raise "Only one interpolated expression is allowed per path segment"
				sb.Append('?')
				_interpolations.Add(expr)
		_path = sb.ToString()

	override def Apply(node as Node):
		assert node isa ClassDefinition
		var webBooNode = node as ClassDefinition
		webBooNode.Accept(WebBooTransformer(self))

private class WebBooTransformer(DepthFirstTransformer):
	private static final METHODS = System.Collections.Generic.List[of string](('Get', 'Post', 'Head', 'Put', 'Delete'))
	private static final STRING_TYPE = SimpleTypeReference('string')
	private static final STREAM_RETURN_TYPE = TypeReference.Lift(System.IO.Stream)
	private static final ARGS_DICT_TYPE = TypeReference.Lift(System.Collections.Generic.IDictionary[of string, string])

	private _superFound as bool

	private _mainGetFound as bool

	private _postFound as bool

	private _putFound as bool

	private _deleteFound as bool

	private _constructorFound as bool

	private _singleGetMatch as bool

	private _attr as WebBooAttribute

	private _interpolationCount as int

	private _validator as Method

	def constructor(attr as WebBooAttribute):
		super()
		_attr = attr
		if attr.Interpolations is not null:
			_interpolationCount = attr.Interpolations.Count

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
		if _interpolationCount > 0:
			BuildInterpolatedClass(node)
		else:
			BuildDispatch(node)
		if _attr.Path is not null:
			validator as Expression = (NullLiteralExpression() if _validator is null else [|$(ReferenceExpression(node.Name)).ValidInterpolation|])
			var registerNote = "Registering path ${_attr.Path}"
			var init = [|
				initialization:
					print $registerNote
					Boo.Web.Application.RegisterWebBooClass($(_attr.Path), {r, s | return $(ReferenceExpression(node.Name))(r, s) as WebBooClass}, $validator)
			|]
			node.GetAncestor[of Module]().Globals.Add(init)

	private def ProcessBaseTypes(baseTypes as TypeReferenceCollection):
		def isInterface(tr as TypeReference):
			type as IType = tr.Entity
			if type is null:
				return false
			return type.IsInterface
		
		if baseTypes.All(isInterface):
			baseTypes.Insert(0, TypeReference.Lift(Boo.Web.WebBooClass))
			return
		
		var baseType = baseTypes[0]
		typeRef as IType = baseType.Entity
		if typeRef is null or not My[of TypeSystemServices].Instance.Map(Boo.Web.WebBooClass).IsAssignableFrom(typeRef):
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
			node.Arguments.Add(ReferenceExpression('context'))
			node.Arguments.Add(ReferenceExpression('session'))
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
		node.Modifiers = node.Modifiers | TypeMemberModifiers.Public
		node.Modifiers = node.Modifiers | TypeMemberModifiers.Override if _interpolationCount == 0
		node.ReturnType = TypeReference.Lift(ResponseData)

	private def IsValidInterpolation(node as Method, extras as int):
		return true if _interpolationCount == 0
		return false if node.Parameters.Count != _interpolationCount + extras
		for i in range(_interpolationCount):
			var interpolation = _attr.Interpolations[i]
			var interpolationType = ('string' if interpolation.NodeType == NodeType.ReferenceExpression else (interpolation cast TryCastExpression).Type.ToString())
			var param = node.Parameters[i]
			var paramType = ('string' if param.Type is null else param.Type.ToString())
			return false unless interpolationType.Equals(paramType)
		return true

	private def IsGetMethod(node as Method) as bool:
		var args = node.Parameters
		if args.Count == _interpolationCount:
			return false unless IsValidInterpolation(node, 0)
			_mainGetFound = true
			return true
		if args.Count == _interpolationCount + 1:
			return false unless IsValidInterpolation(node, 1)
			var arg1 = args[_interpolationCount]
			if arg1.Type is null:
				arg1.Type = ARGS_DICT_TYPE.CleanClone()
				return true
			if arg1.Type.Matches(STRING_TYPE):
				_singleGetMatch = true
				return true
		return false

	private def IsPostOrPutMethod(node as Method) as bool:
		var args = node.Parameters
		if args.Count == _interpolationCount + 1:
			var arg1 = args[_interpolationCount]
			if arg1.Type is null:
				arg1.Type = ARGS_DICT_TYPE.CleanClone()
				return true
		return false

	private def OnGetMethod(node as Method):
		return unless IsGetMethod(node)
		SetFlags(node)

	private def OnPostMethod(node as Method):
		return unless IsPostOrPutMethod(node)
		_postFound = true
		SetFlags(node)

	private def OnHeadMethod(node as Method):
		pass

	private def OnPutMethod(node as Method):
		return unless IsPostOrPutMethod(node)
		_putFound = true
		SetFlags(node)

	private def OnDeleteMethod(node as Method):
		if node.Parameters.Count == _interpolationCount:
			_deleteFound = true
			SetFlags(node)

	private def BuildDispatch(node as ClassDefinition):
		var dispatch = [|
			override protected def _DispatchGet_(path as string) as ResponseData:
				pass
		|]
		var body = dispatch.Body
		if _attr.HasQueryString.Value:
			body.Add([|return Get(ParseQueryString())|])
		else:
			body.Add([|return Get()|])
		if _attr.FileServer.Value:
			dispatch.Body = [|
				if not string.IsNullOrEmpty(path):
					return Get(path)
				$body
			|]
		node.Members.Add(dispatch)

	private def BuildInterpolatedClass(node as ClassDefinition):
		BuildInterpolatedDispatchers(node)
		BuildValidator(node)

	private def BuildValidator(node as ClassDefinition):
		var result = [|
			internal static def ValidInterpolation(index as int, value as string) as bool:
				return true
		|]
		ifst as IfStatement
		for i in range(_interpolationCount):
			var interpolation = _attr.Interpolations[i]
			var interpolationType = ('string' if interpolation.NodeType == NodeType.ReferenceExpression else (interpolation cast TryCastExpression).Type.ToString())
			continue if interpolationType == 'string'
			var typeRef = ReferenceExpression(interpolationType)
			var typeType = SimpleTypeReference(interpolationType)
			var name = ReferenceExpression(CompilerContext.Current.GetUniqueName('interpolation'))
			ifst = [|
				if index == $i:
					$(DeclarationStatement(Declaration(name.Name, typeType), null))
					return $typeRef.TryParse(value, $name)
				else:
					$(ifst if ifst is not null else ReturnStatement(BoolLiteralExpression(true)))
			|]
			result.Body.Clear()
			result.Body.Add(ifst)
		node.Members.Add(result)
		_validator = result

	private def BuildInterpolatedDispatch(name as string, ppd as bool) as Method:
		nameRef = ReferenceExpression("_Dispatch$(name)_")
		var dispatch = [|
			override protected def $nameRef(values as (string)) as ResponseData:
				pass
		|]
		var body = dispatch.Body
		
		var invocation = MethodInvocationExpression(ReferenceExpression(name))
		for i in range(_interpolationCount):
			var expr = _attr.Interpolations[i]
			if expr.NodeType == NodeType.ReferenceExpression:
				invocation.Arguments.Add([|values[$i]|])
			else:
				var tce = expr cast TryCastExpression
				var exprType = tce.Type
				if exprType.ToString == 'string':
					invocation.Arguments.Add([|values[$i]|])
				else:
					invocation.Arguments.Add([|$(ReferenceExpression(exprType.ToString())).Parse(values[$i])|])
		if _attr.HasQueryString.Value:
			invocation.Arguments.Add([|ParseQueryString()|])
		elif ppd:
			invocation.Arguments.Add([|ParsePostData()|])
		body.Add([|return $invocation|])
		return dispatch

	private def BuildInterpolatedDispatchers(node as ClassDefinition):
		node.Members.Add(BuildInterpolatedDispatch('Get', false))
		var dummyGet = [| 
			override protected def _DispatchGet_(path as string) as ResponseData:
				raise System.NotImplementedException()
		|]
		node.Members.Add(dummyGet)
		node.Members.Add(BuildInterpolatedDispatch('Post', true)) if _postFound
		node.Members.Add(BuildInterpolatedDispatch('Put', true)) if _putFound
		node.Members.Add(BuildInterpolatedDispatch('Delete', false)) if _deleteFound

	private static final _fsDefaultGet = [|
		override def Get() as ResponseData:
			return SendFile('/index.html')
	|]

	private def SetFileServer(node as ClassDefinition):
		if _interpolationCount > 0:
			CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) can't be a FileServer with an interpolated path"))
			return
		if _singleGetMatch:
			CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) can't be a FileServer with a Get(string) method already defined"))
			return
		var fs = [|
			override public def Get(value as string) as ResponseData:
				return SendFile(value)
		|]
		node.Members.Add(fs)
		unless _mainGetFound:
			node.Members.Add(_fsDefaultGet.CleanClone())
			_mainGetFound = true

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
		unless _mainGetFound:
			node.Members.Add(_templateDefaultGet.CleanClone())
			_mainGetFound = true
		return result

	private def SetFileServerWithTemplateServer(node as ClassDefinition):
		var processor = SetTemplateServer(node)
		return if processor is null
		processor.Body.Statements.Remove(processor.Body.LastStatement)
		processor.Body.Add([|return SendFile(string.Join('', values))|])
