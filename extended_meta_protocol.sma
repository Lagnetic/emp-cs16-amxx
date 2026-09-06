#include <amxmodx>
#include <amxmisc>
#tryinclude <amxmodx_version>

#if defined AMXX_VERSION_NUM
	#if AMXX_VERSION_NUM >= 190
		#define EM_HAS_CONFIG_MTIME
	#endif
#endif

#define PLUGIN_NAME        "Extended Meta Protocol"
#define PLUGIN_VERSION     "2026.0.15"
#define PLUGIN_AUTHOR      "Lagnetic Team"
#define SCHEMA_VERSION     "1"

#define CONFIG_FILE        "extended_meta_protocol.ini"

#define MAX_CVAR_BYTES     240
#define MAX_DESC_CHARS     240
#define MAX_DESC_BYTES     960
#define MAX_DESC_PARTS     4
#define MAX_COMMAND_BYTES  960
#define MAX_COMMAND_PARTS  4
#define MAX_LINE_LENGTH    1200
#define MAX_ERROR_LENGTH   191
#define MAX_KEY_LENGTH     47
#define MAX_CONFIG_PATH    255
#define MAX_LINKS          12
#define MAX_CUSTOM_FIELDS  12
#define MAX_METADATA_BYTES 10240

enum _:ENUM_META_CVARS
{
	CVAR_STATUS,
	CVAR_ERROR,
	CVAR_SCHEMA,
	CVAR_UPDATED,
	CVAR_DESC,
	CVAR_DESC_2,
	CVAR_DESC_3,
	CVAR_DESC_4,
	CVAR_DESC_PARTS,
	CVAR_MOD,
	CVAR_KEYWORDS,
	CVAR_ICON,
	CVAR_MAP_IMAGE,
	CVAR_LANG_VOICE,
	CVAR_LANG_UI,
	CVAR_LINKS,
	CVAR_CUSTOM,
	CVAR_COMMANDS,
	CVAR_COMMANDS_2,
	CVAR_COMMANDS_3,
	CVAR_COMMANDS_4,
	CVAR_COMMAND_PARTS,
	CVAR_COUNT
};

new const g_cvar_names[CVAR_COUNT][] =
{
	"em_status",
	"em_error",
	"em_schema",
	"em_updated",
	"em_desc",
	"em_desc_2",
	"em_desc_3",
	"em_desc_4",
	"em_desc_parts",
	"em_mod",
	"em_keywords",
	"em_icon",
	"em_map_img",
	"em_lang_voice",
	"em_lang_ui",
	"em_links",
	"em_custom",
	"em_commands",
	"em_commands_2",
	"em_commands_3",
	"em_commands_4",
	"em_command_parts"
};

new g_cvars[CVAR_COUNT];
new g_config_path[MAX_CONFIG_PATH + 1];
new g_error[MAX_ERROR_LENGTH + 1];

new g_description[MAX_DESC_BYTES + 1];
new g_mod[81];
new g_keywords[MAX_CVAR_BYTES + 1];
new g_icon[MAX_CVAR_BYTES + 1];
new g_map_image[MAX_CVAR_BYTES + 1];
new g_lang_voice[121];
new g_lang_ui[121];
new bool:g_publish_commands;
new g_seen_meta_keys;

new g_link_count;
new g_link_keys[MAX_LINKS][MAX_KEY_LENGTH + 1];
new g_link_values[MAX_LINKS][MAX_CVAR_BYTES + 1];

new g_custom_count;
new g_custom_keys[MAX_CUSTOM_FIELDS][MAX_KEY_LENGTH + 1];
new g_custom_values[MAX_CUSTOM_FIELDS][MAX_CVAR_BYTES + 1];

new g_dynamic_count;
new g_dynamic_cvars[MAX_LINKS + MAX_CUSTOM_FIELDS];

