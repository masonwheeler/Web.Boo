namespace Boo.Web

import System
import System.Collections.Generic
import System.IO
import System.Linq.Enumerable
import System.Net
import Newtonsoft.Json.Linq

class SessionExpired(HttpError):
	def constructor(message as string):
		super('200 OK', null, message)

callable WithSessionHandler(s as Session, ref result as ResponseData) as bool

class Session:
"""
Session management for Web.Boo
Adapted from the web.py Session object
"""

	private _store as Store

	private _initializer as Action of Session

	private _lastCleanupTime as DateTime

	private _config as SessionConfig

	[Getter(Data)]
	private _data = Dictionary[of string, string]()

	private _sessionID as Cookie

	private _request as HttpListenerRequest

	private _response as HttpListenerResponse

	private _killed as bool

	[Property(DefaultConfig)]
	static private _defaultConfig = SessionConfig(
			CookieName: 'Web.Boo__sessionID',
			CookieDomain: '',
			CookiePath : '',
			Timeout: 1d, 
			IgnoreExpiry: true,
			IgnoreChangeIP: true,
			SecretKey: 'C39A2DB3A86D48479C7859CEA6F4A7BF',
			ExpiredMessage: 'Session expired',
			HttpOnly: true,
			Secure: false
		)

	static def WithSession(request as HttpListenerRequest, response as HttpListenerResponse, store as Store,
			initializer as Action[of Session], ref result as ResponseData, run as WithSessionHandler) as bool:
		var aSession = Session(request, response, store, initializer, _defaultConfig)
		aSession.Load()
		try:
			return run(aSession, result)
		ensure:
			aSession.Save()

	private def constructor(request as HttpListenerRequest, response as HttpListenerResponse, store as Store,
			initializer as Action of Session, config as SessionConfig):
		_store = store
		_initializer = initializer
		_config = config
		_request = request
		_response = response

	def ContainsKey(name as string):
		return _data.ContainsKey(name)

	Key as string:
		get: return _sessionID?.Value

	private def Update(value as Dictionary[of string, string]):
		for pair in value:
			self._data[pair.Key] = pair.Value

	public self[key as string] as string:
		get: return _data[key]
		set: _data[key] = value

	private def Load():
	"""Load the session from the store, by the id from cookie"""
		var cookieName = self._config.CookieName
		_sessionID = _request.Cookies[cookieName]

		# protection against _sessionID tampering
		if _sessionID and not self.ValidSessionID(_sessionID):
			_sessionID = null

		self.CheckExpiry()
		if self._sessionID:
			d = _store[self._sessionID.Value]
			self.Update(d)
			self.ValidateIP()
		
		self._data['IP'] = _request.RemoteEndPoint.ToString()

		if not self._sessionID:
			self._sessionID = Cookie(cookieName, self.GenerateSessionID())

			if self._initializer:
				self._initializer(self)

	def CheckExpiry() as bool:
		# check for expiry
		if self._sessionID and self._sessionID.Value not in self._store:
			if self._config.IgnoreExpiry:
				self._sessionID = null
			else:
				self.Expired()

	private def ValidateIP():
		# check for change of IP
		if self._sessionID and self._data['IP'] != _request.RemoteEndPoint.ToString():
			if not self._config.IgnoreChangeIP:
				self.Expired() 

	private def Save():
		if not _killed:
			self.SetCookie(self._sessionID)
			self._store[self._sessionID.Value] = self._data
		else:
			self.SetCookie(self._sessionID, DateTime.Now)

	private def SetCookie(sessionID as Cookie):
		SetCookie(sessionID, null)

	private def SetCookie(sessionID as Cookie, expires as DateTime?):
		var cookieName = self._config.CookieName
		var cookieDomain = self._config.CookieDomain
		var cookiePath = self._config.CookiePath
		var httpOnly = self._config.HttpOnly
		var secure = self._config.Secure
		_response.Cookies.Add(Cookie(cookieName, sessionID.Value, cookiePath, cookieDomain, HttpOnly: httpOnly, Secure: secure))
		sessionID.Discard = true

	private static _random = System.Random()
	private static _sha = System.Security.Cryptography.SHA1.Create()

	def GenerateSessionID():
	"""Generate a random id for session"""
		while true:
			lock _random:
				var rand = _random.Next(16)
			var now = DateTime.Now
			secretKey = self._config.SecretKey

			hashable = "$rand$now$(self._data['IP'])$secretKey"
			bytes as (byte)
			lock _sha:
				bytes = _sha.ComputeHash(System.Text.Encoding.UTF8.GetBytes(hashable))
			result as string
			using sb = System.Text.StringBuilder():
				for b in bytes:
					sb.Append(b.ToString('x2'))
				result = sb.ToString()
			return result unless result in self._store

	def ValidSessionID(session as Cookie):
		rx = /^[0-9a-fA-F]+$/
		return rx.Match(session.Value)
		
	def Expired():
	"""Called when an expired session is atime"""
		self._killed = true
		self.Save()
		raise SessionExpired(self._config.ExpiredMessage)
 
	def Kill():
	"""Kill the session, make it no longer available"""
		self._store.Remove(self._sessionID.Value)
		self._killed = true

