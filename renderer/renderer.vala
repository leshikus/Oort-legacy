using GL;
using Vector;
using Math;

namespace Oort {
	public class Renderer {
		public bool render_all_debug_lines = false;
		public int screen_width = 640;
		public int screen_height = 480;
		public double view_scale;
		public Vec2 view_pos;
		public unowned Ship picked = null;
		public Game game;
		public bool follow_picked = false;
		public RenderPerf perf;
		public bool debug = true;

		public Mat4f p_matrix;
		public Rand prng;
		public List<ParticleBunch> particle_bunches;

		Texture font_tex;
		ShaderProgram ship_program;
		ShaderProgram beam_program;
		ShaderProgram text_program;
		Model circle_model;
		RenderBatch[] batches;

		const int MAX_PARTICLE_BUNCHES = 32;

		public static void static_init() {
			Oort.Ship.gfx_create_cb = on_ship_created;

/*
			print("Vendor: %s\n", glGetString(GL_VENDOR));
			print("Renderer: %s\n", glGetString(GL_RENDERER));
			print("GL Version: %s\n", glGetString(GL_VERSION));
			print("GLSL Version: %s\n", glGetString(GL_SHADING_LANGUAGE_VERSION));
			print("Extensions:\n%s\n", glGetString(GL_EXTENSIONS));
*/
		}

		public Renderer(Game game,
		                double initial_view_scale) {
			this.game = game;
			view_scale = initial_view_scale;
			prng = new Rand();
			view_pos = vec2(0,0);
			perf = new RenderPerf();

			circle_model = Model.load("circle");
			particle_bunches = new List<ParticleBunch>();

			batches = {
				new ParticleBatch(),
				new BoundaryBatch(),
				new ShipBatch(),
				new TailBatch(),
				new BulletBatch(),
				new BeamBatch()
			};
		}

		public void init() {
			glClearColor(0.0f, 0.0f, 0.03f, 0.0f);
			glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
			gl_platform_init();
			glLineWidth(1.2f);

			try {
				load_shaders();
			} catch (ShaderError e) {
				GLib.error("loading shaders failed:\n%s", e.message);
			}

			load_font();

			foreach (RenderBatch batch in batches) {
				batch.game = game;
				batch.renderer = this;
				try {
					batch.init();
				} catch (Error e) {
					GLib.error("loading batch failed:\n%s", e.message);
				}
			}
		}

		public void load_font() {
			var tex = new Texture();
			tex.bind();
			glCheck();
			glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
			glCheck();
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
			glCheck();
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glCheck();
			var n = 256;
			var data = new uint8[64*n];
			for (int i = 0; i < n; i++) {
				for (int x = 0; x < 8; x++) {
					for (int y = 0; y < 8; y++) {
						uint8 row = font[8*i+y];
						bool on = ((row >> x) & 1) == 1;
						data[n*8*y + 8*i + x] = on ? 255 : 0;
					}
				}
			}
			glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, n*8, 8, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, data);
			glCheck();
			glBindTexture(GL_TEXTURE_2D, 0);
			glCheck();
			font_tex = tex;
		}

		public void load_shaders() throws ShaderError{
			ship_program = new ShaderProgram.from_resources("ship");
			beam_program = new ShaderProgram.from_resources("beam");
			text_program = new ShaderProgram.from_resources("text");
		}

		public void render() {
			Util.toggle_callgrind_collection();
			prng.set_seed(0); // XXX tick seed
			TimeVal start_time = TimeVal();

			glEnable(GL_BLEND);
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
			glFinish();

			Mat4f.load_simple_ortho(out p_matrix,
			                        (float)this.view_pos.x,
			                        (float)this.view_pos.y,
			                        (float)screen_height/(float)screen_width,
			                        (float)(2000.0/view_scale));


			if (follow_picked && picked != null) {
				view_pos = picked.physics.p;
			}

			foreach (RenderBatch batch in batches) {
				batch.do_render();
			}

			foreach (unowned Ship s in game.all_ships) {
				render_debug_lines(s);
			}
			
			if (picked != null) {
				if (picked.dead) {
					picked = null;
				} else {
					render_picked_circle(picked);
					render_picked_acceleration(picked);
					render_picked_path(picked);
					render_picked_info(picked);
				}
			}

			glFinish();
			perf.update_from_time(start_time);
			Util.toggle_callgrind_collection();
		}

