#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Process-lifetime singleton that owns the CoreLocation work. The codegen
 * TurboModule glue (`RNBackgroundGeolocation.mm`) forwards to this engine so the
 * native logic survives RN bridge reloads and (in later phases) keeps running
 * while the JS context is torn down.
 *
 * Implemented in Objective-C (not Swift) to avoid the Swift-header-from-ObjC++
 * interop fragility under `use_frameworks! :linkage => :static`.
 *
 * Phase 1 scope: foreground one-shot `getCurrentPosition`, odometer, and
 * Transistor-shaped Location normalisation. Continuous tracking, the motion
 * state machine, geofencing, persistence and HTTP land in later phases.
 */
@interface BGGeoEngine : NSObject

@property (class, nonatomic, readonly) BGGeoEngine *shared;

/// Sink for native events. The TurboModule sets this to fan engine events into
/// the codegen `emitOnX:` methods. Names: location, locationerror,
/// providerchange, heartbeat, motionchange, geofence, geofenceschange.
@property (nonatomic, copy, nullable) void (^eventEmitter)(NSString *name, NSDictionary *body);

/// Merge a JS config dictionary into the engine's live config.
- (void)applyConfig:(nullable NSDictionary *)config;

/// Whether tracking is currently enabled.
@property (nonatomic, readonly) BOOL enabled;

/// Build the State dictionary the JS `ready/setConfig/start/stop` callbacks expect.
- (NSDictionary *)stateDictionary;

/// Begin / end tracking (Phase 2 toggles enabled + provider monitoring; Phase 3
/// adds the continuous location stream + motion state machine).
- (void)startTracking;
- (void)stopTracking;

/// Non-nil LICENSE_* code when the current build/license blocks tracking; nil
/// when licensed (or a debuggable/simulator evaluation build). Re-evaluated on
/// applyConfig (the config carries the `license` key).
- (nullable NSString *)licenseErrorCode;

/// Escalating permission request (WhenInUse -> Always per config). Resolves a
/// numeric AUTHORIZATION_STATUS_*.
- (void)requestPermission:(void (^)(NSInteger status))resolve
                   reject:(void (^)(NSString *code, NSString *message))reject;

/// iOS 14+: request temporary Precise ("full") accuracy; `purpose` is a key in
/// the app's NSLocationTemporaryUsageDescriptionDictionary. Completes with the
/// resulting accuracy authorization: 0 = full, 1 = reduced. iOS < 14 completes 0.
- (void)requestTemporaryFullAccuracy:(NSString *)purpose
                          completion:(void (^)(NSInteger accuracyAuthorization))completion;

/// Current provider state: { status, enabled, gps, network }.
- (NSDictionary *)providerState;

/// Current OS Low Power Mode state (Transistor isPowerSaveMode()).
- (BOOL)isPowerSaveMode;

/// Tokens the native uploader currently holds: { accessToken, refreshToken }.
/// It may have refreshed them on a background 401/403 while JS was dead, so JS
/// reconciles its store against these on foreground.
- (NSDictionary *)authStateDictionary;

/// Upload queue: manual drain ({ count } pending at call time), queued
/// records ({ locations }), and destroy-all ({ count } removed).
- (NSDictionary *)syncQueue;
- (NSDictionary *)queuedLocations;
- (NSDictionary *)destroyQueuedLocations;
- (NSUInteger)pendingQueueCount;                          // records in the upload queue
- (BOOL)destroyQueuedLocation:(NSString *)uuid;           // NO when no such record
- (void)insertQueuedLocation:(NSDictionary *)location;    // normal persist path (autoSync/cap apply)

/// Native log queue (see BGGeoLogger). Entries are Transistor-shaped:
/// { ts (ISO), level (number), src, event, message?, data? }, newest-first.
- (NSArray<NSDictionary *> *)logEntries:(NSInteger)limit;
- (NSInteger)destroyLogs;      // rows removed
- (NSInteger)pendingLogCount;  // rows awaiting upload
- (void)flushLogs;             // manual upload trigger (no-op without logUrl)

/// One-shot location. Options: persist, samples, timeout, maximumAge,
/// desiredAccuracy, extras. Resolves a Transistor-shaped Location dictionary.
- (void)getCurrentPosition:(nullable NSDictionary *)options
                   resolve:(void (^)(NSDictionary *location))resolve
                    reject:(void (^)(NSString *code, NSString *message))reject;

/// Current odometer reading (metres).
- (double)odometer;

/// Reset the odometer to `value` (metres). Resolves the current Location.
- (void)setOdometer:(double)value
            resolve:(void (^)(NSDictionary *location))resolve
             reject:(void (^)(NSString *code, NSString *message))reject;

/// Manual motion-state override (Transistor changePace); NO while disabled.
- (BOOL)changePace:(BOOL)isMoving;

/// Begin / end a periodic position watch. Each fix is emitted via `onLocation`
/// with the supplied `extras` echoed (so the JS facade can route it to the
/// watch's success callback). Options: interval (ms), persist, extras.
- (void)startWatch:(nullable NSDictionary *)options;
- (void)stopWatch;

/// Current accumulated odometer distance in metres.
@property (nonatomic, readonly) double odometer;

/// Build a Transistor-shaped Location dictionary from a CLLocation.
- (NSDictionary *)normalizeLocation:(CLLocation *)location
                             extras:(nullable NSDictionary *)extras
                             sample:(BOOL)sample
                              event:(nullable NSString *)event;

/// Geofence CRUD — forwards 1:1 to BGGeoGeofenceManager.
- (nullable NSString *)addGeofences:(NSArray<NSDictionary *> *)geofences; // INVALID_GEOFENCE or nil
- (BOOL)removeGeofence:(NSString *)identifier;
- (void)removeAllGeofences;
- (NSArray<NSDictionary *> *)geofences;
- (BOOL)geofenceExists:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
