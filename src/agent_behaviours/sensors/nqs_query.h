#pragma once

#include "../../node_query_system/node_query_system.h"
#include "../../node_query_system/search_spaces/nqs.h"
#include "../sensor.h"
#include <godot_cpp/core/object.hpp>

namespace godot {

class NNNQSQuerySensor : public NNSensor {
	GDCLASS(NNNQSQuerySensor, NNSensor)

private:
	enum class QueryState { IDLE,
		RUNNING };

	ObjectID _nqs_search_space_cache;

	bool _is_high_priority;
	String _best_result_key;

	QueryState _query_state;
	// A nonzero token identifies the registration this sensor posted.
	uint64_t _posted_query_registration;
	Callable _query_completed_callable;

	NNNQSSearchSpaces *_resolve_nqs_search_space() const;
	bool _connect_query_completed(NNNQSSearchSpaces *p_search_space);
	void _on_query_completed(Object *p_search_space, int64_t p_query_registration);
	void _cancel_posted_query();

protected:
	static void _bind_methods();

	virtual float evaluate_sensor_value() override;
	virtual void uninitialize_sensor() override;
	virtual void _on_is_enabled_changed(bool p_is_enabled) override;

public:
	NNNQSQuerySensor();
	~NNNQSQuerySensor();

	// Getters and setters for attributes.

	void set_nqs_search_space(NNNQSSearchSpaces *nqs_search_space);
	NNNQSSearchSpaces *get_nqs_search_space() const;

	void set_is_high_priority(bool is_high_priority);
	bool get_is_high_priority() const;

	void set_best_result_key(const String &best_result_key);
	String get_best_result_key() const;
};

} //namespace godot
