#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Central engine logger: mirrors every line to os_log unconditionally (the
 * existing Console.app workflow), and — when `logLevel` (config) admits it —
 * persists a row into bgeo.db `log_entries` for server upload by
 * -[BGGeoHttpStore flushLogs]. Never throws, never blocks the caller: DB
 * writes run on a private serial queue and swallow failures. BGGeoDb itself
 * must NOT log through here (recursion guard — it keeps raw os_log).
 * Levels: Transistor logLevel scale 0=OFF 1=ERROR 2=WARN 3=INFO 4=DEBUG
 * 5=VERBOSE (bgeo::LogPolicy).
 */
@interface BGGeoLogger : NSObject

+ (void)configure:(NSInteger)level;

+ (void)log:(NSInteger)level
      event:(NSString *)event
    message:(nullable NSString *)message
       data:(nullable NSString *)data
        src:(NSString *)src;

+ (void)error:(NSString *)event message:(nullable NSString *)message;
+ (void)warn:(NSString *)event message:(nullable NSString *)message;
+ (void)info:(NSString *)event message:(nullable NSString *)message;
+ (void)debug:(NSString *)event message:(nullable NSString *)message;
+ (void)verbose:(NSString *)event message:(nullable NSString *)message;

/// Upload request: fired (once per crossing) when pending rows reach
/// LogPolicy::kBatchLimit, and — debounced — for each line logged while
/// `foreground` is YES.
@property (class, nonatomic, copy, nullable) void (^onFlushRequest)(void);

/// Set by the engine on app foreground/background. While YES, a logged line
/// arms a short coalescing timer so a watching console sees it in about
/// LogPolicy::kForegroundFlushDelayMs instead of waiting for the next
/// heartbeat. Stays NO in background by design: the piggyback triggers exist
/// so log upload never wakes the radio on its own.
@property (class, nonatomic, assign) BOOL foreground;

@end

NS_ASSUME_NONNULL_END
