namespace Boo.Web

import System.Linq.Enumerable
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
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

	def constructor(path as StringLiteralExpression):
		super()
		_path = path.Value

	override def Apply(node as Node):
		assert node isa ClassDefinition
		var webBooNode = node as ClassDefinition
		webBooNode.Accept(WebBooTransformer(self))

private class WebBooTransformer(DepthFirstTransformer):
	private static final METHODS = System.Collections.Generic.List[of string](('Get', 'Post', 'Head'))
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
		assert node.BaseTypes.Count == 0, "WebBoo attribute can't be applied to classes with a base type"
		node.BaseTypes.Add(TypeReference.Lift(Boo.Web.WebBooClass))
		super(node)
		unless _constructorFound:
			var ctr = [|
				public def constructor(context as System.Net.HttpListenerRequest):
					super(context)
			|]
			node.Members.Add(ctr)
		unless _mainGetFound:
			CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) does not define a default Get() method."))
		
		SetFileServer(node) if _attr.FileServer.Value
		BuildDispatch(node)
		var init = [|
			initialization:
				Boo.Web.Application.RegisterWebBooClass($(_attr.Path), {r | return $(ReferenceExpression(node.Name))(r)})
		|]
		node.GetAncestor[of Module]().Globals.Add(init)

	override def OnConstructor(node as Constructor):
		raise "WebBoo class's constructor must take 0 parameters" if node.Parameters.Count > 0
		super(node)
		unless _superFound:
			node.Body.Insert(0, ExpressionStatement([|super(context)|]))
		node.Parameters.Add(ParameterDeclaration('context', TypeReference.Lift(System.Net.HttpListenerRequest)))
		_constructorFound = true

	override def OnMethodInvocationExpression(node as MethodInvocationExpression):
		if node.Target.NodeType == NodeType.SuperLiteralExpression:
			raise "Super constructor invocation should not pass arguments" unless node.Arguments.Count == 0
			node.Arguments.Add([|context|])
			_superFound = true

	override def OnMethod(node as Method):
		__switch__(METHODS.IndexOf(node.Name), gett, post, head)
		return
		:gett
		OnGetMethod(node); return
		:post
		OnPostMethod(node); return
		:head
		OnHeadMethod(node); return

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

	private def IsPostMethod(node as Method) as bool:
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
		return unless IsPostMethod(node)
		SetFlags(node)
		
	private def OnHeadMethod(node as Method):
		pass

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

	private def SetFileServer(node as ClassDefinition):
		if _getMatches:
			CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) can't be a FileServer with a Get(string*) method already defined"))
			return
		var fs = [|
			override public def Get(values as string*) as ResponseData:
				return SendFile(string.Join('', values))
		|]
		node.Members.Add(fs)
		if _attr.Regex is null:
			_attr.Regex = RELiteralExpression('/(.*)/')
		_getMatches = true