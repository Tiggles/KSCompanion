GameState :: enum {
    MENU;
    PLAYER_CREATION_1;
    PLAYER_CREATION_2;
    WAR_FACE;
    PLAYING;
    BATTLE;
}

Stats :: struct {
    strength: u8 = 6;
    health: u8 = 6;
    agility: u8 = 6;
}

Player :: struct {
    fixed_stats: Stats;
    current_stats: Stats;
    items: [..]string;
}

is_critical :: (dice_roll_1: int, dice_roll_2: int) -> bool {
    return dice_roll_1 == dice_roll_2 && dice_roll_1 != 1;
}

is_a_hit :: (strength: int, dice_roll_1: int, dice_roll_2: int) -> bool {
    return dice_roll_1 + dice_roll_1 <= strength;
}

calculate_damage :: (dice_roll_1: int, dice_roll_2: int) -> int {
    if is_critical(dice_roll_1, dice_roll_2) return 4;
    return 2;
}

WindowSettings :: struct {
    window: Window_Type;
    window_width: s32 = 1280;
    window_height: s32 = 720;
    game_state: GameState;
    current_theme: Default_Themes = Default_Themes.Blood_Vampire;
    quit: bool = false;
    war_face: Simp.Texture;
}

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    w: WindowSettings;
    w.window = create_window(w.window_width, w.window_height, "A Window");
    #if OS == .WINDOWS {
        // @Feature: Add user-specific typelist support.
        Windows.DragAcceptFiles(w.window, cast(Windows.BOOL) true);
    } else #if OS == .LINUX {
        X11 :: #import "X11";
        typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
        X11.enable_drag_and_drop(w.window, typelist);
    } else #if OS == .MACOS {
        // @Incomplete
    }

    player: Player;

    w.window_width, w.window_height = Simp.get_render_dimensions(w.window);

    Simp.set_render_target(w.window);

    font := init_font(w.window_height);
    ui_init();

    current_time: float64;
    last_time: float64;

    while !w.quit {
        current_time = get_time();
        dt := cast(float)(current_time - last_time);
        Clamp(*dt, 0, 0.1);
        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            if it.window == w.window {
                should_reinit := (it.width != w.window_width) || (it.height != w.window_height);

                w.window_width = it.width;
                w.window_height = it.height;

                if should_reinit then font = init_font(w.window_height);
            }
        }

        for event: Input.events_this_frame {
            if event.type == .QUIT then w.quit = true;

            getrect_handle_event(event);

            if event.type == {
                case .KEYBOARD;
                    if event.key_pressed && event.key_code == .ESCAPE {
                        active_widget_deactivate_all();
                    }
                case .DRAG_AND_DROP_FILES;
                    // TODO(Jonas): 
                    // for dropped_files free(it);
                    // array_reset(*dropped_files);
                    for event.files {
                        Simp.texture_load_from_file(*w.war_face, it);
                    }
            }
        }
        
        update(*w, *player, dt, current_time, font);

        reset_temporary_storage();
        sleep_milliseconds(10);
    }
}

update :: (
    w: *WindowSettings,
    player: *Player,
    dt: float64,
    current_time: float64,
    font: *Font
) {
    proc := default_theme_procs[w.current_theme];
    theme := proc();
    set_default_theme(theme);  // Just in case we don't explicitly pass themes sometimes...!

    bg_col := theme.background_color; 
    Simp.clear_render_target(bg_col.x, bg_col.y, bg_col.z, 1);

    x, y, width, height := get_dimensions(w.window, true);
    ui_per_frame_update(w.window, width, height, current_time);

    if #complete w.game_state == {
        case .MENU;
            menu(w, font, theme);
        case .PLAYER_CREATION_1;
            player_creation_1(w, player, font, theme);
        case .PLAYER_CREATION_2;
            player_creation_2(w, player, font, theme);
        case .WAR_FACE;
            war_face(w, font, theme);
        case .PLAYING;
            playing(w, player, font);
        case .BATTLE;
            battle();
    }

    Simp.swap_buffers(w.window);
}

slider_float_value: float = 27.02;
slider_int_value  : s32 = 3;

