// Camera and menu window for applications that provide their own 3D renderer.
// Keep the full scene example and its movement/animation dependencies in tbx/engine.
#import "Basic";
#import "Math";
#import "GL";
#import "File_Utilities";

#import "tbx/configuration";
#import "tbx/rectangle";
#import "tbx/geometry";
#import "tbx/opengl";
#import "tbx/camera";
#import "tbx/time";
#import "tbx/turns";
#import "tbx/math";
#import "tbx/ui";
#import "tbx/assets";
#import "tbx/model_loading";
#import "tbx/software_rasterizer";
#import "tbx/engine/monitor";

#load "../../movement/god_mode.jai";
#load "../build_type.jai";
#load "../input.jai";
#load "../looping_program.jai";
#load "../crosshair_editor_model.jai";
#load "../crosshair_library.jai";
#load "../crosshair.jai";
#load "../windowed_program.jai";
#load "../windowed_menu_program.jai";
#load "../crosshair_editor.jai";
#load "../graphs.jai";
#load "../sound.jai";
#load "windowed_program_3d_base.jai";
