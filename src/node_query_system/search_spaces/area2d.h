#pragma once

#include "area_search_space.h"
#include "nqs.h"
#include <godot_cpp/classes/area2d.hpp>

namespace godot {

class NNArea2DSearchSpace : public NNNQSSearchSpaces {
	GDCLASS(NNArea2DSearchSpace, NNNQSSearchSpaces)

private:
	AreaSearchSpaceCore<Area2D> _core;

protected:
	static void _bind_methods();

	virtual void _initialize_search_space() override;
	virtual void _uninitialize_search_space() override;

public:
	void on_area_entered(Area2D *area);
	void on_area_exited(Area2D *area);

	// Getters and setters for attributes.

	void set_area2d(Area2D *area2d);
	Area2D *get_area2d() const;

	void set_intersecting_areas(TypedArray<Area2D> intersecting_areas);
	TypedArray<Area2D> get_intersecting_areas() const;

	virtual TypedArray<Node> get_searchspace_nodes() const override;
};

} //namespace godot
