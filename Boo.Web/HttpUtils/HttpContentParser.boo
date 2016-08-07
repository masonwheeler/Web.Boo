/// HttpUtils.HttpContentParser
/// 
/// Copyright (c) 2012 Lorenzo Polidori
///
/// Ported to Boo 2016 by Mason Wheeler
/// original C# code can be found at https://bitbucket.org/lorenzopolidori/http-form-parser
/// 
/// This software is distributed under the terms of the MIT License reproduced below.
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy of this software 
/// and associated documentation files (the "Software"), to deal in the Software without restriction, 
/// including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, 
/// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, 
/// subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in all copies or substantial 
/// portions of the Software.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT 
/// NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
/// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
/// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
/// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
/// 

namespace HttpUtils

import System.IO
import System.Text
import System.Collections.Generic

public class HttpContentParser:
"""
<summary>
HttpContentParser
Reads an http data stream and returns the form parameters.
</summary>
"""
	public def constructor(stream as Stream):
		self.Parse(stream, Encoding.UTF8)

	public def constructor(stream as Stream, encoding as Encoding):
		self.Parse(stream, encoding)

	private def Parse(stream as Stream, encoding as Encoding):
		self.Success = false
		// Read the stream into a byte array
		data as (byte) = Misc.ToByteArray(stream)
		
		// Copy to a string for header parsing
		content as string = encoding.GetString(data)
		
		name as string = string.Empty
		
		value as string = string.Empty
		lookForValue = false
		charCount = 0
		for c in content:
			if c == char('='):
				lookForValue = true
			elif c == char('&'):
				lookForValue = false
				AddParameter(name, value)
				name = string.Empty
				value = string.Empty
			elif not lookForValue:
				name += c
			else:
				value += c
			if (++charCount) == content.Length:
				AddParameter(name, value)
				break 
		
		// If some data has been successfully received, set success to true
		if Parameters.Count != 0:
			self.Success = true

	private def AddParameter(name as string, value as string):
		if (not string.IsNullOrWhiteSpace(name)) and (not string.IsNullOrWhiteSpace(value)):
			Parameters.Add(name.Trim(), value.Trim())

	public Parameters as IDictionary[of string, string] = Dictionary[of string, string]()

	[Property(Success, ProtectedSetter: true)]
	private _success as bool
