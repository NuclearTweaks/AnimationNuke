// AnimationNuke — Nukes the wait: scale every decorative UI animation 0.5x–100x.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

//%hook SomeClass
//- (void)someMethod {
//    NSLog(@"[AnimationNuke] someMethod");
//    %orig;
//}
//%end

%ctor {
    NSLog(@"[AnimationNuke] loaded into %@ (pid %d)",
          [NSProcessInfo processInfo].processName,
          [[NSProcessInfo processInfo] processIdentifier]);
}
