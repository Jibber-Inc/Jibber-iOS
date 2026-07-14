//
//  ParseSimulatorCompatibility.m
//  Jibber
//
//  ParseObjC 6.1.1 scans each loaded Mach-O image to discover PFObject
//  subclasses. That scan stalls in dyld on the iOS 27 simulator. Enumerating
//  the already-loaded Objective-C runtime classes provides the same automatic
//  registration without asking dyld to inspect the executable image.
//

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <objc/message.h>
#import <objc/runtime.h>

#if TARGET_OS_SIMULATOR

static void JibberScanForParseSubclasses(id controller, SEL command, BOOL shouldSubscribe) {
    (void)command;
    (void)shouldSubscribe;

    Class parseObjectClass = NSClassFromString(@"PFObject");
    Protocol *subclassingProtocol = NSProtocolFromString(@"PFSubclassing");
    Protocol *skipRegistrationProtocol =
        NSProtocolFromString(@"PFSubclassingSkipAutomaticRegistration");
    SEL registerSelector = NSSelectorFromString(@"registerSubclass:");

    if (parseObjectClass == Nil || subclassingProtocol == nil ||
        skipRegistrationProtocol == nil || ![controller respondsToSelector:registerSelector]) {
        return;
    }

    int estimatedClassCount = objc_getClassList(NULL, 0);
    if (estimatedClassCount <= 0) {
        return;
    }

    __unsafe_unretained Class *classes =
        (__unsafe_unretained Class *)calloc((size_t)estimatedClassCount, sizeof(Class));
    if (classes == NULL) {
        return;
    }
    int classCount = objc_getClassList(classes, estimatedClassCount);

    for (int index = 0; index < classCount; index++) {
        Class candidate = classes[index];
        if (candidate == parseObjectClass) {
            continue;
        }

        for (Class superclass = candidate;
             superclass != Nil;
             superclass = class_getSuperclass(superclass)) {
            if (superclass == parseObjectClass) {
                if (class_conformsToProtocol(candidate, subclassingProtocol) &&
                    !class_conformsToProtocol(candidate, skipRegistrationProtocol)) {
                    ((void (*)(id, SEL, Class))objc_msgSend)(
                        controller,
                        registerSelector,
                        candidate
                    );
                }
                break;
            }
        }
    }

    free(classes);
}

__attribute__((constructor))
static void JibberInstallParseSimulatorCompatibility(void) {
    if (@available(iOS 27.0, *)) {
        Class controllerClass = NSClassFromString(@"PFObjectSubclassingController");
        SEL scanSelector = NSSelectorFromString(@"scanForUnregisteredSubclasses:");
        Method scanMethod = class_getInstanceMethod(controllerClass, scanSelector);

        if (scanMethod != NULL) {
            method_setImplementation(scanMethod, (IMP)JibberScanForParseSubclasses);
        }
    }
}

#endif