public plugin_init( )
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

	for( new i = 0; i < CVAR_COUNT; i++ )
	{
		#if !defined EM_HAS_CONFIG_MTIME
			if( i == CVAR_UPDATED )
				continue;
		#endif

		g_cvars[i] = register_cvar(g_cvar_names[i], "", FCVAR_SERVER | FCVAR_UNLOGGED);
	}

	register_concmd("em_reload", "command_reload", ADMIN_RCON, "Reload configs/extended_meta_protocol.ini");

	update_status_cvar(0);
	set_pcvar_string(g_cvars[CVAR_ERROR], "loading");
}

public plugin_cfg( )
{
	get_configsdir(g_config_path, charsmax(g_config_path));
	format(g_config_path, charsmax(g_config_path), "%s/%s", g_config_path, CONFIG_FILE);
	load_metadata( );
}

public command_reload( id, level, cid )
{
	if( !cmd_access(id, level, cid, 1) )
		return PLUGIN_HANDLED;

	load_metadata( );

	new status[32], error[MAX_ERROR_LENGTH + 1];

	get_pcvar_string(g_cvars[CVAR_STATUS], status, charsmax(status));
	get_pcvar_string(g_cvars[CVAR_ERROR], error, charsmax(error));
	console_print(id, "[EM] Status: %s, error: %s", status, error);

	return PLUGIN_HANDLED;
}

load_metadata( )
{
	clear_published_metadata( );
	reset_config_data( );

	if( !file_exists(g_config_path) )
	{
		fail_config("config_missing");
		return;
	}

	new file = fopen(g_config_path, "rt");

	if( !file )
	{
		fail_config("config_open_failed");
		return;
	}

	new line[MAX_LINE_LENGTH + 1];
	new section[16];
	new line_number;

	while( !feof(file) )
	{
		if( !fgets(file, line, charsmax(line)) )
			break;

		line_number++;

		if( line_number == 1 )
			strip_utf8_bom(line);

		trim(line);

		if( !line[0] || line[0] == ';' || line[0] == '#' )
			continue;

		if( line[0] == '[' )
		{
			if( !parse_section(line, section, charsmax(section)) )
			{
				set_parse_error(line_number, "invalid_section");
				break;
			}

			continue;
		}

		if( !section[0] )
		{
			set_parse_error(line_number, "key_outside_section");
			break;
		}

		if( !parse_config_line(section, line, line_number) )
			break;
	}

	fclose(file);

	if( g_error[0] )
	{
		fail_config(g_error);
		return;
	}

	if( !validate_config( ) )
	{
		fail_config(g_error);
		return;
	}

	publish_metadata( );
}

bool:parse_section( const line[], section[], section_length )
{
	new length = strlen(line);

	if( length < 3 || line[length - 1] != ']' )
		return false;

	new content_length = length - 2;

	if( content_length > section_length )
		return false;

	for( new i = 0; i < content_length; i++ )
		section[i] = line[i + 1];

	section[content_length] = '^0';
	trim(section);
	strtolower(section);

	return equal(section, "meta") || equal(section, "links") || equal(section, "custom");
}

