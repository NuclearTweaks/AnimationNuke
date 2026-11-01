// AnimationNukePrefs — Settings pane (PreferenceLoader bundle).
//
// The private Preferences framework classes are declared minimally here and
// resolved at runtime (the dylib is linked with -undefined dynamic_lookup),
// so the build needs no SDK stubs and iOS drift can't break linking.

#import <UIKit/UIKit.h>

// ─── minimal private declarations (runtime-resolved) ───────────────────────

@interface PSSpecifier : NSObject
- (NSMutableDictionary *)properties;
@end

@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (NSArray *)specifiers;
@end

// ─── speed mapping ──────────────────────────────────────────────────────────
// The slider works in "position" space 0…100 mapped piecewise-logarithmically
// onto speed 0.5…100:  the left quarter of the slider covers 0.5x–1x (slow
// zone), the rest covers 1x–100x. 1x sits at position 25.

static NSString *const kDomain  = @"com.nucleartweaks.animation-nuke";
static NSString *const kChanged = @"com.nucleartweaks.animation-nuke/changed";

static double ANPosToSpeed(double pos) {
    if (pos <= 25.0) return pow(2.0, -1.0 + pos / 25.0);            // 0.5 … 1
    return pow(2.0, (pos - 25.0) / 75.0 * log2(100.0));             // 1 … 100
}
static double ANSpeedToPos(double s) {
    if (s <= 1.0) return (log2(s) + 1.0) * 25.0;
    return 25.0 + 75.0 * log2(s) / log2(100.0);
}

static double ANStoredSpeed(void) {
    CFStringRef dom = (__bridge CFStringRef)kDomain;
    CFPreferencesAppSynchronize(dom);
    CFNumberRef n = (CFNumberRef)CFPreferencesCopyValue(CFSTR("speed"), dom,
                        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    double v = 1.0;
    if (n) { CFNumberGetValue(n, kCFNumberDoubleType, &v); CFRelease(n); }
    if (v < 0.5) v = 0.5; if (v > 100.0) v = 100.0;
    return v;
}

static NSString *ANFooterText(double speed) {
    if (speed >= 50.0)
        return [NSString stringWithFormat:@"Speed: %.0f× — animations are effectively gone. Nuke achieved.", speed];
    if (speed >= 8.0)
        return [NSString stringWithFormat:@"Speed: %.0f× — animations are just flickers now.", speed];
    if (speed > 1.05)
        return [NSString stringWithFormat:@"Speed: %.2f× — snappy. Everything decorative runs this much faster.", speed];
    if (speed < 0.95)
        return [NSString stringWithFormat:@"Speed: %.2f× — slow motion. For when you want to see the eye candy.", speed];
    return @"Speed: 1.0× — stock iOS. Drag right to crush animations, left to savor them.";
}

// ─── root controller ────────────────────────────────────────────────────────

@interface ANRootController : PSListController
@end

@implementation ANRootController {
    PSSpecifier *_footerSpec;
}

- (NSArray *)specifiers {
    return [self loadSpecifiersFromPlistName:@"Root" target:self];
}

- (PSSpecifier *)liveFooter {
    if (!_footerSpec) {
        for (PSSpecifier *s in [self specifiers]) {
            if ([[s properties] objectForKey:@"footerText"]) { _footerSpec = s; break; }
        }
    }
    return _footerSpec;
}

- (void)updateFooter {
    PSSpecifier *g = [self liveFooter];
    [[g properties] setObject:ANFooterText(ANStoredSpeed()) forKey:@"footerText"];
    SEL r = NSSelectorFromString(@"reloadSpecifier:");
    if ([self respondsToSelector:r]) {
        IMP imp = [self methodForSelector:r];
        void (*fn)(id, SEL, id) = (void (*)(id, SEL, id))imp;
        fn(self, r, g);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:NO];
    [self updateFooter];
}

// ─── slider Get/Set (bound in Root.plist; slider value = position 0…100) ───

- (id)readSpeedPos:(id)spec {
    return @(ANSpeedToPos(ANStoredSpeed()));
}

- (void)writeSpeed:(id)val forSpecifier:(id)spec {
    double pos = [val doubleValue];
    double speed = ANPosToSpeed(pos);
    CFStringRef dom = (__bridge CFStringRef)kDomain;
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberDoubleType, &speed);
    CFPreferencesSetValue(CFSTR("speed"), n, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFRelease(n);
    CFPreferencesAppSynchronize(dom);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.nucleartweaks.animation-nuke/changed"), NULL, NULL, true);
    [self updateFooter];
}

@end