		public void render_text(int x, int y, string text) {
			var prog = text_program;
			var pos = pixel2screen(vec2(x,y));
			var spacing = 9.0f;

			var chars = new float[text.length];
			var indices = new float[text.length];
			for (int i = 0; i < text.length; i++) {
				chars[i] = (float) text[i];
				indices[i] = (float) i;
			}

			prog.use();
			font_tex.bind();
			glUniform1i(prog.u("tex"), 0);
			glUniform1f(prog.u("dist"), 2.0f*spacing/screen_width);
			glUniform2f(prog.u("position"), (float)pos.x, (float)pos.y);
			glVertexAttribPointer(prog.a("character"), 1, GL_FLOAT, false, 0, chars);
			glVertexAttribPointer(prog.a("index"), 1, GL_FLOAT, false, 0, indices);
			glEnableVertexAttribArray(prog.a("character"));
			glEnableVertexAttribArray(prog.a("index"));
			glDrawArrays(GL_POINTS, 0, (GLsizei) text.length);
			glDisableVertexAttribArray(prog.a("character"));
			glDisableVertexAttribArray(prog.a("index"));
			glUseProgram(0);
			glCheck();
		}

		void render_debug_lines(Ship s) {
			if (s != picked && !render_all_debug_lines) {
				return;
			}

			var prog = ship_program;
			prog.use();
			glCheck();
			Mat4f mv_matrix;
			Mat4f.load_identity(out mv_matrix);
			glUniformMatrix4fv(prog.u("mv_matrix"), 1, false, mv_matrix.data);
			glUniformMatrix4fv(prog.u("p_matrix"), 1, false, p_matrix.data);
			glUniform4f(prog.u("color"), 0.29f, 0.83f, 0.8f, 0.66f);
			var vertices = new float[s.debug.num_lines*4];
			for (int j = 0; j < s.debug.num_lines; j++) {
				var a = s.debug.lines[j].a;
				var b = s.debug.lines[j].b;
				vertices[4*j+0] = (float)a.x;
				vertices[4*j+1] = (float)a.y;
				vertices[4*j+2] = (float)b.x;
				vertices[4*j+3] = (float)b.y;
			}
			glVertexAttribPointer(prog.a("vertex"), 2, GL_FLOAT, false, 0, vertices);
			glEnableVertexAttribArray(prog.a("vertex"));
			glDrawArrays(GL_LINES, 0, (GLsizei) s.debug.num_lines*2);
			glDisableVertexAttribArray(prog.a("vertex"));
			glUseProgram(0);
			glCheck();
		}

		void render_picked_circle(Ship s) {
			var prog = ship_program;
			var shape = circle_model.shapes[0];
			prog.use();
			Mat4f rotation_matrix;
			Mat4f translation_matrix;
			Mat4f scale_matrix;
			Mat4f mv_matrix;
			Mat4f tmp_matrix;
			Mat4f.load_rotation(out rotation_matrix, (float)s.physics.h, 0, 0, 1);
			Mat4f.load_translation(out translation_matrix, (float)s.physics.p.x, (float)s.physics.p.y, 0);
			Mat4f.load_scale(out scale_matrix, (float)s.class.radius, (float)s.class.radius, (float)s.class.radius);
			Mat4f.multiply(out tmp_matrix, ref rotation_matrix, ref scale_matrix);
			Mat4f.multiply(out mv_matrix, ref translation_matrix, ref tmp_matrix);
			glBindBuffer(GL_ARRAY_BUFFER, shape.buffer);
			glVertexAttribPointer(prog.a("vertex"), 2, GL_FLOAT, false, 0, (void*) 0);
			glEnableVertexAttribArray(prog.a("vertex"));
			glUniform4f(prog.u("color"), 0.8f, 0.8f, 0.8f, 0.67f);
			glUniformMatrix4fv(prog.u("mv_matrix"), 1, false, mv_matrix.data);
			glDrawArrays(GL_LINE_LOOP, 0, (GLsizei) shape.vertices.length);
			glDisableVertexAttribArray(prog.a("vertex"));
			glBindBuffer(GL_ARRAY_BUFFER, 0);
			glUseProgram(0);
			glCheck();
		}

