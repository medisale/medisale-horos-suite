#import <Foundation/Foundation.h>

#import "ImageContext.h"
#import "MeasurementRecord.h"
#import "SQLiteMeasurementStore.h"
#import <math.h>
#import <sqlite3.h>
#import <sys/stat.h>

static NSUInteger Assertions = 0;
static NSUInteger Failures = 0;

static void Check(BOOL condition, NSString *message)
{
    Assertions++;
    if (!condition) {
        Failures++;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    }
}

static NSString *SyntheticIdentity(NSString *kind)
{
    return [NSString stringWithFormat:@"synthetic-%@-%@", kind, NSUUID.UUID.UUIDString];
}

static ImageContext *Context(NSInteger frame)
{
    return [[ImageContext alloc]
        initWithStudyInstanceUID:SyntheticIdentity(@"study")
               seriesInstanceUID:SyntheticIdentity(@"series")
                  sopInstanceUID:SyntheticIdentity(@"instance")
                     frameNumber:frame
                      pixelWidth:128
                     pixelHeight:96
                   pixelSpacingX:0.5
                   pixelSpacingY:0.75];
}

static ImageContext *ContextWithFrame(ImageContext *context, NSInteger frame)
{
    return [[ImageContext alloc]
        initWithStudyInstanceUID:context.studyInstanceUID
               seriesInstanceUID:context.seriesInstanceUID
                  sopInstanceUID:context.sopInstanceUID
                     frameNumber:frame
                      pixelWidth:context.pixelWidth
                     pixelHeight:context.pixelHeight
                   pixelSpacingX:context.pixelSpacingX
                   pixelSpacingY:context.pixelSpacingY];
}

static MeasurementRecord *Record(NSString *identifier,
                                 ImageContext *context,
                                 double ax, double ay,
                                 double bx, double by,
                                 NSDate *created,
                                 NSDate *updated)
{
    return [[MeasurementRecord alloc]
        initWithMeasurementID:identifier
                 imageContext:context
                    endpointAX:ax
                    endpointAY:ay
                    endpointBX:bx
                    endpointBY:by
                  pixelDistance:hypot(bx - ax, by - ay)
                  schemaVersion:MedisaleMeasurementSchemaVersion
                      createdAt:created
                      updatedAt:updated];
}

static sqlite3 *OpenReadOnly(NSURL *databaseURL)
{
    sqlite3 *database = NULL;
    int result = sqlite3_open_v2(databaseURL.fileSystemRepresentation,
        &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX |
        SQLITE_OPEN_NOFOLLOW, NULL);
    if (result != SQLITE_OK) {
        if (database != NULL) {
            sqlite3_close(database);
        }
        return NULL;
    }
    if (sqlite3_exec(database, "PRAGMA query_only = ON", NULL, NULL, NULL) != SQLITE_OK) {
        sqlite3_close(database);
        return NULL;
    }
    return database;
}

