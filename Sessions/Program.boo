namespace Sessions

import System
import Boo.Web

[WebBoo('/')]
class Homepage:
	def Get():
		var visits = int.Parse(SessionData['Visits']) + 1
		SessionData['Visits'] = visits.ToString()
		return "Total visits: $visits"

var store = DiskStore(System.IO.Path.Combine(WebBooClass.EXE_DIR, 'Sessions'))
Application(store, {s as Session | s['Visits'] = '0'}, 'http://localhost:2468/').Run()