		void render_picked_acceleration(Ship s) {
			float vertices[4] = { 0, 0, (float)s.physics.acc.x, (float)s.physics.acc.y };
			var prog = ship_program;
			prog.use();
			Mat4f rotation_matrix;
			Mat4f translation_matrix;
			Mat4f mv_matrix;
			Mat4f.load_rotation(out rotation_matrix, (float)s.physics.h, 0, 0, 1);
			Mat4f.load_translation(out translation_matrix, (float)s.physics.p.x, (float)s.physics.p.y, 0);
			Mat4f.multiply(out mv_matrix, ref translation_matrix, ref rotation_matrix);
			glVertexAttribPointer(prog.a("vertex"), 2, GL_FLOAT, false, 0, vertices);
			glEnableVertexAttribArray(prog.a("vertex"));
			glUniform4f(prog.u("color"), 0.8f, 0.8f, 0.8f, 0.46f);
			glUniformMatrix4fv(prog.u("mv_matrix"), 1, false, mv_matrix.data);
			glDrawArrays(GL_LINE_LOOP, 0, 2);
			glDisableVertexAttribArray(prog.a("vertex"));
			glUseProgram(0);
			glCheck();
		}

		void render_picked_path(Ship s) {
			int n = (int) (1/Game.TICK_LENGTH);
			float[] vertices = new float[n*2];
			Physics q = s.physics.copy();
			for (int j = 0; j < n; j++) {
				vertices[j*2+0] = (float) q.p.x;
				vertices[j*2+1] = (float) q.p.y;
				q.tick_one();
			}

			var prog = ship_program;
			prog.use();
			Mat4f mv_matrix;
			Mat4f.load_identity(out mv_matrix);
			glVertexAttribPointer(prog.a("vertex"), 2, GL_FLOAT, false, 0, vertices);
			glEnableVertexAttribArray(prog.a("vertex"));
			glUniform4f(prog.u("color"), 0.29f, 0.83f, 0.8f, 0.66f);
			glUniformMatrix4fv(prog.u("mv_matrix"), 1, false, mv_matrix.data);
			glDrawArrays(GL_LINE_STRIP, 0, (GLsizei) n);
			glDisableVertexAttribArray(prog.a("vertex"));
			glUseProgram(0);
			glCheck();
		}

		private string fmt(double v, string unit) {
			var i = 0;
			var sign = v < 0 ? -1 : 1;
			var prefixes = " kMGTPEZY";
			for (i = 0; i < prefixes.length && sign*v >= 1000; i++) {
				v /= 1000;
			}
			if (sign*v < 1e-9) {
				v = 0;
			}
			var prefix = i == 0 ? "" : "%c".printf((int)prefixes[i]);
			return "%0.3g %s%s".printf(v, prefix, unit);
		}

		private void render_picked_info(Ship s) {
			int x = 15;
			int dy = 12;
			int y = screen_height - 22 - 11*dy;
			var rv = s.physics.v.rotate(-s.physics.h);
			textf(x, y+0*dy, "%s %s %s", s.class.name, s.hex_id, s.controlled ? "(player controlled)" : "");
			textf(x, y+1*dy, "hull: %s", fmt(s.hull,"J"));
			textf(x, y+2*dy, "position: (%s, %s)", fmt(s.physics.p.x,"m"), fmt(s.physics.p.y,"m"));
			textf(x, y+3*dy, "heading: %s", fmt(s.physics.h,"rad"));
			textf(x, y+4*dy, "velocity: (%s, %s) rel=(%s, %s)",
			                 fmt(s.physics.v.x,"m/s"), fmt(s.physics.v.y,"m/s"),
			                 fmt(rv.x,"m/s"), fmt(rv.y,"m/s"));
			textf(x, y+5*dy, "angular velocity: %s", fmt(s.physics.w,"rad/s"));
			textf(x, y+6*dy, "acceleration:");
			textf(x, y+7*dy, " main: %s", fmt(s.physics.acc.x,"m/s\xFD"));
			textf(x, y+8*dy, " lateral: %s", fmt(s.physics.acc.y,"m/s\xFD"));
			textf(x, y+9*dy, " angular: %s", fmt(s.physics.wa,"rad/s\xFD"));
			textf(x, y+10*dy, "energy: %s", fmt(s.get_energy(),"J"));
			textf(x, y+11*dy, "reaction mass: %s", fmt(s.get_reaction_mass()*1000,"g"));
		}

		public void reshape(int width, int height) {
			screen_width = width;
			screen_height = height;
			glViewport (0, 0, (GLsizei)width, (GLsizei)height);
		}

		public void tick() {
			Util.toggle_callgrind_collection();
			tick_particles();
			Util.toggle_callgrind_collection();
		}

