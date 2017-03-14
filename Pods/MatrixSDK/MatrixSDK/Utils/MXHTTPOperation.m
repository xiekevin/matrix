/*
 Copyright 2015 OpenMarket Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXHTTPOperation.h"


#pragma mark - Constants definitions

/**
 The default max attempts.
 */
#define MXHTTPOPERATION_DEFAULT_MAX_RETRIES 3

/**
 The default max time a request can be retried.
 */
#define MXHTTPOPERATION_DEFAULT_MAX_TIME_MS 180000


@interface MXHTTPOperation ()
{
    NSDate *creationDate;
}
@end


@implementation MXHTTPOperation

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        creationDate = [NSDate date];
        _numberOfTries = 0;
        _maxNumberOfTries = MXHTTPOPERATION_DEFAULT_MAX_RETRIES;
        _maxRetriesTime = MXHTTPOPERATION_DEFAULT_MAX_TIME_MS;
    }
    return self;
}

- (void)cancel
{
    // Prevent further retry on this operation
    _maxNumberOfTries = 0;
    _maxRetriesTime = 0;

    [_operation cancel];
}

- (NSUInteger)age
{
    return [[NSDate date] timeIntervalSinceDate:creationDate] * 1000;
}

- (void)mutateTo:(MXHTTPOperation *)operation
{
    // Apply all data from the other MXHTTPOperation
    _operation = operation.operation;
    creationDate = operation->creationDate;
    _numberOfTries = operation.numberOfTries;
    _maxNumberOfTries = operation.maxRetriesTime;
    _maxRetriesTime = operation.maxRetriesTime;
}

@end