bool:parse_config_line( const section[], const line[], line_number )
{
	new key[MAX_KEY_LENGTH + 1];
	new value[MAX_LINE_LENGTH + 1];
	new delimiter = contain(line, "=");

	if( delimiter == -1 )
	{
		set_parse_error(line_number, "missing_equals");
		return false;
	}

	new key_start;
	new key_end = delimiter;

	while( key_start < key_end && is_config_whitespace(line[key_start]) )
		key_start++;
	while( key_end > key_start && is_config_whitespace(line[key_end - 1]) )
		key_end--;

	new key_length = key_end - key_start;

	if( !key_length )
	{
		set_parse_error(line_number, "empty_key");
		return false;
	}

	if( key_length > MAX_KEY_LENGTH )
	{
		set_parse_error(line_number, "key_too_long");
		return false;
	}

	for( new i = 0; i < key_length; i++ )
		key[i] = line[key_start + i];

	key[key_length] = '^0';

	formatex(value, charsmax(value), "%s", line[delimiter + 1]);
	trim(value);
	strtolower(key);

	if( !strip_outer_quotes(value) )
	{
		set_parse_error(line_number, "invalid_quotes");
		return false;
	}

	if( equal(section, "meta") )
		return parse_meta_value(key, value, line_number);

	if( !is_valid_key(key) )
	{
		set_parse_error(line_number, "invalid_key");
		return false;
	}

	if( strlen(value) > MAX_CVAR_BYTES )
	{
		set_parse_error(line_number, "value_too_long");
		return false;
	}

	if( equal(section, "links") )
	{
		if( !is_http_url(value) )
		{
			set_parse_error(line_number, "invalid_link_url");
			return false;
		}

		return add_pair(g_link_keys, g_link_values, g_link_count, MAX_LINKS, key, value, line_number);
	}

	return add_pair(g_custom_keys, g_custom_values, g_custom_count, MAX_CUSTOM_FIELDS, key, value, line_number);
}

bool:parse_meta_value( const key[], const value[], line_number )
{
	if( equal(key, "description") )
	{
		if( !mark_meta_key(1 << 0, line_number) )
			return false;

		if( strlen(value) > MAX_DESC_BYTES )
		{
			set_parse_error(line_number, "description_too_long");
			return false;
		}

		formatex(g_description, charsmax(g_description), "%s", value);
	}
	else if( equal(key, "mod") )
	{
		if( !mark_meta_key(1 << 1, line_number) )
			return false;

		if( strlen(value) > charsmax(g_mod) )
		{
			set_parse_error(line_number, "mod_too_long");
			return false;
		}

		formatex(g_mod, charsmax(g_mod), "%s", value);
	}
	else if( equal(key, "keywords") )
	{
		if( !mark_meta_key(1 << 2, line_number) )
			return false;

		if( strlen(value) > charsmax(g_keywords) )
		{
			set_parse_error(line_number, "keywords_too_long");
			return false;
		}

		formatex(g_keywords, charsmax(g_keywords), "%s", value);
	}
	else if( equal(key, "icon") )
	{
		if( !mark_meta_key(1 << 3, line_number) )
			return false;

		if( strlen(value) > charsmax(g_icon) )
		{
			set_parse_error(line_number, "icon_too_long");
			return false;
		}

		formatex(g_icon, charsmax(g_icon), "%s", value);
	}
	else if( equal(key, "map_image") )
	{
		if( !mark_meta_key(1 << 4, line_number) )
			return false;

		if( strlen(value) > charsmax(g_map_image) )
		{
			set_parse_error(line_number, "map_image_too_long");
			return false;
		}

		formatex(g_map_image, charsmax(g_map_image), "%s", value);
	}
	else if( equal(key, "voice_languages") )
	{
		if( !mark_meta_key(1 << 5, line_number) )
			return false;

		if( strlen(value) > charsmax(g_lang_voice) )
		{
			set_parse_error(line_number, "voice_languages_too_long");
			return false;
		}

		formatex(g_lang_voice, charsmax(g_lang_voice), "%s", value);
	}
	else if( equal(key, "interface_languages") )
	{
		if( !mark_meta_key(1 << 6, line_number) )
			return false;

		if( strlen(value) > charsmax(g_lang_ui) )
		{
			set_parse_error(line_number, "interface_languages_too_long");
			return false;
		}

		formatex(g_lang_ui, charsmax(g_lang_ui), "%s", value);
	}
	else if( equal(key, "publish_commands") )
	{
		if( !mark_meta_key(1 << 7, line_number) )
			return false;

		if( !equal(value, "0") && !equal(value, "1") )
		{
			set_parse_error(line_number, "invalid_publish_commands");
			return false;
		}

		g_publish_commands = ( equal(value, "1") ) ? true : false;
	}
	else
	{
		set_parse_error(line_number, "unknown_meta_key");
		return false;
	}

	return true;
}

