// AnimationNuke — scale every decorative UI animation from 0.5x (half speed)
// to 100x (effectively instant). Everything that "is just there to look nice"
// runs through a handful of UIKit/CoreAnimation entry points; we scale the
// duration at each one and nothing else. No frame-rate games, no CADisplayLink
// tampering (that would break finger-tracking scroll), no SpringBoard patching.
//
// Speed lives in the preference domain com.nucleartweaks.animation-nuke (key
// "speed"), written by the Settings pane; a Darwin notification reloads it
// live in every hooked process — no respring needed.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <dlfcn.h>

// The substrate provider differs per jailbreak (ElleKit, libhooker, libsubstitute,
// or this sim's CydiaSubstrate.framework shim) and may not be a linked dependency
// of this dylib — resolving MSHookMessageEx through the linker can bind NULL and
// segfault. Find it explicitly across the known homes; skip cleanly if absent.
typedef void (*AN_MSHook)(Class, SEL, IMP, IMP *);

static NSString *const kDomain   = @"com.nucleartweaks.animation-nuke";
static NSString *const kSpeedKey = @"speed";
static NSString *const kChanged  = @"com.nucleartweaks.animation-nuke/changed";

static double gSpeed = 1.0;                       // multiplier: 0.5 … 100
static os_log_t gLog;
static int gBudget = 12;                          // rate-limited proof logs

static inline CFTimeInterval ANScale(CFTimeInterval d) {
    if (d <= 0.0 || gSpeed == 1.0) return d;
    CFTimeInterval s = d / gSpeed;
    if (s < 0.0005) s = 0.0;                      // below vsync — just snap
    return s;
}

static void ANLogScale(const char *what, CFTimeInterval from, CFTimeInterval to) {
    if (gBudget <= 0 || from == to) return;
    gBudget--;
    os_log(gLog, "%s: %{public}.3fs -> %{public}.3fs (speed %{public}.1fx)",
           what, from, to, gSpeed);
    NSLog(@"[AnimationNuke] %s: %.3fs -> %.3fs (speed %.1fx)", what, from, to, gSpeed);
    FILE *pf = fopen("/Users/spencer/animationnuke-proof.txt", "a");   // JB-sim host FS; absent on device
    if (pf) { fprintf(pf, "%s: %.3fs -> %.3fs (speed %.1fx)\n", what, from, to, gSpeed); fclose(pf); }
}

// ─── preferences ────────────────────────────────────────────────────────────

