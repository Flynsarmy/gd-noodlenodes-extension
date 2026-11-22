#include "performance_monitor.h"
#include <godot_cpp/classes/performance.hpp>

using namespace godot;

NNPerformanceMonitor *NNPerformanceMonitor::_singleton = nullptr;

NNPerformanceMonitor::NNPerformanceMonitor() {
	_is_performance_counter_initialized = false;
	_total_time_elapsed_ai_agents_usec = 0;
	_total_time_elapsed_ai_agents_update_behaviour_usec = 0;
	_total_time_elapsed_behaviour_trees_usec = 0;
	_total_time_elapsed_state_trees_usec = 0;
	_total_time_elapsed_htn_usec = 0;
	_current_total_time_elapsed_ai_agents_usec = 0;
	_current_total_time_elapsed_ai_agents_update_behaviour_usec = 0;
	_current_total_time_elapsed_behaviour_trees_usec = 0;
	_current_total_time_elapsed_state_trees_usec = 0;
	_current_total_time_elapsed_htn_usec = 0;
	_singleton = this;
}

NNPerformanceMonitor::~NNPerformanceMonitor() {
}

void NNPerformanceMonitor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("increment_total_time_elapsed_ai_agents_usec", "time_usec"), &NNPerformanceMonitor::increment_total_time_elapsed_ai_agents_usec);
	ClassDB::bind_method(D_METHOD("increment_total_time_elapsed_ai_agents_update_behaviour_usec", "time_usec"), &NNPerformanceMonitor::increment_total_time_elapsed_ai_agents_update_behaviour_usec);
	ClassDB::bind_method(D_METHOD("increment_total_time_elapsed_behaviour_trees_usec", "time_usec"), &NNPerformanceMonitor::increment_total_time_elapsed_behaviour_trees_usec);
	ClassDB::bind_method(D_METHOD("increment_total_time_elapsed_state_trees_usec", "time_usec"), &NNPerformanceMonitor::increment_total_time_elapsed_state_trees_usec);
	ClassDB::bind_method(D_METHOD("increment_total_time_elapsed_htn_usec", "time_usec"), &NNPerformanceMonitor::increment_total_time_elapsed_htn_usec);

	ClassDB::bind_method(D_METHOD("initialize_performance_counters"), &NNPerformanceMonitor::initialize_performance_counters);
	ClassDB::bind_method(D_METHOD("update_performance_counters"), &NNPerformanceMonitor::update_performance_counters);

	ClassDB::bind_method(D_METHOD("get_total_time_elapsed_ai_agents_usec"), &NNPerformanceMonitor::get_total_time_elapsed_ai_agents_usec);
	ClassDB::bind_method(D_METHOD("get_total_time_elapsed_ai_agents_update_behaviour_usec"), &NNPerformanceMonitor::get_total_time_elapsed_ai_agents_update_behaviour_usec);
	ClassDB::bind_method(D_METHOD("get_total_time_elapsed_behaviour_trees_usec"), &NNPerformanceMonitor::get_total_time_elapsed_behaviour_trees_usec);
	ClassDB::bind_method(D_METHOD("get_total_time_elapsed_state_trees_usec"), &NNPerformanceMonitor::get_total_time_elapsed_state_trees_usec);
	ClassDB::bind_method(D_METHOD("get_total_time_elapsed_htn_usec"), &NNPerformanceMonitor::get_total_time_elapsed_htn_usec);
}

// Getters and setters.

int NNPerformanceMonitor::get_current_total_time_elapsed_ai_agents_usec() const {
	return _current_total_time_elapsed_ai_agents_usec;
}

int NNPerformanceMonitor::get_current_total_time_elapsed_ai_agents_update_behaviour_usec() const {
	return _current_total_time_elapsed_ai_agents_update_behaviour_usec;
}

int NNPerformanceMonitor::get_current_total_time_elapsed_behaviour_trees_usec() const {
	return _current_total_time_elapsed_behaviour_trees_usec;
}

int NNPerformanceMonitor::get_current_total_time_elapsed_state_trees_usec() const {
	return _current_total_time_elapsed_state_trees_usec;
}