bool:validate_config( )
{
	if( !g_description[0] )
	{
		formatex(g_error, charsmax(g_error), "description_required");
		return false;
	}

	new description_chars;

	if( !utf8_length(g_description, description_chars) )
	{
		formatex(g_error, charsmax(g_error), "description_invalid_utf8");
		return false;
	}

	if( description_chars > MAX_DESC_CHARS )
	{
		formatex(g_error, charsmax(g_error), "description_too_long");
		return false;
	}

	if( !g_mod[0] )
	{
		formatex(g_error, charsmax(g_error), "mod_required");
		return false;
	}

	if( equal(g_description, "Краткое описание сервера длиной до 240 символов") || contains_example_url( ) )
	{
		formatex(g_error, charsmax(g_error), "placeholder_value");
		return false;
	}

	if( g_icon[0] && !is_http_url(g_icon) )
	{
		formatex(g_error, charsmax(g_error), "invalid_icon_url");
		return false;
	}

	if( g_map_image[0] && !is_http_url(g_map_image) )
	{
		formatex(g_error, charsmax(g_error), "invalid_map_image_url");
		return false;
	}

	return true;
}

publish_metadata( )
{
	#if defined EM_HAS_CONFIG_MTIME
		new updated = GetFileTime(g_config_path, FileTime_LastChange);

		if( updated <= 0 )
		{
			formatex(g_error, charsmax(g_error), "config_time_failed");
			fail_config(g_error);
			return;
		}

		new updated_text[16];

		num_to_str(updated, updated_text, charsmax(updated_text));
	#endif

	set_pcvar_string(g_cvars[CVAR_SCHEMA], SCHEMA_VERSION);

	#if defined EM_HAS_CONFIG_MTIME
		set_pcvar_string(g_cvars[CVAR_UPDATED], updated_text);
	#endif

	set_pcvar_string(g_cvars[CVAR_MOD], g_mod);
	set_pcvar_string(g_cvars[CVAR_KEYWORDS], g_keywords);
	set_pcvar_string(g_cvars[CVAR_ICON], g_icon);
	set_pcvar_string(g_cvars[CVAR_LANG_VOICE], g_lang_voice);
	set_pcvar_string(g_cvars[CVAR_LANG_UI], g_lang_ui);

	if( !publish_map_image( ) )
	{
		fail_config(g_error);
		return;
	}

	publish_description( );

	if( g_publish_commands )
		publish_commands( );

	if( !validate_metadata_size( ) )
	{
		fail_config(g_error);
		return;
	}

	publish_dynamic_fields( );

	set_pcvar_string(g_cvars[CVAR_ERROR], "");
	update_status_cvar(1);

	new status[32];

	get_pcvar_string(g_cvars[CVAR_STATUS], status, charsmax(status));
	server_print("[EM] Metadata published, status: %s", status);
}

publish_description( )
{
	new parts[MAX_DESC_PARTS][MAX_CVAR_BYTES + 1];
	new part_count = split_utf8(g_description, parts, MAX_DESC_PARTS);
	new parts_text[4];

	num_to_str(part_count, parts_text, charsmax(parts_text));

	for( new i = 0; i < MAX_DESC_PARTS; i++ )
		set_pcvar_string(g_cvars[CVAR_DESC + i], parts[i]);

	set_pcvar_string(g_cvars[CVAR_DESC_PARTS], parts_text);
}

bool:publish_map_image( )
{
	new value[MAX_CVAR_BYTES + 65];

	formatex(value, charsmax(value), "%s", g_map_image);

	if( value[0] )
	{
		new map_name[64];

		get_mapname(map_name, charsmax(map_name));
		replace_all(value, charsmax(value), "{map}", map_name);

		if( strlen(value) > MAX_CVAR_BYTES )
		{
			formatex(g_error, charsmax(g_error), "map_image_expanded_too_long");
			return false;
		}
	}

	set_pcvar_string(g_cvars[CVAR_MAP_IMAGE], value);

	return true;
}

