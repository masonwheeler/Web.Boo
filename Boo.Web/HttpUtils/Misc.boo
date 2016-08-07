/// HttpUtils.Misc
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

import System
import System.IO

public static class Misc:

	public def IndexOf(searchWithin as (byte), searchFor as (byte), startIndex as int) as int:
		index = 0
		startPos as int = Array.IndexOf(searchWithin, searchFor[0], startIndex)
		if startPos != -1:
			while (startPos + index) < searchWithin.Length:
				if searchWithin[startPos + index] == searchFor[index]:
					index += 1
					if index == searchFor.Length:
						return startPos
				else:
					startPos = Array.IndexOf[of byte](searchWithin, searchFor[0], startPos + index)
					if startPos == -1:
						return -1
					index = 0
		return -1

	public def ToByteArray(stream as Stream) as (byte):
		buffer as (byte) = array(byte, 32768)
		using ms = MemoryStream():
			while true:
				read as int = stream.Read(buffer, 0, buffer.Length)
				if read <= 0:
					return ms.ToArray()
				ms.Write(buffer, 0, read)

