// Copyright 2011 Rich Lane
#include "sim/ship_class.h"

#include <iostream>
#include <boost/foreach.hpp>

namespace Oort {

ShipClass *fighter;

void ShipClass::initialize() {
	std::vector<glm::vec2> vertices = { glm::vec2(-0.7, -0.71),
	                                    glm::vec2(1, 0),
	                                    glm::vec2(-0.7, 0.71) };
	fighter = new ShipClass(vertices, 10e3);
}

ShipClass::ShipClass(std::vector<glm::vec2> _vertices, float mass)
	: vertices(_vertices),
    mass(mass) {
	shape.Set((b2Vec2*) &vertices[0], vertices.size());

	// calculate density for desired mass
	b2MassData md;
	shape.ComputeMass(&md, 1);
	density = mass/md.mass;

	// move center of mass to local origin
	BOOST_FOREACH(glm::vec2 &v, vertices) {
		v -= glm::vec2(md.center.x, md.center.y);
	}
	shape.Set((b2Vec2*) &vertices[0], vertices.size());
}

}