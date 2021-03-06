package armory.system;

import iron.data.SceneFormat;
import armory.system.CyclesFormat;

class CyclesShaderData {
	var material:TMaterial;

	public function new(material:TMaterial) {
		this.material = material;
	}

	public function add_context(props:Dynamic):CyclesShaderContext {
		return new CyclesShaderContext(material, props);
	}
}

class CyclesShaderContext {
	public var vert:CyclesShader;
	public var frag:CyclesShader;
	public var geom:CyclesShader;
	public var tesc:CyclesShader;
	public var tese:CyclesShader;
	public var data:TShaderContext;
	var material:TMaterial;
	var constants:Array<TShaderConstant>;
	var tunits:Array<TTextureUnit>;

	public function new(material:TMaterial, props:Dynamic) {
		this.material = material;
		data = {
			name: props.name,
			depth_write: props.depth_write,
			compare_mode: props.compare_mode,
			cull_mode: props.cull_mode,
			blend_source: props.blend_source,
			blend_destination: props.blend_destination,
			blend_operation: props.blend_operation,
			alpha_blend_source: props.alpha_blend_source,
			alpha_blend_destination: props.alpha_blend_destination,
			alpha_blend_operation: props.alpha_blend_operation,
			fragment_shader: '',
			vertex_shader: '',
			vertex_elements: Reflect.hasField(props, 'vertex_elements') ? props.vertex_elements : [ {name: "pos", data: 'short4norm'}, {name: "nor", data: 'short2norm'}]
		};

		if (props.color_write_red != null)
			data.color_write_red = props.color_write_red;
		if (props.color_write_green != null)
			data.color_write_green = props.color_write_green;
		if (props.color_write_blue != null)
			data.color_write_blue = props.color_write_blue;
		if (props.color_write_alpha != null)
			data.color_write_alpha = props.color_write_alpha;
		if (props.color_writes_red != null)
			data.color_writes_red = props.color_writes_red;
		if (props.color_writes_green != null)
			data.color_writes_green = props.color_writes_green;
		if (props.color_writes_blue != null)
			data.color_writes_blue = props.color_writes_blue;
		if (props.color_writes_alpha != null)
			data.color_writes_alpha = props.color_writes_alpha;

		tunits = data.texture_units = [];
		constants = data.constants = [];
	}

	public function add_elem(name:String, data_type:String) {
		for (e in data.vertex_elements) {
			if (e.name == name) return;
		}
		var elem:TVertexElement = { name: name, data: data_type };
		data.vertex_elements.push(elem);
	}

	public function is_elem(name:String) {
		for (elem in data.vertex_elements)
			if (elem.name == name)
				return true;
		return false;
	}

	public function get_elem(name:String):TVertexElement {
		for (elem in data.vertex_elements) {
			#if cpp
			if (Reflect.field(elem, "name") == name)
			#else
			if (elem.name == name)
			#end {
				return elem;
			}
		}
		return null;
	}

	public function add_constant(ctype:String, name:String, link:String = null) {
		for (c in constants)
			if (c.name == name)
				return;

		var c:TShaderConstant = { name: name, type: ctype };
		if (link != null)
			c.link = link;
		constants.push(c);
	}

	public function add_texture_unit(ctype:String, name:String, link:String = null, is_image = false) {
		for (c in tunits)
			if (c.name == name)
				return;

		var c:TTextureUnit = { name: name };
		if (link != null)
			c.link = link;
		if (is_image)
			c.is_image = is_image;
		tunits.push(c);
	}

	public function make_vert() {
		data.vertex_shader = material.name + '_' + data.name + '.vert';
		vert = new CyclesShader(this, 'vert');
		return vert;
	}

	public function make_frag() {
		data.fragment_shader = material.name + '_' + data.name + '.frag';
		frag = new CyclesShader(this, 'frag');
		return frag;
	}
}

class CyclesShader {

	public var context:CyclesShaderContext;
	var shader_type = '';
	var includes:Array<String> = [];
	public var ins:Array<String> = [];
	public var outs:Array<String> = [];
	var uniforms:Array<String> = [];
	var functions = new Map<String, String>();
	public var main = '';
	public var main_init = '';
	public var main_end = '';
	public var main_normal = '';
	public var main_textures = '';
	public var main_attribs = '';
	var header = '';
	public var write_pre = false;
	public var write_normal = 0;
	public var write_textures = 0;
	var vstruct_as_vsin = true;
	var lock = false;