int NNPerformanceMonitor::get_current_total_time_elapsed_htn_usec() const {
	return _current_total_time_elapsed_htn_usec;
}

int NNPerformanceMonitor::get_total_time_elapsed_ai_agents_usec() const {
	return _total_time_elapsed_ai_agents_usec;
}

int NNPerformanceMonitor::get_total_time_elapsed_ai_agents_update_behaviour_usec() const {
	return _total_time_elapsed_ai_agents_update_behaviour_usec;
}

int NNPerformanceMonitor::get_total_time_elapsed_behaviour_trees_usec() const {
	return _total_time_elapsed_behaviour_trees_usec;
}

int NNPerformanceMonitor::get_total_time_elapsed_state_trees_usec() const {
	return _total_time_elapsed_state_trees_usec;
}

int NNPerformanceMonitor::get_total_time_elapsed_htn_usec() const {
	return _total_time_elapsed_htn_usec;
}

// Handling methods.

void NNPerformanceMonitor::increment_total_time_elapsed_ai_agents_usec(uint64_t time_usec) {
	_current_total_time_elapsed_ai_agents_usec += time_usec;
}

void NNPerformanceMonitor::increment_total_time_elapsed_ai_agents_update_behaviour_usec(uint64_t time_usec) {
	_current_total_time_elapsed_ai_agents_update_behaviour_usec += time_usec;
}

void NNPerformanceMonitor::increment_total_time_elapsed_behaviour_trees_usec(uint64_t time_usec) {
	_current_total_time_elapsed_behaviour_trees_usec += time_usec;
}

void NNPerformanceMonitor::increment_total_time_elapsed_state_trees_usec(uint64_t time_usec) {
	_current_total_time_elapsed_state_trees_usec += time_usec;
}

void NNPerformanceMonitor::increment_total_time_elapsed_htn_usec(uint64_t time_usec) {
	_current_total_time_elapsed_htn_usec += time_usec;
}

void NNPerformanceMonitor::initialize_performance_counters() {
#ifdef DEBUG_ENABLED
	if (_is_performance_counter_initialized)
		return;
	Performance *perf = godot::Performance::get_singleton();
	if (perf == nullptr)
		return;
	perf->add_custom_monitor("NNPerformanceMonitor/AI Agent evaluate options time usec", Callable(this, "get_total_time_elapsed_ai_agents_usec"));
	perf->add_custom_monitor("NNPerformanceMonitor/AI Agent update behaviour time usec", Callable(this, "get_total_time_elapsed_ai_agents_update_behaviour_usec"));
	perf->add_custom_monitor("NNPerformanceMonitor/Behaviour Tree tick time usec", Callable(this, "get_total_time_elapsed_behaviour_trees_usec"));
	perf->add_custom_monitor("NNPerformanceMonitor/State Tree tick time usec", Callable(this, "get_total_time_elapsed_state_trees_usec"));
	perf->add_custom_monitor("NNPerformanceMonitor/HTN tick time usec", Callable(this, "get_total_time_elapsed_htn_usec"));
	_is_performance_counter_initialized = true;
#endif
}

void NNPerformanceMonitor::update_performance_counters() {
	_total_time_elapsed_ai_agents_usec = _current_total_time_elapsed_ai_agents_usec;
	_total_time_elapsed_ai_agents_update_behaviour_usec = _current_total_time_elapsed_ai_agents_update_behaviour_usec;
	_total_time_elapsed_behaviour_trees_usec = _current_total_time_elapsed_behaviour_trees_usec;
	_total_time_elapsed_state_trees_usec = _current_total_time_elapsed_state_trees_usec;
	_total_time_elapsed_htn_usec = _current_total_time_elapsed_htn_usec;
	_current_total_time_elapsed_ai_agents_usec = 0;
	_current_total_time_elapsed_ai_agents_update_behaviour_usec = 0;
	_current_total_time_elapsed_behaviour_trees_usec = 0;
	_current_total_time_elapsed_state_trees_usec = 0;
	_current_total_time_elapsed_htn_usec = 0;
}