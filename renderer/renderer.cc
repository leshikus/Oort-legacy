#include "renderer/renderer.h"
#include <boost/scoped_ptr.hpp>
#include <boost/foreach.hpp>
#include <stdint.h>

#include "glm/glm.hpp"
#include "glm/gtc/type_ptr.hpp"
#include "glm/gtc/matrix_transform.hpp"
#include "glm/gtx/string_cast.hpp"
#include <Box2D/Box2D.h>

#include "sim/ship.h"
#include "sim/ship_class.h"
#include "sim/bullet.h"
#include "sim/team.h"
#include "common/log.h"
#include "common/resources.h"
#include "gl/program.h"
#include "gl/shader.h"
#include "gl/buffer.h"
#include "gl/texture.h"
#include "gl/check.h"
#include "renderer/font.h"

using glm::vec2;
using std::make_shared;
using std::shared_ptr;
using boost::scoped_ptr;

namespace Oort {

Renderer::Renderer(shared_ptr<Game> game)
  : game(game),
    prog(new GL::Program(
      make_shared<GL::VertexShader>(load_resource("shaders/ship.v.glsl")),
      make_shared<GL::FragmentShader>(load_resource("shaders/ship.f.glsl")))),
    text_prog(new GL::Program(
      make_shared<GL::VertexShader>(load_resource("shaders/text.v.glsl")),
      make_shared<GL::FragmentShader>(load_resource("shaders/text.f.glsl"))))
{
	vertex_buf.data(fighter->vertices);
	load_font();
}

void Renderer::load_font() {
	font_tex.bind();
	GL::check();
	glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
	GL::check();
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	GL::check();
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	GL::check();
	const int n = 256;
	unsigned char data[64*n];
	for (int i = 0; i < n; i++) {
		for (int x = 0; x < 8; x++) {
			for (int y = 0; y < 8; y++) {
				uint8 row = oort_font[8*i+y];
				bool on = ((row >> x) & 1) == 1;
				data[n*8*y + 8*i + x] = on ? 255 : 0;
			}
		}
	}
	glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, n*8, 8, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, data);
	GL::check();
	GL::Texture::unbind();
	GL::check();
}

void Renderer::render(float view_radius,
                      float aspect_ratio,
                      glm::vec2 view_center) {
	GL::check();
	glClear(GL_COLOR_BUFFER_BIT);
	prog->use();
	glEnableVertexAttribArray(prog->attrib_location("vertex"));
	GL::check();

	glEnable(GL_POINT_SPRITE);
	glEnable(GL_PROGRAM_POINT_SIZE);
	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glShadeModel(GL_SMOOTH);
	glEnable(GL_LINE_SMOOTH);
	glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
	glLineWidth(1.2f);

	glm::mat4 p_matrix = glm::ortho(view_center.x - view_radius,
	                                view_center.x + view_radius,
	                                view_center.y - view_radius/aspect_ratio,
	                                view_center.y + view_radius/aspect_ratio);

	prog->uniform("p_matrix", p_matrix);

	BOOST_FOREACH(auto ship, game->ships) {
		glm::mat4 mv_matrix;
		auto p = ship->body->GetPosition();
		auto h = ship->body->GetAngle();
		mv_matrix = glm::translate(mv_matrix, glm::vec3(p.x, p.y, 0));
		mv_matrix = glm::rotate(mv_matrix, glm::degrees(h), glm::vec3(0, 0, 1));
		glm::vec4 color(ship->team->color, 0.7f);
		GL::check();

		prog->uniform("mv_matrix", mv_matrix);
		prog->uniform("color", color);
		vertex_buf.bind();
		glVertexAttribPointer(prog->attrib_location("vertex"),
		                      2, GL_FLOAT, GL_FALSE, 0, 0);
		vertex_buf.unbind();
		GL::check();

		glDrawArrays(GL_LINE_LOOP, 0, 3);
		GL::check();
	}

	BOOST_FOREACH(auto bullet, game->bullets) {
		glm::mat4 mv_matrix;
		auto p = bullet->body->GetPosition();
		auto h = bullet->body->GetAngle();
		mv_matrix = glm::translate(mv_matrix, glm::vec3(p.x, p.y, 0));
		mv_matrix = glm::rotate(mv_matrix, glm::degrees(h), glm::vec3(0, 0, 1));
		mv_matrix = glm::scale(mv_matrix, glm::vec3(0.1f, 0.1f, 0.1f));
		glm::vec4 color(bullet->team->color, 0.4f);
		GL::check();

		prog->uniform("mv_matrix", mv_matrix);
		prog->uniform("color", color);
		vertex_buf.bind();
		glVertexAttribPointer(prog->attrib_location("vertex"),
		                      2, GL_FLOAT, GL_FALSE, 0, 0);
		vertex_buf.unbind();
		GL::check();

		glDrawArrays(GL_LINE_LOOP, 0, 3);
		GL::check();
	}

	glDisableVertexAttribArray(prog->attrib_location("vertex"));
	GL::Program::clear();
	GL::check();
}

// XXX
static constexpr float screen_width = 1600;
static constexpr float screen_height = 900;

static vec2 pixel2screen(vec2 p) {
	return vec2((float) (2*p.x/screen_width-1),
	            (float) (-2*p.y/screen_height+1));
}

void Renderer::text(int x, int y, const std::string &str) {
	auto pos = pixel2screen(vec2(x,y));
	auto spacing = 9.0f;
	auto n = str.length();

	auto chars = new float[n];
	auto indices = new float[n];
	for (unsigned int i = 0; i < n; i++) {
		chars[i] = (float) str[i];
		indices[i] = (float) i;
	}

	text_prog->use();
	font_tex.bind();
	glUniform1i(text_prog->uniform_location("tex"), 0);
	glUniform1f(text_prog->uniform_location("dist"), 2.0f*spacing/screen_width);
	glUniform2f(text_prog->uniform_location("position"), (float)pos.x, (float)pos.y);
	glVertexAttribPointer(text_prog->attrib_location("character"), 1, GL_FLOAT, false, 0, chars);
	glVertexAttribPointer(text_prog->attrib_location("index"), 1, GL_FLOAT, false, 0, indices);
	glEnableVertexAttribArray(text_prog->attrib_location("character"));
	glEnableVertexAttribArray(text_prog->attrib_location("index"));
	glDrawArrays(GL_POINTS, 0, (GLsizei) str.length());
	glDisableVertexAttribArray(text_prog->attrib_location("character"));
	glDisableVertexAttribArray(text_prog->attrib_location("index"));
	glUseProgram(0);
	GL::check();

	delete[](chars);
	delete[](indices);
}

}
