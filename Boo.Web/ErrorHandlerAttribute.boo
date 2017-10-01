namespace Boo.Web

import System
import System.Linq.Enumerable
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
import Boo.Lang.Environments
import Boo.Lang.Compiler.TypeSystem
import Boo.Lang.Compiler.TypeSystem.Services

class ErrorHandlerAttribute(AbstractAstAttribute):
"""Apply this to a method that will be used to handle HTTP errors (4xx or 5xx codes) The method's signature must be:
	static def [name](code as int, request as HttpListenerRequest) as ResponseData
"""
	private _codes as (IntegerLiteralExpression)

	public def constructor(*errorCodes as (IntegerLiteralExpression)):
		_codes = errorCodes

	private def IsStatic(value as TypeMemberModifiers):
		return value & TypeMemberModifiers.Static == TypeMemberModifiers.Static

	private def IsValidMethodSignature(value as Method):
		unless IsStatic(value.Modifiers) or IsStatic(value.GetAncestor[of TypeDefinition]().Modifiers):
			return false
		unless value.Parameters.Count == 2:
			return false
		var nrs = My[of NameResolutionService].Instance
		var tss = My[of TypeSystemServices].Instance
		
		var p1 = value.Parameters[0]
		return false if p1.Type is null
		typeRef as IType = nrs.Resolve(p1.Type.ToString(), EntityType.Type)
		return false if typeRef != tss.IntType
		
		var p2 = value.Parameters[1]
		return false if p2.Type is null
		typeRef = nrs.Resolve(p2.Type.ToString(), EntityType.Type)
		return false if typeRef != tss.Map(System.Net.HttpListenerRequest)
		
		return false if value.ReturnType is null
		typeRef = nrs.Resolve(value.ReturnType.ToString(), EntityType.Type)
		return typeRef == tss.Map(Boo.Web.ResponseData)

	private def BuildInitialization(target as Method, codes as (int)):
		var targetName = ReferenceExpression(target.Name)
		var owner = target.GetAncestor[of TypeDefinition]()
		while owner is not null:
			var ownerName = ReferenceExpression(owner.Name)
			targetName = MemberReferenceExpression.Combine(ownerName, targetName)
			owner = owner.GetAncestor[of TypeDefinition]()
		var body = Block()
		for code in codes:
			body.Add([|Boo.Web.Application.RegisterErrorHandler($code, $targetName)|])
		var init = MacroStatement(self.LexicalInfo, 'initialization', Body: body)
		target.GetAncestor[of Module]().Globals.Add(init)

	override def Apply(node as Node):
		var targetMethod = node as Method
		assert targetMethod is not null, "ErrorHandler must be applied to a method"
		
		if _codes is null or _codes.Length == 0:
			raise "No error codes are defined for this attribute"
		var codeValues = _codes.Select({ile | ile.Value}).Where({v | v >= 400 and v < 600}).Cast[of int]().ToArray()
		if codeValues.Length < _codes.Length:
			CompilerContext.Current.Warnings.Add(CompilerWarning(_codes[0].LexicalInfo, "Only 4xx and 5xx codes are valid for an error handler"))
			if codeValues.Length == 0:
				raise "No valud error codes are defined for this attribute"
		unless IsValidMethodSignature(targetMethod):
			raise "Error handler method's signature must be: static def [name](code as int, request as HttpListenerRequest) as ResponseData"
		BuildInitialization(targetMethod, codeValues)