		public void tick_particles() {
			float current_time = game.ticks * (float)Game.TICK_LENGTH;
			var bunch = new ParticleBunch(current_time);

			foreach (unowned Bullet b in game.all_bullets) {
				if (b.dead) continue;
				unowned Physics q = b.physics;
				if (b.type == BulletType.PLASMA) {
					bunch.shower(ParticleType.PLASMA,
					             q.p.to_vec2f(),
					             vec2f(0,0), q.v.to_vec2f().scale(0.507f),
					             20.0f, 0.2f, 0.4f, 4);
				} else if (b.type == BulletType.EXPLOSION) {
					if (prng.next_double() < 0.1) {
						bunch.shower(ParticleType.EXPLOSION, q.p.to_vec2f(),
						             vec2f(0,0), q.v.to_vec2f().scale(0.001f),
						             256, 0.16f, 0.53f, 6);
					}
				}
			}
			foreach (unowned BulletHit hit in game.bullet_hits) {
				var n = uint16.max((uint16)(hit.e/10000),1);
				bunch.shower(ParticleType.HIT, hit.cp.to_vec2f(),
				             hit.s.physics.v.to_vec2f(), vec2f(0,0),
				             256, 0.03f, 0.63f, n);
			}

			foreach (unowned BeamHit hit in game.beam_hits) {
				var n = uint16.max((uint16)(hit.e/500),1);
				bunch.shower(ParticleType.HIT, hit.cp.to_vec2f(),
				             hit.s.physics.v.to_vec2f(), vec2f(0,0),
				             256, 0.03f, 0.63f, n);
			}

			foreach (unowned Ship s in game.all_ships) {
				if (s.physics.acc.abs() != 0) {
					var vec_main = vec2(-s.physics.acc.x, 0).rotate(s.physics.h).scale(s.physics.m/1000);
					var vec_lateral = vec2(0, -s.physics.acc.y).rotate(s.physics.h).scale(s.physics.m/1000);
					bunch.shower(ParticleType.ENGINE, s.physics.p.to_vec2f(),
					             s.physics.v.to_vec2f(), vec_main.to_vec2f(),
					             32, 0.06f, 0.13f, 8);
					bunch.shower(ParticleType.ENGINE, s.physics.p.to_vec2f(),
					             s.physics.v.to_vec2f(), vec_lateral.to_vec2f(),
					             32, 0.06f, 0.13f, 8);
				}
			}

			if (particle_bunches.length() > MAX_PARTICLE_BUNCHES) {
				unowned List<ParticleBunch> link = particle_bunches.first();
				link.data = null;
				particle_bunches.delete_link(link);
			}

			if (bunch.count > 0) {
				particle_bunches.append(bunch);
			}
		}

		public Vec2 pixel2screen(Vec2 p) {
			return vec2((float) (2*p.x/screen_width-1),
			            (float) (-2*p.y/screen_height+1));
		}

		public Vec2 W(Vec2 o) {
			Mat4f m;
			Vec2 screen_coord = pixel2screen(o);
			Vec4f v = vec4f((float)screen_coord.x, (float)screen_coord.y, 0, 0);
			Mat4f.invert(out m, ref p_matrix);
			var v2 = v.transform(ref m);
			v2.x += (float)view_pos.x;
			v2.y += (float)view_pos.y;
			return vec2(v2.x, v2.y);
		}

		// XXX find ship with minimum distance, allow 5 px error
		public void pick(int x, int y) {
			Vec2 p = W(vec2(x, y));
			picked = null;
			double min_dist = 10/view_scale;
			foreach (unowned Ship s in game.all_ships) {
				var dist = s.physics.p.distance(p);
				if (!s.dead && ((dist < min_dist) || (picked == null && dist < s.physics.r))) {
					picked = s;
					if (dist < min_dist) min_dist = dist;
				}
			}
		}

		// XXX const
		double zoom_force = 0.1;
		double min_view_scale = 0.05;
		double max_view_scale = 6.0;

		public void zoom(int x, int y, double f) {
			if (view_scale != min_view_scale && view_scale != max_view_scale) {
				view_pos = view_pos.scale(1-zoom_force).add(W(vec2(x,y)).scale(zoom_force));
			}
			view_scale *= f;
			view_scale = double.min(double.max(view_scale, min_view_scale), max_view_scale);
		}

		static void on_ship_created(Ship s)
		{
		}

		public void textf(int x, int y, string fmt, ...) {
			va_list ap = va_list();
			var str = fmt.vprintf(ap);
			render_text(x, y, str);
		}

		public void dump_perf() {
			print("== Renderer performance dump:\n");
			foreach (RenderBatch batch in batches) {
				print("Batch %s:\n", batch.get_type().name());
				batch.perf.dump();
			}
			print("== Overall:\n");
			perf.dump();
			print("== Batch summaries:\n");
			foreach (RenderBatch batch in batches) {
				print("%s: %s\n", batch.get_type().name(), batch.perf.summary());
			}
			print("\n");
		}
	}
}
