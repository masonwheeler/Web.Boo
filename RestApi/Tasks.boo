namespace RestApi

import System
import Boo.Adt
import Boo.Web
import Newtonsoft.Json.Linq

// Implementing the basic RESTful API defined in the first half of the tutorial at:
// https://blog.miguelgrinberg.com/post/designing-a-restful-api-with-python-and-flask
// Still on the todo list: everything from the "Improving the web service interface"
// heading and below

let tasks = [
	{
		'id': 1,
		'title': 'Buy groceries',
		'description': 'Milk, Cheese, Pizza, Fruit, Tylenol', 
		'done': false
	},
	{
		'id': 2,
		'title': 'Learn Boo',
		'description': 'Need to find a good Boo tutorial on the web', 
		'done': false
	}
]

[WebBoo('/todo/api/v1.0/tasks')]
class Tasks:
	def Get():
		return Hash2JSON({'tasks': tasks})

	def Post(values):
		var json = JsonData() as JObject
		
		if not json or not json['title']:
			Abort(400)
		task = {
		    'id': ((tasks[-1] as Hash)['id'] cast int) + 1,
		    'title': json['title'],
		    'description': json['description'] or "",
		    'done': false
		}
		tasks.Add(task)
		Response.StatusCode = 201
		return jsonify({'task': task})

[WebBoo("/todo/api/v1.0/tasks/${task_id as int}")]
class Task:
	def Get(task_id as int):
		var task = [taskItem for taskItem as Hash in tasks if taskItem['id'] == task_id]
		if len(task) == 0:
			Abort(404)
		return jsonify({'task': task[0]})

	def Put(task_id as int, values):
		var lTasks = [taskItem for taskItem as Hash in tasks if taskItem['id'] == task_id]
		Abort(404) if len(lTasks) == 0
		var json = JsonData() as JObject
		Abort(404) if not json
		Abort(400) if json['title'] and (json['title'].Type != JTokenType.String)
		Abort(400) if json['description'] and (json['description'].Type != JTokenType.String)
		Abort(400) if json['done'] and (json['done'].Type != JTokenType.Boolean)
		var task = lTasks[0] as Hash
		task['title'] = json['title'] or task['title']
		task['description'] = json['description'] or task['description']
		task['done'] = json['done'] or task['done']
		return jsonify({'task': task})

	def Delete(task_id as int):
		var task = [taskItem for taskItem as Hash in tasks if taskItem['id'] == task_id]
		if len(task) == 0:
			Abort(404)
		tasks.Remove(task[0])
		return jsonify({'result': true})