publish_dynamic_fields( )
{
	new manifest[MAX_CVAR_BYTES + 1];
	new cvar_name[64];

	for( new i = 0; i < g_link_count; i++ )
	{
		formatex(cvar_name, charsmax(cvar_name), "em_link_%s", g_link_keys[i]);
		g_dynamic_cvars[g_dynamic_count] = register_cvar(cvar_name, "", FCVAR_SERVER | FCVAR_UNLOGGED);
		set_cvar_flags(cvar_name, FCVAR_SERVER | FCVAR_UNLOGGED);
		set_pcvar_string(g_dynamic_cvars[g_dynamic_count++], g_link_values[i]);
		append_manifest(manifest, charsmax(manifest), g_link_keys[i]);
	}

	set_pcvar_string(g_cvars[CVAR_LINKS], manifest);

	manifest[0] = '^0';

	for( new i = 0; i < g_custom_count; i++ )
	{
		formatex(cvar_name, charsmax(cvar_name), "em_x_%s", g_custom_keys[i]);
		g_dynamic_cvars[g_dynamic_count] = register_cvar(cvar_name, "", FCVAR_SERVER | FCVAR_UNLOGGED);
		set_cvar_flags(cvar_name, FCVAR_SERVER | FCVAR_UNLOGGED);
		set_pcvar_string(g_dynamic_cvars[g_dynamic_count++], g_custom_values[i]);
		append_manifest(manifest, charsmax(manifest), g_custom_keys[i]);
	}

	set_pcvar_string(g_cvars[CVAR_CUSTOM], manifest);
}

bool:validate_metadata_size( )
{
	new value[MAX_CVAR_BYTES + 1];
	new total_bytes;

	for( new i = 0; i < CVAR_COUNT; i++ )
	{
		if( !g_cvars[i] )
			continue;

		get_pcvar_string(g_cvars[i], value, charsmax(value));
		total_bytes += strlen(g_cvar_names[i]) + strlen(value) + 2;
	}

	for( new i = 0; i < g_link_count; i++ )
	{
		total_bytes += strlen(g_link_keys[i]) + ( i ? 1 : 0 );
		total_bytes += strlen("em_link_") + strlen(g_link_keys[i]) + strlen(g_link_values[i]) + 2;
	}

	for( new i = 0; i < g_custom_count; i++ )
	{
		total_bytes += strlen(g_custom_keys[i]) + ( i ? 1 : 0 );
		total_bytes += strlen("em_x_") + strlen(g_custom_keys[i]) + strlen(g_custom_values[i]) + 2;
	}

	if( total_bytes <= MAX_METADATA_BYTES )
		return true;

	formatex(g_error, charsmax(g_error), "metadata_too_large");
	return false;
}

publish_commands( )
{
	new command_list[MAX_COMMAND_BYTES + 1];
	new command[64], info[2], flags;
	new command_count = get_concmdsnum(0, -1);

	for( new i = 0; i < command_count; i++ )
	{
		if( !get_concmd(i, command, charsmax(command), flags, info, charsmax(info), 0, -1) )
			continue;

		trim(command);

		if( !command[0] || contain(command, ",") != -1 || list_contains(command_list, command) )
			continue;

		new required = strlen(command) + ( command_list[0] ? 1 : 0 );

		if( strlen(command_list) + required > MAX_COMMAND_BYTES )
			break;

		append_manifest(command_list, charsmax(command_list), command);
	}

	new parts[MAX_COMMAND_PARTS][MAX_CVAR_BYTES + 1];
	new part_count = split_ascii_list(command_list, parts, MAX_COMMAND_PARTS);
	new parts_text[4];

	num_to_str(part_count, parts_text, charsmax(parts_text));

	for( new i = 0; i < MAX_COMMAND_PARTS; i++ )
		set_pcvar_string(g_cvars[CVAR_COMMANDS + i], parts[i]);

	set_pcvar_string(g_cvars[CVAR_COMMAND_PARTS], parts_text);
}

