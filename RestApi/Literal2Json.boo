namespace RestApi

import System
import Newtonsoft.Json.Linq

def jsonify(value):
	if value isa Boo.Lang.List:
		return List2JSON(value)
	elif value isa Hash:
		return Hash2JSON(value)
	else: return JValue(value)

def List2JSON(values as Boo.Lang.List) as JArray:
	result = JArray()
	for elem as object in values:
		if elem isa Hash:
			result.Add(Hash2JSON(elem))
		elif elem isa Boo.Lang.List:
			result.Add(List2JSON(elem))
		else: result.Add(elem)
	return result

def Hash2JSON(value as Hash) as JToken:
	return JValue.CreateNull() if value is null
	
	result = JObject()
	enumerator = value.GetEnumerator()
	while enumerator.MoveNext():
		entry = enumerator.Entry
		elem as object = entry.Value
		if elem isa Hash:
			elem = Hash2JSON(elem)
		elif elem isa Boo.Lang.List:
			elem = List2JSON(elem)
		key as object = entry.Key
		key = Hash2JSON(key).ToString().Replace('\r\n', '') if key isa Hash
		result.Add(key.ToString(), elem)
	return result