static void ANReload(void) {
    CFStringRef dom = (__bridge CFStringRef)kDomain;
    CFPreferencesAppSynchronize(dom);
    CFNumberRef n = (CFNumberRef)CFPreferencesCopyValue((__bridge CFStringRef)kSpeedKey,
                        dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    double v = 1.0;
    if (n) { CFNumberGetValue(n, kCFNumberDoubleType, &v); CFRelease(n); }
    if (v < 0.5)   v = 0.5;
    if (v > 100.0) v = 100.0;
    if (v != gSpeed) {
        gSpeed = v;
        gBudget = 12;
        os_log(gLog, "speed set to %{public}.2fx", v);
        NSLog(@"[AnimationNuke] speed set to %.2fx", v);
    }
}

static void ANPrefsChanged(CFNotificationCenterRef c, void *obs,
                           CFNotificationName n, const void *p, CFDictionaryRef u) {
    ANReload();
}

// ─── UIView animation blocks ────────────────────────────────────────────────
// Signatures: (Class self, SEL _cmd, …). Where a delay exists it is scaled
// too — waiting is exactly the waste this tweak removes.

typedef void (^ANBoolBlock)(BOOL);

typedef void (*AN_D_A)(Class, SEL, NSTimeInterval, void (^)(void));
typedef void (*AN_D_A_C)(Class, SEL, NSTimeInterval, void (^)(void), ANBoolBlock);
typedef void (*AN_D_S_O_A_C)(Class, SEL, NSTimeInterval, NSTimeInterval, UIViewAnimationOptions, void (^)(void), ANBoolBlock);
typedef void (*AN_Spring7)(Class, SEL, NSTimeInterval, NSTimeInterval, CGFloat, CGFloat, UIViewAnimationOptions, void (^)(void), ANBoolBlock);
typedef void (*AN_SpringBounce)(Class, SEL, NSTimeInterval, CGFloat, CGFloat, NSTimeInterval, UIViewAnimationOptions, void (^)(void), ANBoolBlock);
typedef void (*AN_Keyframes)(Class, SEL, NSTimeInterval, NSTimeInterval, UIViewKeyframeAnimationOptions, void (^)(void), ANBoolBlock);

static AN_D_A           orig_D_A;
static AN_D_A_C         orig_D_A_C;
static AN_D_S_O_A_C     orig_D_S_O_A_C;
static AN_Spring7       orig_Spring7;
static AN_SpringBounce  orig_SpringBounce;
static AN_Keyframes     orig_Keyframes;

static void rep_D_A(Class c, SEL s, NSTimeInterval d, void (^a)(void)) {
    ANLogScale("animate:anim", d, ANScale(d));
    orig_D_A(c, s, ANScale(d), a);
}
static void rep_D_A_C(Class c, SEL s, NSTimeInterval d, void (^a)(void), ANBoolBlock comp) {
    ANLogScale("animate:anim:comp", d, ANScale(d));
    orig_D_A_C(c, s, ANScale(d), a, comp);
}
static void rep_D_S_O_A_C(Class c, SEL s, NSTimeInterval d, NSTimeInterval delay,
                          UIViewAnimationOptions o, void (^a)(void), ANBoolBlock comp) {
    ANLogScale("animate:dur:delay", d, ANScale(d));
    orig_D_S_O_A_C(c, s, ANScale(d), ANScale(delay), o, a, comp);
}
static void rep_Spring7(Class c, SEL s, NSTimeInterval d, NSTimeInterval delay, CGFloat damp,
                        CGFloat vel, UIViewAnimationOptions o, void (^a)(void), ANBoolBlock comp) {
    ANLogScale("spring", d, ANScale(d));
    orig_Spring7(c, s, ANScale(d), ANScale(delay), damp, vel, o, a, comp);
}
static void rep_SpringBounce(Class c, SEL s, NSTimeInterval d, CGFloat bounce, CGFloat vel,
                             NSTimeInterval delay, UIViewAnimationOptions o, void (^a)(void), ANBoolBlock comp) {
    ANLogScale("springBounce", d, ANScale(d));
    orig_SpringBounce(c, s, ANScale(d), bounce, vel, ANScale(delay), o, a, comp);
}
static void rep_Keyframes(Class c, SEL s, NSTimeInterval d, NSTimeInterval delay,
                          UIViewKeyframeAnimationOptions o, void (^a)(void), ANBoolBlock comp) {
    ANLogScale("keyframes", d, ANScale(d));
    orig_Keyframes(c, s, ANScale(d), ANScale(delay), o, a, comp);
}

// ─── UIViewPropertyAnimator ─────────────────────────────────────────────────
// SpringBoard's interruptible transition/icon-zoom animators on modern iOS
// are fraction-driven animators; scaling their duration scales app open/close
// and switcher even though they never call UIView animate directly.

typedef id (*AN_PA_InitDC)(id, SEL, NSTimeInterval, UIViewAnimationCurve, void (^)(void));
typedef id (*AN_PA_InitDT)(id, SEL, NSTimeInterval, id);
typedef id (*AN_PA_InitSpring)(id, SEL, NSTimeInterval, NSTimeInterval, CGFloat, CGFloat, UIViewAnimationCurve, UIViewAnimationOptions, void (^)(void));
typedef void (*AN_PA_SetDur)(id, SEL, NSTimeInterval);

static AN_PA_InitDC     orig_PA_InitDC;
static AN_PA_InitDT     orig_PA_InitDT;
static AN_PA_InitSpring orig_PA_InitSpring;
static AN_PA_SetDur     orig_PA_SetDur;

static __thread BOOL gInsideAnimatorInit = NO;

static id rep_PA_InitDC(id self, SEL s, NSTimeInterval d, UIViewAnimationCurve curve, void (^a)(void)) {
    ANLogScale("propAnim.init", d, ANScale(d));
    gInsideAnimatorInit = YES;
    id r = orig_PA_InitDC(self, s, ANScale(d), curve, a);
    gInsideAnimatorInit = NO;
    return r;
}
static id rep_PA_InitDT(id self, SEL s, NSTimeInterval d, id params) {
    ANLogScale("propAnim.initTiming", d, ANScale(d));
    gInsideAnimatorInit = YES;
    id r = orig_PA_InitDT(self, s, ANScale(d), params);
    gInsideAnimatorInit = NO;
    return r;
}
static id rep_PA_InitSpring(id self, SEL s, NSTimeInterval d, NSTimeInterval delay, CGFloat damp,
                            CGFloat vel, UIViewAnimationCurve curve, UIViewAnimationOptions o, void (^a)(void)) {
    ANLogScale("propAnim.initSpring", d, ANScale(d));
    gInsideAnimatorInit = YES;
    id r = orig_PA_InitSpring(self, s, ANScale(d), ANScale(delay), damp, vel, curve, o, a);
    gInsideAnimatorInit = NO;
    return r;
}
static void rep_PA_SetDur(id self, SEL s, NSTimeInterval d) {
    orig_PA_SetDur(self, s, gInsideAnimatorInit ? d : ANScale(d));
}

// ─── CoreAnimation ──────────────────────────────────────────────────────────
// CAAnimation is the base of every CABasicAnimation/CAKeyframeAnimation/
// CASpringAnimation instance — scroll rebound, layer fades, animations that
// never touch the UIView block API.

typedef void (*AN_CA_SetDur)(id, SEL, CFTimeInterval);
typedef void (*AN_CT_SetDur)(Class, SEL, CFTimeInterval);

static AN_CA_SetDur orig_CA_SetDur;
static AN_CT_SetDur orig_CT_SetDur;

static void rep_CA_SetDur(id self, SEL s, CFTimeInterval d) {
    ANLogScale("CAAnimation.setDuration", d, ANScale(d));
    orig_CA_SetDur(self, s, ANScale(d));
}
static void rep_CT_SetDur(Class c, SEL s, CFTimeInterval d) {
    ANLogScale("CATransaction.setAnimationDuration", d, ANScale(d));
    orig_CT_SetDur(c, s, ANScale(d));
}

// ─── installation ───────────────────────────────────────────────────────────

static AN_MSHook gHook;   // resolved at ctor; NULL → skip hooks, never crash

static void ANHookInstance(Class c, SEL sel, IMP rep, IMP *orig) {
    if (gHook && c && class_getInstanceMethod(c, sel)) gHook(c, sel, rep, orig);
}
static void ANHookClass(Class c, SEL sel, IMP rep, IMP *orig) {
    if (!gHook || !c) return;
    Class meta = object_getClass(c);
    if (class_getInstanceMethod(meta, sel)) gHook(meta, sel, rep, orig);
}

static AN_MSHook ANFindSubstrate(void) {
    // Global pool first — the loader may have dlopen'd us RTLD_FIRST, which is
    // exactly what binds our import stub to NULL (measured on the iOS 27 JB sim).
    AN_MSHook h = (AN_MSHook)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (h) return h;
    static const char *homes[] = {
        "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",        // rootful (JB sim)
        "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/var/jb/usr/lib/libellekit.dylib",                                   // ElleKit (Dopamine etc.)
        "/var/jb/usr/lib/libsubstitute.dylib",
        "/var/jb/usr/lib/TweakLoader.dylib",
        "/usr/lib/libsubstitute.dylib",
    };
    for (size_t i = 0; i < sizeof(homes)/sizeof(homes[0]) && !h; i++) {
        void *img = dlopen(homes[i], RTLD_LAZY);
        if (img) h = (AN_MSHook)dlsym(img, "MSHookMessageEx");
    }
    return h;
}

%ctor {
    @autoreleasepool {
        gLog = os_log_create("com.nucleartweaks", "AnimationNuke");
        if (!NSClassFromString(@"UIApplication")) return;   // GUI processes only

        ANReload();
        gHook = ANFindSubstrate();
        if (!gHook) { os_log(gLog, "no substrate symbol found — idle (no hooks)"); NSLog(@"[AnimationNuke] no substrate symbol — idle"); return; }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, ANPrefsChanged,
                                        (__bridge CFStringRef)kChanged, NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);

        Class uiview = objc_getClass("UIView");
        ANHookClass(uiview, @selector(animateWithDuration:animations:),                         (IMP)rep_D_A,       (IMP *)&orig_D_A);
        ANHookClass(uiview, @selector(animateWithDuration:animations:completion:),              (IMP)rep_D_A_C,     (IMP *)&orig_D_A_C);
        ANHookClass(uiview, @selector(animateWithDuration:delay:options:animations:completion:),(IMP)rep_D_S_O_A_C, (IMP *)&orig_D_S_O_A_C);
        ANHookClass(uiview, @selector(animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:), (IMP)rep_Spring7, (IMP *)&orig_Spring7);
        ANHookClass(uiview, @selector(animateWithSpringDuration:bounce:initialSpringVelocity:delay:options:animations:completion:),           (IMP)rep_SpringBounce, (IMP *)&orig_SpringBounce);
        ANHookClass(uiview, @selector(animateKeyframesWithDuration:delay:options:animations:completion:),                                     (IMP)rep_Keyframes, (IMP *)&orig_Keyframes);

        Class pa = objc_getClass("UIViewPropertyAnimator");
        ANHookInstance(pa, @selector(initWithDuration:curve:animations:),                                                     (IMP)rep_PA_InitDC,    (IMP *)&orig_PA_InitDC);
        ANHookInstance(pa, @selector(initWithDuration:timingParameters:),                                                     (IMP)rep_PA_InitDT,    (IMP *)&orig_PA_InitDT);
        ANHookInstance(pa, @selector(initWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:curve:options:animations:), (IMP)rep_PA_InitSpring, (IMP *)&orig_PA_InitSpring);
        ANHookInstance(pa, @selector(setDuration:),                                                                            (IMP)rep_PA_SetDur,    (IMP *)&orig_PA_SetDur);

        ANHookInstance(objc_getClass("CAAnimation"), @selector(setDuration:), (IMP)rep_CA_SetDur, (IMP *)&orig_CA_SetDur);

        ANHookClass(objc_getClass("CATransaction"), @selector(setAnimationDuration:), (IMP)rep_CT_SetDur, (IMP *)&orig_CT_SetDur);

        os_log(gLog, "installed (speed %{public}.2fx)", gSpeed);
        NSLog(@"[AnimationNuke] installed (speed %.2fx)", gSpeed);
        FILE *pf = fopen("/Users/spencer/animationnuke-proof.txt", "a"); // JB-sim only, see above
        if (pf) { fprintf(pf, "installed pid=%d speed=%.2f hook=%p\n",
                          getpid(), gSpeed, (void *)gHook); fclose(pf); }
    }
}