menu :: (w: *WindowSettings, font: *Font, theme: Overall_Theme) {
    button_theme := theme.button_theme;
    button_theme.font = font;
    button_theme.enable_variable_frame_thickness = true;    
    k := w.window_height * .1;
    r := get_rect(w.window_width / 2.0 - k, w.window_height / 2.0, 3 * k, k);

    if button(r, "Start", *button_theme) {
        w.game_state = .PLAYER_CREATION_1;
    }

    r.y -= k * 1.2;
    
    if button(r, "Quit", *button_theme) {
        w.quit = true;
    }
}

MAX_POINTS :: 20;
MAX_STAT_WITHOUT_BONUS :: 8;
MIN_STAT :: 4;

player_creation_1 :: (w: *WindowSettings, player: *Player, font: *Font, theme: Overall_Theme) {
    button_theme := theme.button_theme;
    button_theme.font = font;
    button_theme.enable_variable_frame_thickness = true; 


    assigned := player.fixed_stats.strength + player.fixed_stats.health + player.fixed_stats.agility;

    disabled := assigned == MAX_POINTS;

    label_theme: Label_Theme;
    label_theme.alignment = .Center;
    label_theme.text_color = .{.5, .5, .5, 1};

    k := w.window_height * .1;
    button_size := k / 3.0;
    label_size := button_size * 7.0;

    r := get_rect(w.window_width / 2.0 - button_size - label_size / 2, w.window_height - k * 3, button_size, button_size);
    
    x_start := r.x;

    // STRENGTH
    if button(r, "-", *button_theme, disable_press = player.fixed_stats.strength == 4) {
        player.fixed_stats.strength -= 1;
        Clamp(*player.fixed_stats.strength, MIN_STAT, MAX_STAT_WITHOUT_BONUS);
    }

    r.x += button_size;
    r.w = label_size;

    labelText := tprint("Kampfærdighed: %", player.fixed_stats.strength);
    label(r, labelText, *label_theme);
    
    r.x += label_size;
    r.w = button_size;

    if button(r, "+", *button_theme, disable_press = disabled || player.fixed_stats.strength == 8) {
        player.fixed_stats.strength += 1;
        Clamp(*player.fixed_stats.strength, MIN_STAT, MAX_STAT_WITHOUT_BONUS);
    }

    r.x = x_start;
    r.y -= button_size + k / 10;

    // HEALTH
    if button(r, "-", *button_theme, disable_press = player.fixed_stats.health == 4) {
        player.fixed_stats.health -= 1;
        Clamp(*player.fixed_stats.health, MIN_STAT, MAX_STAT_WITHOUT_BONUS);
    }

    r.x += button_size;
    r.w = label_size;

    labelText = tprint("Helbred: %", player.fixed_stats.health);
    label(r, labelText, *label_theme);
    
    r.x += label_size;
    r.w = button_size;

    if button(r, "+", *button_theme, disable_press = disabled || player.fixed_stats.health == 8) {
        player.fixed_stats.health += 1;
        Clamp(*player.fixed_stats.health, MIN_STAT, MAX_STAT_WITHOUT_BONUS);
    }

    r.x = x_start;
    r.y -= button_size + k / 10;

    // Agility
    if button(r, "-", *button_theme, disable_press = player.fixed_stats.agility == 4) {
        player.fixed_stats.agility -= 1;
        Clamp(*player.fixed_stats.agility, MIN_STAT, MAX_STAT_WITHOUT_BONUS);
    }

    r.x += button_size;
    r.w = label_size;

    labelText = tprint("Behændighed: %", player.fixed_stats.agility);
    label(r, labelText, *label_theme);
    
    r.x += label_size;
    r.w = button_size;

    if button(r, "+", *button_theme, disable_press = disabled || player.fixed_stats.agility == 8) {
        player.fixed_stats.agility += 1;
        Clamp(*player.fixed_stats.agility, MIN_STAT, MAX_STAT_WITHOUT_BONUS);
    }

    labelText = tprint("Resterende point: %", MAX_POINTS - assigned);
    r.x = x_start + button_size;
    r.y -= button_size + k / 10;
    r.w = label_size;
    label(r, labelText, *label_theme);

    r.y -= button_size + k;
    r.h += r.h;

    if button(r, "Fortsæt", *button_theme, disable_over = assigned != MAX_POINTS, disable_press = assigned != MAX_POINTS) {
        w.game_state = .PLAYER_CREATION_2;
    }
}

