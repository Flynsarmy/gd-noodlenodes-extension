#pragma once

#include <functional>
#include <godot_cpp/core/object_id.hpp>

namespace godot {
class NoodleNodes;
}

class NNTickScheduler {
public:
	enum ProcessThread {
		IDLE = 0,
		PHYSICS = 1,
		MANUAL = 2,
	};

	// p_tick_delta is the time since the previous due tick and is only passed on a due step.
	using StepCallback = std::function<bool(double p_delta, double p_tick_delta, bool p_due)>;

	NNTickScheduler();

	// The owner must outlive the scheduler.
	void configure(godot::NoodleNodes *p_owner, StepCallback p_step);

	void set_process_thread(int p_process_thread);
	int get_process_thread() const;

	void set_tick_rate(int p_tick_rate);
	int get_tick_rate() const;

	void rearm();

	void set_hosted(bool p_hosted);
	bool is_hosted() const;

	void on_tree_entered();
	void on_tree_exited();
	void on_enabled_changed(bool p_enabled);

	void update_connections();
	void disconnect_connections();

	void handle_frame_signal(int p_process_thread, double p_delta);

	bool step(int p_process_thread, double p_delta);

	// The host's step for a hosted owner. It applies the rate schedule and the
	// delta accumulation, but never touches the frame signals or the owner's
	// process thread.
	bool step_hosted(double p_delta);

private:
	bool _advance(double p_delta);

	godot::NoodleNodes *_owner;
	StepCallback _step;

	int _process_thread;
	int _tick_rate;
	uint64_t _frame;
	double _elapsed_delta;
	godot::ObjectID _process_tree_id;
	bool _is_hosted;
};