static NSInteger RecordCount(NSURL *databaseURL)
{
    sqlite3 *database = OpenReadOnly(databaseURL);
    if (database == NULL) {
        return -1;
    }
    sqlite3_stmt *statement = NULL;
    NSInteger count = -1;
    if (sqlite3_prepare_v2(database, "SELECT count(*) FROM measurements", -1,
                           &statement, NULL) == SQLITE_OK &&
        sqlite3_step(statement) == SQLITE_ROW) {
        count = (NSInteger)sqlite3_column_int64(statement, 0);
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return count;
}

static NSDictionary *ReadRecord(NSURL *databaseURL, NSString *identifier)
{
    sqlite3 *database = OpenReadOnly(databaseURL);
    if (database == NULL) {
        return nil;
    }
    static const char *query =
        "SELECT study_instance_uid, series_instance_uid, sop_instance_uid,"
        "frame_number, endpoint_a_x, endpoint_a_y, endpoint_b_x, endpoint_b_y,"
        "pixel_distance, schema_version, created_at, updated_at "
        "FROM measurements WHERE measurement_id = ?";
    sqlite3_stmt *statement = NULL;
    NSMutableDictionary *record = nil;
    if (sqlite3_prepare_v2(database, query, -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, identifier.UTF8String, -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            record = [NSMutableDictionary dictionary];
            NSArray<NSString *> *textKeys = @[@"study", @"series", @"instance"];
            for (int index = 0; index < 3; index++) {
                const unsigned char *value = sqlite3_column_text(statement, index);
                record[textKeys[index]] = value == NULL ? @"" :
                    [NSString stringWithUTF8String:(const char *)value];
            }
            record[@"frame"] = @(sqlite3_column_int64(statement, 3));
            record[@"ax"] = @(sqlite3_column_double(statement, 4));
            record[@"ay"] = @(sqlite3_column_double(statement, 5));
            record[@"bx"] = @(sqlite3_column_double(statement, 6));
            record[@"by"] = @(sqlite3_column_double(statement, 7));
            record[@"distance"] = @(sqlite3_column_double(statement, 8));
            record[@"version"] = @(sqlite3_column_int64(statement, 9));
            record[@"created"] = @(sqlite3_column_double(statement, 10));
            record[@"updated"] = @(sqlite3_column_double(statement, 11));
        }
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return record;
}

static BOOL IntegrityPasses(NSURL *databaseURL)
{
    sqlite3 *database = OpenReadOnly(databaseURL);
    if (database == NULL) {
        return NO;
    }
    sqlite3_stmt *statement = NULL;
    BOOL passed = NO;
    if (sqlite3_prepare_v2(database, "PRAGMA integrity_check", -1,
                           &statement, NULL) == SQLITE_OK &&
        sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *value = sqlite3_column_text(statement, 0);
        passed = value != NULL && strcmp((const char *)value, "ok") == 0;
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return passed;
}

static BOOL ExclusiveTransactionPasses(NSURL *databaseURL)
{
    sqlite3 *database = NULL;
    int result = sqlite3_open_v2(databaseURL.fileSystemRepresentation,
        &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX |
        SQLITE_OPEN_NOFOLLOW, NULL);
    if (result != SQLITE_OK) {
        if (database != NULL) {
            sqlite3_close(database);
        }
        return NO;
    }
    sqlite3_busy_timeout(database, 250);
    BOOL passed = sqlite3_exec(database, "BEGIN EXCLUSIVE", NULL, NULL, NULL) == SQLITE_OK;
    if (passed) {
        passed = sqlite3_exec(database, "ROLLBACK", NULL, NULL, NULL) == SQLITE_OK;
    }
    sqlite3_close(database);
    return passed;
}

static NSInteger UserVersion(NSURL *databaseURL)
{
    sqlite3 *database = OpenReadOnly(databaseURL);
    if (database == NULL) {
        return -1;
    }
    sqlite3_stmt *statement = NULL;
    NSInteger version = -1;
    if (sqlite3_prepare_v2(database, "PRAGMA user_version", -1,
                           &statement, NULL) == SQLITE_OK &&
        sqlite3_step(statement) == SQLITE_ROW) {
        version = sqlite3_column_int(statement, 0);
    }
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return version;
}

static void VerifyFailure(SQLiteMeasurementStore *store,
                          MeasurementRecord *attempt,
                          MeasurementRecord *knownGood,
                          MedisaleSQLiteFailureInjection injection)
{
    NSInteger beforeCount = RecordCount(store.databaseURL);
    NSDictionary *before = ReadRecord(store.databaseURL, knownGood.measurementID);
    store.failureInjection = injection;
    NSError *error = nil;
    Check(![store saveMeasurement:attempt error:&error], @"injected save must fail");
    Check(error != nil, @"injected failure must return an error");
    store.failureInjection = MedisaleSQLiteFailureInjectionNone;
    Check(RecordCount(store.databaseURL) == beforeCount,
          @"failure must not change record count");
    Check([ReadRecord(store.databaseURL, knownGood.measurementID) isEqual:before],
          @"failure must not change an existing record");
    Check(IntegrityPasses(store.databaseURL), @"failure must preserve integrity");
    error = nil;
    Check([store saveMeasurement:knownGood error:&error],
          @"a normal save must succeed after failure");
}

int main(void)
{
    @autoreleasepool {
        NSURL *workspace = [NSURL fileURLWithPath:NSFileManager.defaultManager.currentDirectoryPath
                                       isDirectory:YES];
        NSURL *temporaryRoot = [[workspace URLByAppendingPathComponent:@"build"
                                                            isDirectory:YES]
            URLByAppendingPathComponent:[@"p1-11-store-test-"
                stringByAppendingString:NSUUID.UUID.UUIDString]
                         isDirectory:YES];
        NSURL *databaseURL = [[temporaryRoot URLByAppendingPathComponent:@"store"
                                                              isDirectory:YES]
            URLByAppendingPathComponent:@"measurements.sqlite3" isDirectory:NO];
        NSError *error = nil;
        SQLiteMeasurementStore *store = [[SQLiteMeasurementStore alloc]
            initWithDatabaseURL:databaseURL error:&error];
        Check(store != nil && error == nil, @"store initialization must succeed");
        if (store == nil) {
            [NSFileManager.defaultManager removeItemAtURL:temporaryRoot error:NULL];
            return 1;
        }

        NSString *homePrefix = [NSHomeDirectory().stringByStandardizingPath
            stringByAppendingString:@"/"];
        Check([store.databaseURL.path.stringByStandardizingPath hasPrefix:homePrefix],
              @"database must remain inside the user home");
        struct stat databaseStatus;
        struct stat parentStatus;
        Check(lstat(store.databaseURL.fileSystemRepresentation, &databaseStatus) == 0 &&
              S_ISREG(databaseStatus.st_mode) && !S_ISLNK(databaseStatus.st_mode) &&
              databaseStatus.st_uid == getuid() && (databaseStatus.st_mode & 0077) == 0,
              @"database must be an owned restrictive regular file");
        Check(lstat(store.databaseURL.URLByDeletingLastPathComponent.fileSystemRepresentation,
                    &parentStatus) == 0 && S_ISDIR(parentStatus.st_mode) &&
              !S_ISLNK(parentStatus.st_mode) && parentStatus.st_uid == getuid() &&
              (parentStatus.st_mode & 0077) == 0,
              @"database parent must be an owned restrictive directory");
        Check(UserVersion(store.databaseURL) == MedisaleMeasurementSchemaVersion,
              @"schema version must be explicit");
        Check(IntegrityPasses(store.databaseURL), @"new database integrity must pass");

        NSDate *created = [NSDate dateWithTimeIntervalSince1970:1000.0];
        NSString *firstID = NSUUID.UUID.UUIDString;
        ImageContext *firstContext = Context(0);
        MeasurementRecord *first = Record(firstID, firstContext,
                                          10.25, 20.5, 45.75, 60.125,
                                          created, created);
        Check([store saveMeasurement:first error:&error], @"initial save must succeed");
        Check(RecordCount(store.databaseURL) == 1, @"initial save must commit one record");
        NSDictionary *firstRow = ReadRecord(store.databaseURL, firstID);
        Check([firstRow[@"study"] isEqual:firstContext.studyInstanceUID] &&
              [firstRow[@"series"] isEqual:firstContext.seriesInstanceUID] &&
              [firstRow[@"instance"] isEqual:firstContext.sopInstanceUID] &&
              [firstRow[@"frame"] integerValue] == firstContext.frameNumber,
              @"stored image identity and frame must match");
        Check(fabs([firstRow[@"ax"] doubleValue] - first.endpointAX) < 0.000001 &&
              fabs([firstRow[@"ay"] doubleValue] - first.endpointAY) < 0.000001 &&
              fabs([firstRow[@"bx"] doubleValue] - first.endpointBX) < 0.000001 &&
              fabs([firstRow[@"by"] doubleValue] - first.endpointBY) < 0.000001 &&
              fabs([firstRow[@"distance"] doubleValue] - first.pixelDistance) < 0.000001,
              @"stored endpoints and distance must match");
        error = nil;
        MeasurementRecord *restoredFirst =
            [store latestMeasurementForImageContext:firstContext error:&error];
        Check(restoredFirst != nil && error == nil,
              @"exact image and frame must return a stored measurement");
        Check([restoredFirst.measurementID isEqual:firstID] &&
              fabs(restoredFirst.endpointAX - first.endpointAX) < 0.000001 &&
              fabs(restoredFirst.endpointBY - first.endpointBY) < 0.000001,
              @"restored identifier and image coordinates must match");

        ImageContext *wrongFrame = ContextWithFrame(firstContext, 1);
        error = nil;
        Check([store latestMeasurementForImageContext:wrongFrame error:&error] == nil &&
              error == nil,
              @"same SOP on a different frame must not restore");
        ImageContext *wrongImage = Context(0);
        error = nil;
        Check([store latestMeasurementForImageContext:wrongImage error:&error] == nil &&
              error == nil,
              @"a different SOP must not receive another image's measurement");

        NSDate *updatedAt = [NSDate dateWithTimeIntervalSince1970:1001.0];
        MeasurementRecord *updated = Record(firstID, firstContext,
                                            11.0, 21.0, 47.0, 61.0,
                                            created, updatedAt);
        Check([store saveMeasurement:updated error:&error], @"transactional update must succeed");
        Check(RecordCount(store.databaseURL) == 1, @"update must not add a second row");
        NSDictionary *updatedRow = ReadRecord(store.databaseURL, firstID);
        Check(fabs([updatedRow[@"bx"] doubleValue] - updated.endpointBX) < 0.000001 &&
              fabs([updatedRow[@"created"] doubleValue] - created.timeIntervalSince1970) < 0.000001 &&
              fabs([updatedRow[@"updated"] doubleValue] - updatedAt.timeIntervalSince1970) < 0.000001,
              @"update must preserve creation and replace mutable values");
        MeasurementRecord *restoredUpdate =
            [store latestMeasurementForImageContext:firstContext error:&error];
        Check([restoredUpdate.measurementID isEqual:firstID] &&
              fabs(restoredUpdate.endpointBX - updated.endpointBX) < 0.000001 &&
              fabs(restoredUpdate.updatedAt.timeIntervalSince1970 -
                   updatedAt.timeIntervalSince1970) < 0.000001,
              @"restore must return the transactionally updated values");

        NSString *secondID = NSUUID.UUID.UUIDString;
        ImageContext *secondContext = Context(1);
        MeasurementRecord *second = Record(secondID, secondContext,
                                           5.0, 6.0, 25.0, 26.0,
                                           created, updatedAt);
        Check([store saveMeasurement:second error:&error], @"second viewer save must succeed");
        Check(RecordCount(store.databaseURL) == 2, @"independent measurements must remain distinct");
        NSDictionary *secondRow = ReadRecord(store.databaseURL, secondID);
        Check([secondRow[@"instance"] isEqual:secondContext.sopInstanceUID] &&
              [secondRow[@"frame"] integerValue] == secondContext.frameNumber &&
              ![secondRow[@"instance"] isEqual:firstContext.sopInstanceUID],
              @"image and frame keys must not cross measurements");
        MeasurementRecord *restoredSecond =
            [store latestMeasurementForImageContext:secondContext error:&error];
        Check([restoredSecond.measurementID isEqual:secondID] &&
              restoredSecond.imageContext.frameNumber == secondContext.frameNumber,
              @"second Viewer image and frame must restore independently");

        ImageContext *invalidContext = Context(-1);
        MeasurementRecord *invalid = Record(firstID, invalidContext,
                                            1.0, 2.0, 3.0, 4.0,
                                            created, updatedAt);
        NSInteger invalidCount = RecordCount(store.databaseURL);
        NSDictionary *beforeInvalid = ReadRecord(store.databaseURL, firstID);
        error = nil;
        Check(![store saveMeasurement:invalid error:&error] && error != nil,
              @"invalid frame must fail safely");
        Check(RecordCount(store.databaseURL) == invalidCount &&
              [ReadRecord(store.databaseURL, firstID) isEqual:beforeInvalid],
              @"invalid input must not mutate records");

        MeasurementRecord *outsideImage = Record(firstID, firstContext,
                                                  -1.0, 2.0, 3.0, 4.0,
                                                  created, updatedAt);
        error = nil;
        Check(![store saveMeasurement:outsideImage error:&error] && error != nil,
              @"out-of-image coordinates must fail safely");
        Check(RecordCount(store.databaseURL) == invalidCount &&
              [ReadRecord(store.databaseURL, firstID) isEqual:beforeInvalid],
              @"out-of-image input must not mutate records");

        MeasurementRecord *attempt = Record(firstID, firstContext,
                                            30.0, 31.0, 70.0, 71.0,
                                            created, [NSDate dateWithTimeIntervalSince1970:1002.0]);
        VerifyFailure(store, attempt, updated, MedisaleSQLiteFailureInjectionConstraint);
        VerifyFailure(store, attempt, updated, MedisaleSQLiteFailureInjectionStatement);
        VerifyFailure(store, attempt, updated, MedisaleSQLiteFailureInjectionBeforeCommit);
        VerifyFailure(store, attempt, updated, MedisaleSQLiteFailureInjectionInterruptedSave);

        NSInteger lockedCount = RecordCount(store.databaseURL);
        sqlite3 *locker = NULL;
        Check(sqlite3_open_v2(store.databaseURL.fileSystemRepresentation, &locker,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW,
                              NULL) == SQLITE_OK,
              @"lock connection must open");
        if (locker != NULL) {
            Check(sqlite3_exec(locker, "BEGIN EXCLUSIVE", NULL, NULL, NULL) == SQLITE_OK,
                  @"exclusive test lock must start");
            error = nil;
            Check(![store saveMeasurement:attempt error:&error] && error != nil,
                  @"busy database save must fail safely");
            sqlite3_exec(locker, "ROLLBACK", NULL, NULL, NULL);
            sqlite3_close(locker);
            Check(RecordCount(store.databaseURL) == lockedCount,
                  @"busy failure must leave record count unchanged");
            Check([store saveMeasurement:updated error:&error],
                  @"normal save after busy failure must succeed");
        }

        NSString *databasePath = store.databaseURL.path;
        NSString *parentPath = store.databaseURL.URLByDeletingLastPathComponent.path;
        chmod(databasePath.fileSystemRepresentation, 0400);
        chmod(parentPath.fileSystemRepresentation, 0500);
        error = nil;
        BOOL readOnlySave = [store saveMeasurement:attempt error:&error];
        chmod(parentPath.fileSystemRepresentation, 0700);
        chmod(databasePath.fileSystemRepresentation, 0600);
        Check(!readOnlySave && error != nil, @"read-only I/O save must fail safely");
        Check(RecordCount(store.databaseURL) == 2,
              @"read-only failure must leave record count unchanged");
        Check(IntegrityPasses(store.databaseURL), @"read-only failure must preserve integrity");
        Check([store saveMeasurement:updated error:&error],
              @"normal save after I/O failure must succeed");

        SQLiteMeasurementStore *reopened = [[SQLiteMeasurementStore alloc]
            initWithDatabaseURL:store.databaseURL error:&error];
        Check(reopened != nil && RecordCount(reopened.databaseURL) == 2,
              @"committed records must remain after reopening the store");
        Check(IntegrityPasses(reopened.databaseURL), @"final integrity must pass");
        MeasurementRecord *relaunchRestore =
            [reopened latestMeasurementForImageContext:firstContext error:&error];
        Check([relaunchRestore.measurementID isEqual:firstID] &&
              fabs(relaunchRestore.endpointBX - updated.endpointBX) < 0.000001,
              @"reopened store must restore the exact committed measurement");

        store = nil;
        reopened = nil;
        Check(ExclusiveTransactionPasses(databaseURL),
              @"closed primary stores must leave no database lock");

        for (NSUInteger cycle = 0; cycle < 10; cycle++) {
            @autoreleasepool {
                NSURL *cycleDirectory = [temporaryRoot
                    URLByAppendingPathComponent:[NSString stringWithFormat:
                        @"lifecycle-%lu", (unsigned long)cycle]
                                     isDirectory:YES];
                NSURL *cycleDatabase = [cycleDirectory
                    URLByAppendingPathComponent:@"measurements.sqlite3"
                                     isDirectory:NO];
                NSError *cycleError = nil;
                SQLiteMeasurementStore *cycleStore = [[SQLiteMeasurementStore alloc]
                    initWithDatabaseURL:cycleDatabase error:&cycleError];
                Check(cycleStore != nil && cycleError == nil,
                      @"lifecycle store open must succeed");

                ImageContext *cycleContext = Context((NSInteger)(cycle % 2));
                NSString *cycleID = NSUUID.UUID.UUIDString;
                NSDate *cycleCreated = [NSDate dateWithTimeIntervalSince1970:
                    2000.0 + (NSTimeInterval)cycle * 2.0];
                MeasurementRecord *cycleInitial = Record(
                    cycleID, cycleContext, 8.0, 9.0, 30.0, 31.0,
                    cycleCreated, cycleCreated);
                Check([cycleStore saveMeasurement:cycleInitial error:&cycleError],
                      @"lifecycle initial save must commit");

                NSDate *cycleUpdatedAt = [cycleCreated dateByAddingTimeInterval:1.0];
                MeasurementRecord *cycleUpdated = Record(
                    cycleID, cycleContext, 10.0, 11.0, 32.0, 33.0,
                    cycleCreated, cycleUpdatedAt);
                Check([cycleStore saveMeasurement:cycleUpdated error:&cycleError],
                      @"lifecycle update must commit");
                Check(RecordCount(cycleDatabase) == 1,
                      @"lifecycle update must not create a partial or duplicate row");
                MeasurementRecord *cycleRestored =
                    [cycleStore latestMeasurementForImageContext:cycleContext
                                                            error:&cycleError];
                Check([cycleRestored.measurementID isEqual:cycleID] &&
                      fabs(cycleRestored.endpointBX - cycleUpdated.endpointBX) < 0.000001,
                      @"lifecycle restore must return the committed update");

                cycleStore = nil;
                Check(ExclusiveTransactionPasses(cycleDatabase),
                      @"lifecycle close must release the database lock");

                SQLiteMeasurementStore *cycleReopened = [[SQLiteMeasurementStore alloc]
                    initWithDatabaseURL:cycleDatabase error:&cycleError];
                MeasurementRecord *reopenedRecord =
                    [cycleReopened latestMeasurementForImageContext:cycleContext
                                                               error:&cycleError];
                Check(cycleReopened != nil &&
                      [reopenedRecord.measurementID isEqual:cycleID],
                      @"lifecycle reopen must retain the exact committed record");
                Check(IntegrityPasses(cycleDatabase),
                      @"lifecycle database integrity must pass");
                cycleReopened = nil;
                Check(ExclusiveTransactionPasses(cycleDatabase),
                      @"lifecycle reopened close must release the database lock");
            }
        }

        [NSFileManager.defaultManager removeItemAtURL:temporaryRoot error:NULL];
        if (Failures == 0) {
            printf("PASS: P1-11 transactional persistence (%lu assertions)\n",
                   (unsigned long)Assertions);
            return 0;
        }
        fprintf(stderr, "FAIL: P1-11 transactional persistence (%lu of %lu)\n",
                (unsigned long)Failures, (unsigned long)Assertions);
        return 1;
    }
}
