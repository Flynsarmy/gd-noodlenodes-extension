#pragma once

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <cstdint>
#include <functional>

namespace godot {

// Copied off the Node so worker threads never read scene data.
struct NNNQSCandidate {
	enum Kind : uint8_t {
		OTHER,
		NODE_2D,
		NODE_3D,
	};
	Kind kind = OTHER;
	Transform2D global_transform_2d;
	Transform3D global_transform_3d;
};

// Runs on worker threads, so it must not touch any Object other than resources it owns.
class NNNQSThreadedCriterion {
public:
	virtual ~NNNQSThreadedCriterion() = default;
	// r_filter_out and r_score arrive as false and 1.0 and stay so for a candidate of the wrong kind.
	virtual void evaluate(const NNNQSCandidate &p_candidate, bool &r_filter_out, float &r_score) const = 0;
};

// Destruction waits for the task, so the work never outlives what it captured.
class NNNQSWorkerJob {
public:
	NNNQSWorkerJob() = default;
	NNNQSWorkerJob(const NNNQSWorkerJob &) = delete;
	NNNQSWorkerJob &operator=(const NNNQSWorkerJob &) = delete;
	~NNNQSWorkerJob();

	void start(uint32_t p_count, uint32_t p_chunk_size, std::function<void(uint32_t, uint32_t)> &&p_work, const String &p_description);
	bool is_started() const;
	bool poll();
	void wait();

private:
	static void _run_chunk(void *p_userdata, uint32_t p_chunk);

	std::function<void(uint32_t, uint32_t)> _work;
	uint32_t _count = 0;
	uint32_t _chunk_size = 1;
	int64_t _group_id = -1;
};

} //namespace godot