class Store:
"""Base class for session stores"""

	static def op_Member(lhs as string, rhs as Store) as bool:
		return rhs.Contains(lhs)

	static def op_NotMember(lhs as string, rhs as Store) as bool:
		return not rhs.Contains(lhs)

	abstract protected internal def Contains(key as string) as bool:
		pass

	self[key as string] as Dictionary[of string, string]):
		virtual get:
			raise NotImplementedException()
		virtual set: 
			raise NotImplementedException()

	abstract def Cleanup(timeout as timespan):
	"""removes all the expired sessions"""
		pass

	abstract protected internal def Remove(key as string):
		pass

	protected def Encode(sessionDict as Dictionary[of string, string]):
	"""encodes session dict as a string"""
		var result = JObject()
		for pair in sessionDict:
			result[pair.Key] = pair.Value
		return System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(result.ToString()))

	protected def Decode(sessionData as string) as Dictionary[of string, string]:
	"""decodes the data to get back the session dict """
		var json = JObject.Parse(System.Text.Encoding.UTF8.GetString(System.Convert.FromBase64String(sessionData)))
		var result = Dictionary[of string, string]()
		for pair as KeyValuePair[of string, JToken] in json:
			result[pair.Key] = pair.Value.ToString()
		return result

class DiskStore(Store):
	private final _root as string

	def constructor(root as string):
		# if the storage root doesn't exists, create it.
		Directory.CreateDirectory(root)
		self._root = root

	private def GetPath(key as string):
		if Path.DirectorySeparatorChar in key: 
			raise "Bad key: $key"
		return Path.Combine(_root, key)

	override protected internal def Contains(key as string) as bool:
		lock self:
			var path = self.GetPath(key)
			return File.Exists(path)

	override protected internal def Remove(key as string):
		lock self:
			var path = self.GetPath(key)
			File.Delete(path) if File.Exists(path)

	self[key as string] as Dictionary[of string, string]):
		override get:
			lock self:
				var path = self.GetPath(key)
		
				if File.Exists(path):
					var text = File.ReadAllText(path)
					return self.Decode(text)
				else:
					raise ArgumentException(key)
		override set:
			lock self:
				var path = self.GetPath(key)
				var text = self.Encode(value)
				try:
					File.WriteAllText(path, text)
				except as IOException:
					pass

	override def Cleanup(timeout as timespan):
		lock self:
			var now = DateTime.Now
			for path in Directory.EnumerateFiles(self._root).Where({p | now - File.GetLastWriteTime(p) > timeout}).ToArray():
				File.Delete(path)

#TODO: Translate this once we've got database support
/*
class DBStore(Store):
"""Store for saving a session in database
Needs a table with the following columns:
	_sessionID CHAR(128) UNIQUE NOT NULL,
	atime DATETIME NOT NULL default current_timestamp,
	data TEXT
"""
	def constructor(db, table_name):
		self.db = db
		self.table = table_name
	
	def __contains__(key):
		data = self.db.select(self.table, where="_sessionID=$key", vars=locals())
		return bool(list(data)) 

	def __getitem__(key):
		now = datetime.datetime.now()
		try:
			s = self.db.select(self.table, where="_sessionID=$key", vars=locals())[0]
			self.db.update(self.table, where="_sessionID=$key", atime=now, vars=locals())
		except IndexError:
			raise KeyError(key)
		return self.decode(s.data)

	def __setitem__(key, value):
		pickled = self.encode(value)
		now = datetime.datetime.now()
		if key in self:
			self.db.update(self.table, where="_sessionID=$key", data=pickled,atime=now,  vars=locals())
		else:
			self.db.insert(self.table, False, _sessionID=key, atime=now, data=pickled )
				
	def __delitem__(key):
		self.db.delete(self.table, where="_sessionID=$key", vars=locals())

	def cleanup(timeout):
		timeout = datetime.timedelta(timeout/(24.0*60*60)) #timedelta takes numdays as arg
		last_allowed_time = datetime.datetime.now() - timeout
		self.db.delete(self.table, where="$last_allowed_time > atime", vars=locals())
*/

class SessionConfig:
	property CookieName as string
	property CookieDomain as string
	property CookiePath as string
	property HttpOnly as bool
	property IgnoreExpiry as bool
	property IgnoreChangeIP as bool
	property Secure as bool
	property SecretKey as string
	property Timeout as timespan
	property ExpiredMessage as string