namespace Boo.Web

import System

interface IMailer:
	def SendMail(sender as string, recipient as string, subject as string, body as string) as System.Threading.Tasks.Task
