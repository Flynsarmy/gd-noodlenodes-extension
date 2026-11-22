#include "nqs_threading.h"

#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

NNNQSWorkerJob::~NNNQSWorkerJob() {
	wait();
}

void NNNQSWorkerJob::start(uint32_t p_count, uint32_t p_chunk_size, std::function<void(uint32_t, uint32_t)> &&p_work, const String &p_description) {
	wait();
	ERR_FAIL_COND(p_chunk_size == 0);
	_work = std::move(p_work);
	_count = p_count;
	_chunk_size = p_chunk_size;
	const uint32_t chunks = (p_count + p_chunk_size - 1) / p_chunk_size;
	_group_id = WorkerThreadPool::get_singleton()->add_native_group_task(&NNNQSWorkerJob::_run_chunk, this, (int)chunks, -1, false, p_description);
}

bool NNNQSWorkerJob::is_started() const {
	return _group_id >= 0;
}

bool NNNQSWorkerJob::poll() {
	if (_group_id < 0) {
		return true;
	}
	if (!WorkerThreadPool::get_singleton()->is_group_task_completed(_group_id)) {
		return false;
	}
	wait();
	return true;
}

void NNNQSWorkerJob::wait() {
	if (_group_id < 0) {
		return;
	}
	// A completed group task still has to be waited on to release it.
	WorkerThreadPool::get_singleton()->wait_for_group_task_completion(_group_id);
	_group_id = -1;
	_work = nullptr;
}

void NNNQSWorkerJob::_run_chunk(void *p_userdata, uint32_t p_chunk) {
	NNNQSWorkerJob *job = static_cast<NNNQSWorkerJob *>(p_userdata);
	const uint32_t begin = p_chunk * job->_chunk_size;
	const uint32_t end = MIN(begin + job->_chunk_size, job->_count);
	job->_work(begin, end);
}