clear_published_metadata( )
{
	clear_manifest_fields(CVAR_LINKS, "em_link_");
	clear_manifest_fields(CVAR_CUSTOM, "em_x_");

	for( new i = CVAR_SCHEMA; i < CVAR_COUNT; i++ )
	{
		if( g_cvars[i] )
			set_pcvar_string(g_cvars[i], "");
	}

	for( new i = 0; i < g_dynamic_count; i++ )
	{
		if( g_dynamic_cvars[i] )
			set_pcvar_string(g_dynamic_cvars[i], "");
	}

	g_dynamic_count = 0;

	set_pcvar_string(g_cvars[CVAR_ERROR], "");
	update_status_cvar(0);
}

clear_manifest_fields( manifest_cvar, const prefix[] )
{
	new manifest[MAX_CVAR_BYTES + 1];

	get_pcvar_string(g_cvars[manifest_cvar], manifest, charsmax(manifest));

	new length = strlen(manifest);
	new start;
	new key[MAX_KEY_LENGTH + 1];
	new cvar_name[64];

	while( start < length )
	{
		new end = start;

		while( end < length && manifest[end] != ',' )
			end++;

		new key_length = end - start;

		if( key_length > 0 && key_length <= MAX_KEY_LENGTH )
		{
			for( new i = 0; i < key_length; i++ )
				key[i] = manifest[start + i];

			key[key_length] = '^0';

			if( is_valid_key(key) )
			{
				formatex(cvar_name, charsmax(cvar_name), "%s%s", prefix, key);

				new pointer = get_cvar_pointer(cvar_name);

				if( pointer )
				{
					set_pcvar_string(pointer, "");
					remove_cvar_flags(cvar_name, FCVAR_SERVER);
				}
			}
		}

		start = end + 1;
	}
}

reset_config_data( )
{
	g_error[0] = '^0';
	g_description[0] = '^0';
	g_mod[0] = '^0';
	g_keywords[0] = '^0';
	g_icon[0] = '^0';
	g_map_image[0] = '^0';
	g_lang_voice[0] = '^0';
	g_lang_ui[0] = '^0';
	g_publish_commands = false;
	g_seen_meta_keys = 0;
	g_link_count = 0;
	g_custom_count = 0;
}

fail_config( const error[] )
{
	clear_published_metadata( );
	set_pcvar_string(g_cvars[CVAR_ERROR], error);
	update_status_cvar(0);
	server_print("[EM] Metadata not published: %s", error);
}

update_status_cvar( status_state )
{
	new status[32];

	formatex(status, charsmax(status), "%s-%d", PLUGIN_VERSION, status_state);
	set_pcvar_string(g_cvars[CVAR_STATUS], status);
}

set_parse_error( line_number, const code[] )
{
	formatex(g_error, charsmax(g_error), "line_%d:%s", line_number, code);
}

bool:strip_outer_quotes( value[] )
{
	new length = strlen(value);
	new bool:first_quote = length > 0 && value[0] == '"';
	new bool:last_quote = length > 0 && value[length - 1] == '"';

	if( first_quote != last_quote || ( first_quote && length < 2 ) )
		return false;

	if( first_quote )
	{
		for( new i = 0; i < length - 2; i++ )
			value[i] = value[i + 1];

		value[length - 2] = '^0';
	}

	return true;
}

bool:is_config_whitespace( character )
{
	return character == ' ' || character == '^t' || character == '^r' || character == '^n';
}

bool:mark_meta_key( bit, line_number )
{
	if( g_seen_meta_keys & bit )
	{
		set_parse_error(line_number, "duplicate_meta_key");
		return false;
	}

	g_seen_meta_keys |= bit;
	return true;
}

