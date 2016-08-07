/// HttpUtils.HttpMultipartParser
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
import System.Text
import System.Text.RegularExpressions
import System.Collections.Generic

public class HttpMultipartParser:
"""
<summary>
HttpMultipartParser
Reads a multipart http data stream and returns the file name, content type and file content.
Also, it returns any additional form parameters in a Dictionary.
</summary>
"""

	public def constructor(stream as Stream, filePartName as string):
		FilePartName = filePartName
		self.Parse(stream, Encoding.UTF8)

	public def constructor(stream as Stream, encoding as Encoding, filePartName as string):
		FilePartName = filePartName
		self.Parse(stream, encoding)

	private def Parse(stream as Stream, encoding as Encoding):
		startIndex as int
		self.Success = false
		
		// Read the stream into a byte array
		data as (byte) = Misc.ToByteArray(stream)
		
		// Copy to a string for header parsing
		content as string = encoding.GetString(data)
		
		// The first line should contain the delimiter
		delimiterEndIndex as int = content.IndexOf('\r\n')
		
		// Get the start & end indexes of the file contents
		if delimiterEndIndex > (-1):
			delimiter as string = content.Substring(0, content.IndexOf('\r\n'))
			sections as (string) = content.Split((of string: delimiter), StringSplitOptions.RemoveEmptyEntries)
			for s as string in sections:
				if s.Contains('Content-Disposition'):
					// If we find "Content-Disposition", this is a valid multi-part section
					// Now, look for the "name" parameter
					nameMatch as Match = Regex('(?<=name\\=\\")(.*?)(?=\\")').Match(s)
					name as string = nameMatch.Value.Trim().ToLower()
					if name == FilePartName:
						// Look for Content-Type
						re = Regex('(?<=Content\\-Type:)(.*?)(?=\\r\\n\\r\\n)')
						contentTypeMatch as Match = re.Match(content)
						
						// Look for filename
						re = Regex('(?<=filename\\=\\")(.*?)(?=\\")')
						filenameMatch as Match = re.Match(content)
						
						// Did we find the required values?
						if contentTypeMatch.Success and filenameMatch.Success:
							// Set properties
							self.ContentType = contentTypeMatch.Value.Trim()
							self.Filename = filenameMatch.Value.Trim()
							
							// Get the start & end indexes of the file contents
							startIndex = ((contentTypeMatch.Index + contentTypeMatch.Length) + '\r\n\r\n'.Length)
							delimiterBytes as (byte) = encoding.GetBytes(('\r\n' + delimiter))
							endIndex as int = Misc.IndexOf(data, delimiterBytes, startIndex)
							
							contentLength as int = (endIndex - startIndex)
							
							// Extract the file contents from the byte array
							fileData as (byte) = array(byte, contentLength)
							
							Buffer.BlockCopy(data, startIndex, fileData, 0, contentLength)
							
							self.FileContents = fileData
							
					elif not string.IsNullOrWhiteSpace(name):
						// Get the start & end indexes of the file contents
						startIndex = ((nameMatch.Index + nameMatch.Length) + '\r\n\r\n'.Length)
						Parameters.Add(name, s.Substring(startIndex).TrimEnd(*(char('\r'), char('\n'))).Trim())
			// If some data has been successfully received, set success to true
			if (FileContents is not null) or (Parameters.Count != 0):
				self.Success = true

	public Parameters as IDictionary[of string, string] = Dictionary[of string, string]()

	[Property(FilePartName, ProtectedSetter: true)]
	private _filePartName as string

	[Property(Success, ProtectedSetter: true)]
	private _success as bool

	[Property(ContentType, ProtectedSetter: true)]
	private _contentType as string

	[Property(Filename, ProtectedSetter: true)]
	private _filename as string

	[Property(FileContents, ProtectedSetter: true)]
	private _fileContents as (byte)