	// References
	public var bposition = false;
	public var wposition = false;
	public var mposition = false;
	public var vposition = false;
	public var wvpposition = false;
	public var ndcpos = false;
	public var wtangent = false;
	public var vVec = false;
	public var vVecCam = false;
	public var n = false;
	public var dotNV = false;
	public var invTBN = false;

	public function new(context:CyclesShaderContext, shader_type:String) {
		this.context = context;
		this.shader_type = shader_type;
	}

	public function add_include(s:String) {
		includes.push(s);
	}

	public function add_in(s:String) {
		ins.push(s);
	}

	public function add_out(s:String) {
		outs.push(s);
	}

	public function add_uniform(s:String, link:Dynamic = null, included = false) {
		var ar = s.split(' ');
		// layout(RGBA8) image3D voxels
		var utype = ar[ar.length - 2];
		var uname = ar[ar.length - 1];
		if (StringTools.startsWith(utype, 'sampler') || StringTools.startsWith(utype, 'image') || StringTools.startsWith(utype, 'uimage')) {
			var is_image = (StringTools.startsWith(utype, 'image') || StringTools.startsWith(utype, 'uimage')) ? true : false;
			context.add_texture_unit(utype, uname, link, is_image);
		}
		else {
			// Prefer vec4[] for d3d to avoid padding
			if (ar[0] == 'float' && ar[1].indexOf('[') >= 0) {
				ar[0] = 'floats';
				ar[1] = ar[1].split('[')[0];
			}
			else if (ar[0] == 'vec4' && ar[1].indexOf('[') >= 0) {
				ar[0] = 'floats';
				ar[1] = ar[1].split('[')[0];
			}
			context.add_constant(ar[0], ar[1], link);
		}
		if (included == false && uniforms.indexOf(s) == -1) {
			uniforms.push(s);
		}
	}

	public function add_function(s:String) {
		var fname = s.split('(')[0];
		if (functions.exists(fname)) return;
		functions.set(fname, s);
	}

	public function contains(s:String):Bool {
		return main.indexOf(s) >= 0 ||
			   main_init.indexOf(s) >= 0 ||
			   main_normal.indexOf(s) >= 0 ||
			   ins.indexOf(s) >= 0 ||
			   main_textures.indexOf(s) >= 0 ||
			   main_attribs.indexOf(s) >= 0;
	}

	public function write_init(s:String) {
		main_init = s + '\n' + main_init;
	}

	public function write(s:String) {
		if (lock) return;
		if (write_textures > 0) {
			main_textures += s + '\n';
		}
		else if (write_normal > 0) {
			main_normal += s + '\n';
		}
		else if (write_pre) {
			main_init += s + '\n';
		}
		else {
			main += s + '\n';
		}
	}

	public function write_header(s:String) {
		header += s + '\n';
	}

	public function write_end(s:String) {
		main_end += s + '\n';
	}

	public function write_attrib(s:String) {
		main_attribs += s + '\n';
	}

	function dataSize(data:String):String {
		if (data == 'float1') return '1';
		else if (data == 'float2') return '2';
		else if (data == 'float3') return '3';
		else if (data == 'float4') return '4';
		else if (data == 'short2norm') return '2';
		else if (data == 'short4norm') return '4';
		else return '1';
	}

	function vstruct_to_vsin() {
		// if self.shader_type != 'vert' or self.ins != [] or not self.vstruct_as_vsin: # Vertex structure as vertex shader input
			// return
		var vs = context.data.vertex_elements;
		for (e in vs) {
			add_in('vec' + dataSize(e.data) + ' ' + e.name);
		}
	}

	public function get() {
		#if kha_webgl // WebGL2
		var s = '#version 300 es\n';
		if (shader_type == 'frag') {
			s += 'precision mediump float;\n';
			s += 'precision mediump int;\n';
		}
		#else
		var s = '#version 330\n';
		#end

		s += header;

		var in_ext = '';
		var out_ext = '';

		if (shader_type == 'vert' && vstruct_as_vsin) {
			vstruct_to_vsin();
		}

		for (a in includes)
			s += '#include "' + a + '"\n';
		for (a in ins)
			s += 'in $a$in_ext;\n';
		for (a in outs)
			s += 'out $a$out_ext;\n';
		for (a in uniforms)
			s += 'uniform ' + a + ';\n';
		for (f in functions)
			s += f + '\n';
		s += 'void main() {\n';
		s += main_attribs;
		s += main_textures;
		s += main_normal;
		s += main_init;
		s += main;
		s += main_end;
		s += '}\n';
		return s;
	}
}
