#import <Cocoa/Cocoa.h>

// A bare binary started from a shell is not a bundled .app, so macOS gives it
// no activation: the window is created but sits behind everything. Asking
// NSApp directly is the only reliable way to bring it forward.
void babeltro_activate(void) {
	[NSApp activateIgnoringOtherApps:YES];
}
