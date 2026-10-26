extends Node
## ProceduralJobRunner.gd
## Dispatches heavy procedural generation (SimpleXTerrain, godot-wfc, ProtonScatter, Voxel meshing)
## onto Godot 4's native WorkerThreadPool so _ready() never blocks the main frame loop.

signal job_completed(job_id: String, result: Variant)

var _active_tasks: Dictionary = {}

func run_on_worker_thread(job_id: String, callable_task: Callable, on_complete: Callable = Callable()) -> int:
	var bound_task := Callable(self, "_execute_worker_task").bind(job_id, callable_task, on_complete)
	var task_id: int = WorkerThreadPool.add_task(bound_task, false, job_id)
	_active_tasks[job_id] = task_id
	return task_id

func _execute_worker_task(job_id: String, callable_task: Callable, on_complete: Callable) -> void:
	var output: Variant = callable_task.call()
	call_deferred("_finalize_job", job_id, output, on_complete)

func _finalize_job(job_id: String, result: Variant, on_complete: Callable) -> void:
	if _active_tasks.has(job_id):
		var tid: int = _active_tasks[job_id]
		WorkerThreadPool.wait_for_task_completion(tid)
		_active_tasks.erase(job_id)
	if on_complete.is_valid():
		on_complete.call(result)
	job_completed.emit(job_id, result)

func is_job_running(job_id: String) -> bool:
	return _active_tasks.has(job_id)

func _exit_tree() -> void:
	for job_id in _active_tasks.keys():
		var tid: int = _active_tasks[job_id]
		WorkerThreadPool.wait_for_task_completion(tid)
	_active_tasks.clear()
