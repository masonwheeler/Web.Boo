﻿namespace Boo.Web

import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast

//based on System.Net.HttpListener
//see also https://bitbucket.org/lorenzopolidori/http-form-parser/src

class WebBooAttribute(AbstractAstAttribute):
	override def Apply(node as Node):
		assert node isa ClassDefinition
		var webBooNode = node as ClassDefinition
		webBooNode.Accept(WebBooTransformer())

private class WebBooTransformer(DepthFirstTransformer):
	private static final METHODS = System.Collections.Generic.List[of string](('Get', 'Post', 'Head'))
	private static final STRING_TYPE = TypeReference.Lift(string)
	private static final MATCHES_TYPE = TypeReference.Lift(typeof(string*))
	private static final STREAM_RETURN_TYPE = TypeReference.Lift(System.IO.Stream)
	private static final ARGS_DICT_TYPE = TypeReference.Lift(System.Collections.Generic.IDictionary[of string, string])

	private _superFound as bool

	private _mainGetFound as bool

	private _constructorFound as bool

	private _singleGetMatch as bool

	private _getMatches as bool

	[Property(Regex)]
	private _regex as System.Text.RegularExpressions.Regex

	[Property(HasQueryString)]
	private _hasQueryString as bool

	override def OnClassDefinition(node as ClassDefinition):
		assert node.BaseTypes.Count == 0, "WebBoo attribute can't be applied to classes with a base type"
		node.BaseTypes.Add(TypeReference.Lift(Boo.Web.WebBooClass))
		super(node)
		unless _constructorFound:
			var ctr = [|
				public def constructor(context as System.Net.HttpListenerRequest):
					super(context)
			|]
			node.Members.Add(ctr)
		unless _constructorFound:
			CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) does not define a default Get() method."))
		
		BuildDispatch(node)

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

	private def OnGetMethod(node as Method):
		return unless IsGetMethod(node)
		SetFlags(node)
	
	private def OnPostMethod(node as Method):
		pass
		
	private def OnHeadMethod(node as Method):
		pass

	private def BuildDispatch(node as ClassDefinition):
		var dispatch = [|
			override protected internal def _DispatchGet_(path as string) as string:
				pass
		|]
		var body = dispatch.Body
		if self._regex is not null:
			body.Add([|var matches = _regex.Matches(path).Select({m | m.Value}).ToArray()|])
			if self._singleGetMatch:
				var singleGet = [|
					if matches.Length == 1:
						return Get(matches[0])
				|]
				body.Add(singleGet)
				body = Block()
				singleGet.FalseBlock = body
			body.Add([|return Get(matches)|])
			unless _singleGetMatch or _getMatches:
				CompilerContext.Current.Warnings.Add(CompilerWarning(node.LexicalInfo, "WebBoo class $(node.Name) specifies a regex but no Get methods to match a regex"))
		elif _hasQueryString:
			body.Add([|return Get(ParseQS(Request.QueryString))|])
		else:
			body.Add([|return Get()|])

/*
[WebBoo('/', Regex: /(.*)/)]
class Hello:
	def Get():
		return Get('World')"

	def Get(name as string):
		return "Hello, $(name)!!"
*/