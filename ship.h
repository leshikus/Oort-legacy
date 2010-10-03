#include <complex.h>
#include <lua.h>
#include <lauxlib.h>
#include <glib.h>

#ifndef SHIP_H
#define SHIP_H

struct ship_class {
	const char *name;
	double radius;
	double hull;
	int count_for_victory;
};

#define TAIL_SEGMENTS 16
#define TAIL_TICKS 4
#define API_ID_SIZE 8
#define MAX_DEBUG_LINES 32

struct ship {
	const char api_id[API_ID_SIZE];
	const struct ship_class *class;
	struct team *team;
	struct physics *physics;
	double energy, hull;
	lua_State *lua, *global_lua;
	struct {
		lua_Alloc allocator;
		void *allocator_ud;
		int cur, limit;
	} mem;
	GRand *prng;
	int dead, ai_dead;
	complex double tail[TAIL_SEGMENTS];
	int tail_head;
	int last_shot_tick;
	GQueue *mq;
	guint64 line_start_time;
	char line_info[256];
	struct {
		int num_lines;
		struct {
			vec2 a, b;
		} lines[MAX_DEBUG_LINES];
	} debug;
};

extern const struct ship_class fighter, mothership;
extern GList *all_ships;

struct ship *ship_create(const char *filename, const char *class_name, const char *orders);
void ship_purge();
void ship_shutdown();
void ship_tick(double t);
int load_ship_classes(const char *filename);
double ship_get_energy(struct ship *s);

#endif