bool:contains_example_url( )
{
	if( containi(g_icon, "example.com") != -1 || containi(g_map_image, "example.com") != -1 )
	{
		return true;
	}

	for( new i = 0; i < g_link_count; i++ )
	{
		if( containi(g_link_values[i], "example.com") != -1 )
			return true;
	}

	return false;
}

strip_utf8_bom( value[] )
{
	if( ( value[0] & 0xFF ) == 0xEF && ( value[1] & 0xFF ) == 0xBB && ( value[2] & 0xFF ) == 0xBF )
	{
		new length = strlen(value);

		for( new i = 0; i <= length - 3; i++ )
			value[i] = value[i + 3];
	}
}

bool:is_valid_key( const key[] )
{
	new length = strlen(key);

	if( !length || length > MAX_KEY_LENGTH )
		return false;

	for( new i = 0; i < length; i++ )
	{
		if( ( key[i] >= 'a' && key[i] <= 'z' ) || ( key[i] >= '0' && key[i] <= '9' ) || key[i] == '_' )
		{
			continue;
		}

		return false;
	}

	return true;
}

bool:is_http_url( const value[] )
{
	new scheme_length;

	if( containi(value, "https://") == 0 )
		scheme_length = 8;
	else if( containi(value, "http://") == 0 )
		scheme_length = 7;
	else
		return false;

	new length = strlen(value);

	if( length <= scheme_length )
		return false;

	for( new i = 0; i < length; i++ )
	{
		new character = value[i] & 0xFF;

		if( character <= 0x20 || character == 0x7F || character == '"' || character == '<' || character == '>' || character == '\' )
			return false;
	}

	new host_end = scheme_length;

	while( host_end < length && value[host_end] != ':' && value[host_end] != '/' && value[host_end] != '?' && value[host_end] != '#' )
		host_end++;

	new host_length = host_end - scheme_length;

	if( !host_length || host_length > 253 )
		return false;

	new bool:has_dot;
	new bool:has_letter;
	new label_length;

	for( new i = scheme_length; i < host_end; i++ )
	{
		new character = value[i];

		if( character == '.' )
		{
			if( !label_length || value[i - 1] == '-' )
				return false;

			has_dot = true;
			label_length = 0;
			continue;
		}

		if( label_length == 0 && character == '-' )
			return false;

		if( ( character >= 'a' && character <= 'z' ) || ( character >= 'A' && character <= 'Z' ) )
			has_letter = true;
		else if( !( character >= '0' && character <= '9' ) && character != '-' )
			return false;

		if( ++label_length > 63 )
			return false;
	}

	if( !has_dot || !has_letter || !label_length || value[host_end - 1] == '-' )
		return false;

	if( host_end < length && value[host_end] == ':' )
	{
		new port;
		new port_start = ++host_end;

		while( host_end < length && value[host_end] != '/' && value[host_end] != '?' && value[host_end] != '#' )
		{
			if( value[host_end] < '0' || value[host_end] > '9' )
				return false;

			port = port * 10 + value[host_end++] - '0';

			if( port > 65535 )
				return false;
		}

		if( host_end == port_start || !port )
			return false;
	}

	return true;
}

bool:add_pair( keys[][MAX_KEY_LENGTH + 1], values[][MAX_CVAR_BYTES + 1], &count, maximum, const key[], const value[], line_number )
{
	if( !value[0] )
	{
		set_parse_error(line_number, "empty_value");
		return false;
	}

	if( count >= maximum )
	{
		set_parse_error(line_number, "too_many_fields");
		return false;
	}

	new manifest_length = strlen(key);

	for( new i = 0; i < count; i++ )
		manifest_length += strlen(keys[i]) + 1;

	if( manifest_length > MAX_CVAR_BYTES )
	{
		set_parse_error(line_number, "manifest_too_long");
		return false;
	}

	for( new i = 0; i < count; i++ )
	{
		if( equal(keys[i], key) )
		{
			set_parse_error(line_number, "duplicate_key");
			return false;
		}
	}

	formatex(keys[count], MAX_KEY_LENGTH, "%s", key);
	formatex(values[count], MAX_CVAR_BYTES, "%s", value);
	count++;
	return true;
}

append_manifest( output[], output_length, const value[] )
{
	if( output[0] )
		format(output, output_length, "%s,%s", output, value);
	else
		formatex(output, output_length, "%s", value);
}

bool:list_contains( const list[], const value[] )
{
	new list_length = strlen(list);
	new value_length = strlen(value);
	new start;

	while( start < list_length )
	{
		new end = start;

		while( end < list_length && list[end] != ',' )
			end++;

		if( end - start == value_length && equal(list[start], value, value_length) )
			return true;

		start = end + 1;
	}

	return false;
}

bool:utf8_length( const value[], &characters )
{
	characters = 0;
	new length = strlen(value);

	for( new i = 0; i < length; characters++ )
	{
		new sequence = utf8_sequence_length(value, i, length);

		if( !sequence )
			return false;

		i += sequence;
	}

	return true;
}

utf8_sequence_length( const value[], position, length )
{
	new first = value[position] & 0xFF;

	if( first <= 0x7F )
		return 1;

	if( first >= 0xC2 && first <= 0xDF )
		return ( has_continuations(value, position, length, 1) ) ? 2 : 0;

	if( first >= 0xE0 && first <= 0xEF )
	{
		if( !has_continuations(value, position, length, 2) )
			return 0;

		new second = value[position + 1] & 0xFF;

		if( ( first == 0xE0 && second < 0xA0 ) || ( first == 0xED && second > 0x9F ) )
			return 0;

		return 3;
	}

	if( first >= 0xF0 && first <= 0xF4 )
	{
		if( !has_continuations(value, position, length, 3) )
			return 0;

		new second = value[position + 1] & 0xFF;

		if( ( first == 0xF0 && second < 0x90 ) || ( first == 0xF4 && second > 0x8F ) )
			return 0;

		return 4;
	}

	return 0;
}

bool:has_continuations( const value[], position, length, count )
{
	if( position + count >= length )
		return false;

	for( new i = 1; i <= count; i++ )
	{
		new byte_value = value[position + i] & 0xFF;

		if( byte_value < 0x80 || byte_value > 0xBF )
			return false;
	}

	return true;
}

split_utf8( const input[], output[][MAX_CVAR_BYTES + 1], maximum_parts )
{
	new input_length = strlen(input);
	new input_position;
	new part;
	new part_position;

	while( input_position < input_length && part < maximum_parts )
	{
		new sequence = utf8_sequence_length(input, input_position, input_length);

		if( !sequence )
			return 0;

		if( part_position + sequence > MAX_CVAR_BYTES )
		{
			output[part][part_position] = '^0';
			part++;
			part_position = 0;
			continue;
		}

		for( new i = 0; i < sequence; i++ )
			output[part][part_position++] = input[input_position++];
	}

	if( part_position > 0 )
	{
		output[part][part_position] = '^0';
		part++;
	}

	return part;
}

split_ascii_list( const input[], output[][MAX_CVAR_BYTES + 1], maximum_parts )
{
	new length = strlen(input);

	if( !length )
		return 0;

	new input_position;
	new part;

	while( input_position < length && part < maximum_parts )
	{
		new end = input_position + MAX_CVAR_BYTES;

		if( end >= length )
		{
			formatex(output[part], MAX_CVAR_BYTES, "%s", input[input_position]);
			part++;
			break;
		}

		while( end > input_position && input[end] != ',' )
			end--;

		if( end == input_position )
			end = input_position + MAX_CVAR_BYTES;

		new copy_length = end - input_position;

		for( new i = 0; i < copy_length; i++ )
			output[part][i] = input[input_position + i];

		output[part][copy_length] = '^0';
		part++;
		input_position = ( input[end] == ',' ) ? end + 1 : end;
	}

	return part;
}