player_creation_2 :: (w: *WindowSettings, player: *Player, font: *Font, theme: Overall_Theme) {
    button_theme := theme.button_theme;
    button_theme.font = font;
    button_theme.enable_variable_frame_thickness = true;

    k := w.window_height * .1;
    r := get_rect(w.window_width / 2.0 - k * 3, w.window_height * 0.67, k * 6, k);

    label_theme: Label_Theme;
    label_theme.alignment = .Center;
    label_theme.text_color = .{.5, .5, .5, 1};
    label(r, "Specialisering (+2)", *label_theme);

    r.w = 3 * k;
    r.h = k;
    r.y -= k + k * 0.2;
    r.x += k * 1.5;
    if button(r, "Kampfærdighed", *button_theme) {
        player.fixed_stats.strength += 2;
        player.current_stats = player.fixed_stats;
        w.game_state = .WAR_FACE;
    }

    r.y -= k + k * 0.2;
    if button(r, "Helbred", *button_theme) {
        player.fixed_stats.health += 2;
        player.current_stats = player.fixed_stats;
        w.game_state = .WAR_FACE;
    }

    r.y -= k + k * 0.2;
    if button(r, "Behændighed", *button_theme) {
        player.fixed_stats.agility += 2;
        player.current_stats = player.fixed_stats;
        w.game_state = .WAR_FACE;
    }
}

get_k :: (w: *WindowSettings) -> float32 {
    return w.window_height * 0.1;
}

war_face :: (w: *WindowSettings, font: *Font, theme: Overall_Theme) {
    label_theme: Label_Theme;
    label_theme.alignment = .Center;
    label_theme.text_color = .{.5, .5, .5, 1};

    k := get_k(w);
    label_size := k * 2.33;

    
    if w.war_face.width != 1 && w.war_face.height != 1 {
        w.game_state = .PLAYING;
    } else {
        r := get_rect(w.window_width / 2.0 - label_size, w.window_height / 2.0 + label_size / 2.0, label_size * 2, label_size / 6.0);
        label(r, "Træk et billede ind til din karakter", *label_theme);
    }
}

draw_war_face :: (w: *WindowSettings, font: *Font) {
    Simp.set_shader_for_images(*w.war_face);
    Simp.immediate_begin();
    
    label_theme: Label_Theme;
    label_theme.alignment = .Center;
    label_theme.text_color = .{.5, .5, .5, 1};

    width := w.window_height / 4.0;
    k := get_k(w);

    v2 :: make_vector2;
    r := get_rect(k / 4, width, k * 2, k / 2);
    Simp.immediate_quad(v2(0, 0), v2(width, 0), v2(width, width), v2(0, width));
    label(r, "Krigs ansigt", *label_theme);
}

draw_stats :: (w: *WindowSettings, p: *Player) {
    k := get_k(w);
    label_size := k * 2.33;
    label_theme: Label_Theme;
    label_theme.alignment = .Left;
    label_theme.text_color = .{.5, .5, .5, 1};
    r := get_rect(k / 2, w.window_height - k, label_size, label_size / 8);
    text := tprint("% / %", p.current_stats.strength, p.fixed_stats.strength);
    label(r, "Kampfærdighed", *label_theme);
    label_theme.alignment = .Right;
    label(r, text, *label_theme);
    
    r.y -= label_size / 8 + 4;
    text = tprint("% / %", p.current_stats.health, p.fixed_stats.health);
    label_theme.alignment = .Left;
    label(r, "Helbred", *label_theme);
    label_theme.alignment = .Right;
    label(r, text, *label_theme);

    r.y -= label_size / 8 + 4;
    text = tprint("% / %", p.current_stats.agility, p.fixed_stats.agility);
    label_theme.alignment = .Left;
    label(r, "Behændighed", *label_theme);
    label_theme.alignment = .Right;
    label(r, text, *label_theme);
}

playing :: (w: *WindowSettings, p: *Player, font: *Font) {
    draw_war_face(w, font);
    draw_stats(w, p);
    // Stats
    // Items
    // Fight Monster
}
    
battle :: () {
    // Show dice
    // Click to roll
}

init_font :: (window_height: int) -> *Font {
    return Simp.get_font_at_size("Assets", "Karla-Regular.ttf", 24);
}

default_starting_items :: string.[
    "Et slagsværd",
    "En læderrustning",
    "En pung med fem guldstykker",
    "Et fåreskinstæppe som du bruger, når du sover",
    "8 stykker proviant"
];

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console();
    }
}

Font :: Simp.Dynamic_Font;

Simp  :: #import "Simp";
Input :: #import "Input";
#import "GetRect";

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.